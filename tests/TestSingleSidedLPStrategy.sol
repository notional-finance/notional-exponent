// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";
import "../src/single-sided-lp/curve/CurveConvex2Token.sol";
// import "../src/single-sided-lp/curve/CurveConvexStableSwapNG.sol";
// import "../src/single-sided-lp/curve/CurveConvexV1.sol";
// import "../src/single-sided-lp/curve/CurveConvexV2.sol";
import "../src/single-sided-lp/AbstractSingleSidedLP.sol";
import "../src/oracles/Curve2TokenOracle.sol";
import "./TestWithdrawRequest.sol";

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
    // Used to set the price oracle to USD for the primary token
    address usdOracleToken;
    IWithdrawRequestManager[] managers;

    DepositParams depositParams;
    RedeemParams redeemParams;
    WithdrawParams withdrawParams;

    TradeParams[] tradeBeforeDepositParams;
    TradeParams[] tradeBeforeRedeemParams;

    TestWithdrawRequest[] withdrawRequests;

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal virtual override returns (bytes memory depositData) {
        return abi.encode(depositParams);
    }

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal virtual override returns (bytes memory redeemData) {
        RedeemParams memory r = redeemParams;
        if (r.minAmounts.length == 0) {
            r.minAmounts = new uint256[](2);
        }

        return abi.encode(r);
    }

    function finalizeWithdrawRequest(address user) internal {
        for (uint256 i; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            (WithdrawRequest memory w, /* */) = managers[i].getWithdrawRequest(address(y), user);
            if (address(withdrawRequests[i]) == address(0)) continue;
            withdrawRequests[i].finalizeWithdrawRequest(w.requestId);
        }
    }

    function setMarketVariables() internal virtual;

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        invertBase = false;
        // Set default parameters
        managers.push(IWithdrawRequestManager(address(0)));
        managers.push(IWithdrawRequestManager(address(0)));
        withdrawRequests.push(TestWithdrawRequest(address(0)));
        withdrawRequests.push(TestWithdrawRequest(address(0)));
        tradeBeforeDepositParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeDepositParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeRedeemParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeRedeemParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));

        setMarketVariables();
        if (usdOracleToken == address(0)) usdOracleToken = address(asset);

        y = new CurveConvex2Token(
            maxPoolShare,
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
                convexRewardPool: address(rewardPool),
                curveInterface: curveInterface
            })
        );

        feeToken = lpToken;
        (baseToUSDOracle, /* */) = TRADING_MODULE.priceOracles(usdOracleToken);
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
    }

    function postDeploySetup() internal override virtual {
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
        vm.skip(tradeBeforeDepositParams[stakeTokenIndex].dexId == 0);

        depositParams.depositTrades = tradeBeforeDepositParams;
        depositParams.depositTrades[stakeTokenIndex].tradeAmount = (defaultDeposit + defaultBorrow) / 2;

        test_enterPosition();
        // TODO: how do we know that this was done via trading?

        delete depositParams;
    }

    function test_exitPosition_tradeBeforeRedeem(bool isFullExit) public {
        vm.skip(tradeBeforeRedeemParams[stakeTokenIndex].dexId == 0);

        redeemParams.minAmounts = new uint256[](2);
        redeemParams.redemptionTrades = tradeBeforeRedeemParams;

        if (isFullExit) {
            test_exitPosition_fullExit();
        } else {
            test_exitPosition_partialExit();
        }
        // TODO: how do we know that this was done via trading?

        delete redeemParams;
    }

    function test_exitPosition_withdrawBeforeRedeem() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        withdrawParams.minAmounts = new uint256[](2);
        withdrawParams.withdrawData = new bytes[](2);

        vm.startPrank(msg.sender);
        uint256[] memory requestIds = AbstractSingleSidedLP(payable(address(y))).initiateWithdraw(abi.encode(withdrawParams));
        assertEq(requestIds.length, 2);

        vm.warp(block.timestamp + 6 minutes);
        uint256 shares = y.balanceOfShares(msg.sender);

        redeemParams.minAmounts = new uint256[](2);
        redeemParams.redemptionTrades = tradeBeforeRedeemParams;
        bytes memory redeemData = abi.encode(redeemParams);

        vm.expectRevert("Withdraw request not finalized");
        y.exitPosition(
            msg.sender,
            msg.sender,
            shares,
            type(uint256).max,
            redeemData
        );
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.startPrank(msg.sender);
        y.exitPosition(
            msg.sender,
            msg.sender,
            shares,
            type(uint256).max,
            redeemData
        );
        vm.stopPrank();

        delete redeemParams;
    }

    function test_cannotEnterAboveMaxPoolShare() public {
        vm.startPrank(owner);
        MORPHO.withdraw(y.marketParams(), 1_000_000 * 10 ** asset.decimals(), 0, owner, owner);
        vm.stopPrank();

        y = new CurveConvex2Token(
            0.001e18, // 0.1% max pool share
            address(asset),
            address(w),
            0.0010e18, // 0.1%
            IRM,
            0.915e18,
            address(new ConvexRewardManager()),
            DeploymentParams({
                pool: address(lpToken),
                poolToken: address(lpToken),
                gauge: curveGauge,
                convexRewardPool: address(rewardPool),
                curveInterface: curveInterface
            })
        );
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(y), abi.encodeWithSelector(Initializable.initialize.selector,
            abi.encode("name", "symbol")),
            address(0)
        );
        y = IYieldStrategy(address(proxy));

        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            vm.prank(owner);
            managers[i].setApprovedVault(address(y), true);
        }

        vm.startPrank(owner);
        MORPHO.supply(y.marketParams(), 1_000_000 * 10 ** asset.decimals(), 0, owner, "");
        vm.stopPrank();

        vm.startPrank(msg.sender);
        if (!MORPHO.isAuthorized(msg.sender, address(y))) MORPHO.setAuthorization(address(y), true);
        asset.approve(address(y), defaultDeposit);
        bytes memory depositData = getDepositData(msg.sender, defaultDeposit + defaultBorrow);
        vm.expectPartialRevert(AbstractSingleSidedLP.PoolShareTooHigh.selector);
        y.enterPosition(msg.sender, defaultDeposit, defaultBorrow, depositData);
        vm.stopPrank();
    }


    // TODO: test withdraw valuation
    // TODO: test force withdraws
    // TODO: test re-entrancy context
    // TODO: test split withdraw
}