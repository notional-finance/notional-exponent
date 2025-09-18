// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {IWithdrawRequestManager} from "../../src/interfaces/IWithdrawRequestManager.sol";
import {MORPHO, MarketParams, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract FinalizeWithdraw is Script {

    function run(
        address account,
        address vaultAddress,
        address wrmAddress
    ) public {
        console.log("Finalizing withdraw for vault", vaultAddress);
        console.log("Account: ", account);
        console.log("WRM: ", wrm);
        finalizeWithdraw(account, vaultAddress, wrmAddress);
    }

    function finalizeWithdraw(
        address account,
        address vaultAddress,
        address wrmAddress
    ) internal {

        wrm = IWithdrawRequestManager(wrmAddress);

        vm.startBroadcast();
        uint256 tokensWithdrawn, bool finalized = wrm.finalizeRequestManual(
            vaultAddress, account
        );
        vm.stopBroadcast();

        console.log("Tokens Withdrawn: ", tokensWithdrawn);
        console.log("Finalized: ", finalized);
    }
}