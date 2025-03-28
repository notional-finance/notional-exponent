// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

interface INotionalV4Callback {
    function onEnterPosition(uint256 sharesMinted, bytes calldata data) external;
    function onExitPosition(uint256 assetsWithdrawn, bytes calldata data) external;
}