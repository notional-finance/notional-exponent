// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";
import { IConcreteVault } from "../interfaces/IConcrete.sol";

contract ConcreteWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TokenUtils for ERC20;
    using TypeConvert for uint256;

    IConcreteVault public immutable ConcreteVault;

    struct ConcreteWithdrawRequest {
        uint128 withdrawAmount;
        uint128 epochNumber;
    }

    struct EpochClaimData {
        uint128 totalWithdrawals;
        uint120 totalUnderlyingClaimed;
        bool hasClaimed;
    }

    mapping(uint256 requestId => ConcreteWithdrawRequest request) public s_ConcreteWithdrawRequest;
    mapping(uint256 epochID => EpochClaimData epochClaimData) public s_epochClaimData;

    constructor(address _ConcreteVault)
        AbstractWithdrawRequestManager(
            IConcreteVault(_ConcreteVault).asset(), _ConcreteVault, IConcreteVault(_ConcreteVault).asset()
        )
    {
        ConcreteVault = IConcreteVault(_ConcreteVault);
    }

    function _stakeTokens(
        uint256 amount,
        bytes memory /* stakeData */
    )
        internal
        override
    {
        ERC20(STAKING_TOKEN).checkApprove(address(ConcreteVault), amount);
        ConcreteVault.deposit(amount, address(this));
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
        requestId = uint256(uint160(account));

        ERC20(YIELD_TOKEN).checkApprove(address(ConcreteVault), amountToWithdraw);
        // If the queue is active, then this is how much we expect to redeem. This
        // gets incremented in userEpochRequests and they will stack in the given epoch.
        uint256 latestEpochID = ConcreteVault.latestEpochID();
        // This returns an asset figure but this may not be the actual amount of assets redeemed
        // which is pending the epochPrice.
        ConcreteVault.redeem(amountToWithdraw, address(this), address(this));
        uint128 withdrawAmount = amountToWithdraw.toUint128();
        s_ConcreteWithdrawRequest[requestId] =
            ConcreteWithdrawRequest({ withdrawAmount: withdrawAmount, epochNumber: latestEpochID.toUint128() });

        EpochClaimData storage epochClaimData = s_epochClaimData[latestEpochID];
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
        ConcreteWithdrawRequest memory request = s_ConcreteWithdrawRequest[requestId];
        EpochClaimData memory epochClaimData = s_epochClaimData[request.epochNumber];

        if (epochClaimData.hasClaimed == false) {
            uint256 balanceBefore = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));
            uint256[] memory epochIDs = new uint256[](1);
            epochIDs[0] = request.epochNumber;
            ConcreteVault.claimWithdrawal(epochIDs);
            uint256 balanceAfter = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));

            EpochClaimData storage e = s_epochClaimData[request.epochNumber];
            e.hasClaimed = true;
            epochClaimData.totalUnderlyingClaimed = (balanceAfter - balanceBefore).toUint120();
            // Make sure this is written to storage.
            e.totalUnderlyingClaimed = epochClaimData.totalUnderlyingClaimed;
        }

        tokensClaimed = request.withdrawAmount * epochClaimData.totalUnderlyingClaimed / epochClaimData.totalWithdrawals;
        delete s_ConcreteWithdrawRequest[requestId];
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        ConcreteWithdrawRequest memory request = s_ConcreteWithdrawRequest[requestId];
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
        ConcreteWithdrawRequest memory request = s_ConcreteWithdrawRequest[requestId];
        // Once the epoch price is set, the withdraw request can be finalized.
        return ConcreteVault.getEpochPricePerShare(request.epochNumber) > 0;
    }
}
