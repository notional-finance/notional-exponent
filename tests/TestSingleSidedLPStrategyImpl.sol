// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "./TestSingleSidedLPStrategy.sol";
import "../src/utils/Constants.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/withdraws/AbstractWithdrawRequestManager.sol";
import "./TestWithdrawRequestImpl.sol";

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
        withdrawRequests[1] = new TestEtherFiWithdrawRequest();

        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;
        w = ERC20(rewardPool);

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        maxExitValuationSlippage = 0.005e18;

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });
    }

    function postDeployHook() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
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

        tradeBeforeDepositParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });
    }

    function postDeployHook() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(USDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract Test_LP_Curve_sDAI_sUSDe is TestSingleSidedLPStrategy {

    function getDepositData(address user, uint256 depositAmount) internal view override returns (bytes memory) {
        TradeParams[] memory depositTrades = new TradeParams[](2);
        uint256 sDAIAmount = depositAmount / 2;
        uint256 sUSDeAmount = depositAmount - sDAIAmount;
        bytes memory sDAI_StakeData = abi.encode(StakingTradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
                fromIndex: 1,
                toIndex: 0
            })),
            stakeData: bytes("")
        }));
        bytes memory sUSDe_StakeData = abi.encode(StakingTradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 1,
                toIndex: 0
            })),
            stakeData: bytes("")
        }));

        depositTrades[0] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: sDAIAmount,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(managers[0], sDAI_StakeData)
        });
        depositTrades[1] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: sUSDeAmount,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(managers[1], sUSDe_StakeData)
        });

        return abi.encode(DepositParams({
            minPoolClaim: 0,
            depositTrades: depositTrades
        }));
    }

    function getRedeemData(address user, uint256 redeemAmount) internal override returns (bytes memory) {
        // TODO: There is no way to trade out of this position, therefore we cannot flash liquidate
        vm.skip(true);
    }

    function setMarketVariables() internal override {
        lpToken = ERC20(0x167478921b907422F8E88B43C4Af2B8BEa278d3A);
        curveGauge = 0x330Cfd12e0E97B0aDF46158D2A81E8Bd2985c6cB;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 1;
        usdOracleToken = address(sUSDe);
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        maxExitValuationSlippage = 0.005e18;

        managers[0] = new GenericERC4626WithdrawRequestManager(owner, address(sDAI));
        managers[1] = new EthenaWithdrawRequestManager(owner);
        withdrawRequests[0] = new TestGenericERC4626WithdrawRequest();
        withdrawRequests[1] = new TestEthenaWithdrawRequest();

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
                fromIndex: 0,
                toIndex: 1
            }))
        });

        tradeBeforeRedeemParams[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 0,
                toIndex: 1
            }))
        });

        vm.startPrank(owner);
        MockOracle sDAIOracle = new MockOracle(1156574190016110658);
        TRADING_MODULE.setPriceOracle(address(sDAI), AggregatorV2V3Interface(address(sDAIOracle)));
        vm.stopPrank();

    }

    function postDeployHook() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(sUSDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(USDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(DAI),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));

        // Allow withdraw managers to sell USDC
        TRADING_MODULE.setTokenPermissions(
            address(managers[0]),
            address(USDC),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(managers[1]),
            address(USDC),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        // Allow Ethena manager to sell DAI
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(DAI),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}