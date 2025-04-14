// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "./TestWithdrawRequest.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/withdraws/GenericERC4626.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/Origin.sol";
import "../src/withdraws/Dinero.sol";

contract TestEtherFiWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
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
    function finalizeWithdrawRequest(uint256 requestId) public override {
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
    function finalizeWithdrawRequest(uint256 /* requestId */) public pure override {
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
    function finalizeWithdrawRequest(uint256 /* requestId */) public pure override {
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

    function finalizeWithdrawRequest(uint256 /* requestId */) public override {
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

contract TestDineropxETHWithdrawRequest is TestWithdrawRequest {

    function finalizeWithdrawRequest(uint256 requestId) public override {
        uint256 initialBatchId = requestId >> 120 & type(uint120).max;
        uint256 finalBatchId = requestId & type(uint120).max;
        address rewardRecipient = PirexETH.rewardRecipient();

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            bytes memory validator = PirexETH.batchIdToValidator(i);
            vm.record();
            PirexETH.status(validator);
            (bytes32[] memory reads, ) = vm.accesses(address(PirexETH));
            vm.store(address(PirexETH), reads[0], bytes32(uint256(IPirexETH.ValidatorStatus.Withdrawable)));

            deal(rewardRecipient, 32e18);
            vm.prank(rewardRecipient);
            PirexETH.dissolveValidator{value: 32e18}(validator);
        }
    }

    function setUp() public override {
        super.setUp();
        manager = new DineroWithdrawRequestManager(owner, address(pxETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 10e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}
