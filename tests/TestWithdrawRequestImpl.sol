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
import "../src/interfaces/IMidas.sol";
import "../src/withdraws/Pareto.sol";
import "../src/withdraws/InfiniFi.sol";
import { USDC } from "../src/utils/Constants.sol";
import { sDAI, DAI } from "../src/interfaces/IEthena.sol";
import { IdleKeyring } from "../src/interfaces/IPareto.sol";

address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

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
    address tokenIn;
    address tokenOut;
    IDepositVault depositVault;
    IRedemptionVault redemptionVault;
    address constant USDC_WHALE = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant GREENLISTED_ROLE_OPERATOR = 0x4f75307888fD06B16594cC93ED478625AD65EEea;

    function setManager(address newManager) public {
        manager = IWithdrawRequestManager(newManager);
    }

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
        if (tokenOut == address(USDC)) {
            vm.prank(USDC_WHALE);
            USDC.transfer(address(this), amount);
            vm.stopPrank();
        } else {
            deal(address(tokenOut), address(this), amount);
        }
        ERC20(tokenOut).transfer(address(manager), amount);
    }

    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_034_331;
    }

    function deployManager() public override {
        withdrawCallData = "";
        manager = new MidasWithdrawRequestManager(tokenOut, tokenIn, depositVault, redemptionVault);
        allowedDepositTokens.push(ERC20(tokenIn));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(address(this), 200_000e6);
        vm.stopPrank();

        if (tokenIn != address(USDC)) {
            deal(tokenIn, address(this), 10 * (10 ** TokenUtils.getDecimals(tokenIn)));
        }
    }

    function postDeploySetup() internal override {
        address greenlistedAccount = makeAddr("greenlisted_account");
        address staker1 = makeAddr("staker1");
        address staker2 = makeAddr("staker2");

        depositCallData = abi.encode(0);

        vm.startPrank(GREENLISTED_ROLE_OPERATOR);
        IMidasAccessControl accessControl = IMidasAccessControl(depositVault.accessControl());
        bytes32 greenlistedRole = accessControl.GREENLISTED_ROLE();
        accessControl.grantRole(greenlistedRole, address(manager));
        accessControl.grantRole(greenlistedRole, greenlistedAccount);
        accessControl.grantRole(greenlistedRole, address(this));
        accessControl.grantRole(greenlistedRole, staker1);
        accessControl.grantRole(greenlistedRole, staker2);
        vm.stopPrank();
    }
}

contract TestMidas_mHYPER_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        tokenOut = address(USDC);
        depositVault = IDepositVault(0xbA9FD2850965053Ffab368Df8AA7eD2486f11024);
        redemptionVault = IRedemptionVault(0x6Be2f55816efd0d91f52720f096006d63c366e98);
    }
}

contract TestMidas_mAPOLLO_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        tokenOut = address(USDC);
        depositVault = IDepositVault(0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921);
        redemptionVault = IRedemptionVault(0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0);
    }
}

contract TestMidas_mF_ONE_USDC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(USDC);
        tokenOut = address(USDC);
        depositVault = IDepositVault(0x41438435c20B1C2f1fcA702d387889F346A0C3DE);
        redemptionVault = IRedemptionVault(0x44b0440e35c596e858cEA433D0d82F5a985fD19C);
    }
}

contract TestMidas_mHyperETH_WETH_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(WETH);
        tokenOut = address(WETH);
        depositVault = IDepositVault(0x57B3Be350C777892611CEdC93BCf8c099A9Ecdab);
        redemptionVault = IRedemptionVault(0x15f724b35A75F0c28F352b952eA9D1b24e348c57);
    }
}

contract TestMidas_mHyperBTC_WBTC_WithdrawRequest is TestMidas_WithdrawRequest {
    constructor() {
        tokenIn = address(WBTC);
        tokenOut = address(cbBTC);
        depositVault = IDepositVault(0xeD22A9861C6eDd4f1292aeAb1E44661D5f3FE65e);
        redemptionVault = IRedemptionVault(0x16d4f955B0aA1b1570Fe3e9bB2f8c19C407cdb67);
    }
}

