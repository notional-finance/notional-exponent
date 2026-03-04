// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { StakingStrategy } from "./StakingStrategy.sol";
import { ParetoWithdrawRequestManager } from "../withdraws/Pareto.sol";
import { IdleCDOEpochVariant } from "../interfaces/IPareto.sol";

contract CrossChainStakingStrategy is AbstractStakingStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate
    )
        AbstractStakingStrategy(_asset, _yieldToken, _feeRate, ADDRESS_REGISTRY.getWithdrawRequestManager(_yieldToken))
    { }

    function strategy() public pure override returns (string memory) {
        return "CrossChainStaking";
    }

    function _isWithdrawRequestPending(address account) internal view override returns (bool isPending) {
        isPending = super._isWithdrawRequestPending(account);
        if (!isPending) isPending = CrossChainYieldToken(yieldToken).getPendingAssetStaking(account) > 0;
    }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        ERC20(yieldToken).checkApprove(address(CROSS_CHAIN_YIELD_TOKEN), assets);
        CrossChainYieldToken(yieldToken).transferAndBridge(receiver, assets, depositData);
    }

    /// @notice Returns the total value in terms of the borrowed token of the account's position
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0)) {
            if (super._isWithdrawRequestPending(account)) {
                (bool hasRequest, uint256 value) =
                    withdrawRequestManager.getWithdrawRequestValue(address(this), t_CurrentAccount, asset, shares);

                // If the account does not have a withdraw request then this will fall through
                // to the super implementation.
                if (hasRequest) return value;
            }

            uint256 pendingAssetStaking = CrossChainYieldToken(yieldToken).getPendingAssetStaking(t_CurrentAccount);
            if (pendingAssetStaking > 0) return pendingAssetStaking;
        }

        return super.convertToAssets(shares);
    }

    function _executeInstantRedemption(
        address,
        uint256,
        bytes memory
    )
        internal
        override
        returns (uint256 assetsPurchased)
    {
        revert("Not implemented");
    }

    function finalizeAssetStaking(address account)
        external
        nonReentrant
        onlyLendingRouter
        setCurrentAccount(account)
        returns (uint256 sharesMinted)
    {
        // First we finalize the asset staking by getting the excess yield tokens. They will be minted
        // to the account.
        uint256 excessYieldTokens = CrossChainYieldToken(yieldToken).finalizeAssetStaking(account);
        // Approval will be granted to this vault to transfer the yield tokens and then vault shares
        // will be minted to the account.
        sharesMinted = _mintSharesGivenAssets(excessYieldTokens, bytes(""), account, true);

        // Transfer the shares to the lending router so it can supply collateral
        t_AllowTransfer_To = t_CurrentLendingRouter;
        t_AllowTransfer_Amount = sharesMinted;
        _transfer(receiver, t_CurrentLendingRouter, sharesMinted);
        _checkInvariant();
    }
}

