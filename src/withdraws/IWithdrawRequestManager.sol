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

    /// @notice Stakes the deposit token to the yield token and transfers it back to the vault
    /// @dev Only approved vaults can stake tokens
    /// @param depositToken the token to stake, will be transferred from the vault
    /// @param amount the amount of tokens to stake
    /// @param data additional data for the stake
    function stakeTokens(address depositToken, uint256 amount, bytes calldata data) external;

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

    /// @notice Allows the emergency exit role to rescue tokens from the withdraw request manager
    /// @param cooldownHolder the cooldown holder to rescue tokens from
    /// @param token the token to rescue
    /// @param receiver the receiver of the rescued tokens
    /// @param amount the amount of tokens to rescue
    function rescueTokens(address cooldownHolder, address token, address receiver, uint256 amount) external;

    /// @notice Returns whether a withdraw request can be finalized
    /// @param requestId the request id of the withdraw request
    /// @return canFinalize whether the withdraw request can be finalized
    function canFinalizeWithdrawRequest(uint256 requestId) external view returns (bool);

    /// @notice Returns the withdraw request and split withdraw request for an account
    /// @param vault the vault to get the withdraw request for
    /// @param account the account to get the withdraw request for
    /// @return w the withdraw request
    /// @return s the split withdraw request
    function getWithdrawRequest(address vault, address account) external view returns (WithdrawRequest memory w, SplitWithdrawRequest memory s);
}
