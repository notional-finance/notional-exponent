// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "./TestWithdrawRequest.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/withdraws/GenericERC4626.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/Origin.sol";

contract TestEtherFiWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) internal override {
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(requestId);
    }

    function setUp() public override {
        super.setUp();
        manager = new EtherFiWithdrawRequestManager(owner);
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 10e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestEthenaWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) internal override {
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(requestId)));
        vm.warp(wCooldown.cooldownEnd);
    }

    function setUp() public override {
        super.setUp();
        manager = new EthenaWithdrawRequestManager(owner);
        allowedDepositTokens.push(ERC20(address(USDe)));
        deal(address(USDe), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestGenericERC4626WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 /* requestId */) internal pure override {
        return;
    }

    function setUp() public override {
        super.setUp();
        manager = new GenericERC4626WithdrawRequestManager(owner, address(sDAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestGenericERC20WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 /* requestId */) internal pure override {
        return;
    }

    function setUp() public override {
        super.setUp();
        manager = new GenericERC20WithdrawRequestManager(owner, address(DAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestOriginWithdrawRequest is TestWithdrawRequest {

    function finalizeWithdrawRequest(uint256 /* requestId */) internal override {
        uint256 claimDelay = OriginVault.withdrawalClaimDelay();
        vm.warp(block.timestamp + claimDelay);

        deal(address(WETH), address(OriginVault), 1_000e18);
        OriginVault.addWithdrawalQueueLiquidity();
    }

    function setUp() public override {
        super.setUp();
        manager = new OriginWithdrawRequestManager(owner);
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 10e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}
