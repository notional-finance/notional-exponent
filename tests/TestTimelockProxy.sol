// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";
import "../src/proxy/AddressRegistry.sol";
import "../src/proxy/PauseAdmin.sol";

contract MockInitializable is Initializable {
    bool public didInitialize;

    function doSomething() external pure returns (bool) {
        return true;
    }

    function _initialize(
        bytes calldata /* data */
    )
        internal
        override
    {
        didInitialize = true;
    }
}

contract TestTimelockProxy is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 23_033_352;

    Initializable public impl;
    TimelockUpgradeableProxy public proxy;
    address public upgradeOwner;
    PauseAdmin public pauseAdmin;
    address public feeReceiver;
    address public pauser;
    AddressRegistry public registry = ADDRESS_REGISTRY;

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        upgradeOwner = ADDRESS_REGISTRY.upgradeAdmin();
        pauseAdmin = new PauseAdmin();
        feeReceiver = ADDRESS_REGISTRY.feeReceiver();
        pauser = makeAddr("pauser");

        vm.startPrank(upgradeOwner);
        registry.transferPauseAdmin(address(pauseAdmin));
        pauseAdmin.acceptPauseAdmin();
        vm.stopPrank();

        impl = new MockInitializable();
        proxy = new TimelockUpgradeableProxy(
            address(impl), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol"))
        );

        // Upgrade the AddressRegistry
        address newAddressRegistry = address(new AddressRegistry());
        vm.startPrank(upgradeOwner);
        TimelockUpgradeableProxy(payable(address(ADDRESS_REGISTRY))).initiateUpgrade(newAddressRegistry);
        vm.warp(block.timestamp + 7 days);
        TimelockUpgradeableProxy(payable(address(ADDRESS_REGISTRY))).executeUpgrade(bytes(""));
        vm.stopPrank();
    }

    function test_cannotReinitializeImplementation() public {
        // Cannot re-initialize the implementation
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        impl.initialize(bytes(""));
    }

    function test_initializeProxy() public {
        // Cannot re-initialize the proxy
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        Initializable(address(proxy)).initialize(bytes(""));

        // Check that the proxy is initialized
        assertEq(MockInitializable(address(proxy)).didInitialize(), true);
    }

    function test_initiateUpgrade() public {
        Initializable timelock2 = new Initializable();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.initiateUpgrade(address(timelock2));

        vm.expectEmit(true, true, true, true);
        emit TimelockUpgradeableProxy.UpgradeInitiated(
            address(timelock2), uint32(block.timestamp + proxy.UPGRADE_DELAY())
        );
        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));

        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.startPrank(upgradeOwner);
        // Cannot upgrade before the delay
        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade(bytes(""));

        vm.warp(block.timestamp + proxy.UPGRADE_DELAY() + 1);
        proxy.executeUpgrade(bytes(""));

        assertEq(proxy.getImplementation(), address(timelock2));
        vm.stopPrank();
    }

    function test_cancelUpgrade() public {
        Initializable timelock2 = new Initializable();

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));
        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(0));

        assertEq(proxy.newImplementation(), address(0));
        assertEq(proxy.upgradeValidAt(), uint32(0));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.executeUpgrade(bytes(""));

        vm.startPrank(upgradeOwner);
        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade(bytes(""));
        vm.stopPrank();
    }

    function test_addPauser() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        pauseAdmin.addPendingPauser(pauser);

        vm.prank(upgradeOwner);
        pauseAdmin.addPendingPauser(pauser);

        assertEq(pauseAdmin.pendingPausers(pauser), true);

        vm.prank(pauser);
        pauseAdmin.acceptPauser();

        assertEq(pauseAdmin.pausers(pauser), true);
        assertEq(pauseAdmin.pendingPausers(pauser), false);
    }

    function test_pause_RevertsIf_notPauser() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.pause();
    }

    function test_removePauser() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        pauseAdmin.removePauser(pauser);

        vm.prank(upgradeOwner);
        pauseAdmin.addPendingPauser(pauser);

        vm.startPrank(pauser);
        pauseAdmin.acceptPauser();
        vm.stopPrank();

        assertEq(pauseAdmin.pausers(pauser), true);

        vm.prank(upgradeOwner);
        pauseAdmin.removePauser(pauser);
        assertEq(pauseAdmin.pausers(pauser), false);

        vm.startPrank(pauser);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, pauser));
        pauseAdmin.pause(address(proxy));
        vm.stopPrank();
    }

    function test_pause_given_contract() public {
        vm.prank(upgradeOwner);
        pauseAdmin.addPendingPauser(pauser);

        vm.startPrank(pauser);
        pauseAdmin.acceptPauser();
        pauseAdmin.pause(address(proxy));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Paused.selector));
        MockInitializable(address(proxy)).doSomething();

        // Cannot unpause if not the pause admin
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.unpause();

        // Whitelist the doSomething function
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockInitializable.doSomething.selector;

        // Cannot call this directly
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.whitelistSelectors(selectors, true);

        // Can call via the upgrade admin
        vm.prank(upgradeOwner);
        pauseAdmin.whitelistSelectors(address(proxy), selectors, true);

        assertEq(MockInitializable(address(proxy)).doSomething(), true);

        vm.prank(upgradeOwner);
        proxy.unpause();

        assertEq(MockInitializable(address(proxy)).doSomething(), true);
    }

    function test_transferUpgradeOwnership() public {
        address newUpgradeOwner = makeAddr("newUpgradeOwner");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferUpgradeAdmin(newUpgradeOwner);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PendingUpgradeAdminSet(newUpgradeOwner);
        vm.prank(upgradeOwner);
        registry.transferUpgradeAdmin(newUpgradeOwner);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.acceptUpgradeOwnership();

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.UpgradeAdminTransferred(newUpgradeOwner);
        vm.prank(newUpgradeOwner);
        registry.acceptUpgradeOwnership();

        assertEq(registry.upgradeAdmin(), newUpgradeOwner);
    }

    function test_transferPauseAdmin() public {
        address newPauseAdmin = makeAddr("newPauseAdmin");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferPauseAdmin(newPauseAdmin);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PendingPauseAdminSet(newPauseAdmin);
        vm.prank(upgradeOwner);
        registry.transferPauseAdmin(newPauseAdmin);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.acceptPauseAdmin();

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PauseAdminTransferred(newPauseAdmin);
        vm.prank(newPauseAdmin);
        registry.acceptPauseAdmin();

        assertEq(registry.pauseAdmin(), newPauseAdmin);
    }

    function test_transferFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferFeeReceiver(newFeeReceiver);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.FeeReceiverTransferred(newFeeReceiver);
        vm.prank(upgradeOwner);
        registry.transferFeeReceiver(newFeeReceiver);

        assertEq(registry.feeReceiver(), newFeeReceiver);
    }

    function test_addPausableContract_onlyUpgradeAdmin() public {
        // Deploy a new TimelockUpgradeableProxy to simulate a new pausable contract
        Initializable newImpl = new MockInitializable();
        TimelockUpgradeableProxy newProxy = new TimelockUpgradeableProxy(
            address(newImpl), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol"))
        );

        // Non-upgradeAdmin cannot add pausable contracts
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.addPausableContract(address(newProxy));

        // PauseAdmin cannot add pausable contracts
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(pauseAdmin)));
        vm.prank(address(pauseAdmin));
        registry.addPausableContract(address(newProxy));

        // UpgradeAdmin can add pausable contracts
        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PausableContractAdded(address(newProxy));
        vm.prank(upgradeOwner);
        registry.addPausableContract(address(newProxy));

        // Verify the contract was added
        address[] memory pausableContracts = registry.getAllPausableContracts();
        bool found = false;
        for (uint256 i = 0; i < pausableContracts.length; i++) {
            if (pausableContracts[i] == address(newProxy)) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Pausable contract should be in the list");
    }

    function test_addPausableContract_multipleContracts() public {
        // Deploy multiple new proxies
        Initializable impl1 = new MockInitializable();
        TimelockUpgradeableProxy proxy1 = new TimelockUpgradeableProxy(
            address(impl1), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name1", "symbol1"))
        );

        Initializable impl2 = new MockInitializable();
        TimelockUpgradeableProxy proxy2 = new TimelockUpgradeableProxy(
            address(impl2), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name2", "symbol2"))
        );

        Initializable impl3 = new MockInitializable();
        TimelockUpgradeableProxy proxy3 = new TimelockUpgradeableProxy(
            address(impl3), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name3", "symbol3"))
        );

        uint256 initialLength = registry.getAllPausableContracts().length;

        // Add all three contracts
        vm.startPrank(upgradeOwner);
        registry.addPausableContract(address(proxy1));
        registry.addPausableContract(address(proxy2));
        registry.addPausableContract(address(proxy3));
        vm.stopPrank();

        // Verify all contracts were added
        address[] memory pausableContracts = registry.getAllPausableContracts();
        assertEq(pausableContracts.length, initialLength + 3, "Should have added 3 contracts");

        // Verify each contract is in the list
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;
        for (uint256 i = 0; i < pausableContracts.length; i++) {
            if (pausableContracts[i] == address(proxy1)) found1 = true;
            if (pausableContracts[i] == address(proxy2)) found2 = true;
            if (pausableContracts[i] == address(proxy3)) found3 = true;
        }
        assertTrue(found1, "Proxy1 should be in the list");
        assertTrue(found2, "Proxy2 should be in the list");
        assertTrue(found3, "Proxy3 should be in the list");

        // Now test that pauseAll will pause all the contracts
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        pauseAdmin.pauseAll();

        vm.prank(upgradeOwner);
        pauseAdmin.addPendingPauser(pauser);

        vm.startPrank(pauser);
        pauseAdmin.acceptPauser();
        pauseAdmin.pauseAll();
        vm.stopPrank();

        // Verify all contracts are paused
        assertEq(TimelockUpgradeableProxy(payable(address(proxy1))).isPaused(), true);
        assertEq(TimelockUpgradeableProxy(payable(address(proxy2))).isPaused(), true);
        assertEq(TimelockUpgradeableProxy(payable(address(proxy3))).isPaused(), true);
    }

    function test_removePausableContract_onlyUpgradeAdmin() public {
        // First add a contract
        Initializable newImpl = new MockInitializable();
        TimelockUpgradeableProxy newProxy = new TimelockUpgradeableProxy(
            address(newImpl), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol"))
        );

        vm.startPrank(upgradeOwner);
        registry.addPausableContract(address(newProxy));
        vm.stopPrank();

        // Get the index of the contract we just added
        address[] memory contracts = registry.getAllPausableContracts();
        uint256 index = 0;
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == address(newProxy)) {
                index = i;
                break;
            }
        }

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = index;

        // Non-upgradeAdmin cannot remove pausable contracts
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.removePausableContract(indexes);

        // PauseAdmin cannot remove pausable contracts
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(pauseAdmin)));
        vm.prank(address(pauseAdmin));
        registry.removePausableContract(indexes);

        // UpgradeAdmin can remove pausable contracts
        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PausableContractsRemoved(address(newProxy));
        vm.prank(upgradeOwner);
        registry.removePausableContract(indexes);

        // Verify the contract was removed
        address[] memory remainingContracts = registry.getAllPausableContracts();
        bool found = false;
        for (uint256 i = 0; i < remainingContracts.length; i++) {
            if (remainingContracts[i] == address(newProxy)) {
                found = true;
                break;
            }
        }
        assertFalse(found, "Pausable contract should not be in the list");
        assertEq(remainingContracts.length, contracts.length - 1, "Should have removed 1 contract");
    }

    function test_removePausableContract_multipleContracts() public {
        // Add multiple contracts
        Initializable impl1 = new MockInitializable();
        TimelockUpgradeableProxy proxy1 = new TimelockUpgradeableProxy(
            address(impl1), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name1", "symbol1"))
        );

        Initializable impl2 = new MockInitializable();
        TimelockUpgradeableProxy proxy2 = new TimelockUpgradeableProxy(
            address(impl2), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name2", "symbol2"))
        );

        Initializable impl3 = new MockInitializable();
        TimelockUpgradeableProxy proxy3 = new TimelockUpgradeableProxy(
            address(impl3), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name3", "symbol3"))
        );

        vm.startPrank(upgradeOwner);
        registry.addPausableContract(address(proxy1));
        registry.addPausableContract(address(proxy2));
        registry.addPausableContract(address(proxy3));
        vm.stopPrank();

        // Get indices of contracts to remove
        address[] memory contracts = registry.getAllPausableContracts();
        uint256 index1 = 0;
        uint256 index2 = 0;
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == address(proxy1)) index1 = i;
            if (contracts[i] == address(proxy2)) index2 = i;
        }

        // Remove two contracts
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = index1;
        indexes[1] = index2;

        vm.startPrank(upgradeOwner);
        registry.removePausableContract(indexes);
        vm.stopPrank();

        // Verify contracts were removed
        address[] memory remainingContracts = registry.getAllPausableContracts();
        assertEq(remainingContracts.length, contracts.length - 2, "Should have removed 2 contracts");

        // Verify proxy3 is still there
        bool found3 = false;
        for (uint256 i = 0; i < remainingContracts.length; i++) {
            if (remainingContracts[i] == address(proxy3)) {
                found3 = true;
                break;
            }
        }
        assertTrue(found3, "Proxy3 should still be in the list");
    }

    function test_getAllPausableContracts() public {
        // Get initial contracts
        address[] memory initialContracts = registry.getAllPausableContracts();
        uint256 initialLength = initialContracts.length;

        // Add a contract
        Initializable newImpl = new MockInitializable();
        TimelockUpgradeableProxy newProxy = new TimelockUpgradeableProxy(
            address(newImpl), abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol"))
        );

        vm.prank(upgradeOwner);
        registry.addPausableContract(address(newProxy));

        // Verify getAllPausableContracts returns the updated list
        address[] memory allContracts = registry.getAllPausableContracts();
        assertEq(allContracts.length, initialLength + 1, "Should have one more contract");
        assertEq(allContracts[allContracts.length - 1], address(newProxy), "Last contract should be the new proxy");
    }

    function test_unpause_via_pauseAdmin() public {
        // The morpho lending router is only unpaused via the pause admin
        address morphoLendingRouter = 0x9a0c630C310030C4602d1A76583a3b16972ecAa0;

        vm.startPrank(upgradeOwner);
        registry.addPausableContract(morphoLendingRouter);
        pauseAdmin.addPendingPauser(pauser);
        vm.stopPrank();

        vm.startPrank(pauser);
        pauseAdmin.acceptPauser();
        pauseAdmin.pauseAll();
        vm.stopPrank();
        assertEq(TimelockUpgradeableProxy(payable(morphoLendingRouter)).isPaused(), true);

        vm.startPrank(upgradeOwner);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, upgradeOwner));
        TimelockUpgradeableProxy(payable(morphoLendingRouter)).unpause();

        pauseAdmin.unpause(morphoLendingRouter);
        assertEq(TimelockUpgradeableProxy(payable(morphoLendingRouter)).isPaused(), false);
        vm.stopPrank();
    }

    function test_pauseAll_doesNotRevertIf_contractDoesNotPause() public {
        // The morpho lending router is only unpaused via the pause admin
        address morphoLendingRouter = 0x9a0c630C310030C4602d1A76583a3b16972ecAa0;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        vm.startPrank(upgradeOwner);
        registry.addPausableContract(morphoLendingRouter);
        registry.addPausableContract(usdc);
        registry.addPausableContract(address(0));
        pauseAdmin.addPendingPauser(pauser);
        vm.stopPrank();

        address[] memory pausableContracts = registry.getAllPausableContracts();
        assertEq(pausableContracts.length, 3);
        assertEq(pausableContracts[0], morphoLendingRouter);
        assertEq(pausableContracts[1], usdc);
        assertEq(pausableContracts[2], address(0));

        vm.startPrank(pauser);
        pauseAdmin.acceptPauser();
        vm.expectEmit(true, true, true, true);
        emit PauseAdmin.ErrorPausingContract(usdc);
        pauseAdmin.pauseAll();
        vm.stopPrank();

        assertEq(TimelockUpgradeableProxy(payable(morphoLendingRouter)).isPaused(), true);
    }
}
