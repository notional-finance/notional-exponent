// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IConcreteVault is IERC4626 {
    error NoClaimableRequest();
    error EpochNotProcessed(uint256 epochNumber);

    function getEpochPricePerShare(uint256 epochNumber) external view returns (uint256);
    function latestEpochID() external view returns (uint256);
    function claimWithdrawal(uint256[] memory epochIDs) external;
    function claimWithdrawal(address asset, address user, uint256[] calldata epochIDs, uint8 decimals) external;
    function pastEpochsUnclaimedAssets() external view returns (uint256);
}

interface IConcreteWhitelistHook {
    function owner() external view returns (address);
    function whitelistUsers(address[] memory users) external;
}
