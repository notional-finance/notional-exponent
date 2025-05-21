// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {Unauthorized} from "../interfaces/Errors.sol";
import {IWithdrawRequestManager} from "../interfaces/IWithdrawRequestManager.sol";

/// @notice Registry for the addresses for different components of the protocol.
contract AddressRegistry {
    event PendingUpgradeAdminSet(address indexed newPendingUpgradeAdmin);
    event UpgradeAdminTransferred(address indexed newUpgradeAdmin);
    event PendingPauseAdminSet(address indexed newPendingPauseAdmin);
    event PauseAdminTransferred(address indexed newPauseAdmin);
    event FeeReceiverTransferred(address indexed newFeeReceiver);
    event WithdrawRequestManagerSet(address indexed yieldToken, address indexed withdrawRequestManager);
    event LendingRouterSet(address indexed lendingRouter);

    /// @notice Address of the admin that is allowed to:
    /// - Upgrade TimelockUpgradeableProxy contracts given a 7 day timelock
    /// - Transfer the upgrade admin role
    /// - Set the pause admin
    /// - Set the fee receiver
    /// - Add reward tokens to the RewardManager
    /// - Set the WithdrawRequestManager for a yield token
    /// - Whitelist vaults for the WithdrawRequestManager
    /// - Whitelist new lending routers
    address public upgradeAdmin;
    address public pendingUpgradeAdmin;

    /// @notice Address of the admin that is allowed to selectively pause or unpause
    /// TimelockUpgradeableProxy contracts
    address public pauseAdmin;
    address public pendingPauseAdmin;

    /// @notice Address of the account that receives the protocol fees
    address public feeReceiver;

    /// @notice Mapping of yield token to WithdrawRequestManager
    mapping(address token => address withdrawRequestManager) public withdrawRequestManagers;

    /// @notice Mapping of lending router to boolean indicating if it is whitelisted
    mapping(address lendingRouter => bool isLendingRouter) public lendingRouters;

    /// @notice Constructor to set the initial admins, this contract is intended to be
    /// non-upgradeable
    constructor(address _upgradeAdmin, address _pauseAdmin, address _feeReceiver) {
        upgradeAdmin = _upgradeAdmin;
        pauseAdmin = _pauseAdmin;
        feeReceiver = _feeReceiver;
    }

    modifier onlyUpgradeAdmin() {
        if (msg.sender != upgradeAdmin) revert Unauthorized(msg.sender);
        _;
    }

    function transferUpgradeAdmin(address _newUpgradeAdmin) external onlyUpgradeAdmin {
        pendingUpgradeAdmin = _newUpgradeAdmin;
        emit PendingUpgradeAdminSet(_newUpgradeAdmin);
    }

    function acceptUpgradeOwnership() external {
        if (msg.sender != pendingUpgradeAdmin) revert Unauthorized(msg.sender);
        upgradeAdmin = pendingUpgradeAdmin;
        delete pendingUpgradeAdmin;
        emit UpgradeAdminTransferred(upgradeAdmin);
    }

    function transferPauseAdmin(address _newPauseAdmin) external onlyUpgradeAdmin {
        pendingPauseAdmin = _newPauseAdmin;
        emit PendingPauseAdminSet(_newPauseAdmin);
    }

    function acceptPauseAdmin() external {
        if (msg.sender != pendingPauseAdmin) revert Unauthorized(msg.sender);
        pauseAdmin = pendingPauseAdmin;
        delete pendingPauseAdmin;
        emit PauseAdminTransferred(pauseAdmin);
    }

    function transferFeeReceiver(address _newFeeReceiver) external onlyUpgradeAdmin {
        feeReceiver = _newFeeReceiver;
        emit FeeReceiverTransferred(_newFeeReceiver);
    }

    function setWithdrawRequestManager(address withdrawRequestManager) external onlyUpgradeAdmin {
        address yieldToken = IWithdrawRequestManager(withdrawRequestManager).YIELD_TOKEN();
        // Prevent accidental override of a withdraw request manager, this is dangerous
        // as it could lead to withdraw requests being stranded on the deprecated withdraw
        // request manager. Managers can be upgraded using a TimelockUpgradeableProxy.
        require (withdrawRequestManagers[yieldToken] == address(0), "Withdraw request manager already set");

        withdrawRequestManagers[yieldToken] = withdrawRequestManager;
        emit WithdrawRequestManagerSet(yieldToken, withdrawRequestManager);
    }

    function getWithdrawRequestManager(address yieldToken) external view returns (IWithdrawRequestManager) {
        return IWithdrawRequestManager(withdrawRequestManagers[yieldToken]);
    }

    function setLendingRouter(address lendingRouter) external onlyUpgradeAdmin {
        lendingRouters[lendingRouter] = true;
        emit LendingRouterSet(lendingRouter);
    }

    function isLendingRouter(address lendingRouter) external view returns (bool) {
        return lendingRouters[lendingRouter];
    }
}