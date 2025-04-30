// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../rewards/IRewardManager.sol";

library LibStorage {
    uint256 private constant REWARD_POOL_SLOT = 1000001;
    uint256 private constant VAULT_REWARD_STATE_SLOT = 1000002;
    uint256 private constant ACCOUNT_REWARD_DEBT_SLOT = 1000003;
    uint256 private constant REWARD_MANAGER_SLOT = 1000004;

    function getRewardPoolSlot() internal pure returns (RewardPoolStorage storage store) {
        assembly { store.slot := REWARD_POOL_SLOT }
    }

    function getVaultRewardStateSlot() internal pure returns (VaultRewardState[] storage store) {
        assembly { store.slot := VAULT_REWARD_STATE_SLOT }
    }

    // account => rewardToken => rewardDebt
    function getAccountRewardDebtSlot() internal pure returns (mapping(address => mapping(address => uint256)) storage store) {
        assembly { store.slot := ACCOUNT_REWARD_DEBT_SLOT }
    }

    function _rewardManagerSlot() internal pure returns (mapping(uint256 => address) storage store) {
        assembly { store.slot := REWARD_MANAGER_SLOT }
    }

    function getRewardManagerSlot() internal view returns (address store) {
        return _rewardManagerSlot()[0];
    }
}
