// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../utils/Errors.sol";
import "../withdraws/IWithdrawRequestManager.sol";

contract AddressRegistry {
    address public upgradeAdmin;
    address public pendingUpgradeAdmin;

    address public pauseAdmin;
    address public pendingPauseAdmin;

    address public feeReceiver;

    // Token -> Withdraw Request Manager
    mapping(address => address) public withdrawRequestManagers;
    // Vault -> Token -> Withdraw Request Manager
    mapping(address => mapping(address => address)) public withdrawRequestManagerOverrides;

    event PendingUpgradeAdminSet(address indexed newPendingUpgradeAdmin);
    event UpgradeAdminTransferred(address indexed newUpgradeAdmin);
    event PendingPauseAdminSet(address indexed newPendingPauseAdmin);
    event PauseAdminTransferred(address indexed newPauseAdmin);
    event FeeReceiverTransferred(address indexed newFeeReceiver);

    constructor(address _upgradeAdmin, address _pauseAdmin, address _feeReceiver) {
        upgradeAdmin = _upgradeAdmin;
        pauseAdmin = _pauseAdmin;
        feeReceiver = _feeReceiver;
    }

    function transferUpgradeAdmin(address _newUpgradeAdmin) external {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        pendingUpgradeAdmin = _newUpgradeAdmin;
        emit PendingUpgradeAdminSet(_newUpgradeAdmin);
    }

    function acceptUpgradeOwnership() external {
        if (msg.sender != pendingUpgradeAdmin) revert Unauthorized(msg.sender);
        upgradeAdmin = pendingUpgradeAdmin;
        delete pendingUpgradeAdmin;
        emit UpgradeAdminTransferred(upgradeAdmin);
    }

    function transferPauseAdmin(address _newPauseAdmin) external {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        pendingPauseAdmin = _newPauseAdmin;
        emit PendingPauseAdminSet(_newPauseAdmin);
    }

    function acceptPauseAdmin() external {
        if (msg.sender != pendingPauseAdmin) revert Unauthorized(msg.sender);
        pauseAdmin = pendingPauseAdmin;
        delete pendingPauseAdmin;
        emit PauseAdminTransferred(pauseAdmin);
    }

    function transferFeeReceiver(address _newFeeReceiver) external {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        feeReceiver = _newFeeReceiver;
        emit FeeReceiverTransferred(_newFeeReceiver);
    }

    function setWithdrawRequestManager(address withdrawRequestManager, bool overrideExisting) external {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        address yieldToken = IWithdrawRequestManager(withdrawRequestManager).YIELD_TOKEN();
        if (withdrawRequestManagers[yieldToken] != address(0)) {
            require(overrideExisting, "Withdraw request manager already set");
        }

        withdrawRequestManagers[yieldToken] = withdrawRequestManager;
    }

    function setWithdrawRequestManagerOverride(address vault, address yieldToken, address withdrawRequestManager) external {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        // Don't get the yield token from the manager so that we can clear this if needed
        withdrawRequestManagerOverrides[vault][yieldToken] = withdrawRequestManager;
    }

    function getWithdrawRequestManager(address vault, address yieldToken) external view returns (IWithdrawRequestManager) {
        address manager = withdrawRequestManagerOverrides[vault][yieldToken];
        if (manager != address(0)) return IWithdrawRequestManager(manager);

        return IWithdrawRequestManager(withdrawRequestManagers[yieldToken]);
    }

}