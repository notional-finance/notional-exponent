// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";
import {TimelockUpgradeableProxy} from "../src/proxy/TimelockUpgradeableProxy.sol";
import {Initializable} from "../src/proxy/Initializable.sol";

// Sepolia: 0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5
contract DeployAddressRegistry is Script {
    address constant UPGRADE_ADMIN = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;
    address constant PAUSE_ADMIN = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;
    address constant FEE_RECEIVER = 0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3;

    function run() public {
        vm.startBroadcast();
        address impl = address(new AddressRegistry());
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            impl,
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(UPGRADE_ADMIN, PAUSE_ADMIN, FEE_RECEIVER))
        );
        console.log("AddressRegistry deployed at", address(proxy));
        vm.stopBroadcast();
    }
}