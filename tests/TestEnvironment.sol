// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";

import "./Mocks.sol";
import "../src/interfaces/ILendingRouter.sol";
import "../src/proxy/AddressRegistry.sol";
import "../src/utils/Constants.sol";
import "../src/AbstractYieldStrategy.sol";
import "../src/oracles/AbstractCustomOracle.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "./TestWithdrawRequest.sol";

abstract contract TestEnvironment is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 23_027_757;

    ERC20 public w;
    MockOracle public o;
    IYieldStrategy public y;
    ERC20 public feeToken;
    ERC20 public asset;
    uint256 public defaultDeposit;
    uint256 public defaultBorrow;
    uint256 public maxEntryValuationSlippage = 0.001e18;
    uint256 public maxExitValuationSlippage = 0.0015e18;
    uint256 public maxWithdrawValuationChange = 0.005e18;
    bool public skipFeeCollectionTest = false;
    bool public knownTokenPreventsLiquidation = false;
    bool public noInstantRedemption = false;

    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant IRM = address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);
    address public addressRegistry;
    ILendingRouter public lendingRouter;

    IWithdrawRequestManager public manager;
    TestWithdrawRequest public withdrawRequest;
    MockOracle internal withdrawTokenOracle;

    string public strategyName;
    string public strategySymbol;

    bool public canInspectTransientVariables = false;

    modifier onlyIfWithdrawRequestManager() {
        vm.skip(address(manager) == address(0));
        _;
    }

    function checkTransientsCleared() internal view {
        if (!canInspectTransientVariables) return;

        (address currentAccount, address currentLendingRouter, address allowTransferTo, uint256 allowTransferAmount) =
            MockYieldStrategy(address(y)).transientVariables();
        assertEq(currentAccount, address(0), "Current account should be cleared");
        assertEq(currentLendingRouter, address(0), "Current lending router should be cleared");
        assertEq(allowTransferTo, address(0), "Allow transfer to should be cleared");
        assertEq(allowTransferAmount, 0, "Allow transfer amount should be cleared");
    }

    function setMaxOracleFreshness() internal {
        vm.record();
        TRADING_MODULE.maxOracleFreshnessInSeconds();
        (bytes32[] memory reads,) = vm.accesses(address(TRADING_MODULE));
        vm.store(address(TRADING_MODULE), reads[1], bytes32(uint256(type(uint32).max)));
    }

    function setPriceOracle(address token, address oracle) internal {
        vm.record();
        TRADING_MODULE.priceOracles(token);
        (bytes32[] memory reads,) = vm.accesses(address(TRADING_MODULE));
        bytes32 oracleData =
            bytes32(uint256(uint160(oracle))) | bytes32(uint256(AggregatorV2V3Interface(oracle).decimals())) << 160;
        vm.store(address(TRADING_MODULE), reads[1], oracleData);

        (AggregatorV2V3Interface _o, uint8 rateDecimals) = TRADING_MODULE.priceOracles(token);
        assertEq(address(_o), oracle, "oracle should be set");
        assertEq(rateDecimals, AggregatorV2V3Interface(oracle).decimals(), "rate decimals should be set");
    }

    function setExistingWithdrawRequestManager(address yieldToken) internal {
        manager = IWithdrawRequestManager(ADDRESS_REGISTRY.getWithdrawRequestManager(yieldToken));
    }

    function setupWithdrawRequestManager(address impl) internal virtual {
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(impl), abi.encodeWithSelector(Initializable.initialize.selector, bytes(""))
        );
        manager = IWithdrawRequestManager(address(proxy));

        if (address(ADDRESS_REGISTRY.getWithdrawRequestManager(manager.YIELD_TOKEN())) == address(0)) {
            vm.prank(ADDRESS_REGISTRY.upgradeAdmin());
            ADDRESS_REGISTRY.setWithdrawRequestManager(address(manager));
        } else {
            setExistingWithdrawRequestManager(manager.YIELD_TOKEN());
        }
    }

    function overrideForkBlock() internal virtual { }

    function setUp() public virtual {
        overrideForkBlock();
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        strategyName = "name";
        strategySymbol = "symbol";
        setMaxOracleFreshness();
        if (address(ADDRESS_REGISTRY).code.length == 0) {
            address impl = address(new AddressRegistry());
            deployCodeTo("TimelockUpgradeableProxy.sol", abi.encode(impl, bytes("")), address(ADDRESS_REGISTRY));
            ADDRESS_REGISTRY.initialize(abi.encode(owner, owner, owner));
        } else if (block.number < 23_398_148) {
            address impl = address(new AddressRegistry());
            vm.startPrank(owner);
            TimelockUpgradeableProxy(payable(address(ADDRESS_REGISTRY))).initiateUpgrade(impl);
            vm.warp(block.timestamp + 7 days);
            TimelockUpgradeableProxy(payable(address(ADDRESS_REGISTRY))).executeUpgrade(bytes(""));
            vm.stopPrank();
        }

        deployYieldStrategy();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(y),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(strategyName, strategySymbol))
        );
        y = IYieldStrategy(address(proxy));

        vm.prank(ADDRESS_REGISTRY.upgradeAdmin());
        ADDRESS_REGISTRY.setWhitelistedVault(address(y), true);

        asset = ERC20(y.asset());
        // Set default fee token, this changes for Convex staked tokens
        if (address(feeToken) == address(0)) feeToken = w;

        setPriceOracle(address(w), address(o));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(msg.sender, 100_000e6);
        USDC.transfer(owner, 15_000_000e6);
        vm.stopPrank();

        // Deal asset token
        deal(address(asset), owner, 2_000_000 * (10 ** TokenUtils.getDecimals(address(asset))));
        vm.startPrank(owner);
        ERC20(asset).transfer(msg.sender, 250_000 * (10 ** TokenUtils.getDecimals(address(asset))));
        vm.stopPrank();

        lendingRouter = setupLendingRouter(0.915e18);
        if (address(manager) != address(0)) {
            vm.prank(owner);
            manager.setApprovedVault(address(y), true);
        }

        postDeploySetup();
    }

    /**
     * Virtual Test Functions **
     */
    function finalizeWithdrawRequest(address user) internal virtual {
        (
            WithdrawRequest memory wr, /* */
        ) = manager.getWithdrawRequest(address(y), user);
        withdrawRequest.finalizeWithdrawRequest(wr.requestId);
    }

    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        virtual
        returns (bytes memory redeemData)
    {
        return "";
    }

    function getDepositData(
        address, /* user */
        uint256 /* depositAmount */
    )
        internal
        virtual
        returns (bytes memory depositData)
    {
        return "";
    }

    function getWithdrawRequestData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        virtual
        returns (bytes memory withdrawRequestData)
    {
        return bytes("");
    }

    function deployYieldStrategy() internal virtual;

    function postDeploySetup() internal virtual { }

    function setupLendingRouter(uint256 lltv) internal virtual returns (ILendingRouter);
}
