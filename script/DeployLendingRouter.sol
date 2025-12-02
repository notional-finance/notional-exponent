// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import { ADDRESS_REGISTRY } from "../src/utils/Constants.sol";
import { AddressRegistry } from "../src/proxy/AddressRegistry.sol";
import { MorphoLendingRouter } from "../src/routers/MorphoLendingRouter.sol";
import { ProxyHelper } from "./ProxyHelper.sol";
import { GnosisHelper, MethodCall } from "./GnosisHelper.sol";
import { TimelockUpgradeableProxy } from "../src/proxy/TimelockUpgradeableProxy.sol";

contract DeployMorphoLendingRouter is ProxyHelper, GnosisHelper {
    address public PROXY = 0x9a0c630C310030C4602d1A76583a3b16972ecAa0;

    function run() public {
        vm.startBroadcast();
        MorphoLendingRouter lendingRouter = new MorphoLendingRouter();
        vm.stopBroadcast();

        if (PROXY == address(0)) {
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
        } else {
            MethodCall[] memory calls = new MethodCall[](1);
            calls[0] = MethodCall({
                to: PROXY,
                value: 0,
                callData: abi.encodeWithSelector(
                    TimelockUpgradeableProxy.initiateUpgrade.selector, address(lendingRouter)
                )
            });
            generateBatch("./script/upgrade-morpho-lending-router.json", calls);
        }
    }
}
