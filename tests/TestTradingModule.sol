// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/trading/TradingModule.sol";
import "../src/interfaces/ITradingModule.sol";

IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

contract TradeContract {
    function executeTrade(
        uint16 dexId,
        Trade calldata trade
    )
        external
        payable
        returns (uint256 amountSold, uint256 amountBought)
    {
        address implementation = nProxy(payable(address(Deployments.TRADING_MODULE))).getImplementation();
        bytes memory result =
            _delegateCall(implementation, abi.encodeWithSelector(ITradingModule.executeTrade.selector, dexId, trade));
        (amountSold, amountBought) = abi.decode(result, (uint256, uint256));
    }

    function _delegateCall(address target, bytes memory data) internal returns (bytes memory result) {
        bool success;
        (success, result) = target.delegatecall(data);
        if (!success) {
            assembly {
                // Copy the return data to memory
                returndatacopy(0, 0, returndatasize())
                // Revert with the return data
                revert(0, returndatasize())
            }
        }
    }
}

contract TestTradingModule is Test {
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = 23_949_179;
    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);

    ITradingModule public tradingModule = Deployments.TRADING_MODULE;
    TradeContract public tradeContract;

    function setUp() public virtual {
        vm.createSelectFork(RPC_URL, FORK_BLOCK);
        address impl = address(new TradingModule());
        tradeContract = new TradeContract();

        ITradingModule.TokenPermissions memory permissions = ITradingModule.TokenPermissions({
            allowSell: true,
            dexFlags: uint32(1 << uint8(DexId.CURVE_V2)) | uint32(1 << uint8(DexId.UNISWAP_V2))
                | uint32(1 << uint8(DexId.UNISWAP_V3)) | uint32(1 << uint8(DexId.ZERO_EX)),
            tradeTypeFlags: uint32(1 << uint8(TradeType.EXACT_IN_SINGLE))
                | uint32(1 << uint8(TradeType.EXACT_OUT_SINGLE))
        });
        vm.startPrank(owner);
        tradingModule.setTokenPermissions(address(tradeContract), address(USDT), permissions);
        nProxy(payable(address(tradingModule))).upgradeTo(impl);
        vm.stopPrank();
    }

    function test_onlyOwnerCanQueueOperations() public {
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert(ITradingModule.Unauthorized.selector);
        tradingModule.queueOperation(tradingModule.setMaxOracleFreshness.selector, abi.encode(1000));
        vm.stopPrank();
    }

    function test_mustQueue_setMaxOracleFreshness() public {
        assertEq(tradingModule.maxOracleFreshnessInSeconds(), 90_000);

        vm.startPrank(owner);
        vm.expectRevert("Insufficient timelock");
        tradingModule.setMaxOracleFreshness(1000);

        tradingModule.queueOperation(tradingModule.setMaxOracleFreshness.selector, abi.encode(1000));
        vm.warp(block.timestamp + 1 days + 1 seconds);
        tradingModule.setMaxOracleFreshness(1000);

        assertEq(tradingModule.maxOracleFreshnessInSeconds(), 1000);
        vm.stopPrank();
    }

    function test_mustQueue_setPriceOracle() public {
        address token = address(0x1234567890123456789012345678901234567890);
        address oracle = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

        vm.startPrank(owner);
        vm.expectRevert("Insufficient timelock");
        tradingModule.setPriceOracle(token, AggregatorV2V3Interface(address(oracle)));

        tradingModule.queueOperation(
            tradingModule.setPriceOracle.selector, abi.encode(token, AggregatorV2V3Interface(address(oracle)))
        );
        vm.warp(block.timestamp + 1 days + 1 seconds);
        tradingModule.setPriceOracle(token, AggregatorV2V3Interface(address(oracle)));
        (AggregatorV2V3Interface priceOracle, uint8 rateDecimals) = tradingModule.priceOracles(token);

        assertEq(address(priceOracle), address(oracle));
        assertEq(rateDecimals, 8);
        vm.stopPrank();
    }

    function test_mustQueue_setTokenPermissions() public {
        address sender = makeAddr("sender");
        address token = makeAddr("token");
        ITradingModule.TokenPermissions memory permissions = ITradingModule.TokenPermissions({
            allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 1
        });

        vm.startPrank(owner);
        vm.expectRevert("Insufficient timelock");
        tradingModule.setTokenPermissions(sender, token, permissions);

        tradingModule.queueOperation(tradingModule.setTokenPermissions.selector, abi.encode(sender, token, permissions));
        vm.warp(block.timestamp + 1 days + 1 seconds);
        tradingModule.setTokenPermissions(sender, token, permissions);
        (bool allowSell, uint32 dexFlags, uint32 tradeTypeFlags) = tradingModule.tokenWhitelist(sender, token);
        assertEq(allowSell, true);
        assertEq(dexFlags, permissions.dexFlags);
        assertEq(tradeTypeFlags, permissions.tradeTypeFlags);
        vm.stopPrank();
    }

    function test_mustQueue_upgradeTo() public {
        address newImplementation = address(new TradingModule());

        vm.startPrank(owner);
        vm.expectRevert("Insufficient timelock");
        nProxy(payable(address(tradingModule))).upgradeToAndCall(newImplementation, "");

        tradingModule.queueOperation(nProxy.upgradeToAndCall.selector, abi.encode(newImplementation, ""));
        vm.warp(block.timestamp + 1 days + 1 seconds);
        nProxy(payable(address(tradingModule))).upgradeToAndCall(newImplementation, "");

        assertEq(nProxy(address(tradingModule)).getImplementation(), newImplementation);
    }

    function test_getOraclePrice() public { }

    function test_executeTrade_RevertsIf_InsufficientPermissions() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000,
            limit: 1000,
            deadline: block.timestamp + 1 days,
            exchangeData: bytes("")
        });

        vm.expectRevert(ITradingModule.InsufficientPermissions.selector);
        tradeContract.executeTrade(uint16(DexId.CAMELOT_V3), trade);
    }

    function test_executeTrade_RevertsIf_SellTokenEqualsBuyToken() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(USDT),
            amount: 1000,
            limit: 1000,
            deadline: block.timestamp + 1 days,
            exchangeData: bytes("")
        });

        vm.expectRevert(ITradingModule.SellTokenEqualsBuyToken.selector);
        tradeContract.executeTrade(uint16(DexId.CURVE_V2), trade);
    }

    function test_executeTrade_RevertsIf_InvalidDex() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000,
            limit: 1000,
            deadline: block.timestamp + 1 days,
            exchangeData: bytes("")
        });

        vm.expectRevert(ITradingModule.UnknownDEX.selector);
        tradeContract.executeTrade(uint16(DexId.UNISWAP_V2), trade);
    }

    function test_executeTrade_RevertsIf_ExactOutTrade() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_OUT_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000,
            limit: 1000,
            deadline: block.timestamp + 1 days,
            exchangeData: bytes("")
        });

        vm.expectRevert(InvalidTrade.selector);
        tradeContract.executeTrade(uint16(DexId.CURVE_V2), trade);

        vm.expectRevert(InvalidTrade.selector);
        tradeContract.executeTrade(uint16(DexId.UNISWAP_V3), trade);

        vm.expectRevert(InvalidTrade.selector);
        tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);
    }

    function test_executeTrade_RevertsIf_HasInsufficientSellTokens() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000e6,
            limit: 1e18,
            deadline: block.timestamp + 1 days,
            exchangeData: abi.encode(UniV3SingleData({ fee: 300 }))
        });

        vm.expectRevert(abi.encodeWithSelector(ITradingModule.PreValidationExactIn.selector, 1000e6, 0));
        tradeContract.executeTrade(uint16(DexId.UNISWAP_V3), trade);
    }

    function test_executeTrade_RevertsIf_BuyOrSellTokenIsETH() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(0),
            amount: 1000e6,
            limit: 1e18,
            deadline: block.timestamp + 1 days,
            exchangeData: abi.encode(UniV3SingleData({ fee: 300 }))
        });

        vm.expectRevert();
        tradeContract.executeTrade(uint16(DexId.UNISWAP_V3), trade);
    }

    function test_executeTrade_RevertsIf_BuyLimitIsNotMet() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000e6,
            limit: 1e18,
            deadline: block.timestamp + 1 days,
            exchangeData: abi.encode(UniV3SingleData({ fee: 3000 }))
        });

        deal(address(USDT), address(tradeContract), 1000e6);
        vm.expectRevert();
        tradeContract.executeTrade(uint16(DexId.UNISWAP_V3), trade);
    }

    function test_executeTrade_CurveV2_ExactInSingle() public { }

    function test_executeTrade_CurveV2_ExactInBatch() public { }

    function test_executeTrade_UniV3_ExactInSingle() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000e6,
            limit: 0.3e18,
            deadline: block.timestamp + 1 days,
            exchangeData: abi.encode(UniV3SingleData({ fee: 3000 }))
        });

        deal(address(USDT), address(tradeContract), 1000e6);
        (uint256 amountSold, uint256 amountBought) = tradeContract.executeTrade(uint16(DexId.UNISWAP_V3), trade);

        assertEq(amountSold, 1000e6);
        assertGt(amountBought, 0.3e18);
        assertEq(USDT.balanceOf(address(tradeContract)), 0);
        assertEq(Deployments.WETH.balanceOf(address(tradeContract)), amountBought);
    }

    function test_executeTrade_UniV3_ExactInBatch() public { }

    function test_executeTrade_ZeroEx_RevertsIf_TargetIsZeroExProxy() public { }

    function test_executeTrade_ZeroEx_RevertsIf_SellTokenIsNotTheSellToken() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 999e6,
            limit: 0,
            deadline: block.timestamp,
            exchangeData: hex"2213bc0b000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece000000000000000000000000dac27f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003841fff991f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000048a4a8660b2a21800000000000000000000000000000000000000000000000000000000000000a0eb82fe3541b8a288707f64160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018422ce6ede000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000693344e600000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cdac17f958d2ee523a2206206994597c13d831ec700000064c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008434ee90ca000000000000000000000000f5c4f3dc02c3fb9279495a8fef7b0741da956157000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000496090d731351aa00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        });

        deal(address(USDT), address(tradeContract), 1000e6);
        vm.expectRevert("Invalid Token");
        tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);
    }

    function test_executeTrade_ZeroEx_RevertsIf_AmountDiffersFromTheAmountToSell() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 999e6,
            limit: 0,
            deadline: block.timestamp,
            exchangeData: hex"2213bc0b000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003841fff991f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000048a4a8660b2a21800000000000000000000000000000000000000000000000000000000000000a0eb82fe3541b8a288707f64160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018422ce6ede000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000693344e600000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cdac17f958d2ee523a2206206994597c13d831ec700000064c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008434ee90ca000000000000000000000000f5c4f3dc02c3fb9279495a8fef7b0741da956157000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000496090d731351aa00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        });

        deal(address(USDT), address(tradeContract), 1010e6);
        vm.expectRevert("Amount Delta");
        tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);

        trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1010e6,
            limit: 0,
            deadline: block.timestamp,
            exchangeData: hex"2213bc0b000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003841fff991f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000048a4a8660b2a21800000000000000000000000000000000000000000000000000000000000000a0eb82fe3541b8a288707f64160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018422ce6ede000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000693344e600000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cdac17f958d2ee523a2206206994597c13d831ec700000064c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008434ee90ca000000000000000000000000f5c4f3dc02c3fb9279495a8fef7b0741da956157000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000496090d731351aa00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        });

        vm.expectRevert("Amount Delta");
        tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);
    }

    function test_executeTrade_ZeroEx() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 1000e6,
            limit: 0,
            deadline: block.timestamp,
            exchangeData: hex"2213bc0b000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003841fff991f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000048a4a8660b2a21800000000000000000000000000000000000000000000000000000000000000a0eb82fe3541b8a288707f64160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018422ce6ede000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000693344e600000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cdac17f958d2ee523a2206206994597c13d831ec700000064c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008434ee90ca000000000000000000000000f5c4f3dc02c3fb9279495a8fef7b0741da956157000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000496090d731351aa00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        });

        deal(address(USDT), address(tradeContract), 1000e6);
        (uint256 amountSold, uint256 amountBought) = tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);

        assertEq(amountSold, 1000e6);
        assertGt(amountBought, 0.3e18);
        assertEq(USDT.balanceOf(address(tradeContract)), 0);
        assertEq(Deployments.WETH.balanceOf(address(tradeContract)), amountBought);
    }

    function test_executeTrade_ZeroEx_sellEntireBalance() public {
        Trade memory trade = Trade({
            tradeType: TradeType.EXACT_IN_SINGLE,
            sellToken: address(USDT),
            buyToken: address(Deployments.WETH),
            amount: 999.5e6,
            limit: 0,
            deadline: block.timestamp,
            // This is generated with an amount of 1000e6
            exchangeData: hex"2213bc0b000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece00000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000003841fff991f0000000000000000000000002e234dae75c793f67a35089c9d99245e1c58470b000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000000000048a4a8660b2a21800000000000000000000000000000000000000000000000000000000000000a0eb82fe3541b8a288707f64160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018422ce6ede000000000000000000000000207e1074858a7e78f17002075739ed2745dbaece0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000693344e600000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002cdac17f958d2ee523a2206206994597c13d831ec700000064c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008434ee90ca000000000000000000000000f5c4f3dc02c3fb9279495a8fef7b0741da956157000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000496090d731351aa00000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        });

        deal(address(USDT), address(tradeContract), 999.5e6);
        (uint256 amountSold, uint256 amountBought) = tradeContract.executeTrade(uint16(DexId.ZERO_EX), trade);

        assertEq(amountSold, 999.5e6);
        assertGt(amountBought, 0.3e18);
        assertEq(USDT.balanceOf(address(tradeContract)), 0);
        assertEq(Deployments.WETH.balanceOf(address(tradeContract)), amountBought);
    }
}

/*

curl -X GET "https://api.0x.org/swap/allowance-holder/quote?chainId=1&sellToken=0xdAC17F958D2ee523a2206206994597C13D831ec7&buyToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&sellAmount=1000000000&taker=0x2e234DAe75C793f67A35089C9d99245E1C58470b"  -H "0x-api-key: $ZERO_EX_API_KEY" -H "0x-version: v2" -H "Accept: application/json" -H "Content-Type: application/json" | jq ".transaction.data"

*/