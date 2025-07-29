// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {WETH} from "../utils/Constants.sol";
import "../interfaces/IOrigin.sol";

contract OriginWithdrawRequestManager is AbstractWithdrawRequestManager {

    constructor() AbstractWithdrawRequestManager(address(WETH), address(wOETH), address(WETH)) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 woETHToWithdraw,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        uint256 oethRedeemed = wOETH.redeem(woETHToWithdraw, address(this), address(this));
        oETH.approve(address(OriginVault), oethRedeemed);
        (requestId, ) = OriginVault.requestWithdrawal(oethRedeemed);
    }

    function _stakeTokens(uint256 amount, bytes memory stakeData) internal override {
        uint256 minAmountOut;
        if (stakeData.length > 0) (minAmountOut) = abi.decode(stakeData, (uint256));
        WETH.approve(address(OriginVault), amount);
        uint256 oethBefore = oETH.balanceOf(address(this));
        OriginVault.mint(address(WETH), amount, minAmountOut);
        uint256 oethAfter = oETH.balanceOf(address(this));

        oETH.approve(address(wOETH), oethAfter - oethBefore);
        wOETH.deposit(oethAfter - oethBefore, address(this));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed) {
        uint256 balanceBefore = WETH.balanceOf(address(this));
        OriginVault.claimWithdrawal(requestId);
        tokensClaimed = WETH.balanceOf(address(this)) - balanceBefore;
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        IOriginVault.WithdrawalRequest memory request = OriginVault.withdrawalRequests(requestId);
        IOriginVault.WithdrawalQueueMetadata memory queue = OriginVault.withdrawalQueueMetadata();
        uint256 withdrawalClaimDelay = OriginVault.withdrawalClaimDelay();

        bool claimDelayMet = request.timestamp + withdrawalClaimDelay <= block.timestamp;
        bool queueLiquidityAvailable = request.queued <= queue.claimable;
        bool notClaimed = request.claimed == false;

        return claimDelayMet && queueLiquidityAvailable && notClaimed;
    }
}