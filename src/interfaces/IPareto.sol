// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

interface IdleCreditVault {
    function lastWithdrawRequest(address account) external view returns (uint256);
    function withdrawRequests(address account) external view returns (uint256);
    function epochNumber() external view returns (uint256);
    function instantWithdrawRequests(address account) external view returns (uint256);
}

interface IdleKeyring {
    function admin() external view returns (address);
    function setWhitelistStatus(address account, bool status) external;
}

interface IdleCDOEpochVariant {
    function keyring() external view returns (address);
    function AATranche() external view returns (address);
    function token() external view returns (address);
    function virtualPrice(address token) external view returns (uint256);

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

interface IdleCDOEpochQueue {
    function tranche() external view returns (address);
    function idleCDOEpoch() external view returns (address);
    function epochWithdrawPrice(uint256 epoch) external view returns (uint256);
    function epochPendingClaims(uint256 epoch) external view returns (uint256);

    function requestDeposit(uint256 amount) external;
    function requestWithdraw(uint256 amount) external;
    function userDepositsEpochs(address user, uint256 epoch) external view returns (uint256);
    function userWithdrawalsEpochs(address user, uint256 epoch) external view returns (uint256);

    function claimDepositRequest(uint256 _epoch) external;
    function claimWithdrawRequest(uint256 _epoch) external;
}
