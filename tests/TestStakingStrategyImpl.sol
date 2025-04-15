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

contract TestStakingStrategy_PT_eUSDe is TestStakingStrategy {
    address internal constant market = 0x85667e484a32d884010Cf16427D90049CCf46e97;
    // USDe (Token In/Token Out)
    address internal constant tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant tokenOut = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    // Redemption Token USDe
    address internal constant redemptionToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    // eUSDe PT May 28 2025
    address internal constant ptToken = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    // No withdraw request manager
    address internal constant withdrawRequestManager = address(0);


    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal pure override returns (bytes memory) {
        PendleDepositParams memory d = PendleDepositParams({
            dexId: uint8(DexId.CURVE_V2),
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 1,
                toIndex: 0
            })),
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
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory) {
        RedeemParams memory r;

        r.minPurchaseAmount = 0;
        r.dexId = uint8(DexId.CURVE_V2);
        // For CurveV2 we need to swap the in and out indexes on exit
        CurveV2SingleData memory d;
        d.pool = 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72;
        d.fromIndex = 0;
        d.toIndex = 1;
        r.exchangeData = abi.encode(d);

        return abi.encode(r);
    }

    function deployYieldStrategy() internal override {
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
            IWithdrawRequestManager(withdrawRequestManager)
        );

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface baseToUSDOracle, ) = TRADING_MODULE.priceOracles(address(y.asset()));
        PendlePTOracle pendleOracle = new PendlePTOracle(
            market,
            baseToUSDOracle,
            false,
            true,
            15 minutes,
            "Pendle PT eUSDe",
            address(0)
        );

        o = new MockOracle(pendleOracle.latestAnswer());
    }
}
