// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../../src/interfaces/ITradingModule.sol";
import {RedeemParams} from "../../src/staking/AbstractStakingStrategy.sol";
import {MorphoLendingRouter} from "../../src/routers/MorphoLendingRouter.sol";
import {AddressRegistry} from "../../src/proxy/AddressRegistry.sol";
import {PendlePT} from "../../src/staking/PendlePT.sol";
import {CurveConvex2Token} from "../../src/single-sided-lp/CurveConvex2Token.sol";
import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {IWithdrawRequestManager, WithdrawRequest, TokenizedWithdrawRequest} from "../../src/interfaces/IWithdrawRequestManager.sol";
import {MORPHO, MarketParams, Id, Position} from "../../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);
AddressRegistry constant ADDRESS_REGISTRY = AddressRegistry(0xe335d314BD4eF7DD44F103dC124FEFb7Ce63eC95);

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

        string memory strategy = vault.strategy();
        address yieldToken = vault.yieldToken();
        
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

        // Get WRM addresses based on strategy type
        console.log("--- Withdraw Request Details ---");
        console.log("Strategy: ", strategy);
        
        if (keccak256(abi.encodePacked(strategy)) == keccak256(abi.encodePacked("Staking"))) {
            IWithdrawRequestManager wrm = ADDRESS_REGISTRY.getWithdrawRequestManager(yieldToken);
            console.log("WRM Address: ", address(wrm));
            (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) = wrm.getWithdrawRequest(vaultAddress, account);
            if (w.requestId != 0) {
                console.log("Withdraw Request ID: ", w.requestId);
                console.log("Withdraw Request Yield Token Amount: ", w.yieldTokenAmount);
                console.log("Withdraw Request Shares Amount: ", w.sharesAmount);
                console.log("Withdraw Request Finalized: ", s.finalized);
            } else {
                console.log("No Withdraw Request");
            }
        } else if (keccak256(abi.encodePacked(strategy)) == keccak256(abi.encodePacked("PendlePT"))) {
            address tokenOutSy = PendlePT(vaultAddress).TOKEN_OUT_SY();
            IWithdrawRequestManager wrm = ADDRESS_REGISTRY.getWithdrawRequestManager(tokenOutSy);
            console.log("WRM Address: ", address(wrm));
            (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) = wrm.getWithdrawRequest(vaultAddress, account);
            if (w.requestId != 0) {
                console.log("Withdraw Request ID: ", w.requestId);
                console.log("Withdraw Request Yield Token Amount: ", w.yieldTokenAmount);
                console.log("Withdraw Request Shares Amount: ", w.sharesAmount);
                console.log("Withdraw Request Finalized: ", s.finalized);
            } else {
                console.log("No Withdraw Request");
            }
        }
        // } else if (keccak256(abi.encodePacked(strategy)) == keccak256(abi.encodePacked("CurveConvex2Token"))) {
        //     address[2] memory tokens = CurveConvex2Token(vaultAddress).TOKENS();
            
        //     // Replace address(0) with WETH
        //     address token0 = tokens[0] == address(0) ? 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 : tokens[0]; // WETH mainnet
        //     address token1 = tokens[1] == address(0) ? 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 : tokens[1]; // WETH mainnet
            
        //     IWithdrawRequestManager wrm_one = ADDRESS_REGISTRY.getWithdrawRequestManager(token0);
        //     IWithdrawRequestManager wrm_two = ADDRESS_REGISTRY.getWithdrawRequestManager(token1);

        //     console.log("WRM One Address: ", address(wrm_one));
        //     console.log("WRM Two Address: ", address(wrm_two));
        //     (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) = wrm_one.getWithdrawRequest(vaultAddress, account);
        //     if (w.requestId != 0) {
        //         console.log("Withdraw Request One ID: ", w.requestId);
        //         console.log("Withdraw Request One Yield Token Amount: ", w.yieldTokenAmount);
        //         console.log("Withdraw Request One Shares Amount: ", w.sharesAmount);
        //         console.log("Withdraw Request One Finalized: ", s.finalized);
        //     } else {
        //         console.log("No Withdraw Request");
        //     }
        //     (w, s) = wrm_two.getWithdrawRequest(vaultAddress, account);
        //     if (w.requestId != 0) {
        //         console.log("Withdraw Request Two ID: ", w.requestId);
        //         console.log("Withdraw Request Two Yield Token Amount: ", w.yieldTokenAmount);
        //         console.log("Withdraw Request Two Shares Amount: ", w.sharesAmount);
        //         console.log("Withdraw Request Two Finalized: ", s.finalized);
        //     } else {
        //         console.log("No Withdraw Request");
        //     }
        // }
    }
}