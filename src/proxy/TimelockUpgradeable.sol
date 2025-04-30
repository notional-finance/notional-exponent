// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../utils/Errors.sol";

/// @title TimelockUpgradeable
/// @notice A contract that allows for the upgrade of a contract with a hardcoded delay.
contract TimelockUpgradeable is UUPSUpgradeable, Initializable {

    event UpgradeInitiated(address indexed newImplementation, uint32 upgradeValidAt);

    address public upgradeOwner;
    address public newImplementation;
    uint32 public upgradeValidAt;
    uint32 public constant UPGRADE_DELAY = 7 days;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @param data The data to initialize the contract with.
    function _initialize(bytes calldata data) internal virtual { }

    /// @notice Initializes the contract.
    /// @param _upgradeOwner The address of the owner of the upgrade.
    /// @param data The data to initialize the contract with.
    function initialize(address _upgradeOwner, bytes calldata data) public initializer {
        upgradeOwner = _upgradeOwner;
        _initialize(data);
    }

    /// @notice Initiates an upgrade and sets the upgrade delay.
    /// @param _newImplementation The address of the new implementation.
    function initiateUpgrade(address _newImplementation) external {
        if (msg.sender != upgradeOwner) revert Unauthorized(msg.sender);
        newImplementation = _newImplementation;
        if (_newImplementation == address(0)) {
            // Setting the new implementation to the zero address will cancel
            // any pending upgrade.
            upgradeValidAt = 0;
        } else {
            upgradeValidAt = uint32(block.timestamp) + UPGRADE_DELAY;
        }
        emit UpgradeInitiated(_newImplementation, upgradeValidAt);
    }

    /// @dev Authorizes an upgrade and ensures the upgrade delay has passed. Anyone
    /// can call this function but the upgrade will only be limited to the listed implementation
    function _authorizeUpgrade(address _newImplementation) internal view override {
        if (block.timestamp < upgradeValidAt) revert InvalidUpgrade();
        if (_newImplementation != newImplementation) revert InvalidUpgrade();
        if (_newImplementation == address(0)) revert InvalidUpgrade();
    }
}