// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import {ConvexRewardManager} from "../src/rewards/ConvexRewardManager.sol";
import "../src/single-sided-lp/CurveConvex2Token.sol";
import "../src/single-sided-lp/AbstractSingleSidedLP.sol";
import "../src/oracles/Curve2TokenOracle.sol";

contract TestSingleSidedLPStrategy is TestMorphoYieldStrategy {
    ERC20 lpToken;
    address rewardPool;
    IRewardManager rm;

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
    

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        lpToken = ERC20(0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85);
        rewardPool = 0x83644fa70538e5251D125205186B14A76cA63606;

        y = new CurveConvex2Token(
            100e18,
            owner,
            address(USDC),
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
                curveInterface: CurveInterface.StableSwapNG,
                convexRewardPool: address(rewardPool)
            })
        );

        w = ERC20(rewardPool);

        Curve2TokenOracle oracle = new Curve2TokenOracle(
            0.95e18,
            1.05e18,
            address(lpToken),
            0,
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

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
    
}