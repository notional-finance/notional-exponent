// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractStakingStrategy } from "./AbstractStakingStrategy.sol";
import { IPMarket, IStandardizedYield, IPPrincipalToken, IPYieldToken } from "../interfaces/IPendle.sol";
import { IWithdrawRequestManager } from "../interfaces/IWithdrawRequestManager.sol";
import { Trade, TradeType } from "../interfaces/ITradingModule.sol";
import { SlippageTooHigh } from "../interfaces/Errors.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { PendlePTLib } from "./PendlePTLib.sol";
import { TokenUtils } from "../utils/TokenUtils.sol";

struct PendleDepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    bytes pendleData;
}

struct PendleRedeemParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    bytes limitOrderData;
}

/**
 * Base implementation for Pendle PT vaults
 */
contract PendlePT is AbstractStakingStrategy {
    using TokenUtils for ERC20;

    IPMarket public immutable MARKET;
    address public immutable TOKEN_OUT_SY;

    address public immutable TOKEN_IN_SY;
    IStandardizedYield public immutable SY;
    IPPrincipalToken public immutable PT;
    IPYieldToken public immutable YT;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address asset,
        address yieldToken,
        uint256 feeRate,
        IWithdrawRequestManager withdrawRequestManager
    )
        AbstractStakingStrategy(asset, yieldToken, feeRate, withdrawRequestManager)
    {
        MARKET = IPMarket(market);
        (address sy, address pt, address yt) = MARKET.readTokens();
        SY = IStandardizedYield(sy);
        PT = IPPrincipalToken(pt);
        YT = IPYieldToken(yt);
        require(address(PT) == yieldToken);
        require(SY.isValidTokenIn(tokenInSY));
        // This may not be the same as valid token in, for LRT you can
        // put ETH in but you would only get weETH or eETH out
        require(SY.isValidTokenOut(tokenOutSY));

        TOKEN_IN_SY = tokenInSY;
        TOKEN_OUT_SY = tokenOutSY;

        if (address(withdrawRequestManager) == address(0)) {
            // If no withdraw request manager is set then use the token in sy
            // as the accounting asset.
            accountingAsset = tokenInSY;
        }
    }

    function strategy() public pure override returns (string memory) {
        return "PendlePT";
    }

    function _mintYieldTokens(
        uint256 assets,
        address,
        /* receiver */
        bytes memory data
    )
        internal
        override
    {
        require(!PT.isExpired(), "Expired");
        PendleDepositParams memory params = abi.decode(data, (PendleDepositParams));
        uint256 tokenInAmount;

        if (TOKEN_IN_SY != asset) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: asset,
                buyToken: TOKEN_IN_SY,
                amount: assets,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, tokenInAmount) = _executeTrade(trade, params.dexId);
        } else {
            tokenInAmount = assets;
        }

        PendlePTLib.swapExactTokenForPt(TOKEN_IN_SY, address(MARKET), address(PT), tokenInAmount, params.pendleData);
    }

    /// @notice Handles PT redemption whether it is expired or not
    function _redeemPT(uint256 netPtIn, bytes memory limitOrderData) internal returns (uint256 netTokenOut) {
        if (PT.isExpired()) {
            netTokenOut = PendlePTLib.redeemExpiredPT(PT, YT, SY, TOKEN_OUT_SY, netPtIn);
        } else {
            netTokenOut =
                PendlePTLib.swapExactPtForToken(address(PT), address(MARKET), TOKEN_OUT_SY, netPtIn, limitOrderData);
        }
    }

    function _executeInstantRedemption(
        address,
        /* sharesOwner */
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    )
        internal
        virtual
        override
        returns (uint256 assetsPurchased)
    {
        PendleRedeemParams memory params = abi.decode(redeemData, (PendleRedeemParams));
        uint256 netTokenOut = _redeemPT(yieldTokensToRedeem, params.limitOrderData);

        if (TOKEN_OUT_SY != asset) {
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: TOKEN_OUT_SY,
                buyToken: asset,
                amount: netTokenOut,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });

            // Executes a trade on the given Dex, the vault must have permissions set for
            // each dex and token it wants to sell.
            (/* */, assetsPurchased) = _executeTrade(trade, params.dexId);
        } else {
            if (params.minPurchaseAmount > netTokenOut) revert SlippageTooHigh(netTokenOut, params.minPurchaseAmount);
            assetsPurchased = netTokenOut;
        }
    }

    function _initiateWithdraw(
        address account,
        uint256 ptAmount,
        uint256 sharesHeld,
        bytes memory data,
        address forceWithdrawFrom
    )
        internal
        override
        returns (uint256 requestId)
    {
        // Withdraws can only be initiated for expired PTs
        require(PT.isExpired(), "Cannot initiate withdraw for non-expired PTs");
        // When doing a direct withdraw for PTs, we first redeem the expired PT
        // and then initiate a withdraw on the TOKEN_OUT_SY. Since the vault shares are
        // stored in PT terms, we pass tokenOutSy terms (i.e. weETH or sUSDe) to the withdraw
        // implementation.
        uint256 tokenOutSy = _redeemPT(ptAmount, bytes(""));

        ERC20(TOKEN_OUT_SY).checkApprove(address(withdrawRequestManager), tokenOutSy);
        return withdrawRequestManager.initiateWithdraw({
            account: account,
            yieldTokenAmount: tokenOutSy,
            sharesAmount: sharesHeld,
            data: data,
            forceWithdrawFrom: forceWithdrawFrom
        });
    }
}
