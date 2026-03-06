// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployTimelockController is Script {
    function run() public {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
        vm.startBroadcast();
        address impl = address(new TimelockController(7 days, proposers, proposers, address(0)));
        console.log("TimelockController deployed at", address(impl));
        vm.stopBroadcast();
    }
}
