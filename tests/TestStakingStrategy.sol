// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequest.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/interfaces/ITradingModule.sol";

abstract contract TestStakingStrategy is TestMorphoYieldStrategy {
    IWithdrawRequestManager public manager;
    TestWithdrawRequest public withdrawRequest;
    MockOracle internal withdrawTokenOracle;

    modifier onlyIfWithdrawRequestManager() {
        vm.skip(address(manager) == address(0));
        _;
    }

    function getWithdrawRequestData(
        address /* user */,
        uint256 /* shares */
    ) internal pure virtual returns (bytes memory withdrawRequestData) {
        return bytes("");
    }

    function finalizeWithdrawRequest(address user) internal {
        (WithdrawRequest memory w, /* */) = manager.getWithdrawRequest(address(y), user);
        withdrawRequest.finalizeWithdrawRequest(w.requestId);
    }

    function test_enterPosition_RevertsIf_ExistingWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));

        asset.approve(address(y), defaultDeposit);

        vm.expectRevert();
        y.enterPosition(msg.sender, defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit));
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
        bytes memory data = getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender));
        vm.expectRevert(abi.encodeWithSelector(CannotInitiateWithdraw.selector, msg.sender));
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(data);
        vm.stopPrank();
    }

    function test_exitPosition_FullWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        (/* */, uint256 collateralValueBefore, /* */) = y.healthFactor(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        (/* */, uint256 collateralValueAfter, /* */) = y.healthFactor(msg.sender);
        if (address(withdrawTokenOracle) != address(0)) {
            // If there is a different oracle for the withdraw token (i.e. for PTs),
            // there will be some slippage as a result of selling the PT
            assertApproxEqRel(collateralValueBefore, collateralValueAfter, 0.0050e18, "Price changed during withdraw request");
        } else {
            assertEq(collateralValueBefore, collateralValueAfter, "Price changed during withdraw request");
        }
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender),
            type(uint256).max,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender))
        );
        vm.stopPrank();
    }

    function test_exitPosition_PartialWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);
        setMaxOracleFreshness();

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();
        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender) * 0.10e18 / 1e18,
            0,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender) * 0.10e18 / 1e18)
        );

        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender) * 0.10e18 / 1e18,
            0,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender) * 0.10e18 / 1e18)
        );
        vm.stopPrank();
    }
    
    function test_withdrawRequest_FeeCollection() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        setMaxOracleFreshness();

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
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

        // Fees should accrue now on the new staker's position only
        feesAccruedBefore = y.feesAccrued();
        vm.warp(block.timestamp + 90 days);
        feesAccruedAfter = y.feesAccrued();
        assertApproxEqRel(
            feesAccruedAfter - feesAccruedBefore,
            y.convertSharesToYieldToken(y.balanceOfShares(staker2)) * 0.00025e18 / 1e18,
            0.03e18,
        "Fees should have accrued");
    }

    function test_liquidate_splitsWithdrawRequest() public onlyIfWithdrawRequestManager {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();

        if (address(withdrawTokenOracle) != address(0)) {
            withdrawTokenOracle.setPrice(withdrawTokenOracle.latestAnswer() * 0.85e18 / 1e18);
        } else {
            o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);
        }

        vm.startPrank(owner);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(owner);
        uint256 sharesToLiquidator = y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        uint256 assetAfter = asset.balanceOf(owner);
        uint256 netAsset = assetBefore - assetAfter;

        assertEq(y.balanceOfShares(msg.sender), balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(owner), sharesToLiquidator);
        vm.stopPrank();

        finalizeWithdrawRequest(owner);

        vm.startPrank(owner);
        uint256 assets = y.redeem(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        assertGt(assets, netAsset);
        vm.stopPrank();
    }

    function test_liquidate_RevertsIf_LiquidatorHasCollateralBalance() public onlyIfWithdrawRequestManager {
        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();

        if (address(withdrawTokenOracle) != address(0)) {
            withdrawTokenOracle.setPrice(withdrawTokenOracle.latestAnswer() * 0.85e18 / 1e18);
        } else {
            o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);
        }

        vm.startPrank(owner);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(CannotReceiveSplitWithdrawRequest.selector));
        y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        vm.stopPrank();
    }

    function test_withdrawRequestValuation() public onlyIfWithdrawRequestManager {
        address staker = makeAddr("staker");
        vm.prank(owner);
        asset.transfer(staker, defaultDeposit);

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        // The staker exists to generate fees on the position to test the withdraw valuation
        _enterPosition(staker, defaultDeposit, defaultBorrow);
        setMaxOracleFreshness();

        (/* */, uint256 collateralValueBefore, /* */) = y.healthFactor(msg.sender);
        (/* */, uint256 collateralValueBeforeStaker, /* */) = y.healthFactor(staker);
        assertApproxEqRel(collateralValueBefore, collateralValueBeforeStaker, 0.0005e18, "Staker should have same collateral value as msg.sender");

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(
            getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender))
        );
        vm.stopPrank();
        (/* */, uint256 collateralValueAfter, /* */) = y.healthFactor(msg.sender);
        if (address(withdrawTokenOracle) != address(0)) {
            // If there is a different oracle for the withdraw token (i.e. for PTs),
            // there will be some slippage as a result of selling the PT
            assertApproxEqRel(collateralValueBefore, collateralValueAfter, 0.0050e18, "Withdrawal should not change collateral value");
        } else {
            assertEq(collateralValueBefore, collateralValueAfter, "Withdrawal should not change collateral value");
        }

        vm.warp(block.timestamp + 10 days);
        (/* */, uint256 collateralValueAfterWarp, /* */) = y.healthFactor(msg.sender);
        (/* */, uint256 collateralValueAfterWarpStaker, /* */) = y.healthFactor(staker);

        // Collateral value for the withdrawer should not change over time
        assertEq(collateralValueAfter, collateralValueAfterWarp, "Withdrawal should not change collateral value over time");

        // For the staker, the collateral value should have decreased due to fees
        assertGt(collateralValueBeforeStaker, collateralValueAfterWarpStaker, "Staker should have lost value due to fees");

        // Check price after finalize
        finalizeWithdrawRequest(msg.sender);
        manager.finalizeRequestManual(address(y), msg.sender);
        (/* */, uint256 collateralValueAfterFinalize, /* */) = y.healthFactor(msg.sender);

        assertApproxEqRel(collateralValueAfterFinalize, collateralValueAfterWarp, 0.01e18, "Withdrawal should be similar to collateral value after finalize");
        assertGt(collateralValueAfterFinalize, collateralValueAfterWarp, "Withdrawal value should increase after finalize");
    }

    // function test_multiple_entries_exits_with_withdrawRequest() public {
    //     assertEq(true, false);
    //     // TODO: check that asset valuation is continuous for multiple entries and exits
    // }
}
