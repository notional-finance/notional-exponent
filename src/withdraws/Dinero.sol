// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {WETH} from "../utils/Constants.sol";
import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IPirexETH, PirexETH, pxETH, apxETH, upxETH} from "../interfaces/IDinero.sol";

contract DineroCooldownHolder is ClonedCoolDownHolder, ERC1155Holder {
    uint256 public initialBatchId;
    uint256 public finalBatchId;

    receive() external payable { }

    constructor(address _manager) ClonedCoolDownHolder(_manager) { }

    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown(uint256 amountToWithdraw) internal override {
        require(initialBatchId == 0 && finalBatchId == 0);

        initialBatchId = PirexETH.batchId();
        pxETH.approve(address(PirexETH), amountToWithdraw);
        // TODO: what do we put for should trigger validator exit?
        PirexETH.initiateRedemption(amountToWithdraw, address(this), false);
        finalBatchId = PirexETH.batchId();
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint256 i = initialBatchId;
        uint256 end = finalBatchId;

        for (; i <= end; i++) {
            uint256 assets = upxETH.balanceOf(address(this), i);
            if (assets == 0) continue;
            PirexETH.redeemWithUpxEth(i, assets, address(this));
            tokensClaimed += assets;
        }
        WETH.deposit{value: tokensClaimed}();
        WETH.transfer(manager, tokensClaimed);
        finalized = true;
    }
}

contract DineroWithdrawRequestManager is AbstractWithdrawRequestManager {

    address public HOLDER_IMPLEMENTATION;

    constructor(address pxETHorApxETH) AbstractWithdrawRequestManager(
        address(WETH), address(pxETHorApxETH), address(WETH)
    ) { }

    function _initialize(bytes calldata /* data */) internal override {
        HOLDER_IMPLEMENTATION = address(new DineroCooldownHolder(address(this)));
    }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 amountToWithdraw,
        bytes calldata /* data */,
        address /* forceWithdrawFrom */
    ) override internal returns (uint256 requestId) {
        if (YIELD_TOKEN == address(apxETH)) {
            // First redeem the apxETH to pxETH before we initiate the redemption
            amountToWithdraw = apxETH.redeem(amountToWithdraw, address(this), address(this));
        }

        DineroCooldownHolder holder = DineroCooldownHolder(payable(Clones.clone(HOLDER_IMPLEMENTATION)));
        pxETH.transfer(address(holder), amountToWithdraw);
        holder.startCooldown(amountToWithdraw);

        return uint256(uint160(address(holder)));
    }

    function _stakeTokens(uint256 amount, bytes memory /* stakeData */) internal override {
        WETH.withdraw(amount);
        PirexETH.deposit{value: amount}(address(this), YIELD_TOKEN == address(apxETH));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed) {
        DineroCooldownHolder holder = DineroCooldownHolder(payable(address(uint160(requestId))));
        bool finalized;
        (tokensClaimed, finalized) = holder.finalizeCooldown();
        require(finalized);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        DineroCooldownHolder holder = DineroCooldownHolder(payable(address(uint160(requestId))));
        uint256 initialBatchId = holder.initialBatchId();
        uint256 finalBatchId = holder.finalBatchId();
        uint256 totalAssets;

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            IPirexETH.ValidatorStatus status = PirexETH.status(PirexETH.batchIdToValidator(i));

            if (status != IPirexETH.ValidatorStatus.Dissolved && status != IPirexETH.ValidatorStatus.Slashed) {
                // Can only finalize if all validators are dissolved or slashed
                return false;
            }

            totalAssets += upxETH.balanceOf(address(holder), i);
        }

        // Can only finalize if the total assets are greater than the outstanding redemptions
        return PirexETH.outstandingRedemptions() >= totalAssets;
    }

    function getExchangeRate() public view override returns (uint256) {
        // pxETH is rebasing so we can just return 1e18
        if (YIELD_TOKEN == address(pxETH)) return 1e18;
        return super.getExchangeRate();
    }
}