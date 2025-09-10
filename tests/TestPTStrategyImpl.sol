// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequestImpl.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/interfaces/ITradingModule.sol";
import "./TestStakingStrategy.sol";
import "../src/staking/PendlePT.sol";
import "../src/staking/PendlePTLib.sol";
import "../src/oracles/PendlePTOracle.sol";
import "../src/staking/PendlePT_sUSDe.sol";
import { OrderFilledV2 } from "../src/interfaces/IPendle.sol";

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

    IPRouter.FillOrderParams[] internal depositFills;
    IPRouter.FillOrderParams[] internal redeemFills;

    function getDepositData(
        address, /* user */
        uint256 /* depositAmount */
    )
        internal
        view
        override
        returns (bytes memory)
    {
        IPRouter.LimitOrderData memory limitOrderData;

        PendleDepositParams memory d = PendleDepositParams({
            dexId: defaultDexId,
            minPurchaseAmount: 0,
            exchangeData: defaultDepositExchangeData,
            pendleData: abi.encode(
                PendleDepositData({
                    minPtOut: 0,
                    approxParams: IPRouter.ApproxParams({
                        guessMin: 0,
                        guessMax: type(uint256).max,
                        guessOffchain: 0,
                        maxIteration: 256,
                        eps: 1e15 // recommended setting (0.1%)
                     }),
                    limitOrderData: limitOrderData
                })
            )
        });

        return abi.encode(d);
    }

    function getRedeemData(address user, uint256 /* shares */ ) internal view override returns (bytes memory) {
        WithdrawRequest memory w;
        if (address(manager) != address(0)) {
            (w, /* */ ) = manager.getWithdrawRequest(address(y), user);
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

    function setMarketVariables() internal virtual;

    function deployYieldStrategy() internal override {
        strategyName = "Pendle PT";
        address(deployCode("PendlePTLib.sol:PendlePTLib"));

        setMarketVariables();
        bool isSUSDe = tokenOut == address(sUSDe);

        if (isSUSDe) {
            y = new PendlePT_sUSDe(market, tokenIn, tokenOut, address(USDC), ptToken, 0.001e18, manager);
        } else {
            y = new PendlePT(market, tokenIn, tokenOut, address(USDC), ptToken, 0.001e18, manager);
        }

        w = ERC20(y.yieldToken());
        // NOTE: is tokenOut the right token to use here?
        (AggregatorV2V3Interface baseToUSDOracle,) = TRADING_MODULE.priceOracles(address(tokenOut));
        PendlePTOracle pendleOracle =
            new PendlePTOracle(market, baseToUSDOracle, false, true, 15 minutes, "Pendle PT", address(0), 1e18);

        o = new MockOracle(pendleOracle.latestAnswer());
    }

    function postDeploySetup() internal virtual override {
        vm.startPrank(owner);
        if (address(manager) != address(0)) manager.setApprovedVault(address(y), true);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(y.asset()),
            ITradingModule.TokenPermissions({ allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 })
        );
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(tokenOut),
            ITradingModule.TokenPermissions({ allowSell: true, dexFlags: uint32(1 << defaultDexId), tradeTypeFlags: 5 })
        );

        if (tokenOut == address(sUSDe)) {
            TRADING_MODULE.setTokenPermissions(
                address(y),
                address(DAI),
                ITradingModule.TokenPermissions({
                    allowSell: true,
                    dexFlags: uint32(1 << defaultDexId),
                    tradeTypeFlags: 5
                })
            );
            // Allow trading of USDe
            TRADING_MODULE.setTokenPermissions(
                address(y),
                address(tokenIn),
                ITradingModule.TokenPermissions({
                    allowSell: true,
                    dexFlags: uint32(1 << defaultDexId),
                    tradeTypeFlags: 5
                })
            );
        }
        vm.stopPrank();

        maxEntryValuationSlippage = 0.01e18;
        maxExitValuationSlippage = 0.01e18;
    }

    function test_enterPosition_usingLimitOrder() public {
        vm.skip(depositFills.length == 0);
        vm.startPrank(msg.sender);
        MORPHO.setAuthorization(address(lendingRouter), true);
        asset.approve(address(lendingRouter), defaultDeposit);

        IPRouter.LimitOrderData memory limitOrderData = IPRouter.LimitOrderData({
            limitRouter: 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321,
            epsSkipMarket: 0,
            normalFills: depositFills,
            flashFills: new IPRouter.FillOrderParams[](0),
            optData: bytes("")
        });

        PendleDepositParams memory d = PendleDepositParams({
            dexId: defaultDexId,
            minPurchaseAmount: 0,
            exchangeData: defaultDepositExchangeData,
            pendleData: abi.encode(
                PendleDepositData({
                    minPtOut: 0,
                    approxParams: IPRouter.ApproxParams({
                        guessMin: 0,
                        guessMax: type(uint256).max,
                        guessOffchain: 0,
                        maxIteration: 256,
                        eps: 1e15 // recommended setting (0.1%)
                     }),
                    limitOrderData: limitOrderData
                })
            )
        });

        bytes memory depositData = abi.encode(d);

        vm.expectEmit(false, false, false, false, 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321);
        emit OrderFilledV2(
            bytes32(0),
            IPRouter.OrderType.SY_FOR_PT,
            address(0), // This is the YT address
            address(tokenIn),
            0,
            0,
            0,
            0,
            msg.sender,
            msg.sender
        );

        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, depositData);
        vm.stopPrank();
    }

    function test_exitPosition_usingLimitOrder() public {
        vm.skip(redeemFills.length == 0);
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.warp(block.timestamp + 6 minutes);

        IPRouter.LimitOrderData memory limitOrderData = IPRouter.LimitOrderData({
            limitRouter: 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321,
            epsSkipMarket: 0,
            normalFills: new IPRouter.FillOrderParams[](0),
            flashFills: redeemFills,
            optData: bytes("")
        });

        PendleRedeemParams memory d = PendleRedeemParams({
            dexId: defaultDexId,
            minPurchaseAmount: 0,
            exchangeData: defaultRedeemExchangeData,
            limitOrderData: abi.encode(limitOrderData)
        });
        bytes memory redeemData = abi.encode(d);

        uint256 sharesToExit = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 debtToRepay = type(uint256).max;

        vm.startPrank(msg.sender);
        vm.expectEmit(false, false, false, false, 0x000000000000c9B3E2C3Ec88B1B4c0cD853f4321);
        emit OrderFilledV2(
            bytes32(0),
            IPRouter.OrderType.PT_FOR_SY,
            address(0), // This is the YT address
            address(tokenOut),
            0,
            0,
            0,
            0,
            msg.sender,
            msg.sender
        );
        lendingRouter.exitPosition(msg.sender, address(y), msg.sender, sharesToExit, debtToRepay, redeemData);
        vm.stopPrank();
    }
}

