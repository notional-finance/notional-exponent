// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

interface ILendingRouter {

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

    function enterPosition(
        address onBehalf,
        address collateralToken,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData
    ) external;

    function exitPosition(
        address onBehalf,
        address collateralToken,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external;

    function liquidate(
        address liquidateAccount,
        address vault,
        uint256 seizedAssets,
        uint256 repaidShares
    ) external returns (uint256 sharesToLiquidator);

    function healthFactor(address borrower, address vault) external view returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow);

    function accountCollateralBalance(address account, address vault) external view returns (uint256 collateralBalance);

}

