// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractStakingStrategy} from "./AbstractStakingStrategy.sol";
import {IWithdrawRequestManager} from "../interfaces/IWithdrawRequestManager.sol";
import {weETH, WETH, LiquidityPool, eETH} from "../withdraws/EtherFi.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";

contract EtherFiStaking is AbstractStakingStrategy {
    constructor(uint256 _feeRate) AbstractStakingStrategy(
        address(WETH), address(weETH), _feeRate, ADDRESS_REGISTRY.getWithdrawRequestManager(address(weETH))
    ) {
        require(block.chainid == 1);
    }
}