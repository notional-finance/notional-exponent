// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "forge-std/src/Test.sol";
import "./GnosisHelper.sol";
import "./DeployWithdrawManager.sol";
import { ProxyHelper } from "./ProxyHelper.sol";
import { AddressRegistry } from "../src/proxy/AddressRegistry.sol";
import { TimelockUpgradeableProxy } from "../src/proxy/TimelockUpgradeableProxy.sol";
import { Initializable } from "../src/proxy/Initializable.sol";
import { ADDRESS_REGISTRY, WETH } from "../src/utils/Constants.sol";
import { MORPHO } from "../src/interfaces/Morpho/IMorpho.sol";
import {
    TRADING_MODULE, ITradingModule, TradeType, DexId, CurveV2SingleData
} from "../src/interfaces/ITradingModule.sol";
import { MorphoLendingRouter } from "../src/routers/MorphoLendingRouter.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV2V3Interface } from "../src/interfaces/AggregatorV2V3Interface.sol";
import { weETH } from "../src/interfaces/IEtherFi.sol";
import { sUSDe, USDe } from "../src/interfaces/IEthena.sol";
import "../src/staking/StakingStrategy.sol";
import { IWithdrawRequestManager, StakingTradeParams } from "../src/interfaces/IWithdrawRequestManager.sol";
import { IYieldStrategy } from "../src/interfaces/IYieldStrategy.sol";
import { RedeemParams } from "../src/staking/AbstractStakingStrategy.sol";

address constant MORPHO_IRM = address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);
MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

abstract contract DeployVault is ProxyHelper, GnosisHelper, Test {
    address public proxy;

    uint256 public depositAmount;
    uint256 public supplyAmount;
    uint256 public borrowAmount;
    uint256 public feeRate;
    uint256 public MORPHO_LLTV;
    // Used for withdraw manager only exits
    bool public skipExit = false;

    function deployVault() public virtual returns (address impl);

    function name() internal view virtual returns (string memory);
    function symbol() internal view virtual returns (string memory);
    function managers() internal view virtual returns (IWithdrawRequestManager[] memory);
    function tradePermissions() internal view virtual returns (bytes[] memory);

    function getDepositData(address user, uint256 amount) internal view virtual returns (bytes memory);
    function getRedeemData(address user, uint256 amount) internal view virtual returns (bytes memory);

    function deployCustomOracle() internal virtual returns (address oracle, address oracleToken) {
        return (address(0), address(0));
    }

    function run() public {
        address impl = deployVault();
        console.log("Vault implementation deployed at", impl);
        require(feeRate > 0, "Fee rate must be greater than 0");

        MethodCall[] memory calls;
        bool isUpgrade = false;
        if (proxy == address(0)) {
            proxy = deployProxy(impl, abi.encode(name(), symbol()));
            console.log("Vault proxy deployed at", address(proxy));

            MethodCall[] memory setup = postDeploySetup();
            calls = new MethodCall[](setup.length + 1);

            for (uint256 i = 0; i < setup.length; i++) {
                calls[i] = setup[i];
            }
            calls[calls.length - 1] = MethodCall({
                to: address(ADDRESS_REGISTRY),
                value: 0,
                callData: abi.encodeWithSelector(AddressRegistry.setWhitelistedVault.selector, proxy, true)
            });
        } else {
            isUpgrade = true;
            console.log("Existing proxy at", proxy);
            calls = new MethodCall[](1);
            calls[0] = MethodCall({
                to: proxy,
                value: 0,
                callData: abi.encodeWithSelector(TimelockUpgradeableProxy.initiateUpgrade.selector, impl)
            });
        }

        vm.startPrank(ADDRESS_REGISTRY.upgradeAdmin());
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success,) = calls[i].to.call(calls[i].callData);
            if (!success) revert("Failed to call");
        }
        if (isUpgrade) {
            vm.warp(block.timestamp + 7 days);
            TimelockUpgradeableProxy(payable(proxy)).executeUpgrade(bytes(""));
            ITradingModule(TRADING_MODULE).setMaxOracleFreshness(type(uint32).max);
        }
        vm.stopPrank();

        test_Enter_Exit_Position();

        generateBatch(string(abi.encodePacked("./script/list-", symbol(), "-vault.json")), calls);
    }

    function test_Enter_Exit_Position() internal virtual {
        address user = makeAddr("user");
        address supplier = makeAddr("supplier");

        IYieldStrategy y = IYieldStrategy(proxy);
        ERC20 asset = ERC20(y.asset());
        deal(address(asset), user, depositAmount);
        deal(address(asset), supplier, supplyAmount);

        vm.startPrank(supplier);
        asset.approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(MORPHO_LENDING_ROUTER.marketParams(address(y)), supplyAmount, 0, supplier, "");
        vm.stopPrank();

        vm.startPrank(user);
        MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
        asset.approve(address(MORPHO_LENDING_ROUTER), depositAmount);
        MORPHO_LENDING_ROUTER.enterPosition(
            user, address(y), depositAmount, borrowAmount, getDepositData(user, depositAmount + borrowAmount)
        );
        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(user, address(y));
        console.log("Enter position: ", depositAmount, borrowAmount);
        console.log("Balance of Collateral: ", balance);

        if (skipExit) return;

        vm.warp(block.timestamp + 5 minutes);

        MORPHO_LENDING_ROUTER.exitPosition(
            user, address(y), user, balance, type(uint256).max, getRedeemData(user, balance)
        );
        console.log("Exited Position: ", asset.balanceOf(user));

        vm.stopPrank();
    }

    function getTokenPermission(
        address sender,
        address token,
        uint8 dexId
    )
        internal
        view
        virtual
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            TRADING_MODULE.setTokenPermissions.selector,
            sender,
            token,
            ITradingModule.TokenPermissions({ allowSell: true, dexFlags: uint32(1 << dexId), tradeTypeFlags: 1 })
        );
    }

    function postDeploySetup() internal virtual returns (MethodCall[] memory calls) {
        IWithdrawRequestManager[] memory m = managers();
        bytes[] memory t = tradePermissions();
        (address oracle, address oracleToken) = deployCustomOracle();

        if (m.length == 0) console.log("No withdraw request managers");
        for (uint256 i = 0; i < m.length; i++) {
            console.log("Withdraw Request Manager for ", ERC20(m[i].YIELD_TOKEN()).symbol(), " at", address(m[i]));
        }

        uint256 callIndex = 0;
        uint256 totalCalls = m.length + t.length + 1;
        if (oracle != address(0)) totalCalls++;
        calls = new MethodCall[](totalCalls);

        if (oracle != address(0)) {
            console.log("Custom oracle: ", AggregatorV2V3Interface(oracle).description(), " deployed at", oracle);
            console.log("Custom oracle token: ", oracleToken);
            console.log("Custom oracle price: ", AggregatorV2V3Interface(oracle).latestAnswer());

            calls[callIndex++] = MethodCall({
                to: address(TRADING_MODULE),
                value: 0,
                callData: abi.encodeWithSelector(TRADING_MODULE.setPriceOracle.selector, oracleToken, oracle)
            });
        }

        for (uint256 i = 0; i < m.length; i++) {
            calls[callIndex++] = MethodCall({
                to: address(m[i]),
                value: 0,
                callData: abi.encodeWithSelector(IWithdrawRequestManager.setApprovedVault.selector, proxy, true)
            });
        }

        for (uint256 i = 0; i < t.length; i++) {
            calls[callIndex++] = MethodCall({ to: address(TRADING_MODULE), value: 0, callData: t[i] });
        }

        calls[callIndex++] = MethodCall({
            to: address(MORPHO_LENDING_ROUTER),
            value: 0,
            callData: abi.encodeWithSelector(MorphoLendingRouter.initializeMarket.selector, proxy, MORPHO_IRM, MORPHO_LLTV)
        });
    }
}

