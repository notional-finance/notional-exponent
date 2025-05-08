// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";

contract DeployAddressRegistry is Script {
    address constant UPGRADE_ADMIN = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;
    address constant PAUSE_ADMIN = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;
    address constant FEE_RECEIVER = 0x02479BFC7Dce53A02e26fE7baea45a0852CB0909;

    function run() public {
        vm.startBroadcast();
        address impl = address(new AddressRegistry(UPGRADE_ADMIN, PAUSE_ADMIN, FEE_RECEIVER));
        console.log("AddressRegistry deployed at", impl);
        vm.stopBroadcast();
    }
}