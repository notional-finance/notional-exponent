// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "./IRewardManager.sol";
import "../Constants.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {IEIP20NonStandard} from "../interfaces/IEIP20NonStandard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract AbstractRewardManager is IRewardManager, ReentrancyGuard {
    using TypeConvert for uint256;
    using TokenUtils for IERC20;

    // TODO: move these into an offset storage contract
    RewardPoolStorage private s_rewardPoolState;
    VaultRewardState[] private s_vaultRewardState;
    // Reward Token -> Account -> Reward Debt
    mapping(address => mapping(address => uint256)) private s_accountRewardDebt;
    address private s_rewardManager;

    modifier onlyRewardManager() {
        require(msg.sender == s_rewardManager, "Only the reward manager can call this function");
        _;
    }

    /// @inheritdoc IRewardManager
    function getRewardSettings() external view override returns (
        VaultRewardState[] memory rewardStates,
        RewardPoolStorage memory rewardPool
    ) {
        rewardStates = s_vaultRewardState;
        rewardPool = s_rewardPoolState;
    }

    /// @inheritdoc IRewardManager
    function getRewardDebt(
        address rewardToken,
        address account
    ) external view override returns (uint256 rewardDebt) {
        return s_accountRewardDebt[rewardToken][account];
    }

    /// @inheritdoc IRewardManager
    function getAccountRewardClaim(
        address account,
        uint256 blockTime
    ) external view override returns (uint256[] memory rewards) {
        VaultRewardState[] memory rewardStates = s_vaultRewardState;
        rewards = new uint256[](rewardStates.length);

        uint256 totalVaultSharesBefore = IERC20(address(this)).totalSupply();
        uint256 vaultSharesBefore = 0;
        // uint256 vaultSharesBefore = IAbstractVault(address(this)).getAccountVaultShare(account);

        for (uint256 i; i < rewards.length; i++) {
            uint256 rewardsPerVaultShare = _getAccumulatedRewardViaEmissionRate(
                rewardStates[i], totalVaultSharesBefore, blockTime
            );
            rewards[i] = _getRewardsToClaim(
                rewardStates[i].rewardToken, account, vaultSharesBefore, rewardsPerVaultShare
            );
        }
    }

    /// @inheritdoc IRewardManager
    function updateRewardToken(
        uint256 index,
        address rewardToken,
        uint128 emissionRatePerYear,
        uint32 endTime
    ) external override onlyRewardManager {
        uint256 totalVaultSharesBefore = IERC20(address(this)).totalSupply();
        VaultRewardState memory state = s_vaultRewardState[index];

        if (index < s_vaultRewardState.length) {
            // Safety check to ensure that the correct token is specified, we can never change the
            // token address once set.
            require(state.rewardToken == rewardToken);
            // Modifies the emission rate on an existing token, direct claims of the token will
            // not be affected by the emission rate.
            // First accumulate under the old regime up to the current time. Even if the previous
            // emissionRatePerYear is zero this will still set the lastAccumulatedTime to the current
            // blockTime.
            _accumulateSecondaryRewardViaEmissionRate(index, state, totalVaultSharesBefore);

            // Save the new emission rates
            state.emissionRatePerYear = emissionRatePerYear;
            if (state.emissionRatePerYear == 0) {
                state.endTime = 0;
            } else {
                require(block.timestamp < endTime);
                state.endTime = endTime;
            }
            s_vaultRewardState[index] = state;
        } else if (index == s_vaultRewardState.length) {
            // This sets a new reward token, ensure that the current slot is empty
            require(state.rewardToken == address(0));
            s_vaultRewardState.push(state);
            state.rewardToken = rewardToken;

            // If no emission rate is set then governance is just adding a token that can be claimed
            // via the LP tokens without an emission rate. These settings will be left empty and the
            // subsequent _claimVaultRewards method will set the initial accumulatedRewardPerVaultShare.
            if (0 < emissionRatePerYear) {
                state.emissionRatePerYear = emissionRatePerYear;
                require(block.timestamp < endTime);
                state.endTime = endTime;
                state.lastAccumulatedTime = uint32(block.timestamp);
            }
            s_vaultRewardState[index] = state;
        } else {
            // Can only append or modify existing tokens
            revert();
        }

        // Claim all vault rewards up to the current time
        _claimVaultRewards(totalVaultSharesBefore, s_vaultRewardState);
        emit VaultRewardUpdate(rewardToken, emissionRatePerYear, endTime);
    }

    function migrateRewardPool(address poolToken, RewardPoolStorage memory newRewardPool) external override onlyRewardManager nonReentrant {
        // Claim all rewards from the previous reward pool before withdrawing
        uint256 totalVaultSharesBefore = IERC20(address(this)).totalSupply();
        _claimVaultRewards(totalVaultSharesBefore, s_vaultRewardState);
        RewardPoolStorage memory oldRewardPool = s_rewardPoolState;

        if (oldRewardPool.rewardPool != address(0)) {
            _withdrawFromPreviousRewardPool(poolToken, oldRewardPool);

            // Clear approvals on the old pool.
            IERC20(poolToken).checkRevoke(address(oldRewardPool.rewardPool));
        }

        uint256 poolTokens = IERC20(poolToken).balanceOf(address(this));
        _depositIntoNewRewardPool(poolToken, poolTokens, newRewardPool);

        // Set the last claim timestamp to the current block timestamp since we re claiming all the rewards
        // earlier in this method.
        newRewardPool.lastClaimTimestamp = uint32(block.timestamp);
        s_rewardPoolState = newRewardPool;
    }

    /// @notice Claims all the rewards for the entire vault and updates the accumulators. Does not
    /// update emission rewarders since those are automatically updated on every account claim.
    function claimRewardTokens() external nonReentrant {
        // This method is not executed from inside enter or exit vault positions, so this total
        // vault shares value is valid.
        uint256 totalVaultSharesBefore = IERC20(address(this)).totalSupply();
        _claimVaultRewards(totalVaultSharesBefore, s_vaultRewardState);
    }

    /// @notice Called by the vault inside a delegatecall to update the account reward claims.
    function updateAccountRewards(
        address account,
        uint256 vaultSharesBefore,
        uint256 vaultShares,
        uint256 totalVaultSharesBefore,
        bool isMint
    ) external {
        _claimAccountRewards(
            account,
            totalVaultSharesBefore,
            vaultSharesBefore,
            isMint ? vaultSharesBefore + vaultShares : vaultSharesBefore - vaultShares
        );
    }

    // /// @notice Called to ensure that rewarders are properly updated during deleverage, when
    // /// vault shares are transferred from an account to the liquidator.
    // function deleverageAccount(
    //     address account,
    //     address vault,
    //     address liquidator,
    //     uint16 currencyIndex,
    //     int256 depositUnderlyingInternal
    // ) external payable returns (uint256 vaultSharesFromLiquidation, int256 depositAmountPrimeCash) {
    //     // Record all vault share values before
    //     uint256 totalVaultSharesBefore = VaultStorage.getStrategyVaultState().totalVaultSharesGlobal;
    //     uint256 accountVaultSharesBefore = _getVaultSharesBefore(account);
    //     uint256 liquidatorVaultSharesBefore = _getVaultSharesBefore(liquidator);

    //     // Forward the liquidation call to Notional
    //     (
    //         vaultSharesFromLiquidation,
    //         depositAmountPrimeCash
    //     ) = Deployments.NOTIONAL.deleverageAccount{value: msg.value}(
    //         account, vault, liquidator, currencyIndex, depositUnderlyingInternal
    //     );

    //     _claimAccountRewards(
    //         account, totalVaultSharesBefore, accountVaultSharesBefore,
    //         accountVaultSharesBefore - vaultSharesFromLiquidation
    //     );
    //     // The second claim will be skipped as a gas optimization because the last claim
    //     // timestamp will equal the current timestamp.
    //     _claimAccountRewards(
    //         liquidator, totalVaultSharesBefore, liquidatorVaultSharesBefore,
    //         liquidatorVaultSharesBefore + vaultSharesFromLiquidation
    //     );
    // }

    /// @notice Executes a claim on account rewards
    function _claimAccountRewards(
        address account,
        uint256 totalVaultSharesBefore,
        uint256 vaultSharesBefore,
        uint256 vaultSharesAfter
    ) internal {
        VaultRewardState[] memory state = s_vaultRewardState;
        _claimVaultRewards(totalVaultSharesBefore, state);

        for (uint256 i; i < state.length; i++) {
            if (0 < state[i].emissionRatePerYear) {
                // Accumulate any rewards with an emission rate here
                _accumulateSecondaryRewardViaEmissionRate(i, state[i], totalVaultSharesBefore);
            }

            _claimRewardToken(
                state[i].rewardToken,
                account,
                vaultSharesBefore,
                vaultSharesAfter,
                state[i].accumulatedRewardPerVaultShare
            );
        }
    }

    /// @notice Executes a claim against the given reward pool type and updates internal
    /// rewarder accumulators.
    function _claimVaultRewards(
        uint256 totalVaultSharesBefore,
        VaultRewardState[] memory state
    ) internal {
        uint256 lastClaimTimestamp = s_rewardPoolState.lastClaimTimestamp;
        uint256 forceClaimAfter = s_rewardPoolState.forceClaimAfter;
        if (block.timestamp < lastClaimTimestamp + forceClaimAfter) return;

        uint256[] memory balancesBefore = new uint256[](state.length);
        // Run a generic call against the reward pool and then do a balance
        // before and after check.
        for (uint256 i; i < state.length; i++) {
            // Presumes that ETH will never be given out as a reward token.
            balancesBefore[i] = IERC20(state[i].rewardToken).balanceOf(address(this));
        }

        _executeClaim();

        s_rewardPoolState.lastClaimTimestamp = uint32(block.timestamp);

        // This only accumulates rewards claimed, it does not accumulate any secondary emissions
        // that are streamed to vault users.
        for (uint256 i; i < state.length; i++) {
            uint256 balanceAfter = IERC20(state[i].rewardToken).balanceOf(address(this));
            _accumulateSecondaryRewardViaClaim(
                i,
                state[i],
                // balanceAfter should never be less than balanceBefore
                balanceAfter - balancesBefore[i],
                totalVaultSharesBefore
            );
        }
    }


    /** Reward Claim Methods **/
    function _getRewardsToClaim(
        address rewardToken,
        address account,
        uint256 vaultSharesBefore,
        uint256 rewardsPerVaultShare
    ) internal view returns (uint256 rewardToClaim) {
        // Vault shares are always in 8 decimal precision
        rewardToClaim = (
            (vaultSharesBefore * rewardsPerVaultShare) / VAULT_SHARE_PRECISION
        ) - s_accountRewardDebt[rewardToken][account];
    }

    function _claimRewardToken(
        address rewardToken,
        address account,
        uint256 vaultSharesBefore,
        uint256 vaultSharesAfter,
        uint256 rewardsPerVaultShare
    ) internal returns (uint256 rewardToClaim) {
        rewardToClaim = _getRewardsToClaim(
            rewardToken, account, vaultSharesBefore, rewardsPerVaultShare
        );

        s_accountRewardDebt[rewardToken][account] = (
            (vaultSharesAfter * rewardsPerVaultShare) / VAULT_SHARE_PRECISION
        );

        if (0 < rewardToClaim) {
            // Ignore transfer errors here so that any strange failures here do not
            // prevent normal vault operations from working. Failures may include a
            // lack of balances or some sort of blacklist that prevents an account
            // from receiving tokens.
            if (rewardToken.code.length > 0) {
                try IEIP20NonStandard(rewardToken).transfer(account, rewardToClaim) {
                    bool success = TokenUtils.checkReturnCode();
                    if (success) {
                        emit VaultRewardTransfer(rewardToken, account, rewardToClaim);
                    } else {
                        emit VaultRewardTransfer(rewardToken, account, 0);
                    }
                // Emits zero tokens transferred if the transfer fails.
                } catch {
                    emit VaultRewardTransfer(rewardToken, account, 0);
                }
            }
        }
    }

    /*** ACCUMULATORS  ***/

    function _accumulateSecondaryRewardViaClaim(
        uint256 index,
        VaultRewardState memory state,
        uint256 tokensClaimed,
        uint256 totalVaultSharesBefore
    ) private {
        if (tokensClaimed == 0) return;

        state.accumulatedRewardPerVaultShare += (
            (tokensClaimed * VAULT_SHARE_PRECISION) / totalVaultSharesBefore
        ).toUint128();

        s_vaultRewardState[index] = state;
    }

    function _accumulateSecondaryRewardViaEmissionRate(
        uint256 index,
        VaultRewardState memory state,
        uint256 totalVaultSharesBefore
    ) private {
        state.accumulatedRewardPerVaultShare = _getAccumulatedRewardViaEmissionRate(
            state, totalVaultSharesBefore, block.timestamp
        ).toUint128();
        state.lastAccumulatedTime = uint32(block.timestamp);

        s_vaultRewardState[index] = state;
    }

    function _getAccumulatedRewardViaEmissionRate(
        VaultRewardState memory state,
        uint256 totalVaultSharesBefore,
        uint256 blockTime
    ) private pure returns (uint256) {
        // Short circuit the method with no emission rate
        if (state.emissionRatePerYear == 0) return state.accumulatedRewardPerVaultShare;
        require(0 < state.endTime);
        uint256 time = blockTime < state.endTime ? blockTime : state.endTime;

        uint256 additionalIncentiveAccumulatedPerVaultShare;
        if (state.lastAccumulatedTime < time && 0 < totalVaultSharesBefore) {
            // NOTE: no underflow, checked in if statement
            uint256 timeSinceLastAccumulation = time - state.lastAccumulatedTime;
            // Precision here is:
            //  timeSinceLastAccumulation (SECONDS)
            //  emissionRatePerYear (REWARD_TOKEN_PRECISION)
            //  VAULT_SHARE_PRECISION (1e18)
            // DIVIDE BY
            //  YEAR (SECONDS)
            //  VAULT_SHARE_PRECISION (1e18)
            // => Precision = REWARD_TOKEN_PRECISION
            additionalIncentiveAccumulatedPerVaultShare =
                (timeSinceLastAccumulation
                    * VAULT_SHARE_PRECISION
                    * state.emissionRatePerYear)
                / (YEAR * totalVaultSharesBefore);
        }

        return state.accumulatedRewardPerVaultShare + additionalIncentiveAccumulatedPerVaultShare;
    }

    /// @notice Executes the proper call for various rewarder types.
    function _executeClaim() internal virtual;
    function _withdrawFromPreviousRewardPool(address poolToken, RewardPoolStorage memory r) internal virtual;
    function _depositIntoNewRewardPool(address poolToken, uint256 poolTokens, RewardPoolStorage memory newRewardPool) internal virtual;
}