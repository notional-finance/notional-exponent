// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RedeemNative is Script {

    function run(
        address vaultAddress,
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) public {
        console.log("Redeeming native for vault", vaultAddress);
        redeemNative(vaultAddress, sharesToRedeem, redeemData);
    }

    function redeemNative(
        address vaultAddress,
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) internal {

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        ERC20 asset = ERC20(vault.asset());
        uint256 balanceBefore = asset.balanceOf(msg.sender);
        console.log("Balance of Asset Before Redeem Native: ", balanceBefore);
        console.log("Balance of Shares Before Redeem Native: ", vault.balanceOf(msg.sender));

        vm.startBroadcast();
        vault.redeemNative(sharesToRedeem, redeemData);
        vm.stopBroadcast();

        uint256 balanceAfter = asset.balanceOf(msg.sender);
        console.log("Balance of Asset After Redeem Native: ", balanceAfter);
        console.log("Balance of Shares After Redeem Native: ", vault.balanceOf(msg.sender));
    }
}