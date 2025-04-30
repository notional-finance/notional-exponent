// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/proxy/TimelockUpgradeable.sol";
import "../src/proxy/nProxy.sol";

contract TestTimelockProxy is Test {
    TimelockUpgradeable public impl;
    TimelockUpgradeable public proxy;

    function setUp() public {
        impl = new TimelockUpgradeable();
        proxy = TimelockUpgradeable(address(new nProxy(address(impl), "")));
    }

    function test_cannotReinitializeImplementation() public {
        // Cannot re-initialize the implementation
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        impl.initialize(address(this), bytes(""));
    }

    function test_initializeProxy() public {
        // Initialize the proxy
        proxy.initialize(address(this), bytes(""));

        // Cannot re-initialize the proxy
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proxy.initialize(msg.sender, bytes(""));

        // Check that the proxy is initialized
        assertEq(proxy.upgradeOwner(), address(this));
    }

    function test_initiateUpgrade() public {
        address upgradeOwner = makeAddr("upgradeOwner");
        proxy.initialize(upgradeOwner, bytes(""));

        TimelockUpgradeable timelock2 = new TimelockUpgradeable();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.initiateUpgrade(address(timelock2));

        vm.expectEmit(true, true, true, true);
        emit TimelockUpgradeable.UpgradeInitiated(address(timelock2), uint32(block.timestamp + proxy.UPGRADE_DELAY()));
        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));

        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.upgradeToAndCall(address(timelock2), bytes(""));

        vm.warp(block.timestamp + proxy.UPGRADE_DELAY() + 1);
        proxy.upgradeToAndCall(address(timelock2), bytes(""));

        assertEq(proxy.newImplementation(), address(timelock2));
    }

    function test_invalidUpgrade() public {
        address upgradeOwner = makeAddr("upgradeOwner");
        proxy.initialize(upgradeOwner, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.upgradeToAndCall(address(0), bytes(""));
    }

    function test_cancelUpgrade() public {
        address upgradeOwner = makeAddr("upgradeOwner");
        proxy.initialize(upgradeOwner, bytes(""));
        TimelockUpgradeable timelock2 = new TimelockUpgradeable();

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));
        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(0));

        assertEq(proxy.newImplementation(), address(0));
        assertEq(proxy.upgradeValidAt(), uint32(0));

        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.upgradeToAndCall(address(0), bytes(""));
    }
}
