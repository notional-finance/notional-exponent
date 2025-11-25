// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract EnterPosition is Script {

    function run(
        address vaultAddress,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes memory depositData
    ) public {
        console.log("Entering position");
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        console.log("Entering position for vault", vaultAddress);
        enterPosition(vault, depositAssetAmount, borrowAmount, depositData);
    }

    function enterPosition(
        IYieldStrategy vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes memory depositData
    ) internal {
        ERC20 asset = ERC20(vault.asset());

        if (!MORPHO.isAuthorized(msg.sender, address(MORPHO_LENDING_ROUTER))) {
            console.log("Setting authorization for lending router");
            vm.startBroadcast();
            MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
            vm.stopBroadcast();
        }

        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(address(vault));
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        console.log("Morpho ID");
        console.logBytes32(Id.unwrap(id));

        console.log("Entering position");
        
        uint256 assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance Before: ", assetBalance);

        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        console.log("Balance of Collateral Before Enter Position: ", balance);

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.enterPosition(
            msg.sender, address(vault), depositAssetAmount, borrowAmount, depositData
        );
        vm.stopBroadcast();

        assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance After Enter Position: ", assetBalance);

        balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        console.log("Balance of Collateral After Enter Position: ", balance);
    }
}