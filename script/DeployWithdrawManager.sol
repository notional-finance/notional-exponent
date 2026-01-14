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
import { TimelockUpgradeableProxy } from "../src/proxy/TimelockUpgradeableProxy.sol";
import { OriginWithdrawRequestManager, oETH } from "../src/withdraws/Origin.sol";
import { WETH } from "../src/utils/Constants.sol";
import { MidasWithdrawRequestManager } from "../src/withdraws/Midas.sol";
import { IDepositVault, IRedemptionVault } from "../src/interfaces/IMidas.sol";

address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

abstract contract DeployWithdrawManager is ProxyHelper, GnosisHelper {
    address payable public PROXY;

    function name() internal pure virtual returns (string memory);

    function deployWithdrawManager() internal virtual returns (address impl);
    function postDeployChecks(address impl) internal virtual {
        // Do nothing
    }

    function run() public {
        vm.startBroadcast();
        address impl = deployWithdrawManager();
        console.log(name(), "implementation at", impl);
        vm.stopBroadcast();

        if (PROXY == address(0)) {
            address proxy = deployProxy(impl, bytes(""));
            console.log(name(), "proxy at", address(proxy));

            MethodCall[] memory calls = new MethodCall[](1);
            calls[0] = MethodCall({
                to: address(ADDRESS_REGISTRY),
                value: 0,
                callData: abi.encodeWithSelector(AddressRegistry.setWithdrawRequestManager.selector, proxy)
            });

            generateBatch(string(abi.encodePacked("./script/list-", name(), "-withdraw-manager.json")), calls);
        } else {
            MethodCall[] memory calls = new MethodCall[](1);
            calls[0] = MethodCall({
                to: address(PROXY),
                value: 0,
                callData: abi.encodeWithSelector(TimelockUpgradeableProxy.initiateUpgrade.selector, impl)
            });

            generateBatch(
                string(abi.encodePacked("./script/list-", "upgrade-", name(), "-withdraw-manager.json")), calls
            );
        }

        postDeployChecks(impl);
    }
}

contract DeployEtherFiWithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0x71ba37c7C0eAB9F86De6D8745771c66fD3962F20);
    }

    function name() internal pure override returns (string memory) {
        return "EtherFiWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EtherFiWithdrawRequestManager());
    }
}

contract DeployEthenaWithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0x8c7C9a45916550C6fE04CDaA139672A1b5803c9F);
    }

    function name() internal pure override returns (string memory) {
        return "EthenaWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new EthenaWithdrawRequestManager());
    }

    function postDeployChecks(address impl) internal override {
        address holder = EthenaWithdrawRequestManager(PROXY).HOLDER_IMPLEMENTATION();
        vm.startPrank(ADDRESS_REGISTRY.upgradeAdmin());
        TimelockUpgradeableProxy(PROXY).initiateUpgrade(impl);
        vm.warp(block.timestamp + 7 days);
        TimelockUpgradeableProxy(PROXY)
            .executeUpgrade(abi.encodeWithSelector(EthenaWithdrawRequestManager.redeployHolder.selector));
        vm.stopPrank();

        assert(EthenaWithdrawRequestManager(PROXY).HOLDER_IMPLEMENTATION() != holder);
    }
}

contract DeployWETHWithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0xe854ceB7e57988b083b93195D092d289feD1d0ff);
    }

    function name() internal pure override returns (string memory) {
        return "WETHWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new GenericERC20WithdrawRequestManager(address(WETH)));
    }
}

contract DeployOriginWithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0x59aA04B190eC76C95a1Eb02d9a184b7fdD64b9fB);
    }

    function name() internal pure override returns (string memory) {
        return "OriginWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(new OriginWithdrawRequestManager(address(oETH)));
    }
}

contract DeployMidas_mHYPER_WithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0x18f86644781fc9F7B4641D371f377c96744EC10F);
    }

    function name() internal pure override returns (string memory) {
        return "mHYPERWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(
            new MidasWithdrawRequestManager(
                address(USDC),
                address(USDC),
                IDepositVault(0xbA9FD2850965053Ffab368Df8AA7eD2486f11024),
                IRedemptionVault(0x6Be2f55816efd0d91f52720f096006d63c366e98)
            )
        );
    }
}

contract DeployMidas_mAPOLLO_WithdrawManager is DeployWithdrawManager {
    constructor() {
        PROXY = payable(0xE4ebB6EA270a70491c3Af06376a5862a0fdA7268);
    }

    function name() internal pure override returns (string memory) {
        return "mAPOLLOWithdrawManager";
    }

    function deployWithdrawManager() internal override returns (address impl) {
        impl = address(
            new MidasWithdrawRequestManager(
                address(USDC),
                address(USDC),
                IDepositVault(0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921),
                IRedemptionVault(0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0)
            )
        );
    }
}
