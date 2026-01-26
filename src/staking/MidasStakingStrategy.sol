// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { StakingStrategy } from "./StakingStrategy.sol";
import { RedeemParams, Trade, TradeType } from "./AbstractStakingStrategy.sol";
import { IMidasVault, ISanctionsList, IMidasAccessControl, IRedemptionVault } from "../interfaces/IMidas.sol";
import { ADDRESS_REGISTRY, CHAIN_ID_MAINNET } from "../utils/Constants.sol";
import { ERC20, TokenUtils } from "../utils/TokenUtils.sol";
import { MidasWithdrawRequestManager } from "../withdraws/Midas.sol";

contract MidasStakingStrategy is StakingStrategy {
    using TokenUtils for ERC20;

    error MidasBlockedAccount(address account);

    constructor(address _asset, address _yieldToken, uint256 _feeRate)
        StakingStrategy(_asset, _yieldToken, _feeRate)
    { }

    function strategy() public pure override returns (string memory) {
        return "MidasStaking";
    }

    function _checkMidasAccount(address account, IMidasVault vault) internal view {
        IMidasAccessControl accessControl = IMidasAccessControl(vault.accessControl());
        // This is the Chainalysis sanctions list.
        ISanctionsList sanctionsList = ISanctionsList(vault.sanctionsList());
        if (sanctionsList.isSanctioned(account)) revert MidasBlockedAccount(account);
        if (accessControl.hasRole(accessControl.BLACKLISTED_ROLE(), account)) revert MidasBlockedAccount(account);
        if (vault.greenlistEnabled() && !accessControl.hasRole(accessControl.GREENLISTED_ROLE(), account)) {
            revert MidasBlockedAccount(account);
        }
    }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        MidasWithdrawRequestManager wrm = MidasWithdrawRequestManager(address(withdrawRequestManager));
        IMidasVault vault = IMidasVault(wrm.depositVault());
        _checkMidasAccount(receiver, vault);
        super._mintYieldTokens(assets, receiver, depositData);
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
        _checkMidasAccount(sharesOwner, redeemVault);

        uint256 withdrawTokenBefore = TokenUtils.tokenBalance(withdrawToken);

        ERC20(yieldToken).checkApprove(address(redeemVault), yieldTokensToRedeem);
        redeemVault.redeemInstant(address(withdrawToken), yieldTokensToRedeem, 0);
        // Make sure to revoke the approval since the transfer amount will be less than the
        // approval amount due to fees charged by the vault.
        ERC20(yieldToken).checkRevoke(address(redeemVault));

        uint256 withdrawTokens = TokenUtils.tokenBalance(withdrawToken) - withdrawTokenBefore;
        if (asset != withdrawToken) {
            // When asset != withdrawToken then we need to execute a trade back to the asset.
            RedeemParams memory params = abi.decode(redeemData, (RedeemParams));
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: address(withdrawToken),
                buyToken: address(asset),
                amount: withdrawTokens,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, assetsPurchased) = _executeTrade(trade, params.dexId);
        } else {
            // When asset = withdrawToken then check the minReceiveAmount here and return
            // the value.
            (uint256 minReceiveAmount) = abi.decode(redeemData, (uint256));
            require(minReceiveAmount <= withdrawTokens);
            assetsPurchased = withdrawTokens;
        }
    }

    function _initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data,
        address forceWithdrawFrom
    )
        internal
        override
        returns (uint256 requestId)
    {
        MidasWithdrawRequestManager wrm = MidasWithdrawRequestManager(address(withdrawRequestManager));
        IMidasVault vault = IMidasVault(wrm.redeemVault());
        _checkMidasAccount(account, vault);
        requestId = super._initiateWithdraw(account, yieldTokenAmount, sharesHeld, data, forceWithdrawFrom);
    }
}
