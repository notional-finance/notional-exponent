// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Errors.sol";
import {INotionalV4Callback} from "./interfaces/INotionalV4Callback.sol";
import {BorrowData, IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams} from "./interfaces/Morpho/IMorpho.sol";
import {IOracle} from "./interfaces/Morpho/IOracle.sol";
import {TRADING_MODULE} from "./interfaces/ITradingModule.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "./interfaces/ITradingModule.sol";

/// @title AbstractYieldStrategy
/// @notice This is the base contract for all yield strategies, it implements the core logic for
/// minting, burning and the valuation of tokens.
abstract contract AbstractYieldStrategy /* layout at 0xAAAA */ is ERC20, IYieldStrategy {
    using SafeERC20 for ERC20;

    uint256 internal constant SHARE_PRECISION = 1e18;
    uint256 internal constant YEAR = 365 days;

    // TODO: if we want to use immutables, then we need to have new deployments for
    // each yield strategy.


    /// @inheritdoc IYieldStrategy
    address public immutable override asset;
    /// @inheritdoc IYieldStrategy
    address public immutable override yieldToken;
    /// @inheritdoc IYieldStrategy
    uint256 public immutable override feeRate;

    uint8 internal immutable _yieldTokenDecimals;
    uint8 internal immutable _assetDecimals;
    // Used for Morpho market params
    address internal immutable _irm;
    uint256 internal immutable _lltv;

    /********* Storage Variables *********/
    address public owner;

    // TODO: can we re-use the ERC20 approvals?
    mapping(address user => mapping(address operator => bool approved)) private _isApproved;

    /// @dev To prevent inflation attacks we track the yield token balance internally. This
    /// is less gas efficient but it is also required for some yield strategies.
    uint256 private s_trackedYieldTokenBalance;
    uint256 private s_lastFeeAccrualTime;
    uint256 private s_accruedFeesInYieldTokenPerShare;

    /****** End Storage Variables ******/

    /********* Transient Variables *********/
    // Used to authorize transfers off of the lending market
    address internal transient t_AllowTransfer_To;
    uint256 internal transient t_AllowTransfer_Amount;
    /****** End Transient Variables ******/

    receive() external payable {}

    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address __irm,
        uint256 __lltv
    ) ERC20(
        string(abi.encodePacked("Notional: ", ERC20(_yieldToken).name(), " [", ERC20(_asset).symbol(), "]")),
        string(abi.encodePacked("N-", ERC20(_yieldToken).symbol(), ":", ERC20(_asset).symbol()))
    ) {
        feeRate = _feeRate;
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        _yieldTokenDecimals = TokenUtils.getDecimals(_yieldToken);
        _assetDecimals = TokenUtils.getDecimals(_asset);

        // If multiple markets exist for the same strategy with different LTVs then we can
        // deploy multiple contracts for each market so that they are 1-1. This simplifies
        // what users need to pass in to the enterPosition function.
        _irm = __irm;
        _lltv = __lltv;

        // TODO: If upgradeable then this needs to be called in initialize()
        s_lastFeeAccrualTime = block.timestamp;
        owner = _owner;
    }

    /*** Valuation and Conversion Functions ***/

    /// @inheritdoc IYieldStrategy
    function convertSharesToYieldToken(uint256 shares) public view virtual override returns (uint256) {
        // NOTE: rounds down on division
        return (shares * (s_trackedYieldTokenBalance - feesAccrued())) / totalSupply();
    }

    /// @inheritdoc IYieldStrategy
    function convertToShares(uint256 assets) public view override returns (uint256) {
        // NOTE: rounds down on division
        uint256 yieldTokens = assets * (10 ** _yieldTokenDecimals) / convertYieldTokenToAsset();
        return convertYieldTokenToShares(yieldTokens);
    }

    /// @inheritdoc IOracle
    function price() public view override returns (uint256) {
        return convertToAssets(SHARE_PRECISION) * (10 ** (36 + _assetDecimals - 18));
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToShares(uint256 yieldTokens) public view returns (uint256) {
        // NOTE: rounds down on division
        return (yieldTokens * SHARE_PRECISION * totalSupply()) / ((s_trackedYieldTokenBalance - feesAccrued()) * (10 ** _yieldTokenDecimals));
    }

    /// @inheritdoc IYieldStrategy
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 yieldTokens = convertSharesToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * convertYieldTokenToAsset()) / (10 ** _yieldTokenDecimals);
    }

    /// @inheritdoc IYieldStrategy
    function totalAssets() public view virtual override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /*** Fee Methods ***/

    /// @inheritdoc IYieldStrategy
    function feesAccrued() public view virtual override returns (uint256 feesAccruedInYieldToken) {
        uint256 additionalFeesInYieldToken = _calculateAdditionalFeesInYieldToken();
        uint256 accruedFeesPerShare = s_accruedFeesInYieldTokenPerShare + additionalFeesInYieldToken;
        return accruedFeesPerShare * totalSupply() / SHARE_PRECISION;
    }

    /// @inheritdoc IYieldStrategy
    function collectFees() external override {
        if (msg.sender != owner) revert NotAuthorized(msg.sender, owner);
        _accrueFees();
        uint256 feesToCollect = s_accruedFeesInYieldTokenPerShare * totalSupply() / SHARE_PRECISION;
        ERC20(yieldToken).safeTransfer(owner, feesToCollect);
        s_trackedYieldTokenBalance -= feesToCollect;
    }

    /*** Authorization Methods ***/

    /// @inheritdoc IYieldStrategy
    function setApproval(address operator, bool approved) external override {
        _isApproved[msg.sender][operator] = approved;
    }

    /// @inheritdoc IYieldStrategy
    function isApproved(address user, address operator) public view override returns (bool) {
        return _isApproved[user][operator];
    }


    modifier isAuthorized(address onBehalf) {
        if (msg.sender != onBehalf && !isApproved(msg.sender, onBehalf)) {
            revert NotAuthorized(msg.sender, onBehalf);
        }
        _;
    }

    /*** Core Functions ***/

    /// @dev returns the Morpho market params for the matching lending market
    function _marketParams() internal view returns (MarketParams memory) {
        return MarketParams({
            loanToken: address(asset),
            collateralToken: address(this),
            // This contract will serve as its own oracle
            oracle: address(this),
            irm: _irm,
            lltv: _lltv
        });
    }

    /// @inheritdoc IYieldStrategy
    function enterPosition(
        address onBehalf,
        uint256 depositAssetAmount,
        BorrowData calldata borrowData,
        bytes calldata depositData
    ) external override isAuthorized(onBehalf) {
        // First collect the margin deposit
        if (depositAssetAmount > 0) {
            ERC20(asset).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        // At this point we will flash borrow funds from the lending market and then
        // receive control in a different function on a callback.
        bytes memory flashLoanData = abi.encode(depositAssetAmount, depositData, onBehalf);
        
        // XXX: below here is Morpho market specific code.
        (uint256 borrowAmount) = abi.decode(borrowData.callData, (uint256));
        MORPHO.flashLoan(asset, borrowAmount, flashLoanData);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        (uint256 depositAssetAmount, bytes memory depositData, address receiver) = abi.decode(
            data, (uint256, bytes, address)
        );

        uint256 sharesMinted = _mintSharesGivenAssets(assets + depositAssetAmount, depositData, receiver);

        // Allow Morpho to transferFrom the receiver the minted shares.
        _approve(receiver, address(MORPHO), sharesMinted);
        MORPHO.supplyCollateral(_marketParams(), sharesMinted, receiver, "");

        // Borrow the assets in order to repay the flash loan
        MORPHO.borrow(_marketParams(), assets, 0, receiver, address(this));

        // Allow for flash loan to be repaid
        ERC20(asset).forceApprove(address(MORPHO), assets);
    }

    /// @inheritdoc IYieldStrategy
    function exitPosition(
        address onBehalf,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override isAuthorized(onBehalf) returns (uint256 assetsWithdrawn) {
        // First optimistically redeem the required yield tokens even though we
        // are not sure if the holder has enough shares to yet since the shares are held
        // by the lending market. If they don't have enough shares then the withdraw
        // will fail.
        assetsWithdrawn = _burnShares(sharesToRedeem, redeemData, onBehalf);

        if (0 < assetToRepay) {
            // Allow Morpho to repay the portion of debt
            ERC20(asset).forceApprove(address(MORPHO), assetToRepay);

            // TODO: if assetToRepay is uint256.max then get the morpho borrow shares amount
            // XXX: Morpho market specific code.
            MORPHO.repay(_marketParams(), assetToRepay, 0, onBehalf, "");

            // Clear the approval to prevent re-use in a future call.
            ERC20(asset).forceApprove(address(MORPHO), 0);
        }

        // Withdraw the collateral and allow the transfer of shares from the lending market.
        t_AllowTransfer_To = onBehalf;
        t_AllowTransfer_Amount = sharesToRedeem;
        // XXX: Morpho market specific code.
        MORPHO.withdrawCollateral(_marketParams(), sharesToRedeem, onBehalf, onBehalf);
        // Clear the transient variables to prevent re-use in a future call.
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;

        // Transfer any profits to the receiver
        if (assetsWithdrawn < assetToRepay) {
            // We have to revert in this case because we've already redeemed the yield tokens
            revert InsufficientAssetsForRepayment(assetToRepay, assetsWithdrawn);
        }

        uint256 profitsWithdrawn;
        unchecked {
            profitsWithdrawn = assetsWithdrawn - assetToRepay;
        }
        ERC20(asset).safeTransfer(receiver, profitsWithdrawn);
    }

    /// @inheritdoc IYieldStrategy
    function liquidate(
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override {
        uint256 maxLiquidateShares = _canLiquidate(liquidateAccount);
        if (maxLiquidateShares == 0) revert CannotLiquidate();

        uint256 initialBalance = balanceOf(msg.sender);
        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        ERC20(asset).safeTransferFrom(msg.sender, address(this), assetToRepay);
        ERC20(asset).forceApprove(address(MORPHO), assetToRepay);

        t_AllowTransfer_To = msg.sender;
        t_AllowTransfer_Amount = maxLiquidateShares;
        /// XXX: Morpho market specific code.
        MORPHO.liquidate(_marketParams(), liquidateAccount, sharesToLiquidate, assetToRepay, "");
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;

        // Clear the approval to prevent re-use in a future call.
        ERC20(asset).forceApprove(address(MORPHO), 0);

        uint256 sharesToLiquidator = balanceOf(msg.sender) - initialBalance;
        uint256 finalAssetBalance = ERC20(asset).balanceOf(address(this));

        _postLiquidation(msg.sender, liquidateAccount, sharesToLiquidator);
        // If the liquidator specifies redeem data then we will redeem the shares and send the assets to the liquidator.
        if (redeemData.length > 0) redeem(sharesToLiquidator, redeemData);

        if (initialAssetBalance < finalAssetBalance) {
            ERC20(asset).safeTransfer(msg.sender, finalAssetBalance - initialAssetBalance);
        } else if (finalAssetBalance < initialAssetBalance) {
            revert InsufficientAssetsForRepayment(assetToRepay, initialAssetBalance - finalAssetBalance);
        }
    }

    /// @inheritdoc IYieldStrategy
    function redeem(uint256 sharesToRedeem, bytes memory redeemData) public returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToRedeem, redeemData, msg.sender);
        ERC20(asset).safeTransfer(msg.sender, assetsWithdrawn);
    }

    /*** Private Functions ***/

    function _calculateAdditionalFeesInYieldToken() private view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - s_lastFeeAccrualTime;
        // TODO: round up on division
        additionalFeesInYieldToken =
            (s_trackedYieldTokenBalance * timeSinceLastFeeAccrual * feeRate) / (YEAR * totalSupply());
    }

    function _accrueFees() private {
        if (s_lastFeeAccrualTime == block.timestamp) return;
        // NOTE: this has to be called before any mints or burns.
        uint256 additionalFeesInYieldToken = _calculateAdditionalFeesInYieldToken();
        s_accruedFeesInYieldTokenPerShare += additionalFeesInYieldToken;
        s_lastFeeAccrualTime = block.timestamp;
    }

    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) private returns (uint256 sharesMinted) {
        if (assets == 0) return 0;

        // First accrue fees on the yield token
        _accrueFees();
        uint256 initialYieldTokenBalance = ERC20(yieldToken).balanceOf(address(this));
        _mintYieldTokens(assets, receiver, depositData);
        uint256 yieldTokensMinted = ERC20(yieldToken).balanceOf(address(this)) - initialYieldTokenBalance;

        s_trackedYieldTokenBalance += yieldTokensMinted;
        sharesMinted = convertYieldTokenToShares(yieldTokensMinted);
        _mint(receiver, sharesMinted);

        _checkInvariants();
    }

    function _burnShares(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) private returns (uint256 assetsWithdrawn) {
        if (sharesToBurn == 0) return 0;

        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        // First accrue fees on the yield token
        _accrueFees();
        uint256 yieldTokensToBurn = convertSharesToYieldToken(sharesToBurn);
        _redeemYieldTokens(yieldTokensToBurn, sharesOwner, redeemData);
        s_trackedYieldTokenBalance -= yieldTokensToBurn;

        _burn(sharesOwner, sharesToBurn);
        uint256 finalAssetBalance = ERC20(asset).balanceOf(address(this));
        assetsWithdrawn = finalAssetBalance - initialAssetBalance;

        _checkInvariants();
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(MORPHO)) {
            // Any transfers off of the lending market must be authorized here.
            if (t_AllowTransfer_To != to) revert UnauthorizedLendingMarketTransfer(from, to, value);
            if (t_AllowTransfer_Amount > value) revert UnauthorizedLendingMarketTransfer(from, to, value);
        }

        super._update(from, to, value);
    }

    function _checkInvariants() internal view virtual {
        // Sanity check to ensure that the yield token balance is not being manipulated, although this
        // will pass if there is a donation of yield tokens to the contract.
        if (ERC20(yieldToken).balanceOf(address(this)) < s_trackedYieldTokenBalance) {
            revert InsufficientYieldTokenBalance();
        }
    }

    /*** Internal Helper Functions ***/

    function _getYieldTokenBalance() internal view returns (uint256) {
        return s_trackedYieldTokenBalance;
    }

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(TRADING_MODULE))).getImplementation()
            .delegatecall(abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade));
        if (!success) revert TradeFailed();
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    /*** Virtual Functions ***/

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToAsset() public view virtual returns (uint256) {
        (int256 rate , /* */) = TRADING_MODULE.getOraclePrice(yieldToken, asset);
        require(rate > 0);
        return uint256(rate);
    }

    /// @dev Returns the maximum number of shares that can be liquidated. Allows the strategy to override the
    /// underlying lending market's liquidation logic.
    function _canLiquidate(address liquidateAccount) internal virtual returns (uint256 maxLiquidateShares) {
        // TODO: get the balance of the account's position in the lending market
        return balanceOf(liquidateAccount);
    }

    /// @dev Called after liquidation to update the yield token balance.
    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal virtual { }

    /// @dev Mints yield tokens given a number of assets.
    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual;

    /// @dev Redeems yield tokens given a number of yield tokens.
    function _redeemYieldTokens(uint256 yieldTokensToRedeem, address sharesOwner, bytes memory redeemData) internal virtual;
}

