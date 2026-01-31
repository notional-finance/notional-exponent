// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {MorphoLendingRouter} from "./routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Market, Id} from "./interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract FlashLiquidatorV2 {

    address private owner;

    uint256 private constant ORACLE_PRICE_SCALE = 1e36;
    uint256 private constant WAD = 1e18;
    uint256 private constant VIRTUAL_ASSETS = 1;
    uint256 private constant VIRTUAL_SHARES = 1e6;
    uint256 private constant LIQUIDATION_CURSOR = 0.3e18;
    uint256 private constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivDown(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    constructor() {
        owner = msg.sender;
        ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        usdc.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        weth.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        usdc.approve(address(MORPHO), type(uint256).max);
        weth.approve(address(MORPHO), type(uint256).max);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function approve(address asset) external onlyOwner {
        ERC20(asset).approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        ERC20(asset).approve(address(MORPHO), type(uint256).max);
    }

    /// @notice Calculate the liquidation incentive factor for a given market
    /// @dev Mirrors Morpho's calculation: min(maxFactor, 1 / (1 - cursor × (1 - lltv)))
    function calculateLiquidationIncentiveFactor(uint256 lltv) internal pure returns (uint256) {
        // liquidationIncentiveFactor = min(MAX, WAD / (WAD - CURSOR × (WAD - lltv)))
        uint256 denominator = WAD - wMulDown(LIQUIDATION_CURSOR, WAD - lltv);
        uint256 incentiveFactor = wDivDown(WAD, denominator);
        return min(MAX_LIQUIDATION_INCENTIVE_FACTOR, incentiveFactor);
    }

    /// @notice Calculate shares to liquidate to repay all borrow shares
    /// @dev Reverses Morpho's calculation, rounding down to avoid reverts
    /// @param borrowShares The total borrow shares to repay
    /// @param collateralPrice The price of collateral from the vault oracle
    /// @param market The Morpho market state
    /// @param lltv The loan-to-value ratio for the market
    /// @return sharesToLiquidate The amount of collateral shares to seize
    function calculateSharesToLiquidate(
        uint256 borrowShares,
        uint256 collateralPrice,
        Market memory market,
        uint256 lltv
    ) internal pure returns (uint256 sharesToLiquidate) {
        // Step 1: Convert borrow shares to assets (round down for safety)
        uint256 repaidAssets = toAssetsDown(
            borrowShares,
            market.totalBorrowAssets,
            market.totalBorrowShares
        );

        // Step 2: Calculate liquidation incentive factor
        uint256 liquidationIncentiveFactor = calculateLiquidationIncentiveFactor(lltv);

        // Step 3: Apply liquidation incentive (multiply by factor)
        uint256 seizedAssetsQuoted = wMulDown(repaidAssets, liquidationIncentiveFactor);

        // Step 4: Convert from loan token value to collateral shares (round down for safety)
        sharesToLiquidate = mulDivDown(seizedAssetsQuoted, ORACLE_PRICE_SCALE, collateralPrice);
    }

    function flashLiquidate(
        address vaultAddress,
        address[] memory liquidateAccounts,
        uint256[] memory sharesToLiquidate,
        bool[] memory isMaxLiquidate,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) external {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();

        bytes memory flashLoanData = abi.encode(
            vaultAddress, liquidateAccounts, sharesToLiquidate, isMaxLiquidate, redeemData
        );

        MORPHO.flashLoan(
            asset,
            assetsToBorrow,
            flashLoanData
        );

        ERC20 assetToken = ERC20(asset);
        uint256 finalBalance = assetToken.balanceOf(address(this));
        
        if (finalBalance > 0) {
            assetToken.transfer(owner, finalBalance);
        }
    }

    function onMorphoFlashLoan(
        uint256 /* assetsToBorrow */,
        bytes memory flashLoanData
    ) external {
        (
            address vaultAddress,
            address[] memory liquidateAccounts,
            uint256[] memory sharesToLiquidate,
            bool[] memory isMaxLiquidate,
            bytes memory redeemData
        ) = abi.decode(flashLoanData, (address, address[], uint256[], bool[], bytes));

        IYieldStrategy vaultContract = IYieldStrategy(vaultAddress);

        // Get market parameters
        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(vaultAddress);

        // Accrue interest to get current state
        MORPHO.accrueInterest(marketParams);

        // Get market state
        Market memory market = MORPHO.market(Id.wrap(keccak256(abi.encode(marketParams))));

        for (uint256 i = 0; i < liquidateAccounts.length; i++) {
            uint256 sharesToSeize = sharesToLiquidate[i];

            // If max liquidate is requested, calculate the shares to liquidate
            if (isMaxLiquidate[i]) {
                // Get the account's borrow shares
                uint256 borrowShares = MORPHO_LENDING_ROUTER.balanceOfBorrowShares(
                    liquidateAccounts[i],
                    vaultAddress
                );

                // Get the collateral price from the vault oracle
                uint256 collateralPrice = vaultContract.price(liquidateAccounts[i]);

                // Calculate shares to liquidate to repay all borrow shares
                sharesToSeize = calculateSharesToLiquidate(
                    borrowShares,
                    collateralPrice,
                    market,
                    marketParams.lltv
                );
            }

            MORPHO_LENDING_ROUTER.liquidate(liquidateAccounts[i], vaultAddress, sharesToSeize, 0);
        }

        uint256 sharesToRedeem = vaultContract.balanceOf(address(this));
        vaultContract.redeemNative(sharesToRedeem, redeemData);
    }
}