// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "./AbstractStakingStrategy.sol";
import "../interfaces/IPendle.sol";
import "../Constants.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct PendleDepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
}

/** Base implementation for Pendle PT vaults */
contract PendlePT is AbstractStakingStrategy {
    using SafeERC20 for ERC20;

    IPMarket public immutable MARKET;
    address public immutable TOKEN_OUT_SY;

    address public immutable TOKEN_IN_SY;
    IStandardizedYield immutable SY;
    IPPrincipalToken immutable PT;
    IPYieldToken immutable YT;

    constructor(
        address market,
        address tokenInSY,
        address tokenOutSY,
        address asset,
        address yieldToken,
        address redemptionToken,
        address owner,
        uint256 feeRate,
        address irm,
        uint256 lltv,
        IWithdrawRequestManager withdrawRequestManager
    ) AbstractStakingStrategy(owner, asset, yieldToken, feeRate, irm, lltv, redemptionToken, withdrawRequestManager) {
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
    }

    function _stakeTokens(
        uint256 assets,
        address /* receiver */,
        bytes memory data
    ) internal override returns (uint256 ptReceived) {
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

        IPRouter.SwapData memory EMPTY_SWAP;
        IPRouter.LimitOrderData memory EMPTY_LIMIT;

        ERC20(TOKEN_IN_SY).forceApprove(address(PENDLE_ROUTER), tokenInAmount);
        uint256 msgValue = TOKEN_IN_SY == ETH_ADDRESS ? tokenInAmount : 0;
        (ptReceived, /* */, /* */) = PENDLE_ROUTER.swapExactTokenForPt{value: msgValue}(
            address(this),
            address(MARKET),
            params.minPtOut,
            params.approxParams,
            // When tokenIn == tokenMintSy then the swap router can be set to
            // empty data. This means that the vault must hold the underlying sy
            // token when we begin the execution.
            IPRouter.TokenInput({
                tokenIn: TOKEN_IN_SY,
                netTokenIn: tokenInAmount,
                tokenMintSy: TOKEN_IN_SY,
                pendleSwap: address(0),
                swapData: EMPTY_SWAP
            }),
            EMPTY_LIMIT
        );
    }

    /// @notice Handles PT redemption whether it is expired or not
    function _redeemPT(uint256 netPtIn) internal returns (uint256 netTokenOut) {
        uint256 netSyOut;

        // PT tokens are known to be ERC20 compatible
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            netSyOut = YT.redeemPY(address(SY));
        } else {
            PT.transfer(address(MARKET), netPtIn);
            (netSyOut, ) = MARKET.swapExactPtForSy(address(SY), netPtIn, "");
        }

        netTokenOut = SY.redeem(address(this), netSyOut, TOKEN_OUT_SY, 0, true);
    }

    function _executeInstantRedemption(
        uint256 yieldTokensToRedeem,
        RedeemParams memory params
    ) internal override virtual returns (uint256 assetsPurchased) {
        uint256 netTokenOut = _redeemPT(yieldTokensToRedeem);

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
            require(params.minPurchaseAmount <= netTokenOut, "Slippage");
            assetsPurchased = netTokenOut;
        }
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal override returns (uint256 requestId) {
        uint256 amount;
        // When doing a direct withdraw for PTs, we first redeem or trade out of the PT
        // and then initiate a withdraw on the TOKEN_OUT_SY. Since the vault shares are
        // stored in PT terms, we pass tokenOutSy terms (i.e. weETH or sUSDe) to the withdraw
        // implementation.
        (uint256 minTokenOutSy, bytes memory withdrawData) = abi.decode(data, (uint256, bytes));
        uint256 tokenOutSy = _redeemPT(amount);
        require(minTokenOutSy <= tokenOutSy, "Slippage");

        requestId = withdrawRequestManager.initiateWithdraw({
            account: account, amount: tokenOutSy, isForced: isForced, data: withdrawData
        });
    }
}
