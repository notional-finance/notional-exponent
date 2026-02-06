// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IdleCDOEpochVariant, IdleCreditVault } from "../interfaces/IPareto.sol";

contract ParetoWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TypeConvert for uint256;

    error ParetoBlockedAccount(address account);

    IdleCDOEpochVariant public immutable paretoVault;

    struct ParetoWithdrawRequest {
        uint128 underlyingAmount;
        uint128 epochNumber;
    }

    uint256 public s_lastFinalizedEpoch;
    mapping(uint256 requestId => ParetoWithdrawRequest p) public s_paretoWithdrawData;

    constructor(IdleCDOEpochVariant _paretoVault)
        AbstractWithdrawRequestManager(_paretoVault.token(), _paretoVault.AATranche(), _paretoVault.token())
    {
        paretoVault = _paretoVault;
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
        uint256 currentEpoch = creditVault.epochNumber();
        uint256 lastWithdrawRequest = creditVault.lastWithdrawRequest(address(this));

        // We are only allowed to have one withdraw request per epoch. All users who request a withdraw during the
        // current epoch will "stack" inside the pareto credit vault and we will need to finalize and claim them all
        // at once in order to avoid pushing the withdraw request into the next epoch. This means anyone who wants to
        // withdraw in the next epoch must wait until we call claimWithdrawRequest for the last finalized epoch.
        require(lastWithdrawRequest == currentEpoch || lastWithdrawRequest == 0, "Withdraw request already exists");

        uint256 instantWithdrawAmountBefore = creditVault.instantWithdrawRequests(address(this));
        // This underlying amount is what is credited to the user in the withdraw request.
        uint256 underlyingAmount = paretoVault.requestWithdraw(amountToWithdraw, paretoVault.AATranche());
        uint256 instantWithdrawAmountAfter = creditVault.instantWithdrawRequests(address(this));

        // An account can only have one withdraw request at a time, so we use it as the request id. Even if it
        // is tokenized this should be okay.
        requestId = uint256(uint160(account));
        if (instantWithdrawAmountAfter > instantWithdrawAmountBefore) {
            // This should always be the case given the pareto vault code.
            require(instantWithdrawAmountAfter - instantWithdrawAmountBefore == underlyingAmount);
            // We have received an instant withdraw, claim it and then mark the request as finalized.
            uint256 balanceBefore = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));
            paretoVault.claimInstantWithdrawRequest();
            uint256 balanceReceived = ERC20(WITHDRAW_TOKEN).balanceOf(address(this)) - balanceBefore;
            require(balanceReceived == underlyingAmount);

            s_paretoWithdrawData[requestId] = ParetoWithdrawRequest({
                underlyingAmount: underlyingAmount.toUint128(),
                // Signifies that this was an instant withdraw and will always be
                // less than or equal to the s_lastFinalizedEpoch.
                epochNumber: 0
            });
        } else {
            // Was not an instant withdraw so record the request
            s_paretoWithdrawData[requestId] = ParetoWithdrawRequest({
                underlyingAmount: underlyingAmount.toUint128(), epochNumber: currentEpoch.toUint128()
            });
        }
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
        tokensClaimed = request.underlyingAmount;
        require(tokensClaimed > 0);

        if (request.epochNumber <= s_lastFinalizedEpoch) {
            // This would be the case for an instant withdraw or a withdraw that was
            // already finalized. We do not need to try to claim the withdraw request again.
            delete s_paretoWithdrawData[requestId];
            return tokensClaimed;
        }

        uint256 currentEpoch = paretoVault.strategy().epochNumber();
        require(request.epochNumber < currentEpoch);

        // This will revert if we are not in the correct epoch. It will send all of the
        // underlying for all withdraw requests in the epoch back to the withdraw manager
        // and set the lastWithdrawRequest for this contract back to zero.
        paretoVault.claimWithdrawRequest();
        // At this point we have finalized up to the epoch before the current one.
        s_lastFinalizedEpoch = currentEpoch - 1;

        delete s_paretoWithdrawData[requestId];
        return tokensClaimed;
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        ParetoWithdrawRequest memory request = s_paretoWithdrawData[requestId];
        hasKnownAmount = true;
        amount = request.underlyingAmount;
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        ParetoWithdrawRequest memory request = s_paretoWithdrawData[requestId];
        if (request.epochNumber <= s_lastFinalizedEpoch) return true;

        uint256 currentEpoch = paretoVault.strategy().epochNumber();
        return request.epochNumber < currentEpoch;
    }
}
