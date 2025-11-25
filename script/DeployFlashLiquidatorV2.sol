// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {FlashLiquidatorV2} from "../src/FlashLiquidatorV2.sol";

contract DeployFlashLiquidatorV2 is Script {
    function run() public {
        vm.startBroadcast();
        FlashLiquidatorV2 flashLiquidator = new FlashLiquidatorV2();
        console.log("FlashLiquidatorV2 deployed at", address(flashLiquidator));
        vm.stopBroadcast();
    }
}