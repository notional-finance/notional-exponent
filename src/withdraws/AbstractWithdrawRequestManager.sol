// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "./IWithdrawRequestManager.sol";
import "./ClonedCoolDownHolder.sol";
import "../utils/Errors.sol";
import "../utils/TypeConvert.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Trade, TradeType, TRADING_MODULE, nProxy, TradeFailed} from "../interfaces/ITradingModule.sol";

struct StakingTradeParams {
    TradeType tradeType;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    uint16 dexId;
    bytes stakeData;
}

/**
 * Library to handle potentially illiquid withdraw requests of staking tokens where there
 * is some indeterminate lock up time before tokens can be redeemed. Examples would be withdraws
 * of staked or restaked ETH, tokens like sUSDe or stkAave which have cooldown periods before they
 * can be withdrawn.
 *
 * Primarily, this library tracks the withdraw request and an associated identifier for the withdraw
 * request. It also allows for the withdraw request to be "tokenized" so that shares of the withdraw
 * request can be liquidated.
 */
abstract contract AbstractWithdrawRequestManager is IWithdrawRequestManager {
    using SafeERC20 for ERC20;
    using TypeConvert for uint256;

    address public override immutable YIELD_TOKEN;
    address public override immutable WITHDRAW_TOKEN;
    address public override immutable STAKING_TOKEN;

    mapping(address => bool) public override isApprovedVault;
    // vault => account => withdraw request
    mapping(address => mapping(address => WithdrawRequest)) internal s_accountWithdrawRequest;
    mapping(uint256 => SplitWithdrawRequest) internal s_splitWithdrawRequest;

    constructor(address _withdrawToken, address _yieldToken, address _stakingToken) {
        WITHDRAW_TOKEN = _withdrawToken;
        YIELD_TOKEN = _yieldToken;
        STAKING_TOKEN = _stakingToken;
    }

    modifier onlyOwner() {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        _;
    }

    // TODO: do we really need this?
    modifier onlyApprovedVault() {
        if (!isApprovedVault[msg.sender]) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Returns the status of a withdraw request
    function getWithdrawRequest(address vault, address account) public view returns (WithdrawRequest memory w, SplitWithdrawRequest memory s) {
        w = s_accountWithdrawRequest[vault][account];
        s = s_splitWithdrawRequest[w.requestId];
    }

    /// @inheritdoc IWithdrawRequestManager
    function setApprovedVault(address vault, bool isApproved) external override onlyOwner {
        isApprovedVault[vault] = isApproved;
        emit ApprovedVault(vault, isApproved);
    }

    /// @inheritdoc IWithdrawRequestManager
    function stakeTokens(address depositToken, uint256 amount, bytes calldata data) external override onlyApprovedVault returns (uint256 yieldTokensMinted) {
        uint256 initialYieldTokenBalance = ERC20(YIELD_TOKEN).balanceOf(address(this));
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        (uint256 stakeTokenAmount, bytes memory stakeData) = _preStakingTrade(depositToken, amount, data);
        _stakeTokens(stakeTokenAmount, stakeData);

        yieldTokensMinted = ERC20(YIELD_TOKEN).balanceOf(address(this)) - initialYieldTokenBalance;
        ERC20(YIELD_TOKEN).safeTransfer(msg.sender, yieldTokensMinted);
    }

    /// @inheritdoc IWithdrawRequestManager
    function initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesAmount,
        bytes calldata data
    ) external override onlyApprovedVault returns (uint256 requestId) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[msg.sender][account];
        if (accountWithdraw.requestId != 0) revert ExistingWithdrawRequest(msg.sender, account, accountWithdraw.requestId);

        // Receive the requested amount of yield tokens from the approved vault.
        ERC20(YIELD_TOKEN).transferFrom(msg.sender, address(this), yieldTokenAmount);

        requestId = _initiateWithdrawImpl(account, yieldTokenAmount, data);
        accountWithdraw.requestId = requestId;
        accountWithdraw.hasSplit = false;
        accountWithdraw.yieldTokenAmount = yieldTokenAmount.toUint120();
        accountWithdraw.sharesAmount = sharesAmount.toUint120();

        emit InitiateWithdrawRequest(account, yieldTokenAmount, sharesAmount, requestId);
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeAndRedeemWithdrawRequest(
        address account,
        uint256 withdrawYieldTokenAmount,
        uint256 sharesToBurn
    ) external override onlyApprovedVault returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[msg.sender][account];
        if (accountWithdraw.requestId == 0) return (0, false);

        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, accountWithdraw);

        if (finalized) {
            // Allows for partial withdrawal of yield tokens
            if (withdrawYieldTokenAmount < accountWithdraw.yieldTokenAmount) {
                _splitPartialWithdrawRequest(accountWithdraw, tokensWithdrawn);
                tokensWithdrawn = tokensWithdrawn * withdrawYieldTokenAmount / accountWithdraw.yieldTokenAmount;
                accountWithdraw.sharesAmount -= sharesToBurn.toUint120();
                accountWithdraw.yieldTokenAmount -= withdrawYieldTokenAmount.toUint120();
            } else {
                require(accountWithdraw.yieldTokenAmount == withdrawYieldTokenAmount);
                delete s_accountWithdrawRequest[msg.sender][account];
            }

            ERC20(WITHDRAW_TOKEN).safeTransfer(msg.sender, tokensWithdrawn);
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function finalizeRequestManual(
        address vault,
        address account
    ) external override returns (uint256 tokensWithdrawn, bool finalized) {
        WithdrawRequest storage accountWithdraw = s_accountWithdrawRequest[vault][account];
        if (accountWithdraw.requestId == 0) revert NoWithdrawRequest(vault, account);

        (tokensWithdrawn, finalized) = _finalizeWithdraw(account, accountWithdraw);
        if (finalized) _splitPartialWithdrawRequest(accountWithdraw, tokensWithdrawn);
    }

    function _splitPartialWithdrawRequest(WithdrawRequest storage accountWithdraw, uint256 tokensWithdrawn) internal {
        // If the account has not split, we store the total tokens withdrawn in the split withdraw
        // request. When the account does exit, they will skip `_finalizeWithdrawImpl`
        if (!accountWithdraw.hasSplit) {
            s_splitWithdrawRequest[accountWithdraw.requestId] = SplitWithdrawRequest({
                totalYieldTokenAmount: accountWithdraw.yieldTokenAmount,
                totalWithdraw: tokensWithdrawn.toUint120(),
                finalized: true
            });

            accountWithdraw.hasSplit = true;
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function splitWithdrawRequest(
        address _from,
        address _to,
        uint256 sharesAmount
    ) external override onlyApprovedVault {
        if (_from == _to) revert InvalidWithdrawRequestSplit();

        WithdrawRequest storage w = s_accountWithdrawRequest[msg.sender][_from];
        if (w.requestId == 0) return;

        // Create a new split withdraw request
        if (!w.hasSplit) {
            SplitWithdrawRequest storage s = s_splitWithdrawRequest[w.requestId];
            // Safety check to ensure that the split withdraw request is not active, split withdraw
            // requests are never deleted. This presumes that all withdraw request ids are unique.
            require(s.finalized == false && s.totalYieldTokenAmount == 0);
            s_splitWithdrawRequest[w.requestId].totalYieldTokenAmount = w.yieldTokenAmount;
        }

        // Ensure that no withdraw request gets overridden, the _to account always receives their withdraw
        // request in the account withdraw slot. All storage is updated prior to changes to the `w` storage
        // variable below.
        WithdrawRequest storage toWithdraw = s_accountWithdrawRequest[msg.sender][_to];
        if (toWithdraw.requestId != 0 && toWithdraw.requestId != w.requestId) {
            revert ExistingWithdrawRequest(msg.sender, _to, toWithdraw.requestId);
        }

        toWithdraw.requestId = w.requestId;
        toWithdraw.hasSplit = true;

        if (w.sharesAmount < sharesAmount) {
            // This should never occur given the checks below.
            revert InvalidWithdrawRequestSplit();
        } else if (w.sharesAmount == sharesAmount) {
            // If the resulting vault shares is zero, then delete the request. The _from account's
            // withdraw request is fully transferred to _to. In this case, the _to account receives
            // the full amount of the _from account's withdraw request.
            toWithdraw.yieldTokenAmount = toWithdraw.yieldTokenAmount + w.yieldTokenAmount;
            toWithdraw.sharesAmount = toWithdraw.sharesAmount + w.sharesAmount;
            delete s_accountWithdrawRequest[msg.sender][_from];
        } else {
            // In this case, the amount of yield tokens is transferred from one account to the other.
            uint256 yieldTokenAmount = w.yieldTokenAmount * sharesAmount / w.sharesAmount;
            toWithdraw.yieldTokenAmount = (toWithdraw.yieldTokenAmount + yieldTokenAmount).toUint120();
            toWithdraw.sharesAmount = (toWithdraw.sharesAmount + sharesAmount).toUint120();
            w.yieldTokenAmount = (w.yieldTokenAmount - yieldTokenAmount).toUint120();
            w.sharesAmount = (w.sharesAmount - sharesAmount).toUint120();
            w.hasSplit = true;
        }
    }

    /// @inheritdoc IWithdrawRequestManager
    function rescueTokens(
        address cooldownHolder, address token, address receiver, uint256 amount
    ) external override onlyOwner {
        ClonedCoolDownHolder(cooldownHolder).rescueTokens(ERC20(token), receiver, amount);
    }

    /// @notice Finalizes a withdraw request and updates the account required to determine how many
    /// tokens the account has a claim over.
    function _finalizeWithdraw(
        address account,
        WithdrawRequest memory w
    ) internal returns (uint256 tokensWithdrawn, bool finalized) {
        SplitWithdrawRequest memory s;
        if (w.hasSplit) {
            s = s_splitWithdrawRequest[w.requestId];

            // If the split request was already finalized in a different transaction
            // then return the values here and we can short circuit the withdraw impl
            if (s.finalized) {
                return (
                    uint256(s.totalWithdraw) * uint256(w.yieldTokenAmount) / uint256(s.totalYieldTokenAmount),
                    true
                );
            }
        }

        // These values are the total tokens claimed from the withdraw request, does not
        // account for potential splitting.
        (tokensWithdrawn, finalized) = _finalizeWithdrawImpl(account, w.requestId);

        if (w.hasSplit && finalized) {
            s.totalWithdraw = tokensWithdrawn.toUint120();
            s.finalized = true;
            s_splitWithdrawRequest[w.requestId] = s;

            tokensWithdrawn = uint256(s.totalWithdraw) * uint256(w.yieldTokenAmount) / uint256(s.totalYieldTokenAmount);
        } else if (!finalized) {
            // No tokens claimed if not finalized
            require(tokensWithdrawn == 0);
        }
    }


    /// @notice Required implementation to begin the withdraw request
    /// @return requestId some identifier of the withdraw request
    function _initiateWithdrawImpl(
        address account,
        uint256 yieldTokenAmount,
        bytes calldata data
    ) internal virtual returns (uint256 requestId);

    /// @notice Required implementation to finalize the withdraw
    /// @return tokensWithdrawn total tokens claimed as a result of the withdraw, does not
    /// necessarily represent the tokens that go to the account if the request has been
    /// split due to liquidation
    /// @return finalized returns true if the withdraw has been finalized
    function _finalizeWithdrawImpl(address account, uint256 requestId) internal virtual returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice Required implementation to stake the deposit token to the yield token
    function _stakeTokens(uint256 amount, bytes memory stakeData) internal virtual;

    function _preStakingTrade(address depositToken, uint256 depositAmount, bytes calldata data) internal returns (uint256 amountBought, bytes memory stakeData) {
        if (depositToken == STAKING_TOKEN) {
            amountBought = depositAmount;
            stakeData = data;
        } else {
            StakingTradeParams memory params = abi.decode(data, (StakingTradeParams));
            stakeData = params.stakeData;

            (/* */, amountBought) = _executeTrade(Trade({
                tradeType: params.tradeType,
                sellToken: depositToken,
                buyToken: STAKING_TOKEN,
                amount: depositAmount,
                exchangeData: params.exchangeData,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp
            }), params.dexId);
        }
    }

    /// @dev Can be used to delegate call to the TradingModule's implementation in order to execute a trade
    function _executeTrade(
        Trade memory trade,
        uint16 dexId
    ) internal returns (uint256 amountSold, uint256 amountBought) {
        (bool success, bytes memory result) = nProxy(payable(address(TRADING_MODULE))).getImplementation()
            .delegatecall(abi.encodeWithSelector(TRADING_MODULE.executeTrade.selector, dexId, trade));
        if (!success) revert TradeFailed();
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    function getWithdrawRequestValue(
        address vault,
        address account,
        address asset,
        uint256 shares
    ) external view override returns (bool hasRequest, uint256 valueInAsset) {
        WithdrawRequest memory w = s_accountWithdrawRequest[vault][account];
        if (w.requestId == 0) return (false, 0);

        SplitWithdrawRequest memory s = s_splitWithdrawRequest[w.requestId];

        int256 tokenRate;
        uint256 tokenAmount;
        uint256 tokenDecimals;
        uint256 assetDecimals = ERC20(asset).decimals();
        if (s.finalized) {
            // If finalized the withdraw request is locked to the tokens withdrawn
            (tokenRate, /* */) = TRADING_MODULE.getOraclePrice(WITHDRAW_TOKEN, asset);
            tokenDecimals = ERC20(WITHDRAW_TOKEN).decimals();
            tokenAmount = (uint256(w.yieldTokenAmount) * uint256(s.totalWithdraw)) / uint256(s.totalYieldTokenAmount);
        } else {
            // Otherwise we use the yield token rate
            (tokenRate, /* */) = TRADING_MODULE.getOraclePrice(YIELD_TOKEN, asset);
            tokenDecimals = ERC20(YIELD_TOKEN).decimals();
            tokenAmount = w.yieldTokenAmount;
        }

        // The trading module always returns a positive rate in 18 decimals so we can safely
        // cast to uint256
        uint256 totalValue = (uint256(tokenRate) * tokenAmount * (10 ** assetDecimals)) /
            ((10 ** tokenDecimals) * 1e18);
        // NOTE: returns the normalized value given the shares input
        return (true, totalValue * shares / w.sharesAmount);
    }

}