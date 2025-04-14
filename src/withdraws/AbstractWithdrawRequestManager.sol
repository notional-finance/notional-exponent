// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "./IWithdrawRequestManager.sol";
import "./ClonedCoolDownHolder.sol";
import "../utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * Library to handle potentially illiquid withdraw requests of staking tokens where there
 * is some indeterminate lock up time before tokens can be redeemed. Examples would be withdraws
 * of staked or restaked ETH, tokens like sUSDe or stkAave which have cooldown periods before they
 * can be withdrawn.
 *
 * Primarily, this library tracks the withdraw request and an associated identifier for the withdraw
 * request. It also allows for the withdraw request to be "tokenized" so that shares of the withdraw
 * request can be liquidated.
 */
abstract contract AbstractWithdrawRequestManager is IWithdrawRequestManager {
    using SafeERC20 for IERC20;

    address public override immutable yieldToken;
    address public override immutable withdrawToken;

    address public override owner;
    mapping(address => bool) public override isApprovedVault;
    // vault => account => withdraw request
    mapping(address => mapping(address => WithdrawRequest)) internal s_accountWithdrawRequest;
    mapping(uint256 => SplitWithdrawRequest) internal s_splitWithdrawRequest;

    constructor(address _owner, address _withdrawToken, address _yieldToken) {
        owner = _owner;
        withdrawToken = _withdrawToken;
        yieldToken = _yieldToken;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyApprovedVault() {
        if (!isApprovedVault[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Returns the status of a withdraw request
    function getWithdrawRequest(address vault, address account) public view returns (WithdrawRequest memory w, SplitWithdrawRequest memory s) {
        w = s_accountWithdrawRequest[vault][account];
        s = s_splitWithdrawRequest[w.requestId];
    }

    /// @inheritdoc IWithdrawRequestManager
    function setApprovedVault(address vault, bool isApproved) external override onlyOwner {
        isApprovedVault[vault] = isApproved;
        emit ApprovedVault(vault, isApproved);
    }

    /// @inheritdoc IWithdrawRequestManager
    function stakeTokens(address depositToken, uint256 amount, bytes calldata data) external override onlyApprovedVault returns (uint256 yieldTokensMinted) {
        uint256 initialYieldTokenBalance = IERC20(yieldToken).balanceOf(address(this));
        IERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);

        _stakeTokens(depositToken, amount, data);

        yieldTokensMinted = IERC20(yieldToken).balanceOf(address(this)) - initialYieldTokenBalance;
        IERC20(yieldToken).safeTransfer(msg.sender, yieldTokensMinted);
    }

    /// @inheritdoc IWithdrawRequestManager
    function initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        bool isForced,
        bytes calldata data
    ) external override onlyApprovedVault returns (uint256 requestId) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[msg.sender][account];
        if (accountWithdraw.requestId != 0) revert ExistingWithdrawRequest(msg.sender, account, accountWithdraw.requestId);

        // Receive the requested amount of yield tokens from the approved vault.
        IERC20(yieldToken).transferFrom(msg.sender, address(this), yieldTokenAmount);

        requestId = _initiateWithdrawImpl(account, yieldTokenAmount, isForced, data);
        accountWithdraw.requestId = requestId;
        accountWithdraw.hasSplit = false;
        accountWithdraw.yieldTokenAmount = yieldTokenAmount;

        emit InitiateWithdrawRequest(account, isForced, yieldTokenAmount, requestId);
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeAndRedeemWithdrawRequest(
        address account,
        uint256 withdrawYieldTokenAmount
    ) external override onlyApprovedVault returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[msg.sender][account];
        if (accountWithdraw.requestId == 0) return (0, false);

        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, accountWithdraw);

        if (finalized) {
            // Allows for partial withdrawal of yield tokens
            if (withdrawYieldTokenAmount < accountWithdraw.yieldTokenAmount) {
                _splitPartialWithdrawRequest(accountWithdraw, tokensWithdrawn);
                tokensWithdrawn = tokensWithdrawn * withdrawYieldTokenAmount / accountWithdraw.yieldTokenAmount;
                accountWithdraw.yieldTokenAmount -= accountWithdraw.yieldTokenAmount;
            } else {
                require(accountWithdraw.yieldTokenAmount == withdrawYieldTokenAmount);
                delete s_accountWithdrawRequest[msg.sender][account];
            }

            IERC20(withdrawToken).safeTransfer(msg.sender, tokensWithdrawn);
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeRequestManual(
        address vault,
        address account
    ) external override returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[vault][account];
        if (accountWithdraw.requestId == 0) revert NoWithdrawRequest(vault, account);

        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, accountWithdraw);
        if (finalized) _splitPartialWithdrawRequest(accountWithdraw, tokensWithdrawn);
    }

    function _splitPartialWithdrawRequest(WithdrawRequest memory accountWithdraw, uint256 tokensWithdrawn) internal {
        // If the account has not split, we store the total tokens withdrawn in the split withdraw
        // request. When the account does exit, they will skip `_finalizeWithdrawImpl`
        if (!accountWithdraw.hasSplit) {
            s_splitWithdrawRequest[accountWithdraw.requestId] = SplitWithdrawRequest({
                totalYieldTokenAmount: accountWithdraw.yieldTokenAmount,
                totalWithdraw: tokensWithdrawn,
                finalized: true
            });

            accountWithdraw.hasSplit = true;
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function splitWithdrawRequest(
        address _from,
        address _to,
        uint256 yieldTokenAmount
    ) external override onlyApprovedVault {
        if (_from == _to) revert InvalidWithdrawRequestSplit();

        WithdrawRequest storage w = s_accountWithdrawRequest[msg.sender][_from];
        if (w.requestId == 0) return;

        // Create a new split withdraw request
        if (!w.hasSplit) {
            SplitWithdrawRequest memory s = s_splitWithdrawRequest[w.requestId];
            // Safety check to ensure that the split withdraw request is not active, split withdraw
            // requests are never deleted. This presumes that all withdraw request ids are unique.
            require(s.finalized == false && s.totalYieldTokenAmount == 0);
            s_splitWithdrawRequest[w.requestId].totalYieldTokenAmount = w.yieldTokenAmount;
        }

        // Ensure that no withdraw request gets overridden, the _to account always receives their withdraw
        // request in the account withdraw slot. All storage is updated prior to changes to the `w` storage
        // variable below.
        WithdrawRequest storage toWithdraw = s_accountWithdrawRequest[msg.sender][_to];
        if (toWithdraw.requestId != 0 && toWithdraw.requestId != w.requestId) {
            revert ExistingWithdrawRequest(msg.sender, _to, toWithdraw.requestId);
        }

        toWithdraw.requestId = w.requestId;
        toWithdraw.hasSplit = true;

        if (w.yieldTokenAmount < yieldTokenAmount) {
            // This should never occur given the checks below.
            revert InvalidWithdrawRequestSplit();
        } else if (w.yieldTokenAmount == yieldTokenAmount) {
            // If the resulting vault shares is zero, then delete the request. The _from account's
            // withdraw request is fully transferred to _to. In this case, the _to account receives
            // the full amount of the _from account's withdraw request.
            toWithdraw.yieldTokenAmount = toWithdraw.yieldTokenAmount + w.yieldTokenAmount;
            delete s_accountWithdrawRequest[msg.sender][_from];
        } else {
            // In this case, the amount of yield tokens is transferred from one account to the other.
            toWithdraw.yieldTokenAmount = toWithdraw.yieldTokenAmount + yieldTokenAmount;
            w.yieldTokenAmount = w.yieldTokenAmount - yieldTokenAmount;
            w.hasSplit = true;
        }

        // TODO: do we need to ensure that the _to account does not have a balance of vault shares?
    }

    /// @inheritdoc IWithdrawRequestManager
    function rescueTokens(
        address cooldownHolder, address token, address receiver, uint256 amount
    ) external override onlyOwner {
        ClonedCoolDownHolder(cooldownHolder).rescueTokens(IERC20(token), receiver, amount);
    }

    /// @notice Finalizes a withdraw request and updates the account required to determine how many
    /// tokens the account has a claim over.
    function _finalizeWithdraw(
        address account,
        WithdrawRequest memory w
    ) internal returns (uint256 tokensWithdrawn, bool finalized) {
        SplitWithdrawRequest memory s;
        if (w.hasSplit) {
            s = s_splitWithdrawRequest[w.requestId];

            // If the split request was already finalized in a different transaction
            // then return the values here and we can short circuit the withdraw impl
            if (s.finalized) {
                return (s.totalWithdraw * w.yieldTokenAmount / s.totalYieldTokenAmount, true);
            }
        }

        // These values are the total tokens claimed from the withdraw request, does not
        // account for potential splitting.
        (tokensWithdrawn, finalized) = _finalizeWithdrawImpl(account, w.requestId);

        if (w.hasSplit && finalized) {
            s.totalWithdraw = tokensWithdrawn;
            s.finalized = true;
            s_splitWithdrawRequest[w.requestId] = s;

            tokensWithdrawn = s.totalWithdraw * w.yieldTokenAmount / s.totalYieldTokenAmount;
        } else if (!finalized) {
            // No tokens claimed if not finalized
            require(tokensWithdrawn == 0);
        }
    }


    /// @notice Required implementation to begin the withdraw request
    /// @return requestId some identifier of the withdraw request
    function _initiateWithdrawImpl(
        address account,
        uint256 yieldTokenAmount,
        bool isForced,
        bytes calldata data
    ) internal virtual returns (uint256 requestId);

    /// @notice Required implementation to finalize the withdraw
    /// @return tokensWithdrawn total tokens claimed as a result of the withdraw, does not
    /// necessarily represent the tokens that go to the account if the request has been
    /// split due to liquidation
    /// @return finalized returns true if the withdraw has been finalized
    function _finalizeWithdrawImpl(address account, uint256 requestId) internal virtual returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice Required implementation to stake the deposit token to the yield token
    function _stakeTokens(address depositToken, uint256 amount, bytes calldata data) internal virtual;

    // function _getValueOfWithdrawRequest(
    //     uint256 requestId, uint256 totalVaultShares, uint256 stakeAssetPrice
    // ) internal virtual view returns (uint256);

    // function _getValueOfSplitFinalizedWithdrawRequest(
    //     WithdrawRequest memory w,
    //     SplitWithdrawRequest memory s,
    //     address borrowToken,
    //     address redeemToken
    // ) internal virtual view returns (uint256) {
    //     // If the borrow token and the withdraw token match, then there is no need to apply
    //     // an exchange rate at this point.
    //     if (borrowToken == redeemToken) {
    //         return (s.totalWithdraw * w.vaultShares) / s.totalVaultShares;
    //     } else {
    //         // Otherwise, apply the proper exchange rate
    //         (int256 rate, /* */) = Deployments.TRADING_MODULE.getOraclePrice(redeemToken, borrowToken);

    //         uint256 borrowPrecision = 10 ** TokenUtils.getDecimals(borrowToken);
    //         uint256 redeemPrecision = 10 ** TokenUtils.getDecimals(redeemToken);

    //         return (s.totalWithdraw * rate.toUint() * w.vaultShares * borrowPrecision) /
    //             (s.totalVaultShares * Constants.EXCHANGE_RATE_PRECISION * redeemPrecision);
    //     }
    // }

    // /// @notice Returns the value of a withdraw request in terms of the borrowed token. Used
    // /// to determine the collateral position of the vault.
    // function _calculateValueOfWithdrawRequest(
    //     WithdrawRequest memory w,
    //     uint256 stakeAssetPrice,
    //     address borrowToken,
    //     address redeemToken
    // ) internal view returns (uint256 borrowTokenValue) {
    //     if (w.requestId == 0) return 0;

    //     // If a withdraw request has split and is finalized, we know the fully realized value of
    //     // the withdraw request as a share of the total realized value.
    //     if (w.hasSplit) {
    //         SplitWithdrawRequest memory s = VaultStorage.getSplitWithdrawRequest()[w.requestId];
    //         if (s.finalized) {
    //             return _getValueOfSplitFinalizedWithdrawRequest(w, s, borrowToken, redeemToken);
    //         } else {
    //             uint256 totalValue = _getValueOfWithdrawRequest(w.requestId, s.totalVaultShares, stakeAssetPrice);
    //             // Scale the total value of the withdraw request to the account's share of the request
    //             return totalValue * w.vaultShares / s.totalVaultShares;
    //         }
    //     }

    //     return _getValueOfWithdrawRequest(w.requestId, w.vaultShares, stakeAssetPrice);
    // }

}