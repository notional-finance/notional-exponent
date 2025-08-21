// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {MorphoLendingRouter} from "./routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO} from "./interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract FlashLiquidator {

    function flashLiquidate(
        address vaultAddress,
        address liquidateAccount,
        uint256 sharesToLiquidate,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) external {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();

        bytes memory flashLoanData = abi.encode(
            liquidateAccount, vaultAddress, sharesToLiquidate, redeemData
        );

        MORPHO.flashLoan(
            asset,
            assetsToBorrow,
            flashLoanData
        );

        ERC20 assetToken = ERC20(asset);
        uint256 finalBalance = assetToken.balanceOf(address(this));
        
        if (finalBalance > 0) {
            assetToken.transfer(msg.sender, finalBalance);
        }
    }

    function onMorphoFlashLoan(
        uint256 assetsToBorrow,
        bytes memory flashLoanData
    ) external {
        (
            address liquidateAccount,
            address vaultAddress,
            uint256 sharesToLiquidate,
            bytes memory redeemData
        ) = abi.decode(flashLoanData, (address, address, uint256, bytes));

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        ERC20 asset = ERC20(vault.asset());

        asset.approve(address(MORPHO_LENDING_ROUTER), assetsToBorrow);
        asset.approve(address(MORPHO), assetsToBorrow);
        
        MORPHO_LENDING_ROUTER.liquidate(liquidateAccount, address(vault), sharesToLiquidate, 0);
        
        vault.redeemNative(sharesToLiquidate, redeemData);
    }
}