// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/src/console2.sol";

contract GenericERC4626WithdrawRequestManager is AbstractWithdrawRequestManager {

    uint256 private currentRequestId;
    mapping(uint256 => uint256) private s_withdrawRequestShares;

    constructor(address _owner, address _erc4626)
        AbstractWithdrawRequestManager(_owner, IERC4626(_erc4626).asset(), _erc4626) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 sharesToWithdraw,
        bool /* isForced */,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        requestId = ++currentRequestId;
        s_withdrawRequestShares[requestId] = sharesToWithdraw;
    }

    function _stakeTokens(address depositToken, uint256 amount, bytes calldata /* data */) internal override {
        require(depositToken == address(withdrawToken), "Invalid deposit token");
        IERC20(depositToken).approve(address(yieldToken), amount);
        IERC4626(yieldToken).deposit(amount, address(this));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        uint256 sharesToRedeem = s_withdrawRequestShares[requestId];
        delete s_withdrawRequestShares[requestId];
        tokensClaimed = IERC4626(yieldToken).redeem(sharesToRedeem, address(this), address(this));
        finalized = true;
    }

    function canFinalizeWithdrawRequest(uint256 /* requestId */) public pure override returns (bool) {
        return true;
    }
}