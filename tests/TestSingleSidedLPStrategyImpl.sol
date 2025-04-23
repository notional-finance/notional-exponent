// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "./TestSingleSidedLPStrategy.sol";
import "../src/utils/Constants.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/EtherFi.sol";

contract Test_LP_Convex_USDC_USDT is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85);
        rewardPool = 0x83644fa70538e5251D125205186B14A76cA63606;
        asset = USDC;
        w = ERC20(rewardPool);
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
    
}

contract Test_LP_Convex_OETH_ETH is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x94B17476A93b3262d87B9a326965D1E91f9c13E7);
        rewardPool = 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A;
        asset = ERC20(address(WETH));
        curveInterface = CurveInterface.V1;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;
        w = ERC20(rewardPool);

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
        MockOracle oETHOracle = new MockOracle(ethOracle.latestAnswer() * 1e18 / 1e8);
        // TODO: there is no oETH oracle on mainnet
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(
            address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3),
            AggregatorV2V3Interface(address(oETHOracle))
        );
        maxExitValuationSlippage = 0.005e18;
    }
}

contract Test_LP_Convex_weETH_WETH is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5);
        rewardPool = 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58;
        asset = ERC20(address(WETH));
        stakeTokenIndex = 1;

        managers[0] = new GenericERC20WithdrawRequestManager(owner, address(asset));
        managers[1] = new EtherFiWithdrawRequestManager(owner);

        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;
        w = ERC20(rewardPool);

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        maxExitValuationSlippage = 0.005e18;
    }
}

contract Test_LP_Curve_USDe_USDC is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72);
        curveGauge = 0x04E80Db3f84873e4132B221831af1045D27f140F;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 1;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        maxExitValuationSlippage = 0.005e18;
    }
}