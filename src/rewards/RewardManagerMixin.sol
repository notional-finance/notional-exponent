// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IRewardManager} from "./IRewardManager.sol";

abstract contract RewardManagerMixin {
    IRewardManager public immutable REWARD_MANAGER;

    constructor(address _rewardManager) {
        REWARD_MANAGER = IRewardManager(_rewardManager);
    }

    function _updateAccountRewards(
        address account,
        uint256 accountVaultSharesBefore,
        uint256 vaultShares,
        uint256 totalVaultSharesBefore,
        bool isMint
    ) internal {
        (bool success, /* */) = address(REWARD_MANAGER).delegatecall(abi.encodeWithSelector(
            IRewardManager.updateAccountRewards.selector,
            account, accountVaultSharesBefore, vaultShares, totalVaultSharesBefore, isMint
        ));
        require(success);
    }

    fallback() external {
        address target = address(REWARD_MANAGER);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
