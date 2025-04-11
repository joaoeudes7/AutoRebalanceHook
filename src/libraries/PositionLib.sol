// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PositionLib
 * @dev Library for Position-related data structures and utility functions
 */
library PositionLib {
    /**
     * @dev Structure to store position information
     */
    struct Position {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        bool isActive;
        uint256 lastFeeCollectionTimestamp;
        uint256 token0Balance;
        uint256 token1Balance;
    }
    
    /**
     * @dev Checks if a position is out of range
     * @param position The position to check
     * @param currentTick The current tick of the pool
     * @return True if the current tick is outside the position range
     */
    function isOutOfRange(Position memory position, int24 currentTick) internal pure returns (bool) {
        if (!position.isActive) return false;
        
        return currentTick < position.lowerTick || currentTick > position.upperTick;
    }
    
    /**
     * @dev Determines if rebalancing should occur based on current tick's distance from range midpoint
     * @param position The position to check
     * @param currentTick The current tick of the pool
     * @param rebalanceThreshold The threshold percentage for rebalancing
     * @return True if rebalancing should occur
     */
    function shouldRebalance(
        Position memory position, 
        int24 currentTick, 
        uint256 rebalanceThreshold
    ) internal pure returns (bool) {
        // Calculate the middle of the position range
        int24 midTick = (position.lowerTick + position.upperTick) / 2;
        
        // Calculate distance from current tick to midpoint in ticks
        uint24 tickDistance = currentTick > midTick 
            ? uint24(currentTick - midTick) 
            : uint24(midTick - currentTick);
        
        // Calculate the total range width
        uint24 rangeWidth = uint24(position.upperTick - position.lowerTick);
        
        // Calculate threshold ticks based on percentage of range
        uint24 thresholdTicks = rangeWidth * uint24(rebalanceThreshold) / 200; 
        
        // Return true if the tick distance is greater than our threshold
        return tickDistance > thresholdTicks;
    }
} 