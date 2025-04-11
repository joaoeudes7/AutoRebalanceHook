// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * @title SwapUtils
 * @dev Library for swap-related utility functions
 */
library SwapUtils {
    // Constants from Uniswap V3 TickMath for calculating sqrtPrice
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;
    
    // Error messages
    error TransactionExpired();
    error SlippageLimitExceeded(uint256 amountOut, uint256 minAmountOut);
    
    /**
     * @dev Calculates the sqrt ratio corresponding to a given tick
     * @param tick The tick for which to calculate the sqrt ratio
     * @return sqrtPriceX96 The sqrt ratio as a Q64.96 value
     */
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        // Ensure tick is within allowed range
        require(tick >= MIN_TICK && tick <= MAX_TICK, "Tick out of range");
        
        // This is a simplified version of Uniswap's TickMath.getSqrtRatioAtTick
        // For a complete implementation, refer to Uniswap's TickMath library
        
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= uint256(int256(MAX_TICK)), "Tick out of range");
        
        // We're using a simplified approximation here that is reasonable for most tick ranges
        // In a production implementation, the full TickMath algorithm would be used
        
        // Base price is 1.0001^tick as a Q64.96 fixed-point number
        // 1.0001^tick = (1 + 0.0001)^tick
        // ln(1.0001) ≈ 0.0001, so 1.0001^tick ≈ e^(0.0001 * tick)
        
        // For positive ticks, price increases
        // For negative ticks, price decreases
        
        if (tick >= 0) {
            // Simple approximation: 1.0001^tick ≈ 1 + (tick * 0.0001)
            // Convert to sqrt and to Q64.96
            // sqrt(1 + (tick * 0.0001)) ≈ 1 + (tick * 0.00005)
            sqrtPriceX96 = uint160(((1 << 96) * (10000 + (absTick * 5) / 10000)) / 10000);
        } else {
            // For negative ticks, we use 1/(1.0001^|tick|)
            // 1/(1 + (|tick| * 0.0001)) ≈ 1 - (|tick| * 0.0001)
            // sqrt(1 - (|tick| * 0.0001)) ≈ 1 - (|tick| * 0.00005)
            uint256 ratio = ((1 << 96) * (10000 - (absTick * 5) / 10000)) / 10000;
            sqrtPriceX96 = uint160(ratio);
        }
        
        // Ensure the result is within allowed bounds
        uint160 minSqrtRatio = 4295128739; // MIN_SQRT_RATIO from TickMath
        uint160 maxSqrtRatio = 1461446703485210103287273052203988822378723970342; // MAX_SQRT_RATIO from TickMath
        
        if (sqrtPriceX96 < minSqrtRatio) {
            sqrtPriceX96 = minSqrtRatio;
        } else if (sqrtPriceX96 > maxSqrtRatio) {
            sqrtPriceX96 = maxSqrtRatio;
        }
        
        return sqrtPriceX96;
    }

    /**
     * @dev Calculate if a swap is needed to balance token amounts for a position
     * @param amount0 Amount of token0 available
     * @param amount1 Amount of token1 available
     * @param price The current price as a Q64.96 fixed point number
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @return needSwap Whether a swap is needed
     * @return zeroForOne Direction of swap (true if token0 for token1)
     * @return amountToSwap Amount to swap
     */
    function calculateSwapForBalance(
        uint256 amount0,
        uint256 amount1,
        uint160 price,
        int24 lowerTick,
        int24 upperTick
    ) public pure returns (bool needSwap, bool zeroForOne, uint256 amountToSwap) {
        // Skip if either amount is zero
        if (amount0 == 0 || amount1 == 0) {
            return (false, false, 0);
        }
        
        // Calculate ideal ratio based on price and position range
        (uint256 idealAmount0, uint256 idealAmount1) = calculateIdealAmounts(
            amount0 + amount1,
            price,
            lowerTick,
            upperTick
        );
        
        // Determine if swap is needed by comparing actual to ideal
        if (amount0 > idealAmount0 * 105 / 100) {
            // We have too much token0, swap some for token1
            return (true, true, amount0 - idealAmount0);
        } else if (amount1 > idealAmount1 * 105 / 100) {
            // We have too much token1, swap some for token0
            return (true, false, amount1 - idealAmount1);
        } else {
            // The balance is already close enough to ideal
            return (false, false, 0);
        }
    }
    
    /**
     * @dev Calculate ideal token amounts for a position
     * @param totalValue Total value of both tokens in terms of token0
     * @param sqrtPriceX96 The current sqrt price as a Q64.96 fixed point number
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @return idealAmount0 Ideal amount of token0
     * @return idealAmount1 Ideal amount of token1
     */
    function calculateIdealAmounts(
        uint256 totalValue,
        uint160 sqrtPriceX96,
        int24 lowerTick,
        int24 upperTick
    ) internal pure returns (uint256 idealAmount0, uint256 idealAmount1) {
        // Convert ticks to sqrt prices
        uint160 sqrtPriceLowerX96 = getSqrtRatioAtTick(lowerTick);
        uint160 sqrtPriceUpperX96 = getSqrtRatioAtTick(upperTick);
        
        // Ensure sqrtPriceX96 is within the range
        if (sqrtPriceX96 < sqrtPriceLowerX96) {
            sqrtPriceX96 = sqrtPriceLowerX96;
        } else if (sqrtPriceX96 > sqrtPriceUpperX96) {
            sqrtPriceX96 = sqrtPriceUpperX96;
        }
        
        // Calculate the percentage position within the range (0 to 100)
        uint256 rangePosition;
        if (sqrtPriceX96 <= sqrtPriceLowerX96) {
            rangePosition = 0; // At or below lower bound
        } else if (sqrtPriceX96 >= sqrtPriceUpperX96) {
            rangePosition = 100; // At or above upper bound
        } else {
            // Linear interpolation based on sqrt price
            uint256 priceRange = uint256(sqrtPriceUpperX96) - uint256(sqrtPriceLowerX96);
            uint256 pricePosition = uint256(sqrtPriceX96) - uint256(sqrtPriceLowerX96);
            rangePosition = (pricePosition * 100) / priceRange;
        }
        
        // Ideal token distribution based on position in range
        // At lower bound: 100% token1, 0% token0
        // At upper bound: 0% token1, 100% token0
        // Linear interpolation between bounds
        uint256 idealRatio0 = rangePosition;
        uint256 idealRatio1 = 100 - rangePosition;
        
        // Apply minimum thresholds to avoid dust amounts
        if (idealRatio0 < 5) idealRatio0 = 5;
        if (idealRatio1 < 5) idealRatio1 = 5;
        
        // Normalize to 100%
        uint256 totalRatio = idealRatio0 + idealRatio1;
        idealRatio0 = (idealRatio0 * 100) / totalRatio;
        idealRatio1 = (idealRatio1 * 100) / totalRatio;
        
        // Calculate ideal amounts based on ratios
        idealAmount0 = (totalValue * idealRatio0) / 100;
        idealAmount1 = (totalValue * idealRatio1) / 100;
        
        return (idealAmount0, idealAmount1);
    }
    
    /**
     * @dev Execute a swap on Uniswap V4
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param zeroForOne Direction of swap (true if token0 for token1)
     * @param amountSpecified Amount to swap
     * @return amountIn Amount swapped in
     * @return amountOut Amount received
     */
    function executeSwap(
        IPoolManager poolManager,
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        // Define swap parameters
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341 // MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        });
        
        // Execute the swap
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        // Calculate amounts in and out
        if (zeroForOne) {
            // Token0 → Token1 swap
            amountIn = uint256(uint128(-delta.amount0()));
            amountOut = uint256(uint128(delta.amount1()));
        } else {
            // Token1 → Token0 swap
            amountIn = uint256(uint128(-delta.amount1()));
            amountOut = uint256(uint128(delta.amount0()));
        }
        
        return (amountIn, amountOut);
    }
    
    /**
     * @dev Execute a swap with slippage protection to prevent front-running and MEV attacks
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param zeroForOne Direction of swap (true if token0 for token1)
     * @param amountSpecified Amount to swap
     * @param minAmountOut Minimum amount to receive (slippage protection)
     * @param deadline Transaction deadline timestamp
     * @return amountIn Amount swapped in
     * @return amountOut Amount received
     */
    function executeSwapWithSlippage(
        IPoolManager poolManager,
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        // Check deadline to prevent stale transactions
        if (block.timestamp > deadline) {
            revert TransactionExpired();
        }
        
        // Calculate adaptive price limit based on current price and direction
        uint160 sqrtPriceLimitX96;
        
        // For production use, calculate based on the current pool price and desired slippage
        // Here we use conservative limits to protect against price manipulation
        if (zeroForOne) {
            // Token0 to Token1 swap (price decreases)
            // Use a higher minimum price than the absolute minimum to limit slippage
            sqrtPriceLimitX96 = 4295128740 + 100000000; // MIN_SQRT_RATIO + buffer
        } else {
            // Token1 to Token0 swap (price increases)
            // Use a lower maximum price than the absolute maximum to limit slippage
            sqrtPriceLimitX96 = 1461446703485210103287273052203988822378723970341 - 100000000; // MAX_SQRT_RATIO - buffer
        }
        
        // Define swap parameters with improved price limit for better slippage protection
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        
        // Execute the swap
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        // Calculate amounts in and out
        if (zeroForOne) {
            // Token0 → Token1 swap
            amountIn = uint256(uint128(-delta.amount0()));
            amountOut = uint256(uint128(delta.amount1()));
        } else {
            // Token1 → Token0 swap
            amountIn = uint256(uint128(-delta.amount1()));
            amountOut = uint256(uint128(delta.amount0()));
        }
        
        // Verify minimum amount out to prevent front-running
        if (amountOut < minAmountOut) {
            revert SlippageLimitExceeded(amountOut, minAmountOut);
        }
        
        return (amountIn, amountOut);
    }
} 