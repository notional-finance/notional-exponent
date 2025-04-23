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

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal view virtual override returns (bytes memory depositData) {
        DepositParams memory params = DepositParams({
            minPoolClaim: 0,
            depositTrades: new TradeParams[](0)
        });
        return abi.encode(params);
    }

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal view virtual override returns (bytes memory redeemData) {
        RedeemParams memory params = RedeemParams({
            minAmounts: new uint256[](2),
            redemptionTrades: new TradeParams[](0)
        });
        return abi.encode(params);
    }

    function setMarketVariables() internal virtual;

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        setMarketVariables();

        y = new CurveConvex2Token(
            maxPoolShare,
            owner,
            address(asset),
            address(rewardPool),
            0.0010e18, // 0.1%
            IRM,
            0.915e18,
            address(rmImpl),
            DeploymentParams({
                pool: address(lpToken),
                poolToken: address(lpToken),
                // TODO: can we get rid of this?
                gauge: address(0),
                curveInterface: curveInterface,
                convexRewardPool: address(rewardPool)
            })
        );

        w = ERC20(rewardPool);
        feeToken = lpToken;

        Curve2TokenOracle oracle = new Curve2TokenOracle(
            0.95e18,
            1.05e18,
            address(lpToken),
            primaryIndex,
            "Curve 2 Token Oracle",
            address(0)
        );

        o = new MockOracle(oracle.latestAnswer());

        rm = IRewardManager(address(y));
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

    // TODO: test claim rewards
    // TODO: test without convex pool
    // TODO: test trading on other venues
    // TODO: test staking before deposit
    // TODO: test withdraw request before redeem
    // TODO: test trading on redeem
    // TODO: test emergency exit
    
}