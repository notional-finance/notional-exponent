// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TradeType} from "../interfaces/ITradingModule.sol";

/// @notice Parameters for trades
struct TradeParams {
    /// @notice DEX ID
    uint16 dexId;
    /// @notice Trade type (i.e. Single/Batch)
    TradeType tradeType;
    /// @notice For dynamic trades, this field specifies the slippage percentage relative to
    /// the oracle price. For static trades, this field specifies the slippage limit amount.
    uint256 oracleSlippagePercentOrLimit;
    /// @notice DEX specific data
    bytes exchangeData;
}

/// @notice Deposit trade parameters
struct DepositTradeParams {
    /// @notice Amount of primary tokens to sell
    uint256 tradeAmount;
    /// @notice Trade parameters
    TradeParams tradeParams;
}

/// @notice Deposit parameters
struct DepositParams {
    /// @notice min pool claim for slippage control
    uint256 minPoolClaim;
    /// @notice DepositTradeParams or empty (single-sided entry)
    DepositTradeParams[] depositTrades;
}

/// @notice Redeem parameters
struct RedeemParams {
    /// @notice min amounts for slippage control
    uint256[] minAmounts;
    /// @notice Redemption trades or empty (single-sided exit)
    TradeParams[] redemptionTrades;
}

/// @notice Single-sided reinvestment trading parameters
struct SingleSidedRewardTradeParams {
    /// @notice Address of the token to sell (typically one of the reward tokens)
    address sellToken;
    /// @notice Address of the token to buy (typically one of the pool tokens)
    address buyToken;
    /// @notice Amount of tokens to sell
    uint256 amount;
    /// @notice Trade params
    TradeParams tradeParams;
}

/**
 * @notice Base contract for the SingleSidedLP strategy. This strategy deposits into an LP
 * pool given a single borrowed currency. Allows for users to trade via external exchanges
 * during entry and exit, but the general expected behavior is single sided entries and
 * exits. Inheriting contracts will fill in the implementation details for integration with
 * the external DEX pool.
 */
abstract contract AbstractSingleSidedLP is AbstractYieldStrategy {

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

    /// @notice Precision (i.e. 10 ** decimals) of the LP token.
    function POOL_PRECISION() internal view virtual returns (uint256);

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
    ) internal virtual returns (uint256 lpTokens);

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

    constructor(address _owner, address _asset, address _yieldToken, uint256 _feeRate, address _irm, uint256 _lltv)
        AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {}

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
    ) internal override virtual returns (uint256 yieldTokensMinted) {
        DepositParams memory params = abi.decode(depositData, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        amounts[PRIMARY_INDEX()] = assets;

        // If depositTrades are specified, then parts of the initial deposit are traded
        // for corresponding amounts of the other pool tokens via external exchanges. If
        // these amounts are not specified then the pool will just be joined single sided.
        // Deposit trades are not automatically enabled on vaults since the trading module
        // requires explicit permission for every token that can be sold by an address.
        if (params.depositTrades.length > 0) {
            (IERC20[] memory tokens, /* */) = TOKENS();
            // This is an external library call so the memory location of amounts is
            // different before and after the call.
            // amounts = StrategyUtils.executeDepositTrades(
            //     tokens,
            //     amounts,
            //     params.depositTrades,
            //     PRIMARY_INDEX()
            // );
        }

        yieldTokensMinted = _joinPoolAndStake(amounts, params.minPoolClaim);

        // Checks that the vault does not own too large of a portion of the pool. If this is the case,
        // single sided exits may have a detrimental effect on the liquidity.
        // uint256 maxPoolShare = VaultStorage.getStrategyVaultSettings().maxPoolShare;
        // uint256 maxSupplyThreshold = (_totalPoolSupply() * maxPoolShare) / Constants.VAULT_PERCENT_BASIS;
        // if (maxSupplyThreshold < state.totalPoolClaim)
        //     revert Errors.PoolShareTooHigh(state.totalPoolClaim, maxSupplyThreshold);

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
            (IERC20[] memory tokens, /* */) = TOKENS();
            // Redemption trades are not automatically enabled on vaults since the trading module
            // requires explicit permission for every token that can be sold by an address.
            // finalPrimaryBalance = StrategyUtils.executeRedemptionTrades(
            //     tokens,
            //     exitBalances,
            //     params.redemptionTrades,
            //     PRIMARY_INDEX()
            // );
        }

        // _updateAccountRewards({
        //     account: account,
        //     vaultShares: vaultShares,
        //     totalVaultSharesBefore: totalVaultSharesBefore,
        //     isMint: false
        // });
    }

    /************************************************************************
     * REWARD REINVESTMENT                                                  *
     * Methods used by bots to claim reward tokens and reinvest them as LP  *
     * tokens which are donated to all vault users.                         *
     ************************************************************************/

    // /// @notice Ensures that only whitelisted bots can reinvest rewards. Since rewards
    // /// are typically less liquid than pool tokens and lack oracles, reward reinvestment
    // /// is done using explicitly set slippage limits by the reinvestment bots. Reinvestment
    // /// will fail if the spot prices are not close to the oracle prices to ensure that
    // /// there is no front running the reinvestment.
    // function reinvestReward(
    //     SingleSidedRewardTradeParams[] calldata trades,
    //     uint256 minPoolClaim
    // ) external whenNotLocked onlyRole(REWARD_REINVESTMENT_ROLE) returns (
    //     address rewardToken,
    //     uint256 amountSold,
    //     uint256 poolClaimAmount
    // ) {
    //     // Will revert if spot prices are not in line with the oracle values
    //     _checkPriceAndCalculateValue();

    //     // Require one trade per token, if we do not want to buy any tokens at a
    //     // given index then the amount should be set to zero. This applies to pool
    //     // tokens like in the ComposableStablePool.
    //     require(trades.length == NUM_TOKENS());
    //     uint256[] memory amounts;
    //     // The sell token on all trades must be the same (checked inside executeRewardTrades) so
    //     // just validate here that the sellToken is a valid reward token (i.e. none of the tokens
    //     // used in the regular functioning of the vault).
    //     rewardToken = trades[0].sellToken;
    //     if (_isInvalidRewardToken(rewardToken)) revert Errors.InvalidRewardToken(rewardToken);
    //     (amountSold, amounts) = _executeRewardTrades(trades, rewardToken);

    //     poolClaimAmount = _joinPoolAndStake(amounts, minPoolClaim);

    //     // Increase LP token amount without minting additional vault shares
    //     StrategyVaultState memory state = VaultStorage.getStrategyVaultState();
    //     // Do not re-invest if there are no vault shares
    //     require(state.totalVaultSharesGlobal > 0);
    //     state.totalPoolClaim += poolClaimAmount;
    //     state.setStrategyVaultState();
    // }

    // function _executeRewardTrades(
    //     SingleSidedRewardTradeParams[] calldata trades,
    //     address rewardToken
    // ) internal returns (uint256 amountSold, uint256[] memory amounts) {
    //     (IERC20[] memory tokens, /* */) = TOKENS();
    //     (amounts, amountSold) = StrategyUtils.executeRewardTrades(
    //         tokens, trades, rewardToken, address(POOL_TOKEN())
    //     );
    // }

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