// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "../utils/Errors.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {IWithdrawRequestManager, WithdrawRequest, CannotInitiateWithdraw, ExistingWithdrawRequest} from "../withdraws/IWithdrawRequestManager.sol";
import {Trade, TradeType} from "../interfaces/ITradingModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct RedeemParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

struct DepositParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
}

/**
 * Supports vaults that borrow a token and stake it into a token that earns yield but may
 * require some illiquid redemption period.
 */
abstract contract AbstractStakingStrategy is AbstractYieldStrategy {
    using SafeERC20 for ERC20;

    /// @notice if non-zero, the withdraw request manager is used to manage illiquid redemptions
    IWithdrawRequestManager public immutable withdrawRequestManager;

    /// @notice token that is redeemed from a withdraw request
    address public immutable redemptionToken;

    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _redemptionToken,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {
        redemptionToken = _redemptionToken;
        withdrawRequestManager = _withdrawRequestManager;
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertYieldTokenToAsset() public view override returns (uint256) {
        uint256 price = super.convertYieldTokenToAsset();
        if (t_Liquidate_Account == address(0) || address(withdrawRequestManager) == address(0)) return price;
        (WithdrawRequest memory w, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), t_Liquidate_Account);
        if (w.requestId == 0) return price;

        return price * (w.sharesAmount * 10 ** _yieldTokenDecimals) / (w.yieldTokenAmount * SHARE_PRECISION);
    }

    function _preLiquidation(address liquidateAccount, address /* liquidator */) internal view override returns (uint256 maxLiquidateShares) {
        return _accountCollateralBalance(liquidateAccount);
    }

    /// @notice Allows an account to initiate a withdraw of their vault shares
    function initiateWithdraw(bytes calldata data) external returns (uint256 requestId) {
        requestId = _initiateWithdraw({account: msg.sender, isForced: false, data: data});

        if (!isHealthy(msg.sender)) revert CannotInitiateWithdraw(msg.sender);
    }

    /// @notice Allows the emergency exit role to force an account to withdraw all their vault shares
    function forceWithdraw(address account, bytes calldata data) external onlyOwner returns (uint256 requestId) {
        requestId = _initiateWithdraw({account: account, isForced: true, data: data});
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal virtual returns (uint256 requestId) {
        // TODO: this may initiate withdraws across both native balance and collateral balance
        uint256 sharesHeld = balanceOfShares(account);
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld, yieldTokenAmount);
        
        ERC20(yieldToken).approve(address(withdrawRequestManager), yieldTokenAmount);
        requestId = withdrawRequestManager.initiateWithdraw({account: account, yieldTokenAmount: yieldTokenAmount, isForced: isForced, data: data});
        _checkInvariants();
    }

    function _mintYieldTokens(
        uint256 assets,
        address receiver,
        bytes memory depositData
    ) internal override {
        if (address(withdrawRequestManager) != address(0)) {
            (WithdrawRequest memory w, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), receiver);
            if (w.requestId != 0) revert ExistingWithdrawRequest(address(this), receiver, w.requestId);
        }

        _stakeTokens(assets, receiver, depositData);
    }

    /// @dev By default we can use the withdraw request manager to stake the tokens
    function _stakeTokens(uint256 assets, address /* receiver */, bytes memory depositData) internal virtual {
        ERC20(asset).approve(address(withdrawRequestManager), assets);
        withdrawRequestManager.stakeTokens(address(asset), assets, depositData);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bytes memory redeemData
    ) internal override returns (uint256 yieldTokensBurned, bool wasEscrowed) {
        WithdrawRequest memory accountWithdraw;

        if (address(withdrawRequestManager) != address(0)) {
            (accountWithdraw, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), sharesOwner);
        }

        if (accountWithdraw.requestId == 0) {
            yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            _executeInstantRedemption(yieldTokensBurned, redeemData);
            wasEscrowed = false;
        } else {
            // This assumes that the the account cannot get more shares once they initiate a withdraw. That
            // is why accounts are restricted from receiving split withdraw requests if they already have an
            // active position.
            uint256 balanceOfShares = balanceOfShares(sharesOwner);
            require(sharesToRedeem <= balanceOfShares);
            yieldTokensBurned = accountWithdraw.yieldTokenAmount * sharesToRedeem / balanceOfShares;
            wasEscrowed = true;

            (uint256 tokensClaimed, bool finalized) = withdrawRequestManager.finalizeAndRedeemWithdrawRequest(sharesOwner, yieldTokensBurned);
            require(finalized, "Withdraw request not finalized");

            // Trades may be required here if the borrowed token is not the same as what is
            // received when redeeming.
            if (asset != redemptionToken) {
                RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
                Trade memory trade = Trade({
                    tradeType: TradeType.EXACT_IN_SINGLE,
                    sellToken: address(redemptionToken),
                    buyToken: address(asset),
                    amount: tokensClaimed,
                    limit: params.minPurchaseAmount,
                    deadline: block.timestamp,
                    exchangeData: params.exchangeData
                });

                _executeTrade(trade, params.dexId);
            }
        }
    }

    /// @notice Default implementation for an instant redemption is to sell the staking token to the
    /// borrow token through the trading module. Can be overridden if required for different implementations.
    function _executeInstantRedemption(
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    ) internal virtual returns (uint256 assetsPurchased) {
        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(yieldToken),
            buyToken: address(asset),
            amount: yieldTokensToRedeem,
            limit: params.minPurchaseAmount,
            deadline: block.timestamp,
            exchangeData: params.exchangeData
        });

        // Executes a trade on the given Dex, the vault must have permissions set for
        // each dex and token it wants to sell.
        (/* */, assetsPurchased) = _executeTrade(trade, params.dexId);
    }

    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal override {
        // TODO: do we need to check health factor here?

        if (address(withdrawRequestManager) != address(0)) {
            // If the liquidator has a collateral balance then they cannot receive a split withdraw request
            // or the redemption calculation will be incorrect.
            if (_accountCollateralBalance(liquidator) > 0) revert CannotReceiveSplitWithdrawRequest();

            // No need to accrue fees because neither the total supply or total yield token balance is changing.
            uint256 yieldTokenAmount = convertSharesToYieldToken(sharesToLiquidator);
            // TODO: is this possible that we are unable to split the withdraw request b/c the yield token
            // amount is greater than the amount in the withdraw request? It would happen due to a changing
            // ratio of shares to yield tokens.
            // TODO: this is not correct for PTs since the PT is the yield token but we
            // use token out sy terms for the withdraw request.
            withdrawRequestManager.splitWithdrawRequest(liquidateAccount, liquidator, yieldTokenAmount);
        }
    }

}