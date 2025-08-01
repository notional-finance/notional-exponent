// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Script.sol";
import "../src/interfaces/ITradingModule.sol";
import {StakingTradeParams} from "../src/interfaces/IWithdrawRequestManager.sol";
import {MorphoLendingRouter} from "../src/routers/MorphoLendingRouter.sol";
import {IYieldStrategy} from "../src/interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id} from "../src/interfaces/Morpho/IMorpho.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

MorphoLendingRouter constant MORPHO_LENDING_ROUTER = MorphoLendingRouter(0x9a0c630C310030C4602d1A76583a3b16972ecAa0);

contract CreateInitialPosition is Script {

    function getDepositData(
        address /* user */,
        uint256 /* assets */
    ) internal pure returns (bytes memory depositData) {
        // TODO: need to find a way to inject other deposit data
        return abi.encode(StakingTradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            minPurchaseAmount: 0,
            dexId: uint8(DexId.CURVE_V2),
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 1,
                toIndex: 0
            })),
            stakeData: bytes("")
        }));
    }

    function run() public {
        require(msg.sender == 0x407e6F2E410e773ED0D1c4f3c7FCFAE0fF67F2ce, "Invalid sender");

        IYieldStrategy vault = IYieldStrategy(vm.envAddress("VAULT_ADDRESS"));
        console.log("Creating initial position for vault", address(vault));
        createMorphoPosition(vault);
    }

    function createMorphoPosition(IYieldStrategy vault) internal {
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
        uint256 initialSupply = 1.0e6;

        console.log("Supplying initial assets to market");
        vm.startBroadcast();
        MORPHO.supply(marketParams, initialSupply, 0, msg.sender, "");
        vm.stopBroadcast();

        uint256 initialBorrow =  0.9e6;
        uint256 initialDeposit = 1.0e6;
        console.log("Creating initial position");
        console.log("Initial Deposit", initialDeposit);
        console.log("Initial Borrow", initialBorrow);

        bytes memory depositData = getDepositData(msg.sender, initialDeposit + initialBorrow);

        vm.startBroadcast();
        MORPHO_LENDING_ROUTER.enterPosition(
            msg.sender, address(vault), initialDeposit, initialBorrow, depositData
        );
        vm.stopBroadcast();

        uint256 balance = MORPHO_LENDING_ROUTER.balanceOfCollateral(msg.sender, address(vault));
        console.log("Balance of Collateral: ", balance);

        console.log("Morpho Market After");
        console.log("Total Supply Assets: ", MORPHO.market(id).totalSupplyAssets);
        console.log("Total Borrow Assets: ", MORPHO.market(id).totalBorrowAssets);
    }
}