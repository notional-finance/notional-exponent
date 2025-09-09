// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/interfaces/Errors.sol";
import "../src/utils/Constants.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";
import "../src/interfaces/IWithdrawRequestManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract TestWithdrawRequest is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    IWithdrawRequestManager public manager;
    ERC20[] public allowedDepositTokens;
    bytes public depositCallData;
    bytes public withdrawCallData;
    address public forceWithdrawFrom;
    address public owner;

    function deployManager() public virtual;

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        owner = ADDRESS_REGISTRY.upgradeAdmin();
        deployManager();
        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            address(manager), abi.encodeWithSelector(Initializable.initialize.selector, bytes(""))
        );

        manager = IWithdrawRequestManager(address(proxy));
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
        manager.initiateWithdraw(caller, 100, 100, depositCallData, address(0));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.finalizeAndRedeemWithdrawRequest(caller, 100, 100);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, caller));
        manager.tokenizeWithdrawRequest(caller, caller, 100);

        vm.stopPrank();
    }

    function test_stakeTokens() public approveVault {
        for (uint256 i = 0; i < allowedDepositTokens.length; i++) {
            ERC20 depositToken = allowedDepositTokens[i];
            // Deposits come from this contract
            vm.prank(address(this));
            depositToken.approve(address(manager), depositToken.balanceOf(address(this)));

            assertGt(depositToken.balanceOf(address(this)), 0, "Deposit token balance is 0");

            uint256 initialYieldTokenBalance = ERC20(manager.YIELD_TOKEN()).balanceOf(address(this));
            uint256 yieldTokensMinted = manager.stakeTokens(address(depositToken), depositToken.balanceOf(address(this)), depositCallData);
            uint256 finalYieldTokenBalance = ERC20(manager.YIELD_TOKEN()).balanceOf(address(this));

            assertGt(yieldTokensMinted, 0, "Yield tokens minted is 0");
            if (address(depositToken) != address(manager.YIELD_TOKEN())) {
                assertEq(
                    yieldTokensMinted, finalYieldTokenBalance - initialYieldTokenBalance,
                    "Yield tokens minted is not equal to the balance of the yield token"
                );
            }
        }
    }

    function test_initiateWithdraw(bool partialWithdraw) public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;

        vm.expectEmit(true, true, true, false, address(manager));
        emit IWithdrawRequestManager.InitiateWithdrawRequest(address(this), address(this), initialYieldTokenBalance, sharesAmount, 0);
        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom);

        (WithdrawRequest memory request, TokenizedWithdrawRequest memory tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.sharesAmount, sharesAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        uint256 tokensWithdrawn;
        if (!manager.canFinalizeWithdrawRequest(requestId)) {
            // Revert if the request is not finalized
            vm.expectRevert();
            tokensWithdrawn = manager.finalizeAndRedeemWithdrawRequest(
                address(this), initialYieldTokenBalance, sharesAmount
            );

            (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
            assertEq(request.sharesAmount, sharesAmount);
            assertEq(request.requestId, requestId);
            assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
            assertEq(tokenizedRequest.totalWithdraw, 0);
            assertEq(tokenizedRequest.finalized, false);
        }

        finalizeWithdrawRequest(requestId);

        uint256 yieldTokenWithdraw = partialWithdraw ? initialYieldTokenBalance / 2 : initialYieldTokenBalance;
        uint256 sharesToBurn = partialWithdraw ? sharesAmount / 2 : sharesAmount;
        // Now we should be able to finalize the withdraw request and get the full amount back
        tokensWithdrawn = manager.finalizeAndRedeemWithdrawRequest(
            address(this), yieldTokenWithdraw, sharesToBurn
        );
        assertEq(tokensWithdrawn, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(this)));

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        if (partialWithdraw) {
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance - yieldTokenWithdraw);
            assertEq(request.sharesAmount, sharesAmount - sharesToBurn);
            assertEq(request.requestId, requestId);
            assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
            assertApproxEqAbs(tokenizedRequest.totalWithdraw, tokensWithdrawn * 2, 5);
            assertEq(tokenizedRequest.finalized, true);
        } else {
            // The requests should now be empty
            assertEq(request.yieldTokenAmount, 0);
            assertEq(request.sharesAmount, 0);
            assertEq(request.requestId, 0);
            assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
            assertEq(tokenizedRequest.totalWithdraw, 0);
            assertEq(tokenizedRequest.finalized, false);
        }
    }

    function test_initiateWithdraw_RevertIf_ExistingWithdrawRequest() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom);

        vm.expectRevert(abi.encodeWithSelector(ExistingWithdrawRequest.selector, address(this), address(this), requestId));
        manager.initiateWithdraw(address(this), initialYieldTokenBalance, initialYieldTokenBalance, depositCallData, forceWithdrawFrom);
    }

    function test_initiateWithdraw_finalizeManual() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), yieldToken.balanceOf(address(this)));
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;
        vm.expectEmit(true, true, true, false, address(manager));
        emit IWithdrawRequestManager.InitiateWithdrawRequest(address(this), address(this), initialYieldTokenBalance, sharesAmount, 0);
        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom);

        (WithdrawRequest memory request, TokenizedWithdrawRequest memory tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.sharesAmount, sharesAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        uint256 tokensWithdrawn;
        if (!manager.canFinalizeWithdrawRequest(requestId)) {
            // If cannot finalize then no tokens withdrawn
            vm.expectRevert();
            tokensWithdrawn = manager.finalizeRequestManual(address(this), address(this));

            (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
            assertEq(request.sharesAmount, sharesAmount);
            assertEq(request.requestId, requestId);
            assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
            assertEq(tokenizedRequest.totalWithdraw, 0);
            assertEq(tokenizedRequest.finalized, false);
        }

        finalizeWithdrawRequest(requestId);

        tokensWithdrawn = manager.finalizeRequestManual(address(this), address(this));
        // No tokens should be withdrawn, they should be held on the manager
        assertEq(0, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(this)));
        assertEq(tokensWithdrawn, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(manager)));

        // The split request should now be finalized
        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.sharesAmount, sharesAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, tokensWithdrawn);
        assertEq(tokenizedRequest.finalized, true);

        // Now we should be able to finalize the withdraw request via the vault
        tokensWithdrawn = manager.finalizeAndRedeemWithdrawRequest(
            address(this), initialYieldTokenBalance, sharesAmount
        );
        assertEq(tokensWithdrawn, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(this)));
        assertEq(0, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(manager)));

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.sharesAmount, 0);
        assertEq(request.requestId, 0);
        assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);
    }

    function test_initiateWithdraw_AfterFinalize() public approveVaultAndStakeTokens {
        // Test that we can initiate a withdraw after a request has been finalized
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom);
        finalizeWithdrawRequest(requestId);

        manager.finalizeAndRedeemWithdrawRequest(address(this), initialYieldTokenBalance, sharesAmount);

        // Stake new tokens
        allowedDepositTokens[0].approve(address(manager), allowedDepositTokens[0].balanceOf(address(this)));
        manager.stakeTokens(address(allowedDepositTokens[0]), allowedDepositTokens[0].balanceOf(address(this)), depositCallData);

        // Initiate a new withdraw
        uint256 newYieldTokenBalance = yieldToken.balanceOf(address(this));
        yieldToken.approve(address(manager), newYieldTokenBalance);
        manager.initiateWithdraw(address(this), newYieldTokenBalance, newYieldTokenBalance, withdrawCallData, forceWithdrawFrom);
    }

    function test_tokenizeWithdrawRequest(bool useManualFinalize) public approveVaultAndStakeTokens {
        address to = makeAddr("to");
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));
        uint256 sharesAmount = initialYieldTokenBalance / 2;

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, sharesAmount, withdrawCallData, forceWithdrawFrom);

        // Split the withdraw request in half
        uint256 splitAmount = sharesAmount / 2;
        manager.tokenizeWithdrawRequest(address(this), to, splitAmount);

        (WithdrawRequest memory request, TokenizedWithdrawRequest memory tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount * 2);
        assertEq(request.sharesAmount, sharesAmount - splitAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, splitAmount * 2);
        assertEq(request.sharesAmount, splitAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        // Finalize the split request
        finalizeWithdrawRequest(requestId);

        uint256 tokensWithdrawn;
        if (useManualFinalize) {
            tokensWithdrawn = manager.finalizeRequestManual(address(this), address(this));

            (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount * 2);
            assertEq(request.sharesAmount, sharesAmount - splitAmount);
            assertEq(request.requestId, requestId);
            assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
            assertApproxEqAbs(tokenizedRequest.totalWithdraw, tokensWithdrawn * 2, 5);
            assertEq(tokenizedRequest.finalized, true);
        } else {
            tokensWithdrawn = manager.finalizeAndRedeemWithdrawRequest(
                address(this), initialYieldTokenBalance - splitAmount * 2, sharesAmount - splitAmount
            );

            (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
            assertEq(request.yieldTokenAmount, 0);
            assertEq(request.requestId, 0);
            assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
            assertEq(tokenizedRequest.totalWithdraw, 0);
            assertEq(tokenizedRequest.finalized, false);
        }

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, splitAmount * 2);
        assertEq(request.sharesAmount, splitAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertApproxEqAbs(tokenizedRequest.totalWithdraw, tokensWithdrawn * 2, 5);
        assertEq(tokenizedRequest.finalized, true);

        manager.finalizeAndRedeemWithdrawRequest(to, splitAmount * 2, splitAmount);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.requestId, 0);
        assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);
    }

    function test_tokenizeWithdrawRequest_fullAmount(bool useManualFinalize) public approveVaultAndStakeTokens {
        address to = makeAddr("to");
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, initialYieldTokenBalance, withdrawCallData, forceWithdrawFrom);

        // Split the full request
        manager.tokenizeWithdrawRequest(address(this), to, initialYieldTokenBalance);

        (WithdrawRequest memory request, TokenizedWithdrawRequest memory tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.sharesAmount, 0);
        assertEq(request.requestId, 0);
        assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.sharesAmount, initialYieldTokenBalance);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        // Finalize the split request
        finalizeWithdrawRequest(requestId);

        manager.finalizeAndRedeemWithdrawRequest(
            address(this), initialYieldTokenBalance, initialYieldTokenBalance
        );

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.sharesAmount, 0);
        assertEq(request.requestId, 0);
        assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance);
        assertEq(request.sharesAmount, initialYieldTokenBalance);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        uint256 tokensClaimed;
        if (useManualFinalize) {
            tokensClaimed = manager.finalizeRequestManual(address(this), to);
        }
        tokensClaimed = manager.finalizeAndRedeemWithdrawRequest(to, initialYieldTokenBalance, initialYieldTokenBalance);
        assertEq(tokensClaimed, ERC20(manager.WITHDRAW_TOKEN()).balanceOf(address(this)));

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), to);
        assertEq(request.yieldTokenAmount, 0);
        assertEq(request.sharesAmount, 0);
        assertEq(request.requestId, 0);
        assertEq(tokenizedRequest.totalYieldTokenAmount, 0);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);
    }

    function test_tokenizeWithdrawRequest_RevertIf_FromAndToAreSame() public approveVaultAndStakeTokens {
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        manager.initiateWithdraw(address(this), initialYieldTokenBalance, initialYieldTokenBalance, withdrawCallData, forceWithdrawFrom);

        vm.expectRevert();
        manager.tokenizeWithdrawRequest(address(this), address(this), initialYieldTokenBalance / 2);
    }


    function test_tokenizeWithdrawRequest_TokenizeSameRequestTwice() public approveVaultAndStakeTokens {
        address addr1 = makeAddr("addr1");
        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 initialYieldTokenBalance = yieldToken.balanceOf(address(this));

        uint256 requestId = manager.initiateWithdraw(address(this), initialYieldTokenBalance, initialYieldTokenBalance, withdrawCallData, forceWithdrawFrom);

        // Split the request once
        uint256 splitAmount = initialYieldTokenBalance / 10;
        manager.tokenizeWithdrawRequest(address(this), addr1, splitAmount);

        (WithdrawRequest memory request, TokenizedWithdrawRequest memory tokenizedRequest) = manager.getWithdrawRequest(address(this), addr1);
        assertEq(request.yieldTokenAmount, splitAmount);
        assertEq(request.sharesAmount, splitAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount);
        assertEq(request.sharesAmount, initialYieldTokenBalance - splitAmount);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        // Split the withdraw request again
        manager.tokenizeWithdrawRequest(address(this), addr1, splitAmount);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), addr1);
        assertEq(request.yieldTokenAmount, splitAmount * 2);
        assertEq(request.sharesAmount, splitAmount * 2);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);

        (request, tokenizedRequest) = manager.getWithdrawRequest(address(this), address(this));
        assertEq(request.yieldTokenAmount, initialYieldTokenBalance - splitAmount * 2);
        assertEq(request.sharesAmount, initialYieldTokenBalance - splitAmount * 2);
        assertEq(request.requestId, requestId);
        assertEq(tokenizedRequest.totalYieldTokenAmount, initialYieldTokenBalance);
        assertEq(tokenizedRequest.totalWithdraw, 0);
        assertEq(tokenizedRequest.finalized, false);
    }

    function test_tokenizeWithdrawRequest_RevertIf_ExistingtokenizeWithdrawRequest() public approveVaultAndStakeTokens {
        address staker1 = makeAddr("staker1");
        address staker2 = makeAddr("staker2");
        address splitStaker = makeAddr("splitStaker");

        ERC20 yieldToken = ERC20(manager.YIELD_TOKEN());
        yieldToken.approve(address(manager), type(uint256).max);
        uint256 withdrawAmount = yieldToken.balanceOf(address(this)) / 4;

        uint256 request1 = manager.initiateWithdraw(staker1, withdrawAmount, withdrawAmount, withdrawCallData, forceWithdrawFrom);
        manager.initiateWithdraw(staker2, withdrawAmount, withdrawAmount, withdrawCallData, forceWithdrawFrom);

        // Split the request once
        uint256 splitAmount = withdrawAmount / 10;
        manager.tokenizeWithdrawRequest(staker1, splitStaker, splitAmount);

        // Reverts when splitStaker tries to take the split of a different request
        vm.expectRevert(abi.encodeWithSelector(ExistingWithdrawRequest.selector, address(this), splitStaker, request1));
        manager.tokenizeWithdrawRequest(staker2, splitStaker, splitAmount);
    }

    function test_getExchangeRate() public approveVaultAndStakeTokens {
        uint256 exchangeRate = manager.getExchangeRate();
        assertGe(exchangeRate, 1e18);
    }

}
