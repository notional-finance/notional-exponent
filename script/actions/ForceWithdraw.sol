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

contract ForceWithdraw is Script {

    function run(
        address account,
        address vaultAddress,
        bytes memory withdrawData
    ) public {
        console.log("Initiating force withdraw for vault", vaultAddress);
        console.log("Account: ", account);
        initiateForceWithdraw(account, vaultAddress, withdrawData);
    }

    function initiateForceWithdraw(
        address account,
        address vaultAddress,
        bytes memory withdrawData
    ) internal {

        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(account, vaultAddress);
        console.log("Balance of Collateral Before Force Withdraw: ", balance);

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.forceWithdraw(
            account, vaultAddress, withdrawData
        );
        vm.stopBroadcast();

        balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(account, vaultAddress);
        console.log("Balance of Collateral After Force Withdraw: ", balance);
    }
}