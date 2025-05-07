// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IRewardManager} from "./IRewardManager.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {LibStorage} from "../utils/LibStorage.sol";

abstract contract RewardManagerMixin is AbstractYieldStrategy {
    IRewardManager public immutable REWARD_MANAGER;
    uint256 transient t_Liquidator_SharesBefore;
    uint256 transient t_LiquidateAccount_SharesBefore;

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv,
        address _rewardManager,
        uint8 _yieldTokenDecimals
    ) AbstractYieldStrategy(_asset, _yieldToken, _feeRate, _irm, _lltv, _yieldTokenDecimals) {
        REWARD_MANAGER = IRewardManager(_rewardManager);
    }

    function _initialize(bytes calldata data) internal override virtual {
        super._initialize(data);
    }

    function _preLiquidation(address liquidateAccount, address liquidator) internal override virtual returns (uint256 maxLiquidateShares) {
        t_Liquidator_SharesBefore = balanceOfShares(liquidator);
        t_LiquidateAccount_SharesBefore = balanceOfShares(liquidateAccount);
        return super._preLiquidation(liquidateAccount, liquidator);
    }

    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal override virtual {
        super._postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);
       
        // Total supply does not change during liquidation
        uint256 totalSupplyBefore = totalSupply();

        _updateAccountRewards({
            account: liquidator,
            accountVaultSharesBefore: t_Liquidator_SharesBefore,
            vaultShares: sharesToLiquidator,
            totalVaultSharesBefore: totalSupplyBefore,
            isMint: true
        });

        _updateAccountRewards({
            account: liquidateAccount,
            accountVaultSharesBefore: t_LiquidateAccount_SharesBefore,
            vaultShares: sharesToLiquidator,
            totalVaultSharesBefore: totalSupplyBefore,
            isMint: false
        });
    }

    function _mintSharesGivenAssets(uint256 assets, bytes memory depositData, address receiver) internal override returns (uint256 sharesMinted) {
        uint256 totalSupplyBefore = totalSupply();
        uint256 initialVaultShares = balanceOfShares(receiver);
        sharesMinted = super._mintSharesGivenAssets(assets, depositData, receiver);
        _updateAccountRewards({
            account: receiver,
            accountVaultSharesBefore: initialVaultShares,
            vaultShares: sharesMinted,
            totalVaultSharesBefore: totalSupplyBefore,
            isMint: true
        });
    }

    function _burnShares(uint256 sharesToBurn, bytes memory redeemData, address sharesOwner) internal override returns (uint256 assetsWithdrawn) {
        uint256 totalSupplyBefore = totalSupply();
        uint256 initialVaultShares = balanceOfShares(sharesOwner);
        assetsWithdrawn = super._burnShares(sharesToBurn, redeemData, sharesOwner);
        _updateAccountRewards({
            account: sharesOwner,
            accountVaultSharesBefore: initialVaultShares,
            vaultShares: sharesToBurn,
            totalVaultSharesBefore: totalSupplyBefore,
            isMint: false
        });
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
        // Cannot call updateAccountRewards unless it's through the internal methods
        require(msg.sig != IRewardManager.updateAccountRewards.selector);
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
