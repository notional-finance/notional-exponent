// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestWithdrawRequest.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/withdraws/GenericERC4626.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/Origin.sol";
import "../src/withdraws/Dinero.sol";
import "../src/withdraws/Midas.sol";
import { sDAI, DAI } from "../src/interfaces/IEthena.sol";

contract TestEtherFiWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(requestId);
    }

    function deployManager() public override {
        manager = new EtherFiWithdrawRequestManager();
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{ value: 10e18 }();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestEthenaWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(requestId)));
        if (wCooldown.cooldownEnd > block.timestamp) {
            vm.warp(wCooldown.cooldownEnd);
        }
    }

    function deployManager() public override {
        manager = new EthenaWithdrawRequestManager();
        allowedDepositTokens.push(ERC20(address(USDe)));
        deal(address(USDe), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }

    function test_zero_cooldown_duration() public approveVaultAndStakeTokens {
        vm.startPrank(sUSDe.owner());
        sUSDe.setCooldownDuration(0);
        vm.stopPrank();

        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;

        uint256 requestId = manager.initiateWithdraw(
            address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom
        );

        assertEq(manager.canFinalizeWithdrawRequest(requestId), true);

        // Now we should be able to finalize the withdraw request and get the full amount back
        uint256 tokensWithdrawn =
            manager.finalizeAndRedeemWithdrawRequest(address(this), initialYieldTokenBalance, sharesAmount);
        assertGt(tokensWithdrawn, 0);
        assertEq(tokensWithdrawn, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(this)));
    }
}

