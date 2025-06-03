// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/interfaces/ITradingModule.sol";

abstract contract TestStakingStrategy is TestMorphoYieldStrategy {

    function test_initiateWithdraw_RevertsIf_NotAuthorized() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        address operator = makeAddr("operator");

        vm.startPrank(operator);
        uint256 shares = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, operator, msg.sender));
        lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, shares)
        );
        vm.stopPrank();

        vm.prank(msg.sender);
        lendingRouter.setApproval(operator, true);

        vm.startPrank(operator);
        lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, shares)
        );
        vm.stopPrank();
    }

    function test_forceWithdraw_RevertsIf_IsCollateralized() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.expectRevert(abi.encodeWithSelector(CannotForceWithdraw.selector, msg.sender));
        lendingRouter.forceWithdraw(msg.sender, address(y), "");
    }
    

    function test_migrate_WithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        MorphoLendingRouter lendingRouter2 = setup_migration_test(msg.sender);


        vm.startPrank(msg.sender);
        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 requestId = lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, sharesBefore)
        );

        vm.warp(block.timestamp + 6 minutes);
        lendingRouter2.migratePosition(msg.sender, address(y), address(lendingRouter));

        // Cannot enter since we now have a withdraw request
        vm.expectRevert(abi.encodeWithSelector(CannotEnterPosition.selector));
        lendingRouter2.enterPosition(
            msg.sender, address(y), defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit)
        );

        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.startPrank(msg.sender);
        vm.warp(block.timestamp + 6 minutes);
        // Now we can withdraw the position from lendingRouter2
        lendingRouter2.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            sharesBefore,
            type(uint256).max,
            getRedeemData(msg.sender, sharesBefore)
        );
        vm.stopPrank();

        // Assert that the withdraw request is cleared
        (WithdrawRequest memory w, SplitWithdrawRequest memory s) = manager.getWithdrawRequest(address(y), msg.sender);
        assertEq(w.requestId, 0);
        assertEq(w.sharesAmount, 0);
        assertEq(w.yieldTokenAmount, 0);
        assertEq(w.hasSplit, false);
        assertEq(s.totalYieldTokenAmount, 0);
        assertEq(s.totalWithdraw, 0);
        assertEq(s.finalized, false);
    }

    function test_enterPosition_RevertsIf_ExistingWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        uint256 shares = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 requestId = lendingRouter.initiateWithdraw(
            msg.sender,
            address(y),
            getWithdrawRequestData(msg.sender, shares)
        );

        asset.approve(address(lendingRouter), defaultDeposit);

        vm.expectRevert(abi.encodeWithSelector(CannotEnterPosition.selector));
        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit));
        vm.stopPrank();
    }

    function test_initiateWithdrawRequest_RevertIf_InsufficientCollateral() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        if (address(withdrawTokenOracle) != address(0)) {
            withdrawTokenOracle.setPrice(withdrawTokenOracle.latestAnswer() * 0.85e18 / 1e18);
        } else {
            o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);
        }

        vm.startPrank(msg.sender);
        uint256 shares = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        bytes memory data = getWithdrawRequestData(msg.sender, shares);
        vm.expectRevert(abi.encodeWithSelector(CannotInitiateWithdraw.selector, msg.sender));
        lendingRouter.initiateWithdraw(msg.sender, address(y), data);
        vm.stopPrank();
    }

    function test_exitPosition_FullWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        bytes memory withdrawRequestData = getWithdrawRequestData(msg.sender, balanceBefore);
        (/* */, uint256 collateralValueBefore, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        lendingRouter.initiateWithdraw(msg.sender, address(y), withdrawRequestData);
        (/* */, uint256 collateralValueAfter, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        if (address(withdrawTokenOracle) != address(0)) {
            // If there is a different oracle for the withdraw token (i.e. for PTs),
            // there will be some slippage as a result of selling the PT
            assertApproxEqRel(collateralValueBefore, collateralValueAfter, maxWithdrawValuationChange, "Price changed during withdraw request");
        } else {
            assertApproxEqAbs(collateralValueBefore, collateralValueAfter, 100, "Price changed during withdraw request");
        }
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            balanceBefore,
            type(uint256).max,
            getRedeemData(msg.sender, balanceBefore)
        );
        vm.stopPrank();
    }

    function test_exitPosition_PartialWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            balanceBefore * 0.10e18 / 1e18,
            0,
            getRedeemData(msg.sender, balanceBefore * 0.10e18 / 1e18)
        );

        uint256 balanceAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        assertEq(balanceAfter, balanceBefore - balanceBefore * 0.10e18 / 1e18);

        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            balanceAfter,
            type(uint256).max,
            getRedeemData(msg.sender, balanceAfter)
        );
        vm.stopPrank();

        uint256 balanceAfterExit = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        assertEq(balanceAfterExit, 0);
    }
    
    function test_withdrawRequest_FeeCollection() public onlyIfWithdrawRequestManager {
        vm.skip(keccak256(abi.encodePacked(y.name())) == keccak256(abi.encodePacked("Pendle PT")));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
        vm.stopPrank();

        // No fees should accrue at this point since all yield tokens are escrowed
        uint256 feesAccruedBefore = y.feesAccrued();
        vm.warp(block.timestamp + 7 days);
        uint256 feesAccruedAfter = y.feesAccrued();
        assertEq(feesAccruedBefore, feesAccruedAfter, "Fees should not have accrued");

        address staker2 = makeAddr("staker2");
        vm.prank(owner);
        asset.transfer(staker2, defaultDeposit);

        _enterPosition(staker2, defaultDeposit, defaultBorrow);
        uint256 balanceBeforeStaker2 = lendingRouter.balanceOfCollateral(staker2, address(y));

        // Fees should accrue now on the new staker's position only
        feesAccruedBefore = y.feesAccrued();
        vm.warp(block.timestamp + 90 days);
        feesAccruedAfter = y.feesAccrued();
        assertApproxEqRel(
            feesAccruedAfter - feesAccruedBefore,
            y.convertSharesToYieldToken(balanceBeforeStaker2) * 0.00025e18 / 1e18,
            0.03e18,
        "Fees should have accrued");
    }

    function test_liquidate_and_withdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);

        // First liquidate the position
        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(owner);
        asset.approve(address(lendingRouter), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(owner);
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        uint256 assetAfter = asset.balanceOf(owner);
        uint256 netAsset = assetBefore - assetAfter;

        uint256 balanceAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        assertEq(balanceAfter, balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(owner), sharesToLiquidator);
        vm.stopPrank();

        // Now initiate a withdraw request
        vm.startPrank(owner);
        y.initiateWithdrawNative(getWithdrawRequestData(owner, sharesToLiquidator));
        vm.stopPrank();

        // Assert that the withdraw request is active
        (WithdrawRequest memory w, SplitWithdrawRequest memory s) = manager.getWithdrawRequest(address(y), owner);
        assertNotEq(w.requestId, 0);
        assertEq(w.sharesAmount, balanceBefore);
        assertGt(w.yieldTokenAmount, 0);

        // Now finalize the withdraw request and redeem
        finalizeWithdrawRequest(owner);

        vm.startPrank(owner);
        y.redeemNative(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        vm.stopPrank();

        // Assert that the owner received a profit after redeeming
        assertGt(asset.balanceOf(owner) - assetAfter, netAsset);
        assertEq(y.balanceOf(owner), 0);

        // Assert that the withdraw request is cleared
        (w, s) = manager.getWithdrawRequest(address(y), owner);
        assertEq(w.requestId, 0);
        assertEq(w.sharesAmount, 0);
        assertEq(w.yieldTokenAmount, 0); 
    }

    function test_liquidate_splitsWithdrawRequest(bool isForceWithdraw) public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        if (!isForceWithdraw) {
            vm.startPrank(msg.sender);
            lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
            vm.stopPrank();
        }

        // If you change the price here you need to change the amount of shares
        // to liquidate or it will revert
        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);
        if (address(withdrawTokenOracle) != address(0)) {
            withdrawTokenOracle.setPrice(withdrawTokenOracle.latestAnswer() * 0.85e18 / 1e18);
        }

        vm.startPrank(owner);
        if (isForceWithdraw) {
            lendingRouter.forceWithdraw(msg.sender, address(y),  getWithdrawRequestData(msg.sender, balanceBefore));
        }

        vm.warp(block.timestamp + 6 minutes);

        asset.approve(address(lendingRouter), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(owner);
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        uint256 assetAfter = asset.balanceOf(owner);
        uint256 netAsset = assetBefore - assetAfter;

        uint256 balanceAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        assertEq(balanceAfter, balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(owner), sharesToLiquidator);
        vm.stopPrank();

        finalizeWithdrawRequest(owner);

        // The owner does receive a split withdraw request
        (WithdrawRequest memory w, SplitWithdrawRequest memory s) = manager.getWithdrawRequest(address(y), owner);
        assertNotEq(w.requestId, 0);
        assertEq(w.sharesAmount, sharesToLiquidator);
        assertGt(w.yieldTokenAmount, 0);
        assertEq(w.hasSplit, true);

        // We have not finalized the split withdraw request yet
        assertGt(s.totalYieldTokenAmount, 0);
        assertEq(s.finalized, false);
        assertEq(s.totalWithdraw, 0);

        vm.startPrank(owner);
        uint256 assets = y.redeemNative(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        assertGt(assets, netAsset);
        vm.stopPrank();

        // Assert that the withdraw request is cleared
        (w, s) = manager.getWithdrawRequest(address(y), owner);
        assertEq(w.sharesAmount, 0);
        assertEq(w.yieldTokenAmount, 0);
        assertEq(w.hasSplit, false);

        // The original withdraw request is still active on the liquidated account
        if (balanceBefore > sharesToLiquidator) {
            (w, s) = manager.getWithdrawRequest(address(y), msg.sender);
            assertNotEq(w.requestId, 0);
            assertEq(w.sharesAmount, balanceBefore - sharesToLiquidator);
            assertGt(w.yieldTokenAmount, 0);
            assertEq(w.hasSplit, true);

            assertGt(s.totalYieldTokenAmount, 0);
            assertGt(s.totalWithdraw, 0);
            assertEq(s.finalized, true);
        }
    }

    function test_liquidate_withdrawRequest_RevertsIf_LiquidatorHasCollateralBalance() public onlyIfWithdrawRequestManager {
        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
        vm.stopPrank();

        if (address(withdrawTokenOracle) != address(0)) {
            withdrawTokenOracle.setPrice(withdrawTokenOracle.latestAnswer() * 0.85e18 / 1e18);
        } else {
            o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);
        }

        vm.startPrank(owner);
        asset.approve(address(lendingRouter), type(uint256).max);
        vm.expectRevert();
        lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        vm.stopPrank();
    }

    function test_withdrawRequestValuation() public onlyIfWithdrawRequestManager {
        address staker = makeAddr("staker");
        vm.prank(owner);
        asset.transfer(staker, defaultDeposit);

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        // The staker exists to generate fees on the position to test the withdraw valuation
        _enterPosition(staker, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        bytes memory withdrawRequestData = getWithdrawRequestData(msg.sender, balanceBefore);

        (/* */, uint256 collateralValueBefore, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        (/* */, uint256 collateralValueBeforeStaker, /* */) = lendingRouter.healthFactor(staker, address(y));
        assertApproxEqRel(collateralValueBefore, collateralValueBeforeStaker, 0.0005e18, "Staker should have same collateral value as msg.sender");

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), withdrawRequestData);
        vm.stopPrank();

        (/* */, uint256 collateralValueAfter, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        if (address(withdrawTokenOracle) != address(0)) {
            // If there is a different oracle for the withdraw token (i.e. for PTs),
            // there will be some slippage as a result of selling the PT
            assertApproxEqRel(collateralValueBefore, collateralValueAfter, maxWithdrawValuationChange, "Withdrawal should not change collateral value");
        } else {
            assertApproxEqAbs(collateralValueBefore, collateralValueAfter, 100, "Withdrawal should not change collateral value");
        }

        vm.warp(block.timestamp + 10 days);
        (/* */, uint256 collateralValueAfterWarp, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        (/* */, uint256 collateralValueAfterWarpStaker, /* */) = lendingRouter.healthFactor(staker, address(y));

        // Collateral value for the withdrawer should not change over time
        assertEq(collateralValueAfter, collateralValueAfterWarp, "Withdrawal should not change collateral value over time");

        // For the staker, the collateral value should have decreased due to fees
        assertGt(collateralValueBeforeStaker, collateralValueAfterWarpStaker, "Staker should have lost value due to fees");

        // Check price after finalize
        finalizeWithdrawRequest(msg.sender);
        manager.finalizeRequestManual(address(y), msg.sender);
        (/* */, uint256 collateralValueAfterFinalize, /* */) = lendingRouter.healthFactor(msg.sender, address(y));

        assertApproxEqRel(collateralValueAfterFinalize, collateralValueAfterWarp, 0.01e18, "Withdrawal should be similar to collateral value after finalize");
        assertGt(collateralValueAfterFinalize, collateralValueAfterWarp, "Withdrawal value should increase after finalize");
    }

    function test_enterPosition_after_Exit_WithdrawRequest() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            balanceBefore,
            type(uint256).max,
            getRedeemData(msg.sender, balanceBefore)
        );
        vm.stopPrank();
        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), 0);

        // Assert that we can re-enter the position after previously exiting a withdraw request
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
    }
}
