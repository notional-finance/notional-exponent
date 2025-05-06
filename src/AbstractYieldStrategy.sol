// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./utils/Errors.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position, Market} from "./interfaces/Morpho/IMorpho.sol";
import {IOracle} from "./interfaces/Morpho/IOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "./interfaces/ITradingModule.sol";
import {IWithdrawRequestManager} from "./withdraws/IWithdrawRequestManager.sol";
import {Initializable} from "./proxy/Initializable.sol";
import {ADDRESS_REGISTRY} from "./utils/Constants.sol";

/// @title AbstractYieldStrategy
/// @notice This is the base contract for all yield strategies, it implements the core logic for
/// minting, burning and the valuation of tokens.
abstract contract AbstractYieldStrategy is Initializable, ERC20, ReentrancyGuardTransient, IYieldStrategy {
    using SafeERC20 for ERC20;

    uint256 internal constant RATE_DECIMALS = 18;
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_YIELD_TOKENS = 1;
    uint256 internal constant SHARE_PRECISION = 1e18 * VIRTUAL_SHARES;

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
    string private s_name;
    string private s_symbol;

    uint32 private s_lastFeeAccrualTime;
    uint256 private s_accruedFeesInYieldToken;
    uint256 private s_escrowedShares;

    mapping(address user => mapping(address operator => bool approved)) private s_isApproved;
    mapping(address user => uint256 lastEntryTime) private s_lastEntryTime;
    /****** End Storage Variables ******/

    /********* Transient Variables *********/
    // Used to authorize transfers off of the lending market
    address internal transient t_CurrentAccount;
    address internal transient t_AllowTransfer_To;
    uint256 internal transient t_AllowTransfer_Amount;
    /****** End Transient Variables ******/

    receive() external payable {}

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address __irm,
        uint256 __lltv,
        uint8 __yieldTokenDecimals
    ) ERC20("", "") {
        feeRate = _feeRate;
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        // Not all yield tokens have a decimals() function (i.e. Convex staked tokens), so we
        // do have to pass in the decimals as a parameter.
        _yieldTokenDecimals = __yieldTokenDecimals;
        _assetDecimals = TokenUtils.getDecimals(_asset);

        // If multiple markets exist for the same strategy with different LTVs then we can
        // deploy multiple contracts for each market so that they are 1-1. This simplifies
        // what users need to pass in to the enterPosition function.
        _irm = __irm;
        _lltv = __lltv;
    }

    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_name;
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_symbol;
    }

    function morphoId() public view returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams())));
    }

    /*** Valuation and Conversion Functions ***/
    function balanceOfShares(address account) public view returns (uint256 collateralBalance) {
        return balanceOf(account) + _accountCollateralBalance(account);
    }

    /// @inheritdoc IYieldStrategy
    function convertSharesToYieldToken(uint256 shares) public view override returns (uint256) {
        // NOTE: rounds down on division
        return (shares * (yieldTokenBalance() - feesAccrued() + VIRTUAL_YIELD_TOKENS)) / (_effectiveSupply());
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToShares(uint256 yieldTokens) public view returns (uint256) {
        // NOTE: rounds down on division
        return (yieldTokens * _effectiveSupply()) / (yieldTokenBalance() - feesAccrued() + VIRTUAL_YIELD_TOKENS);
    }

    /// @inheritdoc IYieldStrategy
    function convertToShares(uint256 assets) public view override returns (uint256) {
        // NOTE: rounds down on division
        uint256 yieldTokens = assets * (10 ** (_yieldTokenDecimals + RATE_DECIMALS)) / (convertYieldTokenToAsset() * (10 ** _assetDecimals));
        return convertYieldTokenToShares(yieldTokens);
    }

    /// @inheritdoc IOracle
    function price() public view override returns (uint256) {
        return convertToAssets(SHARE_PRECISION) * (10 ** (36 - 24));
    }

    function healthFactor(address borrower) public override returns (
        uint256 borrowed, uint256 collateralValue, uint256 maxBorrow
    ) {
        address _currentAccount = t_CurrentAccount;
        t_CurrentAccount = borrower;

        Position memory position = MORPHO.position(morphoId(), borrower);
        Market memory market = MORPHO.market(morphoId());

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
    function totalAssets() public view override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /*** Fee Methods ***/

    /// @inheritdoc IYieldStrategy
    function feesAccrued() public view override returns (uint256 feesAccruedInYieldToken) {
        return s_accruedFeesInYieldToken + _calculateAdditionalFeesInYieldToken();
    }

    /// @inheritdoc IYieldStrategy
    function collectFees() external override {
        _accrueFees();
        _transferYieldTokenToOwner(ADDRESS_REGISTRY.feeReceiver(), s_accruedFeesInYieldToken);

        delete s_accruedFeesInYieldToken;
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

    function setApproval(address operator, bool approved) external override {
        if (operator == msg.sender) revert NotAuthorized(msg.sender, operator);
        s_isApproved[msg.sender][operator] = approved;
    }

    /// @inheritdoc IYieldStrategy
    function isApproved(address user, address operator) public view override returns (bool) {
        return s_isApproved[user][operator];
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
    ) external override isAuthorized(onBehalf) nonReentrant {
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

        s_lastEntryTime[onBehalf] = block.timestamp;

        _checkInvariants();
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO));

        (uint256 depositAssetAmount, bytes memory depositData, address receiver) = abi.decode(
            data, (uint256, bytes, address)
        );

        _mintSharesAndSupplyCollateral(assets + depositAssetAmount, depositData, receiver);

        // Borrow the assets in order to repay the flash loan
        // XXX: this is a Morpho market specific function
        MORPHO.borrow(marketParams(), assets, 0, receiver, address(this));

        // Allow for flash loan to be repaid
        ERC20(asset).forceApprove(address(MORPHO), assets);
    }

    function _mintSharesAndSupplyCollateral(uint256 assets, bytes memory depositData, address receiver) internal {
        uint256 sharesMinted = _mintSharesGivenAssets(assets, depositData, receiver);

        // Allow Morpho to transferFrom the receiver the minted shares.
        _transfer(receiver, address(this), sharesMinted);

        // XXX: this is a Morpho market specific function
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
    ) external override isAuthorized(onBehalf) nonReentrant returns (uint256 profitsWithdrawn) {
        if (block.timestamp - s_lastEntryTime[onBehalf] < 5 minutes) {
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
                uint256 sharesToRepay = MORPHO.position(morphoId(), onBehalf).borrowShares;
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
    ) external override nonReentrant returns (uint256 sharesToLiquidator) {
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
    function redeem(uint256 sharesToRedeem, bytes memory redeemData) public nonReentrant returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToRedeem, redeemData, msg.sender);
        _burn(msg.sender, sharesToRedeem);
        ERC20(asset).safeTransfer(msg.sender, assetsWithdrawn);
    }

    /*** Private Functions ***/
    function _effectiveSupply() private view returns (uint256) {
        return (
            totalSupply() - s_escrowedShares + VIRTUAL_SHARES - 
            // TODO: clean this up a bit
            (t_AllowTransfer_To != address(this) ? t_AllowTransfer_Amount : 0)
        );
    }

    function yieldTokenBalance() internal view returns (uint256) {
        return ERC20(yieldToken).balanceOf(address(this));
    }

    function _calculateAdditionalFeesInYieldToken() private view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - s_lastFeeAccrualTime;
        // TODO: rate decimals is 18 to match the feeRate decimals
        uint256 divisor = YEAR * (10 ** RATE_DECIMALS);
        // TODO: change this to do continuous compounding
        additionalFeesInYieldToken = (
            (yieldTokenBalance() - s_accruedFeesInYieldToken) * timeSinceLastFeeAccrual * feeRate + (divisor - 1)
        ) / divisor;
    }

    function _accrueFees() private {
        if (s_lastFeeAccrualTime == block.timestamp) return;
        // NOTE: this has to be called before any mints or burns.
        s_accruedFeesInYieldToken += _calculateAdditionalFeesInYieldToken();
        s_lastFeeAccrualTime = uint32(block.timestamp);
    }

    /// @dev Removes some shares from the "pool" that is used to pay fees.
    function _escrowShares(uint256 shares) internal {
        _accrueFees();
        s_escrowedShares += shares;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(MORPHO)) {
            // Any transfers off of the lending market must be authorized here.
            if (t_AllowTransfer_To != to) revert UnauthorizedLendingMarketTransfer(from, to, value);
            if (t_AllowTransfer_Amount < value) revert UnauthorizedLendingMarketTransfer(from, to, value);
        }

        super._update(from, to, value);
    }

    function _checkInvariants() internal view { }

    /*** Internal Helper Functions ***/
    function _accountCollateralBalance(address account) internal view returns (uint256 collateralBalance) {
        collateralBalance = MORPHO.position(morphoId(), account).collateral;
    }

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        if (trade.tradeType == TradeType.STAKE_TOKEN) {
            IWithdrawRequestManager withdrawRequestManager = ADDRESS_REGISTRY.getWithdrawRequestManager(address(this), trade.sellToken);
            ERC20(trade.sellToken).forceApprove(address(withdrawRequestManager), trade.amount);
            amountBought = withdrawRequestManager.stakeTokens(trade.sellToken, trade.amount, trade.exchangeData);
            return (trade.amount, amountBought);
        }

        (bool success, bytes memory result) = nProxy(payable(address(TRADING_MODULE))).getImplementation()
            .delegatecall(abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade));
        if (!success) revert TradeFailed();
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToAsset() public view returns (uint256) {
        // TODO: do we need to get the precision here?
        (int256 rate , /* */) = TRADING_MODULE.getOraclePrice(yieldToken, asset);
        require(rate > 0);
        return uint256(rate);
    }

    /*** Virtual Functions ***/

    function _initialize(bytes calldata data) internal override virtual {
        (string memory _name, string memory _symbol) = abi.decode(data, (string, string));
        s_name = _name;
        s_symbol = _symbol;

        // This is called inside initialize() because we need to use address(this) inside
        // marketParams()
        MORPHO.createMarket(marketParams());

        s_lastFeeAccrualTime = uint32(block.timestamp);
    }

    /// @dev Marked as virtual to allow for RewardManagerMixin to override
    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) internal virtual returns (uint256 sharesMinted) {
        if (assets == 0) return 0;

        // First accrue fees on the yield token
        _accrueFees();
        uint256 initialYieldTokenBalance = yieldTokenBalance();
        _mintYieldTokens(assets, receiver, depositData);
        uint256 yieldTokensMinted = yieldTokenBalance() - initialYieldTokenBalance;

        sharesMinted = (yieldTokensMinted * _effectiveSupply()) / (initialYieldTokenBalance - feesAccrued() + VIRTUAL_YIELD_TOKENS);
        _mint(receiver, sharesMinted);
    }

    /// @dev Marked as virtual to allow for RewardManagerMixin to override
    function _burnShares(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) internal virtual returns (uint256 assetsWithdrawn) {
        if (sharesToBurn == 0) return 0;

        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        // First accrue fees on the yield token
        _accrueFees();
        bool wasEscrowed = _redeemShares(sharesToBurn, sharesOwner, redeemData);
        if (wasEscrowed) s_escrowedShares -= sharesToBurn;

        uint256 finalAssetBalance = ERC20(asset).balanceOf(address(this));
        assetsWithdrawn = finalAssetBalance - initialAssetBalance;
    }

    /// @dev Some yield tokens (such as Convex staked tokens) cannot be transferred, so we may need
    /// to override this function.
    function _transferYieldTokenToOwner(address owner, uint256 yieldTokens) internal virtual {
        ERC20(yieldToken).safeTransfer(owner, yieldTokens);
    }

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
    function _redeemShares(uint256 sharesToRedeem, address sharesOwner, bytes memory redeemData) internal virtual returns (bool wasEscrowed);

    /// @inheritdoc IYieldStrategy
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 yieldTokens = convertSharesToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * convertYieldTokenToAsset() * (10 ** _assetDecimals)) / (10 ** (_yieldTokenDecimals + RATE_DECIMALS));
    }

}