contract TestStakingStrategy_PT_sUSDe is TestStakingStrategy_PT {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 22_352_979;
    }

    function setMarketVariables() internal override {
        market = 0xB162B764044697cf03617C2EFbcB1f42e31E4766;
        tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenOut = address(sUSDe);
        withdrawToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        ptToken = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
        manager = new EthenaWithdrawRequestManager();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(manager), abi.encodeWithSelector(Initializable.initialize.selector, bytes(""))
        );
        manager = EthenaWithdrawRequestManager(address(proxy));

        withdrawRequest = new TestEthenaWithdrawRequest();
        defaultDexId = uint8(DexId.CURVE_V2);
        defaultDepositExchangeData = abi.encode(
            CurveV2SingleData({ pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72, fromIndex: 1, toIndex: 0 })
        );
        defaultRedeemExchangeData = abi.encode(
            CurveV2SingleData({
                pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
                fromIndex: 0, // DAI
                toIndex: 1 // USDC
             })
        );
        defaultWithdrawRequestExchangeData = abi.encode(
            CurveV2SingleData({
                // Sells via the USDe/USDC pool
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 0,
                toIndex: 1
            })
        );

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
        maxWithdrawValuationChange = 0.0085e18;

        (AggregatorV2V3Interface tokenOutSyOracle, /* */ ) = TRADING_MODULE.priceOracles(address(USDe));
        withdrawTokenOracle =
            new MockOracle(tokenOutSyOracle.latestAnswer() * int256(10 ** (18 - tokenOutSyOracle.decimals())));

        vm.startPrank(owner);
        TRADING_MODULE.setPriceOracle(address(USDe), AggregatorV2V3Interface(address(withdrawTokenOracle)));
        vm.stopPrank();
    }

    function getWithdrawRequestData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        override
        returns (bytes memory withdrawRequestData)
    {
        // Warp to expiry
        vm.warp(1_748_476_800 + 1);
        return bytes("");
    }

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(USDe));
    }
}

