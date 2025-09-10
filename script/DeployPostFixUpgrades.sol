// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import "./DeployVault.sol";
import "./DeployWithdrawManager.sol";
import { AddressRegistry } from "../src/proxy/AddressRegistry.sol";
import { MorphoLendingRouter } from "../src/routers/MorphoLendingRouter.sol";
import { EtherFiWithdrawRequestManager } from "../src/withdraws/EtherFi.sol";
import { EthenaWithdrawRequestManager } from "../src/withdraws/Ethena.sol";

contract DeployPostFixUpgrades is Script, GnosisHelper {
    EtherFiStaking internal etherFiStaking = new EtherFiStaking();
    EthenaStaking internal ethenaStaking = new EthenaStaking();
    DeployEtherFiWithdrawManager internal deployEtherFiWithdrawManager = new DeployEtherFiWithdrawManager();
    DeployEthenaWithdrawManager internal deployEthenaWithdrawManager = new DeployEthenaWithdrawManager();

    function run() public {
        MethodCall[] memory calls = new MethodCall[](6);

        vm.startBroadcast();
        AddressRegistry addressRegistry = new AddressRegistry();
        console.log("AddressRegistry deployed at", address(addressRegistry));

        MorphoLendingRouter morphoLendingRouter = new MorphoLendingRouter();
        console.log("MorphoLendingRouter deployed at", address(morphoLendingRouter));

        EtherFiWithdrawRequestManager etherFiWithdrawRequestManager = new EtherFiWithdrawRequestManager();
        console.log("EtherFiWithdrawRequestManager deployed at", address(etherFiWithdrawRequestManager));

        EthenaWithdrawRequestManager ethenaWithdrawRequestManager = new EthenaWithdrawRequestManager();
        console.log("EthenaWithdrawRequestManager deployed at", address(ethenaWithdrawRequestManager));
        vm.stopBroadcast();

        address etherFiVault = etherFiStaking.deployVault();
        console.log("EtherFiStaking deployed at", address(etherFiVault));

        address ethenaVault = ethenaStaking.deployVault();
        console.log("EthenaStaking deployed at", address(ethenaVault));

        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(TimelockUpgradeableProxy.initiateUpgrade.selector, addressRegistry)
        });

        calls[1] = MethodCall({
            to: address(MORPHO_LENDING_ROUTER),
            value: 0,
            callData: abi.encodeWithSelector(
                TimelockUpgradeableProxy.initiateUpgrade.selector, address(morphoLendingRouter)
            )
        });

        calls[2] = MethodCall({
            to: address(deployEtherFiWithdrawManager.PROXY()),
            value: 0,
            callData: abi.encodeWithSelector(
                TimelockUpgradeableProxy.initiateUpgrade.selector, address(etherFiWithdrawRequestManager)
            )
        });

        calls[3] = MethodCall({
            to: address(deployEthenaWithdrawManager.PROXY()),
            value: 0,
            callData: abi.encodeWithSelector(
                TimelockUpgradeableProxy.initiateUpgrade.selector, address(ethenaWithdrawRequestManager)
            )
        });

        calls[4] = MethodCall({
            to: address(etherFiStaking.proxy()),
            value: 0,
            callData: abi.encodeWithSelector(TimelockUpgradeableProxy.initiateUpgrade.selector, address(etherFiVault))
        });

        calls[5] = MethodCall({
            to: address(ethenaStaking.proxy()),
            value: 0,
            callData: abi.encodeWithSelector(TimelockUpgradeableProxy.initiateUpgrade.selector, address(ethenaVault))
        });

        generateBatch("./script/list-post-fix-upgrades.json", calls);
    }
}
