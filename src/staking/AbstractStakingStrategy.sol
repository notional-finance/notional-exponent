// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {IWithdrawRequestManager, WithdrawRequest, CannotInitiateWithdraw, ExistingWithdrawRequest} from "../withdraws/IWithdrawRequestManager.sol";
import {Trade, TradeType} from "../interfaces/ITradingModule.sol";

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
        return super.convertYieldTokenToAsset();

        /* TODO: update this to use a transient variable if we are in liquidation
        WithdrawRequest memory w = getWithdrawRequest(account);
        uint256 withdrawValue = _calculateValueOfWithdrawRequest(
            w, stakeAssetPrice, asset, redemptionToken
        );
        // This should always be zero if there is a withdraw request.
        uint256 vaultSharesNotInWithdrawQueue = (vaultShares - w.vaultShares);

        uint256 vaultSharesValue = (vaultSharesNotInWithdrawQueue * stakeAssetPrice * BORROW_PRECISION) /
            (uint256(Constants.INTERNAL_TOKEN_PRECISION) * Constants.EXCHANGE_RATE_PRECISION);
        return (withdrawValue + vaultSharesValue).toInt();
        */
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
        uint256 yieldTokenAmount = convertSharesToYieldToken(balanceOfShares(account));
        requestId = withdrawRequestManager.initiateWithdraw({account: account, yieldTokenAmount: yieldTokenAmount, isForced: isForced, data: data});
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

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bytes memory redeemData
    ) internal override returns (uint256 yieldTokensBurned) {
        WithdrawRequest memory accountWithdraw;

        if (address(withdrawRequestManager) != address(0)) {
            (accountWithdraw, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), sharesOwner);
        }

        RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
        if (accountWithdraw.requestId == 0) {
            yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            _executeInstantRedemption(yieldTokensBurned, params);
        } else {
            require(balanceOfShares(sharesOwner) == sharesToRedeem, "Must Redeem All Shares");
            yieldTokensBurned = 0;

            (uint256 tokensClaimed, bool finalized) = withdrawRequestManager.finalizeAndRedeemWithdrawRequest(sharesOwner);
            require(finalized, "Withdraw request not finalized");

            // Trades may be required here if the borrowed token is not the same as what is
            // received when redeeming.
            if (asset != redemptionToken) {
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
        RedeemParams memory params
    ) internal virtual returns (uint256 assetsPurchased) {
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
            uint256 yieldTokenAmount = convertSharesToYieldToken(sharesToLiquidator);
            withdrawRequestManager.splitWithdrawRequest(liquidator, liquidateAccount, yieldTokenAmount);
        }
    }

    /// @dev By default we can use the withdraw request manager to stake the tokens
    function _stakeTokens(uint256 assets, address /* receiver */, bytes memory depositData) internal virtual {
        withdrawRequestManager.stakeTokens(address(asset), assets, depositData);
    }
}