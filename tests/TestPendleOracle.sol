// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/oracles/PendlePTOracle.sol";
import "../src/interfaces/IPendle.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/utils/Constants.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV2V3Interface, TRADING_MODULE} from "../src/interfaces/ITradingModule.sol";

contract TestPendleOracle is Test {
    PendlePTOracle public oracle;
    IPMarket public pendleMarket;
    ERC20 public ptToken;
    ERC20 public syToken; 
    ERC20 public tokenInSy;
    ERC20 public tokenOutSy;
    address public marketAddress;
    
    string RPC_URL = vm.envString("RPC_URL");
    // uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");
    uint256 FORK_BLOCK = 23334000;
    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);

    function setUp() public {
        // Fork mainnet for testing
        uint256 forkId = vm.createFork(RPC_URL, FORK_BLOCK);
        vm.selectFork(forkId);

        // Set up Pendle contracts - using sUSDe PT market as example
        marketAddress = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7; // sUSDe PT market
        pendleMarket = IPMarket(marketAddress);
        
        // Read tokens from the market
        (address _syToken, address _ptToken, /* yt */) = pendleMarket.readTokens();
        syToken = ERC20(_syToken);
        ptToken = ERC20(_ptToken);
        
        // Get sy redemption token (for sUSDe market, this would be sUSDe)
        tokenInSy = ERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3); // USDe
        tokenOutSy = ERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497); // sUSDe
        
        // Get base to USD oracle from trading module
        (AggregatorV2V3Interface baseToUSDOracle, /* */) = TRADING_MODULE.priceOracles(address(tokenInSy));
        
        console.log("Market Address:", marketAddress);
        console.log("SY Token:", address(syToken));
        console.log("PT Token:", address(ptToken));
        console.log("tokenInSy Token:", address(tokenInSy));
        console.log("Base to USD Oracle:", address(baseToUSDOracle));
        
        // Set up Pendle oracle
        oracle = new PendlePTOracle(
            marketAddress,           // pendleMarket
            baseToUSDOracle,        // baseToUSDOracle  
            false,                  // invertBase
            true,                  // useSyOracleRate
            900,                   // twapDuration (15 minutes)
            "sUSDe PT Oracle",      // description
            address(0)              // sequencerUptimeOracle (not needed for mainnet)
        );
        
        console.log("Oracle deployed:", address(oracle));
        
        // Fund this contract with tokens for testing
        deal(address(tokenInSy), address(this), 1_000_000e18); // 1M sUSDe
        // deal(address(ptToken), address(this), 1_000_000e18); // 1M PT tokens
        
        // Approve spending
        tokenInSy.approve(address(PENDLE_ROUTER), type(uint256).max);
        ptToken.approve(address(PENDLE_ROUTER), type(uint256).max);
        syToken.approve(address(PENDLE_ROUTER), type(uint256).max);
        
        setMaxOracleFreshness();
        console.log("Setup complete");
    }
    
    function setMaxOracleFreshness() internal {
        vm.prank(owner);
        TRADING_MODULE.setMaxOracleFreshness(type(uint32).max);
    }

    /// @notice Get current PT oracle price
    function getCurrentOraclePrice() internal view returns (uint256) {
        int256 answer = oracle.latestAnswer();
        require(answer > 0, "Invalid oracle price");
        return uint256(answer);
    }

    /// @notice Swap underlying token for PT tokens using Pendle router
    /// @param amountIn Amount of underlying token to swap
    /// @return netPtOut Amount of PT tokens received
    function swapTokenForPT(uint256 amountIn) internal returns (uint256 netPtOut) {
        // Create TokenInput struct
        IPRouter.TokenInput memory tokenInput;
        tokenInput.tokenIn = address(tokenInSy);
        tokenInput.netTokenIn = amountIn;
        tokenInput.tokenMintSy = address(tokenInSy);

        // Create ApproxParams for PT estimation
        IPRouter.ApproxParams memory approxParams = IPRouter.ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 1e15 // 0.1% tolerance
        });

        // Empty limit order data (no limit orders)
        IPRouter.LimitOrderData memory limitOrderData;

        // Execute swap via Pendle router
        (netPtOut, , ) = PENDLE_ROUTER.swapExactTokenForPt(
            address(this),      // receiver
            marketAddress, // market
            0,                  // minPtOut (no minimum for testing)
            approxParams,       // approximation params
            tokenInput,         // token input data
            limitOrderData      // limit order data (empty)
        );

        emit log_named_uint("Swapped tokens for PT", amountIn);
        emit log_named_uint("Received PT tokens", netPtOut);
    }

    /// @notice Swap PT tokens for underlying token using Pendle router
    /// @param ptAmount Amount of PT tokens to swap
    /// @return netTokenOut Amount of underlying tokens received
    function swapPTForToken(uint256 ptAmount) internal returns (uint256 netTokenOut) {
        // Create TokenOutput struct
        IPRouter.TokenOutput memory tokenOutput = IPRouter.TokenOutput({
            tokenOut: address(tokenOutSy),
            minTokenOut: 0, // no minimum for testing
            tokenRedeemSy: address(tokenOutSy),
            pendleSwap: address(0),
            swapData: IPRouter.SwapData({
                swapType: IPRouter.SwapType.NONE,
                extRouter: address(0),
                extCalldata: bytes(""),
                needScale: false
            })
        });

        // Empty limit order data
        IPRouter.LimitOrderData memory limitOrderData = IPRouter.LimitOrderData({
            limitRouter: address(0),
            epsSkipMarket: 0,
            normalFills: new IPRouter.FillOrderParams[](0),
            flashFills: new IPRouter.FillOrderParams[](0),
            optData: bytes("")
        });

        // Execute swap via Pendle router
        (netTokenOut, , ) = PENDLE_ROUTER.swapExactPtForToken(
            address(this),      // receiver
            address(pendleMarket), // market
            ptAmount,           // exact PT amount to swap
            tokenOutput,        // token output data
            limitOrderData      // limit order data (empty)
        );

        emit log_named_uint("Swapped PT tokens", ptAmount);
        emit log_named_uint("Received underlying tokens", netTokenOut);
    }

    function test_oracleSetup() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        
        assertTrue(roundId > 0, "Round ID should be set");
        assertTrue(answer > 0, "Oracle price should be positive");
        assertTrue(updatedAt > 0, "Updated timestamp should be set");
        assertEq(roundId, answeredInRound, "Round IDs should match");
        
        console.log("Oracle price:", uint256(answer));
    }

    /// @notice Test basic trading functionality
    function test_basicTrading() public {
        uint256 initialOraclePrice = getCurrentOraclePrice();
        uint256 swapAmount = 1e18; // 1 sUSDe

        emit log_named_uint("Initial Oracle Price", initialOraclePrice);
        emit log_named_uint("Initial sUSDe Balance", tokenInSy.balanceOf(address(this)));
        emit log_named_uint("Initial PT Balance", ptToken.balanceOf(address(this)));
        emit log_named_uint("Initial sUSDe Balance (output)", tokenOutSy.balanceOf(address(this)));

        // Swap sUSDe for PT
        uint256 ptReceived = swapTokenForPT(swapAmount);
        
        uint256 afterSwapPrice = getCurrentOraclePrice();
        emit log_named_uint("After Token->PT Swap Oracle Price", afterSwapPrice);
        emit log_named_uint("After Token->PT sUSDe Balance", tokenInSy.balanceOf(address(this)));
        emit log_named_uint("After Token->PT PT Balance", ptToken.balanceOf(address(this)));
        
        assertTrue(ptReceived > 0, "Should receive PT tokens");
        
        // Now swap PT back for sUSDe
        uint256 ptToSwap = ptReceived / 2; // Swap half of what we received
        uint256 tokensReceived = swapPTForToken(ptToSwap);
        
        uint256 finalOraclePrice = getCurrentOraclePrice();
        emit log_named_uint("Final Oracle Price", finalOraclePrice);
        emit log_named_uint("Final sUSDe Balance (input)", tokenInSy.balanceOf(address(this)));
        emit log_named_uint("Final PT Balance", ptToken.balanceOf(address(this)));
        emit log_named_uint("Final sUSDe Balance (output)", tokenOutSy.balanceOf(address(this)));
        
        assertTrue(tokensReceived > 0, "Should receive underlying tokens from PT swap");
        
        // Calculate price impact
        int256 priceChange = int256(finalOraclePrice) - int256(initialOraclePrice);
        emit log_named_int("Total Oracle Price Change", priceChange);
    }
}