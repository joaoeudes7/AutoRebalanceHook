// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TickLib
 * @dev Library for tick-related calculations
 */
library TickLib {
    /**
     * @dev Calculate the lower tick of a new range based on configurable parameters
     * @param currentTick The current tick of the pool
     * @param tickSpacing The tick spacing of the pool
     * @param rangeTicks The number of ticks to use for the range
     * @return The new lower tick, rounded to the nearest valid tick
     */
    function calculateLowerTick(
        int24 currentTick, 
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24) {
        // Calculate target lower tick based on configured range
        int24 targetLowerTick = currentTick - rangeTicks;
        
        // Round to the nearest valid tick based on tickSpacing
        return (targetLowerTick / tickSpacing) * tickSpacing;
    }
    
    /**
     * @dev Calculate the upper tick of a new range based on configurable parameters
     * @param currentTick The current tick of the pool
     * @param tickSpacing The tick spacing of the pool
     * @param rangeTicks The number of ticks to use for the range
     * @return The new upper tick, rounded to the nearest valid tick
     */
    function calculateUpperTick(
        int24 currentTick, 
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24) {
        // Calculate target upper tick based on configured range
        int24 targetUpperTick = currentTick + rangeTicks;
        
        // Round to the nearest valid tick based on tickSpacing
        return (targetUpperTick / tickSpacing) * tickSpacing;
    }
} 