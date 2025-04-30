// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "../utils/Errors.sol";

contract TimelockUpgradeableProxy layout at 100_000_000 is ERC1967Proxy {
    event UpgradeInitiated(address indexed newImplementation, uint32 upgradeValidAt);

    uint32 public constant UPGRADE_DELAY = 7 days;
    address public upgradeOwner;
    address public pendingUpgradeOwner;
    address public newImplementation;
    uint32 public upgradeValidAt;

    constructor(
        address _upgradeOwner,
        address _logic,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {
        upgradeOwner = _upgradeOwner;
    }

    receive() external payable {
        // Allow ETH transfers to succeed
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

    function transferUpgradeOwnership(address _newUpgradeOwner) external {
        if (msg.sender != upgradeOwner) revert Unauthorized(msg.sender);
        pendingUpgradeOwner = _newUpgradeOwner;
    }

    function acceptUpgradeOwnership() external {
        if (msg.sender != pendingUpgradeOwner) revert Unauthorized(msg.sender);
        upgradeOwner = pendingUpgradeOwner;
        pendingUpgradeOwner = address(0);
    }

    /// @notice Executes an upgrade.
    function executeUpgrade() external {
        if (block.timestamp < upgradeValidAt) revert InvalidUpgrade();
        if (newImplementation == address(0)) revert InvalidUpgrade();
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    function getImplementation() external view returns (address) {
        return _implementation();
    }
}