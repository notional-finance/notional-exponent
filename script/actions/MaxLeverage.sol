// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {Script, console} from "forge-std/src/Script.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MaxLeverageExecutor} from "../../src/MaxLeverageExecutor.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER =
    MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);
MaxLeverageExecutor constant MAX_LEVERAGE_EXECUTOR =
    MaxLeverageExecutor(0x716Dd5fb9504Ead30810Ed47Ac25eBF0D710Ab8A);

contract MaxLeverage is Script {

    function run(
        address vaultAddress,
        bytes memory redeemData
    ) public {
        console.log("Max Leverage");
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        console.log("Max Leverage for vault", vaultAddress);
        maxLeverage(vault, redeemData);
    }

    function maxLeverage(
        IYieldStrategy vault,
        bytes memory redeemData
    ) internal {

        // 1. Check and authorize MORPHO_LENDING_ROUTER on Morpho if needed
        if (!MORPHO.isAuthorized(msg.sender, address(MORPHO_LENDING_ROUTER))) {
            console.log("Setting authorization for lending router on Morpho");
            vm.startBroadcast();
            MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
            vm.stopBroadcast();
        }

        // 2. Check and approve MaxLeverageExecutor on the router if needed
        if (!MORPHO_LENDING_ROUTER.isApproved(msg.sender, address(MAX_LEVERAGE_EXECUTOR))) {
            console.log("Setting authorization for MaxLeverageExecutor on router");
            vm.startBroadcast();
            MORPHO_LENDING_ROUTER.setApproval(address(MAX_LEVERAGE_EXECUTOR), true);
            vm.stopBroadcast();
        }

        console.log("Asset Balance Before: ", ERC20(vault.asset()).balanceOf(msg.sender));

        // Execute the max leverage calculation and exit atomically
        console.log("Executing max leverage via MaxLeverageExecutor...");
        vm.startBroadcast();
        MAX_LEVERAGE_EXECUTOR.executeMaxLeverage(
            address(vault),
            redeemData
        );
        vm.stopBroadcast();

        console.log("=== EXECUTION RESULTS ===");
        console.log("Asset Balance After: ", ERC20(vault.asset()).balanceOf(msg.sender));

        (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow) =
            MORPHO_LENDING_ROUTER.healthFactor(msg.sender, address(vault));
        console.log("Borrowed: ", borrowed);
        console.log("Collateral Value: ", collateralValue);
        console.log("Max Borrow: ", maxBorrow);
        console.log("Health Factor: ", collateralValue / borrowed);
    }
}