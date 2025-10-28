// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {MaxLeverageExecutor} from "../src/MaxLeverageExecutor.sol";

contract DeployMaxLeverageExecutor is Script {
    function run(address morphoLendingRouter) public {
        vm.startBroadcast();
        MaxLeverageExecutor maxLeverageExecutor = new MaxLeverageExecutor(morphoLendingRouter);
        console.log("MaxLeverageExecutor deployed at", address(maxLeverageExecutor));
        vm.stopBroadcast();
    }
}