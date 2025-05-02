// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestMorphoYieldStrategy.sol";

contract TestDilutionAttack is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");

    ERC20 public w;
    MockOracle public o;
    IYieldStrategy public y;
    ERC20 public asset;
    uint256 public defaultDeposit;
    uint256 public defaultBorrow;

    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant IRM = address(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC);

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
    }

    function setupYieldStrategy() public {
        w = new MockWrapperERC20(ERC20(asset));
        if (asset == USDC) {
            o = new MockOracle(1e18);
        } else {
            (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
            o = new MockOracle(ethOracle.latestAnswer() * 1e18 / 1e8);
        }

        y = new MockYieldStrategy(
            owner,
            address(asset),
            address(w),
            0.0010e18, // 0.1% fee rate
            IRM,
            0.915e18 // 91.5% LTV
        );
        defaultDeposit = asset == USDC ? 10_000e6 : 10e18;
        defaultBorrow = asset == USDC ? 90_000e6 : 90e18;

        TimelockUpgradeableProxy proxy = new TimelockUpgradeableProxy(
            owner, address(y), abi.encodeWithSelector(Initializable.initialize.selector,
            abi.encode("name", "symbol", owner))
        );
        y = IYieldStrategy(address(proxy));

        asset = ERC20(y.asset());

        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(address(w), AggregatorV2V3Interface(address(o)));

        // USDC whale
        vm.startPrank(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);
        USDC.transfer(msg.sender, 100_000e6);
        USDC.transfer(owner, 15_000_000e6);
        vm.stopPrank();

        // Deal WETH
        deal(address(WETH), owner, 1_500_000e18);
        vm.prank(owner);
        WETH.transfer(msg.sender, 250_000e18);

        vm.startPrank(owner);
        asset.approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(y.marketParams(), 1_000_000 * 10 ** asset.decimals(), 0, owner, "");
        vm.stopPrank();
    }

    function _enterPosition(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        if (!MORPHO.isAuthorized(user, address(y))) MORPHO.setAuthorization(address(y), true);
        asset.approve(address(y), depositAmount);
        y.enterPosition(user, depositAmount, borrowAmount, bytes(""));
        vm.stopPrank();
    }

    function test_dilution_attack(bool isUSDC) public {
        asset = isUSDC ? USDC : ERC20(address(WETH));

        setupYieldStrategy();

        address attacker = makeAddr("attacker");
        vm.prank(owner);
        asset.transfer(attacker, defaultDeposit + defaultBorrow + 1);

        _enterPosition(attacker, 1, 0);
        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(attacker);
        // Mint and donate wrapped tokens
        asset.approve(address(w), defaultDeposit + defaultBorrow);
        MockWrapperERC20(address(w)).deposit(defaultDeposit + defaultBorrow);
        MockWrapperERC20(address(w)).transfer(address(y), w.balanceOf(attacker));
        vm.stopPrank();

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        vm.startPrank(attacker);
        uint256 profitsWithdrawn = y.exitPosition(
            attacker,
            attacker,
            y.balanceOfShares(attacker),
            0,
            bytes("")
        );
        vm.stopPrank();
        // NOTE: the attacker will lose money on the donation since some of it will be allocated to the
        // virtual shares and some will accrue to fees
        assertLe(profitsWithdrawn, defaultDeposit + defaultBorrow);
    }


}