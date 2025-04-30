// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/rewards/IRewardManager.sol";
import {AbstractRewardManager, RewardPoolStorage} from "../src/rewards/AbstractRewardManager.sol";
import {RewardManagerMixin} from "../src/rewards/RewardManagerMixin.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000e18);
    }
}

contract MockRewardPool is ERC20 {
    uint256 public rewardAmount;
    ERC20 public depositToken;
    ERC20 public rewardToken;

    constructor(address _depositToken) ERC20("MockRewardPool", "MRP") {
        depositToken = ERC20(_depositToken);
        rewardToken = new MockERC20("MockRewardToken", "MRT");
    }

    function setRewardAmount(uint256 amount) external {
        rewardAmount = amount;
    }

    function getReward(address holder, bool claim) external returns (bool) {
        if (rewardAmount == 0) return true;
        if (claim) rewardToken.transfer(holder, rewardAmount);
        // Clear the reward amount every time it's claimed
        rewardAmount = 0;
        return true;
    }

    function deposit(uint256 /* poolId */, uint256 amount, bool /* stake */) external {
        depositToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 1e18 / 1e6);
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) external {
        if (claim) rewardToken.transfer(address(this), amount);
        _burn(msg.sender, amount);
        depositToken.transfer(msg.sender, amount * 1e6 / 1e18);
    }

    function pid() external pure returns (uint256) {
        return 0;
    }

    function operator() external view returns (address) {
        return address(this);
    }
}


contract MockRewardVault is RewardManagerMixin {
    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager
    ) RewardManagerMixin(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager) {
        ERC20(_asset).approve(address(_yieldToken), type(uint256).max);
    }

    function _mintYieldTokens(uint256 assets, address /* receiver */, bytes memory /* depositData */) internal override {
        MockRewardPool(yieldToken).deposit(0, assets, true);
    }

    function _redeemShares(uint256 sharesToRedeem, address /* sharesOwner */, bytes memory /* redeemData */) internal override returns (uint256 yieldTokensBurned, bool wasEscrowed) {
        yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
        MockRewardPool(yieldToken).withdrawAndUnwrap(yieldTokensBurned, true);
        wasEscrowed = false;
    }
}

