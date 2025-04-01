// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractStakingStrategy} from "./AbstractStakingStrategy.sol";
import {IWithdrawRequestManager} from "../withdraws/IWithdrawRequestManager.sol";
import {weETH, WETH, LiquidityPool, eETH} from "../withdraws/EtherFiWithdrawRequestManager.sol";

contract EtherFiStaking is AbstractStakingStrategy {

    constructor(
        address _owner,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractStakingStrategy(
        address(weETH), address(WETH), address(0), _owner, _feeRate, _irm, _lltv, _withdrawRequestManager
    ) {
        require(block.chainid == 1);
    }

    function _stakeTokens(uint256 assets, address /* receiver */, bytes memory /* depositData */) internal override returns (uint256 yieldTokensMinted) {
        WETH.withdraw(assets);
        uint256 eEthBalBefore = eETH.balanceOf(address(this));
        LiquidityPool.deposit{value: assets}();
        uint256 eETHMinted = eETH.balanceOf(address(this)) - eEthBalBefore;
        yieldTokensMinted = weETH.wrap(eETHMinted);
    }
}