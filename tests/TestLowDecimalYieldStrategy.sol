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
            /* */,
            uint256 collateralValue,
            uint256 maxBorrow
        ) = lendingRouter.healthFactor(msg.sender, address(y));

        assertApproxEqRel(collateralValue, 100_000e6, 0.001e18);
        assertApproxEqRel(maxBorrow, 91_500e6, 0.001e18);
    }

    function test_vault_share_precision() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 oneShare = 10 ** y.decimals();
        uint256 yt = y.convertSharesToYieldToken(oneShare);
        uint256 shares = y.convertYieldTokenToShares(yt);
        assertEq(shares, oneShare);
        assertEq(yt, 1e6);
    }

    function test_fee_accrual() public {
        uint256 initialDeposit = 1e4;
        console.log("initial deposit", initialDeposit);
        _enterPosition(msg.sender, initialDeposit, 0);

        uint256 totalFeesCollected = 0;
        for (uint256 i; i < (365 * 24); i++) {
            vm.warp(block.timestamp + 1 hours);
            totalFeesCollected += y.collectFees();
        }
        console.log("total fees", totalFeesCollected);
        console.log("implied fee rate", totalFeesCollected * 10000 / initialDeposit, "bps");
    }

}