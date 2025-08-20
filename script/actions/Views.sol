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

contract Views is Script {

    function getMarketDetails(
        address vaultAddress
    ) public view {
        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(vaultAddress);
        console.log("Market Params:");
        console.log("Loan Token: ", marketParams.loanToken);
        console.log("Collateral Token: ", marketParams.collateralToken); 
        console.log("Oracle: ", marketParams.oracle);
        console.log("Interest Rate Model: ", marketParams.irm);
        console.log("LLTV: ", marketParams.lltv);
    }

    function getAccountDetails(
        address vaultAddress,
        address account
    ) public {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        
        console.log("--- Account Details ---");
        console.log("Account: ", account);
        console.log("Vault Address: ", vaultAddress);
        console.log("Vault Asset: ", vault.asset());
        console.log("Vault Shares Native Balance: ", vault.balanceOf(account));
        console.log("Morpho Collateral Balance: ", MORPHO_LENDING_ROUTER.balanceOfCollateral(account, vaultAddress));
        console.log("Morpho Borrow Shares Balance: ", MORPHO_LENDING_ROUTER.balanceOfBorrowShares(account, vaultAddress));

        (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow) = MORPHO_LENDING_ROUTER.healthFactor(account, vaultAddress);
        console.log("Borrowed: ", borrowed);
        console.log("Collateral Value: ", collateralValue);
        console.log("Max Borrow: ", maxBorrow);
    }
}