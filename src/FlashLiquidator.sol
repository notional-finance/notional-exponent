// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {MorphoLendingRouter} from "./routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {MORPHO} from "./interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract FlashLiquidator {

    address private owner;

    constructor() {
        owner = msg.sender;
        ERC20 usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        usdc.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        weth.approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        usdc.approve(address(MORPHO), type(uint256).max);
        weth.approve(address(MORPHO), type(uint256).max);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function approve(address asset) external onlyOwner {
        ERC20(asset).approve(address(MORPHO_LENDING_ROUTER), type(uint256).max);
        ERC20(asset).approve(address(MORPHO), type(uint256).max);
    }

    function flashLiquidate(
        address vaultAddress,
        address[] memory liquidateAccounts,
        uint256[] memory sharesToLiquidate,
        uint256[] memory borrowSharesToRepay,
        uint256 assetsToBorrow,
        bytes memory redeemData
    ) external {
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        address asset = vault.asset();

        bytes memory flashLoanData = abi.encode(
            vaultAddress, liquidateAccounts, sharesToLiquidate, borrowSharesToRepay, redeemData
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
            uint256[] memory borrowSharesToRepay,
            bytes memory redeemData
        ) = abi.decode(flashLoanData, (address, address[], uint256[], uint256[], bytes));

        for (uint256 i = 0; i < liquidateAccounts.length; i++) {
            MORPHO_LENDING_ROUTER.liquidate(liquidateAccounts[i], vaultAddress, sharesToLiquidate[i], borrowSharesToRepay[i]);
        }

        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        uint256 sharesToRedeem = vault.balanceOf(address(this));
        vault.redeemNative(sharesToRedeem, redeemData);
    }
}