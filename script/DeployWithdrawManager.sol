// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import { ProxyHelper } from "./ProxyHelper.sol";
import { ADDRESS_REGISTRY } from "../src/utils/Constants.sol";
import { AddressRegistry } from "../src/proxy/AddressRegistry.sol";
import { GenericERC20WithdrawRequestManager } from "../src/withdraws/GenericERC20.sol";
import { EtherFiWithdrawRequestManager } from "../src/withdraws/EtherFi.sol";
import { EthenaWithdrawRequestManager } from "../src/withdraws/Ethena.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract DeployWithdrawManager is ProxyHelper, GnosisHelper {
    function name() internal pure virtual returns (string memory);

    function deployWithdrawManager() internal virtual returns (address impl);

    function run() public {
        vm.startBroadcast();
        address impl = deployWithdrawManager();
        console.log(name(), "implementation at", impl);
        vm.stopBroadcast();

        address proxy = deployProxy(impl, bytes(""));
        console.log(name(), "proxy at", address(proxy));

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setWithdrawRequestManager.selector, proxy)
        });

        generateBatch(string(abi.encodePacked("./script/list-", name(), "-withdraw-manager.json")), calls);
    }
}

contract DeployEtherFiWithdrawManager is DeployWithdrawManager {
    address public constant PROXY = 0x71ba37c7C0eAB9F86De6D8745771c66fD3962F20;

    function name() internal pure override returns (string memory) {
        return "EtherFiWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EtherFiWithdrawRequestManager());
    }
}

contract DeployEthenaWithdrawManager is DeployWithdrawManager {
    address public constant PROXY = 0x8c7C9a45916550C6fE04CDaA139672A1b5803c9F;

    function name() internal pure override returns (string memory) {
        return "EthenaWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EthenaWithdrawRequestManager());
    }
}
