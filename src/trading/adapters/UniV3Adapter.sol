// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { Deployments } from "../mainnet/Deployments.sol";
import "../../interfaces/ITradingModule.sol";

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Uniswap V3
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

library UniV3Adapter {
    function _toAddress(bytes memory _bytes, uint256 _start) private pure returns (address) {
        // _bytes.length checked by the caller
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function _getTokenAddress(address token) internal pure returns (address) {
        return token == Deployments.ETH_ADDRESS ? address(Deployments.WETH) : token;
    }

    function _exactInSingle(address from, Trade memory trade) private pure returns (bytes memory) {
        UniV3SingleData memory data = abi.decode(trade.exchangeData, (UniV3SingleData));

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            _getTokenAddress(trade.sellToken),
            _getTokenAddress(trade.buyToken),
            data.fee,
            from,
            trade.deadline,
            trade.amount,
            trade.limit,
            0 // sqrtPriceLimitX96
        );

        return abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params);
    }

    function _exactInBatch(address from, Trade memory trade) private pure returns (bytes memory) {
        UniV3BatchData memory data = abi.decode(trade.exchangeData, (UniV3BatchData));

        // Validate path EXACT_IN = [sellToken, fee, ... buyToken]
        require(32 <= data.path.length);
        require(_toAddress(data.path, 0) == _getTokenAddress(trade.sellToken));
        require(_toAddress(data.path, data.path.length - 20) == _getTokenAddress(trade.buyToken));

        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams(data.path, from, trade.deadline, trade.amount, trade.limit);

        return abi.encodeWithSelector(ISwapRouter.exactInput.selector, params);
    }

    function getExecutionData(
        address from,
        Trade memory trade
    )
        internal
        pure
        returns (address spender, address target, uint256 msgValue, bytes memory executionCallData)
    {
        spender = address(Deployments.UNIV3_ROUTER);
        target = address(Deployments.UNIV3_ROUTER);
        // msgValue is always zero for uniswap
        msgValue = 0;

        if (trade.tradeType == TradeType.EXACT_IN_SINGLE) {
            executionCallData = _exactInSingle(from, trade);
        } else if (trade.tradeType == TradeType.EXACT_IN_BATCH) {
            executionCallData = _exactInBatch(from, trade);
        } else {
            revert InvalidTrade();
        }
    }
}
