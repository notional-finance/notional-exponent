// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractStakingStrategy } from "./AbstractStakingStrategy.sol";
import { ADDRESS_REGISTRY, CHAIN_ID_MAINNET } from "../utils/Constants.sol";

contract StakingStrategy is AbstractStakingStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate
    )
        AbstractStakingStrategy(_asset, _yieldToken, _feeRate, ADDRESS_REGISTRY.getWithdrawRequestManager(_yieldToken))
    {
        require(block.chainid == CHAIN_ID_MAINNET);
    }

    function strategy() public pure override returns (string memory) {
        return "Staking";
    }
}
