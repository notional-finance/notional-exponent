// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {MorphoLendingRouter} from "./routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Market, Id} from "./interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MaxLeverageExecutor
 * @notice Executes precise max leverage calculations and exits in a single atomic transaction
 * @dev Eliminates timing issues by performing calculation and execution atomically
 */
contract MaxLeverageExecutor {
    uint256 private constant ORACLE_PRICE_SCALE = 1e36;
    uint256 private constant WAD = 1e18;
    uint256 private constant VIRTUAL_ASSETS = 1;
    uint256 private constant VIRTUAL_SHARES = 1e6;

    MorphoLendingRouter public immutable MORPHO_LENDING_ROUTER;

    constructor(address _morphoLendingRouter) {
        MORPHO_LENDING_ROUTER = MorphoLendingRouter(_morphoLendingRouter);
    }

    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + d - 1) / d;
    }

    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return mulDivUp(shares, totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /**
     * @notice Calculates and executes max leverage exit in a single atomic transaction
     * @param vault The vault address to exit from
     * @param redeemData The redeem data for the vault
     */
    function executeMaxLeverage(
        address vault,
        bytes memory redeemData
    ) external {
        IYieldStrategy vaultContract = IYieldStrategy(vault);
        
        // Get market parameters
        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(vault);
        
        // Accrue interest to get current state
        MORPHO.accrueInterest(marketParams);
        
        // Get current balances
        uint256 collateralBalance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, vault);
        uint256 borrowShares = MORPHO_LENDING_ROUTER.balanceOfBorrowShares(msg.sender, vault);
        
        require(collateralBalance > 0, "No collateral balance");
        require(borrowShares > 0, "No borrow balance");
        
        // Get market state
        Market memory market = MORPHO.market(Id.wrap(keccak256(abi.encode(marketParams))));
        
        // Calculate exact borrowed amount using Morpho's precise math
        uint256 borrowed = toAssetsUp(borrowShares, market.totalBorrowAssets, market.totalBorrowShares);
        
        // Get current collateral price
        uint256 collateralPrice = vaultContract.price(msg.sender);
        
        // Calculate minimum required collateral to stay healthy
        // From Morpho: borrowed = requiredCollateral * collateralPrice / ORACLE_PRICE_SCALE * lltv / WAD
        // Solving for requiredCollateral:
        uint256 requiredCollateral = mulDivUp(
            mulDivUp(borrowed, WAD, marketParams.lltv),
            ORACLE_PRICE_SCALE,
            collateralPrice
        );
        
        require(collateralBalance > requiredCollateral, "Position too close to liquidation");
        
        // Execute the exit position atomically
        MORPHO_LENDING_ROUTER.exitPosition(
            msg.sender,
            vault,
            msg.sender,
            collateralBalance - requiredCollateral,
            0, // No asset to repay
            redeemData
        );
    }

}