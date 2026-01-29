// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./DeployVault.sol";
import {
    DepositParams,
    RedeemParams as SingleSidedRedeemParams,
    TradeParams,
    TradeType
} from "../src/interfaces/ISingleSidedLP.sol";
import "../src/single-sided-lp/CurveConvex2Token.sol";
import "../src/oracles/Curve2TokenOracle.sol";
import "../src/rewards/ConvexRewardManager.sol";
import "../src/rewards/CurveRewardManager.sol";
import { IRewardManager, RewardPoolStorage } from "../src/interfaces/IRewardManager.sol";
import { ChainlinkUSDOracle } from "../src/oracles/ChainlinkUSDOracle.sol";

abstract contract DeployLPVault is DeployVault {
    string internal token1Symbol;
    string internal token2Symbol;

    address internal asset;
    address internal lpToken;
    address internal curveGauge;
    address internal rewardPool;
    CurveInterface internal curveInterface;
    uint256 internal maxPoolShare;

    // Oracle Parameters
    uint8 internal primaryIndex;
    uint256 internal dyAmount;
    bool internal invertBase;
    uint256 internal lowerLimitMultiplier;
    uint256 internal upperLimitMultiplier;

    // Reward Parameters
    address[] internal rewardTokens;

    DepositParams depositParams;
    SingleSidedRedeemParams redeemParams;

    constructor(
        string memory _token1Symbol,
        string memory _token2Symbol,
        uint256 _morphoLLTV,
        uint8 _primaryIndex,
        address _asset,
        address _lpToken,
        address _curveGauge,
        address _rewardPool,
        CurveInterface _curveInterface,
        uint256 _maxPoolShare,
        uint256 _dyAmount,
        uint256 _lowerLimitMultiplier,
        uint256 _upperLimitMultiplier,
        uint256 _feeRate,
        bool _invertBase,
        address _proxy
    ) {
        proxy = _proxy;
        token1Symbol = _token1Symbol;
        token2Symbol = _token2Symbol;
        lpToken = _lpToken;
        curveGauge = _curveGauge;
        rewardPool = _rewardPool;
        curveInterface = _curveInterface;
        maxPoolShare = _maxPoolShare;
        dyAmount = _dyAmount;
        invertBase = _invertBase;
        lowerLimitMultiplier = _lowerLimitMultiplier;
        upperLimitMultiplier = _upperLimitMultiplier;
        asset = _asset;
        feeRate = _feeRate;
        MORPHO_LLTV = _morphoLLTV;
        primaryIndex = _primaryIndex;
    }

    function name() internal view override returns (string memory) {
        return string(abi.encodePacked("Notional LP ", token1Symbol, "/", token2Symbol));
    }

    function symbol() internal view override returns (string memory) {
        return string(abi.encodePacked("n-LP-", token1Symbol, "-", token2Symbol));
    }

    function deployVault() public override returns (address impl) {
        address rewardManager;
        vm.startBroadcast();
        if (curveGauge == address(0)) {
            rewardManager = address(new ConvexRewardManager());
        } else {
            rewardManager = address(new CurveRewardManager());
        }

        address yieldToken = rewardPool == address(0) ? address(curveGauge) : address(rewardPool);

        impl = address(
            new CurveConvex2Token({
                _maxPoolShare: maxPoolShare,
                _asset: address(asset),
                _yieldToken: yieldToken,
                _feeRate: feeRate,
                _rewardManager: rewardManager,
                params: DeploymentParams({
                    pool: address(lpToken),
                    poolToken: address(lpToken),
                    gauge: curveGauge,
                    convexRewardPool: address(rewardPool),
                    curveInterface: curveInterface
                })
            })
        );
        vm.stopBroadcast();
    }

    function deployCustomOracle() internal override returns (address oracle, address oracleToken) {
        (
            AggregatorV2V3Interface baseToUSDOracle, /* */
        ) = TRADING_MODULE.priceOracles(address(asset));
        // This needs to match the yield token above
        oracleToken = rewardPool == address(0) ? address(curveGauge) : address(rewardPool);

        vm.startBroadcast();
        oracle = address(
            new Curve2TokenOracle({
                _lowerLimitMultiplier: lowerLimitMultiplier,
                _upperLimitMultiplier: upperLimitMultiplier,
                _lpToken: address(lpToken),
                _primaryIndex: primaryIndex,
                description_: string(abi.encodePacked(name(), " Oracle")),
                sequencerUptimeOracle_: address(0),
                baseToUSDOracle_: baseToUSDOracle,
                _invertBase: invertBase,
                _dyAmount: dyAmount
            })
        );
        vm.stopBroadcast();
    }

    function postDeploySetup()
        internal
        override
        returns (MethodCall[] memory timelockCalls, MethodCall[] memory directCalls)
    {
        MethodCall[] memory superCalls;
        (timelockCalls, superCalls) = super.postDeploySetup();

        directCalls = new MethodCall[](superCalls.length + 1 + rewardTokens.length);

        for (uint256 i = 0; i < superCalls.length; i++) {
            directCalls[i] = superCalls[i];
        }

        directCalls[superCalls.length] = MethodCall({
            to: address(proxy),
            value: 0,
            callData: abi.encodeWithSelector(
                IRewardManager.migrateRewardPool.selector,
                address(lpToken),
                RewardPoolStorage({ rewardPool: address(rewardPool), forceClaimAfter: 0, lastClaimTimestamp: 0 })
            )
        });

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            directCalls[superCalls.length + 1 + i] = MethodCall({
                to: address(proxy),
                value: 0,
                callData: abi.encodeWithSelector(
                    IRewardManager.updateRewardToken.selector, i, address(rewardTokens[i]), 0, 0
                )
            });
        }
    }

    function getDepositData(
        address, /* user */
        uint256 /* depositAmount */
    )
        internal
        view
        virtual
        override
        returns (bytes memory depositData)
    {
        return abi.encode(depositParams);
    }

    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        view
        virtual
        override
        returns (bytes memory redeemData)
    {
        SingleSidedRedeemParams memory r = redeemParams;
        if (r.minAmounts.length == 0) {
            r.minAmounts = new uint256[](2);
        }

        return abi.encode(r);
    }
}

