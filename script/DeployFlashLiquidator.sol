// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {FlashLiquidator} from "../src/FlashLiquidator.sol";

contract DeployFlashLiquidator is Script {
    function run() public {
        vm.startBroadcast();
        FlashLiquidator flashLiquidator = new FlashLiquidator();
        console.log("FlashLiquidator deployed at", address(flashLiquidator));
        vm.stopBroadcast();
    }
}