// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { WETH } from "../utils/Constants.sol";
import { IOriginVault, OriginVault, oETH, wOETH } from "../interfaces/IOrigin.sol";

contract OriginWithdrawRequestManager is AbstractWithdrawRequestManager {
    bool internal immutable IS_WRAPPED_OETH;

    constructor(address yieldToken) AbstractWithdrawRequestManager(address(WETH), yieldToken, address(WETH)) {
        IS_WRAPPED_OETH = YIELD_TOKEN == address(wOETH);
        if (!IS_WRAPPED_OETH) require(yieldToken == address(oETH), "Invalid yield token");
    }

    function _initiateWithdrawImpl(
        address, /* account */
        uint256 amountToWithdraw,
        bytes calldata, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        if (IS_WRAPPED_OETH) {
            amountToWithdraw = wOETH.redeem(amountToWithdraw, address(this), address(this));
        }

        oETH.approve(address(OriginVault), amountToWithdraw);
        (requestId,) = OriginVault.requestWithdrawal(amountToWithdraw);
    }

    function _stakeTokens(uint256 amount, bytes memory stakeData) internal override {
        uint256 minAmountOut;
        if (stakeData.length > 0) (minAmountOut) = abi.decode(stakeData, (uint256));
        WETH.approve(address(OriginVault), amount);
        uint256 oethBefore = oETH.balanceOf(address(this));
        OriginVault.mint(address(WETH), amount, minAmountOut);
        uint256 oethAfter = oETH.balanceOf(address(this));

        if (IS_WRAPPED_OETH) {
            oETH.approve(address(wOETH), oethAfter - oethBefore);
            wOETH.deposit(oethAfter - oethBefore, address(this));
        }
    }

    function _finalizeWithdrawImpl(
        address, /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
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

    function getExchangeRate() public view override returns (uint256) {
        if (IS_WRAPPED_OETH) return super.getExchangeRate();
        // If the yield token is oETH then we can just return 1e18 for a 1-1 exchange rate
        return 1e18;
    }
}
