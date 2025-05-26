// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IRewardManager} from "../interfaces/IRewardManager.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {ILendingRouter} from "../interfaces/ILendingRouter.sol";

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

    function _mintSharesGivenAssets(
        uint256 assets,
        bytes memory depositData,
        address receiver
    ) internal override returns (uint256 sharesMinted) {
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

    function _burnShares(
        uint256 sharesToBurn,
        bytes memory redeemData,
        address sharesOwner
    ) internal override returns (uint256 assetsWithdrawn, bool wasEscrowed) {
        uint256 totalSupplyBefore = totalSupply();
        // When burning shares, the sharesOwner will hold them directly, they will
        // not be held on a lending market
        uint256 sharesHeld = balanceOf(sharesOwner) + 
        // Also include any shares held on a lending market
            (t_CurrentLendingRouter == address(0) ? 0 :
                ILendingRouter(t_CurrentLendingRouter).balanceOfCollateral(sharesOwner, address(this)));

        (assetsWithdrawn, wasEscrowed) = super._burnShares(sharesToBurn, redeemData, sharesOwner);

        if (!wasEscrowed) {
            // If shares were escrowed then the account will not have rewards since they were
            // already cleared upon exit.
            _updateAccountRewards({
                account: sharesOwner,
                accountVaultSharesBefore: sharesHeld,
                vaultShares: sharesToBurn,
                totalVaultSharesBefore: totalSupplyBefore,
                isMint: false
            });
        }
    }

    function __initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data
    ) internal virtual returns (uint256 requestId);
    
    /// @dev Ensures that the account no longer accrues rewards after a withdraw request is initiated.
    function _initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data
    ) internal override returns (uint256 requestId) {
        uint256 totalSupplyBefore = totalSupply();
        requestId = __initiateWithdraw(account, yieldTokenAmount, sharesHeld, data);

        _updateAccountRewards({
            account: account,
            accountVaultSharesBefore: sharesHeld,
            vaultShares: sharesHeld,
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
