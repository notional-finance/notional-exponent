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

contract WithdrawFromMorpho is Script {

    function run(
        address vaultAddress,
        uint256 sharesAmount
    ) public {
        console.log("Withdrawing from Morpho");
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        withdrawFromMorpho(vault, sharesAmount);
    }

    function withdrawFromMorpho(
        IYieldStrategy vault,
        uint256 sharesAmount
    ) internal {
        ERC20 asset = ERC20(vault.asset());

        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(address(vault));
        Id id = Id.wrap(keccak256(abi.encode(marketParams)));
        console.log("Morpho ID");
        console.logBytes32(Id.unwrap(id));

        console.log("Withdrawing from Morpho");
        uint256 assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance Before: ", assetBalance);

        console.log("Withdrawing assets from market");
        vm.startBroadcast();
        MORPHO.withdraw(marketParams, 0, sharesAmount, msg.sender, msg.sender);
        vm.stopBroadcast();

        assetBalance = asset.balanceOf(msg.sender);
        console.log("Asset Balance After Withdraw: ", assetBalance);

        console.log("Morpho Market After");
        console.log("Total Supply Assets: ", MORPHO.market(id).totalSupplyAssets);
        console.log("Total Borrow Assets: ", MORPHO.market(id).totalBorrowAssets);
    }
}