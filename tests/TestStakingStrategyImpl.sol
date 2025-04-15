// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

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
            IRM,
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

        withdrawRequest = new TestEtherFiWithdrawRequest();
    }
}

abstract contract TestStakingStrategy_PT is TestStakingStrategy {
    address internal market;
    address internal tokenIn;
    address internal tokenOut;
    address internal redemptionToken;
    address internal ptToken;

    uint8 internal defaultDexId;
    bytes internal defaultDepositExchangeData;
    bytes internal defaultRedeemExchangeData;
    bytes internal defaultWithdrawRequestExchangeData;

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal view override returns (bytes memory) {
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
            })
        });

        return abi.encode(d);
    }

    function getRedeemData(
        address user,
        uint256 /* shares */
    ) internal view override returns (bytes memory) {
        (WithdrawRequest memory w, /* */) = manager.getWithdrawRequest(address(y), user);
        RedeemParams memory r;

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
        uint256 minTokenOutSy = 0;
        bytes memory withdrawData = "";
        return abi.encode(minTokenOutSy, withdrawData);
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
                redemptionToken,
                owner,
                0.0010e18,
                IRM,
                0.915e18,
                manager
            );
            vm.startPrank(owner);
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
            vm.stopPrank();
        } else {
            y = new PendlePT(
                market,
                tokenIn,
                tokenOut,
                address(USDC),
                ptToken,
                redemptionToken,
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
        vm.stopPrank();
    }
}

contract TestStakingStrategy_PT_eUSDe is TestStakingStrategy_PT {
    function setMarketVariables() internal override {
        market = 0x85667e484a32d884010Cf16427D90049CCf46e97;
        tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenOut = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        redemptionToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
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
        redemptionToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
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
    }
}

