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

FlashLiquidator constant FLASH_LIQUIDATOR = FlashLiquidator(0x239156969FAb8a83D8f1eBd13BEaf1f272922275);

contract FlashLiquidate is Script {

    function run(
        address vaultAddress,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) public {
        console.log("=== Flash Liquidate Started ===");
        console.log("Vault Address: ", vaultAddress);
        console.log("Liquidate Account: ", liquidateAccount);
        console.log("Shares to Liquidate: ", sharesToLiquidate);
        console.log("Assets to Borrow: ", assetsToBorrow);
        console.log("Redeem Data Length: ", redeemData.length);

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        ERC20 asset = ERC20(vault.asset());
        uint256 balanceBefore = asset.balanceOf(msg.sender);

        vm.startBroadcast();
        FLASH_LIQUIDATOR.flashLiquidate(vaultAddress, liquidateAccount, sharesToLiquidate, assetsToBorrow, redeemData);
        vm.stopBroadcast();

        uint256 balanceAfter = asset.balanceOf(msg.sender);
        console.log("Profit: ", balanceAfter - balanceBefore);

        console.log("=== Flash Liquidate Completed ===");
    }

}