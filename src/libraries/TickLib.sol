// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TickLib
 * @notice Library for tick calculations and manipulations
 * @dev Provides utility functions for tick range calculations
 */
library TickLib {
    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    /**
     * @notice Calculates the lower tick of a position's range
     * @param currentTick Current tick of the pool
     * @param tickSpacing Tick spacing of the pool
     * @param rangeTicks Number of ticks for the range
     * @return Lower tick aligned to tick spacing
     */
    function calculateLowerTick(
        int24 currentTick,
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24) {
        // Calculate half of the range to center the position around current tick
        int24 halfRange = (rangeTicks * tickSpacing) / 2;
        
        // Calculate tick lower by subtracting half of the range
        int24 rawTickLower = currentTick - halfRange;
        
        // Ensure tick is multiple of spacing
        int24 tickLower = (rawTickLower / tickSpacing) * tickSpacing;
        
        // Ensure tick is not below minimum
        if (tickLower < MIN_TICK) {
            tickLower = MIN_TICK;
        }
        
        return tickLower;
    }

    /**
     * @notice Calculates the upper tick of a position's range
     * @param currentTick Current tick of the pool
     * @param tickSpacing Tick spacing of the pool
     * @param rangeTicks Number of ticks for the range
     * @return Upper tick aligned to tick spacing
     */
    function calculateUpperTick(
        int24 currentTick,
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24) {
        // Calculate half of the range to center the position around current tick
        int24 halfRange = (rangeTicks * tickSpacing) / 2;
        
        // Calculate tick upper by adding half of the range
        int24 rawTickUpper = currentTick + halfRange;
        
        // Ensure tick is multiple of spacing
        int24 tickUpper = (rawTickUpper / tickSpacing) * tickSpacing;
        
        // Ensure tick is not above maximum
        if (tickUpper > MAX_TICK) {
            tickUpper = MAX_TICK;
        }
        
        return tickUpper;
    }
    
    /**
     * @notice Aligns a tick to the nearest valid tick based on spacing
     * @param tick The tick to align
     * @param tickSpacing The tick spacing
     * @return The aligned tick
     */
    function alignToSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        return (tick / tickSpacing) * tickSpacing;
    }
    
    /**
     * @notice Calculates a narrow lower tick for NarrowRange liquidity
     * @param currentTick Current tick of the pool
     * @param tickSpacing Tick spacing of the pool
     * @param rangeMultiplier Multiplier for the range (1 = very narrow)
     * @return Lower tick for NarrowRange liquidity
     */
    function calculateNarrowLowerTick(
        int24 currentTick,
        int24 tickSpacing,
        uint256 rangeMultiplier
    ) internal pure returns (int24) {
        // For NarrowRange liquidity, we want a very narrow range
        // that's just below the current tick
        // Fix type conversion issues by converting to int24 properly
        int24 adjustedSpacing = int24(int256(uint256(uint24(tickSpacing)) * rangeMultiplier));
        int24 tickLower = currentTick - adjustedSpacing;
        
        // Align to valid tick
        tickLower = alignToSpacing(tickLower, tickSpacing);
        
        // Ensure tick is not below minimum
        if (tickLower < MIN_TICK) {
            tickLower = MIN_TICK;
        }
        
        return tickLower;
    }
    
    /**
     * @notice Calculates a narrow upper tick for NarrowRange liquidity
     * @param currentTick Current tick of the pool
     * @param tickSpacing Tick spacing of the pool
     * @param rangeMultiplier Multiplier for the range (1 = very narrow)
     * @return Upper tick for NarrowRange liquidity
     */
    function calculateNarrowUpperTick(
        int24 currentTick,
        int24 tickSpacing,
        uint256 rangeMultiplier
    ) internal pure returns (int24) {
        // For NarrowRange liquidity, we want a very narrow range
        // that's just above the current tick
        // Fix type conversion issues by converting to int24 properly
        int24 adjustedSpacing = int24(int256(uint256(uint24(tickSpacing)) * rangeMultiplier));
        int24 tickUpper = currentTick + adjustedSpacing;
        
        // Align to valid tick
        tickUpper = alignToSpacing(tickUpper, tickSpacing);
        
        // Ensure tick is not above maximum
        if (tickUpper > MAX_TICK) {
            tickUpper = MAX_TICK;
        }
        
        return tickUpper;
    }
} 