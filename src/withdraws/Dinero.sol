// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {WETH} from "../utils/Constants.sol";
import {console2} from "forge-std/src/console2.sol";

interface IPirexETH {
    error StatusNotDissolvedOrSlashed();
    error NotEnoughETH();

    enum ValidatorStatus {
        // The validator is not staking and has no defined status.
        None,
        // The validator is actively participating in the staking process.
        // It could be in one of the following states: pending_initialized, pending_queued, or active_ongoing.
        Staking,
        // The validator has proceed with the withdrawal process.
        // It represents a meta state for active_exiting, exited_unslashed, and the withdrawal process being possible.
        Withdrawable,
        // The validator's status indicating that ETH is released to the pirexEthValidators
        // It represents the withdrawal_done status.
        Dissolved,
        // The validator's status indicating that it has been slashed due to misbehavior.
        // It serves as a meta state encompassing active_slashed, exited_slashed,
        // and the possibility of starting the withdrawal process (withdrawal_possible) or already completed (withdrawal_done)
        // with the release of ETH, subject to a penalty for the misbehavior.
        Slashed
    }

    function batchId() external view returns (uint256);
    function initiateRedemption(uint256 assets, address receiver, bool shouldTriggerValidatorExit) external;
    function deposit(address receiver, bool shouldCompound) external payable;
    function instantRedeemWithPxEth(uint256 _assets, address _receiver) external;
    function redeemWithUpxEth(uint256 _tokenId, uint256 _assets, address _receiver) external;
    function outstandingRedemptions() external view returns (uint256);

    function dissolveValidator(bytes calldata validator) external payable;
    function rewardRecipient() external view returns (address);
    function batchIdToValidator(uint256 batchId) external view returns (bytes memory);
    function status(bytes calldata validator) external view returns (ValidatorStatus);
}

IPirexETH constant PirexETH = IPirexETH(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
IERC20 constant pxETH = IERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6);
IERC4626 constant apxETH = IERC4626(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);
IERC1155 constant upxETH = IERC1155(0x5BF2419a33f82F4C1f075B4006d7fC4104C43868);

contract DineroWithdrawRequestManager is AbstractWithdrawRequestManager, ERC1155Holder {
    uint16 internal s_batchNonce;

    receive() external payable {}

    constructor(address pxETHorApxETH) AbstractWithdrawRequestManager(
        address(WETH), address(pxETHorApxETH), address(WETH)
    ) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 amountToWithdraw,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        if (YIELD_TOKEN == address(apxETH)) {
            // First redeem the apxETH to pxETH before we initiate the redemption
            amountToWithdraw = apxETH.redeem(amountToWithdraw, address(this), address(this));
        }

        uint256 initialBatchId = PirexETH.batchId();
        pxETH.approve(address(PirexETH), amountToWithdraw);
        // TODO: what do we put for should trigger validator exit?
        PirexETH.initiateRedemption(amountToWithdraw, address(this), false);
        uint256 finalBatchId = PirexETH.batchId();
        uint256 nonce = ++s_batchNonce;

        // May require multiple batches to complete the redemption
        require(initialBatchId < type(uint120).max);
        require(finalBatchId < type(uint120).max);
        // Initial and final batch ids may overlap between requests so the nonce is used to ensure uniqueness
        return nonce << 240 | initialBatchId << 120 | finalBatchId;
    }

    function _stakeTokens(uint256 amount, bytes memory /* stakeData */) internal override {
        WETH.withdraw(amount);
        PirexETH.deposit{value: amount}(address(this), YIELD_TOKEN == address(apxETH));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 initialBatchId = requestId >> 120 & type(uint120).max;
            uint256 finalBatchId = requestId & type(uint120).max;

            for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
                uint256 assets = upxETH.balanceOf(address(this), i);
                if (assets == 0) continue;
                PirexETH.redeemWithUpxEth(i, assets, address(this));
                tokensClaimed += assets;
            }
        }

        WETH.deposit{value: tokensClaimed}();
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        uint256 initialBatchId = requestId >> 120 & type(uint120).max;
        uint256 finalBatchId = requestId & type(uint120).max;
        uint256 totalAssets;

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            IPirexETH.ValidatorStatus status = PirexETH.status(PirexETH.batchIdToValidator(i));

            if (status != IPirexETH.ValidatorStatus.Dissolved && status != IPirexETH.ValidatorStatus.Slashed) {
                // Can only finalize if all validators are dissolved or slashed
                return false;
            }

            totalAssets += upxETH.balanceOf(address(this), i);
        }

        // Can only finalize if the total assets are greater than the outstanding redemptions
        return PirexETH.outstandingRedemptions() > totalAssets;
    }
}