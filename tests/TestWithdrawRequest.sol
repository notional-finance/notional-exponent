// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "../src/utils/Errors.sol";
import "../src/utils/Constants.sol";
import "../src/withdraws/IWithdrawRequestManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract TestWithdrawRequest is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    IWithdrawRequestManager public manager;
    ERC20[] public allowedDepositTokens;
    bytes public depositCallData;
    bytes public withdrawCallData;
    address public owner;

    function setUp() public virtual {
        owner = makeAddr("owner");

        vm.createSelectFork(RPC_URL, FORK_BLOCK);
    }

    modifier approveVault() {
        vm.prank(owner);
        manager.setApprovedVault(address(this), true);
        _;
    }

    modifier approveVaultAndStakeTokens() {
        vm.prank(owner);
        manager.setApprovedVault(address(this), true);
        vm.prank(address(this));
        allowedDepositTokens[0].approve(address(manager), allowedDepositTokens[0].balanceOf(address(this)));
        manager.stakeTokens(address(allowedDepositTokens[0]), allowedDepositTokens[0].balanceOf(address(this)), depositCallData);
        _;
    }

    function finalizeWithdrawRequest(uint256 requestId) public virtual;

    function test_setApprovedVault() public {
        vm.prank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(0x123)));
        manager.setApprovedVault(address(this), true);

        vm.prank(owner);
        manager.setApprovedVault(address(this), true);
    }

    function test_onlyApprovedVault() public {
        address caller = makeAddr("caller");
        vm.startPrank(caller);
        assertEq(manager.isApprovedVault(caller), false);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.stakeTokens(address(allowedDepositTokens[0]), 10e18, depositCallData);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.initiateWithdraw(caller, 100, false, depositCallData);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.finalizeAndRedeemWithdrawRequest(caller);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.splitWithdrawRequest(caller, caller, 100);

        vm.stopPrank();
    }

    function test_stakeTokens() public approveVault {
        for (uint256 i = 0; i < allowedDepositTokens.length; i++) {
            ERC20 depositToken = allowedDepositTokens[i];
            // Deposits come from this contract
            vm.prank(address(this));
            depositToken.approve(address(manager), depositToken.balanceOf(address(this)));
            manager.stakeTokens(address(depositToken), depositToken.balanceOf(address(this)), depositCallData);
        }
    }

    function test_initiateWithdraw() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        vm.expectEmit(true, true, true, false, address(manager));
        emit IWithdrawRequestManager.InitiateWithdrawRequest(address(this), false, initialYieldTokenBalance, 0);
        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        (WithdrawRequest memory request, SplitWithdrawRequest memory splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        uint256 tokensWithdrawn;
        bool finalized;
        if (!manager.canFinalizeWithdrawRequest(requestId)) {
            (tokensWithdrawn, finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
            assertEq(tokensWithdrawn, 0);
            assertEq(finalized, false);

            (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
            assertEq(request.hasSplit, false);
            assertEq(request.requestId, requestId);
            assertEq(splitRequest.totalYieldTokenAmount, 0);
            assertEq(splitRequest.totalWithdraw, 0);
            assertEq(splitRequest.finalized, false);
        }

        finalizeWithdrawRequest(requestId);

        (tokensWithdrawn, finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
        assertEq(tokensWithdrawn, ERC20(manager.withdrawToken()).balanceOf(address(this)));
        assertEq(finalized, true);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);
    }

    function test_initiateWithdraw_RevertIf_ExistingWithdrawRequest() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        vm.expectRevert(abi.encodeWithSelector(ExistingWithdrawRequest.selector, address(this), address(this), requestId));
        manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, depositCallData);
    }

    function test_initiateWithdraw_finalizeManual() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        vm.expectEmit(true, true, true, false, address(manager));
        emit IWithdrawRequestManager.InitiateWithdrawRequest(address(this), false, initialYieldTokenBalance, 0);
        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        (WithdrawRequest memory request, SplitWithdrawRequest memory splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        uint256 tokensWithdrawn;
        bool finalized;
        if (!manager.canFinalizeWithdrawRequest(requestId)) {
            (tokensWithdrawn, finalized) = manager.finalizeRequestManual(address(this), address(this));
            assertEq(tokensWithdrawn, 0);
            assertEq(finalized, false);

            (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
            assertEq(request.hasSplit, false);
            assertEq(request.requestId, requestId);
            assertEq(splitRequest.totalYieldTokenAmount, 0);
            assertEq(splitRequest.totalWithdraw, 0);
            assertEq(splitRequest.finalized, false);
        }

        finalizeWithdrawRequest(requestId);

        (tokensWithdrawn, finalized) = manager.finalizeRequestManual(address(this), address(this));
        assertEq(finalized, true);
        // No tokens should be withdrawn, they should be held on the manager
        assertEq(0, ERC20(manager.withdrawToken()).balanceOf(address(this)));
        assertEq(tokensWithdrawn, ERC20(manager.withdrawToken()).balanceOf(address(manager)));

        // The split request should now be finalized
        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, tokensWithdrawn);
        assertEq(splitRequest.finalized, true);

        // Now we should be able to finalize the withdraw request via the vault
        (tokensWithdrawn, finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
        assertEq(tokensWithdrawn, ERC20(manager.withdrawToken()).balanceOf(address(this)));
        assertEq(0, ERC20(manager.withdrawToken()).balanceOf(address(manager)));
        assertEq(finalized, true);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);
    }

    function test_initiateWithdraw_AfterFinalize() public approveVaultAndStakeTokens {
        // Test that we can initiate a withdraw after a request has been finalized
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);
        finalizeWithdrawRequest(requestId);

        (/* */, bool finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
        assertEq(finalized, true);

        // Stake new tokens
        allowedDepositTokens[0].approve(address(manager), allowedDepositTokens[0].balanceOf(address(this)));
        manager.stakeTokens(address(allowedDepositTokens[0]), allowedDepositTokens[0].balanceOf(address(this)), depositCallData);

        // Initiate a new withdraw
        uint256 newYieldTokenBalance = yieldToken.balanceOf(address(this));
        yieldToken.approve(address(manager), newYieldTokenBalance);
        manager.initiateWithdraw(address(this), newYieldTokenBalance, false, withdrawCallData);
    }

    function test_splitWithdrawRequest(bool useManualFinalize) public approveVaultAndStakeTokens {
        address to = makeAddr("to");
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        // Split the withdraw request in half
        // TODO: test with the full amount
        uint256 splitAmount = initialYieldTokenBalance / 2;
        manager.splitWithdrawRequest(address(this), to, splitAmount);

        (WithdrawRequest memory request, SplitWithdrawRequest memory splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, splitAmount);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        // Finalize the split request
        finalizeWithdrawRequest(requestId);

        bool finalized;
        uint256 tokensWithdrawn;
        if (useManualFinalize) {
            (tokensWithdrawn, finalized) = manager.finalizeRequestManual(address(this), address(this));

            (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount);
            assertEq(request.hasSplit, true);
            assertEq(request.requestId, requestId);
            assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
            assertApproxEqAbs(splitRequest.totalWithdraw, tokensWithdrawn * 2, 1);
            assertEq(splitRequest.finalized, true);
        } else {
            (tokensWithdrawn, finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
            assertEq(finalized, true);

            (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, 0);
            assertEq(request.hasSplit, false);
            assertEq(request.requestId, 0);
            assertEq(splitRequest.totalYieldTokenAmount, 0);
            assertEq(splitRequest.totalWithdraw, 0);
            assertEq(splitRequest.finalized, false);
        }

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, splitAmount);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertApproxEqAbs(splitRequest.totalWithdraw, tokensWithdrawn * 2, 1);
        assertEq(splitRequest.finalized, true);

        (/* */, finalized) = manager.finalizeAndRedeemWithdrawRequest(to);
        assertEq(finalized, true);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);
    }

    function test_splitWithdrawRequest_fullAmount(bool useManualFinalize) public approveVaultAndStakeTokens {
        address to = makeAddr("to");
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        // Split the full request
        manager.splitWithdrawRequest(address(this), to, initialYieldTokenBalance);

        (WithdrawRequest memory request, SplitWithdrawRequest memory splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        // Finalize the split request
        finalizeWithdrawRequest(requestId);

        (/* */, bool finalized) = manager.finalizeAndRedeemWithdrawRequest(address(this));
        assertEq(finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        uint256 tokensClaimed;
        if (useManualFinalize) {
            (tokensClaimed, finalized) = manager.finalizeRequestManual(address(this), to);
            assertEq(finalized, true);
        }
        (tokensClaimed, finalized) = manager.finalizeAndRedeemWithdrawRequest(to);
        assertEq(finalized, true);
        assertEq(tokensClaimed, ERC20(manager.withdrawToken()).balanceOf(address(this)));

        (request, splitRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.hasSplit, false);
        assertEq(request.requestId, 0);
        assertEq(splitRequest.totalYieldTokenAmount, 0);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);
    }

    function test_splitWithdrawRequest_RevertIf_FromAndToAreSame() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        // Split the withdraw request
        vm.expectRevert(abi.encodeWithSelector(InvalidWithdrawRequestSplit.selector));
        manager.splitWithdrawRequest(address(this), address(this), initialYieldTokenBalance / 2);
    }


    function test_splitWithdrawRequest_SplitSameRequestTwice() public approveVaultAndStakeTokens {
        address addr1 = makeAddr("addr1");
        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, false, withdrawCallData);

        // Split the request once
        uint256 splitAmount = initialYieldTokenBalance / 10;
        manager.splitWithdrawRequest(address(this), addr1, splitAmount);

        (WithdrawRequest memory request, SplitWithdrawRequest memory splitRequest) = manager.getWithdrawRequest(address(this), addr1);
        assertEq(request.yieldTokenAmount, splitAmount);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        // Split the withdraw request again
        manager.splitWithdrawRequest(address(this), addr1, splitAmount);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), addr1);
        assertEq(request.yieldTokenAmount, splitAmount * 2);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);

        (request, splitRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount * 2);
        assertEq(request.hasSplit, true);
        assertEq(request.requestId, requestId);
        assertEq(splitRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(splitRequest.totalWithdraw, 0);
        assertEq(splitRequest.finalized, false);
    }

    function test_splitWithdrawRequest_RevertIf_ExistingSplitWithdrawRequest() public approveVaultAndStakeTokens {
        address staker1 = makeAddr("staker1");
        address staker2 = makeAddr("staker2");
        address splitStaker = makeAddr("splitStaker");

        ERC20 yieldToken = ERC20(manager.yieldToken());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 withdrawAmount = yieldToken.balanceOf(address(this)) / 4;

        uint256 request1 = manager.initiateWithdraw(staker1, withdrawAmount, false, withdrawCallData);
        manager.initiateWithdraw(staker2, withdrawAmount, false, withdrawCallData);

        // Split the request once
        uint256 splitAmount = withdrawAmount / 10;
        manager.splitWithdrawRequest(staker1, splitStaker, splitAmount);

        // Reverts when splitStaker tries to take the split of a different request
        vm.expectRevert(abi.encodeWithSelector(ExistingWithdrawRequest.selector, address(this), splitStaker, request1));
        manager.splitWithdrawRequest(staker2, splitStaker, splitAmount);
    }

}
