// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/console.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "./utils/Errors.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO} from "./interfaces/Morpho/IMorpho.sol";
import {IOracle} from "./interfaces/Morpho/IOracle.sol";
import {TokenUtils} from "./utils/TokenUtils.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "./interfaces/ITradingModule.sol";
import {IWithdrawRequestManager} from "./withdraws/IWithdrawRequestManager.sol";
import {Initializable} from "./proxy/Initializable.sol";
import {ADDRESS_REGISTRY} from "./utils/Constants.sol";
import {ILendingRouter} from "./routers/ILendingRouter.sol";

/// @title AbstractYieldStrategy
/// @notice This is the base contract for all yield strategies, it implements the core logic for
/// minting, burning and the valuation of tokens.
abstract contract AbstractYieldStrategy is Initializable, ERC20, ReentrancyGuardTransient, IYieldStrategy {
    using SafeERC20 for ERC20;

    uint256 internal constant RATE_DECIMALS = 18;
    uint256 internal constant RATE_PRECISION = 1e18;
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

    /********* Storage Variables *********/
    string private s_name;
    string private s_symbol;

    uint32 private s_lastFeeAccrualTime;
    uint256 private s_accruedFeesInYieldToken;
    uint256 private s_escrowedShares;
    /****** End Storage Variables ******/

    /********* Transient Variables *********/
    // Used to authorize transfers off of the lending market
    address internal transient t_CurrentAccount;
    address internal transient t_CurrentLendingRouter;
    address internal transient t_AllowTransfer_To;
    uint256 internal transient t_AllowTransfer_Amount;
    /****** End Transient Variables ******/

    receive() external payable {}

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        // TODO: remove these
        address /* __irm */,
        uint256 /* __lltv */,
        uint8 __yieldTokenDecimals
    ) ERC20("", "") {
        feeRate = _feeRate;
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        // Not all yield tokens have a decimals() function (i.e. Convex staked tokens), so we
        // do have to pass in the decimals as a parameter.
        _yieldTokenDecimals = __yieldTokenDecimals;
        _assetDecimals = TokenUtils.getDecimals(_asset);
    }

    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_name;
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_symbol;
    }

    /*** Valuation and Conversion Functions ***/

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

        (borrowed, collateralValue, maxBorrow) = ILendingRouter(t_CurrentLendingRouter).healthFactor(
            borrower, address(this)
        );

        t_CurrentAccount = _currentAccount;
    }

    /// @inheritdoc IYieldStrategy
    function totalAssets() public view override returns (uint256) {
        return convertToAssets(totalSupply());
    }

    /// @inheritdoc IYieldStrategy
    function convertYieldTokenToAsset() public view returns (uint256) {
        // The trading module always returns a positive rate in 18 decimals so we can safely
        // cast to uint256
        (int256 rate , /* */) = TRADING_MODULE.getOraclePrice(yieldToken, asset);
        return uint256(rate);
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

    /*** Core Functions ***/
    modifier onlyLendingRouter() {
        if (ADDRESS_REGISTRY.isLendingRouter(msg.sender) == false) revert Unauthorized(msg.sender);
        t_CurrentLendingRouter = msg.sender;
        _;
        delete t_CurrentLendingRouter;
    }

    modifier setCurrentAccount(address onBehalf) {
        t_CurrentAccount = onBehalf;
        _;
        delete t_CurrentAccount;
    }

    function mintShares(
        uint256 assetAmount,
        address receiver,
        bytes calldata depositData
    ) external override onlyLendingRouter setCurrentAccount(receiver) nonReentrant returns (uint256 sharesMinted) {
        ERC20(asset).safeTransferFrom(t_CurrentLendingRouter, address(this), assetAmount);
        sharesMinted = _mintSharesGivenAssets(assetAmount, depositData, receiver);

        // Transfer the shares to the lending router so it can supply collateral
        _transfer(receiver, t_CurrentLendingRouter, sharesMinted);
    }

    function burnShares(
        address sharesOwner,
        uint256 sharesToBurn,
        uint256 sharesHeld,
        bytes calldata redeemData
    ) external override onlyLendingRouter setCurrentAccount(sharesOwner) nonReentrant returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToBurn, sharesHeld, redeemData, sharesOwner);

        // Send all the assets back to the lending router
        ERC20(asset).safeTransfer(t_CurrentLendingRouter, assetsWithdrawn);

        // Clear the transient variables to prevent re-use in a future call.
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;
    }

    function allowTransfer(address to, uint256 amount) external onlyLendingRouter {
        // Sets the transient variables to allow the lending market to transfer shares on exit position
        // or liquidation.
        t_AllowTransfer_To = to;
        t_AllowTransfer_Amount = amount;
    }

    function preLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 liquidateAccountShares,
        uint256 seizedAssets
    ) external onlyLendingRouter {
        t_CurrentAccount = liquidateAccount;
        uint256 maxLiquidateShares = _preLiquidation(liquidateAccount, liquidator, liquidateAccountShares);
        if (maxLiquidateShares < seizedAssets) revert CannotLiquidate(maxLiquidateShares, seizedAssets);

        // Allow transfers to the lending router which will proxy the call to liquidate.
        t_AllowTransfer_To = msg.sender;
        t_AllowTransfer_Amount = maxLiquidateShares;
    }

    function postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    ) external onlyLendingRouter {
        // Transfer the shares to the liquidator from the lending router
        _transfer(t_CurrentLendingRouter, liquidator, sharesToLiquidator);

        _postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        // Clear the transient variables to prevent re-use in a future call.
        delete t_AllowTransfer_To;
        delete t_AllowTransfer_Amount;
        delete t_CurrentAccount;
        delete t_CurrentLendingRouter;
    }

    /// @inheritdoc IYieldStrategy
    function redeemNative(uint256 sharesToRedeem, bytes memory redeemData) external override nonReentrant returns (uint256 assetsWithdrawn) {
        assetsWithdrawn = _burnShares(sharesToRedeem, balanceOf(msg.sender), redeemData, msg.sender);
        ERC20(asset).safeTransfer(msg.sender, assetsWithdrawn);
    }

    /// @inheritdoc IYieldStrategy
    function initiateWithdraw(
        address account,
        uint256 sharesHeld,
        bytes calldata data
    ) external onlyLendingRouter override returns (uint256 requestId) {
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld);
        return _initiateWithdraw(account, yieldTokenAmount, sharesHeld, data);
    }

    /// @inheritdoc IYieldStrategy
    function initiateWithdrawNativeBalance(bytes calldata data) external override returns (uint256 requestId) {
        uint256 sharesHeld = balanceOf(msg.sender);
        uint256 yieldTokenAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld);
        return _initiateWithdraw(msg.sender, yieldTokenAmount, sharesHeld, data);
    }

    /*** Private Functions ***/
    function _effectiveSupply() private view returns (uint256) {
        return (
            totalSupply() - s_escrowedShares + VIRTUAL_SHARES  - 
            // TODO: we can remove this with the lending router
            // This is required for exits because the yield token to share
            // calculation is incorrect when the yield tokens are burned before
            // the shares are burned. The price is checked by the lending market
            // when collateral is withdrawn. If the t_AllowTransfer_To is the current
            // contract then we are in a liquidation and the yield tokens have not
            // been burned yet so this adjustment is not required.
            (t_AllowTransfer_To != address(this) ? t_AllowTransfer_Amount : 0)
        );
    }

    function yieldTokenBalance() internal view returns (uint256) {
        return ERC20(yieldToken).balanceOf(address(this));
    }

    function _calculateAdditionalFeesInYieldToken() private view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - s_lastFeeAccrualTime;
        // e ^ (feeRate * timeSinceLastFeeAccrual / YEAR)
        uint256 x = (feeRate * timeSinceLastFeeAccrual) / YEAR;
        if (x == 0) return 0;

        // Taylor approximation of e ^ x  - 1 = x + x^2 / 2! + x^3 / 3! + ...
        uint256 eToTheX = x + (x * x) / (2 * RATE_PRECISION) + (x * x * x) / (6 * RATE_PRECISION * RATE_PRECISION);

        additionalFeesInYieldToken = (
            (yieldTokenBalance() - s_accruedFeesInYieldToken) * eToTheX
        ) / RATE_PRECISION;
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
        // TODO: update this restriction
        if (from == address(MORPHO)) {
            // Any transfers off of the lending market must be authorized here.
            if (t_AllowTransfer_To != to) revert UnauthorizedLendingMarketTransfer(from, to, value);
            if (t_AllowTransfer_Amount < value) revert UnauthorizedLendingMarketTransfer(from, to, value);
        }

        super._update(from, to, value);
    }

    /*** Internal Helper Functions ***/

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        if (trade.tradeType == TradeType.STAKE_TOKEN) {
            IWithdrawRequestManager withdrawRequestManager = ADDRESS_REGISTRY.getWithdrawRequestManager(address(this), trade.buyToken);
            ERC20(trade.sellToken).forceApprove(address(withdrawRequestManager), trade.amount);
            amountBought = withdrawRequestManager.stakeTokens(trade.sellToken, trade.amount, trade.exchangeData);
            return (trade.amount, amountBought);
        } else {
            address implementation = nProxy(payable(address(TRADING_MODULE))).getImplementation();
            bytes memory result = _delegateCall(
                implementation, abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade)
            );
            (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
        }
    }

    function _delegateCall(address target, bytes memory data) internal returns (bytes memory result) {
        bool success;
        (success, result) = target.delegatecall(data);
        if (!success) {
            assembly {
                // Copy the return data to memory
                returndatacopy(0, 0, returndatasize())
                // Revert with the return data
                revert(0, returndatasize())
            }
        }
    }

    /*** Virtual Functions ***/

    function _initialize(bytes calldata data) internal override virtual {
        (string memory _name, string memory _symbol) = abi.decode(data, (string, string));
        s_name = _name;
        s_symbol = _symbol;

        s_lastFeeAccrualTime = uint32(block.timestamp);
        emit VaultCreated(address(this));
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
    function _burnShares(uint256 sharesToBurn, uint256 sharesHeld, bytes memory redeemData, address sharesOwner) internal virtual returns (uint256 assetsWithdrawn) {
        if (sharesToBurn == 0) return 0;
        if (sharesHeld < sharesToBurn) revert InsufficientSharesHeld();

        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        // First accrue fees on the yield token
        _accrueFees();
        bool wasEscrowed = _redeemShares(sharesToBurn, sharesOwner, sharesHeld, redeemData);
        if (wasEscrowed) s_escrowedShares -= sharesToBurn;

        uint256 finalAssetBalance = ERC20(asset).balanceOf(address(this));
        assetsWithdrawn = finalAssetBalance - initialAssetBalance;

        // This burns the shares from the sharesOwner's balance
        _burn(sharesOwner, sharesToBurn);
    }

    /// @dev Some yield tokens (such as Convex staked tokens) cannot be transferred, so we may need
    /// to override this function.
    function _transferYieldTokenToOwner(address owner, uint256 yieldTokens) internal virtual {
        ERC20(yieldToken).safeTransfer(owner, yieldTokens);
    }

    /// @dev Returns the maximum number of shares that can be liquidated. Allows the strategy to override the
    /// underlying lending market's liquidation logic.
    function _preLiquidation(address /* liquidateAccount */, address /* liquidator */, uint256 liquidateAccountShares) internal virtual returns (uint256 maxLiquidateShares) {
        return liquidateAccountShares;
    }

    /// @dev Called after liquidation to update the yield token balance.
    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal virtual { }

    /// @dev Mints yield tokens given a number of assets.
    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal virtual;

    /// @dev Redeems shares
    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        uint256 sharesHeld,
        bytes memory redeemData
    ) internal virtual returns (bool wasEscrowed);

    function _initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data
    ) internal virtual returns (uint256 requestId);

    /// @inheritdoc IYieldStrategy
    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 yieldTokens = convertSharesToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * convertYieldTokenToAsset() * (10 ** _assetDecimals)) / (10 ** (_yieldTokenDecimals + RATE_DECIMALS));
    }

}

