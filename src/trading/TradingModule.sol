// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ADDRESS_REGISTRY } from "../utils/Constants.sol";

import { Deployments } from "./mainnet/Deployments.sol";
import { UniV3Adapter } from "./adapters/UniV3Adapter.sol";
import { ZeroExAdapter } from "./adapters/ZeroExAdapter.sol";
import { CurveV2Adapter } from "./adapters/CurveV2Adapter.sol";

import { ERC20 as IERC20, TokenUtils } from "../utils/TokenUtils.sol";
import { ITradingModule, Trade, TradeType, DexId, nProxy } from "../interfaces/ITradingModule.sol";
import { AggregatorV2V3Interface } from "../interfaces/AggregatorV2V3Interface.sol";

interface NotionalProxy {
    function owner() external view returns (address);
}

/// @notice TradingModule is meant to be an upgradeable contract deployed to help Strategy Vaults
/// exchange tokens via multiple DEXes as well as receive price oracle information
contract TradingModule is UUPSUpgradeable, ITradingModule {
    using TokenUtils for IERC20;

    // Used to get the proxy address inside delegate call contexts
    ITradingModule internal immutable PROXY;

    // Grace period after a sequencer downtime has occurred
    uint256 internal constant SEQUENCER_UPTIME_GRACE_PERIOD = 1 hours;
    int256 internal constant RATE_DECIMALS = 1e18;
    uint256 internal constant OPERATION_TIMELOCK = 1 days;

    struct PriceOracle {
        AggregatorV2V3Interface oracle;
        uint8 rateDecimals;
    }

    uint256 private _unused;
    mapping(address token => PriceOracle priceOracle) public priceOracles;
    uint32 public maxOracleFreshnessInSeconds;
    mapping(address sender => mapping(address token => TokenPermissions permissions)) public tokenWhitelist;
    mapping(bytes32 operationHash => uint256 queuedAt) public operationQueue;

    constructor() {
        // Make sure we are using the correct Deployments lib
        require(Deployments.CHAIN_ID == block.chainid);
        PROXY = Deployments.TRADING_MODULE;
    }

    modifier onlyUpgradeAdmin() {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized();
        _;
    }

    function _hashOperation(bytes4 sig, bytes memory data) private pure returns (bytes32) {
        return keccak256(abi.encode(sig, data));
    }

    function _checkOperationQueue(bytes32 operationHash) private {
        uint256 queuedAt = operationQueue[operationHash];
        require(0 < queuedAt && queuedAt + OPERATION_TIMELOCK < block.timestamp, "Insufficient timelock");
        delete operationQueue[operationHash];
    }

    function queueOperation(bytes4 sig, bytes memory data) external onlyUpgradeAdmin {
        bytes32 operationHash = _hashOperation(sig, data);
        require(operationQueue[operationHash] == 0);
        operationQueue[operationHash] = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyUpgradeAdmin {
        _checkOperationQueue(_hashOperation(nProxy.upgradeToAndCall.selector, abi.encode(newImplementation, "")));
    }

    function setMaxOracleFreshness(uint32 newMaxOracleFreshnessInSeconds) external onlyUpgradeAdmin {
        bytes32 operationHash =
            _hashOperation(ITradingModule.setMaxOracleFreshness.selector, abi.encode(newMaxOracleFreshnessInSeconds));
        _checkOperationQueue(operationHash);

        emit MaxOracleFreshnessUpdated(maxOracleFreshnessInSeconds, newMaxOracleFreshnessInSeconds);
        maxOracleFreshnessInSeconds = newMaxOracleFreshnessInSeconds;
    }

    function setPriceOracle(address token, AggregatorV2V3Interface oracle) external override onlyUpgradeAdmin {
        bytes32 operationHash = _hashOperation(ITradingModule.setPriceOracle.selector, abi.encode(token, oracle));
        _checkOperationQueue(operationHash);

        PriceOracle storage oracleStorage = priceOracles[token];
        oracleStorage.oracle = oracle;
        oracleStorage.rateDecimals = oracle.decimals();

        emit PriceOracleUpdated(token, address(oracle));
    }

    function setTokenPermissions(
        address sender,
        address token,
        TokenPermissions calldata permissions
    )
        external
        override
        onlyUpgradeAdmin
    {
        bytes32 operationHash =
            _hashOperation(ITradingModule.setTokenPermissions.selector, abi.encode(sender, token, permissions));
        _checkOperationQueue(operationHash);

        /// @dev update these if we are adding new DEXes or types
        // Validates that the permissions being set do not exceed the max values set
        // by the token.
        for (uint32 i = uint32(DexId.CAMELOT_V3) + 1; i < 32; i++) {
            require(!_hasPermission(permissions.dexFlags, uint32(1 << i)));
        }
        for (uint32 i = uint32(TradeType.EXACT_OUT_BATCH) + 1; i < 32; i++) {
            require(!_hasPermission(permissions.tradeTypeFlags, uint32(1 << i)));
        }
        tokenWhitelist[sender][token] = permissions;
        emit TokenPermissionsUpdated(sender, token, permissions);
    }

    /// @notice Called to receive execution data for vaults that will execute trades without
    /// delegating calls to this contract
    /// @param dexId enum representing the id of the dex
    /// @param from address for the contract executing the trade
    /// @param trade trade object
    /// @return spender the address to approve for the soldToken, will be address(0) if the
    /// send token is ETH and therefore does not require approval
    /// @return target contract to execute the call against
    /// @return msgValue amount of ETH to transfer to the target, if any
    /// @return executionCallData encoded call data for the trade
    function getExecutionData(
        uint16 dexId,
        address from,
        Trade calldata trade
    )
        external
        pure
        override
        returns (address spender, address target, uint256 msgValue, bytes memory executionCallData)
    {
        return _getExecutionData(dexId, from, trade);
    }

    /// @notice Should be called via delegate call to execute a trade on behalf of the caller.
    /// @dev This method has a `payable` modifier to allow for the calling context to have a `msg.value`
    /// set, but should never refer to `msg.value` itself for any of its internal methods.
    /// @param dexId enum representing the id of the dex
    /// @param trade trade object
    /// @return amountSold amount of tokens sold
    /// @return amountBought amount of tokens purchased
    function executeTrade(
        uint16 dexId,
        Trade calldata trade
    )
        external
        payable
        override
        returns (uint256 amountSold, uint256 amountBought)
    {
        if (!PROXY.canExecuteTrade(address(this), dexId, trade)) revert InsufficientPermissions();
        if (trade.amount == 0) return (0, 0);

        (address spender, address target, uint256 msgValue, bytes memory executionData) =
            _getExecutionData(dexId, address(this), trade);

        return _executeInternal(trade, dexId, spender, target, msgValue, executionData);
    }

    function _getExecutionData(
        uint16 dexId,
        address from,
        Trade memory trade
    )
        internal
        pure
        returns (address spender, address target, uint256 msgValue, bytes memory executionCallData)
    {
        if (trade.buyToken == trade.sellToken) revert SellTokenEqualsBuyToken();

        if (DexId(dexId) == DexId.UNISWAP_V3) {
            return UniV3Adapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.ZERO_EX) {
            return ZeroExAdapter.getExecutionData(from, trade);
        } else if (DexId(dexId) == DexId.CURVE_V2) {
            return CurveV2Adapter.getExecutionData(from, trade);
        }

        revert UnknownDEX();
    }

    function _checkSequencer() private view {
        // See: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
        if (address(Deployments.SEQUENCER_UPTIME_ORACLE) != address(0)) {
            (
                /*uint80 roundID*/,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/,
                /*uint80 answeredInRound*/
            ) = Deployments.SEQUENCER_UPTIME_ORACLE.latestRoundData();
            require(answer == 0, "Sequencer Down");
            require(SEQUENCER_UPTIME_GRACE_PERIOD < block.timestamp - startedAt, "Sequencer Grace Period");
        }
    }

    /// @notice Returns the Chainlink oracle price between the baseToken and the quoteToken, the
    /// Chainlink oracles. The quote currency between the oracles must match or the conversion
    /// in this method does not work. Most Chainlink oracles are baseToken/USD pairs.
    /// @param baseToken address of the first token in the pair, i.e. USDC in USDC/DAI
    /// @param quoteToken address of the second token in the pair, i.e. DAI in USDC/DAI
    /// @return answer exchange rate in rate decimals
    /// @return decimals number of decimals in the rate, currently hardcoded to 1e18
    function getOraclePrice(
        address baseToken,
        address quoteToken
    )
        public
        view
        override
        returns (int256 answer, int256 decimals)
    {
        _checkSequencer();
        PriceOracle memory baseOracle = priceOracles[baseToken];
        PriceOracle memory quoteOracle = priceOracles[quoteToken];

        int256 baseDecimals = int256(10 ** baseOracle.rateDecimals);
        int256 quoteDecimals = int256(10 ** quoteOracle.rateDecimals);

        (
            /* */,
            int256 basePrice,
            /* */,
            uint256 bpUpdatedAt, /* */
        ) = baseOracle.oracle.latestRoundData();
        require(block.timestamp - bpUpdatedAt <= maxOracleFreshnessInSeconds);
        require(basePrice > 0);

        (
            /* */,
            int256 quotePrice,
            /* */,
            uint256 qpUpdatedAt, /* */
        ) = quoteOracle.oracle.latestRoundData();
        require(block.timestamp - qpUpdatedAt <= maxOracleFreshnessInSeconds);
        require(quotePrice > 0);

        answer = (basePrice * quoteDecimals * RATE_DECIMALS) / (quotePrice * baseDecimals);
        decimals = RATE_DECIMALS;
    }

    function _hasPermission(uint32 flags, uint32 flagID) private pure returns (bool) {
        return (flags & flagID) == flagID;
    }

    /// @notice Check if the caller is allowed to execute the provided trade object
    function canExecuteTrade(address from, uint16 dexId, Trade calldata trade) external view override returns (bool) {
        TokenPermissions memory permissions = tokenWhitelist[from][trade.sellToken];
        if (!_hasPermission(permissions.dexFlags, uint32(1 << dexId))) {
            return false;
        }
        if (!_hasPermission(permissions.tradeTypeFlags, uint32(1 << uint32(trade.tradeType)))) {
            return false;
        }
        return permissions.allowSell;
    }

    function _executeInternal(
        Trade memory trade,
        uint16,
        /* dexId */
        address spender,
        address target,
        uint256 msgValue,
        bytes memory executionData
    )
        internal
        returns (uint256 amountSold, uint256 amountBought)
    {
        // Get pre-trade token balances
        (uint256 preTradeSellBalance, uint256 preTradeBuyBalance) = _getBalances(trade);

        // Only exact in trades are supported
        require(_isExactIn(trade));
        // Make sure we have enough tokens to sell
        if (preTradeSellBalance < trade.amount) revert PreValidationExactIn(trade.amount, preTradeSellBalance);

        if (spender != address(0)) IERC20(trade.sellToken).checkApprove(spender, trade.amount);

        require(msgValue == 0);
        (bool success, bytes memory returnData) = target.call(executionData);
        if (!success) revert TradeExecution(returnData);

        // Get post-trade token balances
        (uint256 postTradeSellBalance, uint256 postTradeBuyBalance) = _getBalances(trade);

        amountSold = preTradeSellBalance - postTradeSellBalance;
        amountBought = postTradeBuyBalance - preTradeBuyBalance;

        // Ensure we received the minimum amount of tokens we expected
        if (amountBought < trade.limit) revert PostValidationExactIn(trade.limit, amountBought);
        if (spender != address(0)) IERC20(trade.sellToken).checkRevoke(spender);

        emit TradeExecuted(trade.sellToken, trade.buyToken, amountSold, amountBought);
    }

    function _getBalances(Trade memory trade) private view returns (uint256, uint256) {
        // NOTE: these calls will revert if the token is ETH. We do not support native ETH trades.
        return (IERC20(trade.sellToken).balanceOf(address(this)), IERC20(trade.buyToken).balanceOf(address(this)));
    }

    function _isExactIn(Trade memory trade) private pure returns (bool) {
        return trade.tradeType == TradeType.EXACT_IN_SINGLE || trade.tradeType == TradeType.EXACT_IN_BATCH;
    }
}