contract TestRewardManager is TestMorphoYieldStrategy {
    IRewardManager rm;
    ERC20 rewardToken;
    ERC20 emissionsToken;

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        w = new MockRewardPool(address(USDC));
        o = new MockOracle(1e18);
        y = new MockRewardVault(
            owner,
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            IRM,
            0.915e18, // 91.5% LTV
            address(rmImpl)
        );
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
        vm.expectRevert("Only the reward manager can call this function");
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

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        rm.claimRewardTokens();

        // Still no reward debt
        assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");

        uint256 sharesBefore = y.balanceOfShares(msg.sender);
        uint256[] memory rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards.length, hasEmissions ? 2 : 1, "Rewards length is incorrect");
        assertEq(rewards[0], hasRewards ? sharesBefore : 0, "Rewards are incorrect");
        if (hasEmissions) assertEq(rewards[1], 1e18, "Emissions tokens are incorrect");

        rm.claimAccountRewards(msg.sender);

        if (hasRewards) {
            assertEq(rewardToken.balanceOf(msg.sender), sharesBefore, "Rewards are claimed");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), sharesBefore, "Reward debt is updated");
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0, "Rewards are empty");
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0, "Reward debt is empty");
        }

        if (hasEmissions) {
            assertEq(emissionsToken.balanceOf(msg.sender), 1e18, "Emissions tokens are claimed");
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18, "Emissions debt is updated");
        }

        rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards[0], 0, "Rewards are empty");
        if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are empty");

        rm.claimAccountRewards(msg.sender);

        if (hasRewards) {
            assertEq(rewardToken.balanceOf(msg.sender), sharesBefore);
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), sharesBefore);
        } else {
            assertEq(rewardToken.balanceOf(msg.sender), 0);
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);
        }

        if (hasEmissions) {
            assertEq(emissionsToken.balanceOf(msg.sender), 1e18);
            assertEq(rm.getRewardDebt(address(emissionsToken), msg.sender), 1e18);
        }

        _enterPosition(msg.sender, defaultDeposit, 0);
        uint256 sharesAfter = y.balanceOfShares(msg.sender);

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        rm.claimAccountRewards(msg.sender);
        if (hasRewards) {
            assertEq(rewardToken.balanceOf(msg.sender), sharesBefore + sharesAfter, "Rewards are claimed");
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
        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());

        uint256 sharesBefore = y.balanceOfShares(msg.sender);
        uint256 emissionsForUser = 7e18 * sharesBefore / y.totalSupply();
        vm.startPrank(msg.sender);
        if (isFullExit) {
            y.exitPosition(
                msg.sender,
                msg.sender,
                y.balanceOfShares(msg.sender),
                type(uint256).max,
                getRedeemData(msg.sender, y.balanceOfShares(msg.sender))
            );
        } else {
            // Partial exit
            y.exitPosition(
                msg.sender,
                msg.sender,
                sharesBefore / 10,
                defaultBorrow / 10,
                getRedeemData(msg.sender, sharesBefore / 10)
            );
        }
        vm.stopPrank();

        if (hasRewards) {
            assertEq(rewardToken.balanceOf(msg.sender), sharesBefore, "Rewards are claimed");
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

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        uint256 sharesAfter = y.balanceOfShares(msg.sender);
        rm.claimRewardTokens();
        uint256[] memory rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards.length, hasEmissions ? 2 : 1);
        assertEq(rewards[0], hasRewards ? sharesAfter : 0);
        if (hasEmissions) assertEq(rewards[1], 0, "Emissions tokens are claimed");

        rm.claimAccountRewards(msg.sender);

        if (hasRewards) {
            assertEq(rewardToken.balanceOf(msg.sender), sharesBefore + sharesAfter, "Rewards are claimed");
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
        rm.claimAccountRewards(owner);
        if (hasRewards) {
            assertEq(rewardToken.balanceOf(owner), y.balanceOfShares(owner) * 2, "Rewards are claimed");
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

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());

        vm.startPrank(liquidator);
        uint256 sharesBefore = y.balanceOfShares(msg.sender);
        uint256 emissionsForUser = 1e18 * sharesBefore / y.totalSupply();
        asset.approve(address(y), type(uint256).max);
        // This should trigger a claim on rewards
        uint256 sharesToLiquidator = y.liquidate(msg.sender, sharesBefore, 0, bytes(""));
        vm.stopPrank();

        if (hasRewards) assertEq(rewardToken.balanceOf(msg.sender), sharesBefore, "Liquidated account shares");
        if (hasEmissions) {
            assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser, 0.0010e18, "Liquidated account emissions");
        }

        assertEq(rewardToken.balanceOf(liquidator), 0, "Liquidator account rewards");
        assertEq(emissionsToken.balanceOf(liquidator), 0, "Liquidator account emissions");

        if (hasRewards) MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        if (hasEmissions) vm.warp(block.timestamp + 1 days);
        uint256 emissionsForLiquidator = 1e18 * sharesToLiquidator / y.totalSupply();

        rm.claimAccountRewards(liquidator);

        if (hasRewards) assertEq(rewardToken.balanceOf(liquidator), sharesToLiquidator, "Liquidator account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(liquidator), emissionsForLiquidator, 0.0010e18, "Liquidator account emissions");

        rm.claimAccountRewards(msg.sender);
        uint256 emissionsForUserAfter = 1e18 * y.balanceOfShares(msg.sender) / y.totalSupply();

        if (hasRewards) assertEq(rewardToken.balanceOf(msg.sender), sharesBefore + sharesBefore - sharesToLiquidator, "Liquidated account rewards");
        if (hasEmissions) assertApproxEqRel(emissionsToken.balanceOf(msg.sender), emissionsForUser + emissionsForUserAfter, 0.0010e18, "Liquidated account emissions");
    }
}