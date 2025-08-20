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
        
        flashLiquidate(vaultAddress, liquidateAccount, sharesToLiquidate, assetsToBorrow, redeemData);
        
        console.log("=== Flash Liquidate Completed ===");
    }

    function flashLiquidate(
        address vaultAddress,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) internal {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();
        
        console.log("--- Pre-Flash Loan State ---");
        console.log("Asset Address: ", asset);
        console.log("Initial Asset Balance: ", ERC20(asset).balanceOf(address(this)));
        console.log("Initial Asset Balance (msg.sender): ", ERC20(asset).balanceOf(msg.sender));

        bytes memory flashLoanData = abi.encode(
            liquidateAccount, vaultAddress, sharesToLiquidate, redeemData
        );

        console.log("--- Initiating Flash Loan ---");
        console.log("Flash Loan Asset: ", asset);
        console.log("Flash Loan Amount: ", assetsToBorrow);

        MORPHO.flashLoan(
            asset,
            assetsToBorrow,
            flashLoanData
        );

        console.log("--- Post-Flash Loan Transfer ---");
        ERC20 assetToken = ERC20(asset);
        uint256 finalBalance = assetToken.balanceOf(address(this));
        console.log("Final Asset Balance (this contract): ", finalBalance);
        
        if (finalBalance > 0) {
            console.log("Transferring ", finalBalance, " assets to msg.sender");
            assetToken.transfer(msg.sender, finalBalance);
            console.log("Transfer completed. New balance (msg.sender): ", assetToken.balanceOf(msg.sender));
        } else {
            console.log("No assets to transfer");
        }
    }

    function onMorphoFlashLoan(
        uint256 assetsToBorrow,
        bytes memory flashLoanData
    ) internal {
        console.log("--- Flash Loan Callback Started ---");
        
        (
            address liquidateAccount,
            address vaultAddress,
            uint256 sharesToLiquidate,
            bytes memory redeemData
        ) = abi.decode(flashLoanData, (address, address, uint256, bytes));

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();
        
        console.log("--- Pre-Liquidation Balances ---");
        console.log("Asset Balance (this contract): ", ERC20(asset).balanceOf(address(this)));
        console.log("Vault Shares Balance (liquidateAccount): ", vault.balanceOf(liquidateAccount));
        console.log("Collateral Balance (liquidateAccount): ", MORPHO_LENDING_ROUTER.balanceOfCollateral(liquidateAccount, address(vault)));

        console.log("--- Performing Liquidation ---");
        MORPHO_LENDING_ROUTER.liquidate(liquidateAccount, address(vault), sharesToLiquidate, 0);
        
        console.log("--- Post-Liquidation, Pre-Redeem ---");
        console.log("Vault Shares Balance (this contract): ", vault.balanceOf(address(this)));
        console.log("Asset Balance (this contract): ", ERC20(asset).balanceOf(address(this)));

        console.log("--- Performing Redeem ---");
        console.log("Redeeming ", sharesToLiquidate, " shares");
        vault.redeemNative(sharesToLiquidate, redeemData);
        
        console.log("--- Post-Redeem Balances ---");
        console.log("Asset Balance (this contract): ", ERC20(asset).balanceOf(address(this)));
        console.log("Vault Shares Balance (this contract): ", vault.balanceOf(address(this)));
        
        uint256 assetBalance = ERC20(asset).balanceOf(address(this));
        if (assetBalance >= assetsToBorrow) {
            console.log("Flash loan can be repaid. Profit: ", assetBalance - assetsToBorrow);
        } else {
            console.log("WARNING: Insufficient assets to repay flash loan. Deficit: ", assetsToBorrow - assetBalance);
        }
        
        console.log("--- Flash Loan Callback Completed ---");
    }
}