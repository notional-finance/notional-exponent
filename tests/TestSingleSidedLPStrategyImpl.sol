// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "./TestSingleSidedLPStrategy.sol";

contract Test_LP_Convex_USDC_USDT is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85);
        rewardPool = 0x83644fa70538e5251D125205186B14A76cA63606;
        asset = USDC;
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
    
}

        // OETH/ETH: 0x94B17476A93b3262d87B9a326965D1E91f9c13E7, 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A
        // weETH/WETH: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5, 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58
