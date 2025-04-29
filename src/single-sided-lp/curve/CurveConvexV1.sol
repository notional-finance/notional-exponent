// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {CurveConvex2Token, DeploymentParams} from "./CurveConvex2Token.sol";
import "../../interfaces/Curve/ICurve.sol";
import "../../withdraws/IWithdrawRequestManager.sol";

contract CurveConvexV1 is CurveConvex2Token {

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

    function _checkReentrancyContext() internal override {
        uint256[2] memory minAmounts;
        ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(0, minAmounts);
    }

    function _enterPool(
        uint256[] memory _amounts, uint256 minPoolClaim, uint256 msgValue
    ) internal override returns (uint256) {
        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];
        return ICurve2TokenPoolV1(CURVE_POOL).add_liquidity{value: msgValue}(
            amounts, minPoolClaim
        );
    }

    function _exitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        exitBalances = new uint256[](_NUM_TOKENS);
        if (isSingleSided) {
            // Method signature is the same for v1 and stable swap ng
            exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity_one_coin(
                poolClaim, int8(_PRIMARY_INDEX), _minAmounts[_PRIMARY_INDEX]
            );
        } else {
            // Redeem proportionally, min amounts are rewritten to a fixed length array
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            uint256[2] memory _exitBalances = ICurve2TokenPoolV1(CURVE_POOL).remove_liquidity(poolClaim, minAmounts);
            exitBalances[0] = _exitBalances[0];
            exitBalances[1] = _exitBalances[1];
        }
    }
}