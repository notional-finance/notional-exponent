// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "forge-std/src/Test.sol";
import "./GnosisHelper.sol";
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
import { sUSDe } from "../src/interfaces/IEthena.sol";
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
    // Used for withdraw manager only exits
    bool public skipExit = false;

    function deployVault() public virtual returns (address impl);

    function name() internal pure virtual returns (string memory);
    function symbol() internal pure virtual returns (string memory);
    function MORPHO_LLTV() internal view virtual returns (uint256);
    function managers() internal view virtual returns (address[] memory);
    function tradePermissions() internal view virtual returns (bytes[] memory);

    function getDepositData(address user, uint256 amount) internal view virtual returns (bytes memory);
    function getRedeemData(address user, uint256 amount) internal view virtual returns (bytes memory);

    function run() public {
        address impl = deployVault();
        console.log("Vault implementation deployed at", impl);

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

    function postDeploySetup() internal view virtual returns (MethodCall[] memory calls) {
        address[] memory m = managers();
        bytes[] memory t = tradePermissions();
        uint256 callIndex = 0;
        calls = new MethodCall[](m.length + t.length + 1);
        for (uint256 i = 0; i < m.length; i++) {
            calls[callIndex++] = MethodCall({
                to: m[i],
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
            callData: abi.encodeWithSelector(
                MorphoLendingRouter.initializeMarket.selector, proxy, MORPHO_IRM, MORPHO_LLTV()
            )
        });
    }
}

contract EtherFiStaking is DeployVault {
    uint256 public constant FEE_RATE = 0.0015e18;

    constructor() {
        depositAmount = 10e18;
        supplyAmount = 100e18;
        borrowAmount = 90e18;
        proxy = 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae;
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

    function managers() internal pure override returns (address[] memory m) {
        m = new address[](1);
        m[0] = 0x71ba37c7C0eAB9F86De6D8745771c66fD3962F20;
        return m;
    }

    function MORPHO_LLTV() internal pure override returns (uint256) {
        return 0.945e18;
    }

    function deployVault() public override returns (address impl) {
        vm.startBroadcast();
        impl = address(new StakingStrategy(address(WETH), address(weETH), FEE_RATE));
        vm.stopBroadcast();
    }

    function tradePermissions() internal view override returns (bytes[] memory t) {
        t = new bytes[](1);
        t[0] = abi.encodeWithSelector(
            TRADING_MODULE.setTokenPermissions.selector,
            proxy,
            address(weETH),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), // forge-lint: disable-line
                // Exact in single and exact in batch
                tradeTypeFlags: 5
            })
        );
        return t;
    }
}

contract EthenaStaking is DeployVault {
    uint256 public constant FEE_RATE = 0.0025e18;

    constructor() {
        depositAmount = 10_000e6;
        supplyAmount = 100_000e6;
        borrowAmount = 90_000e6;
        skipExit = true;
        proxy = 0xAf14d06A65C91541a5b2db627eCd1c92d7d9C48B;
    }

    function name() internal pure override returns (string memory) {
        return "Notional Staking sUSDe";
    }

    function symbol() internal pure override returns (string memory) {
        return "n-st-sUSDe";
    }

    function MORPHO_LLTV() internal pure override returns (uint256) {
        return 0.915e18;
    }

    function managers() internal pure override returns (address[] memory m) {
        m = new address[](1);
        m[0] = 0x8c7C9a45916550C6fE04CDaA139672A1b5803c9F;
        return m;
    }

    function deployVault() public override returns (address impl) {
        vm.startBroadcast();
        impl = address(new StakingStrategy(address(USDC), address(sUSDe), FEE_RATE));
        vm.stopBroadcast();
    }

    function tradePermissions() internal pure override returns (bytes[] memory t) {
        address[] memory m = managers();
        t = new bytes[](1);
        t[0] = abi.encodeWithSelector(
            TRADING_MODULE.setTokenPermissions.selector,
            m[0],
            address(USDC),
            ITradingModule.TokenPermissions({
                allowSell: true,
                dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), // forge-lint: disable-line
                // Exact in single and exact in batch
                tradeTypeFlags: 5
            })
        );
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
