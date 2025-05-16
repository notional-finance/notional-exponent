// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {MorphoLendingRouter} from "../src/routers/MorphoLendingRouter.sol";

contract DeployLendingRouter is Script {
    function run() public {
        vm.startBroadcast();
        MorphoLendingRouter lendingRouter = new MorphoLendingRouter();
        ADDRESS_REGISTRY.setLendingRouter(address(lendingRouter));
        vm.stopBroadcast();
    }
}   