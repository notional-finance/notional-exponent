// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {CurveConvex2Token, DeploymentParams} from "./CurveConvex2Token.sol";
import "../../interfaces/Curve/ICurve.sol";
import "../../withdraws/IWithdrawRequestManager.sol";

contract CurveConvexStableSwapNG is CurveConvex2Token {

   constructor(
        uint256 _maxPoolShare,
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager,
        DeploymentParams memory params,
        IWithdrawRequestManager[] memory managers
    ) CurveConvex2Token(_maxPoolShare, _owner, _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager, params, managers) { }

    function _checkReentrancyContext() internal view override {
        // Total supply on stable swap has a non-reentrant lock
        ICurveStableSwapNG(CURVE_POOL).totalSupply();
    }

    function _enterPool(
        uint256[] memory _amounts, uint256 minPoolClaim, uint256 msgValue
    ) internal override returns (uint256) {
        return ICurveStableSwapNG(CURVE_POOL).add_liquidity{value: msgValue}(
            _amounts, minPoolClaim
        );
    }

    function _exitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        if (isSingleSided) {
            exitBalances = new uint256[](_NUM_TOKENS);
            // Method signature is the same for v1 and stable swap ng
            exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity_one_coin(
                poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
            );
        } else {
            return ICurveStableSwapNG(CURVE_POOL).remove_liquidity(poolClaim, _minAmounts);
        }
    }
}