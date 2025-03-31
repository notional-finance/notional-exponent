// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

/// Each withdraw request manager contract is responsible for managing withdraws of a token
/// from a specific token (i.e. wstETH, weETH, sUSDe, etc). Each yield strategy can call the
/// appropriate withdraw request manager to initiate a withdraw of a given yield token.

struct WithdrawRequest {
    uint256 requestId;
    uint256 yieldTokenAmount;
    bool hasSplit;
}

struct SplitWithdrawRequest {
    uint256 totalYieldTokenAmount;
    uint256 totalWithdraw;
    bool finalized;
}

error ExistingWithdrawRequest(address strategy, address account, uint256 requestId);
error NoWithdrawRequest(address vault, address account);
error InvalidWithdrawRequestSplit();

interface IWithdrawRequestManager {
    event InitiateWithdrawRequest(
        address indexed account,
        bool indexed isForced,
        uint256 amount,
        uint256 requestId
    );

    /// @notice Initiates a withdraw request
    /// @dev Only approved vaults can initiate withdraw requests
    /// @param account the account to initiate the withdraw request for
    /// @param amount the amount of yield tokens to withdraw
    /// @param isForced whether the withdraw request is forced
    /// @param data additional data for the withdraw request
    /// @return requestId the request id of the withdraw request
    function initiateWithdraw(
        address account,
        uint256 amount,
        bool isForced,
        bytes calldata data
    ) external returns (uint256 requestId);

    /// @notice Attempts to redeem active withdraw requests during vault exit
    /// @param account the account to finalize and redeem the withdraw request for
    /// @return tokensWithdrawn amount of withdraw tokens redeemed from the withdraw requests
    /// @return finalized whether the withdraw request was finalized
    function finalizeAndRedeemWithdrawRequest(
        address account
    ) external returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice Finalizes withdraw requests outside of a vault exit. This may be required in cases if an
    /// account is negligent in exiting their vault position and letting the withdraw request sit idle
    /// could result in losses. The withdraw request is finalized and stored in a "split" withdraw request
    /// where the account has the full claim on the withdraw.
    /// @dev No access control is enforced on this function but no tokens are transferred off the request
    /// manager either.
    function finalizeRequestManual(
        address vault,
        address account
    ) external returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice If an account has an illiquid withdraw request, this method will split their
    /// claim on it during liquidation.
    /// @dev Only approved vaults can split withdraw requests
    /// @param from the account that is being liquidated
    /// @param to the liquidator
    /// @param yieldTokenAmount the amount of yield tokens that have been transferred to the liquidator
    function splitWithdrawRequest(
        address from,
        address to,
        uint256 yieldTokenAmount
    ) external;

    function canFinalizeWithdrawRequest(uint256 requestId) external view returns (bool);
    function getWithdrawRequest(address vault, address account) external view returns (WithdrawRequest memory w, SplitWithdrawRequest memory s);
}
