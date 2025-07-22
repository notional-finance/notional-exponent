// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestMorphoYieldStrategy.sol";

contract TestLowDecimalYieldStrategy is TestMorphoYieldStrategy {

    function deployYieldStrategy() internal override virtual {
        w = new MockWrapperERC20(ERC20(address(USDC)), 6);
        o = new MockOracle(1e18);
        y = new MockYieldStrategy(
            address(USDC),
            address(w),
            0.0010e18 // 0.1% fee rate
        );
        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
        canInspectTransientVariables = true;
    }

}