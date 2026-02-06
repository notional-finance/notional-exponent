// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

interface IdleCreditVault {
    function lastWithdrawRequest(address account) external view returns (uint256);
    function withdrawRequests(address account) external view returns (uint256);
    function epochNumber() external view returns (uint256);
    function instantWithdrawRequests(address account) external view returns (uint256);
}

interface IdleCDOEpochVariant {
    function AATranche() external view returns (address);
    function token() external view returns (address);
    // Returns the amount of tokens received
    function depositAA(uint256 _amount) external returns (uint256);
    function depositDuringEpoch(uint256 _amount, address _tranche) external returns (uint256);
    function requestWithdraw(uint256 _amount, address _tranche) external returns (uint256);
    function isWalletAllowed(address user) external view returns (bool);
    function isEpochRunning() external view returns (bool);
    function isDepositDuringEpochDisabled() external view returns (bool);
    function epochEndDate() external view returns (uint256);
    function isAYSActive() external view returns (bool);
    function strategy() external view returns (IdleCreditVault);

    function claimInstantWithdrawRequest() external;
    function claimWithdrawRequest() external;
}
