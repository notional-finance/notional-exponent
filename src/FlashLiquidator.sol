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
        address[] memory liquidateAccounts,
        uint256[] memory sharesToLiquidate,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) external {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();

        bytes memory flashLoanData = abi.encode(
            vaultAddress, liquidateAccounts, sharesToLiquidate, redeemData
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
        uint256 /* assetsToBorrow */,
        bytes memory flashLoanData
    ) external {
        (
            address vaultAddress,
            address[] memory liquidateAccounts,
            uint256[] memory sharesToLiquidate,
            bytes memory redeemData
        ) = abi.decode(flashLoanData, (address, address[], uint256[], bytes));

        for (uint256 i = 0; i < liquidateAccounts.length; i++) {
            MORPHO_LENDING_ROUTER.liquidate(liquidateAccounts[i], vaultAddress, sharesToLiquidate[i], 0);
        }

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        uint256 sharesToRedeem = vault.balanceOf(address(this));
        vault.redeemNative(sharesToRedeem, redeemData);
    }
}