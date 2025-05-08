// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/AbstractYieldStrategy.sol";
import "../src/oracles/AbstractCustomOracle.sol";
import "../src/utils/Constants.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";

contract MockWrapperERC20 is ERC20 {
    ERC20 public token;
    uint256 public tokenPrecision;

    constructor(ERC20 _token) ERC20("MockWrapperERC20", "MWE") {
        token = _token;
        tokenPrecision = 10 ** token.decimals();
        _mint(msg.sender, 1000000 * 10e18);
    }

    function deposit(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 1e18 / tokenPrecision);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        token.transfer(msg.sender, amount * tokenPrecision / 1e18);
    }
}

contract MockOracle is AbstractCustomOracle {

    int256 public price;

    constructor(int256 _price) AbstractCustomOracle("MockOracle", address(0)) { price = _price; }

    function setPrice(int256 _price) public {
        price = _price;
    }

    function _calculateBaseToQuote() internal view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (0, price, block.timestamp, block.timestamp, 0);
    }
}

contract MockYieldStrategy is AbstractYieldStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv
    ) AbstractYieldStrategy(_asset, _yieldToken, _feeRate, _irm, _lltv, ERC20(_yieldToken).decimals()) { }

    function _mintYieldTokens(uint256 assets, address /* receiver */, bytes memory /* depositData */) internal override {
        ERC20(asset).approve(address(yieldToken), type(uint256).max);
        MockWrapperERC20(yieldToken).deposit(assets);
    }

    function _redeemShares(uint256 sharesToRedeem, address /* sharesOwner */, bytes memory /* redeemData */) internal override returns (bool wasEscrowed) {
        uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
        MockWrapperERC20(yieldToken).withdraw(yieldTokensBurned);
        wasEscrowed = false;
    }
}

