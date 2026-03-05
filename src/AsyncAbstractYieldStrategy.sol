// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Initializable } from "./proxy/Initializable.sol";

/// @notice A wrapper for yield tokens that are only mintable on an async basis. This includes
/// yield tokens that exist on a different chain or yield tokens that are minted on a t+1 basis.
abstract contract AsyncAbstractYieldStrategy is AbstractYieldStrategy {
    uint256[40] private __gap;

    /// @notice We have our own tracking of pending deposit requests since we will need to mint
    /// vault shares when the deposit request is finalized on the yield token.
    mapping(address account => uint256 assetAmount) public s_pendingDepositRequest;

    function pendingDepositRequest(uint256, address controller) external view returns (uint256) {
        return s_pendingDepositRequest[controller];
    }

    /// @notice Prevents minting yield tokens if there is a pending deposit request.
    function _isWithdrawRequestPending(address account) internal view override returns (bool isPending) {
        isPending = super._isWithdrawRequestPending(account);
        if (!isPending) isPending = s_pendingDepositRequest[account] > 0;
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0)) {
            if (super._isWithdrawRequestPending(account)) {
                (bool hasRequest, uint256 value) =
                    withdrawRequestManager.getWithdrawRequestValue(address(this), t_CurrentAccount, asset, shares);

                // If the account does not have a withdraw request then this will fall through
                // to the super implementation.
                if (hasRequest) return value;
            }

            // Return the value of the pending deposit request if it exists.
            uint256 pendingDepositRequest = s_pendingDepositRequest[t_CurrentAccount];
            if (pendingDepositRequest > 0) return pendingDepositRequest;
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
        uint256 pendingDepositRequest = _requestDeposit(assets, receiver, depositData);
        require(pendingDepositRequest > 0, "Failed to request deposit");
        s_pendingDepositRequest[receiver] = pendingDepositRequest;

        // Mint one vault share to the receiver so that some amount of collateral can be supplied to the lending
        // protocol.
        sharesMinted = 1;
        _mint(receiver, sharesMinted);
    }

    function claimPendingDepositRequest(address account)
        external
        nonReentrant
        onlyLendingRouter
        setCurrentAccount(account)
    {
        uint256 pendingDepositRequest = s_pendingDepositRequest[account];
        require(pendingDepositRequest > 0, "No pending deposit request");

        // Here we call the super method to mint the shares since it will handle the yield token minting.
        sharesMinted = super._mintSharesGivenAssets(pendingDepositRequest, bytes(""), account, false);

        delete s_pendingDepositRequest[account];

        // Transfer the shares to the lending router so it can supply collateral
        t_AllowTransfer_To = t_CurrentLendingRouter;
        t_AllowTransfer_Amount = sharesMinted;
        _transfer(receiver, t_CurrentLendingRouter, sharesMinted);
        _checkInvariant();
    }

    function _requestDeposit(
        uint256 assets,
        address receiver,
        bytes memory depositData
    )
        internal
        virtual
        returns (uint256 pendingDepositRequest)
    {
        // TODO: in here actually request the deposit on the external protocol
        ERC20(asset).checkApprove(address(yieldToken), assets);
        uint256 requestId = yieldToken.requestDeposit(assets, address(this), depositData);
        pendingDepositRequest = yieldToken.pendingDepositRequest(requestId, address(this));
    }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual override {
        // TODO: in here actually mint the yield tokens on the external protocol
        yieldToken.deposit(assets, address(this));
    }
}
