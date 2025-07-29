// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";
import {MorphoLendingRouter} from "../src/routers/MorphoLendingRouter.sol";
import {ProxyHelper} from "./ProxyHelper.sol";
import {GnosisHelper, MethodCall} from "./GnosisHelper.sol";

contract DeployLendingRouter is ProxyHelper, GnosisHelper {
    function run() public {
        vm.startBroadcast();
        MorphoLendingRouter lendingRouter = new MorphoLendingRouter();
        address proxy = deployProxy(address(lendingRouter), bytes(""));
        vm.stopBroadcast();

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setLendingRouter.selector, proxy)
        });
        generateBatch("./script/list-lending-router.json", calls);
    }
}   