contract TestMorphoYieldStrategy is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    ERC20 public w;
    MockOracle public o;
    IYieldStrategy public y;
    ERC20 public feeToken;
    ERC20 public asset;
    uint256 public defaultDeposit;
    uint256 public defaultBorrow;
    uint256 public maxEntryValuationSlippage = 0.0010e18;
    uint256 public maxExitValuationSlippage = 0.0010e18;

    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant IRM = address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);
    address public addressRegistry;

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal virtual returns (bytes memory redeemData) {
        return "";
    }

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal virtual returns (bytes memory depositData) {
        return "";
    }

    function deployYieldStrategy() internal virtual {
        w = new MockWrapperERC20(ERC20(address(USDC)));
        o = new MockOracle(1e18);
        y = new MockYieldStrategy(
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            IRM,
            0.915e18 // 91.5% LTV
        );
        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }

    function setMaxOracleFreshness() internal {
        vm.prank(owner);
        TRADING_MODULE.setMaxOracleFreshness(type(uint32).max);
    }

    function postDeploySetup() internal virtual { }

    function deployAddressRegistry() public virtual {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        addressRegistry = address(new AddressRegistry(owner, owner, owner));
    }

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        deployAddressRegistry();
        setMaxOracleFreshness();

        deployYieldStrategy();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(y),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol")),
            addressRegistry
        );
        y = IYieldStrategy(address(proxy));

        asset = ERC20(y.asset());
        if (address(feeToken) == address(0)) feeToken = w;

        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(address(w), AggregatorV2V3Interface(address(o)));

        postDeploySetup();

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(msg.sender, 100_000e6);
        USDC.transfer(owner, 15_000_000e6);
        vm.stopPrank();

        // Deal WETH
        deal(address(WETH), owner, 1_500_000e18);
        vm.prank(owner);
        WETH.transfer(msg.sender, 250_000e18);

        vm.startPrank(owner);
        asset.approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(y.marketParams(), 1_000_000 * 10 ** asset.decimals(), 0, owner, "");
        vm.stopPrank();
    }

    function _enterPosition(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        if (!MORPHO.isAuthorized(user, address(y))) MORPHO.setAuthorization(address(y), true);
        asset.approve(address(y), depositAmount);
        y.enterPosition(user, depositAmount, borrowAmount, getDepositData(user, depositAmount + borrowAmount));
        vm.stopPrank();
    }

    function checkInvariants(address[] memory users) internal virtual {
        // Collect fees to ensure that shares are minted
        vm.prank(owner);
        y.collectFees();

        uint256 totalSupply = y.totalSupply();
        uint256 computedTotalSupply = y.balanceOf(owner);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            assertEq(w.balanceOf(user), 0, "User has no wrapped tokens");
            assertGe(w.balanceOf(address(y)), y.convertSharesToYieldToken(y.totalSupply()),
                "Yield token balance matches total supply"
            );
            assertEq(y.balanceOf(address(MORPHO)), y.totalSupply() - y.balanceOf(owner),
                "Morpho has all collateral shares"
            );
            assertEq(y.balanceOf(user), 0, "User has no collateral shares");
            computedTotalSupply += y.balanceOfShares(user);
        }

        assertEq(computedTotalSupply, totalSupply, "Total supply is correct");
    }

    function test_enterPosition() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0);
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply());
        assertEq(y.balanceOf(msg.sender), 0);
        assertGt(y.balanceOfShares(msg.sender), 0);
        assertEq(w.balanceOf(address(y)), y.convertSharesToYieldToken(y.totalSupply()));
        assertEq(y.convertSharesToYieldToken(y.balanceOfShares(msg.sender)), w.balanceOf(address(y)));
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)));
        assertApproxEqRel(defaultDeposit + defaultBorrow, y.convertToAssets(y.balanceOfShares(msg.sender)), maxEntryValuationSlippage);
    }

    function test_enterPosition_zeroBorrow() public { 
        _enterPosition(msg.sender, defaultDeposit, 0);

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0);
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply());
        assertEq(y.balanceOf(msg.sender), 0);
        assertGt(y.balanceOfShares(msg.sender), 0);
        assertEq(w.balanceOf(address(y)), y.convertSharesToYieldToken(y.totalSupply()));
        assertEq(y.convertSharesToYieldToken(y.balanceOfShares(msg.sender)), w.balanceOf(address(y)));
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)));
        assertApproxEqRel(defaultDeposit, y.convertToAssets(y.balanceOfShares(msg.sender)), maxEntryValuationSlippage);
    }

    function test_exitPosition_partialExit() public {
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);
        uint256 initialBalance = y.balanceOfShares(msg.sender);

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        uint256 netWorthBefore = y.convertToAssets(y.balanceOfShares(msg.sender)) - defaultBorrow;
        uint256 sharesToExit = y.balanceOfShares(msg.sender) / 10;
        uint256 profitsWithdrawn = y.exitPosition(
            msg.sender, msg.sender, sharesToExit, defaultBorrow / 10, getRedeemData(msg.sender, sharesToExit)
        );
        uint256 netWorthAfter = y.convertToAssets(y.balanceOfShares(msg.sender)) - (defaultBorrow - defaultBorrow / 10);
        vm.stopPrank();

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0, "Account has no wrapped tokens");
        assertApproxEqRel(y.convertYieldTokenToShares(w.balanceOf(address(y)) - y.feesAccrued()), y.totalSupply(), 1, "Yield token is 1-1 with collateral shares");
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply(), "Morpho has all collateral shares");
        assertEq(y.balanceOf(msg.sender), 0, "Account has no collateral shares");
        assertEq(y.balanceOfShares(msg.sender), initialBalance - sharesToExit, "Account has collateral shares");
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)), "Account has collateral shares on MORPHO");

        assertApproxEqRel(netWorthBefore - netWorthAfter, profitsWithdrawn, maxExitValuationSlippage);
    }

    function test_exitPosition_fullExit() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        uint256 netWorthBefore = y.convertToAssets(y.balanceOfShares(msg.sender)) - defaultBorrow;
        uint256 profitsWithdrawn = y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender),
            type(uint256).max,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender))
        );
        vm.stopPrank();

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0, "Account has no wrapped tokens");
        assertEq(y.convertYieldTokenToShares(w.balanceOf(address(y)) - y.feesAccrued()), y.totalSupply(), "Yield token is 1-1 with collateral shares");
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply(), "Morpho has all collateral shares");
        assertEq(y.balanceOf(msg.sender), 0, "Account has no collateral shares");
        assertEq(y.balanceOfShares(msg.sender), 0, "Account has collateral shares");
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)), "Account has collateral shares on MORPHO");
        assertApproxEqRel(netWorthBefore, profitsWithdrawn, maxExitValuationSlippage);
    }

    function test_RevertsIf_MorphoWithdrawCollateral() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        MarketParams memory marketParams = y.marketParams();
        // NOTE: this is the morpho revert message
        vm.expectRevert("transfer reverted");
        MORPHO.withdrawCollateral(marketParams, 1, msg.sender, msg.sender);
    }

    function test_exitPosition_revertsIf_BeforeCooldownPeriod() public { 
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(CannotExitPositionWithinCooldownPeriod.selector));
        y.exitPosition(msg.sender, msg.sender, 100_000e6, 100_000e6, bytes(""));
        vm.stopPrank();
    }

    // function test_pause_unpause() public {
    //     // Initially not paused
    //     assertEq(y.isPaused(), false);

    //     // Only owner can pause
    //     vm.prank(msg.sender);
    //     vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
    //     y.pause();

    //     vm.prank(owner);
    //     y.pause();
    //     assertEq(y.isPaused(), true);

    //     // Cannot perform operations while paused
    //     vm.prank(msg.sender);
    //     vm.expectRevert(abi.encodeWithSelector(Paused.selector));
    //     y.enterPosition(msg.sender, 100_000e6, 100_000e6, getDepositData(msg.sender, 100_000e6));

    //     // Only owner can unpause
    //     vm.prank(msg.sender);
    //     vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
    //     y.unpause();

    //     vm.prank(owner);
    //     y.unpause();
    //     assertEq(y.isPaused(), false);

    //     // Can perform operations after unpause
    //     _enterPosition(msg.sender, 100_000e6, 100_000e6);
    // }

    function test_setApproval() public {
        address operator = address(0x123);
        
        // Initially not approved
        assertEq(y.isApproved(msg.sender, operator), false);

        // Can set approval
        vm.prank(msg.sender);
        y.setApproval(operator, true);
        assertEq(y.isApproved(msg.sender, operator), true);

        // Can revoke approval
        vm.prank(msg.sender);
        y.setApproval(operator, false);
        assertEq(y.isApproved(msg.sender, operator), false);

        // Test that approvals work for operations
        vm.prank(msg.sender);
        y.setApproval(operator, true);
        
        // Operator can perform operations on behalf of user
        vm.prank(owner);
        asset.transfer(operator, defaultDeposit);

        vm.prank(msg.sender);
        MORPHO.setAuthorization(address(y), true);

        vm.startPrank(operator);
        asset.approve(address(y), defaultDeposit);
        y.enterPosition(msg.sender, defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit + defaultBorrow));
        vm.stopPrank();

        // Revoke approval
        vm.prank(msg.sender);
        y.setApproval(operator, false);

        // Operator can no longer perform operations
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, operator, msg.sender));
        y.enterPosition(msg.sender, 100_000e6, 100_000e6, getDepositData(msg.sender, 100_000e6));
        vm.stopPrank();
    }

    function test_setApproval_self() public {
        // Cannot approve self
        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, msg.sender));
        y.setApproval(msg.sender, true);
        vm.stopPrank();
    }

    function test_collectFees() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 totalSupply = y.totalSupply();
        setMaxOracleFreshness();

        uint256 yieldTokensPerShare0 = y.convertSharesToYieldToken(1e18);
        uint256 expectedFees = y.convertSharesToYieldToken(totalSupply) * 0.001000500166e18 / 1e18;
        vm.warp(block.timestamp + 365 days);
        uint256 yieldTokensPerShare1 = y.convertSharesToYieldToken(1e18);
        assertLt(yieldTokensPerShare1, yieldTokensPerShare0);

        assertApproxEqRel(y.feesAccrued(), expectedFees, 1e12, "Fees accrued should be equal to expected fees");

        vm.prank(owner);
        y.collectFees();
        uint256 yieldTokensPerShare2 = y.convertSharesToYieldToken(1e18);

        assertApproxEqAbs(yieldTokensPerShare1, yieldTokensPerShare2, 1, "Yield tokens per share should be equal");
        assertEq(y.feesAccrued(), 0, "Fees accrued should be 0");
        assertApproxEqRel(feeToken.balanceOf(owner), expectedFees, 1e12, "Fees should be equal to expected fees");
    }

    function test_share_valuation() public {
        address user = msg.sender;
        _enterPosition(user, defaultDeposit, defaultBorrow);

        uint256 shares = y.balanceOfShares(user);
        uint256 assets = y.convertToAssets(shares);
        uint256 yieldTokens = y.convertSharesToYieldToken(shares);

        assertEq(yieldTokens, w.balanceOf(address(y)), "yield token balance should be equal to yield tokens");
        assertEq(shares, y.convertYieldTokenToShares(yieldTokens), "convertYieldTokenToShares should equal shares");
        assertApproxEqRel(shares, y.convertToShares(assets), 0.0001e18, "convertToShares(convertToAssets(balanceOfShares)) should be equal to balanceOfShares");
    }

    function test_liquidate() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        int256 originalPrice = o.latestAnswer();
        address liquidator = makeAddr("liquidator");
        
        vm.prank(owner);
        asset.transfer(liquidator, defaultDeposit + defaultBorrow);

        o.setPrice(originalPrice * 0.90e18 / 1e18);

        vm.startPrank(liquidator);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(liquidator);
        uint256 sharesToLiquidator = y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        uint256 assetAfter = asset.balanceOf(liquidator);
        uint256 netAsset = assetBefore - assetAfter;

        assertEq(y.balanceOfShares(msg.sender), balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(liquidator), sharesToLiquidator);

        uint256 assets = y.redeem(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        assertGt(assets, netAsset);

        // Set the price back for the valuation assertion
        o.setPrice(originalPrice);
        assertApproxEqRel(assets, y.convertToAssets(sharesToLiquidator), maxExitValuationSlippage);
        vm.stopPrank();
    }

    function test_liquidate_RevertsIf_InsufficientAssetsForRepayment() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        address liquidator = makeAddr("liquidator");

        o.setPrice(o.latestAnswer() * 0.95e18 / 1e18);

        vm.startPrank(liquidator);
        asset.approve(address(y), type(uint256).max);
        vm.expectRevert();
        y.liquidate(msg.sender, 0, defaultBorrow, bytes(""));
        vm.stopPrank();
    }

    function test_liquidate_RevertsIf_CalledOnMorpho() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        o.setPrice(0.95e18);

        vm.startPrank(owner);
        USDC.approve(address(y), 90_000e6);
        MarketParams memory marketParams = y.marketParams();
        vm.expectRevert("transfer reverted");
        MORPHO.liquidate(marketParams, msg.sender, 0, 90_000e6, bytes(""));
        vm.stopPrank();
    }

    function test_RevertIf_callbacksCalledByNonMorpho() public {
        vm.startPrank(msg.sender);
        vm.expectRevert();
        y.onMorphoFlashLoan(10_000e6, bytes(""));

        vm.expectRevert();
        y.onMorphoLiquidate(10_000e6, bytes("")); 
        vm.stopPrank();
    }

    function test_multiple_entries_exits(uint256[10] memory userActions) public {
        address[] memory users = new address[](3);
        users[0] = makeAddr("user1");
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");

        vm.startPrank(owner);
        asset.transfer(users[0], defaultDeposit * 2);
        asset.transfer(users[1], defaultDeposit * 2);
        asset.transfer(users[2], defaultDeposit * 2);
        vm.stopPrank();
        uint256 borrowAmount = defaultBorrow / 2;

        for (uint256 i = 0; i < userActions.length; i++) {
            uint256 userId = userActions[i] % 3;
            address user = users[userId];

            if (y.balanceOfShares(user) == 0) {
                _enterPosition(user, defaultDeposit, borrowAmount);
            } else {
                vm.warp(block.timestamp + 6 minutes);
                bool isPartial = userActions[i] % 7 == 0;
                vm.startPrank(user);
                if (isPartial) {
                    uint256 amountToRepay = borrowAmount / 10;
                    uint256 sharesToExit = y.convertToShares(amountToRepay) * 105 / 100;
                    y.exitPosition(
                        user, user, sharesToExit, amountToRepay, getRedeemData(user, sharesToExit)
                    );
                } else {
                    y.exitPosition(user, user, y.balanceOfShares(user), type(uint256).max, getRedeemData(user, y.balanceOfShares(user)));
                }
                vm.stopPrank();
            }

            checkInvariants(users);
        }
    }

    function test_liquidate_RevertsIf_LiquidatorHasCollateralBalance() public {
        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);

        vm.startPrank(owner);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        vm.expectRevert();
        y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        vm.stopPrank();
    }

}