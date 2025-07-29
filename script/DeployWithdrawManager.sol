// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import {ProxyHelper} from "./ProxyHelper.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";
import {GenericERC20WithdrawRequestManager} from "../src/withdraws/GenericERC20.sol";
import {EtherFiWithdrawRequestManager} from "../src/withdraws/EtherFi.sol";
import {EthenaWithdrawRequestManager} from "../src/withdraws/Ethena.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract DeployWithdrawManager is ProxyHelper, GnosisHelper {

    function deployWithdrawManager() internal virtual returns (address impl);

    function run() public {
        vm.startBroadcast();
        address impl = deployWithdrawManager();
        console.log("WithdrawManager implementation at", impl);
        vm.stopBroadcast();

        address proxy = deployProxy(impl, bytes(""));
        console.log("WithdrawManager proxy at", address(proxy));

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setWithdrawRequestManager.selector, proxy)
        });

        generateBatch("./script/list-withdraw-manager.json", calls);
    }
}

contract DeployEtherFiWithdrawManager is DeployWithdrawManager {

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EtherFiWithdrawRequestManager());
    }
}

contract DeployEthenaWithdrawManager is DeployWithdrawManager {

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EthenaWithdrawRequestManager());
    }
}