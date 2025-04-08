// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28;

import "forge-std/src/Test.sol";
import "../src/AbstractYieldStrategy.sol";
import "../src/oracles/AbstractCustomOracle.sol";

contract MockWrapperERC20 is ERC20 {
    ERC20 public token;

    constructor(ERC20 _token) ERC20("MockWrapperERC20", "MWE") {
        token = _token;
        _mint(msg.sender, 1000000 * 10e18);
    }

    function deposit(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 1e18 / 1e6);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        token.transfer(msg.sender, amount * 1e6 / 1e18);
    }
}

contract MockOracle is AbstractCustomOracle {

    int256 public price;

    constructor(int256 _price) AbstractCustomOracle("MockOracle", address(0)) { price = _price; }

    function setPrice(int256 _price) public {  
        price = _price;
    }

    function _calculateBaseToQuote() internal view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (0, price, block.timestamp, block.timestamp, 0);
    }
}

contract MockYieldStrategy is AbstractYieldStrategy {
    constructor(
        address _owner,
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv
    ) AbstractYieldStrategy(_owner, _asset, _yieldToken, _feeRate, _irm, _lltv) {
        ERC20(_asset).approve(address(_yieldToken), type(uint256).max);
    }

    function _preLiquidation(address liquidateAccount, address /* liquidator */) internal view override returns (uint256 maxLiquidateShares) {
        return _accountCollateralBalance(liquidateAccount);
    }

    function _mintYieldTokens(uint256 assets, address /* receiver */, bytes memory /* depositData */) internal override {
        MockWrapperERC20(yieldToken).deposit(assets);
    }

    function _redeemYieldTokens(uint256 yieldTokensToRedeem, address /* sharesOwner */, bytes memory /* redeemData */) internal override {
        MockWrapperERC20(yieldToken).withdraw(yieldTokensToRedeem);
    }
}

