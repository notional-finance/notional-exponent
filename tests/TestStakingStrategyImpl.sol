// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequestImpl.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "../src/staking/EtherFi.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/interfaces/ITradingModule.sol";
import "./TestStakingStrategy.sol";
import "../src/staking/PendlePT.sol";
import "../src/oracles/PendlePTOracle.sol";
import "../src/staking/PendlePT_sUSDe.sol";

contract TestStakingStrategy_EtherFi is TestStakingStrategy {
    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory redeemData) {
        return abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.CURVE_V2),
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                fromIndex: 1,
                toIndex: 0
            }))
        }));
    }

    function deployYieldStrategy() internal override {
        manager = new EtherFiWithdrawRequestManager(owner);
        y = new EtherFiStaking(
            owner,
            0.0010e18, // 0.1% fee rate
            IRM,
            0.915e18, // 91.5% LTV
            manager
        );
        // weETH
        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;
        maxEntryValuationSlippage = 0.0050e18;
        maxExitValuationSlippage = 0.0050e18;
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        manager.setApprovedVault(address(y), true);

        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();

        withdrawRequest = new TestEtherFiWithdrawRequest();
    }
}

abstract contract TestStakingStrategy_PT is TestStakingStrategy {
    address internal market;
    address internal tokenIn;
    address internal tokenOut;
    address internal withdrawToken;
    address internal ptToken;

    uint8 internal defaultDexId;
    bytes internal defaultDepositExchangeData;
    bytes internal defaultRedeemExchangeData;
    bytes internal defaultWithdrawRequestExchangeData;

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal view override returns (bytes memory) {
        IPRouter.LimitOrderData memory limitOrderData;

        PendleDepositParams memory d = PendleDepositParams({
            dexId: defaultDexId,
            minPurchaseAmount: 0,
            exchangeData: defaultDepositExchangeData,
            minPtOut: 0,
            approxParams: IPRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e15 // recommended setting (0.1%)
            }),
            limitOrderData: limitOrderData
        });

        return abi.encode(d);
    }

    function getRedeemData(
        address user,
        uint256 /* shares */
    ) internal view override returns (bytes memory) {
        WithdrawRequest memory w;
        if (address(manager) != address(0)) {
            (w, /* */) = manager.getWithdrawRequest(address(y), user);
        }
        PendleRedeemParams memory r;

        r.minPurchaseAmount = 0;
        r.dexId = defaultDexId;
        if (w.requestId == 0) {
            r.exchangeData = defaultRedeemExchangeData;
        } else {
            r.exchangeData = defaultWithdrawRequestExchangeData;
        }

        return abi.encode(r);
    }

    function getWithdrawRequestData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory withdrawRequestData) {
        PendleWithdrawParams memory w;
        return abi.encode(w);
    }

    function setMarketVariables() virtual internal;

    function deployYieldStrategy() internal override {
        setMarketVariables();
        bool isSUSDe = tokenOut == address(sUSDe);

        if (isSUSDe) {
            y = new PendlePT_sUSDe(
                market,
                tokenIn,
                tokenOut,
                address(USDC),
                ptToken,
                owner,
                0.0010e18,
                IRM,
                0.915e18,
                manager
            );
        } else {
            y = new PendlePT(
                market,
                tokenIn,
                tokenOut,
                address(USDC),
                ptToken,
                owner,
                0.0010e18,
                IRM,
                0.915e18,
                manager
            );
        }

        w = ERC20(y.yieldToken());
        // NOTE: is tokenOut the right token to use here?
        (AggregatorV2V3Interface baseToUSDOracle, ) = TRADING_MODULE.priceOracles(address(tokenOut));
        PendlePTOracle pendleOracle = new PendlePTOracle(
            market,
            baseToUSDOracle,
            false,
            true,
            15 minutes,
            "Pendle PT",
            address(0)
        );

        o = new MockOracle(pendleOracle.latestAnswer());
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        if (address(manager) != address(0)) manager.setApprovedVault(address(y), true);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(y.asset()),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(tokenOut),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 }
        ));

        if (tokenOut == address(sUSDe)) {
            TRADING_MODULE.setTokenPermissions(
                address(y),
                address(DAI),
                ITradingModule.TokenPermissions(
                { allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 }
            ));
            // Allow trading of USDe
            TRADING_MODULE.setTokenPermissions(
                address(y),
                address(tokenIn),
                ITradingModule.TokenPermissions(
                { allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 }
            ));
        }
        vm.stopPrank();

        maxEntryValuationSlippage = 0.01e18;
        maxExitValuationSlippage = 0.01e18;
    }

    function test_enterPosition_usingLimitOrder() public {
        vm.startPrank(msg.sender);
        MORPHO.setAuthorization(address(y), true);
        asset.approve(address(y), defaultDeposit);
        IPRouter.FillOrderParams[] memory normalFills = new IPRouter.FillOrderParams[](1);
        normalFills[0] = IPRouter.FillOrderParams({
            order: IPRouter.Order({
                salt: 1272298264258536272942376644425766518232160717710904308615777799358817600096,
                expiry: 1745853785,
                nonce: 0,
                orderType: IPRouter.OrderType.YT_FOR_SY,
                token: 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497,
                YT: 0x1de6Ff19FDA7496DdC12f2161f6ad6427c52aBBe,
                maker: 0x401e4211414d8286212d9c0Bc77f5F54B15972C7,
                receiver: 0x401e4211414d8286212d9c0Bc77f5F54B15972C7,
                makingAmount: 20083061612967988565283,
                lnImpliedRate: 74913576139103066,
                failSafeRate: 900000000000000000,
                permit: bytes("")
            }),
            signature: hex"56929fa970eead4bcbb454fb2e837d31d138aef4021409eb42a31c95cd83d860577abbcc5e1233882ebe3d53d7281d4e9880181df8b8ca3360fabf67a84f1c1e1c",
            makingAmount: 20083061612967988565283
        });

        IPRouter.LimitOrderData memory limitOrderData = IPRouter.LimitOrderData({
            limitRouter: 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321,
            epsSkipMarket: 0,
            normalFills: normalFills,
            flashFills: new IPRouter.FillOrderParams[](0),
            optData: bytes("")
        });

        PendleDepositParams memory d = PendleDepositParams({
            dexId: defaultDexId,
            minPurchaseAmount: 0,
            exchangeData: defaultDepositExchangeData,
            minPtOut: 0,
            approxParams: IPRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e15 // recommended setting (0.1%)
            }),
            limitOrderData: limitOrderData
        });

        bytes memory depositData = abi.encode(d);

        vm.expectEmit(false, false, false, false, 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321);
        emit OrderFilledV2(
            bytes32(0),
            IPRouter.OrderType.SY_FOR_PT,
            0x708dD9B344dDc7842f44C7b90492CF0e1E3eb868,
            address(tokenIn),
            0,
            0,
            0,
            0,
            msg.sender,
            msg.sender
        );

        y.enterPosition(msg.sender, defaultDeposit, defaultBorrow, depositData);
        vm.stopPrank();
    }
}

