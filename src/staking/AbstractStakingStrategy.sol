// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../utils/Errors.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {
    IWithdrawRequestManager,
    WithdrawRequest,
    SplitWithdrawRequest,
    CannotInitiateWithdraw,
    ExistingWithdrawRequest
} from "../withdraws/IWithdrawRequestManager.sol";
import {Trade, TradeType, TRADING_MODULE} from "../interfaces/ITradingModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/src/console2.sol";

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
    address public immutable withdrawToken;

    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        IWithdrawRequestManager _withdrawRequestManager
    ) AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv, ERC20(_yieldToken).decimals()) {
        withdrawRequestManager = _withdrawRequestManager;
        withdrawToken = address(withdrawRequestManager) != address(0) ? withdrawRequestManager.withdrawToken() : address(0);
    }

    function _withdrawRequestYieldTokenRate() internal view virtual returns (uint256) {
        return convertYieldTokenToAsset();
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0) && address(withdrawRequestManager) != address(0)) {
            // XXX: 1300 bytes inside here
            (WithdrawRequest memory w, SplitWithdrawRequest memory s) = withdrawRequestManager.getWithdrawRequest(address(this), t_CurrentAccount);
            if (w.requestId == 0) return super.convertToAssets(shares);
            if (s.finalized) {
                // If finalized the withdraw request is locked to the tokens withdrawn
                (int256 withdrawTokenRate, /* */) = TRADING_MODULE.getOraclePrice(withdrawToken, asset);
                require(withdrawTokenRate > 0);
                uint256 withdrawTokenDecimals = ERC20(withdrawToken).decimals();
                uint256 withdrawTokenAmount = (uint256(w.yieldTokenAmount) * uint256(s.totalWithdraw)) / uint256(s.totalYieldTokenAmount);

                uint256 totalValue = (uint256(withdrawTokenRate) * withdrawTokenAmount * (10 ** _assetDecimals)) /
                    (10 ** (withdrawTokenDecimals + 18));
                // NOTE: returns the normalized value given the shares input
                return totalValue * shares / w.sharesAmount;
            }

            uint256 rate = _withdrawRequestYieldTokenRate();
            rate = rate * (w.yieldTokenAmount * (SHARE_PRECISION)) / (w.sharesAmount * (10 ** _yieldTokenDecimals));

            return rate * (10 ** _assetDecimals) * shares / (SHARE_PRECISION * 1e18);
        }

        return super.convertToAssets(shares);
    }

    /// @notice Allows an account to initiate a withdraw of their vault shares
    function initiateWithdraw(bytes calldata data) external returns (uint256 requestId) {
        requestId = _initiateWithdraw({account: msg.sender, isForced: false, data: data});

        // Can only initiate a withdraw if health factor remains positive
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(msg.sender);
        if (borrowed > maxBorrow) revert CannotInitiateWithdraw(msg.sender);
    }

    /// @notice Allows the emergency exit role to force an account to withdraw all their vault shares
    function forceWithdraw(address account, bytes calldata data) external onlyOwner returns (uint256 requestId) {
        requestId = _initiateWithdraw({account: account, isForced: true, data: data});
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal virtual returns (uint256 requestId) {
        // TODO: this may initiate withdraws across both native balance and collateral balance
        uint256 sharesHeld = balanceOfShares(account);
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld);
        
        ERC20(yieldToken).approve(address(withdrawRequestManager), yieldTokenAmount);
        requestId = withdrawRequestManager.initiateWithdraw({
            account: account, yieldTokenAmount: yieldTokenAmount, sharesAmount: sharesHeld, isForced: isForced, data: data
        });
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
    ) internal override returns (bool wasEscrowed) {
        WithdrawRequest memory accountWithdraw;

        if (address(withdrawRequestManager) != address(0)) {
            (accountWithdraw, /* */) = withdrawRequestManager.getWithdrawRequest(address(this), sharesOwner);
        }

        if (accountWithdraw.requestId == 0) {
            uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            _executeInstantRedemption(yieldTokensBurned, redeemData);
            wasEscrowed = false;
        } else {
            // This assumes that the the account cannot get more shares once they initiate a withdraw. That
            // is why accounts are restricted from receiving split withdraw requests if they already have an
            // active position.
            uint256 balanceOfShares = balanceOfShares(sharesOwner);
            require(sharesToRedeem <= balanceOfShares);
            uint256 yieldTokensBurned = uint256(accountWithdraw.yieldTokenAmount) * sharesToRedeem / balanceOfShares;
            wasEscrowed = true;

            (uint256 tokensClaimed, bool finalized) = withdrawRequestManager.finalizeAndRedeemWithdrawRequest({
                account: sharesOwner, withdrawYieldTokenAmount: yieldTokensBurned, sharesToBurn: sharesToRedeem
            });
            require(finalized, "Withdraw request not finalized");

            // Trades may be required here if the borrowed token is not the same as what is
            // received when redeeming.
            if (asset != withdrawToken) {
                RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
                Trade memory trade = Trade({
                    tradeType: TradeType.EXACT_IN_SINGLE,
                    sellToken: address(withdrawToken),
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
            withdrawRequestManager.splitWithdrawRequest(liquidateAccount, liquidator, sharesToLiquidator);
        }
    }

}