contract TestStakingStrategy_PT_eUSDe_13AUG2025 is TestStakingStrategy_PT {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 22_792_979;
    }

    function setMarketVariables() internal override {
        market = 0xE93B4A93e80BD3065B290394264af5d82422ee70;
        tokenIn = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        tokenOut = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        withdrawToken = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
        ptToken = 0x14Bdc3A3AE09f5518b923b69489CBcAfB238e617;
        defaultDexId = uint8(DexId.CURVE_V2);
        defaultDepositExchangeData = abi.encode(
            CurveV2SingleData({ pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72, fromIndex: 1, toIndex: 0 })
        );
        defaultRedeemExchangeData = abi.encode(
            CurveV2SingleData({ pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72, fromIndex: 0, toIndex: 1 })
        );

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        // LimitOrderType: 3, YT_FOR_SY or YT_FOR_TOKEN
        depositFills.push(
            IPRouter.FillOrderParams({
                order: IPRouter.Order({
                    salt: 7_976_209_603_608_691_259_510_522_740_202_114_089_739_545_406_106_745_663_613_802_393_604_058_421_028,
                    expiry: 1_751_256_720,
                    nonce: 0,
                    orderType: IPRouter.OrderType.YT_FOR_SY,
                    token: 0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F,
                    YT: 0xe8eF806c8aaDc541408dcAd36107c7d26a391712,
                    maker: 0x32332308Ad4761d6fEF9DfD98224Aa722c09e269,
                    receiver: 0x32332308Ad4761d6fEF9DfD98224Aa722c09e269,
                    makingAmount: 100_000_000_000_000_000_000_000,
                    lnImpliedRate: 85_076_172_355_119_263,
                    failSafeRate: 900_000_000_000_000_000,
                    permit: bytes("")
                }),
                signature: hex"035e3285d87ea09f56bdc0970604d249394ad576d6559e9a2129d311cab47f7b01df4b4b6d1e0d837ce0baa523391b21d858917ecff523bd42adfb26c053da8e1c",
                // Does not have the full making amount here, but this is enough for the test
                makingAmount: 26_044_106_227_207_729_924_039
            })
        );

        // NOTE: use this API
        /* https://api-v2.pendle.finance/core/v1/sdk/1/markets/{market}/swap
        ?receiver=xxx&slippage=0.01&enableAggregator=false&tokenIn={tokenIn}&tokenOut={tokenOut}&amountIn={amountIn}
        */

        redeemFills.push(
            IPRouter.FillOrderParams({
                order: IPRouter.Order({
                    salt: 15_649_304_437_678_776_201_695_093_386_247_113_070_979_384_594_550_464_093_058_576_137_381_267_332_971,
                    expiry: 1_751_598_305,
                    nonce: 8,
                    orderType: IPRouter.OrderType.YT_FOR_SY,
                    token: 0x90D2af7d622ca3141efA4d8f1F24d86E5974Cc8F,
                    YT: 0xe8eF806c8aaDc541408dcAd36107c7d26a391712,
                    maker: 0x5EBe5223831523823528Ef0a7EdF67D288B1B070,
                    receiver: 0x5EBe5223831523823528Ef0a7EdF67D288B1B070,
                    makingAmount: 21_572_000_000_000_000_000_000,
                    lnImpliedRate: 71_203_759_006_332_065,
                    failSafeRate: 900_000_000_000_000_000,
                    permit: bytes("")
                }),
                signature: hex"ab4530393a915a8e7101afcd399f2f1487a773997221f474ec1e36b131c5f3a946579838b46fb20d288d1e1a44ceec2224e9e85e33e9ca0c6ba1fa394316e4bb1c",
                makingAmount: 21_572_000_000_000_000_000_000
            })
        );
    }

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(USDe));
    }
}
