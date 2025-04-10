// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH} from "../utils/Constants.sol";

interface IOriginVault {
    struct WithdrawalQueueMetadata {
        // cumulative total of all withdrawal requests included the ones that have already been claimed
        uint128 queued;
        // cumulative total of all the requests that can be claimed including the ones that have already been claimed
        uint128 claimable;
        // total of all the requests that have been claimed
        uint128 claimed;
        // index of the next withdrawal request starting at 0
        uint128 nextWithdrawalIndex;
    }

    struct WithdrawalRequest {
        address withdrawer;
        bool claimed;
        uint40 timestamp; // timestamp of the withdrawal request
        // Amount of oTokens to redeem. eg OETH
        uint128 amount;
        // cumulative total of all withdrawal requests including this one.
        // this request can be claimed when this queued amount is less than or equal to the queue's claimable amount.
        uint128 queued;
    }

    function withdrawalRequests(uint256 requestId) external view returns (WithdrawalRequest memory);
    function withdrawalClaimDelay() external view returns (uint256);
    function withdrawalQueueMetadata() external view returns (WithdrawalQueueMetadata memory);
    function requestWithdrawal(uint256 amount) external returns (uint256 requestId, uint256 queued);
    function mint(address token, uint256 amount, uint256 minAmountOut) external;
    function claimWithdrawal(uint256 requestId) external returns (uint256 amount);
    function addWithdrawalQueueLiquidity() external;
}

IOriginVault constant OriginVault = IOriginVault(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);
IERC20 constant oETH = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);

contract OriginWithdrawRequestManager is AbstractWithdrawRequestManager {

    constructor(address _owner) AbstractWithdrawRequestManager(_owner, address(WETH), address(oETH)) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 oETHToWithdraw,
        bool /* isForced */,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        IERC20(yieldToken).approve(address(OriginVault), oETHToWithdraw);
        (requestId, ) = OriginVault.requestWithdrawal(oETHToWithdraw);
    }

    function _stakeTokens(address depositToken, uint256 amount, bytes calldata data) internal override {
        require(depositToken == address(WETH), "Invalid deposit token");
        uint256 minAmountOut;
        if (data.length > 0) (minAmountOut) = abi.decode(data, (uint256));
        WETH.approve(address(OriginVault), amount);
        OriginVault.mint(depositToken, amount, minAmountOut);
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 balanceBefore = WETH.balanceOf(address(this));
            OriginVault.claimWithdrawal(requestId);
            tokensClaimed = WETH.balanceOf(address(this)) - balanceBefore;
        }
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