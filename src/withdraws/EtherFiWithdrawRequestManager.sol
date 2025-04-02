// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETH} from "../Constants.sol";

contract EtherFiWithdrawRequestManager is AbstractWithdrawRequestManager {

    constructor(address _owner) AbstractWithdrawRequestManager(_owner, address(0), address(weETH)) { }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 weETHToUnwrap,
        bool /* isForced */,
        bytes calldata /* data */
    ) override internal returns (uint256 requestId) {
        uint256 balanceBefore = eETH.balanceOf(address(this));
        weETH.unwrap(weETHToUnwrap);
        uint256 balanceAfter = eETH.balanceOf(address(this));
        uint256 eETHReceived = balanceAfter - balanceBefore;

        eETH.approve(address(LiquidityPool), eETHReceived);
        return LiquidityPool.requestWithdraw(address(this), eETHReceived);
    }

    // function _getValueOfWithdrawRequest(
    //     uint256 totalVaultShares,
    //     uint256 weETHPrice,
    //     uint256 borrowPrecision
    // ) internal pure returns (uint256) {
    //     return (totalVaultShares * weETHPrice * borrowPrecision) /
    //         (uint256(Constants.INTERNAL_TOKEN_PRECISION) * Constants.EXCHANGE_RATE_PRECISION);
    // }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        finalized = canFinalizeWithdrawRequest(requestId);

        if (finalized) {
            uint256 balanceBefore = address(this).balance;
            WithdrawRequestNFT.claimWithdraw(requestId);
            tokensClaimed = address(this).balance - balanceBefore;
        }
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view returns (bool) {
        return (
            WithdrawRequestNFT.isFinalized(requestId) &&
            WithdrawRequestNFT.ownerOf(requestId) != address(0)
        );
    }
}


interface IweETH is IERC20 {
    function wrap(uint256 eETHDeposit) external returns (uint256 weETHMinted);
    function unwrap(uint256 weETHDeposit) external returns (uint256 eETHMinted);
}

interface ILiquidityPool {
    function deposit() external payable returns (uint256 eETHMinted);
    function requestWithdraw(address requester, uint256 eETHAmount) external returns (uint256 requestId);
}

interface IWithdrawRequestNFT {
    function ownerOf(uint256 requestId) external view returns (address);
    function isFinalized(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
    function claimWithdraw(uint256 requestId) external;
    function finalizeRequests(uint256 requestId) external;
}

IweETH constant weETH = IweETH(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
IERC20 constant eETH = IERC20(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
ILiquidityPool constant LiquidityPool = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
IWithdrawRequestNFT constant WithdrawRequestNFT = IWithdrawRequestNFT(0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c);