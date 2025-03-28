// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NotAuthorized} from "./Errors.sol";
import {INotionalV4Callback} from "./interfaces/INotionalV4Callback.sol";
import {BorrowData, IYieldStrategy, Operation} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams} from "./interfaces/Morpho/IMorpho.sol";

abstract contract AbstractYieldStrategy /* layout at 0xAAAA */ is ERC20, IYieldStrategy {
    using SafeERC20 for ERC20;

    struct AllowTransfer {
        address to;
        uint256 amount;
        Operation operation;
        bytes redeemData;
    }
    AllowTransfer internal t_AllowTransferFromLendingMarket;

    uint256 internal constant SHARE_PRECISION = 1e18;
    uint256 internal constant YEAR = 365 days;

    address public immutable override asset;
    address public immutable override yieldToken;
    uint256 public immutable override feeRate;

    uint8 internal immutable _yieldTokenDecimals;
    uint8 internal immutable _assetDecimals;

    MarketParams public marketParams;

    /** Storage Variables */
    address public owner;
    mapping(address user => mapping(address operator => bool approved)) private _isApproved;

    uint256 internal trackedYieldTokenBalance;
    uint256 internal lastFeeAccrualTime;
    uint256 internal accruedFeesInYieldTokenPerShare;

    constructor(
        string memory name,
        string memory symbol,
        address _asset,
        address _yieldToken,
        uint256 _feeRate
    ) ERC20(name, symbol) {
        asset = address(_asset);
        yieldToken = address(_yieldToken);
        feeRate = _feeRate;
        _yieldTokenDecimals = ERC20(_yieldToken).decimals();
        _assetDecimals = ERC20(_asset).decimals();
        lastFeeAccrualTime = block.timestamp;

        marketParams = MarketParams({
            loanToken: address(_asset),
            collateralToken: address(this),
            oracle: address(0),
            irm: address(0),
            lltv: 0
        });
    }

    function calculateAdditionalFeesInYieldToken() internal view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - lastFeeAccrualTime;
        // NOTE: feeRate and totalSupply() are in the same units
        // TODO: total supply must be converted to yield token units
        // TODO: round up on division
        additionalFeesInYieldToken =
            (trackedYieldTokenBalance * timeSinceLastFeeAccrual * feeRate) / (YEAR * totalSupply());
    }

    function convertToYieldToken(uint256 shares) public view virtual override returns (uint256) {
        // NOTE: rounds down on division
        return (shares * (trackedYieldTokenBalance - feesAccrued())) / totalSupply();
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        // NOTE: rounds down on division
        uint256 yieldTokens = assets * (10 ** _yieldTokenDecimals) / yieldExchangeRateToAsset();
        return convertYieldTokenToShares(yieldTokens);
    }

    function convertYieldTokenToShares(uint256 yieldTokens) public view returns (uint256) {
        // NOTE: rounds down on division
        return (yieldTokens * 1e18 * totalSupply()) / ((trackedYieldTokenBalance - feesAccrued()) * (10 ** _yieldTokenDecimals));
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 yieldTokens = convertToYieldToken(shares);
        // NOTE: rounds down on division
        return (yieldTokens * yieldExchangeRateToAsset()) / (10 ** _yieldTokenDecimals);
    }

    function feesAccrued() public view virtual override returns (uint256 feesAccruedInYieldToken) {
        uint256 additionalFeesInYieldToken = calculateAdditionalFeesInYieldToken();
        uint256 accruedFeesPerShare = accruedFeesInYieldTokenPerShare + additionalFeesInYieldToken;
        return accruedFeesPerShare * totalSupply() / SHARE_PRECISION;
    }

    function totalAssets() public view virtual returns (uint256) {
        return convertToAssets(totalSupply());
    }

    function setApproval(address operator, bool approved) external override {
        _isApproved[msg.sender][operator] = approved;
    }

    function isApproved(address user, address operator) public view override returns (bool) {
        return _isApproved[user][operator];
    }

    function collectFees() external override {
        accrueFees();
        ERC20(yieldToken).safeTransfer(owner, feesAccrued());
    }

    modifier isAuthorized(address onBehalf) {
        if (msg.sender != onBehalf && !isApproved(msg.sender, onBehalf)) {
            revert NotAuthorized(msg.sender, onBehalf);
        }
        _;
    }

    function enterPosition(
        address onBehalf,
        uint256 depositAssetAmount,
        BorrowData calldata borrowData,
        bytes calldata depositData,
        bytes calldata callbackData
    ) external override isAuthorized(onBehalf) returns (uint256 shares) {
        // First collect the margin deposit
        if (depositAssetAmount > 0) {
            ERC20(asset).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        // At this point we will flash borrow funds from the lending market and then
        // receive control in a different function on a callback.
        (uint256 borrowAmount) = abi.decode(borrowData.callData, (uint256));
        bytes memory flashLoanData = abi.encode(depositAssetAmount, depositData, onBehalf);
        MORPHO.flashLoan(asset, borrowAmount, flashLoanData);

        if (callbackData.length > 0) INotionalV4Callback(msg.sender).onEnterPosition(shares, callbackData);
    }

    function exitPosition(
        address onBehalf,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData,
        bytes calldata callbackData
    ) external override isAuthorized(onBehalf) returns (uint256 assetsWithdrawn) {
        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));

        // First optimistically redeem the required yield tokens even though we
        // are not sure if the holder has enough shares to yet.
        assetsWithdrawn = _burnSharesGivenYieldTokens(sharesToRedeem, redeemData, onBehalf);

        // Allow Morpho to repay the portion of debt
        ERC20(asset).approve(address(MORPHO), assetToRepay);
        // TODO: if assetToRepay is uint256.max then get the shares amount
        MORPHO.repay(marketParams, assetToRepay, 0, onBehalf, "");

        // Withdraw the collateral and allow the transfer of shares from the lending market.
        t_AllowTransferFromLendingMarket = AllowTransfer({
            to: onBehalf,
            amount: sharesToRedeem,
            operation: Operation.WITHDRAW_AND_BURN,
            redeemData: redeemData
        });
        MORPHO.withdrawCollateral(marketParams, sharesToRedeem, onBehalf, onBehalf);
        delete t_AllowTransferFromLendingMarket;

        // TODO: if this is negative then what do we do?
        uint256 profitsWithdrawn = ERC20(asset).balanceOf(address(this)) - initialAssetBalance;
        if (callbackData.length > 0) INotionalV4Callback(msg.sender).onExitPosition(profitsWithdrawn, callbackData);

        // Transfer any profits to the receiver
        if (profitsWithdrawn > 0) {
            ERC20(asset).safeTransfer(receiver, profitsWithdrawn);
        }
    }

    function liquidate(
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override {
        uint256 maxLiquidateShares = _canLiquidate(liquidateAccount);
        uint256 initialAssetBalance = ERC20(asset).balanceOf(address(this));
        bytes memory callbackData = abi.encode(initialAssetBalance, msg.sender);

        t_AllowTransferFromLendingMarket = AllowTransfer({
            to: msg.sender,
            amount: maxLiquidateShares,
            // NOTE: inside this operation we will liquidate and burn the shares
            // and then hold any assets as a result.
            operation: Operation.LIQUIDATE_AND_BURN,
            redeemData: redeemData
        });
        MORPHO.liquidate(marketParams, liquidateAccount, sharesToLiquidate, assetToRepay, callbackData);
        delete t_AllowTransferFromLendingMarket;
    }

    function onMorphoLiquidate(uint256 repaidAmount, bytes calldata redeemData) external {
        (uint256 initialAssetBalance, address liquidator) = abi.decode(redeemData, (uint256, address));
        uint256 netAssetBalance = ERC20(asset).balanceOf(address(this)) - initialAssetBalance;
        if (netAssetBalance < repaidAmount) {
            // Transfer in the difference
            ERC20(asset).safeTransferFrom(liquidator, address(this), repaidAmount - netAssetBalance);
        } else {
            ERC20(asset).safeTransfer(liquidator, netAssetBalance - repaidAmount);
        }

        ERC20(asset).approve(address(MORPHO), repaidAmount);
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        (uint256 depositAssetAmount, bytes memory depositData, address receiver) = abi.decode(
            data, (uint256, bytes, address)
        );

        uint256 sharesMinted = _mintSharesGivenAssets(assets + depositAssetAmount, depositData, receiver);

        // Allow Morpho to transferFrom the receiver the minted shares.
        _approve(receiver, address(MORPHO), sharesMinted);
        MORPHO.supplyCollateral(marketParams, sharesMinted, receiver, "");

        // Borrow the assets in order to repay the flash loan
        MORPHO.borrow(marketParams, assets, 0, receiver, address(this));

        // Allow for flash loan to be repaid
        ERC20(asset).approve(address(MORPHO), assets);
    }

    function accrueFees() internal {
        if (lastFeeAccrualTime == block.timestamp) return;
        // NOTE: this has to be called before any mints or burns.
        uint256 additionalFeesInYieldToken = calculateAdditionalFeesInYieldToken();
        accruedFeesInYieldTokenPerShare += additionalFeesInYieldToken;
        lastFeeAccrualTime = block.timestamp;
    }

    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) private returns (uint256 sharesMinted) {
        // First accrue fees on the yield token
        accrueFees();
        uint256 yieldTokensMinted = _mintYieldTokens(assets, depositData);
        trackedYieldTokenBalance += yieldTokensMinted;

        require(ERC20(yieldToken).balanceOf(address(this)) == trackedYieldTokenBalance, "Insufficient yield token balance");

        sharesMinted = convertYieldTokenToShares(yieldTokensMinted);
        _mint(receiver, sharesMinted);
    }

    function _burnSharesGivenYieldTokens(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) private returns (uint256 assetsWithdrawn) {
        // First accrue fees on the yield token
        accrueFees();
        uint256 yieldTokensToBurn = convertToYieldToken(sharesToBurn);
        assetsWithdrawn = _redeemYieldTokens(yieldTokensToBurn, redeemData);
        trackedYieldTokenBalance -= yieldTokensToBurn;

        require(ERC20(yieldToken).balanceOf(address(this)) == trackedYieldTokenBalance, "Insufficient yield token balance");
        _burn(sharesOwner, sharesToBurn);
    }


    function yieldExchangeRateToAsset() public view virtual returns (uint256);
    function _canLiquidate(address liquidateAccount) internal view virtual returns (uint256 maxLiquidateShares);
    function _mintYieldTokens(uint256 assets, bytes memory depositData) internal virtual returns (uint256 yieldTokensMinted);
    function _redeemYieldTokens(uint256 yieldTokensToRedeem, bytes memory redeemData) internal virtual returns (uint256 assetsWithdrawn);
}

