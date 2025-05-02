// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../utils/Errors.sol";

contract AddressRegistry {
    address public upgradeAdmin;
    address public pendingUpgradeAdmin;

    address public pauseAdmin;
    address public pendingPauseAdmin;

    event PendingUpgradeAdminSet(address indexed newPendingUpgradeAdmin);
    event UpgradeAdminTransferred(address indexed newUpgradeAdmin);
    event PendingPauseAdminSet(address indexed newPendingPauseAdmin);
    event PauseAdminTransferred(address indexed newPauseAdmin);

    constructor(address _upgradeAdmin, address _pauseAdmin) {
        upgradeAdmin = _upgradeAdmin;
        pauseAdmin = _pauseAdmin;
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
}