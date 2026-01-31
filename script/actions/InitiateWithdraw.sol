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

contract InitiateWithdraw is Script {

    function run(
        address vaultAddress,
        bytes memory withdrawData
    ) public {
        console.log("Initiating withdraw for vault", vaultAddress);
        initiateWithdraw(vaultAddress, withdrawData);
    }

    function initiateWithdraw(
        address vaultAddress,
        bytes memory withdrawData
    ) internal {

        if (!MORPHO.isAuthorized(msg.sender, address(MORPHO_LENDING_ROUTER))) {
            console.log("Setting authorization for lending router");
            vm.startBroadcast();
            MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
            vm.stopBroadcast();
        }

        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, vaultAddress);
        console.log("Balance of Collateral Before Initiate Withdraw: ", balance);

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.initiateWithdraw(
            msg.sender, vaultAddress, withdrawData
        );
        vm.stopBroadcast();

        balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, vaultAddress);
        console.log("Balance of Collateral After Initiate Withdraw: ", balance);
    }
}