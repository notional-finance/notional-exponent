// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

error NotAuthorized(address operator, address user);
error Unauthorized(address caller);
error UnauthorizedLendingMarketTransfer(address from, address to, uint256 value);
error InsufficientYieldTokenBalance();
error InsufficientAssetsForRepayment(uint256 assetToRepay, uint256 assetsWithdrawn);
error CannotLiquidate();