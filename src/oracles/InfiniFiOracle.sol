// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractCustomOracle } from "./AbstractCustomOracle.sol";
import { ILockingController, INFINIFI_GATEWAY } from "../interfaces/IInfiniFi.sol";
import { TRADING_MODULE } from "../interfaces/ITradingModule.sol";
import { CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";
import { AggregatorV2V3Interface } from "../interfaces/AggregatorV2V3Interface.sol";

contract InfiniFiOracle is AbstractCustomOracle {
    using TypeConvert for uint256;

    uint16 public immutable UNWINDING_EPOCHS;
    address public immutable baseToken;

    constructor(
        string memory description_,
        uint16 unwindingEpochs,
        address baseToken_
    )
        AbstractCustomOracle(description_, address(0))
    {
        require(block.chainid == CHAIN_ID_MAINNET);
        UNWINDING_EPOCHS = unwindingEpochs;
        baseToken = baseToken_;
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (, int256 liUSDRate,,,) = AggregatorV2V3Interface(0x9B5ae92EBa3C383Be073e3ff94613B2C33851282).latestRoundData();

        (AggregatorV2V3Interface baseToUSDOracle, uint8 baseToUSDDecimals) = TRADING_MODULE.priceOracles(baseToken);
        int256 baseToUSD;
        (roundId, baseToUSD, startedAt, updatedAt, answeredInRound) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0 && liUSDRate > 0, "Chainlink Rate Error");

        answer = (liUSDRate * baseToUSD) / (int256(10 ** baseToUSDDecimals));
    }
}
