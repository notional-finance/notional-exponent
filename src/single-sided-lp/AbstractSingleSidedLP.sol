// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

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
import {TokenUtils} from "../utils/TokenUtils.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";
import "../utils/Errors.sol";

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
    bytes[] withdrawData;
}

interface ILPLib {
    function initialApproveTokens() external;
    function joinPoolAndStake(uint256[] memory amounts, uint256 minPoolClaim) external;
    function unstakeAndExitPool(uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided) external returns (uint256[] memory exitBalances);

    function getWithdrawRequestValue(address account, address asset, uint256 shares) external view returns (uint256 totalValue);

    function finalizeAndRedeemWithdrawRequest(
        address sharesOwner,
        uint256 sharesToRedeem,
        uint256 totalShares
    ) external returns (uint256[] memory exitBalances, IERC20[] memory withdrawTokens);

    function initiateWithdraw(
        address account,
        bool isForced,
        uint256 sharesHeld,
        uint256[] calldata exitBalances,
        bytes[] calldata withdrawData
    ) external returns (uint256[] memory requestIds);
}

/**
 * @notice Base contract for the SingleSidedLP strategy. This strategy deposits into an LP
 * pool given a single borrowed currency. Allows for users to trade via external exchanges
 * during entry and exit, but the general expected behavior is single sided entries and
 * exits. Inheriting contracts will fill in the implementation details for integration with
 * the external DEX pool.
 */
