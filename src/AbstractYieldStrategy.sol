// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract AbstractYieldStrategy is ERC20, IYieldStrategy {
    uint256 internal constant SHARE_PRECISION = 1e18;
    uint256 internal constant YEAR = 365 days;

    address public immutable override asset;
    address public immutable override yieldToken;
    uint256 public immutable override feeRate;

    uint8 internal immutable _yieldTokenDecimals;
    uint8 internal immutable _assetDecimals;

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
    }

    function calculateAdditionalFeesInYieldToken() internal view returns (uint256 additionalFeesInYieldToken) {
        uint256 timeSinceLastFeeAccrual = block.timestamp - lastFeeAccrualTime;
        // NOTE: feeRate and totalSupply() are in the same units
        // TODO: total supply must be converted to yield token units
        // TODO: round up on division
        additionalFeesInYieldToken =
            (trackedYieldTokenBalance * timeSinceLastFeeAccrual * feeRate) / (YEAR * totalSupply());
    }

    function accrueFees() internal {
        // NOTE: this has to be called before any mints or burns.
        uint256 additionalFeesInYieldToken = calculateAdditionalFeesInYieldToken();
        accruedFeesInYieldTokenPerShare += additionalFeesInYieldToken;
        lastFeeAccrualTime = block.timestamp;
    }

    function convertToYieldToken(uint256 shares) public view virtual override returns (uint256) {
        // NOTE: rounds down on division
        return (shares * (trackedYieldTokenBalance - feesAccrued())) / totalSupply();
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        uint256 yieldTokens = assets * (10 ** _yieldTokenDecimals) / yieldExchangeRateToAsset();
        // NOTE: rounds down on division
        return (yieldTokens * totalSupply()) / (trackedYieldTokenBalance - feesAccrued());
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
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

    function isApproved(address user, address operator) external view override returns (bool) {
        return _isApproved[user][operator];
    }

    function collectFees() external override {
        accrueFees();
        ERC20(yieldToken).transfer(owner, feesAccrued());
    }

    function yieldExchangeRateToAsset() public view virtual returns (uint256);

}

