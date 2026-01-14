// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractCustomOracle } from "./AbstractCustomOracle.sol";
import { AggregatorV2V3Interface } from "../interfaces/AggregatorV2V3Interface.sol";
import { IMidasVault } from "../interfaces/IMidas.sol";
import { IMidasDataFeed } from "../interfaces/IMidas.sol";
import { TRADING_MODULE } from "../interfaces/ITradingModule.sol";
import { CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";

contract MidasOracle is AbstractCustomOracle {
    using TypeConvert for uint256;

    address public immutable baseToken;
    AggregatorV2V3Interface public immutable midasOracle;
    int256 public immutable midasDecimals;

    constructor(
        string memory description_,
        IMidasVault midasVault_,
        address baseToken_
    )
        AbstractCustomOracle(description_, address(0))
    {
        require(block.chainid == CHAIN_ID_MAINNET);
        baseToken = baseToken_;
        midasOracle = AggregatorV2V3Interface(IMidasDataFeed(midasVault_.mTokenDataFeed()).aggregator());
        midasDecimals = int256(10 ** midasOracle.decimals());
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (AggregatorV2V3Interface baseToUSDOracle, uint8 baseToUSDDecimals) = TRADING_MODULE.priceOracles(baseToken);
        int256 mTokenRate;
        uint256 mTokenUpdatedAt;
        (roundId, mTokenRate, startedAt, mTokenUpdatedAt, answeredInRound) = midasOracle.latestRoundData();
        // Offset the base/USD rate to ensure that the base/USD rate is hardcoded to 1 in the trading
        // module. In the vaults we request the mToken/base rate so we want to offset any base variations here.
        int256 baseToUSD;
        (, baseToUSD,, updatedAt,) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0 && mTokenRate > 0, "Chainlink Rate Error");

        // mTokenUpdatedAt is only refreshed once or twice a week so we only return it if it is lagging by more than 7
        // days. This will cause the stale price check to revert any action.
        if (mTokenUpdatedAt < updatedAt && (mTokenUpdatedAt < block.timestamp - 7 days)) updatedAt = mTokenUpdatedAt;
        answer = (mTokenRate * baseToUSD * 1e18) / (int256(10 ** baseToUSDDecimals) * midasDecimals);
    }
}
