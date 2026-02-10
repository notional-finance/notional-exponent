// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";
import { TypeConvert } from "../utils/TypeConvert.sol";

interface IRoycoVault is IERC4626 {
    error NoClaimableRequest();
    error EpochNotProcessed(uint256 epochNumber);

    function getEpochPricePerShare(uint256 epochNumber) external view returns (uint256);
    function latestEpochID() external view returns (uint256);
    function claimWithdrawal(uint256[] memory epochIDs) external;
    function claimWithdrawal(address asset, address user, uint256[] calldata epochIDs, uint8 decimals) external;
    function pastEpochsUnclaimedAssets() external view returns (uint256);
}

interface IRoycoWhitelistHook {
    function owner() external view returns (address);
    function whitelistUsers(address[] memory users) external;
}

contract RoycoWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TokenUtils for ERC20;
    using TypeConvert for uint256;

    IRoycoVault public immutable roycoVault;

    struct RoycoWithdrawRequest {
        uint128 withdrawAmount;
        uint128 epochNumber;
    }

    struct EpochClaimData {
        uint128 totalWithdrawals;
        uint120 totalUnderlyingClaimed;
        bool hasClaimed;
    }

    mapping(uint256 requestId => RoycoWithdrawRequest request) public s_roycoWithdrawRequest;
    mapping(uint256 epochID => EpochClaimData epochClaimData) public s_epochClaimData;

    constructor(address _roycoVault)
        AbstractWithdrawRequestManager(IERC4626(_roycoVault).asset(), _roycoVault, IERC4626(_roycoVault).asset())
    {
        roycoVault = IRoycoVault(_roycoVault);
    }

    function _stakeTokens(
        uint256 amount,
        bytes memory /* stakeData */
    )
        internal
        override
    {
        ERC20(STAKING_TOKEN).checkApprove(address(roycoVault), amount);
        roycoVault.deposit(amount, address(this));
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

        ERC20(YIELD_TOKEN).checkApprove(address(roycoVault), amountToWithdraw);
        // If the queue is active, then this is how much we expect to redeem. This
        // gets incremented in userEpochRequests and they will stack in the given epoch.
        uint256 latestEpochID = roycoVault.latestEpochID();
        // This returns an asset figure but this may not be the actual amount of assets redeemed
        // which is pending the epochPrice.
        roycoVault.redeem(amountToWithdraw, address(this), address(this));
        uint128 withdrawAmount = amountToWithdraw.toUint128();
        s_roycoWithdrawRequest[requestId] =
            RoycoWithdrawRequest({ withdrawAmount: withdrawAmount, epochNumber: latestEpochID.toUint128() });

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
        RoycoWithdrawRequest memory request = s_roycoWithdrawRequest[requestId];
        EpochClaimData memory epochClaimData = s_epochClaimData[request.epochNumber];

        if (epochClaimData.hasClaimed == false) {
            uint256 balanceBefore = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));
            uint256[] memory epochIDs = new uint256[](1);
            epochIDs[0] = request.epochNumber;
            roycoVault.claimWithdrawal(epochIDs);
            uint256 balanceAfter = ERC20(WITHDRAW_TOKEN).balanceOf(address(this));

            EpochClaimData storage e = s_epochClaimData[request.epochNumber];
            e.hasClaimed = true;
            epochClaimData.totalUnderlyingClaimed = (balanceAfter - balanceBefore).toUint120();
            // Make sure this is written to storage.
            e.totalUnderlyingClaimed = epochClaimData.totalUnderlyingClaimed;
        }

        tokensClaimed = request.withdrawAmount * epochClaimData.totalUnderlyingClaimed / epochClaimData.totalWithdrawals;
        delete s_roycoWithdrawRequest[requestId];
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        RoycoWithdrawRequest memory request = s_roycoWithdrawRequest[requestId];
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
        RoycoWithdrawRequest memory request = s_roycoWithdrawRequest[requestId];
        // Once the epoch price is set, the withdraw request can be finalized.
        return roycoVault.getEpochPricePerShare(request.epochNumber) > 0;
    }
}
