// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import "./AbstractStakingStrategy.sol";
import "../interfaces/IPendle.sol";
import "../utils/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct PendleDepositParams {
    uint16 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
    IPRouter.LimitOrderData limitOrderData;
}

struct PendleRedeemParams {
    uint8 dexId;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    IPRouter.LimitOrderData limitOrderData;
}

struct PendleWithdrawParams {
    uint256 minTokenOutSy;
    bytes withdrawData;
    IPRouter.LimitOrderData limitOrderData;
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
        address owner,
        uint256 feeRate,
        address irm,
        uint256 lltv,
        IWithdrawRequestManager withdrawRequestManager
    ) AbstractStakingStrategy(owner, asset, yieldToken, feeRate, irm, lltv, withdrawRequestManager) {
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

    function _withdrawRequestYieldTokenRate() internal view override returns (uint256) {
        (int256 tokenOutSyRate, /* */) = TRADING_MODULE.getOraclePrice(TOKEN_OUT_SY, asset);
        require(tokenOutSyRate > 0);
        return uint256(tokenOutSyRate);
    }

    function _stakeTokens(
        uint256 assets,
        address /* receiver */,
        bytes memory data
    ) internal override {
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

        ERC20(TOKEN_IN_SY).forceApprove(address(PENDLE_ROUTER), tokenInAmount);
        uint256 msgValue = TOKEN_IN_SY == ETH_ADDRESS ? tokenInAmount : 0;
        PENDLE_ROUTER.swapExactTokenForPt{value: msgValue}(
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
            params.limitOrderData
        );
    }

    /// @notice Handles PT redemption whether it is expired or not
    function _redeemPT(uint256 netPtIn, IPRouter.LimitOrderData memory limitOrderData) internal returns (uint256 netTokenOut) {
        if (PT.isExpired()) {
            PT.transfer(address(YT), netPtIn);
            uint256 netSyOut = YT.redeemPY(address(SY));
            netTokenOut = SY.redeem(address(this), netSyOut, TOKEN_OUT_SY, 0, true);
        } else {
            IPRouter.SwapData memory EMPTY_SWAP;
            PT.approve(address(PENDLE_ROUTER), netPtIn);
            (netTokenOut, , ) = PENDLE_ROUTER.swapExactPtForToken(
                address(this),
                address(MARKET),
                netPtIn,
                // When tokenIn == tokenMintSy then the swap router can be set to
                // empty data. This means that the vault must hold the underlying sy
                // token when we begin the execution.
                IPRouter.TokenOutput({
                    tokenOut: TOKEN_OUT_SY,
                    minTokenOut: 0,
                    tokenRedeemSy: TOKEN_OUT_SY,
                    pendleSwap: address(0),
                    swapData: EMPTY_SWAP
                }),
                limitOrderData
            );
        }
    }

    function _executeInstantRedemption(
        uint256 yieldTokensToRedeem,
        bytes memory redeemData
    ) internal override virtual returns (uint256 assetsPurchased) {
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
            require(params.minPurchaseAmount <= netTokenOut, "Slippage");
            assetsPurchased = netTokenOut;
        }
    }

    function _initiateWithdraw(address account, bool isForced, bytes calldata data) internal override returns (uint256 requestId) {
        uint256 sharesHeld = balanceOfShares(account);
        uint256 ptAmount = convertSharesToYieldToken(sharesHeld);
        _escrowShares(sharesHeld, ptAmount);
        // When doing a direct withdraw for PTs, we first redeem or trade out of the PT
        // and then initiate a withdraw on the TOKEN_OUT_SY. Since the vault shares are
        // stored in PT terms, we pass tokenOutSy terms (i.e. weETH or sUSDe) to the withdraw
        // implementation.
        PendleWithdrawParams memory params = abi.decode(data, (PendleWithdrawParams));
        uint256 tokenOutSy = _redeemPT(ptAmount, params.limitOrderData);
        require(params.minTokenOutSy <= tokenOutSy, "Slippage");

        ERC20(TOKEN_OUT_SY).approve(address(withdrawRequestManager), tokenOutSy);
        requestId = withdrawRequestManager.initiateWithdraw({
            account: account, yieldTokenAmount: tokenOutSy, sharesAmount: sharesHeld,
            isForced: isForced, data: params.withdrawData
        });
    }
}
