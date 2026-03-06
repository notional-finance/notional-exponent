// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractCustomOracle } from "./AbstractCustomOracle.sol";
import { ILockingController, INFINIFI_GATEWAY } from "../interfaces/IInfiniFi.sol";
import { CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";

contract InfiniFiOracle is AbstractCustomOracle {
    using TypeConvert for uint256;

    uint16 public immutable UNWINDING_EPOCHS;

    constructor(string memory description_, uint16 unwindingEpochs) AbstractCustomOracle(description_, address(0)) {
        require(block.chainid == CHAIN_ID_MAINNET);
        UNWINDING_EPOCHS = unwindingEpochs;
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        ILockingController lockingController = ILockingController(INFINIFI_GATEWAY.getAddress("lockingController"));
        uint256 exchangeRate = lockingController.exchangeRate(UNWINDING_EPOCHS);
        answer = exchangeRate.toInt();
        roundId = 0;
        startedAt = block.timestamp;
        updatedAt = block.timestamp;
        answeredInRound = 0;
    }
}
