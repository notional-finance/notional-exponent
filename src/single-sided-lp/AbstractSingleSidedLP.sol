// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Trade, TradeType} from "../interfaces/ITradingModule.sol";

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

/**
 * @notice Base contract for the SingleSidedLP strategy. This strategy deposits into an LP
 * pool given a single borrowed currency. Allows for users to trade via external exchanges
 * during entry and exit, but the general expected behavior is single sided entries and
 * exits. Inheriting contracts will fill in the implementation details for integration with
 * the external DEX pool.
 */
abstract contract AbstractSingleSidedLP is AbstractYieldStrategy {
    error PoolShareTooHigh(uint256 poolClaim, uint256 maxSupplyThreshold);

    // TODO: this is storage....
    uint256 public maxPoolShare;

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

    /// @notice Called during reward reinvestment to validate that the token being sold is not one
    /// of the tokens that is required for the vault to function properly (i.e. one of the pool tokens
    /// or any of the reward booster tokens).
    function _isInvalidRewardToken(address token) internal view virtual returns (bool);

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

    constructor(uint256 _maxPoolShare, address _owner, address _asset, address _yieldToken, uint256 _feeRate, address _irm, uint256 _lltv)
        AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {
        maxPoolShare = _maxPoolShare;
    }

    /************************************************************************
     * EXTERNAL VIEW FUNCTIONS                                              *
     ************************************************************************/

    // /// @notice Returns basic information about the vault for use in the user interface.
    // function getStrategyVaultInfo() external view override returns (SingleSidedLPStrategyVaultInfo memory) {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     StrategyVaultSettings memory settings = VaultStorage.getStrategyVaultSettings();

    //     return SingleSidedLPStrategyVaultInfo({
    //         pool: address(POOL_TOKEN()),
    //         singleSidedTokenIndex: uint8(PRIMARY_INDEX()),
    //         totalLPTokens: state.totalPoolClaim,
    //         totalVaultShares: state.totalVaultSharesGlobal,
    //         maxPoolShare: settings.maxPoolShare,
    //         oraclePriceDeviationLimitPercent: settings.oraclePriceDeviationLimitPercent
    //     });
    // }

    // /// @notice Returns the current locked status of the vault
    // function isLocked() public view returns (bool) {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     return _hasFlag(state.flags, FLAG_LOCKED);
    // }

    /************************************************************************
     * ADMIN FUNCTIONS                                                      *
     * Administrative functions to set settings and initialize the vault.   *
     * These methods are only callable by the Notional owner.               *
     ************************************************************************/

    // /// @notice Updates the vault settings include the maximum oracle deviation limit and the
    // /// maximum percent of the LP pool that the vault can hold.
    // function setStrategyVaultSettings(StrategyVaultSettings calldata settings) external onlyNotionalOwner {
    //     // Validation occurs inside this method
    //     VaultStorage.setStrategyVaultSettings(settings);
    // }

    // // @notice need to be called with `upgradeToAndCall` when upgrading already deployed vaults
    // // does not need to be called on any upgrade after that
    // function setRewardPoolStorage() public onlyNotionalOwner {
    //     VaultStorage.setRewardPoolStorage(_rewardPoolStorage());
    // }
    // /// @notice Called to initialize the vault and set the initial approvals. All of the other vault
    // /// parameters are set via immutable parameters already.
    // function initialize(InitParams calldata params) external override initializer onlyNotionalOwner {
    //     // Initialize the base vault
    //     __INIT_VAULT(params.name, params.borrowCurrencyId);

    //     // Settings are validated in setStrategyVaultSettings
    //     VaultStorage.setStrategyVaultSettings(params.settings);

    //     _initialApproveTokens();
    //     VaultStorage.setRewardPoolStorage(_rewardPoolStorage());
    // }

    /************************************************************************
     * USER FUNCTIONS                                                       *
     * These functions are called during normal usage of the vault.         *
     * They allow for deposits and redemptions from the vault as well as a  *
     * valuation check that is used by Notional to determine if the user is *
     * properly collateralized.                                             *
     ************************************************************************/

    /// @notice This is a virtual function called by BaseStrategyVault which ensures that
    /// this method is only called by Notional after an initial borrow has been made and
    /// the deposit amount has been transferred to this vault. Will join the LP pool with
    /// the funds given and then return the total vault shares minted.
    function _mintYieldTokens(
        uint256 assets,
        address receiver,
        bytes memory depositData
    ) internal override virtual {
        DepositParams memory params = abi.decode(depositData, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        amounts[PRIMARY_INDEX()] = assets;

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

        // _updateAccountRewards({
        //     account: account,
        //     vaultShares: vaultShares,
        //     totalVaultSharesBefore: totalVaultSharesBefore,
        //     isMint: true
        // });
    }

    /// @notice This is a virtual function called by BaseStrategyVault which ensures that
    /// this method is only called by Notional after an initial position has been made. Will
    /// withdraw the LP tokens from the pool, either single sided or proportionally. On a
    /// proportional exit, will trade all the tokens back to the primary in order to exit the pool.
    function _redeemYieldTokens(
        uint256 yieldTokensToRedeem,
        address sharesOwner,
        bytes memory redeemData
    ) internal override virtual {
        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));

        bool isSingleSided = params.redemptionTrades.length == 0;
        // Returns the amount of each token that has been withdrawn from the pool.
        uint256[] memory exitBalances = _unstakeAndExitPool(yieldTokensToRedeem, params.minAmounts, isSingleSided);
        if (!isSingleSided) {
            // If not a single sided trade, will execute trades back to the primary token on
            // external exchanges. This method will execute EXACT_IN trades to ensure that
            // all of the balance in the other tokens is sold for primary.
            // Redemption trades are not automatically enabled on vaults since the trading module
            // requires explicit permission for every token that can be sold by an address.
            _executeRedemptionTrades(exitBalances, params.redemptionTrades);
        }

        // _updateAccountRewards({
        //     account: account,
        //     vaultShares: vaultShares,
        //     totalVaultSharesBefore: totalVaultSharesBefore,
        //     isMint: false
        // });
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

    /************************************************************************
     * EMERGENCY EXIT                                                       *
     * In case of an emergency, will allow a whitelisted guardian to exit   *
     * funds on the vault and locks the vault from further usage. The owner *
     * can restore funds to the LP pool and reinstate vault usage. If the   *
     * vault cannot be fully restored after an exit, the vault will need to *
     * be upgraded and unwound manually to ensure that debts are repaid and *
     * users can withdraw their funds.                                      *
     ************************************************************************/

    // /// @notice Allows the function to execute only when the vault is not locked
    // modifier whenNotLocked() {
    //     if (isLocked()) revert Errors.VaultLocked();
    //     _;
    // }

    // /// @notice Allows the function to execute only when the vault is locked
    // modifier whenLocked() {
    //     if (!isLocked()) revert Errors.VaultNotLocked();
    //     _;
    // }

    // /// @notice Checks if a flag bit is set
    // function _hasFlag(uint32 flags, uint32 flagID) private pure returns (bool) {
    //     return (flags & flagID) == flagID;
    // }

    // /// @notice Locks the vault, preventing deposits and redemptions. Used during
    // /// emergency exit
    // function _lockVault() internal {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     // Set locked flag
    //     state.flags = state.flags | FLAG_LOCKED;
    //     VaultStorage.setStrategyVaultState(state);
    //     emit VaultLocked();
    // }

    // /// @notice Unlocks the vault, called during restore vault.
    // function _unlockVault() internal {
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     // Remove locked flag
    //     state.flags = state.flags & ~FLAG_LOCKED;
    //     VaultStorage.setStrategyVaultState(state);
    //     emit VaultUnlocked();
    // }

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

    // function _updateAccountRewards(
    //     address account,
    //     uint256 vaultShares,
    //     uint256 totalVaultSharesBefore,
    //     bool isMint
    // ) internal {
    //     (bool success, /* */) = Deployments.VAULT_REWARDER_LIB.delegatecall(abi.encodeWithSelector(
    //         VaultRewarderLib.updateAccountRewards.selector,
    //         account, vaultShares, totalVaultSharesBefore, isMint
    //     ));
    //     require(success);
    // }
}