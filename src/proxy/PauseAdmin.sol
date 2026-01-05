// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { ADDRESS_REGISTRY } from "../utils/Constants.sol";
import { TimelockUpgradeableProxy } from "./TimelockUpgradeableProxy.sol";
import { Unauthorized } from "../interfaces/Errors.sol";

contract PauseAdmin {
    mapping(address pendingPauser => bool isPendingPauser) public pendingPausers;
    mapping(address pauser => bool isPauser) public pausers;

    modifier onlyPauser() {
        if (!pausers[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    modifier onlyUpgradeAdmin() {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        _;
    }

    function acceptPauseAdmin() external onlyUpgradeAdmin {
        ADDRESS_REGISTRY.acceptPauseAdmin();
    }

    function addPendingPauser(address pauser) external onlyUpgradeAdmin {
        pendingPausers[pauser] = true;
    }

    function acceptPauser() external {
        require(pendingPausers[msg.sender], "Not a pending pauser");
        pausers[msg.sender] = true;
        delete pendingPausers[msg.sender];
    }

    function pause(address pausableContract) external onlyPauser {
        TimelockUpgradeableProxy(payable(pausableContract)).pause();
    }

    function pauseAll() external onlyPauser {
        address[] memory pausableContracts = ADDRESS_REGISTRY.getAllPausableContracts();
        for (uint256 i = 0; i < pausableContracts.length; i++) {
            TimelockUpgradeableProxy(payable(pausableContracts[i])).pause();
        }
    }

    function whitelistSelectors(
        address pausableContract,
        bytes4[] calldata selectors,
        bool isWhitelisted
    )
        external
        onlyUpgradeAdmin
    {
        TimelockUpgradeableProxy(payable(pausableContract)).whitelistSelectors(selectors, isWhitelisted);
    }
}
