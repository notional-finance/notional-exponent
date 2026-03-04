// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { CrossChainYieldToken } from "../CrossChainYieldToken.sol";

contract CrossChainWithdrawRequestManager is AbstractWithdrawRequestManager {
    uint256 public s_currentRequestId;
    mapping(uint256 requestId => uint256 assetsReceived) public s_assetsReceived;

    function _stakeTokens(uint256 amount, bytes memory stakeData) internal override {
        // This is done directly on the CrossChainYieldToken contract.
        revert("Not implemented");
    }

    function _initiateWithdrawImpl(
        address account,
        uint256 amountToWithdraw,
        bytes calldata data,
        address forceWithdrawFrom
    )
        internal
        override
        returns (uint256 requestId)
    {
        requestId = ++s_currentRequestId;
        // This sends a message to the other chain with an instruction to withdraw the assets
        // for the given account.
        CrossChainYieldToken(yieldToken).triggerWithdraw(requestId, account, amountToWithdraw, data, forceWithdrawFrom);
    }

    function _finalizeWithdrawImpl(
        address, /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
        tokensClaimed = CrossChainYieldToken(yieldToken).receiveWithdrawAssets(requestId);
    }

    function getKnownWithdrawTokenAmount(uint256 requestId)
        public
        view
        override
        returns (bool hasKnownAmount, uint256 amount)
    {
        amount = CrossChainYieldToken(yieldToken).s_withdrawAssetsReceived(requestId);
        hasKnownAmount = amount > 0;
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        return CrossChainYieldToken(yieldToken).s_withdrawAssetsReceived(requestId) > 0;
    }
}