contract TestStakingStrategy_PT_eUSDe is TestStakingStrategy_PT {
    function setMarketVariables() internal override {
        market = 0x85667e484a32d884010Cf16427D90049CCf46e97;
        tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenOut = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        withdrawToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        ptToken = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
        defaultDexId = uint8(DexId.CURVE_V2);
        defaultDepositExchangeData = abi.encode(CurveV2SingleData({
            pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
            fromIndex: 1,
            toIndex: 0
        }));
        defaultRedeemExchangeData = abi.encode(CurveV2SingleData({
            pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
            fromIndex: 0,
            toIndex: 1
        }));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
}


contract TestStakingStrategy_PT_sUSDe is TestStakingStrategy_PT {
    function setMarketVariables() internal override {
        market = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
        tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenOut = address(sUSDe);
        withdrawToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        ptToken = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
        manager = new EthenaWithdrawRequestManager(owner);
        withdrawRequest = new TestEthenaWithdrawRequest();
        defaultDexId = uint8(DexId.CURVE_V2);
        defaultDepositExchangeData = abi.encode(CurveV2SingleData({
            pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
            fromIndex: 1,
            toIndex: 0
        }));
        defaultRedeemExchangeData = abi.encode(CurveV2SingleData({
            pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
            fromIndex: 0, // DAI
            toIndex: 1 // USDC
        }));
        defaultWithdrawRequestExchangeData = abi.encode(CurveV2SingleData({
            // Sells via the USDe/USDC pool
            pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
            fromIndex: 0,
            toIndex: 1
        }));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        (AggregatorV2V3Interface tokenOutSyOracle, /* */) = TRADING_MODULE.priceOracles(address(tokenOut));
        withdrawTokenOracle = new MockOracle(tokenOutSyOracle.latestAnswer() * int256(10 ** (18 - tokenOutSyOracle.decimals())));

        vm.startPrank(owner);
        TRADING_MODULE.setPriceOracle(address(tokenOut), AggregatorV2V3Interface(address(withdrawTokenOracle)));
        vm.stopPrank();
    }
}

