// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {IRewardManager} from "../interfaces/IRewardManager.sol";
import {AbstractYieldStrategy} from "../AbstractYieldStrategy.sol";
import {ILendingRouter} from "../interfaces/ILendingRouter.sol";

abstract contract RewardManagerMixin is AbstractYieldStrategy {
    IRewardManager public immutable REWARD_MANAGER;

    uint256 internal transient t_Liquidator_SharesBefore;
    uint256 internal transient t_LiquidateAccount_SharesBefore;

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
        uint256 sharesToLiquidate,
        uint256 accountSharesHeld
    ) internal override virtual returns (uint256 maxLiquidateShares) {
        // This only works because the liquidator is prevented from having a position on the lending router so any
        // balance will be a native token balance.
        t_Liquidator_SharesBefore = balanceOf(liquidator);
        t_LiquidateAccount_SharesBefore = accountSharesHeld;
        return super._preLiquidation(liquidateAccount, liquidator, sharesToLiquidate, accountSharesHeld);
    }
    function __postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    ) internal virtual returns (bool didSplit);

    function _postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    ) internal override returns (bool didSplit) {
        // Total supply does not change during liquidation
        uint256 effectiveSupplyBefore = effectiveSupply();

        didSplit = __postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        _updateAccountRewards({
            account: liquidator,
            accountSharesBefore: t_Liquidator_SharesBefore,
            accountSharesAfter: t_Liquidator_SharesBefore + sharesToLiquidator,
            effectiveSupplyBefore: effectiveSupplyBefore,
            sharesInEscrow: didSplit
        });

        _updateAccountRewards({
            account: liquidateAccount,
            accountSharesBefore: t_LiquidateAccount_SharesBefore,
            accountSharesAfter: t_LiquidateAccount_SharesBefore - sharesToLiquidator,
            effectiveSupplyBefore: effectiveSupplyBefore,
            sharesInEscrow: didSplit
        });
    }

    function _mintSharesGivenAssets(
        uint256 assets,
        bytes memory depositData,
        address receiver
    ) internal override returns (uint256 sharesMinted) {
        uint256 effectiveSupplyBefore = effectiveSupply();
        uint256 initialVaultShares = ILendingRouter(t_CurrentLendingRouter).balanceOfCollateral(receiver, address(this));
        sharesMinted = super._mintSharesGivenAssets(assets, depositData, receiver);
        _updateAccountRewards({
            account: receiver,
            accountSharesBefore: initialVaultShares,
            accountSharesAfter: initialVaultShares + sharesMinted,
            effectiveSupplyBefore: effectiveSupplyBefore,
            // Shares cannot be in escrow during minting
            sharesInEscrow: false
        });
    }

    function _burnShares(
        uint256 sharesToBurn,
        bytes memory redeemData,
        address sharesOwner
    ) internal override returns (uint256 assetsWithdrawn) {
        uint256 effectiveSupplyBefore = effectiveSupply();
        // Get the escrow state before burning the shares since it will be cleared if
        // the entire balance is burned.
        bool wasEscrowed = _isWithdrawRequestPending(sharesOwner);
        // When burning shares, the sharesOwner will hold them directly, they will
        // not be held on a lending market
        uint256 sharesHeld = balanceOf(sharesOwner) + 
        // Also include any shares held on a lending market in the total sharesHeld
            (t_CurrentLendingRouter == address(0) ? 0 :
                ILendingRouter(t_CurrentLendingRouter).balanceOfCollateral(sharesOwner, address(this)));

        assetsWithdrawn = super._burnShares(sharesToBurn, redeemData, sharesOwner);

        _updateAccountRewards({
            account: sharesOwner,
            accountSharesBefore: sharesHeld,
            // If shares after is zero then the escrow state will be cleared
            accountSharesAfter: sharesHeld - sharesToBurn,
            effectiveSupplyBefore: effectiveSupplyBefore,
            sharesInEscrow: wasEscrowed
        });
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
        uint256 effectiveSupplyBefore = effectiveSupply();
        requestId = __initiateWithdraw(account, yieldTokenAmount, sharesHeld, data);

        _updateAccountRewards({
            account: account,
            accountSharesBefore: sharesHeld,
            accountSharesAfter: sharesHeld,
            effectiveSupplyBefore: effectiveSupplyBefore,
            sharesInEscrow: true
        });
    }

    function _updateAccountRewards(
        address account,
        uint256 effectiveSupplyBefore,
        uint256 accountSharesBefore,
        uint256 accountSharesAfter,
        bool sharesInEscrow
    ) internal {
        _delegateCall(address(REWARD_MANAGER), abi.encodeWithSelector(
            IRewardManager.updateAccountRewards.selector,
            account, effectiveSupplyBefore, accountSharesBefore, accountSharesAfter, sharesInEscrow
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
