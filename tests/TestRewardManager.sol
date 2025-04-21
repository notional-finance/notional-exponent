// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

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
        if (claim) rewardToken.transfer(holder, rewardAmount);
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

    function test_enterPosition_withRewards() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        // Check balance of reward token
        assertEq(rewardToken.balanceOf(msg.sender), 0);
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);

        MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        rm.claimRewardTokens();
        MockRewardPool(address(w)).setRewardAmount(0);

        // Still no reward debt
        assertEq(rewardToken.balanceOf(msg.sender), 0);
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);

        uint256 sharesBefore = y.balanceOfShares(msg.sender);
        uint256[] memory rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards.length, 1);
        assertEq(rewards[0], sharesBefore);
        rm.claimAccountRewards(msg.sender);

        assertEq(rewardToken.balanceOf(msg.sender), sharesBefore);
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), sharesBefore);

        rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards.length, 1);
        assertEq(rewards[0], 0);
        rm.claimAccountRewards(msg.sender);

        assertEq(rewardToken.balanceOf(msg.sender), sharesBefore);
        assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), sharesBefore);

        _enterPosition(msg.sender, defaultDeposit, 0);
        uint256 sharesAfter = y.balanceOfShares(msg.sender);

        MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        rm.claimAccountRewards(msg.sender);
        assertEq(rewardToken.balanceOf(msg.sender), sharesBefore + sharesAfter);
    }

    function test_exitPosition_withRewards(bool isFullExit) public {
        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);

        vm.warp(block.timestamp + 6 minutes);

        // Rewards are 1-1 with yield tokens
        MockRewardPool(address(w)).setRewardAmount(y.totalSupply());

        uint256 sharesBefore = y.balanceOfShares(msg.sender);
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

        assertEq(rewardToken.balanceOf(msg.sender), sharesBefore);

        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);
        }

        MockRewardPool(address(w)).setRewardAmount(y.totalSupply());
        uint256 sharesAfter = y.balanceOfShares(msg.sender);
        rm.claimRewardTokens();
        uint256[] memory rewards = rm.getAccountRewardClaim(msg.sender, block.timestamp);
        assertEq(rewards.length, 1);
        assertEq(rewards[0], sharesAfter);

        MockRewardPool(address(w)).setRewardAmount(0);
        rm.claimAccountRewards(msg.sender);

        assertEq(rewardToken.balanceOf(msg.sender), sharesBefore + sharesAfter);
        if (isFullExit) {
            assertEq(rm.getRewardDebt(address(rewardToken), msg.sender), 0);
        }
    }

    // function test_liquidate() public override {
    //     super.test_liquidate();
    // }
}