// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./DeployVault.sol";
import { WithdrawRequest } from "../src/interfaces/IWithdrawRequestManager.sol";
import { PendlePT, PendleDepositParams, PendleRedeemParams } from "../src/staking/PendlePT.sol";
import { PendlePTLib, PendleDepositData } from "../src/staking/PendlePTLib.sol";
import { USDe, DAI } from "../src/interfaces/IEthena.sol";
import { PendlePT_sUSDe, sUSDe } from "../src/staking/PendlePT_sUSDe.sol";
import { PendlePTOracle } from "../src/oracles/PendlePTOracle.sol";
import { IPRouter } from "../src/interfaces/IPendle.sol";

abstract contract DeployPTVault is DeployVault {
    string internal expiryDate;
    string internal pendleTokenSymbol;
    address internal asset;

    address internal market;
    address internal tokenIn;
    address internal tokenOut;
    address internal ptToken;
    PendlePTOracle internal pendleOracle;

    uint8 internal defaultDexId;
    bytes internal defaultDepositExchangeData;
    bytes internal defaultRedeemExchangeData;
    bytes internal defaultWithdrawRequestExchangeData;

    bool internal useSyOracleRate;

    constructor(
        string memory _expiryDate,
        string memory _pendleTokenSymbol,
        address _asset,
        address _market,
        address _tokenIn,
        address _tokenOut,
        address _ptToken,
        uint256 _feeRate,
        uint256 _MORPHO_LLTV,
        bool _useSyOracleRate,
        address _proxy
    ) {
        expiryDate = _expiryDate;
        pendleTokenSymbol = _pendleTokenSymbol;
        asset = _asset;
        proxy = _proxy;
        depositAmount = asset == address(WETH) ? 10e18 : 10_000e6;
        supplyAmount = asset == address(WETH) ? 100e18 : 100_000e6;
        borrowAmount = asset == address(WETH) ? 90e18 : 90_000e6;
        market = _market;
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        ptToken = _ptToken;
        feeRate = _feeRate;
        useSyOracleRate = _useSyOracleRate;
        MORPHO_LLTV = _MORPHO_LLTV;
    }

    function name() internal view override returns (string memory) {
        return string(abi.encodePacked("Notional PT ", pendleTokenSymbol, " ", expiryDate));
    }

    function symbol() internal view override returns (string memory) {
        return string(abi.encodePacked("n-PT-", pendleTokenSymbol, "-", expiryDate));
    }

    function deployVault() public override returns (address impl) {
        // TODO: Check for PendlePTLib
        bool isSUSDe = tokenOut == address(sUSDe);

        vm.startBroadcast();
        if (isSUSDe) {
            impl = address(
                new PendlePT_sUSDe({
                    market: market,
                    tokenInSY: tokenIn,
                    tokenOutSY: tokenOut,
                    asset: asset,
                    yieldToken: ptToken,
                    feeRate: feeRate,
                    withdrawRequestManager: managers()[0]
                })
            );
        } else {
            impl = address(
                new PendlePT({
                    market: market,
                    tokenInSY: tokenIn,
                    tokenOutSY: tokenOut,
                    asset: asset,
                    yieldToken: ptToken,
                    feeRate: feeRate,
                    withdrawRequestManager: managers()[0]
                })
            );
        }

        // NOTE: is tokenOut the right token to use here?
        (AggregatorV2V3Interface baseToUSDOracle,) = TRADING_MODULE.priceOracles(address(tokenOut));
        pendleOracle = new PendlePTOracle({
            pendleMarket_: market,
            baseToUSDOracle_: baseToUSDOracle,
            invertBase_: false,
            useSyOracleRate_: useSyOracleRate,
            twapDuration_: 15 minutes,
            description_: string(abi.encodePacked(name(), " Oracle")),
            sequencerUptimeOracle_: address(0),
            ptOraclePrecision_: 1e18
        });

        vm.stopBroadcast();
    }

    function postDeploySetup() internal view override returns (MethodCall[] memory calls) {
        MethodCall[] memory superCalls = super.postDeploySetup();
        calls = new MethodCall[](superCalls.length + 1);
        for (uint256 i = 0; i < superCalls.length; i++) {
            calls[i] = superCalls[i];
        }

        calls[superCalls.length - 1] = MethodCall({
            to: address(TRADING_MODULE),
            value: 0,
            callData: abi.encodeWithSelector(
                TRADING_MODULE.setPriceOracle.selector, address(ptToken), AggregatorV2V3Interface(address(pendleOracle))
            )
        });
    }

    function tradePermissions() internal view virtual override returns (bytes[] memory t) {
        t = new bytes[](2);
        // Sell asset on entry for TOKEN_IN_SY
        t[0] = getTokenPermission(proxy, address(asset), defaultDexId);
        // Sell tokenOut on exit for asset
        t[1] = getTokenPermission(proxy, address(tokenOut), defaultDexId);
    }

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
        if (address(managers()[0]) != address(0)) {
            (w, /* */ ) = managers()[0].getWithdrawRequest(address(proxy), user);
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
}

contract DeployPTVault_sUSDe_26NOV2025 is DeployPTVault {
    constructor()
        DeployPTVault(
            "26NOV2025", // expiryDate
            "sUSDe", // pendleTokenSymbol
            address(USDC), // asset
            0xb6aC3d5da138918aC4E84441e924a20daA60dBdd, // market
            address(USDe), // tokenIn
            address(sUSDe), // tokenOut
            0xe6A934089BBEe34F832060CE98848359883749B3, // ptToken
            0.001e18, // feeRate
            0.915e18, // MORPHO_LLTV
            true, // useSyOracleRate
            address(0) // proxy
        )
    {
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
        skipExit = true;
    }

    function managers() internal view override returns (IWithdrawRequestManager[] memory m) {
        m = new IWithdrawRequestManager[](1);
        m[0] = ADDRESS_REGISTRY.getWithdrawRequestManager(address(sUSDe));
        return m;
    }

    function tradePermissions() internal view override returns (bytes[] memory t) {
        t = new bytes[](4);
        // Sell asset on entry for TOKEN_IN_SY
        t[0] = getTokenPermission(proxy, address(asset), uint8(DexId.CURVE_V2));
        // Sell tokenOut on exit for asset
        t[1] = getTokenPermission(proxy, address(tokenOut), uint8(DexId.CURVE_V2));

        if (tokenOut == address(sUSDe)) {
            // Have to sell DAI on exit for USDe
            t[2] = getTokenPermission(proxy, address(DAI), uint8(DexId.CURVE_V2));
            // Have to sell USDe on exit for asset
            t[3] = getTokenPermission(proxy, address(USDe), uint8(DexId.CURVE_V2));
        }
    }
}
