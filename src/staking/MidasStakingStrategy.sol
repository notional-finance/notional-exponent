// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { StakingStrategy } from "./StakingStrategy.sol";
import { IRedemptionVault, MidasAccessControl, MIDAS_GREENLISTED_ROLE } from "../interfaces/IMidas.sol";
import { ADDRESS_REGISTRY, CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { ERC20, TokenUtils } from "../utils/TokenUtils.sol";
import { MidasWithdrawRequestManager } from "../withdraws/Midas.sol";

contract MidasStakingStrategy is StakingStrategy {
    using TokenUtils for ERC20;

    constructor(address _asset, address _yieldToken, uint256 _feeRate)
        StakingStrategy(_asset, _yieldToken, _feeRate)
    { }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        (uint256 minReceiveAmount) = abi.decode(depositData, (uint256));
        // Ensure that we encode the proper receiver here for KYC checks.
        bytes memory stakeData = abi.encode(receiver, minReceiveAmount);
        super._mintYieldTokens(assets, receiver, stakeData);
    }

    function _executeInstantRedemption(
        address sharesOwner,
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    )
        internal
        override
        returns (uint256 assetsPurchased)
    {
        MidasWithdrawRequestManager wrm = MidasWithdrawRequestManager(address(withdrawRequestManager));
        IRedemptionVault redeemVault = IRedemptionVault(wrm.redeemVault());
        if (redeemVault.greenlistEnabled()) {
            require(
                MidasAccessControl.hasRole(MIDAS_GREENLISTED_ROLE, sharesOwner), "Midas: account is not greenlisted"
            );
        }

        uint256 assetsBefore = TokenUtils.tokenBalance(asset);
        (uint256 minReceiveAmount) = abi.decode(redeemData, (uint256));

        ERC20(yieldToken).checkApprove(address(redeemVault), yieldTokensToRedeem);
        redeemVault.redeemInstant(address(asset), yieldTokensToRedeem, minReceiveAmount);

        uint256 assetsAfter = TokenUtils.tokenBalance(asset);
        assetsPurchased = assetsAfter - assetsBefore;
    }
}
