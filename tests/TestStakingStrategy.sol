// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/staking/EtherFi.sol";
import "../src/withdraws/EtherFi.sol";

contract TestStakingStrategy is TestMorphoYieldStrategy {
    EtherFiWithdrawRequestManager public manager;

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

        vm.prank(owner);
        manager.setApprovedVault(address(y), true);
    }
}
