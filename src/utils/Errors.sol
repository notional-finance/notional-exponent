// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

error NotAuthorized(address operator, address user);
error Unauthorized(address caller);
error UnauthorizedLendingMarketTransfer(address from, address to, uint256 value);
error InsufficientYieldTokenBalance();
error InsufficientAssetsForRepayment(uint256 assetsToRepay, uint256 assetsWithdrawn);
error CannotLiquidate(uint256 maxLiquidateShares, uint256 seizedAssets);
error Paused();
error CannotExitPositionWithinCooldownPeriod();
error CannotReceiveSplitWithdrawRequest();

error CannotEnterPosition();
error InvalidUpgrade();
error InvalidInitialization();

function checkRevert(bool success, bytes memory result) pure {
    if (!success) {
        // If the result length is less than 4, it's not a valid revert
        if (result.length < 4) revert();
        
        // Get the error selector (first 4 bytes)
        bytes4 errorSelector;
        assembly {
            errorSelector := mload(add(result, 32))
        }
        
        // If it's a standard revert message (Error(string) selector)
        if (errorSelector == 0x08c379a0) {
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
        
        // For custom errors, we need to propagate the entire result
        assembly {
            revert(add(result, 32), mload(result))
        }
    }
}