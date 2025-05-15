// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IRewardManager} from "./IRewardManager.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {LibStorage} from "../utils/LibStorage.sol";
import {ILendingRouter} from "../routers/ILendingRouter.sol";

abstract contract RewardManagerMixin is AbstractYieldStrategy {
    IRewardManager public immutable REWARD_MANAGER;
    uint256 transient t_Liquidator_SharesBefore;
    uint256 transient t_LiquidateAccount_SharesBefore;

    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _rewardManager,
        uint8 _yieldTokenDecimals
    ) AbstractYieldStrategy(_asset, _yieldToken, _feeRate, _yieldTokenDecimals) {
        REWARD_MANAGER = IRewardManager(_rewardManager);
    }

    function _initialize(bytes calldata data) internal override virtual {
        super._initialize(data);
    }

    function _preLiquidation(
        address liquidateAccount,
        address liquidator,
        uint256 liquidateAccountShares
    ) internal override virtual returns (uint256 maxLiquidateShares) {
        t_Liquidator_SharesBefore = balanceOf(liquidator);
        t_LiquidateAccount_SharesBefore = liquidateAccountShares;
        return super._preLiquidation(liquidateAccount, liquidator, liquidateAccountShares);
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
        uint256 initialVaultShares = ILendingRouter(t_CurrentLendingRouter).balanceOfCollateral(receiver, address(this));
        sharesMinted = super._mintSharesGivenAssets(assets, depositData, receiver);
        _updateAccountRewards({
            account: receiver,
            accountVaultSharesBefore: initialVaultShares,
            vaultShares: sharesMinted,
            totalVaultSharesBefore: totalSupplyBefore,
            isMint: true
        });
    }

    function _burnShares(uint256 sharesToBurn, uint256 sharesHeld, bytes memory redeemData, address sharesOwner) internal override returns (uint256 assetsWithdrawn) {
        uint256 totalSupplyBefore = totalSupply();
        assetsWithdrawn = super._burnShares(sharesToBurn, sharesHeld, redeemData, sharesOwner);
        _updateAccountRewards({
            account: sharesOwner,
            accountVaultSharesBefore: sharesHeld,
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
        _delegateCall(address(REWARD_MANAGER), abi.encodeWithSelector(
            IRewardManager.updateAccountRewards.selector,
            account, accountVaultSharesBefore, vaultShares, totalVaultSharesBefore, isMint
        ));
    }

    fallback() external {
        address target = address(REWARD_MANAGER);
        // Cannot call updateAccountRewards unless it's through the internal methods
        require(msg.sig != IRewardManager.updateAccountRewards.selector);
        bytes memory result = _delegateCall(target, msg.data);

        assembly {
            // Copy the result to memory
            let resultSize := mload(result)
            // Copy the result data (skipping the length prefix)
            let resultData := add(result, 0x20)
            // Copy to the return data area
            return(resultData, resultSize)
        }
    }
}