contract EtherFiStaking is DeployVault {
    constructor() {
        depositAmount = 10e18;
        supplyAmount = 100e18;
        borrowAmount = 90e18;
        proxy = 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae;
        MORPHO_LLTV = 0.945e18;
    }

    function getDepositData(address, /* user */ uint256 /* amount */ ) internal pure override returns (bytes memory) {
        return bytes("");
    }

    function getRedeemData(address, /* user */ uint256 /* amount */ ) internal pure override returns (bytes memory) {
        return abi.encode(
            RedeemParams({
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5, fromIndex: 1, toIndex: 0 })
                )
            })
        );
    }

    function name() internal pure override returns (string memory) {
        return "Notional Staking weETH";
    }

    function symbol() internal pure override returns (string memory) {
        return "n-st-weETH";
    }

    function managers() internal view override returns (IWithdrawRequestManager[] memory m) {
        m = new IWithdrawRequestManager[](1);
        m[0] = ADDRESS_REGISTRY.getWithdrawRequestManager(address(weETH));
        return m;
    }

    function deployVault() public override returns (address impl) {
        vm.startBroadcast();
        impl = address(new StakingStrategy(address(WETH), address(weETH), feeRate));
        vm.stopBroadcast();
    }

    function tradePermissions() internal view override returns (bytes[] memory t) {
        t = new bytes[](1);
        t[0] = getTokenPermission(proxy, address(weETH), uint8(DexId.CURVE_V2));
        return t;
    }
}

contract EthenaStaking is DeployVault {
    constructor() {
        depositAmount = 10_000e6;
        supplyAmount = 100_000e6;
        borrowAmount = 90_000e6;
        skipExit = true;
        MORPHO_LLTV = 0.915e18;
        proxy = 0xAf14d06A65C91541a5b2db627eCd1c92d7d9C48B;
    }

    function name() internal pure override returns (string memory) {
        return "Notional Staking sUSDe";
    }

    function symbol() internal pure override returns (string memory) {
        return "n-st-sUSDe";
    }

    function managers() internal view override returns (IWithdrawRequestManager[] memory m) {
        m = new IWithdrawRequestManager[](1);
        m[0] = ADDRESS_REGISTRY.getWithdrawRequestManager(address(sUSDe));
        return m;
    }

    function deployVault() public override returns (address impl) {
        vm.startBroadcast();
        impl = address(new StakingStrategy(address(USDC), address(sUSDe), feeRate));
        vm.stopBroadcast();
    }

    function tradePermissions() internal view override returns (bytes[] memory t) {
        IWithdrawRequestManager[] memory m = managers();
        t = new bytes[](3);
        t[0] = getTokenPermission(proxy, address(USDC), uint8(DexId.CURVE_V2));
        t[1] = getTokenPermission(address(m[0]), address(USDC), uint8(DexId.CURVE_V2));
        // For exiting after withdraw request finalized
        t[2] = getTokenPermission(proxy, address(USDe), uint8(DexId.CURVE_V2));
        return t;
    }

    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        pure
        override
        returns (bytes memory redeemData)
    {
        return bytes("");
    }

    function getDepositData(
        address, /* user */
        uint256 /* assets */
    )
        internal
        pure
        override
        returns (bytes memory depositData)
    {
        return abi.encode(
            StakingTradeParams({
                tradeType: TradeType.EXACT_IN_SINGLE,
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72, fromIndex: 1, toIndex: 0 })
                ),
                stakeData: bytes("")
            })
        );
    }
}