contract TestPareto_FalconX_WithdrawRequest is TestWithdrawRequest {
    IdleKeyring public keyring;
    IdleCDOEpochVariant public paretoVault;
    IdleCDOEpochQueue public paretoQueue;

    function setManager(address newManager) public {
        manager = IWithdrawRequestManager(newManager);
        paretoVault = IdleCDOEpochVariant(ParetoWithdrawRequestManager(newManager).paretoVault());
        paretoQueue = IdleCDOEpochQueue(ParetoWithdrawRequestManager(newManager).paretoQueue());
        keyring = IdleKeyring(paretoVault.keyring());
    }

    function finalizeWithdrawRequest(uint256 requestId) public override {
        (/* */, uint256 epoch) = ParetoWithdrawRequestManager(address(manager)).s_paretoWithdrawData(requestId);
        uint256 virtualPrice = manager.getExchangeRate();

        vm.record();
        paretoQueue.epochPendingClaims(epoch);
        (bytes32[] memory reads,) = vm.accesses(address(paretoQueue));
        vm.store(address(paretoQueue), reads[2], 0);

        vm.record();
        paretoQueue.epochWithdrawPrice(epoch);
        (reads,) = vm.accesses(address(paretoQueue));
        vm.store(address(paretoQueue), reads[2], bytes32(uint256(virtualPrice)));

        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(address(paretoQueue), 1_000_000e6);
        vm.stopPrank();
    }

    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_414_984;
    }

    function deployManager() public override {
        withdrawCallData = "";
        paretoVault = IdleCDOEpochVariant(0x433D5B175148dA32Ffe1e1A37a939E1b7e79be4d);
        paretoQueue = IdleCDOEpochQueue(0x5cC24f44cCAa80DD2c079156753fc1e908F495DC);
        keyring = IdleKeyring(paretoVault.keyring());
        manager = new ParetoWithdrawRequestManager(paretoVault, paretoQueue);
        allowedDepositTokens.push(ERC20(USDC));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(address(this), 200_000e6);
        // Used to process withdraw requests
        USDC.transfer(address(paretoQueue), 200_000e6);
        vm.stopPrank();
    }

    function postDeploySetup() internal override {
        address staker1 = makeAddr("staker1");
        address staker2 = makeAddr("staker2");

        address admin = keyring.admin();

        vm.startPrank(admin);
        keyring.setWhitelistStatus(address(manager), true);
        keyring.setWhitelistStatus(staker1, true);
        keyring.setWhitelistStatus(staker2, true);
        keyring.setWhitelistStatus(address(this), true);
        vm.stopPrank();
    }
}

contract TestInfiniFi_liUSD1w_WithdrawRequest is TestWithdrawRequest {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_414_984;
    }

    function finalizeWithdrawRequest(uint256 requestId) public override {
        InfiniFiUnwindingHolder holder = InfiniFiUnwindingHolder(payable(address(uint160(requestId))));
        uint256 s_unwindingTimestamp = holder.s_unwindingTimestamp();
        IUnwindingModule unwindingModule =
            IUnwindingModule(ILockingController(Gateway.getAddress("lockingController")).unwindingModule());
        IUnwindingModule.UnwindingPosition memory position =
            unwindingModule.positions(keccak256(abi.encode(holder, s_unwindingTimestamp)));

        vm.warp(position.toEpoch * 1 weeks + 3 days);
    }

    function deployManager() public override {
        withdrawCallData = "";
        uint32 unwindingEpochs = 1;
        address liUSD = address(0x12b004719fb632f1E7c010c6F5D6009Fb4258442);
        manager = new InfiniFiWithdrawRequestManager(liUSD, unwindingEpochs);
        allowedDepositTokens.push(ERC20(USDC));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(address(this), 200_000e6);
        vm.stopPrank();
    }
}
