// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import {
    IDepositVault,
    IRedemptionVault,
    DecimalsCorrectionLibrary,
    IMidasDataFeed,
    MidasRequestStatus,
    IMidasVault
} from "../interfaces/IMidas.sol";
import { ERC20, TokenUtils } from "../utils/TokenUtils.sol";

contract MidasWithdrawRequestManager is AbstractWithdrawRequestManager {
    using DecimalsCorrectionLibrary for uint256;
    using TokenUtils for ERC20;

    IDepositVault public immutable depositVault;
    IRedemptionVault public immutable redeemVault;
    bytes32 internal constant REFERRER_ID = 0x0000000000000000000000000000000000000000000000000000000000000026;
    uint256 internal constant ONE_HUNDRED_PERCENT = 10_000;

    constructor(
        address tokenIn,
        IDepositVault _depositVault,
        IRedemptionVault _redeemVault
    )
        AbstractWithdrawRequestManager(tokenIn, _depositVault.mToken(), tokenIn)
    {
        depositVault = _depositVault;
        redeemVault = _redeemVault;

        require(depositVault.mToken() == redeemVault.mToken(), "Midas: mToken mismatch");
        address[] memory depositTokens = depositVault.getPaymentTokens();
        bool isValidDepositToken = false;
        for (uint256 i = 0; i < depositTokens.length; i++) {
            if (depositTokens[i] == tokenIn) {
                isValidDepositToken = true;
                break;
            }
        }
        require(isValidDepositToken, "Midas: tokenIn is not a deposit token");

        address[] memory redeemTokens = redeemVault.getPaymentTokens();
        bool isValidRedeemToken = false;
        for (uint256 i = 0; i < redeemTokens.length; i++) {
            if (redeemTokens[i] == tokenIn) {
                isValidRedeemToken = true;
                break;
            }
        }
        require(isValidRedeemToken, "Midas: tokenIn is not a redeem token");
    }

    function _stakeTokens(uint256 amount, bytes memory stakeData) internal override {
        (uint256 minReceiveAmount) = abi.decode(stakeData, (uint256));

        ERC20(STAKING_TOKEN).checkApprove(address(depositVault), amount);

        // Midas requires the amount to be in 18 decimals regardless of the native token decimals.
        uint256 scaledAmount = amount * 1e18 / (10 ** TokenUtils.getDecimals(STAKING_TOKEN));
        depositVault.depositInstant(STAKING_TOKEN, scaledAmount, minReceiveAmount, REFERRER_ID);
    }

    function _initiateWithdrawImpl(
        address account,
        uint256 amountToWithdraw,
        bytes calldata,
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        ERC20(YIELD_TOKEN).checkApprove(address(redeemVault), amountToWithdraw);
        requestId = redeemVault.redeemRequest(WITHDRAW_TOKEN, amountToWithdraw);
    }

    function _finalizeWithdrawImpl(
        address, /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
        IRedemptionVault.Request memory request = redeemVault.redeemRequests(requestId);
        require(request.status == MidasRequestStatus.Processed);
        uint256 tokenDecimals = TokenUtils.getDecimals(WITHDRAW_TOKEN);

        // Once the request is processed, the tokens are transferred to this contract so we calculate the
        // amount of tokens claimed and return it. This is not ideal since we don't pull the tokens but it
        // is how the Midas vault works.
        tokensClaimed = _truncate((request.amountMToken * request.mTokenRate) / request.tokenOutRate, tokenDecimals);
        // Convert to the native token decimals, subtract 1 unit to account for any rounding errors.
        tokensClaimed = (tokensClaimed * 10 ** tokenDecimals) / 1e18 - 1;
    }

    /// @dev truncates the value to the given decimals, mirrors the behavior of the Midas vault.
    function _truncate(uint256 value, uint256 decimals) internal pure returns (uint256) {
        return value.convertFromBase18(decimals).convertToBase18(decimals);
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        IRedemptionVault.Request memory request = redeemVault.redeemRequests(requestId);
        uint256 tokenDecimals = TokenUtils.getDecimals(WITHDRAW_TOKEN);

        // NOTE: it is possible that the mTokenRate moves a bit but this will be used
        // to value the withdraw request when it is pending.
        hasKnownAmount = true;
        // The request.mTokenRate will be updated when the request is processed to the final rate.
        amount = _truncate((request.amountMToken * request.mTokenRate) / request.tokenOutRate, tokenDecimals);
        // Midas vaults return the amount in 18 decimals but we need to convert to the native
        // token decimals here.
        amount = (amount * 10 ** tokenDecimals) / 1e18 - 1;
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        IRedemptionVault.Request memory request = redeemVault.redeemRequests(requestId);
        return request.status == MidasRequestStatus.Processed;
    }

    function getExchangeRate() public view override returns (uint256 rate) {
        IMidasVault.TokenConfig memory tokenConfig = redeemVault.tokensConfig(WITHDRAW_TOKEN);
        rate = IMidasDataFeed(redeemVault.mTokenDataFeed()).getDataInBase18();
        if (!tokenConfig.stable) {
            uint256 tokenRate = IMidasDataFeed(tokenConfig.dataFeed).getDataInBase18();
            rate = 1e18 * rate / tokenRate;
        }
        // Convert to withdraw token decimals.
        rate = rate * 10 ** TokenUtils.getDecimals(WITHDRAW_TOKEN) / 1e18;
    }
}
