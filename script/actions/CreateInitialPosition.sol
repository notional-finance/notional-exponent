// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {StakingTradeParams} from "../../src/interfaces/IWithdrawRequestManager.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract CreateInitialPosition is Script {

    function run(
        address vaultAddress,
        uint256 initialSupply,
        uint256 initialBorrow, 
        uint256 initialDeposit,
        bytes memory depositData
    ) public {
        console.log("Creating initial position");
        console.log(block.number);
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        console.log("Creating initial position for vault", vaultAddress);
        createMorphoPosition(vault, initialSupply, initialBorrow, initialDeposit, depositData);
    }

    function createMorphoPosition(
        IYieldStrategy vault,
        uint256 initialSupply,
        uint256 initialBorrow,
        uint256 initialDeposit, 
        bytes memory depositData
    ) internal {
        ERC20 asset = ERC20(vault.asset());

        if (!MORPHO.isAuthorized(msg.sender, address(MORPHO_LENDING_ROUTER))) {
            console.log("Setting authorization for lending router");
            vm.startBroadcast();
            MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
            vm.stopBroadcast();
        }

        if (asset.allowance(msg.sender, address(MORPHO_LENDING_ROUTER)) == 0) {
            console.log("Setting allowance for lending router");
            vm.startBroadcast();
            asset.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
            vm.stopBroadcast();
        }

        if (asset.allowance(msg.sender, address(MORPHO)) == 0) {
            console.log("Setting allowance for Morpho Supply");
            vm.startBroadcast();
            asset.approve(address(MORPHO), type(uint256).max);
            vm.stopBroadcast();
        }

        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(address(vault));
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        console.log("Morpho ID");
        console.logBytes32(Id.unwrap(id));

        console.log("Supplying initial assets to market");
        vm.startBroadcast();
        MORPHO.supply(marketParams, initialSupply, 0, msg.sender, "");
        vm.stopBroadcast();

        console.log("Creating initial position");
        console.log("Initial Deposit", initialDeposit);
        console.log("Initial Borrow", initialBorrow);

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.enterPosition(msg.sender, address(vault), initialDeposit, initialBorrow, depositData);
        vm.stopBroadcast();

        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        console.log("Balance of Collateral: ", balance);

        console.log("Morpho Market After");
        console.log("Total Supply Assets: ", MORPHO.market(id).totalSupplyAssets);
        console.log("Total Borrow Assets: ", MORPHO.market(id).totalBorrowAssets);
    }
}
