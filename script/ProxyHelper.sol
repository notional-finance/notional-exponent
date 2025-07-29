// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {TimelockUpgradeableProxy} from "../src/proxy/TimelockUpgradeableProxy.sol";
import {Initializable} from "../src/proxy/Initializable.sol";

abstract contract ProxyHelper is Script {
    function deployProxy(address impl, bytes memory initializeData) public returns (address) {
        vm.startBroadcast();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            impl,  abi.encodeWithSelector(Initializable.initialize.selector, initializeData)
        );
        vm.stopBroadcast();
        return address(proxy);
    }
}