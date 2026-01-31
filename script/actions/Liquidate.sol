// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FlashLiquidator} from "../../src/FlashLiquidator.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract Liquidate is Script {

    function run(
        address vaultAddress,
        address liquidateAccount,
        uint256 sharesToLiquidate
    ) public {
        console.log("=== Liquidation Started ===");

        console.log("Vault Address: ", vaultAddress);
        console.log("Liquidate Account: ", liquidateAccount);
        console.log("Shares to Liquidate: ", sharesToLiquidate);

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        ERC20 asset = ERC20(vault.asset());
        uint256 assetBalanceBefore = asset.balanceOf(msg.sender);
        uint256 vaultShareBalanceBefore = vault.balanceOf(msg.sender);

        console.log("Asset Balance Before: ", assetBalanceBefore);
        console.log("Vault Share Balance Before: ", vaultShareBalanceBefore);

        if (asset.allowance(msg.sender, address(MORPHO_LENDING_ROUTER)) == 0) {
            console.log("Setting allowance for lending router");
            vm.startBroadcast();
            asset.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
            vm.stopBroadcast();
        }

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.liquidate(liquidateAccount, vaultAddress, sharesToLiquidate, 0);
        vm.stopBroadcast();

        uint256 assetBalanceAfter = asset.balanceOf(msg.sender);
        uint256 vaultShareBalanceAfter = vault.balanceOf(msg.sender);

        console.log("Asset Balance After: ", assetBalanceAfter);
        console.log("Vault Share Balance After: ", vaultShareBalanceAfter);

        console.log("=== Liquidation Completed ===");
    }

}