abstract contract AbstractSingleSidedLP is RewardManagerMixin {
    using TokenUtils for IERC20;

    error PoolShareTooHigh(uint256 poolClaim, uint256 maxSupplyThreshold);

    mapping(address => bool) public hasPendingWithdraw;
    uint256 immutable MAX_POOL_SHARE;
    address internal immutable LP_LIB;

    /************************************************************************
     * VIRTUAL FUNCTIONS                                                    *
     * These virtual functions are used to isolate implementation specific  *
     * behavior.                                                            *
     ************************************************************************/

    /// @notice Total number of tokens held by the LP token
    function NUM_TOKENS() internal view virtual returns (uint256);

    /// @notice Addresses of tokens held and decimal places of each token. ETH will always be
    /// recorded in this array as Deployments.ETH_Address
    function TOKENS() internal view virtual returns (IERC20[] memory);

    /// @notice Index of the TOKENS() array that refers to the primary borrowed currency by the
    /// leveraged vault. All valuations are done in terms of this currency.
    function PRIMARY_INDEX() internal view virtual returns (uint256);

    /// @notice Returns the total supply of the pool token. Is a virtual function because
    /// ComposableStablePools use a "virtual supply" and a different method must be called
    /// to get the actual total supply.
    function _totalPoolSupply() internal view virtual returns (uint256);

    function _checkReentrancyContext() internal virtual;

    /// @notice Called once during initialization to set the initial token approvals.
    function _initialApproveTokens() internal virtual {
        (bool success, /* */) = LP_LIB.delegatecall(abi.encodeWithSelector(ILPLib.initialApproveTokens.selector));
        require(success);
    }

    /// @notice Implementation specific wrapper for joining a pool with the given amounts. Will also
    /// stake on the relevant booster protocol.
    function _joinPoolAndStake(
        uint256[] memory amounts, uint256 minPoolClaim
    ) internal virtual {
        (bool success, /* */) = LP_LIB.delegatecall(
            abi.encodeWithSelector(ILPLib.joinPoolAndStake.selector, amounts, minPoolClaim)
        );
        require(success);
    }

    /// @notice Implementation specific wrapper for unstaking from the booster protocol and withdrawing
    /// funds from the LP pool
    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory minAmounts, bool isSingleSided
    ) internal virtual returns (uint256[] memory exitBalances) {
        (bool success, bytes memory result) = LP_LIB.delegatecall(
            abi.encodeWithSelector(ILPLib.unstakeAndExitPool.selector, poolClaim, minAmounts, isSingleSided)
        );
        require(success);
        exitBalances = abi.decode(result, (uint256[]));
    }

    /************************************************************************
     * CLASS FUNCTIONS                                                      *
     * Below are class functions that represent the base implementation     *
     * of the Single Sided LP strategy.                                     *
     ************************************************************************/

    constructor(
        uint256 _maxPoolShare,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager,
        uint8 _yieldTokenDecimals
    ) RewardManagerMixin( _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager, _yieldTokenDecimals) {
        MAX_POOL_SHARE = _maxPoolShare;
    }

    function _initialize(bytes calldata data) internal override {
        super._initialize(data);
        _initialApproveTokens();
    }

    /************************************************************************
     * USER FUNCTIONS                                                       *
     * These functions are called during normal usage of the vault.         *
     * They allow for deposits and redemptions from the vault as well as a  *
     * valuation check that is used by Notional to determine if the user is *
     * properly collateralized.                                             *
     ************************************************************************/

    function _mintYieldTokens(
        uint256 assets,
        address receiver,
        bytes memory depositData
    ) internal override {
        DepositParams memory params = abi.decode(depositData, (DepositParams));
        uint256[] memory amounts = new uint256[](NUM_TOKENS());
        if (hasPendingWithdraw[receiver]) revert CannotEnterPosition();

        // If depositTrades are specified, then parts of the initial deposit are traded
        // for corresponding amounts of the other pool tokens via external exchanges. If
        // these amounts are not specified then the pool will just be joined single sided.
        // Deposit trades are not automatically enabled on vaults since the trading module
        // requires explicit permission for every token that can be sold by an address.
        if (params.depositTrades.length > 0) {
            // NOTE: amounts is modified in place
            _executeDepositTrades(assets, amounts, params.depositTrades);
        } else {
            // This is a single sided entry, will revert if index is out of bounds
            amounts[PRIMARY_INDEX()] = assets;
        }

        _joinPoolAndStake(amounts, params.minPoolClaim);

        _checkPoolShare();
    }

    function _checkPoolShare() internal view virtual {
        // Checks that the vault does not own too large of a portion of the pool. If this is the case,
        // single sided exits may have a detrimental effect on the liquidity.
        uint256 maxSupplyThreshold = (_totalPoolSupply() * MAX_POOL_SHARE) / RATE_PRECISION;
        // This is incumbent on a 1-1 ratio between the lpToken and the yieldToken, if that is not the
        // case then this function must be overridden.
        uint256 poolClaim = yieldTokenBalance();
        if (maxSupplyThreshold < poolClaim) revert PoolShareTooHigh(poolClaim, maxSupplyThreshold);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bytes memory redeemData
    ) internal override returns (bool wasEscrowed) {
        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));

        // Returns the amount of each token that has been withdrawn from the pool.
        uint256[] memory exitBalances;
        bool isSingleSided;
        IERC20[] memory tokens;
        if (hasPendingWithdraw[sharesOwner]) {
            // Attempt to withdraw all pending requests
            (exitBalances, tokens) = _withdrawPendingRequests(sharesOwner, sharesToRedeem);
            // If there are pending requests, then we are not single sided by definition
            isSingleSided = false;
            wasEscrowed = true;
        } else {
            isSingleSided = params.redemptionTrades.length == 0;
            uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            exitBalances = _unstakeAndExitPool(yieldTokensBurned, params.minAmounts, isSingleSided);
            tokens = TOKENS();
            wasEscrowed = false;
        }

        if (!isSingleSided) {
            // If not a single sided trade, will execute trades back to the primary token on
            // external exchanges. This method will execute EXACT_IN trades to ensure that
            // all of the balance in the other tokens is sold for primary.
            // Redemption trades are not automatically enabled on vaults since the trading module
            // requires explicit permission for every token that can be sold by an address.
            _executeRedemptionTrades(tokens, exitBalances, params.redemptionTrades);
        }
    }

    /// @dev Trades the amount of primary token into other secondary tokens prior to entering a pool.
    function _executeDepositTrades(
        uint256 assets,
        uint256[] memory amounts,
        TradeParams[] memory depositTrades
    ) internal {
        IERC20[] memory tokens = TOKENS();
        Trade memory trade;
        uint256 assetRemaining = assets;

        for (uint256 i; i < amounts.length; i++) {
            if (i == PRIMARY_INDEX()) continue;
            TradeParams memory t = depositTrades[i];

            if (t.tradeAmount > 0) {
                trade = Trade({
                    tradeType: t.tradeType,
                    sellToken: address(asset),
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
                assetRemaining -= amountSold;
            }
        }

        if (PRIMARY_INDEX() < amounts.length) {
            amounts[PRIMARY_INDEX()] = assetRemaining;
        } else {
            require(assetRemaining == 0, "Asset remaining");
        }
    }

    /// @dev Trades the amount of secondary tokens into the primary token after exiting a pool.
    function _executeRedemptionTrades(
        IERC20[] memory tokens,
        uint256[] memory exitBalances,
        TradeParams[] memory redemptionTrades
    ) internal returns (uint256 finalPrimaryBalance) {
        for (uint256 i; i < exitBalances.length; i++) {
            if (address(tokens[i]) == address(asset)) {
                finalPrimaryBalance += exitBalances[i];
                continue;
            }

            TradeParams memory t = redemptionTrades[i];
            // Always sell the entire exit balance to the primary token
            if (exitBalances[i] > 0) {
                Trade memory trade = Trade({
                    tradeType: t.tradeType,
                    sellToken: address(tokens[i]),
                    buyToken: address(asset),
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

    function _preLiquidation(address liquidateAccount, address liquidator) internal override returns (uint256 maxLiquidateShares) {
        _checkReentrancyContext();
        return super._preLiquidation(liquidateAccount, liquidator);
    }

    function initiateWithdraw(bytes calldata data) external returns (uint256[] memory requestIds) {
        requestIds = _initiateWithdraw({account: msg.sender, isForced: false, data: data});

        // Can only initiate a withdraw if health factor remains positive
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(msg.sender);
        if (borrowed > maxBorrow) revert CannotInitiateWithdraw(msg.sender);
    }

    function forceWithdraw(address account, bytes calldata data) external returns (uint256[] memory requestIds) {
        // TODO: who can do this?
        requestIds = _initiateWithdraw({account: account, isForced: true, data: data});
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal returns (uint256[] memory requestIds) {
        uint256 sharesHeld = balanceOfShares(account);
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld);
        WithdrawParams memory params = abi.decode(data, (WithdrawParams));

        // Ensure that user cannot re-initiate a withdraw
        if (hasPendingWithdraw[account]) revert CannotInitiateWithdraw(account);
        hasPendingWithdraw[account] = true;

        uint256[] memory exitBalances = _unstakeAndExitPool({
            poolClaim: yieldTokenAmount,
            minAmounts: params.minAmounts,
            // When initiating a withdraw, we always exit proportionally
            isSingleSided: false
        });

        (bool success, bytes memory result) = LP_LIB.delegatecall(
            abi.encodeWithSelector(ILPLib.initiateWithdraw.selector, account, isForced, sharesHeld, exitBalances, params.withdrawData)
        );
        require(success);
        requestIds = abi.decode(result, (uint256[]));
    }

    function _withdrawPendingRequests(
        address sharesOwner,
        uint256 sharesToRedeem
    ) internal returns (uint256[] memory exitBalances, IERC20[] memory tokens) {
        uint256 totalShares = balanceOfShares(sharesOwner);

        (bool success, bytes memory result) = LP_LIB.delegatecall(
            abi.encodeWithSelector(ILPLib.finalizeAndRedeemWithdrawRequest.selector, sharesOwner, sharesToRedeem, totalShares)
        );
        require(success);
        (exitBalances, tokens) = abi.decode(result, (uint256[], IERC20[]));
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0) && hasPendingWithdraw[t_CurrentAccount]) {
            return ILPLib(LP_LIB).getWithdrawRequestValue(t_CurrentAccount, asset, shares);
        }

        return super.convertToAssets(shares);
    }
}

abstract contract BaseLPLib is ILPLib {
    using TokenUtils for IERC20;

    function TOKENS() internal view virtual returns (IERC20[] memory);

    function getWithdrawRequestValue(
        address account,
        address asset,
        uint256 shares
    ) external view returns (uint256 totalValue) {
        IERC20[] memory tokens = TOKENS();

        for (uint256 i; i < tokens.length; i++) {
            IWithdrawRequestManager manager = ADDRESS_REGISTRY.getWithdrawRequestManager(msg.sender, address(tokens[i]));
            (/* */, uint256 value) = manager.getWithdrawRequestValue(msg.sender, account, asset, shares);
            totalValue += value;
        }
    }

    function initiateWithdraw(
        address account,
        bool isForced,
        uint256 sharesHeld,
        uint256[] calldata exitBalances,
        bytes[] calldata withdrawData
    ) external override returns (uint256[] memory requestIds) {
        IERC20[] memory tokens = TOKENS();

        requestIds = new uint256[](exitBalances.length);
        for (uint256 i; i < exitBalances.length; i++) {
            if (exitBalances[i] == 0) continue;
            IWithdrawRequestManager manager = ADDRESS_REGISTRY.getWithdrawRequestManager(address(this), address(tokens[i]));

            tokens[i].checkApprove(address(manager), exitBalances[i]);
            requestIds[i] = manager.initiateWithdraw({
                account: account,
                yieldTokenAmount: exitBalances[i],
                sharesAmount: sharesHeld,
                isForced: isForced,
                data: withdrawData[i]
            });
        }
    }

    function finalizeAndRedeemWithdrawRequest(
        address sharesOwner,
        uint256 sharesToRedeem,
        uint256 totalShares
    ) external override returns (uint256[] memory exitBalances, IERC20[] memory withdrawTokens) {
        IERC20[] memory tokens = TOKENS();

        exitBalances = new uint256[](tokens.length);
        withdrawTokens = new IERC20[](tokens.length);

        WithdrawRequest memory request;
        for (uint256 i; i < tokens.length; i++) {
            IWithdrawRequestManager manager = ADDRESS_REGISTRY.getWithdrawRequestManager(address(this), address(tokens[i]));
            (request, /* */) = manager.getWithdrawRequest(address(this), sharesOwner);

            uint256 yieldTokensBurned = uint256(request.yieldTokenAmount) * sharesToRedeem / totalShares;
            bool finalized;
            (exitBalances[i], finalized) = manager.finalizeAndRedeemWithdrawRequest({
                account: sharesOwner, withdrawYieldTokenAmount: yieldTokensBurned, sharesToBurn: sharesToRedeem
            });
            require(finalized, "Withdraw request not finalized");
            withdrawTokens[i] = IERC20(manager.WITHDRAW_TOKEN());
        }
    }
}
