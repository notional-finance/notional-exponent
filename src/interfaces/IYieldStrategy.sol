// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

enum LendingMarket {
    NONE,
    MORPHO,
    EULER,
    SILO
}

enum Operation {
    WITHDRAW_AND_BURN,
    LIQUIDATE_AND_BURN
}

struct BorrowData {
    LendingMarket market;
    bytes callData;
}

/**
 * @notice A strategy vault that is specifically designed for leveraged yield
 * strategies. Minting and burning shares are restricted to the `enterPosition`
 * and `exitPosition` functions respectively. This means that shares will be
 * exclusively held on lending markets as collateral unless the LendingMarket is
 * set to NONE. In this case, the user will just be holding the yield token without
 * any leverage.
 *
 * The `transfer` function is non-standard in that transfers off of a lending market
 * are restricted to ensure that liquidation conditions are met.
 */
interface IYieldStrategy is IERC20, IERC20Metadata {

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address assetTokenAddress);

    /**
     * @dev Returns the address of the yield token held by the vault. Does not equal the share token,
     * which represents each user's share of the yield tokens held by the vault.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function yieldToken() external view returns (address yieldTokenAddress);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Returns the amount of yield tokens that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     */
    function convertToYieldToken(uint256 shares) external view returns (uint256 yieldTokens);

    /**
     * @dev Returns the fee rate of the vault where 100% = 1e18.
     */
    function feeRate() external view returns (uint256 feeRate);

    /**
     * @dev Returns the balance of yield tokens accrued by the vault.
     */
    function feesAccrued() external view returns (uint256 feesAccrued);

    /**
     * @dev Collects the fees accrued by the vault. Only callable by the owner.
     */
    function collectFees() external;

    /**
     * @dev Enters a position by depositing assets and borrowing funds and using
     * the total amount to enter into the yield token. This is the only way to mint
     * shares.
     *
     * @param onBehalf The address to enter the position on behalf of. Requires authorization if
     * msg.sender != onBehalf.
     * @param depositAssetAmount The amount of assets to deposit as margin.
     * @param borrowData identifies the lending market and the calldata required to borrow
     * @param depositData calldata used to enter into the yield token.
     * @param callbackData data to be returned to an optional callback function.
     *
     * @return shares The amount of shares minted to the user.
     */
    function enterPosition(
        address onBehalf,
        uint256 depositAssetAmount,
        BorrowData calldata borrowData,
        bytes calldata depositData,
        bytes calldata callbackData
    ) external returns (uint256 shares);

    /**
     * @dev Exits a position by withdrawing shares and repaying borrowed funds. This is the only
     * way to burn shares.
     *
     * @param onBehalf The address to exit the position on behalf of. Requires authorization if
     * msg.sender != onBehalf.
     * @param receiver The address to receive any profits from the exit.
     * @param sharesToRedeem The amount of shares to withdraw from the lending market and redeem.
     * @param assetToRepay The amount of asset to repay to the lending market.
     * @param redeemData calldata used to redeem the yield token.
     * @param callbackData data to be returned to an optional callback function.
     *
     * @return assetsWithdrawn The amount of assets withdrawn from the lending market.
     */
    function exitPosition(
        address onBehalf,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData,
        bytes calldata callbackData
    ) external returns (uint256 assetsWithdrawn);

    /**
     * @dev Swaps the lending market for the user.
     *
     * @param onBehalf The address to swap the lending market on behalf of. Requires authorization if
     * msg.sender != onBehalf.
     * @param borrowData identifies the lending market and the calldata required to borrow
     * @param callbackData data to be returned to an optional callback function.
     */
    function swapLendingMarket(
        address onBehalf,
        BorrowData calldata borrowData,
        bytes calldata callbackData
    ) external;

    /**
     * @dev Liquidates a position by repaying borrowed funds and withdrawing assets. Used to
     * ensure that the position can be liquidated in the case of withdraw requests.
     *
     * @param liquidateAccount The address to liquidate.
     * @param sharesToLiquidate The amount of shares to liquidate.
     * @param assetToRepay The amount of asset to repay to the lending market.
     * @param redeemData calldata used to redeem the yield token.
     */
    function liquidate(
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external;

    /**
     * @dev Authorizes an address to manage a user's position.
     *
     * @param operator The address to authorize.
     * @param approved The authorization status.
     */
    function setApproval(address operator, bool approved) external;

    /**
     * @dev Returns the authorization status of an address.
     *
     * @param user The address to check the authorization status of.
     * @param operator The address to check the authorization status of.
     *
     * @return The authorization status.
     */
    function isApproved(address user, address operator) external view returns (bool);
}
