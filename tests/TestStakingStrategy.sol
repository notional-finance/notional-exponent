// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/staking/EtherFi.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/interfaces/ITradingModule.sol";

contract TestStakingStrategy is TestMorphoYieldStrategy {
    EtherFiWithdrawRequestManager public manager;

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory redeemData) {
        uint24 fee = 500;
        return abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.UNISWAP_V3),
            exchangeData: abi.encode((fee))
        }));
    }

    function deployYieldStrategy() internal override {
        manager = new EtherFiWithdrawRequestManager(owner);
        y = new EtherFiStaking(
            owner,
            0.0010e18, // 0.1% fee rate
            address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            0.915e18, // 91.5% LTV
            manager
        );
        // weETH
        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 100e18;
        defaultBorrow = 900e18;

        vm.startPrank(owner);
        manager.setApprovedVault(address(y), true);

        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}
