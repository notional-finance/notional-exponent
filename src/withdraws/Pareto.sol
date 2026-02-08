// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IdleCDOEpochVariant, IdleCDOEpochQueue, IdleCreditVault } from "../interfaces/IPareto.sol";

contract ParetoWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TypeConvert for uint256;

    error ParetoBlockedAccount(address account);

    IdleCDOEpochVariant public immutable paretoVault;
    IdleCDOEpochQueue public immutable paretoQueue;

    struct ParetoWithdrawRequest {
        uint128 withdrawAmount;
        uint128 epochNumber;
    }

    struct EpochClaimData {
        uint128 totalWithdrawals;
        uint120 totalUnderlyingClaimed;
        bool hasClaimed;
    }

    mapping(uint256 requestId => ParetoWithdrawRequest p) public s_paretoWithdrawData;
    mapping(uint256 epoch => EpochClaimData epochClaimData) public s_epochClaimData;

    constructor(
        IdleCDOEpochVariant _paretoVault,
        IdleCDOEpochQueue _paretoQueue
    )
        AbstractWithdrawRequestManager(_paretoVault.token(), _paretoVault.AATranche(), _paretoVault.token())
    {
        paretoVault = _paretoVault;
        paretoQueue = _paretoQueue;
        require(paretoQueue.tranche() == _paretoVault.AATranche(), "Invalid tranche");
        require(paretoQueue.idleCDOEpoch() == address(_paretoVault), "Invalid epoch");
    }

    function _stakeTokens(
        uint256 amount,
        bytes memory /* stakeData */
    )
        internal
        override
    {
        bool isEpochRunning = paretoVault.isEpochRunning();
        if (isEpochRunning) {
            // Generally speaking deposits should only occur between epochs.
            require(paretoVault.isDepositDuringEpochDisabled() == false, "Deposit during epoch is disabled");
            require(block.timestamp < paretoVault.epochEndDate(), "Epoch has ended");
            require(paretoVault.isAYSActive() == false, "AYS is active");
            ERC20(STAKING_TOKEN).approve(address(paretoVault), amount);
            // Deposit into the AATranche
            paretoVault.depositDuringEpoch(amount, YIELD_TOKEN);
        } else {
            ERC20(STAKING_TOKEN).approve(address(paretoVault), amount);
            paretoVault.depositAA(amount);
        }
    }

    function _initiateWithdrawImpl(
        address account,
        uint256 amountToWithdraw,
        bytes calldata, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        if (!paretoVault.isWalletAllowed(account)) revert ParetoBlockedAccount(account);
        IdleCreditVault creditVault = paretoVault.strategy();
        uint256 nextEpoch = creditVault.epochNumber() + 1;

        ERC20(YIELD_TOKEN).approve(address(paretoQueue), amountToWithdraw);
        paretoQueue.requestWithdraw(amountToWithdraw);

        // An account can only have one withdraw request at a time, so we use it as the request id. Even if it
        // is tokenized this should be okay.
        requestId = uint256(uint160(account));
        uint128 withdrawAmount = amountToWithdraw.toUint128();
        s_paretoWithdrawData[requestId] =
            ParetoWithdrawRequest({ withdrawAmount: withdrawAmount, epochNumber: nextEpoch.toUint128() });

        EpochClaimData storage epochClaimData = s_epochClaimData[nextEpoch];
        epochClaimData.totalWithdrawals = epochClaimData.totalWithdrawals + withdrawAmount;
    }

    function _finalizeWithdrawImpl(
        address,
        /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
        ParetoWithdrawRequest memory request = s_paretoWithdrawData[requestId];
        EpochClaimData memory epochClaimData = s_epochClaimData[request.epochNumber];

        if (epochClaimData.hasClaimed == false) {
            uint256 balanceBefore = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));
            paretoQueue.claimWithdrawRequest(request.epochNumber);
            uint256 balanceAfter = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));

            EpochClaimData storage e = s_epochClaimData[request.epochNumber];
            e.hasClaimed = true;
            epochClaimData.totalUnderlyingClaimed = (balanceAfter - balanceBefore).toUint120();
            // Make sure this is written to storage.
            e.totalUnderlyingClaimed = epochClaimData.totalUnderlyingClaimed;
        }

        tokensClaimed = request.withdrawAmount * epochClaimData.totalUnderlyingClaimed / epochClaimData.totalWithdrawals;
        delete s_paretoWithdrawData[requestId];
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        ParetoWithdrawRequest memory request = s_paretoWithdrawData[requestId];
        EpochClaimData memory epochClaimData = s_epochClaimData[request.epochNumber];

        if (epochClaimData.hasClaimed) {
            // The known amount is only available after the epoch has been claimed.
            hasKnownAmount = true;
            amount = request.withdrawAmount * epochClaimData.totalUnderlyingClaimed / epochClaimData.totalWithdrawals;
        } else {
            hasKnownAmount = false;
            amount = 0;
        }
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        ParetoWithdrawRequest memory request = s_paretoWithdrawData[requestId];
        // The queue price is set and there are no pending claims.
        return (paretoQueue.epochWithdrawPrice(request.epochNumber) > 0
                && paretoQueue.epochPendingClaims(request.epochNumber) == 0);
    }
}
