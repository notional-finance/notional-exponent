// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {TRADING_MODULE} from "../interfaces/ITradingModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AbstractCustomOracle} from "./AbstractCustomOracle.sol";

/// @notice Returns the value of one LP token in terms of the primary borrowed currency by this
/// strategy. Will revert if the spot price on the pool is not within some deviation tolerance of
/// the implied oracle price. This is intended to prevent any pool manipulation.
/// The value of the LP token is calculated as the value of the token if all the balance claims are
/// withdrawn proportionally and then converted to the primary currency at the oracle price. Slippage
/// from selling the tokens is not considered, any slippage effects will be captured by the maximum
/// leverage ratio allowed before liquidation.
abstract contract AbstractLPOracle is AbstractCustomOracle {
    error InvalidPrice(uint256 oraclePrice, uint256 spotPrice);

    uint256 internal constant PERCENT_BASIS = 1e18;
    uint256 internal immutable POOL_PRECISION;
    uint256 internal immutable LOWER_LIMIT_MULTIPLIER;
    uint256 internal immutable UPPER_LIMIT_MULTIPLIER;
    address internal immutable LP_TOKEN;
    uint8 internal immutable PRIMARY_INDEX;

    constructor(
        uint256 _poolPrecision,
        uint256 _lowerLimitMultiplier,
        uint256 _upperLimitMultiplier,
        address _lpToken,
        uint8 _primaryIndex,
        string memory description_,
        address sequencerUptimeOracle_
    ) AbstractCustomOracle(
        description_,
        sequencerUptimeOracle_
    ) {
        require(_lowerLimitMultiplier < PERCENT_BASIS);
        require(PERCENT_BASIS < _upperLimitMultiplier);

        POOL_PRECISION = _poolPrecision;
        LOWER_LIMIT_MULTIPLIER = _lowerLimitMultiplier;
        UPPER_LIMIT_MULTIPLIER = _upperLimitMultiplier;
        LP_TOKEN = _lpToken;
        PRIMARY_INDEX = _primaryIndex;
    }

    function _totalPoolSupply() internal view virtual returns (uint256) {
        return IERC20(LP_TOKEN).totalSupply();
    }

    /// @notice Returns the pair price of two tokens via the TRADING_MODULE which holds a registry
    /// of oracles. Will revert of the oracle pair is not listed.
    function _getOraclePairPrice(address base, address quote) internal view returns (uint256) {
        (int256 rate, int256 precision) = TRADING_MODULE.getOraclePrice(base, quote);
        require(rate > 0);
        require(precision > 0);
        return uint256(rate) * POOL_PRECISION / uint256(precision);
    }

    /// @notice Helper method called by _checkPriceAndCalculateValue which will supply the relevant
    /// pool balances and spot prices. Calculates the claim of one LP token on relevant pool balances
    /// and compares the oracle price to the spot price, reverting if the deviation is too high.
    /// @return oneLPValueInPrimary the value of one LP token in terms of the primary borrowed currency
    function _calculateLPTokenValue(
        IERC20[] memory tokens,
        uint8[] memory decimals,
        uint256[] memory balances,
        uint256[] memory spotPrices
    ) internal view returns (uint256) {
        address primaryToken = address(tokens[PRIMARY_INDEX]);
        uint256 primaryDecimals = 10 ** decimals[PRIMARY_INDEX];
        uint256 totalSupply = _totalPoolSupply();
        uint256 oneLPValueInPrimary;

        for (uint256 i; i < tokens.length; i++) {
            // Skip the pool token if it is in the token list (i.e. ComposablePools)
            if (address(tokens[i]) == address(LP_TOKEN)) continue;
            // This is the claim on the pool balance of 1 LP token.
            uint256 tokenClaim = balances[i] * POOL_PRECISION / totalSupply;
            if (i == PRIMARY_INDEX) {
                oneLPValueInPrimary += tokenClaim;
            } else {
                uint256 price = _getOraclePairPrice(primaryToken, address(tokens[i]));

                // Check that the spot price and the oracle price are near each other. If this is
                // not true then we assume that the LP pool is being manipulated.
                uint256 lowerLimit = price * LOWER_LIMIT_MULTIPLIER / PERCENT_BASIS;
                uint256 upperLimit = price * UPPER_LIMIT_MULTIPLIER / PERCENT_BASIS;
                if (spotPrices[i] < lowerLimit || upperLimit < spotPrices[i]) {
                    revert InvalidPrice(price, spotPrices[i]);
                }

                // Convert the token claim to primary using the oracle pair price.
                uint256 secondaryDecimals = 10 ** decimals[i];
                oneLPValueInPrimary += (tokenClaim * POOL_PRECISION * primaryDecimals) / 
                    (price * secondaryDecimals);
            }
        }

        // Scale this up to the correct precision
        return oneLPValueInPrimary * rateDecimals / primaryDecimals;
    }

}
