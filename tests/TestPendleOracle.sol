// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/oracles/PendlePTOracle.sol";
import "../src/interfaces/IPendle.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/utils/Constants.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV2V3Interface, TRADING_MODULE } from "../src/interfaces/ITradingModule.sol";
import "../src/utils/TokenUtils.sol";

contract TestPendleOracle is Test {
    using TokenUtils for ERC20;

    PendlePTOracle public oracle;
    IPMarket public pendleMarket;
    ERC20 public ptToken;
    ERC20 public syToken;
    ERC20 public tokenInSy;
    ERC20 public tokenOutSy;
    address public marketAddress;

    string RPC_URL = vm.envString("RPC_URL");
    // uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");
    uint256 FORK_BLOCK = 23_034_483;
    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);

    function setUp() public {
        // Fork mainnet for testing
        uint256 forkId = vm.createFork(RPC_URL, FORK_BLOCK);
        vm.selectFork(forkId);

        // Set up Pendle contracts - using sUSDe PT market as example
        marketAddress = 0xA36b60A14A1A5247912584768C6e53E1a269a9F7; // sUSDe PT market
        pendleMarket = IPMarket(marketAddress);

        // Read tokens from the market
        (
            address _syToken,
            address _ptToken, /* yt */
        ) = pendleMarket.readTokens();
        syToken = ERC20(_syToken);
        ptToken = ERC20(_ptToken);

        // Get sy redemption token (for sUSDe market, this would be sUSDe)
        tokenInSy = ERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3); // USDe
        tokenOutSy = ERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497); // sUSDe

        // Get base to USD oracle from trading module
        (
            AggregatorV2V3Interface baseToUSDOracle, /* */
        ) = TRADING_MODULE.priceOracles(address(tokenInSy));

        console.log("Market Address:", marketAddress);
        console.log("SY Token:", address(syToken));
        console.log("PT Token:", address(ptToken));
        console.log("tokenInSy Token:", address(tokenInSy));
        console.log("Base to USD Oracle:", address(baseToUSDOracle));

        // Set up Pendle oracle
        oracle = new PendlePTOracle(
            marketAddress, // pendleMarket
            baseToUSDOracle, // baseToUSDOracle
            false, // invertBase
            true, // useSyOracleRate
            900, // twapDuration (15 minutes)
            "sUSDe PT Oracle", // description
            address(0), // sequencerUptimeOracle (not needed for mainnet)
            1e18 // ptOraclePrecision
        );

        console.log("Oracle deployed:", address(oracle));

        // Fund this contract with tokens for testing
        deal(address(tokenInSy), address(this), 100_000_000e18); // 1M sUSDe
        // deal(address(ptToken), address(this), 1_000_000e18); // 1M PT tokens

        // Approve spending
        tokenInSy.checkApprove(address(PENDLE_ROUTER), type(uint256).max);
        ptToken.checkApprove(address(PENDLE_ROUTER), type(uint256).max);
        syToken.checkApprove(address(PENDLE_ROUTER), type(uint256).max);

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
        (netPtOut,,) = PENDLE_ROUTER.swapExactTokenForPt(
            address(this), // receiver
            marketAddress, // market
            0, // minPtOut (no minimum for testing)
            approxParams, // approximation params
            tokenInput, // token input data
            limitOrderData // limit order data (empty)
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
                swapType: IPRouter.SwapType.NONE, extRouter: address(0), extCalldata: bytes(""), needScale: false
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
        (netTokenOut,,) = PENDLE_ROUTER.swapExactPtForToken(
            address(this), // receiver
            address(pendleMarket), // market
            ptAmount, // exact PT amount to swap
            tokenOutput, // token output data
            limitOrderData // limit order data (empty)
        );

        emit log_named_uint("Swapped PT tokens", ptAmount);
        emit log_named_uint("Received underlying tokens", netTokenOut);
    }

    /// @notice Test oracle price manipulation resistance over time
    /// This test validates the TWAP oracle's resistance to price manipulation
    /// by checking price changes at different time intervals after a large trade
    function test_oraclePriceManipulation() public {
        uint256 largeSwapAmount = 15_000_000e18; // 15M tokens for significant price impact

        // Advance time to ensure clean TWAP window
        vm.warp(block.timestamp + 1000);

        // Step 1: Record initial oracle rate
        uint256 step1_rate = PENDLE_ORACLE.getPtToSyRate(marketAddress, 900);
        emit log_named_uint("Step 1 - Pre-Swap Rate", step1_rate);

        // Execute large swap to manipulate spot price
        uint256 ptReceived = swapTokenForPT(largeSwapAmount);
        emit log_named_uint("Large swap executed, PT received", ptReceived);

        // Step 2: Record post-swap rate
        uint256 step2_rate = PENDLE_ORACLE.getPtToSyRate(marketAddress, 900);
        emit log_named_uint("Step 2 - Post-Swap Rate", step2_rate);

        // Step 3: Record rate 10 seconds after swap
        vm.warp(block.timestamp + 10);
        uint256 step3_rate = PENDLE_ORACLE.getPtToSyRate(marketAddress, 900);
        emit log_named_uint("Step 3 - Rate (10s after)", step3_rate);

        // Step 4: Record rate 15 minutes after swap (one full TWAP window)
        vm.warp(block.timestamp + 890); // Additional time to reach 900s total
        uint256 step4_rate = PENDLE_ORACLE.getPtToSyRate(marketAddress, 900);
        emit log_named_uint("Step 4 - Rate (15 min after)", step4_rate);

        // Step 5: Record rate 30 minutes after swap (stable state)
        vm.warp(block.timestamp + 900); // Additional 15 minutes
        uint256 step5_rate = PENDLE_ORACLE.getPtToSyRate(marketAddress, 900);
        emit log_named_uint("Step 5 - Rate (30 min after)", step5_rate);

        // === VALIDATION 1: Rate should not change between steps 1 and 2 ===
        uint256 step1to2Change = step2_rate > step1_rate ? step2_rate - step1_rate : step1_rate - step2_rate;

        assertEq(step1to2Change, 0, "Rate should not change between steps 1 and 2");
        emit log_string("Validation 1 passed: No change between steps 1-2");

        // === VALIDATION 2: Rate changes should follow TWAP behavior ===
        uint256 step2to3Change = step3_rate > step2_rate ? step3_rate - step2_rate : step2_rate - step3_rate;

        uint256 step2to4Change = step4_rate > step2_rate ? step4_rate - step2_rate : step2_rate - step4_rate;

        emit log_named_uint("Step 2->3 Change", step2to3Change);
        emit log_named_uint("Step 2->4 Change", step2to4Change);

        // The change at step 3 should be approximately 1/90th of change at step 4
        // (10 seconds vs 900 seconds for linear TWAP)
        if (step2to4Change > 0) {
            // Calculate the ratio with high precision to avoid rounding errors
            uint256 firstRatio = (step3_rate * 1e18) / step2_rate - 1e18;
            uint256 secondRatio = (step4_rate * 1e18) / step2_rate - 1e18;
            uint256 ratio = secondRatio / firstRatio;
            emit log_named_uint("Ratio", ratio);

            // Expected ratio should be around 90
            uint256 expectedRatioMin = 85;
            uint256 expectedRatioMax = 95;

            assertTrue(ratio >= expectedRatioMin, "Step2->4 change too small relative to step2->3 (ratio too low)");
            assertTrue(ratio <= expectedRatioMax, "Step2->4 change too large relative to step2->3 (ratio too high)");

            emit log_string("Validation 2 passed: TWAP progression is reasonable");
        } else {
            emit log_string("Validation 2 skipped: No significant price change detected");
        }

        // === VALIDATION 3: Rate should not change between steps 4 and 5 ===
        uint256 step4to5Change = step5_rate > step4_rate ? step5_rate - step4_rate : step4_rate - step5_rate;

        // Allow minimal change (less than 0.1% of the major change)
        uint256 maxAllowedChange = step2to4Change / 1000;
        if (maxAllowedChange == 0) maxAllowedChange = 1; // Minimum threshold

        assertLe(step4to5Change, maxAllowedChange, "Rate should stabilize between steps 4 and 5");
        emit log_named_uint("Step 4->5 Change", step4to5Change);
        emit log_named_uint("Max Allowed Change", maxAllowedChange);
        emit log_string("Validation 3 passed: Rate stabilized after TWAP window");
    }
}
