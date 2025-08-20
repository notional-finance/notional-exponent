// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Market, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract MaxLeverage is Script {

    function run(
        address vaultAddress,
        uint256 roundingBuffer,
        bytes memory redeemData
    ) public {
        console.log("Max Leverage");
        IYieldStrategy vault = IYieldStrategy(vaultAddress);
        console.log("Max Leverage for vault", vaultAddress);
        maxLeverage(vault, roundingBuffer, redeemData);
    }

    function maxLeverage(
        IYieldStrategy vault,
        uint256 roundingBuffer,
        bytes memory redeemData
    ) internal {

        if (!MORPHO.isAuthorized(msg.sender, address(MORPHO_LENDING_ROUTER))) {
            console.log("Setting authorization for lending router");
            vm.startBroadcast();
            MORPHO.setAuthorization(address(MORPHO_LENDING_ROUTER), true);
            vm.stopBroadcast();
        }

        MarketParams memory marketParams = MORPHO_LENDING_ROUTER.marketParams(address(vault));

        MORPHO.accrueInterest(marketParams);

        uint256 collateralBalance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        uint256 borrowShares = MORPHO_LENDING_ROUTER.balanceOfBorrowShares(msg.sender, address(vault));
        console.log("Price: ", vault.price(msg.sender));
        console.log("LTV: ", marketParams.lltv);
        console.log("Collateral Balance: ", collateralBalance);
        console.log("Borrow Shares: ", borrowShares);

        Market memory market = MORPHO.market(Id.wrap(keccak256(abi.encode(marketParams))));

        uint256 borrowed = borrowShares * market.totalBorrowAssets / market.totalBorrowShares;
        console.log("Borrowed: ", borrowed);

        uint256 collateralValue = collateralBalance * vault.price(msg.sender) / 1e36;
        uint256 maxBorrow = collateralValue * marketParams.lltv / 1e18;
        console.log("Collateral Value: ", collateralValue);
        console.log("Max Borrow: ", maxBorrow);

        uint256 sharesToRedeem = collateralBalance - (collateralBalance * borrowed / maxBorrow) - roundingBuffer;
        console.log("Shares to Redeem: ", sharesToRedeem);

        console.log("Exiting position");
        
        console.log("Asset Balance Before: ", ERC20(vault.asset()).balanceOf(msg.sender));

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.exitPosition(
            msg.sender, address(vault), msg.sender, sharesToRedeem, 0, redeemData
        );
        vm.stopBroadcast();

        console.log("Asset Balance After Exit Position: ", ERC20(vault.asset()).balanceOf(msg.sender));

        collateralBalance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        console.log("Balance of Collateral After Exit Position: ", collateralBalance);

        collateralValue = collateralBalance * vault.price(msg.sender) / 1e36;
        console.log("Collateral Value After Exit Position: ", collateralValue);

        maxBorrow = collateralValue * marketParams.lltv / 1e18;
        console.log("Max Borrow After Exit Position: ", maxBorrow);
    }
}