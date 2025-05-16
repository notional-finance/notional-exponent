// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {MorphoLendingRouter} from "../src/routers/MorphoLendingRouter.sol";

// Lending Router: 0x280deCD520da16e5571A6f2Fb803A57e0c16f423
contract DeployLendingRouter is Script {
    function run() public {
        vm.startBroadcast();
        MorphoLendingRouter lendingRouter = new MorphoLendingRouter();
        ADDRESS_REGISTRY.setLendingRouter(address(lendingRouter));
        vm.stopBroadcast();
    }
}   