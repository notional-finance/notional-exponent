// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import { ADDRESS_REGISTRY } from "../src/utils/Constants.sol";
import { AddressRegistry } from "../src/proxy/AddressRegistry.sol";
import { MorphoLendingRouter } from "../src/routers/MorphoLendingRouter.sol";
import { ProxyHelper } from "./ProxyHelper.sol";
import { GnosisHelper, MethodCall } from "./GnosisHelper.sol";

contract DeployMorphoLendingRouter is ProxyHelper, GnosisHelper {
    function run() public {
        vm.startBroadcast();
        MorphoLendingRouter lendingRouter = new MorphoLendingRouter();
        vm.stopBroadcast();

        console.log("MorphoLendingRouter implementation at", address(lendingRouter));
        address proxy = deployProxy(address(lendingRouter));
        console.log("MorphoLendingRouter proxy at", proxy);

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setLendingRouter.selector, proxy)
        });
        generateBatch("./script/list-morpho-lending-router.json", calls);
    }
}
