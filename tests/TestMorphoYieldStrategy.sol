// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestEnvironment.sol";

import "../src/routers/MorphoLendingRouter.sol";
import "../src/AbstractYieldStrategy.sol";
import "../src/oracles/AbstractCustomOracle.sol";
import "../src/utils/Constants.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";

contract TestMorphoYieldStrategy is TestEnvironment {

    function deployYieldStrategy() internal override virtual {
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

    function setupLendingRouter() internal override {
        lendingRouter = new MorphoLendingRouter();

        vm.startPrank(owner);
        ADDRESS_REGISTRY.setLendingRouter(address(lendingRouter));
        MorphoLendingRouter(address(lendingRouter)).initializeMarket(address(y), IRM, 0.915e18);

        asset.approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(
            MorphoLendingRouter(address(lendingRouter)).marketParams(address(y)),
            1_000_000 * 10 ** asset.decimals(), 0, owner, ""
        );
        vm.stopPrank();
    }

    function _enterPosition(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        if (!MORPHO.isAuthorized(user, address(lendingRouter))) MORPHO.setAuthorization(address(lendingRouter), true);
        asset.approve(address(lendingRouter), depositAmount);
        lendingRouter.enterPosition(
            user, address(y), depositAmount, borrowAmount,
            getDepositData(user, depositAmount + borrowAmount)
        );
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
            computedTotalSupply += lendingRouter.balanceOfCollateral(user, address(y));
        }

        assertEq(computedTotalSupply, totalSupply, "Total supply is correct");
    }

    function postEntryAssertions() internal view {
        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0);
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply());
        assertEq(y.balanceOf(msg.sender), 0);
        assertGt(lendingRouter.balanceOfCollateral(msg.sender, address(y)), 0);
        assertEq(w.balanceOf(address(y)), y.convertSharesToYieldToken(y.totalSupply()));
        assertEq(y.convertSharesToYieldToken(lendingRouter.balanceOfCollateral(msg.sender, address(y))), w.balanceOf(address(y)));
        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), y.balanceOf(address(MORPHO)));
    }

    function test_enterPosition() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        postEntryAssertions();
        assertApproxEqRel(
            defaultDeposit + defaultBorrow,
            y.convertToAssets(lendingRouter.balanceOfCollateral(msg.sender, address(y))),
            maxEntryValuationSlippage
        );
    }

    function test_enterPosition_zeroBorrow() public { 
        _enterPosition(msg.sender, defaultDeposit, 0);
        postEntryAssertions();
        assertApproxEqRel(
            defaultDeposit,
            y.convertToAssets(lendingRouter.balanceOfCollateral(msg.sender, address(y))),
            maxEntryValuationSlippage
        );
    }

    function postExitAssertions(uint256 initialBalance, uint256 netWorthBefore, uint256 sharesToExit, uint256 profitsWithdrawn, uint256 netWorthAfter) internal view {
        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0, "Account has no wrapped tokens");
        assertApproxEqRel(y.convertYieldTokenToShares(w.balanceOf(address(y)) - y.feesAccrued()), y.totalSupply(), 1, "Yield token is 1-1 with collateral shares");
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply(), "Morpho has all collateral shares");
        assertEq(y.balanceOf(msg.sender), 0, "Account has no collateral shares");
        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), initialBalance - sharesToExit, "Account has collateral shares");
        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), y.balanceOf(address(MORPHO)), "Account has collateral shares on MORPHO");
        assertApproxEqRel(netWorthBefore - netWorthAfter, profitsWithdrawn, maxExitValuationSlippage);
    }

    function test_exitPosition_partialExit() public {
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);
        uint256 initialBalance = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 netWorthBefore = y.convertToAssets(balanceBefore) - defaultBorrow;
        uint256 sharesToExit = balanceBefore / 10;
        uint256 assetsBefore = asset.balanceOf(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            sharesToExit,
            defaultBorrow / 10,
            getRedeemData(msg.sender, sharesToExit)
        );
        uint256 balanceAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 netWorthAfter = y.convertToAssets(balanceAfter) - (defaultBorrow - defaultBorrow / 10);
        uint256 assetsAfter = asset.balanceOf(msg.sender);
        uint256 profitsWithdrawn = assetsAfter - assetsBefore;
        vm.stopPrank();

        postExitAssertions(initialBalance, netWorthBefore, sharesToExit, profitsWithdrawn, netWorthAfter);
    }

    function test_exitPosition_fullExit() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 initialBalance = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        uint256 netWorthBefore = y.convertToAssets(initialBalance) - defaultBorrow;
        uint256 assetsBefore = asset.balanceOf(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            initialBalance,
            type(uint256).max,
            getRedeemData(msg.sender, initialBalance)
        );
        uint256 assetsAfter = asset.balanceOf(msg.sender);
        uint256 profitsWithdrawn = assetsAfter - assetsBefore;
        vm.stopPrank();

        postExitAssertions(initialBalance, netWorthBefore, initialBalance, profitsWithdrawn, 0);
    }

    function test_RevertsIf_MorphoWithdrawCollateral() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        MarketParams memory marketParams = MorphoLendingRouter(address(lendingRouter)).marketParams(address(y));
        // NOTE: this is the morpho revert message
        vm.expectRevert("transfer reverted");
        MORPHO.withdrawCollateral(marketParams, 1, msg.sender, msg.sender);
    }

    function test_exitPosition_revertsIf_BeforeCooldownPeriod() public { 
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(CannotExitPositionWithinCooldownPeriod.selector));
        lendingRouter.exitPosition(msg.sender, address(y), msg.sender, 100_000e6, 100_000e6, bytes(""));
        vm.stopPrank();
    }

    // // TODO: add tests for various pause/unpause scenarios
    // // function test_pause_unpause() public {
    // //     // Initially not paused
    // //     assertEq(y.isPaused(), false);

    // //     // Only owner can pause
    // //     vm.prank(msg.sender);
    // //     vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
    // //     y.pause();

    // //     vm.prank(owner);
    // //     y.pause();
    // //     assertEq(y.isPaused(), true);

    // //     // Cannot perform operations while paused
    // //     vm.prank(msg.sender);
    // //     vm.expectRevert(abi.encodeWithSelector(Paused.selector));
    // //     y.enterPosition(msg.sender, 100_000e6, 100_000e6, getDepositData(msg.sender, 100_000e6));

    // //     // Only owner can unpause
    // //     vm.prank(msg.sender);
    // //     vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
    // //     y.unpause();

    // //     vm.prank(owner);
    // //     y.unpause();
    // //     assertEq(y.isPaused(), false);

    // //     // Can perform operations after unpause
    // //     _enterPosition(msg.sender, 100_000e6, 100_000e6);
    // // }

    function test_setApproval() public {
        address operator = address(0x123);
        
        // Initially not approved
        assertEq(lendingRouter.isApproved(msg.sender, operator), false);

        // Can set approval
        vm.prank(msg.sender);
        lendingRouter.setApproval(operator, true);
        assertEq(lendingRouter.isApproved(msg.sender, operator), true);

        // Can revoke approval
        vm.prank(msg.sender);
        lendingRouter.setApproval(operator, false);
        assertEq(lendingRouter.isApproved(msg.sender, operator), false);

        // Test that approvals work for operations
        vm.prank(msg.sender);
        lendingRouter.setApproval(operator, true);
        
        // Operator can perform operations on behalf of user
        vm.prank(owner);
        asset.transfer(operator, defaultDeposit);

        vm.prank(msg.sender);
        MORPHO.setAuthorization(address(lendingRouter), true);

        vm.startPrank(operator);
        asset.approve(address(lendingRouter), defaultDeposit);
        lendingRouter.enterPosition(
            msg.sender, address(y), defaultDeposit, defaultBorrow,
            getDepositData(msg.sender, defaultDeposit + defaultBorrow)
        );
        vm.stopPrank();

        // Revoke approval
        vm.prank(msg.sender);
        lendingRouter.setApproval(operator, false);

        // Operator can no longer perform operations
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, operator, msg.sender));
        lendingRouter.enterPosition(
            msg.sender, address(y), 100_000e6, 100_000e6,
            getDepositData(msg.sender, 100_000e6)
        );
        vm.stopPrank();
    }

    function test_setApproval_self() public {
        // Cannot approve self
        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, msg.sender));
        lendingRouter.setApproval(msg.sender, true);
        vm.stopPrank();
    }

    function test_collectFees() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 totalSupply = y.totalSupply();

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

        uint256 shares = lendingRouter.balanceOfCollateral(user, address(y));
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
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        asset.approve(address(lendingRouter), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(liquidator);
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        uint256 assetAfter = asset.balanceOf(liquidator);
        uint256 netAsset = assetBefore - assetAfter;

        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(liquidator), sharesToLiquidator);

        uint256 assets = y.redeemNative(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
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
        // This reverts on an ERC20 transfer balance error which depends on the token implementation
        vm.expectRevert();
        lendingRouter.liquidate(msg.sender, address(y), 0, defaultBorrow);
        vm.stopPrank();
    }

    function test_liquidate_RevertsIf_CalledOnMorpho() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        o.setPrice(0.95e18);

        vm.startPrank(owner);
        USDC.approve(address(y), 90_000e6);
        MarketParams memory marketParams = MorphoLendingRouter(address(lendingRouter)).marketParams(address(y));
        vm.expectRevert("transfer reverted");
        MORPHO.liquidate(marketParams, msg.sender, 0, 90_000e6, bytes(""));
        vm.stopPrank();
    }

    function test_RevertIf_callbacksCalledByNonMorpho() public {
        vm.startPrank(msg.sender);
        vm.expectRevert();
        MorphoLendingRouter(address(lendingRouter)).onMorphoFlashLoan(10_000e6, bytes(""));

        vm.expectRevert();
        MorphoLendingRouter(address(lendingRouter)).onMorphoLiquidate(10_000e6, bytes("")); 

        vm.expectRevert();
        MorphoLendingRouter(address(lendingRouter)).onMorphoRepay(10_000e6, bytes(""));
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

            if (lendingRouter.balanceOfCollateral(user, address(y)) == 0) {
                _enterPosition(user, defaultDeposit, borrowAmount);
            } else {
                vm.warp(block.timestamp + 6 minutes);
                bool isPartial = userActions[i] % 7 == 0;
                uint256 sharesToExit;
                uint256 amountToRepay;
                vm.startPrank(user);
                if (isPartial) {
                    amountToRepay = borrowAmount / 10;
                    sharesToExit = y.convertToShares(amountToRepay) * 105 / 100;
                } else {
                    sharesToExit = lendingRouter.balanceOfCollateral(user, address(y));
                    amountToRepay = type(uint256).max;
                }
                lendingRouter.exitPosition(
                    user, address(y), user, sharesToExit, amountToRepay, getRedeemData(user, sharesToExit)
                );
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
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        asset.approve(address(y), type(uint256).max);
        vm.expectRevert();
        lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        vm.stopPrank();
    }

}