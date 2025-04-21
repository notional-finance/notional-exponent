// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/rewards/IRewardManager.sol";
import {AbstractRewardManager, RewardPoolStorage} from "../src/rewards/AbstractRewardManager.sol";
import {RewardManagerMixin} from "../src/rewards/RewardManagerMixin.sol";


contract MockRewardManager is AbstractRewardManager {
    constructor(address rewardManager) AbstractRewardManager(rewardManager) { }
    
    function _executeClaim() internal override {
    }

    function _withdrawFromPreviousRewardPool(RewardPoolStorage memory oldRewardPool) internal override {
    }

    function _depositIntoNewRewardPool(address poolToken, uint256 poolTokens, RewardPoolStorage memory newRewardPool) internal override {
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
        MockWrapperERC20(yieldToken).deposit(assets);
    }

    function _redeemShares(uint256 sharesToRedeem, address /* sharesOwner */, bytes memory /* redeemData */) internal override returns (uint256 yieldTokensBurned, bool wasEscrowed) {
        yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
        MockWrapperERC20(yieldToken).withdraw(yieldTokensBurned);
        wasEscrowed = false;
    }
}

contract TestRewardManager is TestMorphoYieldStrategy {
    IRewardManager rm;

    function deployYieldStrategy() internal override {
        rm = new MockRewardManager(owner);
        w = new MockWrapperERC20(USDC);
        o = new MockOracle(1e18);
        y = new MockRewardVault(
            owner,
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            IRM,
            0.915e18, // 91.5% LTV
            address(rm)
        );
        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
}