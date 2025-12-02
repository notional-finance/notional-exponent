// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Used as a No-Op withdraw request manager for ERC20s that are not staked. Allows for
/// more generic integrations with yield strategies in LP tokens where one token in the pool allows
/// for the redemption and the other token is just a generic, non redeemable ERC20.
contract GenericERC20WithdrawRequestManager is AbstractWithdrawRequestManager {
    uint256 private currentRequestId;
    mapping(uint256 requestId => uint256 tokensToWithdraw) private s_withdrawRequestTokens;

    constructor(address _erc20) AbstractWithdrawRequestManager(_erc20, _erc20, _erc20) { }

    function _initiateWithdrawImpl(
        address, /* account */
        uint256 tokensToWithdraw,
        bytes calldata, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        requestId = ++currentRequestId;
        s_withdrawRequestTokens[requestId] = tokensToWithdraw;
    }

    /* solhint-disable no-empty-blocks */
    function _stakeTokens(
        uint256,
        /* amount */
        bytes memory /* stakeData */
    )
        internal
        override
    {
        // No-op
    }
    /* solhint-enable no-empty-blocks */

    function _finalizeWithdrawImpl(
        address, /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
        tokensClaimed = s_withdrawRequestTokens[requestId];
        delete s_withdrawRequestTokens[requestId];
    }

    function canFinalizeWithdrawRequest(
        uint256 /* requestId */
    )
        public
        pure
        override
        returns (bool)
    {
        return true;
    }

    function getExchangeRate() public view override returns (uint256) {
        return 10 ** ERC20(YIELD_TOKEN).decimals();
    }
}
