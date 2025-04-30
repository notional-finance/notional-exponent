// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./utils/Errors.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position, Market} from "./interfaces/Morpho/IMorpho.sol";
import {IOracle} from "./interfaces/Morpho/IOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "./interfaces/ITradingModule.sol";
import {IWithdrawRequestManager} from "./withdraws/IWithdrawRequestManager.sol";
import {TimelockUpgradeable} from "./proxy/TimelockUpgradeable.sol";

/// @title AbstractYieldStrategy
/// @notice This is the base contract for all yield strategies, it implements the core logic for
/// minting, burning and the valuation of tokens.
abstract contract AbstractYieldStrategy is TimelockUpgradeable, ERC20, ReentrancyGuardTransient, IYieldStrategy {
    using SafeERC20 for ERC20;

    uint256 internal constant SHARE_PRECISION = 1e18;
    uint256 internal constant RATE_DECIMALS = 18;
    uint256 internal constant YEAR = 365 days;

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
    Id internal immutable id;

    /********* Storage Variables *********/
    address public override owner;
    bool public override isPaused;
    uint32 private s_lastFeeAccrualTime;

    /// @dev To prevent inflation attacks we track the yield token balance internally. This
    /// is less gas efficient but it is also required for some yield strategies.
    uint256 private s_trackedYieldTokenBalance;
    uint256 private s_accruedFeesInYieldToken;
    uint256 private s_escrowedShares;

    mapping(address user => mapping(address operator => bool approved)) private _isApproved;
    mapping(address user => uint256 lastEntryTime) private _lastEntryTime;
    /****** End Storage Variables ******/

    /********* Transient Variables *********/
    // Used to authorize transfers off of the lending market
    address internal transient t_CurrentAccount;
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
        // TODO: these are not available on all tokens
        // string(abi.encodePacked("Notional: ", ERC20(_yieldToken).name(), " [", ERC20(_asset).symbol(), "]")),
        // string(abi.encodePacked("N-", ERC20(_yieldToken).symbol(), ":", ERC20(_asset).symbol()))
        string(abi.encodePacked("Notional:  [", ERC20(_asset).symbol(), "]")),
        string(abi.encodePacked("N-:", ERC20(_asset).symbol()))
    ) {
        feeRate = _feeRate;
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        // TODO: these are not available on all tokens
        _yieldTokenDecimals = 18; // TokenUtils.getDecimals(_yieldToken);
        _assetDecimals = TokenUtils.getDecimals(_asset);

        // If multiple markets exist for the same strategy with different LTVs then we can
        // deploy multiple contracts for each market so that they are 1-1. This simplifies
        // what users need to pass in to the enterPosition function.
        _irm = __irm;
        _lltv = __lltv;

        MORPHO.createMarket(marketParams());
        id = Id.wrap(keccak256(abi.encode(marketParams())));

        // TODO: If upgradeable then this needs to be called in initialize()
        s_lastFeeAccrualTime = uint32(block.timestamp);
        owner = _owner;
        isPaused = false;
    }

    /*** Valuation and Conversion Functions ***/
    function balanceOfShares(address account) public view returns (uint256 collateralBalance) {
        return balanceOf(account) + _accountCollateralBalance(account);
    }

    /// @inheritdoc IYieldStrategy
    function convertSharesToYieldToken(uint256 shares) public view override returns (uint256) {
        uint256 effectiveSupply = totalSupply() - s_escrowedShares;
        if (effectiveSupply == 0) return shares * (10 ** _yieldTokenDecimals) / SHARE_PRECISION;

        // NOTE: rounds down on division
        return (shares * (s_trackedYieldTokenBalance - feesAccrued())) / effectiveSupply;
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToShares(uint256 yieldTokens) public view returns (uint256) {
        uint256 effectiveSupply = totalSupply() - s_escrowedShares;
        if (effectiveSupply == 0) return yieldTokens * SHARE_PRECISION / (10 ** _yieldTokenDecimals);

        // NOTE: rounds down on division
        return (yieldTokens * SHARE_PRECISION * effectiveSupply) / (
            (s_trackedYieldTokenBalance - feesAccrued()) * (10 ** _yieldTokenDecimals)
        );
    }

    /// @inheritdoc IYieldStrategy
    function convertToShares(uint256 assets) public view override returns (uint256) {
        // NOTE: rounds down on division
        uint256 yieldTokens = assets * (10 ** (_yieldTokenDecimals + RATE_DECIMALS)) / (convertYieldTokenToAsset() * (10 ** _assetDecimals));
        return convertYieldTokenToShares(yieldTokens);
    }

    /// @inheritdoc IOracle
    function price() public view override returns (uint256) {
        return convertToAssets(SHARE_PRECISION) * (10 ** (36 - 18));
    }

    function healthFactor(address borrower) public override returns (
        uint256 borrowed, uint256 collateralValue, uint256 maxBorrow
    ) {
        address _currentAccount = t_CurrentAccount;
        t_CurrentAccount = borrower;

        Position memory position = MORPHO.position(id, borrower);
        Market memory market = MORPHO.market(id);

        if (position.borrowShares > 0) {
            borrowed = (uint256(position.borrowShares) * uint256(market.totalBorrowAssets)) / uint256(market.totalBorrowShares);
        } else {
            borrowed = 0;
        }
        collateralValue = (uint256(position.collateral) * price()) / 1e36;
        maxBorrow = collateralValue * _lltv / 1e18;

        t_CurrentAccount = _currentAccount;
    }

    /// @inheritdoc IYieldStrategy
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 yieldTokens = convertSharesToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * convertYieldTokenToAsset() * (10 ** _assetDecimals)) / (10 ** (_yieldTokenDecimals + RATE_DECIMALS));
    }

    /// @inheritdoc IYieldStrategy
    function totalAssets() public view virtual override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /*** Fee Methods ***/

    /// @inheritdoc IYieldStrategy
    function feesAccrued() public view virtual override returns (uint256 feesAccruedInYieldToken) {
        return s_accruedFeesInYieldToken + _calculateAdditionalFeesInYieldToken();
    }

    /// @inheritdoc IYieldStrategy
    function collectFees() external onlyOwner override {
        _accrueFees();
        _transferYieldTokenToOwner(s_accruedFeesInYieldToken);
        s_trackedYieldTokenBalance -= s_accruedFeesInYieldToken;

        delete s_accruedFeesInYieldToken;
    }

    /// @dev Some yield tokens (such as Convex staked tokens) cannot be transferred, so we may need
    /// to override this function.
    function _transferYieldTokenToOwner(uint256 yieldTokens) internal virtual {
        ERC20(yieldToken).safeTransfer(owner, yieldTokens);
    }

    /*** Authorization Methods ***/
    modifier isAuthorized(address onBehalf) {
        // In this case msg.sender is the operator
        if (msg.sender != onBehalf && !isApproved(onBehalf, msg.sender)) {
            revert NotAuthorized(msg.sender, onBehalf);
        }

        t_CurrentAccount = onBehalf;
        _;
        delete t_CurrentAccount;
    }

    modifier isNotPaused() {
        if (isPaused) revert Paused();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized(msg.sender, owner);
        _;
    }

    /// @inheritdoc IYieldStrategy
    function pause() external override onlyOwner {
        isPaused = true;
    }

    /// @inheritdoc IYieldStrategy
    function unpause() external override onlyOwner {
        isPaused = false;
    }

    function setApproval(address operator, bool approved) external override {
        if (operator == msg.sender) revert NotAuthorized(msg.sender, operator);
        _isApproved[msg.sender][operator] = approved;
    }

    /// @inheritdoc IYieldStrategy
    function isApproved(address user, address operator) public view override returns (bool) {
        return _isApproved[user][operator];
    }


    /*** Core Functions ***/

    /// @dev returns the Morpho market params for the matching lending market
    function marketParams() public view returns (MarketParams memory) {
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
        uint256 borrowAmount,
        bytes calldata depositData
    ) external override isAuthorized(onBehalf) isNotPaused nonReentrant {
        // First collect the margin deposit
        if (depositAssetAmount > 0) {
            ERC20(asset).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        if (borrowAmount > 0) {
            // At this point we will flash borrow funds from the lending market and then
            // receive control in a different function on a callback.
            bytes memory flashLoanData = abi.encode(depositAssetAmount, depositData, onBehalf);
            // XXX: below here is Morpho market specific code.
            MORPHO.flashLoan(asset, borrowAmount, flashLoanData);
        } else {
            _mintSharesAndSupplyCollateral(depositAssetAmount, depositData, onBehalf);
        }

        _lastEntryTime[onBehalf] = block.timestamp;

        _checkInvariants();
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO));

        (uint256 depositAssetAmount, bytes memory depositData, address receiver) = abi.decode(
            data, (uint256, bytes, address)
        );

        _mintSharesAndSupplyCollateral(assets + depositAssetAmount, depositData, receiver);

        // Borrow the assets in order to repay the flash loan
        MORPHO.borrow(marketParams(), assets, 0, receiver, address(this));

        // Allow for flash loan to be repaid
        ERC20(asset).forceApprove(address(MORPHO), assets);
    }

    function _mintSharesAndSupplyCollateral(uint256 assets, bytes memory depositData, address receiver) internal {
        uint256 sharesMinted = _mintSharesGivenAssets(assets, depositData, receiver);

        // Allow Morpho to transferFrom the receiver the minted shares.
        _transfer(receiver, address(this), sharesMinted);
        _approve(address(this), address(MORPHO), sharesMinted);
        MORPHO.supplyCollateral(marketParams(), sharesMinted, receiver, "");
    }

    /// @inheritdoc IYieldStrategy
    function exitPosition(
        address onBehalf,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override isAuthorized(onBehalf) isNotPaused nonReentrant returns (uint256 profitsWithdrawn) {
        if (block.timestamp - _lastEntryTime[onBehalf] < 5 minutes) {
            revert CannotExitPositionWithinCooldownPeriod();
        }

        // First optimistically redeem the required yield tokens even though we
        // are not sure if the holder has enough shares to yet since the shares are held
        // by the lending market. If they don't have enough shares then the withdraw
        // will fail.
        uint256 assetsWithdrawn = _burnShares(sharesToRedeem, redeemData, onBehalf);

        if (0 < assetToRepay) {
            // Allow Morpho to repay the portion of debt
            ERC20(asset).forceApprove(address(MORPHO), assetToRepay);

            // XXX: Morpho market specific code.
            if (assetToRepay == type(uint256).max) {
                // If assetToRepay is uint256.max then get the morpho borrow shares amount to
                // get a full exit.
                uint256 sharesToRepay = MORPHO.position(id, onBehalf).borrowShares;
                (assetToRepay, ) = MORPHO.repay(marketParams(), 0, sharesToRepay, onBehalf, "");
            } else {
                MORPHO.repay(marketParams(), assetToRepay, 0, onBehalf, "");
            }

            // Clear the approval to prevent re-use in a future call.
            ERC20(asset).forceApprove(address(MORPHO), 0);
        }

        // Withdraw the collateral and allow the transfer of shares from the lending market.
        t_AllowTransfer_To = onBehalf;
        t_AllowTransfer_Amount = sharesToRedeem;
        // XXX: Morpho market specific code.
        MORPHO.withdrawCollateral(marketParams(), sharesToRedeem, onBehalf, onBehalf);
        // Clear the transient variables to prevent re-use in a future call.
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;

        // Do this after withdraw collateral since onBehalf will now have the shares
        _burn(onBehalf, sharesToRedeem);

        // Transfer any profits to the receiver
        if (assetsWithdrawn < assetToRepay) {
            // We have to revert in this case because we've already redeemed the yield tokens
            revert InsufficientAssetsForRepayment(assetToRepay, assetsWithdrawn);
        }

        unchecked {
            profitsWithdrawn = assetsWithdrawn - assetToRepay;
        }
        ERC20(asset).safeTransfer(receiver, profitsWithdrawn);

        _checkInvariants();
    }

    /// @inheritdoc IYieldStrategy
    function liquidate(
        address liquidateAccount,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata redeemData
    ) external override isNotPaused nonReentrant returns (uint256 sharesToLiquidator) {
        t_CurrentAccount = liquidateAccount;
        uint256 maxLiquidateShares = _preLiquidation(liquidateAccount, msg.sender);
        if (maxLiquidateShares < seizedAssets) revert CannotLiquidate(maxLiquidateShares, seizedAssets);

        t_AllowTransfer_To = address(this);
        t_AllowTransfer_Amount = maxLiquidateShares;
        /// XXX: Morpho market specific code.
        (sharesToLiquidator, /* */) = MORPHO.liquidate(
            marketParams(), liquidateAccount, seizedAssets, repaidShares, abi.encode(msg.sender)
        );
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;
        delete t_CurrentAccount;

        // Transfer the shares to the liquidator
        _transfer(address(this), msg.sender, sharesToLiquidator);
        // Clear the approval to prevent re-use in a future call.
        ERC20(asset).forceApprove(address(MORPHO), 0);

        _postLiquidation(msg.sender, liquidateAccount, sharesToLiquidator);
        // If the liquidator specifies redeem data then we will redeem the shares and send the assets to the liquidator.
        if (redeemData.length > 0) redeem(sharesToLiquidator, redeemData);

        _checkInvariants();
    }

    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external {
        require(msg.sender == address(MORPHO));
        (address liquidator) = abi.decode(data, (address));

        ERC20(asset).safeTransferFrom(liquidator, address(this), repaidAssets);
        ERC20(asset).forceApprove(address(MORPHO), repaidAssets);
    }

    /// @inheritdoc IYieldStrategy
    function redeem(uint256 sharesToRedeem, bytes memory redeemData) public isNotPaused nonReentrant returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToRedeem, redeemData, msg.sender);
        _burn(msg.sender, sharesToRedeem);
        ERC20(asset).safeTransfer(msg.sender, assetsWithdrawn);
    }

    /*** Private Functions ***/

    function _calculateAdditionalFeesInYieldToken() private view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - s_lastFeeAccrualTime;
        uint256 divisor = YEAR * SHARE_PRECISION;
        additionalFeesInYieldToken =
            ((s_trackedYieldTokenBalance * timeSinceLastFeeAccrual * feeRate) + (divisor - 1)) / divisor;
    }

    function _accrueFees() private {
        if (s_lastFeeAccrualTime == block.timestamp) return;
        // NOTE: this has to be called before any mints or burns.
        s_accruedFeesInYieldToken += _calculateAdditionalFeesInYieldToken();
        s_lastFeeAccrualTime = uint32(block.timestamp);
    }

    /// @dev Removes some shares from the "pool" that is used to pay fees.
    function _escrowShares(uint256 shares, uint256 yieldTokens) internal virtual {
        _accrueFees();

        s_escrowedShares += shares;
        s_trackedYieldTokenBalance -= yieldTokens;
    }

    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) internal virtual returns (uint256 sharesMinted) {
        if (assets == 0) return 0;

        // First accrue fees on the yield token
        _accrueFees();
        uint256 initialYieldTokenBalance = ERC20(yieldToken).balanceOf(address(this));
        _mintYieldTokens(assets, receiver, depositData);
        uint256 yieldTokensMinted = ERC20(yieldToken).balanceOf(address(this)) - initialYieldTokenBalance;

        sharesMinted = convertYieldTokenToShares(yieldTokensMinted);
        // Update the tracked yield token balance after calculating the shares to mint
        s_trackedYieldTokenBalance += yieldTokensMinted;
        _mint(receiver, sharesMinted);
    }

    function _burnShares(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) internal virtual returns (uint256 assetsWithdrawn) {
        if (sharesToBurn == 0) return 0;

        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        // First accrue fees on the yield token
        _accrueFees();
        (uint256 yieldTokensBurned, bool wasEscrowed) = _redeemShares(sharesToBurn, sharesOwner, redeemData);
        // TODO: this may happen too soon on exitPosition because the shares to burn come back but
        // the yield tokens are already burned.
        if (wasEscrowed) {
            s_escrowedShares -= sharesToBurn;
        } else {
            s_trackedYieldTokenBalance -= yieldTokensBurned;
        }

        uint256 finalAssetBalance = ERC20(asset).balanceOf(address(this));
        assetsWithdrawn = finalAssetBalance - initialAssetBalance;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(MORPHO)) {
            // Any transfers off of the lending market must be authorized here.
            if (t_AllowTransfer_To != to) revert UnauthorizedLendingMarketTransfer(from, to, value);
            if (t_AllowTransfer_Amount < value) revert UnauthorizedLendingMarketTransfer(from, to, value);
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

    function _accountCollateralBalance(address account) internal view returns (uint256 collateralBalance) {
        collateralBalance = MORPHO.position(id, account).collateral;
    }

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        if (trade.tradeType == TradeType.STAKE_TOKEN) {
            // TODO: withdraw request manager should be a trusted contract
            (address withdrawRequestManager, bytes memory stakeData) = abi.decode(trade.exchangeData, (address, bytes));
            ERC20(trade.sellToken).forceApprove(address(withdrawRequestManager), trade.amount);
            amountBought = IWithdrawRequestManager(withdrawRequestManager).stakeTokens(trade.sellToken, trade.amount, stakeData);
            return (trade.amount, amountBought);
        }

        (bool success, bytes memory result) = nProxy(payable(address(TRADING_MODULE))).getImplementation()
            .delegatecall(abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade));
        if (!success) revert TradeFailed();
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToAsset() public view returns (uint256) {
        (int256 rate , /* */) = TRADING_MODULE.getOraclePrice(yieldToken, asset);
        require(rate > 0);
        return uint256(rate);
    }

    /*** Virtual Functions ***/

    /// @dev Returns the maximum number of shares that can be liquidated. Allows the strategy to override the
    /// underlying lending market's liquidation logic.
    function _preLiquidation(address liquidateAccount, address /* liquidator */) internal virtual returns (uint256 maxLiquidateShares) {
        return _accountCollateralBalance(liquidateAccount);
    }

    /// @dev Called after liquidation to update the yield token balance.
    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal virtual { }

    /// @dev Mints yield tokens given a number of assets.
    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual;

    /// @dev Redeems shares
    function _redeemShares(uint256 sharesToRedeem, address sharesOwner, bytes memory redeemData) internal virtual returns (uint256 yieldTokensBurned, bool wasEscrowed);

}

