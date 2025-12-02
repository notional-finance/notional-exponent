// SPDX-License-Identifier: BSUL-1.1
pragma solidity >=0.8.29;

import { AbstractCustomOracle } from "./AbstractCustomOracle.sol";
import { AggregatorV2V3Interface } from "../interfaces/AggregatorV2V3Interface.sol";
import { DEFAULT_PRECISION } from "../utils/Constants.sol";

contract ChainlinkUSDOracle is AbstractCustomOracle {
    AggregatorV2V3Interface public immutable baseToUSDOracle;
    int256 public immutable baseToUSDDecimals;
    AggregatorV2V3Interface public immutable quoteToUSDOracle;
    int256 public immutable quoteToUSDDecimals;
    bool public immutable invertBase;
    bool public immutable invertQuote;

    constructor(
        AggregatorV2V3Interface baseToUSDOracle_,
        AggregatorV2V3Interface quoteToUSDOracle_,
        bool invertBase_,
        bool invertQuote_,
        string memory description_,
        address sequencerUptimeOracle_
    )
        AbstractCustomOracle(description_, sequencerUptimeOracle_)
    {
        baseToUSDOracle = baseToUSDOracle_;
        quoteToUSDOracle = quoteToUSDOracle_;
        uint8 _baseDecimals = baseToUSDOracle_.decimals();
        uint8 _quoteDecimals = quoteToUSDOracle_.decimals();

        require(_baseDecimals <= 18);
        require(_quoteDecimals <= 18);

        baseToUSDDecimals = int256(10 ** _baseDecimals);
        quoteToUSDDecimals = int256(10 ** _quoteDecimals);
        invertBase = invertBase_;
        invertQuote = invertQuote_;
    }

    function _getQuoteRate() internal view virtual returns (int256 quoteRate) {
        (/* roundId */,
            quoteRate,/* uint256 startedAt */,/* updatedAt */,
            /* answeredInRound */
        ) = quoteToUSDOracle.latestRoundData();
        require(quoteRate > 0, "Chainlink Rate Error");
        if (invertQuote) quoteRate = (quoteToUSDDecimals * quoteToUSDDecimals) / quoteRate;
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 baseToUSD;
        (roundId, baseToUSD, startedAt, updatedAt, answeredInRound) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0, "Chainlink Rate Error");
        // Overflow and div by zero not possible
        if (invertBase) baseToUSD = (baseToUSDDecimals * baseToUSDDecimals) / baseToUSD;

        int256 quoteToUSD = _getQuoteRate();

        // To convert from USDC/USD (base) and ETH/USD (quote) to USDC/ETH we do:
        // (USDC/USD * quoteDecimals * 1e18) / (ETH/USD * baseDecimals)
        answer = (baseToUSD * quoteToUSDDecimals * int256(DEFAULT_PRECISION)) / (quoteToUSD * baseToUSDDecimals);
    }
}
