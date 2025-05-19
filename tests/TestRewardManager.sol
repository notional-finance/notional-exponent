// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/interfaces/IRewardManager.sol";
import {AbstractRewardManager, RewardPoolStorage} from "../src/rewards/AbstractRewardManager.sol";
import {RewardManagerMixin} from "../src/rewards/RewardManagerMixin.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";

contract TestRewardManager is TestMorphoYieldStrategy {
    IRewardManager rm;
    ERC20 rewardToken;
    ERC20 emissionsToken;

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        w = new MockRewardPool(address(USDC));
        o = new MockOracle(1e18);
        y = new MockRewardVault(
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            address(rmImpl)
        );
    }

    function postDeploySetup() internal override {
        // We use the delegate call here.
        rm = IRewardManager(address(y));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
        rewardToken = MockRewardPool(address(w)).rewardToken();

        // Set the initial reward pool
        vm.startPrank(owner);
        emissionsToken = new MockERC20("MockEmissionsToken", "MET");
        emissionsToken.transfer(address(rm), 100_0000e18);
        rm.migrateRewardPool(address(USDC), RewardPoolStorage({
            rewardPool: address(w),
            forceClaimAfter: 0,
            lastClaimTimestamp: 0
        }));
        rm.updateRewardToken(0, address(rewardToken), 0, 0);
        vm.stopPrank();
    }

    function test_migrateRewardPool() public {
        vm.skip(true);
        // No tokens in the vault at this point
        assertEq(y.totalSupply(), 0);

        vm.startPrank(owner);
        rm.migrateRewardPool(address(USDC), RewardPoolStorage({
            rewardPool: address(w),
            forceClaimAfter: 0,
            lastClaimTimestamp: 0
        }));
        vm.stopPrank();

        (VaultRewardState[] memory rewardStates, RewardPoolStorage memory rewardPool) = rm.getRewardSettings();
        assertEq(rewardStates.length, 0);
        assertEq(rewardPool.rewardPool, address(w));
        assertEq(rewardPool.forceClaimAfter, 0);
        assertEq(rewardPool.lastClaimTimestamp, block.timestamp);
    }

    function test_callUpdateRewardToken_RevertIf_NotRewardManager() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        rm.updateRewardToken(0, address(rewardToken), 0, 0);
    }

    function test_callUpdateAccountRewards_RevertIf_NotVault() public {
        vm.expectRevert();
        rm.updateAccountRewards(msg.sender, 0, 0, 0, true);
    }

    function test_enterPosition_withRewards(bool hasEmissions, bool hasRewards) public {
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        // Check balance of reward token
        assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        rm.claimRewardTokens();

        // Still no reward debt
        assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");

        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;

        vm.prank(msg.sender);
        uint256[] memory rewards = lendingRouter.claimRewards(address(y));

        assertApproxEqRel(rewards[0], expectedRewards, 0.0001e18, "Rewards are incorrect");
        if (hasEmissions) assertEq(rewards[1], 1e18, "Emissions tokens are incorrect");

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(rewardToken), msg.sender), expectedRewards, 0.0001e18, "Reward debt is updated");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");
        }

        if (hasEmissions) {
            assertEq(emissionsToken.balanceOf(msg.sender), 1e18, "Emissions tokens are claimed");
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18, "Emissions debt is updated");
        }

        vm.prank(msg.sender);
        rewards = lendingRouter.claimRewards(address(y));
        assertEq(rewards[0], 0, "Rewards are empty");
        if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are empty");

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
            assertApproxEqRel(rm.getRewardDebt(address(rewardToken), msg.sender), expectedRewards, 0.0001e18, "Reward debt is updated");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0);
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);
        }

        if (hasEmissions) {
            assertEq(emissionsToken.balanceOf(msg.sender), 1e18);
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18);
        }

        _enterPosition(msg.sender, defaultDeposit, 0);
        uint256 sharesAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewardsAfter = hasRewards ? y.convertSharesToYieldToken(sharesAfter) : 0;
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewardsAfter, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }
        // No additional emissions tokens are claimed
        if (hasEmissions) assertEq(emissionsToken.balanceOf(msg.sender), 1e18, "Emissions tokens are claimed");
    }

    function test_exitPosition_withRewards(bool isFullExit, bool hasRewards, bool hasEmissions) public {
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);

        vm.warp(block.timestamp + 7 days);

        // Rewards are 1-1 with yield tokens
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;
        uint256 emissionsForUser = 7e18 * sharesBefore / y.totalSupply();
        vm.startPrank(msg.sender);
        if (isFullExit) {
            lendingRouter.exitPosition(
                msg.sender,
                address(y),
                msg.sender,
                sharesBefore,
                type(uint256).max,
                getRedeemData(msg.sender, sharesBefore)
            );
        } else {
            // Partial exit
            lendingRouter.exitPosition(
                msg.sender,
                address(y),
                msg.sender,
                sharesBefore / 10,
                defaultBorrow / 10,
                getRedeemData(msg.sender, sharesBefore / 10)
            );
        }
        vm.stopPrank();

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Emissions tokens are claimed");
        }

        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 0, "Emissions debt is updated");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is updated");
        }

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        uint256 sharesAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 expectedRewardsAfter = hasRewards ? y.convertSharesToYieldToken(sharesAfter) : 0;

        rm.claimRewardTokens();

        vm.prank(msg.sender);
        uint256[] memory rewards = lendingRouter.claimRewards(address(y));
        if (isFullExit) {
            assertEq(rewards.length, 0);
        } else {
            assertEq(rewards.length, hasEmissions ? 2 : 1);
            assertApproxEqRel(rewards[0], expectedRewardsAfter, 0.0001e18, "Rewards are correct");
            if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are claimed");
        }

        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewardsAfter, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Emissions tokens are claimed");
        }

        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 0, "Emissions debt is updated");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is updated");
        }

        // Since there were two claims before, the owner should receive 2x the rewards
        // as the balance of shares.
        vm.prank(owner);
        lendingRouter.claimRewards(address(y));
        uint256 sharesAfterOwner = lendingRouter.balanceOfCollateral(owner, address(y));
        uint256 expectedRewardsForOwner = hasRewards ? y.convertSharesToYieldToken(sharesAfterOwner) * 2 : 0;
        if (hasRewards) {
            assertApproxEqRel(rewardToken.balanceOf(owner), expectedRewardsForOwner, 0.0001e18, "Rewards are claimed");
        } else {
            assertEq(rewardToken.balanceOf(owner), 0, "Rewards are empty");
        }

        if (hasEmissions) {
            uint256 emissionsForOwner = 7e18 - emissionsForUser;
            assertApproxEqRel(emissionsToken.balanceOf(owner), emissionsForOwner, 0.0010e18, "Emissions tokens are claimed for owner");
        }
    }

    function test_liquidate_withRewards(bool hasEmissions, bool hasRewards) public {
        int256 originalPrice = o.latestAnswer();
        address liquidator = makeAddr("liquidator");
        if (hasEmissions) {
            vm.prank(owner);
            rm.updateRewardToken(1, address(emissionsToken), 365e18, uint32(block.timestamp + 365 days));
        }

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        _enterPosition(owner, defaultDeposit, 0);

        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        
        vm.prank(owner);
        asset.transfer(liquidator, defaultDeposit + defaultBorrow);

        o.setPrice(originalPrice * 0.90e18 / 1e18);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));

        vm.startPrank(liquidator);
        uint256 sharesBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 emissionsForUser = 1e18 * sharesBefore / y.totalSupply();
        uint256 expectedRewards = hasRewards ? y.convertSharesToYieldToken(sharesBefore) : 0;
        asset.approve(address(lendingRouter), type(uint256).max);
        // This should trigger a claim on rewards
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), sharesBefore, 0);
        vm.stopPrank();

        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards, 0.0001e18, "Liquidated account shares");
        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Liquidated account emissions");
        }

        assertEq(rewardToken.balanceOf(liquidator), 0, "Liquidator account rewards");
        assertEq(emissionsToken.balanceOf(liquidator), 0, "Liquidator account emissions");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.convertSharesToYieldToken(y.totalSupply()));
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        uint256 emissionsForLiquidator = 1e18 * sharesToLiquidator / y.totalSupply();

        // This second parameter is ignored because we get the balanceOf from
        // the contract itself.
        rm.claimAccountRewards(liquidator, type(uint256).max);

        uint256 expectedRewardsForLiquidator = hasRewards ? y.convertSharesToYieldToken(sharesToLiquidator) : 0;
        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(liquidator), expectedRewardsForLiquidator, 0.0001e18, "Liquidator account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(liquidator), emissionsForLiquidator, 0.0010e18, "Liquidator account emissions");

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        uint256 sharesAfterUser = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 emissionsForUserAfter = 1e18 * sharesAfterUser / y.totalSupply();

        if (hasRewards) assertApproxEqRel(rewardToken.balanceOf(msg.sender), expectedRewards + expectedRewards - expectedRewardsForLiquidator, 0.0001e18, "Liquidated account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser + emissionsForUserAfter, 0.0010e18, "Liquidated account emissions");
    }

    function test_withdrawRequest_withRewards() public {
        // TODO: does a withdraw request work with rewards? will the user still receive rewards while
        // they are in the withdraw queue?
        vm.skip(true);
    }

    // TODO: what happens when we roll between lending platforms?
}