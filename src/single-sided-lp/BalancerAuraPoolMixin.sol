// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractSingleSidedLP} from "./AbstractSingleSidedLP.sol";
import {ETH_ADDRESS} from "../Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBalancerPool} from "../interfaces/Balancer/IBalancerPool.sol";
import {IAuraRewardPool, IAuraBooster} from "../interfaces/Balancer/IAura.sol";
import"../interfaces/Balancer/IBalancerVault.sol";

/** Base class for all Balancer LP strategies */
abstract contract BalancerAuraPoolMixin is AbstractSingleSidedLP {
    using SafeERC20 for IERC20;

    uint256 internal constant BALANCER_PRECISION = 1e18;

    bytes32 internal immutable BALANCER_POOL_ID;

    uint256 internal immutable _NUM_TOKENS;
    uint256 internal immutable _PRIMARY_INDEX;
    uint256 internal immutable BPT_INDEX;

    /// @notice this implementation currently supports up to 5 tokens
    address internal immutable TOKEN_1;
    address internal immutable TOKEN_2;
    address internal immutable TOKEN_3;
    address internal immutable TOKEN_4;
    address internal immutable TOKEN_5;

    uint8 internal immutable DECIMALS_1;
    uint8 internal immutable DECIMALS_2;
    uint8 internal immutable DECIMALS_3;
    uint8 internal immutable DECIMALS_4;
    uint8 internal immutable DECIMALS_5;

    function NUM_TOKENS() internal view override returns (uint256) { return _NUM_TOKENS; }
    function PRIMARY_INDEX() internal view override returns (uint256) { return _PRIMARY_INDEX; }
    function POOL_PRECISION() internal pure override returns (uint256) { return BALANCER_PRECISION; }
    function TOKENS() public view virtual override returns (IERC20[] memory, uint8[] memory) {
        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        uint8[] memory decimals = new uint8[](_NUM_TOKENS);

        if (_NUM_TOKENS > 0) (tokens[0], decimals[0]) = (IERC20(TOKEN_1), DECIMALS_1);
        if (_NUM_TOKENS > 1) (tokens[1], decimals[1]) = (IERC20(TOKEN_2), DECIMALS_2);
        if (_NUM_TOKENS > 2) (tokens[2], decimals[2]) = (IERC20(TOKEN_3), DECIMALS_3);
        if (_NUM_TOKENS > 3) (tokens[3], decimals[3]) = (IERC20(TOKEN_4), DECIMALS_4);
        if (_NUM_TOKENS > 4) (tokens[4], decimals[4]) = (IERC20(TOKEN_5), DECIMALS_5);

        return (tokens, decimals);
    }

    /// @notice Used to get type compatibility with the Balancer join and exit methods.
    function ASSETS() internal virtual view returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](_NUM_TOKENS);
        if (_NUM_TOKENS > 0) assets[0] = IAsset(TOKEN_1);
        if (_NUM_TOKENS > 1) assets[1] = IAsset(TOKEN_2);
        if (_NUM_TOKENS > 2) assets[2] = IAsset(TOKEN_3);
        if (_NUM_TOKENS > 3) assets[3] = IAsset(TOKEN_4);
        if (_NUM_TOKENS > 4) assets[4] = IAsset(TOKEN_5);
        return assets;
    }

    /// @notice Aura booster contract used for staking BPT
    IAuraBooster internal immutable AURA_BOOSTER;
    /// @notice Aura reward pool contract used for unstaking and claiming reward tokens
    IAuraRewardPool internal immutable AURA_REWARD_POOL;
    /// @notice Aura pool ID used for staking
    uint256 internal immutable AURA_POOL_ID;
    address immutable WHITELISTED_REWARD;

    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        bytes32 balancerPoolId,
        address rewardPool,
        address whitelistedReward
    ) AbstractSingleSidedLP(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {
        BALANCER_POOL_ID = balancerPoolId;
        (address pool, /* */) = BALANCER_VAULT.getPool(balancerPoolId);
        require(_yieldToken == pool, "BalancerPoolMixin: yield token does not match pool token");

        // Fetch all the token addresses in the pool
        (
            address[] memory tokens,
            /* uint256[] memory balances */,
            /* uint256 lastChangeBlock */
        ) = BALANCER_VAULT.getPoolTokens(balancerPoolId);

        require(tokens.length <= MAX_TOKENS);
        _NUM_TOKENS = uint8(tokens.length);

        TOKEN_1 = _NUM_TOKENS > 0 ? tokens[0] : address(0);
        TOKEN_2 = _NUM_TOKENS > 1 ? tokens[1] : address(0);
        TOKEN_3 = _NUM_TOKENS > 2 ? tokens[2] : address(0);
        TOKEN_4 = _NUM_TOKENS > 3 ? tokens[3] : address(0);
        TOKEN_5 = _NUM_TOKENS > 4 ? tokens[4] : address(0);

        DECIMALS_1 = _NUM_TOKENS > 0 ? ERC20(TOKEN_1).decimals() : 0;
        DECIMALS_2 = _NUM_TOKENS > 1 ? ERC20(TOKEN_2).decimals() : 0;
        DECIMALS_3 = _NUM_TOKENS > 2 ? ERC20(TOKEN_3).decimals() : 0;
        DECIMALS_4 = _NUM_TOKENS > 3 ? ERC20(TOKEN_4).decimals() : 0;
        DECIMALS_5 = _NUM_TOKENS > 4 ? ERC20(TOKEN_5).decimals() : 0;

        uint8 primaryIndex = NOT_FOUND;
        uint8 bptIndex = NOT_FOUND;
        for (uint8 i; i < tokens.length; i++) {
            if (tokens[i] == _asset) primaryIndex = i; 
            else if (tokens[i] == address(yieldToken)) bptIndex = i;
        }

        // Primary Index must exist for all balancer pools, but BPT_INDEX
        // will only exist for ComposableStablePools
        require(primaryIndex != NOT_FOUND);

        _PRIMARY_INDEX = primaryIndex;
        BPT_INDEX = bptIndex;

        AURA_REWARD_POOL = IAuraRewardPool(rewardPool);

        if (address(AURA_REWARD_POOL) != address(0)) {
            // Skip this if there is no reward pool
            AURA_BOOSTER = IAuraBooster(AURA_REWARD_POOL.operator());
            AURA_POOL_ID = AURA_REWARD_POOL.pid();
        }
        // Allows one of the pool tokens to be whitelisted as a reward token to be re-entered
        // back into the pool to increase LP shares.
        WHITELISTED_REWARD = whitelistedReward;
    }

    // Checks if a token in the pool is a BPT. Used in cases where a BPT is one of the
    // tokens within the pool (not the self BPT in the case of the Composable Stable Pool).
    function _isBPT(address token) internal view returns (bool) {
        // Need to check for zero address since this breaks the try / catch
        if (token == address(0)) return false;

        try IBalancerPool(token).getPoolId() returns (bytes32 /* poolId */) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev Prevent liquidation if we are in a re-entrancy context
    function _canLiquidate(address /* liquidateAccount */) internal override returns (uint256) {
        IBalancerVault.UserBalanceOp[] memory noop = new IBalancerVault.UserBalanceOp[](0);
        BALANCER_VAULT.manageUserBalance(noop);
        return 0;
    }

    /// @notice Joins a balancer pool using the supplied amounts of tokens
    function _joinPoolExactTokensIn(
        uint256[] memory amounts,
        bytes memory customData
    ) internal returns (uint256 bptAmount) {
        uint256 msgValue;
        IAsset[] memory assets = ASSETS();
        require(assets.length == amounts.length);
        for (uint256 i; i < assets.length; i++) {
            // Sets the msgValue of transferring ETH
            if (address(assets[i]) == ETH_ADDRESS) {
                msgValue = amounts[i];
                break;
            }
        }

        bptAmount = IERC20(yieldToken).balanceOf(address(this));
        BALANCER_VAULT.joinPool{value: msgValue}(
            BALANCER_POOL_ID,
            address(this), // sender
            address(this), //  Vault will receive the pool tokens
            IBalancerVault.JoinPoolRequest(
                ASSETS(),
                amounts,
                customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amount of BPT minted
        bptAmount = IERC20(yieldToken).balanceOf(address(this)) - bptAmount;
    }

    /// @notice Exits a balancer pool using exact BPT in
    function _exitPoolExactBPTIn(
        uint256[] memory amounts,
        bytes memory customData
    ) internal returns (uint256[] memory exitBalances) {
        // For composable pools, the asset array includes the BPT token (i.e. poolToken). The balance
        // will decrease in an exit while all of the other balances increase, causing a subtraction
        // underflow in the final loop. For that reason, exit balances are not calculated of the poolToken
        // is included in the array of assets.
        exitBalances = new uint256[](_NUM_TOKENS);
        IAsset[] memory assets = ASSETS();

        for (uint256 i; i < _NUM_TOKENS; i++) {
            if (address(assets[i]) == address(yieldToken)) continue;
            exitBalances[i] = IERC20(address(assets[i])).balanceOf(address(this));
        }

        BALANCER_VAULT.exitPool(
            BALANCER_POOL_ID,
            address(this), // sender
            payable(address(this)), // Vault will receive the underlying assets
            IBalancerVault.ExitPoolRequest(
                assets,
                amounts,
                customData,
                false // Don't use internal balances
            )
        );

        // Calculate the amounts of underlying tokens after the exit
        for (uint256 i; i < _NUM_TOKENS; i++) {
            if (address(assets[i]) == address(yieldToken)) continue;
            uint256 balanceAfter = IERC20(address(assets[i])).balanceOf(address(this));
            exitBalances[i] = balanceAfter - exitBalances[i];
        }
    }

    function _isInvalidRewardToken(address token) internal override view returns (bool) {
        // ETH is also at address(0) but that is never given out as a reward token
        if (WHITELISTED_REWARD != address(0) && token == WHITELISTED_REWARD) return false;

        return (
            token == TOKEN_1 ||
            token == TOKEN_2 ||
            token == TOKEN_3 ||
            token == TOKEN_4 ||
            token == TOKEN_5 ||
            token == address(yieldToken) ||
            token == address(AURA_BOOSTER) ||
            token == address(AURA_REWARD_POOL) ||
            // token == address(WETH) ||
            token == address(ETH_ADDRESS)
        );
    }

    /// @notice Called once on initialization to set token approvals
    function _initialApproveTokens() internal override {
        (IERC20[] memory tokens, /* */) = TOKENS();
        for (uint256 i; i < tokens.length; i++) {
            tokens[i].forceApprove(address(BALANCER_VAULT), type(uint256).max);
        }

        // Approve Aura to transfer pool tokens for staking
        if (address(AURA_BOOSTER) != address(0)) {
            IERC20(yieldToken).forceApprove(address(AURA_BOOSTER), type(uint256).max);
        }
    }

    /// @notice Claim reward tokens
    // function _rewardPoolStorage() internal view override returns (RewardPoolStorage memory r) {
    //     r.poolType = address(AURA_REWARD_POOL) == address(0) ? RewardPoolType._UNUSED : RewardPoolType.AURA;
    //     r.rewardPool = address(AURA_REWARD_POOL);
    // }
}