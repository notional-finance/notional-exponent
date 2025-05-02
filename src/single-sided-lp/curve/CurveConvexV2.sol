// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {CurveConvex2Token, DeploymentParams} from "./CurveConvex2Token.sol";
import "../../interfaces/Curve/ICurve.sol";
import {TokenUtils, IERC20} from "../../utils/TokenUtils.sol";
import "../../withdraws/IWithdrawRequestManager.sol";

contract CurveConvexV2 is CurveConvex2Token {
    using TokenUtils for IERC20;

   constructor(
        uint256 _maxPoolShare,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager,
        DeploymentParams memory params,
        IWithdrawRequestManager[] memory managers
    ) CurveConvex2Token(_maxPoolShare, _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager, params, managers) { }

    function _checkReentrancyContext() internal override {
        uint256[2] memory minAmounts;
        // Curve V2 does a `-1` on the liquidity amount so set the amount removed to 1 to
        // avoid an underflow.
        ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(1, minAmounts, true, address(this));
    }

    function _enterPool(
        uint256[] memory _amounts, uint256 minPoolClaim, uint256 msgValue
    ) internal override returns (uint256) {
        uint256[2] memory amounts;
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];
        return ICurve2TokenPoolV2(CURVE_POOL).add_liquidity{value: msgValue}(
            amounts, minPoolClaim, 0 < msgValue // use_eth = true if msgValue > 0
        );
    }

    function _exitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        exitBalances = new uint256[](_NUM_TOKENS);

        if (isSingleSided) {
            // Method signature is the same for v1 and stable swap ng
            exitBalances[_PRIMARY_INDEX] = ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity_one_coin(
                // Last two parameters are useEth = true and receiver = this contract
                poolClaim, _PRIMARY_INDEX, _minAmounts[_PRIMARY_INDEX], true, address(this)
            );
        } else {
            uint256[2] memory minAmounts;
            minAmounts[0] = _minAmounts[0];
            minAmounts[1] = _minAmounts[1];

            exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1);
            exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2);
            // Remove liquidity on CurveV2 does not return the exit amounts so we have to measure
            // them before and after.
            ICurve2TokenPoolV2(CURVE_POOL).remove_liquidity(
                // Last two parameters are useEth = true and receiver = this contract
                poolClaim, minAmounts, true, address(this)
            );
            exitBalances[0] = TokenUtils.tokenBalance(TOKEN_1) - exitBalances[0];
            exitBalances[1] = TokenUtils.tokenBalance(TOKEN_2) - exitBalances[1];
        }
    }
}