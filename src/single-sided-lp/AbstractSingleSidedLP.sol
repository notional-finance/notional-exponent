// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Trade, TradeType} from "../interfaces/ITradingModule.sol";
import {RewardManagerMixin} from "../rewards/RewardManagerMixin.sol";
import {
    IWithdrawRequestManager,
    WithdrawRequest,
    SplitWithdrawRequest,
    CannotInitiateWithdraw,
    ExistingWithdrawRequest
} from "../withdraws/IWithdrawRequestManager.sol";

struct TradeParams {
    uint256 tradeAmount;
    uint16 dexId;
    TradeType tradeType;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

/// @notice Deposit parameters
struct DepositParams {
    /// @notice min pool claim for slippage control
    uint256 minPoolClaim;
    /// @notice DepositTradeParams or empty (single-sided entry)
    TradeParams[] depositTrades;
}

/// @notice Redeem parameters
struct RedeemParams {
    /// @notice min amounts for slippage control
    uint256[] minAmounts;
    /// @notice Redemption trades or empty (single-sided exit)
    TradeParams[] redemptionTrades;
}

struct WithdrawParams {
    uint256[] minAmounts;
    bool isSingleSided;
    bytes[] withdrawData;
}

/**
 * @notice Base contract for the SingleSidedLP strategy. This strategy deposits into an LP
 * pool given a single borrowed currency. Allows for users to trade via external exchanges
 * during entry and exit, but the general expected behavior is single sided entries and
 * exits. Inheriting contracts will fill in the implementation details for integration with
 * the external DEX pool.
 */
abstract contract AbstractSingleSidedLP is RewardManagerMixin {
    error PoolShareTooHigh(uint256 poolClaim, uint256 maxSupplyThreshold);

    // TODO: this is storage....
    uint256 public maxPoolShare;
    IWithdrawRequestManager[] public withdrawRequestManagers;

    uint256 internal constant POOL_SHARE_BASIS = 1e18;
    uint256 internal constant MAX_TOKENS = 5;
    uint8 internal constant NOT_FOUND = type(uint8).max;

    /************************************************************************
     * VIRTUAL FUNCTIONS                                                    *
     * These virtual functions are used to isolate implementation specific  *
     * behavior.                                                            *
     ************************************************************************/

    /// @notice Total number of tokens held by the LP token
    function NUM_TOKENS() internal view virtual returns (uint256);

    /// @notice Addresses of tokens held and decimal places of each token. ETH will always be
    /// recorded in this array as Deployments.ETH_Address
    function TOKENS() public view virtual returns (IERC20[] memory, uint8[] memory decimals);

    /// @notice Index of the TOKENS() array that refers to the primary borrowed currency by the
    /// leveraged vault. All valuations are done in terms of this currency.
    function PRIMARY_INDEX() internal view virtual returns (uint256);

    /// @notice Called once during initialization to set the initial token approvals.
    function _initialApproveTokens() internal virtual;

    // /// @notice Called to claim reward tokens
    // function _rewardPoolStorage() internal view virtual returns (RewardPoolStorage memory);

    /// @notice Implementation specific wrapper for joining a pool with the given amounts. Will also
    /// stake on the relevant booster protocol.
    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal virtual;

    /// @notice Implementation specific wrapper for unstaking from the booster protocol and withdrawing
    /// funds from the LP pool
    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal virtual returns (uint256[] memory exitBalances);

    /// @notice Returns the total supply of the pool token. Is a virtual function because
    /// ComposableStablePools use a "virtual supply" and a different method must be called
    /// to get the actual total supply.
    function _totalPoolSupply() internal view virtual returns (uint256) {
        return IERC20(yieldToken).totalSupply();
    }

    /************************************************************************
     * CLASS FUNCTIONS                                                      *
     * Below are class functions that represent the base implementation     *
     * of the Single Sided LP strategy.                                     *
     ************************************************************************/

    constructor(
        uint256 _maxPoolShare,
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager
    ) RewardManagerMixin(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager) {
        maxPoolShare = _maxPoolShare;
    }

    /************************************************************************
     * USER FUNCTIONS                                                       *
     * These functions are called during normal usage of the vault.         *
     * They allow for deposits and redemptions from the vault as well as a  *
     * valuation check that is used by Notional to determine if the user is *
     * properly collateralized.                                             *
     ************************************************************************/

    function requestIdsForAccount(address account) public view returns (WithdrawRequest[] memory requests, bool hasPendingRequest) {
        requests = new WithdrawRequest[](withdrawRequestManagers.length);

        for (uint256 i; i < withdrawRequestManagers.length; i++) {
            (requests[i], /* */) = withdrawRequestManagers[i].getWithdrawRequest(address(this), account);
            hasPendingRequest = hasPendingRequest || requests[i].requestId != 0;
        }
    }

    function _mintYieldTokens(
        uint256 assets,
        address receiver,
        bytes memory depositData
    ) internal override virtual {
        DepositParams memory params = abi.decode(depositData, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        amounts[PRIMARY_INDEX()] = assets;
        (/* */, bool hasPendingRequest) = requestIdsForAccount(receiver);
        if (hasPendingRequest) revert("Existing Withdraw Request");

        // If depositTrades are specified, then parts of the initial deposit are traded
        // for corresponding amounts of the other pool tokens via external exchanges. If
        // these amounts are not specified then the pool will just be joined single sided.
        // Deposit trades are not automatically enabled on vaults since the trading module
        // requires explicit permission for every token that can be sold by an address.
        if (params.depositTrades.length > 0) {
            // NOTE: amounts is modified in place
            _executeDepositTrades(amounts, params.depositTrades);
        }

        _joinPoolAndStake(amounts, params.minPoolClaim);

        // Checks that the vault does not own too large of a portion of the pool. If this is the case,
        // single sided exits may have a detrimental effect on the liquidity.
        uint256 maxSupplyThreshold = (_totalPoolSupply() * maxPoolShare) / POOL_SHARE_BASIS;
        uint256 poolClaim = _getYieldTokenBalance();
        if (maxSupplyThreshold < poolClaim) revert PoolShareTooHigh(poolClaim, maxSupplyThreshold);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bytes memory redeemData
    ) internal override virtual returns (uint256 yieldTokensBurned, bool wasEscrowed) {
        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
        (WithdrawRequest[] memory requests, bool hasPendingRequest) = requestIdsForAccount(sharesOwner);

        // Returns the amount of each token that has been withdrawn from the pool.
        uint256[] memory exitBalances;
        bool isSingleSided = params.redemptionTrades.length == 0;
        if (hasPendingRequest) {
            // Attempt to withdraw all pending requests
            exitBalances = _withdrawPendingRequests(requests, sharesOwner, sharesToRedeem);
            wasEscrowed = true;
        } else {
            yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            exitBalances = _unstakeAndExitPool(yieldTokensBurned, params.minAmounts, isSingleSided);
            wasEscrowed = false;
        }

        if (!isSingleSided) {
            // If not a single sided trade, will execute trades back to the primary token on
            // external exchanges. This method will execute EXACT_IN trades to ensure that
            // all of the balance in the other tokens is sold for primary.
            // Redemption trades are not automatically enabled on vaults since the trading module
            // requires explicit permission for every token that can be sold by an address.
            _executeRedemptionTrades(exitBalances, params.redemptionTrades);
        }
    }

    /// @dev Trades the amount of primary token into other secondary tokens prior to entering a pool.
    function _executeDepositTrades(
        uint256[] memory amounts,
        TradeParams[] memory depositTrades
    ) internal {
        (IERC20[] memory tokens, /* */) = TOKENS();
        address primaryToken = address(tokens[PRIMARY_INDEX()]);
        Trade memory trade;

        for (uint256 i; i < amounts.length; i++) {
            if (i == PRIMARY_INDEX()) continue;
            TradeParams memory t = depositTrades[i];

            if (t.tradeAmount > 0) {
                trade = Trade({
                    tradeType: t.tradeType,
                    sellToken: primaryToken,
                    buyToken: address(tokens[i]),
                    amount: t.tradeAmount,
                    limit: t.minPurchaseAmount,
                    deadline: block.timestamp,
                    exchangeData: t.exchangeData
                });
                // Always selling the primaryToken and buying the secondary token.
                (uint256 amountSold, uint256 amountBought) = _executeTrade(trade, t.dexId);

                amounts[i] = amountBought;
                // Will revert on underflow if over-selling the primary borrowed
                amounts[PRIMARY_INDEX()] -= amountSold;
            }
        }
    }

    /// @dev Trades the amount of secondary tokens into the primary token after exiting a pool.
    function _executeRedemptionTrades(
        uint256[] memory exitBalances,
        TradeParams[] memory redemptionTrades
    ) internal returns (uint256 finalPrimaryBalance) {
        (IERC20[] memory tokens, /* */) = TOKENS();
        address primaryToken = address(tokens[PRIMARY_INDEX()]);

        for (uint256 i; i < exitBalances.length; i++) {
            if (i == PRIMARY_INDEX()) {
                finalPrimaryBalance += exitBalances[i];
                continue;
            }

            TradeParams memory t = redemptionTrades[i];
            // Always sell the entire exit balance to the primary token
            if (exitBalances[i] > 0) {
                Trade memory trade = Trade({
                    tradeType: t.tradeType,
                    sellToken: address(tokens[i]),
                    buyToken: primaryToken,
                    amount: exitBalances[i],
                    limit: t.minPurchaseAmount,
                    deadline: block.timestamp,
                    exchangeData: t.exchangeData
                });
                (/* */, uint256 amountBought) = _executeTrade(trade, t.dexId);

                finalPrimaryBalance += amountBought;
            }
        }
    }

    function _checkReentrancyContext() internal virtual;

    function _preLiquidation(address liquidateAccount, address liquidator) internal override returns (uint256 maxLiquidateShares) {
        _checkReentrancyContext();
        return super._preLiquidation(liquidateAccount, liquidator);
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal returns (uint256[] memory requestIds) {
        uint256 sharesHeld = balanceOfShares(account);
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld, yieldTokenAmount);
        WithdrawParams memory params = abi.decode(data, (WithdrawParams));

        uint256[] memory exitBalances = _unstakeAndExitPool(yieldTokenAmount, params.minAmounts, params.isSingleSided);
        requestIds = new uint256[](exitBalances.length);
        for (uint256 i; i < exitBalances.length; i++) {
            if (exitBalances[i] == 0) continue;

            requestIds[i] = withdrawRequestManagers[i].initiateWithdraw({
                account: account,
                yieldTokenAmount: exitBalances[i],
                sharesAmount: sharesHeld,
                isForced: isForced,
                data: params.withdrawData[i]
            });
        }
    }

    function _withdrawPendingRequests(
        WithdrawRequest[] memory requests,
        address sharesOwner,
        uint256 sharesToRedeem
    ) internal returns (uint256[] memory exitBalances) {
        uint256 totalShares = balanceOfShares(sharesOwner);
        exitBalances = new uint256[](requests.length);

        for (uint256 i; i < requests.length; i++) {
            uint256 yieldTokensBurned = uint256(requests[i].yieldTokenAmount) * sharesToRedeem / totalShares;
            bool finalized;
            (exitBalances[i], finalized) = withdrawRequestManagers[i].finalizeAndRedeemWithdrawRequest({
                account: sharesOwner, withdrawYieldTokenAmount: yieldTokensBurned, sharesToBurn: sharesToRedeem
            });
            require(finalized, "Withdraw request not finalized");
        }
    }

    /************************************************************************
     * EMERGENCY EXIT                                                       *
     * In case of an emergency, will allow a whitelisted guardian to exit   *
     * funds on the vault and locks the vault from further usage. The owner *
     * can restore funds to the LP pool and reinstate vault usage. If the   *
     * vault cannot be fully restored after an exit, the vault will need to *
     * be upgraded and unwound manually to ensure that debts are repaid and *
     * users can withdraw their funds.                                      *
     ************************************************************************/

    // /// @notice Allows the emergency exit role to trigger an emergency exit on the vault.
    // /// In this situation, the `claimToExit` is withdrawn proportionally to the underlying
    // /// tokens and held on the vault. The vault is locked so that no entries, exits or
    // /// valuations of vaultShares can be performed.
    // /// @param claimToExit if this is set to zero, the entire pool claim is withdrawn
    // function emergencyExit(
    //     uint256 claimToExit, bytes calldata /* data */
    // ) external override onlyRole(EMERGENCY_EXIT_ROLE) {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     if (claimToExit == 0 || claimToExit > state.totalPoolClaim) claimToExit = state.totalPoolClaim;

    //     // By setting min amounts to zero, we will accept whatever tokens come from the pool
    //     // in a proportional exit. Front running will not have an effect since no trading will
    //     // occur during a proportional exit.
    //     uint256[] memory exitBalances = _unstakeAndExitPool(claimToExit, new uint256[](NUM_TOKENS()), false);

    //     state.totalPoolClaim = state.totalPoolClaim - claimToExit;
    //     state.setStrategyVaultState();

    //     emit EmergencyExit(claimToExit, exitBalances);
    //     _lockVault();
    // }

    // /// @notice Restores withdrawn tokens from emergencyExit back into the vault proportionally.
    // /// Unlocks the vault after restoration so that normal functionality is restored.
    // /// @param minPoolClaim slippage limit to prevent front running
    // /// @param data the owner will pass in an array of amounts for the pool to re-enter the vault.
    // /// This prevents any front running or manipulation of the vault balances.
    // function restoreVault(
    //     uint256 minPoolClaim, bytes calldata data
    // ) external override whenLocked onlyNotionalOwner {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();

    //     uint256[] memory amounts = abi.decode(data, (uint256[]));

    //     // No trades are specified so this joins proportionally using the
    //     // amounts specified.
    //     uint256 poolTokens = _joinPoolAndStake(amounts, minPoolClaim);

    //     state.totalPoolClaim = state.totalPoolClaim + poolTokens;
    //     state.setStrategyVaultState();

    //     _unlockVault();
    // }

    // /// @notice This is a trusted method that can only be executed while the vault is locked. The owner
    // /// may trade tokens prior to restoring the vault if the tokens withdrawn are imbalanced. In this
    // /// method, one of the tokens held is sold for other tokens that go into the pool. If multiple tokens
    // /// need to be sold then this method will be called multiple times prior to restoreVault.
    // function tradeTokensBeforeRestore(
    //     SingleSidedRewardTradeParams[] calldata trades
    // ) external override whenLocked onlyNotionalOwner {
    //     // The sell token on all trades must be the same (checked inside executeRewardTrades). In this
    //     // method we do not validate the sell token so we can sell any of the tokens held on the vault
    //     // in exchange for any other token that goes into the pool.
    //     _executeRewardTrades(trades, trades[0].sellToken);
    // }
}