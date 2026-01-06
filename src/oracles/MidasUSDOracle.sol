// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractCustomOracle } from "./AbstractCustomOracle.sol";
import { AggregatorV2V3Interface } from "../interfaces/AggregatorV2V3Interface.sol";
import { IMidasVault } from "../interfaces/IMidas.sol";
import { IMidasDataFeed } from "../interfaces/IMidas.sol";
import { CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";

contract MidasUSDOracle is AbstractCustomOracle {
    using TypeConvert for uint256;

    AggregatorV2V3Interface public constant usdcToUSDOracle =
        AggregatorV2V3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    AggregatorV2V3Interface public immutable midasOracle;
    int256 public immutable usdcToUSDDecimals;
    int256 public immutable midasDecimals;

    constructor(string memory description_, IMidasVault midasVault_) AbstractCustomOracle(description_, address(0)) {
        require(block.chainid == CHAIN_ID_MAINNET);
        usdcToUSDDecimals = int256(10 ** usdcToUSDOracle.decimals());
        midasOracle = AggregatorV2V3Interface(IMidasDataFeed(midasVault_.mTokenDataFeed()).aggregator());
        midasDecimals = int256(10 ** midasOracle.decimals());
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        int256 mTokenRate;
        (roundId, mTokenRate, startedAt, updatedAt, answeredInRound) = midasOracle.latestRoundData();
        // Offset the USDC/USD rate to ensure that the USDC/USD rate is hardcoded to 1 in the trading
        // module. In the vaults we request the mToken/USDC rate so we want to offset any USDC variations here.
        int256 usdcToUSD;
        (, usdcToUSD,,,) = usdcToUSDOracle.latestRoundData();
        require(usdcToUSD > 0 && mTokenRate > 0, "Chainlink Rate Error");
        answer = (mTokenRate * usdcToUSD * 1e18) / (usdcToUSDDecimals * midasDecimals);
    }
}
