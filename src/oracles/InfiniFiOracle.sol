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
        ILockingController lockingController = ILockingController(INFINIFI_GATEWAY.getAddress("lockingController"));
        int256 liUSDRate = lockingController.exchangeRate(UNWINDING_EPOCHS).toInt();

        (AggregatorV2V3Interface baseToUSDOracle, uint8 baseToUSDDecimals) = TRADING_MODULE.priceOracles(baseToken);
        int256 baseToUSD;
        (roundId, baseToUSD, startedAt, updatedAt, answeredInRound) = baseToUSDOracle.latestRoundData();
        require(baseToUSD > 0 && liUSDRate > 0, "Chainlink Rate Error");

        answer = (liUSDRate * baseToUSD) / (int256(10 ** baseToUSDDecimals));
    }
}
