// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequestImpl.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/staking/EtherFi.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/interfaces/ITradingModule.sol";

contract TestStakingStrategy is TestMorphoYieldStrategy {
    EtherFiWithdrawRequestManager public manager;
    TestWithdrawRequest public withdrawRequest;

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory redeemData) {
        uint24 fee = 500;
        return abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.UNISWAP_V3),
            exchangeData: abi.encode((fee))
        }));
    }

    function getWithdrawRequestData(
        address /* user */,
        uint256 /* shares */
    ) internal pure virtual returns (bytes memory withdrawRequestData) {
        return bytes("");
    }

    function finalizeWithdrawRequest(address user) internal {
        (WithdrawRequest memory w, /* */) = manager.getWithdrawRequest(address(y), user);
        withdrawRequest.finalizeWithdrawRequest(w.requestId);
    }

    function deployYieldStrategy() internal override {
        manager = new EtherFiWithdrawRequestManager(owner);
        y = new EtherFiStaking(
            owner,
            0.0010e18, // 0.1% fee rate
            address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            0.915e18, // 91.5% LTV
            manager
        );
        // weETH
        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 100e18;
        defaultBorrow = 900e18;

        vm.startPrank(owner);
        manager.setApprovedVault(address(y), true);

        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            // UniswapV3, EXACT_IN_SINGLE, EXACT_IN_BATCH
            { allowSell: true, dexFlags: 4, tradeTypeFlags: 5 }
        ));
        vm.stopPrank();

        withdrawRequest = new TestEtherFiWithdrawRequest();
    }

    function test_enterPosition_RevertsIf_ExistingWithdrawRequest() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));

        asset.approve(address(y), defaultDeposit);

        vm.expectRevert();
        y.enterPosition(msg.sender, defaultDeposit, defaultBorrow, bytes(""));
        vm.stopPrank();
    }

    function test_initiateWithdrawRequest_RevertIf_InsufficientCollateral() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);

        vm.startPrank(msg.sender);
        bytes memory data = getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender));
        vm.expectRevert(abi.encodeWithSelector(CannotInitiateWithdraw.selector, msg.sender));
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(data);
        vm.stopPrank();
    }

    function test_exitPosition_FullWithdrawRequest() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        uint256 priceBefore = y.price();
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        uint256 priceAfter = y.price();
        assertEq(priceBefore, priceAfter, "Price changed during withdraw request");
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender),
            type(uint256).max,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender))
        );
        // TODO: this needs to clear the escrowed yield tokens
        vm.stopPrank();
    }

    function test_exitPosition_PartialWithdrawRequest() public {
        _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();
        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(msg.sender);
        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender) * 0.10e18 / 1e18,
            0,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender) * 0.10e18 / 1e18)
        );

        y.exitPosition(
            msg.sender,
            msg.sender,
            y.balanceOfShares(msg.sender) * 0.10e18 / 1e18,
            0,
            getRedeemData(msg.sender, y.balanceOfShares(msg.sender) * 0.10e18 / 1e18)
        );
        vm.stopPrank();
    }
    
    function test_withdrawRequest_FeeCollection() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        setMaxOracleFreshness();

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();

        // No fees should accrue at this point since all yield tokens are escrowed
        uint256 feesAccruedBefore = y.feesAccrued();
        vm.warp(block.timestamp + 90 days);
        uint256 feesAccruedAfter = y.feesAccrued();
        assertEq(feesAccruedBefore, feesAccruedAfter, "Fees should not have accrued");

        address staker2 = makeAddr("staker2");
        vm.prank(owner);
        asset.transfer(staker2, defaultDeposit);

        _enterPosition(staker2, defaultDeposit, defaultBorrow);

        // Fees should accrue now on the new staker's position only
        feesAccruedBefore = y.feesAccrued();
        vm.warp(block.timestamp + 90 days);
        feesAccruedAfter = y.feesAccrued();
        assertApproxEqRel(
            feesAccruedAfter - feesAccruedBefore,
            y.balanceOfShares(staker2) * 0.00025e18 / 1e18,
            0.03e18,
        "Fees should have accrued");
    }

    function test_liquidate_splitsWithdrawRequest() public {
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();

        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);

        vm.startPrank(owner);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(owner);
        uint256 sharesToLiquidator = y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        uint256 assetAfter = asset.balanceOf(owner);
        uint256 netAsset = assetBefore - assetAfter;

        assertEq(y.balanceOfShares(msg.sender), balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(owner), sharesToLiquidator);
        vm.stopPrank();

        finalizeWithdrawRequest(owner);

        vm.startPrank(owner);
        uint256 assets = y.redeem(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        assertGt(assets, netAsset);
        vm.stopPrank();
    }

    function test_liquidate_RevertsIf_LiquidatorHasCollateralBalance() public {
        _enterPosition(owner, defaultDeposit, defaultBorrow);
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        AbstractStakingStrategy(payable(address(y))).initiateWithdraw(getWithdrawRequestData(msg.sender, y.balanceOfShares(msg.sender)));
        vm.stopPrank();

        o.setPrice(o.latestAnswer() * 0.85e18 / 1e18);

        vm.startPrank(owner);
        uint256 balanceBefore = y.balanceOfShares(msg.sender);
        asset.approve(address(y), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(CannotReceiveSplitWithdrawRequest.selector));
        y.liquidate(msg.sender, balanceBefore, 0, bytes(""));
        vm.stopPrank();
    }

    function test_withdrawRequestValuation() public {
        assertEq(true, false);
    }

}
