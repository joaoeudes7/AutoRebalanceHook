// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebalanceStrategy} from "../interfaces/IRebalanceStrategy.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import "../libraries/TickLib.sol";

/**
 * @title StandardRebalanceStrategy
 * @notice A standard implementation of rebalance strategy
 * @dev Provides basic rebalancing logic that works for most cases
 */
contract StandardRebalanceStrategy is IRebalanceStrategy {
    // Owner of the strategy
    address public owner;
    
    // Error codes
    error Unauthorized();
    
    // Events
    event OwnershipTransferred(address previousOwner, address newOwner);
    
    /**
     * @dev Constructor
     */
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Modifier to restrict function access to contract owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    /**
     * @notice Transfer ownership to a new address
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @notice Check if a position should be rebalanced
     * @param lowerTick Current lower tick of the position
     * @param upperTick Current upper tick of the position
     * @param currentTick The current tick of the pool
     * @param lastRebalance Timestamp of the last rebalance
     * @param rebalanceThreshold Threshold percentage for rebalancing
     * @param cooldownPeriod Minimum time between rebalances
     * @return needsRebalancing True if position should be rebalanced
     */
    function shouldRebalance(
        bytes32 /* poolId */,
        int24 lowerTick,
        int24 upperTick,
        int24 currentTick,
        uint256 lastRebalance,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod
    ) external view returns (bool needsRebalancing) {
        // Check cooldown period
        if (block.timestamp < lastRebalance + cooldownPeriod) {
            return false;
        }
        
        // Check if out of range
        if (currentTick < lowerTick || currentTick >= upperTick) {
            return true;
        }
        
        // Calculate deviation from center of range
        int24 rangeMidpoint = lowerTick + (upperTick - lowerTick) / 2;
        uint256 rangeWidth = uint24(upperTick - lowerTick);
        
        // Calculate distance from midpoint as percentage
        uint256 deviation;
        if (currentTick > rangeMidpoint) {
            deviation = (uint24(currentTick - rangeMidpoint) * 100) / rangeWidth;
        } else {
            deviation = (uint24(rangeMidpoint - currentTick) * 100) / rangeWidth;
        }
        
        // Compare with rebalance threshold
        return deviation >= rebalanceThreshold;
    }
    
    /**
     * @notice Calculate new tick range for a position
     * @param currentTick The current tick of the pool
     * @param tickSpacing The tick spacing of the pool
     * @param rangeTicks Number of ticks for the range
     * @param volatilityMetric Optional metric for volatility-based adjustments
     * @return lowerTick New lower tick
     * @return upperTick New upper tick
     */
    function calculateNewRange(
        int24 currentTick,
        int24 tickSpacing,
        int24 rangeTicks,
        uint32 volatilityMetric
    ) external pure returns (int24 lowerTick, int24 upperTick) {
        // Adjust rangeTicks based on volatility if needed
        int24 adjustedRangeTicks = rangeTicks;
        
        // Apply volatility adjustment if greater than zero
        if (volatilityMetric > 0) {
            // Scale up the range ticks based on volatility
            // Higher volatility = wider range
            // This is a simple linear scaling, but could be more sophisticated
            uint256 scaleFactor = 100 + (volatilityMetric / 100); // e.g., 1000 basis points -> 110%
            adjustedRangeTicks = int24((int256(rangeTicks) * int256(scaleFactor)) / 100);
        }
        
        // Calculate the range using TickLib
        lowerTick = TickLib.calculateLowerTick(currentTick, tickSpacing, adjustedRangeTicks);
        upperTick = TickLib.calculateUpperTick(currentTick, tickSpacing, adjustedRangeTicks);
        
        return (lowerTick, upperTick);
    }
    
    /**
     * @notice Get the strategy name
     * @return name The name of the strategy
     */
    function getName() external pure returns (string memory name) {
        return "StandardRebalanceStrategy";
    }
} 