contract LP_Convex_OETH_WETH is DeployLPVault {
    constructor()
        DeployLPVault(
            "OETH", // token1Symbol
            "WETH", // token2Symbol
            0.915e18, // MORPHO_LLTV
            1, // primaryIndex
            address(WETH), // asset
            address(0xcc7d5785AD5755B6164e21495E07aDb0Ff11C2A8), // lpToken
            address(0), // curveGauge
            address(0xAc15ffFdCA77fc86770bEAbA20cbC1bc2D00494c), // rewardPool
            CurveInterface.StableSwapNG, // curveInterface
            100e18, // maxPoolShare
            1e16, // dyAmount
            0.95e18, // lowerLimitMultiplier
            1.05e18, // upperLimitMultiplier
            0.005e18, // feeRate
            false, // invertBase
            0x2716561755154Eef59Bc48Eb13712510b27F167F // proxy
        )
    {
        // CRV
        rewardTokens.push(0xD533a949740bb3306d119CC777fa900bA034cd52);
        // CVX
        rewardTokens.push(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

        supplyAmount = 100e18;
        borrowAmount = 90e18;
        depositAmount = 10e18;
    }

    function getDepositData(
        address, /* user */
        uint256 /* depositAmount */
    )
        internal
        view
        virtual
        override
        returns (bytes memory depositData)
    {
        TradeParams[] memory depositTrades = new TradeParams[](2);
        depositTrades[0] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 50e18,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        });

        DepositParams memory d = DepositParams({ minPoolClaim: 0, depositTrades: depositTrades });
        return abi.encode(d);
    }

    function managers() internal view override returns (IWithdrawRequestManager[] memory) {
        IWithdrawRequestManager[] memory m = new IWithdrawRequestManager[](2);
        m[0] = ADDRESS_REGISTRY.getWithdrawRequestManager(address(oETH));
        m[1] = ADDRESS_REGISTRY.getWithdrawRequestManager(address(WETH));
        return m;
    }

    function tradePermissions() internal pure override returns (bytes[] memory) {
        return new bytes[](0);
    }
}
