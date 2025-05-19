// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractStakingStrategy} from "./AbstractStakingStrategy.sol";
import {IWithdrawRequestManager} from "../interfaces/IWithdrawRequestManager.sol";
import {weETH, WETH, LiquidityPool, eETH} from "../withdraws/EtherFi.sol";

contract EtherFiStaking is AbstractStakingStrategy {
    constructor(
        uint256 _feeRate,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractStakingStrategy(
        address(WETH), address(weETH), _feeRate, _withdrawRequestManager
    ) {
        require(block.chainid == 1);
    }
}