// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";
import "../src/single-sided-lp/CurveConvex2Token.sol";
import "../src/single-sided-lp/AbstractSingleSidedLP.sol";
import "../src/oracles/Curve2TokenOracle.sol";

abstract contract TestSingleSidedLPStrategy is TestMorphoYieldStrategy {
    ERC20 lpToken;
    address rewardPool;
    IRewardManager rm;
    CurveInterface curveInterface;
    uint8 primaryIndex;
    uint256 maxPoolShare;
    AggregatorV2V3Interface baseToUSDOracle;
    bool invertBase;
    uint256 dyAmount;
    address curveGauge;
    uint8 stakeTokenIndex;
    IWithdrawRequestManager[] managers;

    DepositParams depositParams;
    RedeemParams redeemParams;
    TradeParams tradeBeforeDepositParams;

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal view virtual override returns (bytes memory depositData) {
        return abi.encode(depositParams);
    }

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal view virtual override returns (bytes memory redeemData) {
        return abi.encode(redeemParams);
    }

    function setMarketVariables() internal virtual;

    function postDeployHook() internal virtual {}

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        invertBase = false;
        // Set the managers to zero by default
        managers.push(IWithdrawRequestManager(address(0)));
        managers.push(IWithdrawRequestManager(address(0)));

        setMarketVariables();

        y = new CurveConvex2Token(
            maxPoolShare,
            owner,
            address(asset),
            address(w),
            0.0010e18, // 0.1%
            IRM,
            0.915e18,
            address(rmImpl),
            DeploymentParams({
                pool: address(lpToken),
                poolToken: address(lpToken),
                gauge: curveGauge,
                curveInterface: curveInterface,
                convexRewardPool: address(rewardPool)
            }),
            managers
        );

        feeToken = lpToken;

        (baseToUSDOracle, /* */) = TRADING_MODULE.priceOracles(address(asset));
        Curve2TokenOracle oracle = new Curve2TokenOracle(
            0.95e18,
            1.05e18,
            address(lpToken),
            primaryIndex,
            "Curve 2 Token Oracle",
            address(0),
            baseToUSDOracle,
            invertBase,
            dyAmount
        );

        o = new MockOracle(oracle.latestAnswer());

        rm = IRewardManager(address(y));
        if (address(rewardPool) != address(0)) {
            vm.startPrank(owner);
            rm.migrateRewardPool(address(lpToken), RewardPoolStorage({
                rewardPool: rewardPool,
                forceClaimAfter: 0,
                lastClaimTimestamp: 0
            }));
            // List CRV reward token
            rm.updateRewardToken(0, address(0xD533a949740bb3306d119CC777fa900bA034cd52), 0, 0);
            vm.stopPrank();
        }

        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            vm.prank(owner);
            managers[i].setApprovedVault(address(y), true);
        }

        postDeployHook();
    }

    function test_claimRewards() public {
        // TODO: test claims on the curve gauge directly
        vm.skip(rewardPool == address(0));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.warp(block.timestamp + 1 days);

        rm.claimAccountRewards(msg.sender);
        (VaultRewardState[] memory rewardStates, /* */) = rm.getRewardSettings();
        uint256[] memory rewardsBefore = new uint256[](rewardStates.length);
        for (uint256 i = 0; i < rewardStates.length; i++) {
            rewardsBefore[i] = ERC20(rewardStates[i].rewardToken).balanceOf(msg.sender);
            assertGt(rewardsBefore[i], 0);
        }

        rm.claimAccountRewards(msg.sender);
        for (uint256 i = 0; i < rewardStates.length; i++) {
            assertEq(ERC20(rewardStates[i].rewardToken).balanceOf(msg.sender), rewardsBefore[i]);
        }
    }

    function test_enterPosition_stakeBeforeDeposit() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));

        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));

        depositParams.depositTrades[stakeTokenIndex] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: (defaultDeposit + defaultBorrow) / 2,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(address(managers[stakeTokenIndex]), bytes(""))
        });

        test_enterPosition();
        // TODO: how do we know that this was done via staking?

        delete depositParams;
    }

    function test_enterPosition_tradeBeforeDeposit() public {
        vm.skip(tradeBeforeDepositParams.dexId == 0);

        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));

        depositParams.depositTrades[stakeTokenIndex] = tradeBeforeDepositParams;
        depositParams.depositTrades[stakeTokenIndex].tradeAmount = (defaultDeposit + defaultBorrow) / 2;

        test_enterPosition();
        // TODO: how do we know that this was done via trading?

        delete depositParams;
    }
        
    // TODO: test withdraw request before redeem
    // TODO: test trading on redeem
    // TODO: test emergency exit

    // TODO: test max pool share
    // TODO: test re-entrancy context
}