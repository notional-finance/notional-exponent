// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { TokenUtils, ERC20 } from "../utils/TokenUtils.sol";
import { Initializable } from "../proxy/Initializable.sol";
import { AbstractStakingStrategy } from "./AbstractStakingStrategy.sol";
import { IAsyncYieldStrategy } from "../interfaces/IYieldStrategy.sol";

/// @notice A wrapper for yield tokens that are only mintable on an async basis. This includes
/// yield tokens that exist on a different chain or yield tokens that are minted on a t+1 basis.
abstract contract AsyncAbstractYieldStrategy is AbstractStakingStrategy, IAsyncYieldStrategy {
    using TokenUtils for ERC20;
    uint256[40] private __gap;

    /// @notice The number of shares that are pending to be minted due to a deposit request.
    uint256 internal s_pendingDepositShares;

    /// @notice We have our own tracking of pending deposit requests since we will need to mint
    /// vault shares when the deposit request is finalized on the yield token.
    mapping(address account => uint256 assetAmount) public s_pendingDepositRequest;

    function effectiveSupply() public view override returns (uint256) {
        return super.effectiveSupply() - s_pendingDepositShares;
    }

    function pendingDepositRequest(address account) external view returns (uint256) {
        return s_pendingDepositRequest[account];
    }

    /// @notice Prevents minting yield tokens if there is a pending deposit request.
    function _isWithdrawRequestPending(address account) internal view override returns (bool isPending) {
        isPending = super._isWithdrawRequestPending(account);
        if (!isPending) isPending = s_pendingDepositRequest[account] > 0;
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0)) {
            if (super._isWithdrawRequestPending(t_CurrentAccount)) {
                (bool hasRequest, uint256 value) =
                    withdrawRequestManager.getWithdrawRequestValue(address(this), t_CurrentAccount, asset, shares);

                // If the account does not have a withdraw request then this will fall through
                // to the super implementation.
                if (hasRequest) return value;
            }

            // Return the value of the pending deposit request if it exists.
            uint256 pendingAssets = s_pendingDepositRequest[t_CurrentAccount];
            if (pendingAssets > 0) return pendingAssets;
        }

        return super.convertToAssets(shares);
    }

    function _mintSharesGivenAssets(
        uint256 assets,
        bytes memory depositData,
        address receiver,
        bool transferYieldTokensFromReceiver
    )
        internal
        override
        returns (uint256 sharesMinted)
    {
        // If transferring yield tokens, then the super method will work.
        if (transferYieldTokensFromReceiver) {
            return super._mintSharesGivenAssets(assets, depositData, receiver, transferYieldTokensFromReceiver);
        }

        // Otherwise, due to the async nature of the deposit request we will mint one vault share here and mark
        // the pending deposit request.
        require(s_pendingDepositRequest[receiver] == 0, "Pending deposit request already exists");
        uint256 pendingAssets = _requestDeposit(assets, receiver, depositData);
        require(pendingAssets > 0, "Failed to request deposit");
        s_pendingDepositRequest[receiver] = pendingAssets;

        // Mint one vault share to the receiver so that some amount of collateral can be supplied to the lending
        // protocol.
        sharesMinted = 1;
        s_pendingDepositShares++;
        _mint(receiver, sharesMinted);
    }

    function claimPendingDepositRequest(
        address account,
        bytes memory depositData
    )
        external
        override
        nonReentrant
        onlyLendingRouter
        setCurrentAccount(account)
        returns (uint256 sharesMinted)
    {
        uint256 pendingAssets = s_pendingDepositRequest[account];
        require(pendingAssets > 0, "No pending deposit request");

        // Here we call the super method to mint the shares since it will handle the yield token minting.
        sharesMinted = super._mintSharesGivenAssets(pendingAssets, depositData, account, false);

        delete s_pendingDepositRequest[account];
        s_pendingDepositShares--;

        // Transfer the shares to the lending router so it can supply collateral
        t_AllowTransfer_To = t_CurrentLendingRouter;
        t_AllowTransfer_Amount = sharesMinted;
        _transfer(account, t_CurrentLendingRouter, sharesMinted);
        _checkInvariant();
    }

    // TODO: in here actually request the deposit on the external protocol
    function _requestDeposit(
        uint256 assets,
        address receiver,
        bytes memory depositData
    )
        internal
        virtual
        returns (uint256 pendingAssets);
    // {
    //     ERC20(asset).checkApprove(address(yieldToken), assets);
    //     // uint256 requestId = yieldToken.requestDeposit(assets, address(this), depositData);
    //     // pendingAssets = yieldToken.pendingDepositRequest(requestId, address(this));
    // }

    // TODO: in here actually mint the yield tokens on the external protocol
    // yieldToken.deposit(assets, address(this));
    // function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual;
}
