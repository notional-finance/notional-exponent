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

    function test_share_precision() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        (
            uint256 borrowAmount,
            uint256 collateralValue,
            uint256 maxBorrow
        ) = lendingRouter.healthFactor(msg.sender, address(y));

        console.log("wrapped tokens", w.balanceOf(address(y)));
        console.log("total supply", y.totalSupply());
        console.log("effective supply", y.effectiveSupply());

        assertApproxEqRel(collateralValue, 100_000e6, 0.001e18);
        assertApproxEqRel(maxBorrow, 91_500e6, 0.001e18);
    }

}