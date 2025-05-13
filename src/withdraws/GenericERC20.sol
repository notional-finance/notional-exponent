// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GenericERC20WithdrawRequestManager is AbstractWithdrawRequestManager {

    uint256 private currentRequestId;
    mapping(uint256 => uint256) private s_withdrawRequestTokens;

    constructor(address _erc20) AbstractWithdrawRequestManager(_erc20, _erc20, _erc20) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 tokensToWithdraw,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        requestId = ++currentRequestId;
        s_withdrawRequestTokens[requestId] = tokensToWithdraw;
    }

    function _stakeTokens(uint256 /* amount */, bytes memory /* stakeData */) internal override {
        // No-op
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        tokensClaimed = s_withdrawRequestTokens[requestId];
        delete s_withdrawRequestTokens[requestId];
        finalized = true;
    }

    function canFinalizeWithdrawRequest(uint256 /* requestId */) public pure override returns (bool) {
        return true;
    }
}