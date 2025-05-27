// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "./GnosisHelper.sol";
import {ADDRESS_REGISTRY} from "../src/utils/Constants.sol";
import {AddressRegistry} from "../src/proxy/AddressRegistry.sol";
import {GenericERC20WithdrawRequestManager} from "../src/withdraws/GenericERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract DeployWithdrawManager is Script, GnosisHelper {

    function deployWithdrawManager() internal virtual returns (address impl);

    function run() public {
        vm.startBroadcast();
        address impl = deployWithdrawManager();
        console.log("WithdrawManager deployed at", impl);
        vm.stopBroadcast();

        MethodCall[] memory calls = new MethodCall[](1);
        calls[0] = MethodCall({
            to: address(ADDRESS_REGISTRY),
            value: 0,
            callData: abi.encodeWithSelector(AddressRegistry.setWithdrawRequestManager.selector, impl, false)
        });

        generateBatch("./script/list-withdraw-manager.json", calls);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000_000e18);
    }
}

contract DeployMockERC20WithdrawManager is DeployWithdrawManager {
    address MOCK_ERC20;

    function deployWithdrawManager() internal override returns (address impl) {
        MOCK_ERC20 = address(new MockERC20("MockERC20", "MOCK"));
        // 0xa40aedAac28F9574124D7c8EFf59732cC77f1DD4
        console.log("Mock ERC20 deployed at", MOCK_ERC20);
        impl = address(new GenericERC20WithdrawRequestManager(MOCK_ERC20));
        // 0x72Ec9dE3eFD22552b6dc17142EAd505A48940D4E
    }
}
