// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import { Deployments } from "../mainnet/Deployments.sol";
import { Trade, TradeType, InvalidTrade } from "../../interfaces/ITradingModule.sol";

interface IAllowanceHolder {
    /// @notice Executes against `target` with the `data` payload. Prior to execution, token permits
    ///         are temporarily stored for the duration of the transaction. These permits can be
    ///         consumed by the `operator` during the execution
    /// @notice `operator` consumes the funds during its operations by calling back into
    ///         `AllowanceHolder` with `transferFrom`, consuming a token permit.
    /// @dev Neither `exec` nor `transferFrom` check that `token` contains code.
    /// @dev msg.sender is forwarded to target appended to the msg data (similar to ERC-2771)
    /// @param operator An address which is allowed to consume the token permits
    /// @param token The ERC20 token the caller has authorised to be consumed
    /// @param amount The quantity of `token` the caller has authorised to be consumed
    /// @param target A contract to execute operations with `data`
    /// @param data The data to forward to `target`
    /// @return result The returndata from calling `target` with `data`
    /// @notice If calling `target` with `data` reverts, the revert is propagated
    function exec(
        address operator,
        address token,
        uint256 amount,
        address payable target,
        bytes calldata data
    )
        external
        payable
        returns (bytes memory result);

    /// @notice The counterpart to `exec` which allows for the consumption of token permits later
    ///         during execution
    /// @dev *DOES NOT* check that `token` contains code. This function vacuously succeeds if
    ///      `token` is empty.
    /// @dev can only be called by the `operator` previously registered in `exec`
    /// @param token The ERC20 token to transfer
    /// @param owner The owner of tokens to transfer
    /// @param recipient The destination/beneficiary of the ERC20 `transferFrom`
    /// @param amount The quantity of `token` to transfer`
    /// @return true
    function transferFrom(address token, address owner, address recipient, uint256 amount) external returns (bool);
}

library ZeroExAdapter {
    uint256 internal constant MAX_SLIPPAGE = 0.001e18; // 0.1%

    /// @dev executeTrade validates pre and post trade balances and also
    /// sets and revokes all approvals. We are also only calling a trusted
    /// zero ex proxy in this case. Therefore no order validation is done
    /// to allow for flexibility.
    function getExecutionData(
        address,
        /* from */
        Trade memory trade
    )
        internal
        pure
        returns (address spender, address target, uint256 msgValue, bytes memory executionCallData)
    {
        if (trade.tradeType != TradeType.EXACT_IN_SINGLE) revert InvalidTrade();
        spender = Deployments.ZERO_EX;
        target = Deployments.ZERO_EX;
        executionCallData = trade.exchangeData;
        // Extract first 4 bytes using standard memory operations
        bytes4 selector;
        assembly {
            selector := mload(add(executionCallData, 32))
        }
        require(selector == IAllowanceHolder.exec.selector);

        // Create new bytes memory without the selector
        bytes memory callWithoutSelector = new bytes(executionCallData.length - 4);
        for (uint256 i = 0; i < callWithoutSelector.length; i++) {
            callWithoutSelector[i] = executionCallData[i + 4];
        }

        (
            /* */,
            address token,
            uint256 amount,
            address _target, /* */
        ) = abi.decode(callWithoutSelector, (address, address, uint256, address, bytes));
        // If the target is the zero ex proxy, then it is an intermediate call and is not
        // valid in this context.
        require(_target != Deployments.ZERO_EX);
        // ZeroEx only permits the sell token as an input.
        require(token == trade.sellToken, "Invalid Token");
        uint256 amountDelta = trade.amount < amount ? amount - trade.amount : trade.amount - amount;
        require(amountDelta * 1e18 / trade.amount <= MAX_SLIPPAGE, "Amount Delta");

        // msgValue is always zero
        msgValue = 0;
    }
}
