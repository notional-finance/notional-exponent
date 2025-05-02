// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";

contract TestTimelockProxy is Test {
    Initializable public impl;
    TimelockUpgradeableProxy public proxy;
    address public upgradeOwner;
    AddressRegistry public registry;

    function setUp() public {
        upgradeOwner = makeAddr("upgradeOwner");
        registry = new AddressRegistry(upgradeOwner, upgradeOwner);
        impl = new Initializable();
        proxy = new TimelockUpgradeableProxy(
            address(impl),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol")),
            address(registry)
        );
    }

    function test_cannotReinitializeImplementation() public {
        // Cannot re-initialize the implementation
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        impl.initialize(bytes(""));
    }

    function test_initializeProxy() public {
        // Initialize the proxy
        Initializable(address(proxy)).initialize(bytes(""));

        // Cannot re-initialize the proxy
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        Initializable(address(proxy)).initialize(bytes(""));

        // Check that the proxy is initialized
        // TODO: fix this
        // assertEq(proxy.upgradeOwner(), upgradeOwner);
    }

    function test_initiateUpgrade() public {
        Initializable timelock2 = new Initializable();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.initiateUpgrade(address(timelock2));

        vm.expectEmit(true, true, true, true);
        emit TimelockUpgradeableProxy.UpgradeInitiated(address(timelock2), uint32(block.timestamp + proxy.UPGRADE_DELAY()));
        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));

        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        // Cannot upgrade before the delay
        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade();

        vm.warp(block.timestamp + proxy.UPGRADE_DELAY() + 1);
        proxy.executeUpgrade();

        assertEq(proxy.newImplementation(), address(timelock2));
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

        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade();
    }

    // TODO: fix this
    // function test_transferUpgradeOwnership() public {
    //     address newUpgradeOwner = makeAddr("newUpgradeOwner");
    //     vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
    //     proxy.transferUpgradeOwnership(newUpgradeOwner);

    //     vm.prank(upgradeOwner);
    //     proxy.transferUpgradeOwnership(newUpgradeOwner);

    //     vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
    //     proxy.acceptUpgradeOwnership();

    //     vm.prank(newUpgradeOwner);
    //     proxy.acceptUpgradeOwnership();

    //     assertEq(proxy.upgradeOwner(), newUpgradeOwner);
    // }
}