contract TestGenericERC4626WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(
        uint256 /* requestId */
    )
        public
        pure
        override
    {
        return;
    }

    function deployManager() public override {
        manager = new GenericERC4626WithdrawRequestManager(address(sDAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestGenericERC20WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(
        uint256 /* requestId */
    )
        public
        pure
        override
    {
        return;
    }

    function deployManager() public override {
        manager = new GenericERC20WithdrawRequestManager(address(DAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestWrappedOriginWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(
        uint256 /* requestId */
    )
        public
        override
    {
        uint256 claimDelay = OriginVault.withdrawalClaimDelay();
        vm.warp(block.timestamp + claimDelay);

        deal(address(WETH), address(OriginVault), 2000e18);
        OriginVault.addWithdrawalQueueLiquidity();
    }

    function deployManager() public override {
        manager = new OriginWithdrawRequestManager(address(wOETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{ value: 10e18 }();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestOriginWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(
        uint256 /* requestId */
    )
        public
        override
    {
        uint256 claimDelay = OriginVault.withdrawalClaimDelay();
        vm.warp(block.timestamp + claimDelay);

        deal(address(WETH), address(OriginVault), 2000e18);
        OriginVault.addWithdrawalQueueLiquidity();
    }

    function deployManager() public override {
        manager = new OriginWithdrawRequestManager(address(oETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{ value: 10e18 }();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestDinero_pxETH_WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        DineroCooldownHolder holder = DineroCooldownHolder(payable(address(uint160(requestId))));
        uint256 initialBatchId = holder.initialBatchId();
        uint256 finalBatchId = holder.finalBatchId();
        address rewardRecipient = PirexETH.rewardRecipient();

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            bytes memory validator = PirexETH.batchIdToValidator(i);
            vm.record();
            PirexETH.status(validator);
            (bytes32[] memory reads,) = vm.accesses(address(PirexETH));
            vm.store(address(PirexETH), reads[0], bytes32(uint256(IPirexETH.ValidatorStatus.Withdrawable)));

            deal(rewardRecipient, 32e18);
            vm.prank(rewardRecipient);
            PirexETH.dissolveValidator{ value: 32e18 }(validator);
        }
    }

    function deployManager() public override {
        manager = new DineroWithdrawRequestManager(address(pxETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{ value: 45e18 }();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestDinero_apxETH_WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        DineroCooldownHolder holder = DineroCooldownHolder(payable(address(uint160(requestId))));
        uint256 initialBatchId = holder.initialBatchId();
        uint256 finalBatchId = holder.finalBatchId();
        address rewardRecipient = PirexETH.rewardRecipient();

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            bytes memory validator = PirexETH.batchIdToValidator(i);
            vm.record();
            PirexETH.status(validator);
            (bytes32[] memory reads,) = vm.accesses(address(PirexETH));
            vm.store(address(PirexETH), reads[0], bytes32(uint256(IPirexETH.ValidatorStatus.Withdrawable)));

            deal(rewardRecipient, 32e18);
            vm.prank(rewardRecipient);
            PirexETH.dissolveValidator{ value: 32e18 }(validator);
        }
    }

    function deployManager() public override {
        manager = new DineroWithdrawRequestManager(address(apxETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{ value: 45e18 }();
        depositCallData = "";
        withdrawCallData = "";
    }
}

abstract contract TestMidas_WithdrawRequest is TestWithdrawRequest {
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address tokenIn;
    IDepositVault depositVault;
    IRedemptionVault redemptionVault;
    bytes32 referrerId = bytes32(uint256(0));
    address constant USDC_WHALE = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant GREENLISTED_ROLE_OPERATOR = 0x4f75307888fD06B16594cC93ED478625AD65EEea;

    function finalizeWithdrawRequest(uint256 requestId) public override {
        vm.record();
        IRedemptionVault.Request memory request = redemptionVault.redeemRequests(requestId);
        if (request.status == MidasRequestStatus.Processed) return;
        (bytes32[] memory reads,) = vm.accesses(address(redemptionVault));

        vm.store(
            address(redemptionVault),
            reads[3],
            bytes32(uint256(MidasRequestStatus.Processed)) << 160
                | bytes32(uint256(vm.load(address(redemptionVault), reads[3])))
        );

        // This will now calculate the exact amount of tokens that will be withdrawn.
        (, uint256 amount) = manager.getKnownWithdrawTokenAmount(requestId);
        if (tokenIn == address(USDC)) {
            vm.prank(USDC_WHALE);
            USDC.transfer(address(this), amount);
            vm.stopPrank();
        } else if (tokenIn == address(WETH)) {
            deal(address(WETH), address(this), amount);
        }
        ERC20(tokenIn).transfer(address(manager), amount);
    }

    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_034_331;
    }

    function deployManager() public override {
        withdrawCallData = "";
        manager = new MidasWithdrawRequestManager(tokenIn, depositVault, redemptionVault, referrerId);
        allowedDepositTokens.push(ERC20(tokenIn));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(address(this), 1_000_000e6);
        vm.stopPrank();

        deal(address(WETH), address(this), 200e18);
    }

    function postDeploySetup() internal override {
        address greenlistedAccount = makeAddr("greenlisted_account");
        address staker1 = makeAddr("staker1");
        address staker2 = makeAddr("staker2");

        depositCallData = abi.encode(greenlistedAccount, 0);

        vm.startPrank(GREENLISTED_ROLE_OPERATOR);
        MidasAccessControl.grantRole(MIDAS_GREENLISTED_ROLE, address(manager));
        MidasAccessControl.grantRole(MIDAS_GREENLISTED_ROLE, greenlistedAccount);
        MidasAccessControl.grantRole(MIDAS_GREENLISTED_ROLE, address(this));
        MidasAccessControl.grantRole(MIDAS_GREENLISTED_ROLE, staker1);
        MidasAccessControl.grantRole(MIDAS_GREENLISTED_ROLE, staker2);
        vm.stopPrank();
    }

    function test_deposit_RevertsIf_Account_Not_Greenlisted() public approveVault {
        vm.skip(!depositVault.greenlistEnabled());
        address staker = makeAddr("staker");
        uint256 amount = allowedDepositTokens[0].balanceOf(address(this));
        ERC20(allowedDepositTokens[0]).approve(address(manager), amount);

        vm.expectRevert("Midas: account is not greenlisted");
        manager.stakeTokens(address(allowedDepositTokens[0]), amount, abi.encode(staker, 0));
    }

    function test_redeem_RevertsIf_Account_Not_Greenlisted() public approveVaultAndStakeTokens {
        vm.skip(!redemptionVault.greenlistEnabled());
        address staker = makeAddr("staker");
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.transfer(staker, yieldToken.balanceOf(address(this)));

        uint256 amount = yieldToken.balanceOf(address(this));
        vm.expectRevert("Midas: account is not greenlisted");
        manager.initiateWithdraw(staker, amount, amount, withdrawCallData, forceWithdrawFrom);
    }
}

contract TestMidas_mHYPER_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        depositVault = IDepositVault(0xbA9FD2850965053Ffab368Df8AA7eD2486f11024);
        redemptionVault = IRedemptionVault(0x6Be2f55816efd0d91f52720f096006d63c366e98);
    }
}

contract TestMidas_mAPOLLO_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        depositVault = IDepositVault(0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921);
        redemptionVault = IRedemptionVault(0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0);
    }
}

contract TestMidas_mF_ONE_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        depositVault = IDepositVault(0x41438435c20B1C2f1fcA702d387889F346A0C3DE);
        redemptionVault = IRedemptionVault(0x44b0440e35c596e858cEA433D0d82F5a985fD19C);
    }
}

contract TestMidas_mHyperETH_WETH_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(WETH);
        depositVault = IDepositVault(0x57B3Be350C777892611CEdC93BCf8c099A9Ecdab);
        redemptionVault = IRedemptionVault(0x15f724b35A75F0c28F352b952eA9D1b24e348c57);
    }
}
