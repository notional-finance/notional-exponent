// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "../utils/Errors.sol";
import "./AddressRegistry.sol";

contract TimelockUpgradeableProxy layout at 100_000_000 is ERC1967Proxy {
    event UpgradeInitiated(address indexed newImplementation, uint32 upgradeValidAt);

    uint32 public constant UPGRADE_DELAY = 7 days;
    AddressRegistry public immutable addressRegistry;

    mapping(bytes4 => bool) public whitelistedSelectors;
    address public newImplementation;
    uint32 public upgradeValidAt;
    bool public isPaused;

    constructor(
        address _logic,
        bytes memory _data,
        address _addressRegistry
    ) ERC1967Proxy(_logic, _data) {
        addressRegistry = AddressRegistry(_addressRegistry);
    }

    receive() external payable {
        // Allow ETH transfers to succeed
    }

    /// @notice Initiates an upgrade and sets the upgrade delay.
    /// @param _newImplementation The address of the new implementation.
    function initiateUpgrade(address _newImplementation) external {
        if (msg.sender != addressRegistry.upgradeAdmin()) revert Unauthorized(msg.sender);
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

    /// @notice Executes an upgrade.
    function executeUpgrade() external {
        if (block.timestamp < upgradeValidAt) revert InvalidUpgrade();
        if (newImplementation == address(0)) revert InvalidUpgrade();
        ERC1967Utils.upgradeToAndCall(newImplementation, "");
    }

    function pause() external {
        if (msg.sender != addressRegistry.pauseAdmin()) revert Unauthorized(msg.sender);
        isPaused = true;
    }

    function unpause() external {
        if (msg.sender != addressRegistry.pauseAdmin()) revert Unauthorized(msg.sender);
        isPaused = false;
    }

    function whitelistSelectors(bytes4[] calldata selectors, bool isWhitelisted) external {
        if (msg.sender != addressRegistry.pauseAdmin()) revert Unauthorized(msg.sender);
        for (uint256 i; i < selectors.length; i++) whitelistedSelectors[selectors[i]] = isWhitelisted;
    }

    function getImplementation() external view returns (address) {
        return _implementation();
    }

    function _fallback() internal override {
        // Allows some whitelisted selectors to be called even if the proxy is paused
        if (isPaused && whitelistedSelectors[msg.sig] == false) revert Paused();
        super._fallback();
    }
}