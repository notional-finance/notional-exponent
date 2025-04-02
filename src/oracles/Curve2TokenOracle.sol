// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractLPOracle, IERC20} from "./AbstractLPOracle.sol";
import {ICurvePool} from "../interfaces/Curve/ICurve.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {ETH_ADDRESS, ALT_ETH_ADDRESS} from "../Constants.sol";
import {TypeConvert} from "../Constants.sol";

contract Curve2TokenOracle is AbstractLPOracle {
    using TypeConvert for uint256;

    uint8 internal immutable SECONDARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;

    constructor(
        uint256 _lowerLimitMultiplier,
        uint256 _upperLimitMultiplier,
        address _lpToken,
        uint8 _primaryIndex,
        string memory description_,
        address sequencerUptimeOracle_
    ) AbstractLPOracle(1e18, _lowerLimitMultiplier, _upperLimitMultiplier, _lpToken, _primaryIndex, description_, sequencerUptimeOracle_) {
        TOKEN_1 = _rewriteAltETH(ICurvePool(_lpToken).coins(0));
        TOKEN_2 = _rewriteAltETH(ICurvePool(_lpToken).coins(1));
        DECIMALS_1 = TokenUtils.getDecimals(TOKEN_1);
        DECIMALS_2 = TokenUtils.getDecimals(TOKEN_2);
        SECONDARY_INDEX = 1 - PRIMARY_INDEX;
    }

    function _rewriteAltETH(address token) private pure returns (address) {
        return token == address(ALT_ETH_ADDRESS) ? ETH_ADDRESS : address(token);
    }

    function _calculateBaseToQuote() internal view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = ICurvePool(LP_TOKEN).balances(0);
        balances[1] = ICurvePool(LP_TOKEN).balances(1);

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = DECIMALS_1;
        decimals[1] = DECIMALS_2;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(TOKEN_1);
        tokens[1] = IERC20(TOKEN_2);

        // The primary index spot price is left as zero.
        uint256[] memory spotPrices = new uint256[](2);
        uint256 primaryPrecision = 10 ** decimals[PRIMARY_INDEX];
        uint256 secondaryPrecision = 10 ** decimals[SECONDARY_INDEX];

        // `get_dy` returns the price of one unit of the primary token
        // converted to the secondary token. The spot price is in secondary
        // precision and then we convert it to POOL_PRECISION.
        spotPrices[SECONDARY_INDEX] = ICurvePool(LP_TOKEN).get_dy(
            int8(PRIMARY_INDEX), int8(SECONDARY_INDEX), primaryPrecision
        ) * POOL_PRECISION / secondaryPrecision;

        answer = _calculateLPTokenValue(tokens, decimals, balances, spotPrices).toInt();
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        roundId = 0;
        answeredInRound = 0;
    }
}