contract TestMorphoYieldStrategy is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    MockWrapperERC20 public w;
    MockOracle public o;
    MockYieldStrategy public y;

    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);

        w = new MockWrapperERC20(USDC);
        o = new MockOracle(1e18);
        y = new MockYieldStrategy(
            owner,
            address(USDC),
            address(w),
            0.0010e18, // 0.1% fee rate
            // Adaptive Curve IRM
            address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            0.915e18 // 91.5% LTV
        );

        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(address(w), AggregatorV2V3Interface(address(o)));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(msg.sender, 100_000e6);
        USDC.transfer(owner, 15_000_000e6);
        vm.stopPrank();

        vm.startPrank(owner);
        USDC.approve(address(MORPHO), 10_000_000e6);
        MORPHO.supply(y.marketParams(), 10_000_000e6, 0, owner, "");
        vm.stopPrank();
    }

    function _enterPosition(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        MORPHO.setAuthorization(address(y), true);
        USDC.approve(address(y), depositAmount);
        y.enterPosition(user, depositAmount, borrowAmount, bytes(""));
        vm.stopPrank();
    }

    function test_enterPosition() public { 
        _enterPosition(msg.sender, 100_000e6, 100_000e6);

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0);
        assertEq(w.balanceOf(address(y)), y.totalSupply());
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply());
        assertEq(y.balanceOf(msg.sender), 0);
        assertEq(y.balanceOfShares(msg.sender), 200_000e18);
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)));
    }

    function test_exitPosition_fullExit() public {
        _enterPosition(msg.sender, 100_000e6, 100_000e6);

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        y.exitPosition(msg.sender, msg.sender, 75_000e18, 50_000e6, bytes(""));
        vm.stopPrank();

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0, "Account has no wrapped tokens");
        assertEq(y.convertYieldTokenToShares(w.balanceOf(address(y)) - y.feesAccrued()), y.totalSupply(), "Yield token is 1-1 with collateral shares");
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply(), "Morpho has all collateral shares");
        assertEq(y.balanceOf(msg.sender), 0, "Account has no collateral shares");
        assertEq(y.balanceOfShares(msg.sender), 125_000e18, "Account has collateral shares");
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)), "Account has collateral shares on MORPHO");
    }

    function test_exitPosition_partialExit() public {
        _enterPosition(msg.sender, 10_000e6, 100_000e6);

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        y.exitPosition(msg.sender, msg.sender, y.balanceOfShares(msg.sender), type(uint256).max, bytes(""));
        vm.stopPrank();

        // Check that the yield token balance is correct
        assertEq(w.balanceOf(msg.sender), 0, "Account has no wrapped tokens");
        assertEq(y.convertYieldTokenToShares(w.balanceOf(address(y)) - y.feesAccrued()), y.totalSupply(), "Yield token is 1-1 with collateral shares");
        assertEq(y.balanceOf(address(MORPHO)), y.totalSupply(), "Morpho has all collateral shares");
        assertEq(y.balanceOf(msg.sender), 0, "Account has no collateral shares");
        assertEq(y.balanceOfShares(msg.sender), 0, "Account has collateral shares");
        assertEq(y.balanceOfShares(msg.sender), y.balanceOf(address(MORPHO)), "Account has collateral shares on MORPHO");
    }

    function test_RevertsIf_MorphoWithdrawCollateral() public {
        _enterPosition(msg.sender, 100_000e6, 100_000e6);

        vm.startPrank(msg.sender);
        MarketParams memory marketParams = y.marketParams();
        // NOTE: this is the morpho revert message
        vm.expectRevert("transfer reverted");
        MORPHO.withdrawCollateral(marketParams, 10e18, msg.sender, msg.sender);
    }

    function test_exitPosition_revertsIf_BeforeCooldownPeriod() public { 
        _enterPosition(msg.sender, 100_000e6, 100_000e6);

        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(CannotExitPositionWithinCooldownPeriod.selector));
        y.exitPosition(msg.sender, msg.sender, 100_000e6, 100_000e6, bytes(""));
        vm.stopPrank();
    }

    function test_pause_unpause() public {
        // Initially not paused
        assertEq(y.isPaused(), false);

        // Only owner can pause
        vm.prank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
        y.pause();

        vm.prank(owner);
        y.pause();
        assertEq(y.isPaused(), true);

        // Cannot perform operations while paused
        vm.prank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(Paused.selector));
        y.enterPosition(msg.sender, 100_000e6, 100_000e6, bytes(""));

        // Only owner can unpause
        vm.prank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, owner));
        y.unpause();

        vm.prank(owner);
        y.unpause();
        assertEq(y.isPaused(), false);

        // Can perform operations after unpause
        _enterPosition(msg.sender, 100_000e6, 100_000e6);
    }

    function test_setApproval() public {
        address operator = address(0x123);
        
        // Initially not approved
        assertEq(y.isApproved(msg.sender, operator), false);

        // Can set approval
        vm.prank(msg.sender);
        y.setApproval(operator, true);
        assertEq(y.isApproved(msg.sender, operator), true);

        // Can revoke approval
        vm.prank(msg.sender);
        y.setApproval(operator, false);
        assertEq(y.isApproved(msg.sender, operator), false);

        // Test that approvals work for operations
        vm.prank(msg.sender);
        y.setApproval(operator, true);
        
        // Operator can perform operations on behalf of user
        vm.prank(owner);
        USDC.transfer(operator, 100_000e6);

        vm.prank(msg.sender);
        MORPHO.setAuthorization(address(y), true);

        vm.startPrank(operator);
        USDC.approve(address(y), 100_000e6);
        y.enterPosition(msg.sender, 100_000e6, 100_000e6, bytes(""));
        vm.stopPrank();

        // Revoke approval
        vm.prank(msg.sender);
        y.setApproval(operator, false);

        // Operator can no longer perform operations
        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, operator, msg.sender));
        y.enterPosition(msg.sender, 100_000e6, 100_000e6, bytes(""));
        vm.stopPrank();
    }

    function test_setApproval_self() public {
        // Cannot approve self
        vm.startPrank(msg.sender);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, msg.sender, msg.sender));
        y.setApproval(msg.sender, true);
        vm.stopPrank();
    }

    function test_collectFees() public {
        _enterPosition(msg.sender, 10_000e6, 90_000e6);
        assertEq(y.totalSupply(), 100_000e18);

        uint256 yieldTokensPerShare0 = y.convertSharesToYieldToken(1e18);
        vm.warp(block.timestamp + 365 days);
        uint256 yieldTokensPerShare1 = y.convertSharesToYieldToken(1e18);
        assertLt(yieldTokensPerShare1, yieldTokensPerShare0);

        assertEq(y.feesAccrued(), 100e18);

        vm.prank(owner);
        y.collectFees();
        uint256 yieldTokensPerShare2 = y.convertSharesToYieldToken(1e18);

        assertEq(yieldTokensPerShare1, yieldTokensPerShare2 + 1);
        assertEq(y.feesAccrued(), 0);
        assertEq(y.convertSharesToYieldToken(y.balanceOf(owner)), 100e18);

        vm.startPrank(owner);
        uint256 assets = y.redeem(y.balanceOf(owner), "");
        assertEq(assets, 100e6);
        vm.stopPrank();
    }

    // function test_share_valuation() public {
        
    // }

    // function test_liquidate() public {
    //     _enterPosition(msg.sender, 100_000e6, 100_000e6);

    //     vm.startPrank(msg.sender);
    //     y.liquidate(msg.sender, 100_000e18, 100_000e6, bytes(""));
    //     vm.stopPrank();
    // }

    // function test_liquidate_RevertsIf_BeforeCooldownPeriod() public {
    //     _enterPosition(msg.sender, 100_000e6, 100_000e6);
    // }

    // function test_liquidate_RevertsIf_InsufficientAssetsForRepayment() public {
    //     _enterPosition(msg.sender, 100_000e6, 100_000e6);
    // }

    // function test_liquidate_RevertsIf_CalledOnMorpho() public {
    //     _enterPosition(msg.sender, 100_000e6, 100_000e6);
    // }
 
}