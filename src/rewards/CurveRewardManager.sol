// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractRewardManager, RewardPoolStorage} from "./AbstractRewardManager.sol";
import {ICurveGauge} from "../interfaces/Curve/ICurve.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";

contract CurveRewardManager is AbstractRewardManager {
    using TokenUtils for ERC20;

    function _executeClaim() internal override {
        address rewardPool = _getRewardPoolSlot().rewardPool;
        ICurveGauge(rewardPool).claim_rewards();
    }

    function _withdrawFromPreviousRewardPool(RewardPoolStorage memory oldRewardPool) internal override {
        uint256 boosterBalance = ERC20(oldRewardPool.rewardPool).balanceOf(address(this));
        ICurveGauge(oldRewardPool.rewardPool).withdraw(boosterBalance);
    }

    function _depositIntoNewRewardPool(address poolToken, uint256 poolTokens, RewardPoolStorage memory newRewardPool) internal override {
        ERC20(poolToken).checkApprove(newRewardPool.rewardPool, type(uint256).max);

        if (poolTokens > 0) ICurveGauge(newRewardPool.rewardPool).deposit(poolTokens);
    }
}
