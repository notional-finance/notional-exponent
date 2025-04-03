// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IRewardManager} from "./IRewardManager.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";

abstract contract RewardManagerMixin is AbstractYieldStrategy {
    IRewardManager public immutable REWARD_MANAGER;

    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager
    ) AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {
        REWARD_MANAGER = IRewardManager(_rewardManager);
    }

    // TODO: add pre and post hooks to liquidation

    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) internal override returns (uint256 sharesMinted) {
        uint256 totalSupplyBefore = totalSupply();
        uint256 initialVaultShares = balanceOf(receiver) + _accountCollateralBalance(receiver);
        sharesMinted = super._mintSharesGivenAssets(assets, depositData, receiver);
        _updateAccountRewards(receiver, initialVaultShares, sharesMinted, totalSupplyBefore, true);
    }

    function _burnShares(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) internal override returns (uint256 assetsWithdrawn) {
        uint256 totalSupplyBefore = totalSupply();
        uint256 initialVaultShares = balanceOf(sharesOwner) + _accountCollateralBalance(sharesOwner);
        assetsWithdrawn = super._burnShares(sharesToBurn, redeemData, sharesOwner);
        _updateAccountRewards(sharesOwner, initialVaultShares, sharesToBurn, totalSupplyBefore, false);
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
