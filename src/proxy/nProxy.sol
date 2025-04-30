// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract nProxy is ERC1967Proxy {
    constructor(
        address _logic,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) {}

    receive() external payable {
        // Allow ETH transfers to succeed
    }

    function getImplementation() external view returns (address) {
        return _implementation();
    }
}