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

contract DepositToMorpho is Script {

    function run(
        address vaultAddress,
        uint256 assetAmount
    ) public {
        console.log("Depositing to Morpho");
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        depositToMorpho(vault, assetAmount);
    }

    function depositToMorpho(
        IYieldStrategy vault,
        uint256 assetAmount
    ) internal {
        ERC20 asset = ERC20(vault.asset());

        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(address(vault));
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        console.log("Morpho ID");
        console.logBytes32(Id.unwrap(id));

        // Check asset approval
        if (asset.allowance(msg.sender, address(MORPHO)) < assetAmount) {
            console.log("Approving Morpho Supply");
            vm.startBroadcast();
            asset.approve(address(MORPHO), assetAmount);
            vm.stopBroadcast();
        }

        console.log("Depositing to Morpho");
        uint256 assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance Before: ", assetBalance);

        console.log("Depositing assets to market");
        vm.startBroadcast();
        MORPHO.supply(marketParams, assetAmount, 0, msg.sender, "");
        vm.stopBroadcast();

        assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance After Deposit: ", assetBalance);

        console.log("Morpho Market After");
        console.log("Total Supply Assets: ", MORPHO.market(id).totalSupplyAssets);
        console.log("Total Borrow Assets: ", MORPHO.market(id).totalBorrowAssets);
    }
}