// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/oracles/Curve2TokenOracle.sol";
import "../src/interfaces/Curve/ICurve.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/interfaces/Curve/ICurve.sol";
import "../src/utils/Constants.sol";
import "../src/utils/TokenUtils.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { AggregatorV2V3Interface, TRADING_MODULE } from "../src/interfaces/ITradingModule.sol";

contract TestCurveOraclePriceManipulation is Test {
    using TokenUtils for ERC20;
    Curve2TokenOracle public oracle;
    ICurvePool public curvePool;
    ERC20 public token0;
    ERC20 public token1;
    uint8 public primaryIndex;
    uint8 public secondaryIndex;
    uint256 public dyAmount;
    string RPC_URL = vm.envString("RPC_URL");
    uint256 FORK_BLOCK = vm.envUint("FORK_BLOCK");
    address public owner = address(0x02479BFC7Dce53A02e26fE7baea45a0852CB0909);

    function setUp() public {
        // Fork mainnet for testing
        vm.createSelectFork(RPC_URL, FORK_BLOCK);

        // Use USDC/USDe Curve pool for testing
        curvePool = ICurvePool(0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72);
        token0 = ERC20(curvePool.coins(0)); // USDe
        token1 = ERC20(curvePool.coins(1)); // USDC
        primaryIndex = 1;
        secondaryIndex = 0;
        dyAmount = 1e6; // 1 unit in USDC decimals

        console.log("creating oracle");
        // Use Chainlink USDC/USDe oracle
        (
            AggregatorV2V3Interface baseToUSDOracle, /* */
        ) = TRADING_MODULE.priceOracles(address(token1));
        console.log("baseToUSDOracle", address(baseToUSDOracle));
        // Deploy oracle
        oracle = new Curve2TokenOracle(
            0.95e18, // lowerLimitMultiplier (5% below)
            1.05e18, // upperLimitMultiplier (5% above)
            address(curvePool),
            primaryIndex,
            "USDC/USDe Curve Oracle",
            address(0), // no sequencer oracle needed for mainnet
            baseToUSDOracle,
            false, // don't invert base
            dyAmount
        );
        console.log("oracle", address(oracle));
        // Fund this contract with tokens for trading
        deal(address(token0), address(this), 1_000_000_000e18); // 1M USDe
        deal(address(token1), address(this), 1_000_000_000e6); // 1M USDC
        console.log("funding tokens");
        // Approve spending
        token0.checkApprove(address(curvePool), type(uint256).max);
        token1.checkApprove(address(curvePool), type(uint256).max);
        console.log("approved tokens");
        setMaxOracleFreshness();
        console.log("set max oracle freshness");
    }

    function setMaxOracleFreshness() internal {
        vm.prank(owner);
        TRADING_MODULE.setMaxOracleFreshness(type(uint32).max);
    }

    function getCurrentOraclePrice() internal view returns (uint256) {
        int256 answer = oracle.latestAnswer();
        require(answer > 0, "Invalid oracle price");
        return uint256(answer);
    }

    /// @notice Get current spot price from Curve pool (mirrors Curve2TokenOracle logic)
    function getCurrentSpotPrice() internal view returns (uint256) {
        uint256 primaryPrecision = primaryIndex == 0 ? 10 ** 18 : 10 ** 6; // USDe = 18, USDC = 6
        uint256 secondaryPrecision = secondaryIndex == 0 ? 10 ** 18 : 10 ** 6; // USDe = 18, USDC = 6

        // Get dy amount (same logic as Curve2TokenOracle)
        uint256 spotPrice = curvePool.get_dy(int8(primaryIndex), int8(secondaryIndex), dyAmount) * primaryPrecision
            * DEFAULT_PRECISION / (dyAmount * secondaryPrecision);

        return spotPrice;
    }

    /// @notice Move spot price by a specific percentage using binary search
    /// @param percentChange Percentage change in basis points (500 = 5%, -300 = -3%)
    /// @param fromIndex Token index to sell from (0 = USDe, 1 = USDC)
    /// @param toIndex Token index to buy (0 = USDe, 1 = USDC)
    /// @return swapAmount The amount needed to achieve the target price change
    function movePriceByPercentage(
        int256 percentChange,
        uint8 fromIndex,
        uint8 toIndex
    )
        internal
        returns (uint256 swapAmount)
    {
        uint256 initialPrice = getCurrentSpotPrice();
        uint256 targetPrice = calculateTargetPrice(initialPrice, percentChange);
        console.log("initialPrice", initialPrice);
        console.log("targetPrice", targetPrice);
        bool isIncreasing = percentChange >= 0;
        return binarySearchSwapAmount(targetPrice, fromIndex, toIndex, isIncreasing);
    }

    /// @notice Calculate target price based on percentage change
    function calculateTargetPrice(uint256 currentPrice, int256 percentChange) internal pure returns (uint256) {
        if (percentChange >= 0) {
            return currentPrice * uint256(10_000 + percentChange) / 10_000;
        } else {
            return currentPrice * uint256(10_000 - uint256(-percentChange)) / 10_000;
        }
    }

    /// @notice Binary search to find swap amount needed for target price
    function binarySearchSwapAmount(
        uint256 targetPrice,
        uint8 fromIndex,
        uint8 toIndex,
        bool isIncreasing
    )
        internal
        returns (uint256 bestAmount)
    {
        ERC20 fromToken = fromIndex == 0 ? token0 : token1;
        ERC20 toToken = toIndex == 0 ? token0 : token1;
        uint256 high = toToken.balanceOf(address(curvePool));
        high = high * 10 ** fromToken.decimals() / 10 ** toToken.decimals();
        uint256 low = 1;
        uint256 tolerance = targetPrice / 1000; // 0.1% tolerance
        for (uint256 i = 0; i < 50; i++) {
            if (low >= high) break;
            uint256 mid = (low + high) / 2;
            (uint256 resultPrice, bool success) = simulateSwapSafe(mid, fromIndex, toIndex);
            if (!success) {
                // Swap would revert - amount too high
                high = mid - 1;
                continue;
            }

            if (isWithinTolerance(resultPrice, targetPrice, tolerance)) {
                bestAmount = mid;
                break;
            }

            if (isIncreasing) {
                if (resultPrice > targetPrice) {
                    // Overshot target, try smaller amount
                    high = mid - 1;
                    bestAmount = mid; // Keep this as backup
                } else {
                    // Undershot target, try larger amount
                    low = mid + 1;
                }
            } else {
                // For decreasing price: more swap = lower price
                if (resultPrice < targetPrice) {
                    // Overshot (went too low), try smaller amount
                    high = mid - 1;
                    bestAmount = mid; // Keep this as backup
                } else {
                    // Undershot (still too high), try larger amount
                    low = mid + 1;
                }
            }
        }

        require(bestAmount > 0, "No valid swap amount found");

        // Execute the actual swap
        curvePool.exchange(int8(fromIndex), int8(toIndex), bestAmount, 0);

        return bestAmount;
    }

    /// @notice Safely simulate a swap using snapshots
    function simulateSwapSafe(
        uint256 amount,
        uint8 fromIndex,
        uint8 toIndex
    )
        internal
        returns (uint256 resultPrice, bool success)
    {
        uint256 snapshot = vm.snapshot();

        try curvePool.exchange(int8(fromIndex), int8(toIndex), amount, 0) {
            resultPrice = getCurrentSpotPrice();
            success = true;
        } catch {
            success = false;
        }

        vm.revertTo(snapshot);
    }

    /// @notice Check if price is within tolerance of target
    function isWithinTolerance(uint256 price, uint256 target, uint256 tolerance) internal pure returns (bool) {
        return price >= target - tolerance && price <= target + tolerance;
    }

    /// @notice Get oracle pair price (mirrors AbstractLPOracle._getOraclePairPrice)
    function getOraclePairPrice(address base, address quote) internal view returns (uint256) {
        (
            int256 rate, /* */
        ) = TRADING_MODULE.getOraclePrice(base, quote);
        return uint256(rate);
    }

    /// @notice Test deviation threshold - price pushed beyond upper limit should revert
    function test_deviationThreshold_upperLimit() public {
        // Get the oracle pair price between USDC (primary) and USDe (secondary)
        address primaryToken = address(token1); // USDC
        address secondaryToken = address(token0); // USDe
        uint256 oraclePrice = getOraclePairPrice(primaryToken, secondaryToken);

        // Get upper limit (from AbstractLPOracle lines 93-94)
        uint256 upperLimit = oraclePrice * 1.05e18 / DEFAULT_PRECISION; // 5% above oracle price

        emit log_named_uint("Oracle Price", oraclePrice);
        emit log_named_uint("Upper Limit", upperLimit);

        // Calculate how much we need to move spot price to exceed upper limit
        // Add 1% buffer to ensure we exceed the threshold
        uint256 targetPrice = upperLimit * 101 / 100; // 1% beyond upper limit
        uint256 currentSpotPrice = getCurrentSpotPrice();

        // Calculate percentage change needed
        int256 percentChangeNeeded = int256((targetPrice * 10_000) / currentSpotPrice) - 10_000;

        emit log_named_uint("Current Spot Price", currentSpotPrice);
        emit log_named_uint("Target Price", targetPrice);
        emit log_named_int("Percent Change Needed (bp)", percentChangeNeeded);

        // Push spot price beyond upper limit by selling USDC for USDe
        movePriceByPercentage(percentChangeNeeded, 0, 1); // USDC -> USDe

        uint256 finalSpotPrice = getCurrentSpotPrice();
        emit log_named_uint("Final Spot Price", finalSpotPrice);

        // Verify spot price is beyond upper limit
        assertTrue(finalSpotPrice > upperLimit, "Spot price should exceed upper limit");

        // Oracle should revert when spot price is beyond threshold
        vm.expectRevert();
        oracle.latestAnswer();
    }

    /// @notice Test deviation threshold - price pushed beyond lower limit should revert
    function test_deviationThreshold_lowerLimit() public {
        // Get the oracle pair price between USDC (primary) and USDe (secondary)
        address primaryToken = address(token1); // USDC
        address secondaryToken = address(token0); // USDe
        uint256 oraclePrice = getOraclePairPrice(primaryToken, secondaryToken);

        // Get lower limit (from AbstractLPOracle lines 93-94)
        uint256 lowerLimit = oraclePrice * 0.95e18 / DEFAULT_PRECISION; // 5% below oracle price

        emit log_named_uint("Oracle Price", oraclePrice);
        emit log_named_uint("Lower Limit", lowerLimit);

        // Calculate how much we need to move spot price to fall below lower limit
        // Add 1% buffer to ensure we exceed the threshold
        uint256 targetPrice = lowerLimit * 99 / 100; // 1% beyond lower limit
        uint256 currentSpotPrice = getCurrentSpotPrice();

        // Calculate percentage change needed
        int256 percentChangeNeeded = int256((targetPrice * 10_000) / currentSpotPrice) - 10_000;

        emit log_named_uint("Current Spot Price", currentSpotPrice);
        emit log_named_uint("Target Price", targetPrice);
        emit log_named_int("Percent Change Needed (bp)", percentChangeNeeded);

        // Push spot price below lower limit by selling USDe for USDC
        movePriceByPercentage(percentChangeNeeded, 1, 0); // USDe -> USDC

        uint256 finalSpotPrice = getCurrentSpotPrice();
        emit log_named_uint("Final Spot Price", finalSpotPrice);

        // Verify spot price is below lower limit
        assertTrue(finalSpotPrice < lowerLimit, "Spot price should be below lower limit");

        // Oracle should revert when spot price is beyond threshold
        vm.expectRevert();
        oracle.latestAnswer();
    }

    /// @notice Test that oracle works normally when within deviation limits
    function test_deviationThreshold_withinLimits() public {
        // Move price by small amount (2%) - should stay within 5% limits
        movePriceByPercentage(200, 0, 1); // 2% increase

        uint256 spotPrice = getCurrentSpotPrice();
        address primaryToken = address(token1);
        address secondaryToken = address(token0);
        uint256 oraclePrice = getOraclePairPrice(primaryToken, secondaryToken);
        uint256 lowerLimit = oraclePrice * 0.95e18 / DEFAULT_PRECISION;
        uint256 upperLimit = oraclePrice * 1.05e18 / DEFAULT_PRECISION;

        emit log_named_uint("Spot Price", spotPrice);
        emit log_named_uint("Oracle Price", oraclePrice);
        emit log_named_uint("Lower Limit", lowerLimit);
        emit log_named_uint("Upper Limit", upperLimit);

        // Verify spot price is within limits
        assertTrue(spotPrice >= lowerLimit && spotPrice <= upperLimit, "Spot price should be within limits");

        // Oracle should work normally
        int256 answer = oracle.latestAnswer();
        assertTrue(answer > 0, "Oracle should return valid price");
    }

    /// @notice Test that dyAmount swaps maintain price stability
    /// @dev This tests that the oracle's dyAmount parameter provides consistent spot price calculations
    function test_dyAmount_priceStability() public {
        // Execute first swap: primary -> secondary with dyAmount
        uint256 initialSpotPrice = getCurrentSpotPrice();

        uint256 amountIn = dyAmount; // 1 USDC (1e6)
        uint256 minAmountOut = 0;

        // First swap: USDC -> USDe
        uint256 firstAmountOut = curvePool.exchange(
            int8(primaryIndex), // from USDC (index 1)
            int8(secondaryIndex), // to USDe (index 0)
            amountIn,
            minAmountOut
        );

        uint256 afterFirstSwapPrice = getCurrentSpotPrice();

        emit log_named_uint("Initial Spot Price", initialSpotPrice);
        emit log_named_uint("After First Swap Price", afterFirstSwapPrice);
        emit log_named_uint("First Amount In (USDC)", amountIn);
        emit log_named_uint("First Amount Out (USDe)", firstAmountOut);

        // Execute second swap with identical parameters
        uint256 secondAmountOut = curvePool.exchange(
            int8(primaryIndex), // from USDC (index 1)
            int8(secondaryIndex), // to USDe (index 0)
            amountIn, // same dyAmount
            minAmountOut
        );

        uint256 afterSecondSwapPrice = getCurrentSpotPrice();

        emit log_named_uint("After Second Swap Price", afterSecondSwapPrice);
        emit log_named_uint("Second Amount In (USDC)", amountIn);
        emit log_named_uint("Second Amount Out (USDe)", secondAmountOut);

        // Calculate price difference between first and second swap
        uint256 priceDifference;
        if (afterSecondSwapPrice > afterFirstSwapPrice) {
            priceDifference = afterSecondSwapPrice - afterFirstSwapPrice;
        } else {
            priceDifference = afterFirstSwapPrice - afterSecondSwapPrice;
        }

        // Calculate percentage difference (in basis points)
        uint256 percentageDifference = (priceDifference * 10_000) / afterFirstSwapPrice;

        emit log_named_uint("Price Difference (absolute)", priceDifference);
        emit log_named_uint("Percentage Difference (bp)", percentageDifference);

        // Verify the price difference is less than 0.01% (1 basis point)
        // This ensures the oracle's dyAmount parameter provides consistent price calculations
        assertTrue(percentageDifference <= 1, "Price difference should be less than 0.01% (1 bp)");

        // Verify both swaps received similar amounts (allowing for slippage)
        uint256 amountDifference;
        if (secondAmountOut > firstAmountOut) {
            amountDifference = secondAmountOut - firstAmountOut;
        } else {
            amountDifference = firstAmountOut - secondAmountOut;
        }

        uint256 amountPercentageDifference = (amountDifference * 10_000) / firstAmountOut;
        emit log_named_uint("Amount Difference (USDe)", amountDifference);
        emit log_named_uint("Amount Percentage Difference (bp)", amountPercentageDifference);

        // Amount received should be very similar (allowing for some pool state changes)
        assertTrue(amountPercentageDifference <= 10, "Amount difference should be reasonable");
    }

    /// @notice Test maximum upward price manipulation without crossing deviation thresholds
    /// @dev Tests that LP token oracle price remains stable when spot price approaches upper limit
    function test_maxPriceManipulation_upperLimit() public {
        uint256 initialLpOraclePrice = getCurrentOraclePrice();
        uint256 oraclePrice = getOraclePairPrice(address(token1), address(token0));
        uint256 upperLimit = oraclePrice * 1.05e18 / DEFAULT_PRECISION; // 5% above

        emit log_named_uint("Initial LP Oracle Price", initialLpOraclePrice);
        emit log_named_uint("Oracle Pair Price", oraclePrice);
        emit log_named_uint("Upper Limit", upperLimit);

        // Push spot price up to upper limit (with 0.2% buffer)
        uint256 initialSpotPrice = getCurrentSpotPrice();
        uint256 targetPrice = upperLimit * 998 / 1000; // 0.2% below upper limit
        int256 percentChange = int256((targetPrice * 10_000) / initialSpotPrice) - 10_000;

        emit log_named_uint("Initial Spot Price", initialSpotPrice);
        emit log_named_uint("Target Price", targetPrice);
        emit log_named_int("Percent Change (bp)", percentChange);

        // Move price up by selling USDC for USDe
        movePriceByPercentage(percentChange, 0, 1);

        uint256 finalLpPrice = getCurrentOraclePrice();
        uint256 finalSpotPrice = getCurrentSpotPrice();

        emit log_named_uint("Final Spot Price", finalSpotPrice);
        emit log_named_uint("Final LP Oracle Price", finalLpPrice);

        // Verify spot price is within limits but close to upper bound
        assertTrue(finalSpotPrice <= upperLimit, "Spot price should not exceed upper limit");
        assertTrue(finalSpotPrice >= upperLimit * 990 / 1000, "Spot price should be close to upper limit");

        // Calculate LP oracle price change
        uint256 lpPriceChange = finalLpPrice > initialLpOraclePrice
            ? finalLpPrice - initialLpOraclePrice
            : initialLpOraclePrice - finalLpPrice;
        uint256 lpPercentChange = (lpPriceChange * 10_000) / initialLpOraclePrice;

        emit log_named_uint("LP Price Change (absolute)", lpPriceChange);
        emit log_named_uint("LP Price Change (bp)", lpPercentChange);

        // LP oracle price should remain stable (< 1% change)
        assertTrue(lpPercentChange <= 100, "LP oracle price change should be < 1% when approaching upper limit");
    }

    /// @notice Test maximum downward price manipulation without crossing deviation thresholds
    /// @dev Tests that LP token oracle price remains stable when spot price approaches lower limit
    function test_maxPriceManipulation_lowerLimit() public {
        uint256 initialLpOraclePrice = getCurrentOraclePrice();
        uint256 oraclePrice = getOraclePairPrice(address(token1), address(token0));
        uint256 lowerLimit = oraclePrice * 0.95e18 / DEFAULT_PRECISION; // 5% below

        emit log_named_uint("Initial LP Oracle Price", initialLpOraclePrice);
        emit log_named_uint("Oracle Pair Price", oraclePrice);
        emit log_named_uint("Lower Limit", lowerLimit);

        // Push spot price down to lower limit (with 0.2% buffer)
        uint256 initialSpotPrice = getCurrentSpotPrice();
        uint256 targetPrice = lowerLimit * 1002 / 1000; // 0.2% above lower limit
        int256 percentChange = int256((targetPrice * 10_000) / initialSpotPrice) - 10_000;

        emit log_named_uint("Initial Spot Price", initialSpotPrice);
        emit log_named_uint("Target Price", targetPrice);
        emit log_named_int("Percent Change (bp)", percentChange);

        // Move price down by selling USDe for USDC
        movePriceByPercentage(percentChange, 1, 0);

        uint256 finalLpPrice = getCurrentOraclePrice();
        uint256 finalSpotPrice = getCurrentSpotPrice();

        emit log_named_uint("Final Spot Price", finalSpotPrice);
        emit log_named_uint("Final LP Oracle Price", finalLpPrice);

        // Verify spot price is within limits but close to lower bound
        assertTrue(finalSpotPrice >= lowerLimit, "Spot price should not fall below lower limit");
        assertTrue(finalSpotPrice <= lowerLimit * 1010 / 1000, "Spot price should be close to lower limit");

        // Calculate LP oracle price change
        uint256 lpPriceChange = finalLpPrice > initialLpOraclePrice
            ? finalLpPrice - initialLpOraclePrice
            : initialLpOraclePrice - finalLpPrice;
        uint256 lpPercentChange = (lpPriceChange * 10_000) / initialLpOraclePrice;

        emit log_named_uint("LP Price Change (absolute)", lpPriceChange);
        emit log_named_uint("LP Price Change (bp)", lpPercentChange);

        // LP oracle price should remain stable (< 1% change)
        assertTrue(lpPercentChange <= 100, "LP oracle price change should be < 1% when approaching lower limit");
    }
}
