// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractSingleSidedLP} from "../AbstractSingleSidedLP.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils, IERC20} from "../../utils/TokenUtils.sol";
import {ETH_ADDRESS, ALT_ETH_ADDRESS, WETH, CHAIN_ID_MAINNET} from "../../utils/Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/Curve/ICurve.sol";
import "../../interfaces/Curve/IConvex.sol";
import "../../rewards/IRewardManager.sol";
import "../../withdraws/IWithdrawRequestManager.sol";

struct DeploymentParams {
    address pool;
    address poolToken;
    address gauge;
    address convexRewardPool;
}

abstract contract CurveConvex2Token is AbstractSingleSidedLP {
    using TokenUtils for IERC20;
    using SafeERC20 for IERC20;

    uint256 internal constant _NUM_TOKENS = 2;

    address internal immutable CURVE_POOL;
    IERC20 internal immutable CURVE_POOL_TOKEN;

    /// @dev Curve gauge contract used when there is no convex reward pool
    address internal immutable CURVE_GAUGE;
    /// @dev Convex booster contract used for staking BPT
    address internal immutable CONVEX_BOOSTER;
    /// @dev Convex reward pool contract used for unstaking and claiming reward tokens
    address internal immutable CONVEX_REWARD_POOL;
    uint256 internal immutable CONVEX_POOL_ID;

    uint8 internal immutable _PRIMARY_INDEX;
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;

    function NUM_TOKENS() internal pure override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function TOKENS() public view override returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        tokens[0] = IERC20(TOKEN_1);
        tokens[1] = IERC20(TOKEN_2);
        return tokens;
    }

    constructor(
        uint256 _maxPoolShare,
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager,
        DeploymentParams memory params,
        IWithdrawRequestManager[] memory managers
    ) AbstractSingleSidedLP(_maxPoolShare, _owner, _asset, _yieldToken, _feeRate, _irm, _lltv, _rewardManager, params.poolToken, 18) {
        CURVE_POOL = params.pool;
        CURVE_GAUGE = params.gauge;
        CURVE_POOL_TOKEN = IERC20(params.poolToken);

        // We interact with curve pools directly so we never pass the token addresses back
        // to the curve pools. The amounts are passed back based on indexes instead. Therefore
        // we can rewrite the token addresses from ALT Eth (0xeeee...) back to (0x0000...) which
        // is used by the vault internally to represent ETH.
        TOKEN_1 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(0));
        TOKEN_2 = _rewriteAltETH(ICurvePool(CURVE_POOL).coins(1));

        // Assets may be WETH, so we need to unwrap it in this case.
        _PRIMARY_INDEX =
            (TOKEN_1 == _asset || (TOKEN_1 == ETH_ADDRESS && _asset == address(WETH))) ? 0 :
            (TOKEN_2 == _asset || (TOKEN_2 == ETH_ADDRESS && _asset == address(WETH))) ? 1 :
            // Otherwise the primary index is not set and we will not be able to enter or exit
            // single sided.
            type(uint8).max;

        // If the convex reward pool is set then get the booster and pool id, if not then
        // we will stake on the curve gauge directly.
        CONVEX_REWARD_POOL = params.convexRewardPool;
        address convexBooster;
        uint256 poolId;
        if (block.chainid == CHAIN_ID_MAINNET && CONVEX_REWARD_POOL != address(0)) {
            convexBooster = IConvexRewardPool(CONVEX_REWARD_POOL).operator();
            poolId = IConvexRewardPool(CONVEX_REWARD_POOL).pid();
        }

        CONVEX_POOL_ID = poolId;
        CONVEX_BOOSTER = convexBooster;

        require(managers.length == _NUM_TOKENS);
        for (uint256 i = 0; i < _NUM_TOKENS; i++) {
            withdrawRequestManagers.push(managers[i]);
        }
    }

    function _rewriteAltETH(address token) private pure returns (address) {
        return token == address(ALT_ETH_ADDRESS) ? ETH_ADDRESS : address(token);
    }

    function _initialApproveTokens() internal override virtual {
        // If either token is ETH_ADDRESS the check approve will short circuit
        IERC20(TOKEN_1).checkApprove(address(CURVE_POOL), type(uint256).max);
        IERC20(TOKEN_2).checkApprove(address(CURVE_POOL), type(uint256).max);
        if (CONVEX_BOOSTER != address(0)) {
            CURVE_POOL_TOKEN.checkApprove(address(CONVEX_BOOSTER), type(uint256).max);
        } else {
            CURVE_POOL_TOKEN.checkApprove(address(CURVE_GAUGE), type(uint256).max);
        }
    }

    function _joinPoolAndStake(
        uint256[] memory _amounts, uint256 minPoolClaim
    ) internal override {
        // Although Curve uses ALT_ETH to represent native ETH, it is rewritten in the Curve2TokenPoolMixin
        // to the Deployments.ETH_ADDRESS which we use internally.
        uint256 msgValue;
        if (TOKEN_1 == ETH_ADDRESS) {
            msgValue = _amounts[0];
        } else if (TOKEN_2 == ETH_ADDRESS) {
            msgValue = _amounts[1];
        }
        if (msgValue > 0) WETH.withdraw(msgValue);

        uint256 lpTokens = _enterPool(_amounts, minPoolClaim, msgValue);

        _stakeLpTokens(lpTokens);
    }

    function _unstakeAndExitPool(
        uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided
    ) internal override returns (uint256[] memory exitBalances) {
        _unstakeLpTokens(poolClaim);

        exitBalances = _exitPool(poolClaim, _minAmounts, isSingleSided);

        if (asset == address(WETH)) {
            if (TOKEN_1 == ETH_ADDRESS) {
                WETH.deposit{value: exitBalances[0]}();
            } else if (TOKEN_2 == ETH_ADDRESS) {
                WETH.deposit{value: exitBalances[1]}();
            }
        }
    }

    function _enterPool(uint256[] memory _amounts, uint256 minPoolClaim, uint256 msgValue) internal virtual returns (uint256 lpTokens);
    function _exitPool(uint256 poolClaim, uint256[] memory _minAmounts, bool isSingleSided) internal virtual returns (uint256[] memory exitBalances);

    function _stakeLpTokens(uint256 lpTokens) internal {
        if (CONVEX_BOOSTER != address(0)) {
            bool success = IConvexBooster(CONVEX_BOOSTER).deposit(CONVEX_POOL_ID, lpTokens, true);
            require(success);
        } else {
            ICurveGauge(CURVE_GAUGE).deposit(lpTokens);
        }
    }


    function _unstakeLpTokens(uint256 poolClaim) internal {
        if (CONVEX_REWARD_POOL != address(0)) {
            bool success = IConvexRewardPool(CONVEX_REWARD_POOL).withdrawAndUnwrap(poolClaim, false);
            require(success);
        } else {
            ICurveGauge(CURVE_GAUGE).withdraw(poolClaim);
        }
    }

    function _transferYieldTokenToOwner(uint256 yieldTokens) internal override {
        _unstakeLpTokens(yieldTokens);
        CURVE_POOL_TOKEN.safeTransfer(owner, yieldTokens);
    }

}