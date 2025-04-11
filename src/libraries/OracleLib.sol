// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * @title OracleLib
 * @dev Library with utilities for tracking time-weighted prices and protecting against price manipulation
 */
library OracleLib {
    // Constants for TWAP calculation and manipulation protection
    uint32 internal constant MIN_TWAP_PERIOD = 30 minutes;
    uint32 internal constant MAX_TWAP_PERIOD = 24 hours;
    uint32 internal constant DEFAULT_TWAP_PERIOD = 60 minutes;
    
    // Struct to track price observations for TWAP
    struct PriceObservation {
        uint32 timestamp;
        int24 tick;
        uint16 tickCumulativeIndex;  // For implementing circular buffer
    }
    
    // Struct to hold pool price tracking data
    struct PriceState {
        // Circular buffer of price observations
        PriceObservation[] observations;
        uint16 observationIndex;     // Current index in the observations array
        uint16 observationCardinality; // Number of observations recorded
        uint32 lastUpdateTimestamp;  // Last time observations were updated
        
        // Set to true if we detect potential manipulation
        bool potentialManipulation;
        
        // Configuration
        uint32 twapPeriod;          // Time window for TWAP calculation
        int24 maxTickDeviation;     // Maximum allowed deviation between TWAP and spot price
    }
    
    /**
     * @dev Initialize price observation state for a pool
     * @param state The price state storage to initialize
     * @param initialCapacity Initial capacity for observations array
     * @param twapPeriod TWAP window period (0 for default)
     */
    function initialize(
        PriceState storage state,
        uint16 initialCapacity,
        uint32 twapPeriod
    ) internal {
        require(initialCapacity > 0, "Capacity must be positive");
        
        // Set TWAP period (with default fallback)
        if (twapPeriod < MIN_TWAP_PERIOD) {
            state.twapPeriod = DEFAULT_TWAP_PERIOD;
        } else if (twapPeriod > MAX_TWAP_PERIOD) {
            state.twapPeriod = MAX_TWAP_PERIOD;
        } else {
            state.twapPeriod = twapPeriod;
        }
        
        // Default to 5% tick deviation (about 512 ticks)
        state.maxTickDeviation = 512;
        
        // Initialize observations array with empty slots
        state.observations = new PriceObservation[](initialCapacity);
        state.observationCardinality = 0;
        state.observationIndex = 0;
        state.lastUpdateTimestamp = uint32(block.timestamp);
        state.potentialManipulation = false;
    }
    
    /**
     * @dev Record a new price observation
     * @param state The price state storage to update
     * @param tick Current tick of the pool
     */
    function recordObservation(
        PriceState storage state,
        int24 tick
    ) internal {
        uint32 timestamp = uint32(block.timestamp);
        
        // Only update if enough time has passed
        if (timestamp > state.lastUpdateTimestamp) {
            uint16 index = state.observationIndex;
            
            // Record new observation
            state.observations[index] = PriceObservation({
                timestamp: timestamp,
                tick: tick,
                tickCumulativeIndex: index
            });
            
            // Update index for next observation (circular buffer)
            if (state.observationCardinality < state.observations.length) {
                // Still filling the buffer
                state.observationCardinality++;
            }
            
            // Move to next slot
            state.observationIndex = (index + 1) % uint16(state.observations.length);
            state.lastUpdateTimestamp = timestamp;
        }
    }
    
    /**
     * @dev Calculate TWAP tick from recorded observations
     * @param state The price state storage
     * @return twapTick The time-weighted average tick
     * @return sufficientData True if enough data for reliable TWAP
     */
    function calculateTwapTick(
        PriceState storage state
    ) internal view returns (int24 twapTick, bool sufficientData) {
        if (state.observationCardinality == 0) {
            return (0, false);
        }
        
        uint32 targetTimestamp = uint32(block.timestamp) - state.twapPeriod;
        
        // Find the oldest and newest observations we have
        uint32 oldestTimestamp = state.observations[0].timestamp;
        for (uint i = 1; i < state.observationCardinality; i++) {
            if (state.observations[i].timestamp < oldestTimestamp) {
                oldestTimestamp = state.observations[i].timestamp;
            }
        }
        
        // Check if we have enough data for a complete TWAP
        if (oldestTimestamp > targetTimestamp) {
            // Not enough data yet, but use what we have
            targetTimestamp = oldestTimestamp;
            sufficientData = false;
        } else {
            sufficientData = true;
        }
        
        // Calculate TWAP tick
        int24 cumulativeTick = 0;
        uint32 cumulativeTime = 0;
        
        // Sum over observations within our window
        for (uint i = 0; i < state.observationCardinality; i++) {
            PriceObservation storage obs = state.observations[i];
            
            if (obs.timestamp >= targetTimestamp) {
                // Calculate time for this observation's weight
                uint32 timeDelta;
                if (i == 0 || state.observationCardinality == 1) {
                    timeDelta = uint32(block.timestamp) - obs.timestamp;
                } else {
                    // Find next observation by timestamp
                    uint32 nextTimestamp = uint32(block.timestamp);
                    for (uint j = 0; j < state.observationCardinality; j++) {
                        if (j != i && state.observations[j].timestamp > obs.timestamp && 
                            state.observations[j].timestamp < nextTimestamp) {
                            nextTimestamp = state.observations[j].timestamp;
                        }
                    }
                    timeDelta = nextTimestamp - obs.timestamp;
                }
                
                // Add weighted contribution
                cumulativeTick += obs.tick * int24(int32(timeDelta));
                cumulativeTime += timeDelta;
            }
        }
        
        // Calculate average
        if (cumulativeTime > 0) {
            twapTick = cumulativeTick / int24(int32(cumulativeTime));
        } else {
            // If no time elapsed, return latest tick
            uint16 lastIndex = state.observationIndex == 0 ? 
                uint16(state.observations.length - 1) : 
                (state.observationIndex - 1);
            twapTick = state.observations[lastIndex].tick;
            sufficientData = false;
        }
        
        return (twapTick, sufficientData);
    }
    
    /**
     * @dev Check if the current price may be manipulated based on deviation from TWAP
     * @param state The price state storage
     * @param currentTick The current tick to check
     * @return manipulationDetected True if potential price manipulation is detected
     */
    function checkPriceManipulation(
        PriceState storage state,
        int24 currentTick
    ) internal returns (bool manipulationDetected) {
        // First record this observation
        recordObservation(state, currentTick);
        
        // Calculate TWAP
        (int24 twapTick, bool sufficientData) = calculateTwapTick(state);
        
        // If we don't have sufficient data, we can't be sure about manipulation
        if (!sufficientData) {
            state.potentialManipulation = false;
            return false;
        }
        
        // Calculate absolute deviation from TWAP
        int24 deviation = currentTick > twapTick ? 
            currentTick - twapTick : 
            twapTick - currentTick;
        
        // Check if deviation exceeds our threshold
        manipulationDetected = deviation > state.maxTickDeviation;
        
        // Update manipulation state
        state.potentialManipulation = manipulationDetected;
        
        return manipulationDetected;
    }
    
    /**
     * @dev Get a manipulation-resistant tick for operations
     * @param state The price state storage
     * @param currentTick The current observed tick
     * @return safeTickToUse The tick that should be used (either current or TWAP)
     */
    function getSafeTickForOperations(
        PriceState storage state,
        int24 currentTick
    ) internal view returns (int24 safeTickToUse) {
        // Check if we've previously detected manipulation
        if (state.potentialManipulation) {
            // Use TWAP instead of current tick
            (int24 twapTick, bool sufficientData) = calculateTwapTick(state);
            if (sufficientData) {
                return twapTick;
            }
        }
        
        // Otherwise use current tick
        return currentTick;
    }
    
    /**
     * @dev Update the maximum allowed tick deviation configuration
     * @param state The price state storage
     * @param newMaxTickDeviation New maximum tick deviation
     */
    function setMaxTickDeviation(
        PriceState storage state,
        int24 newMaxTickDeviation
    ) internal {
        require(newMaxTickDeviation > 0, "Deviation must be positive");
        state.maxTickDeviation = newMaxTickDeviation;
    }
    
    /**
     * @dev Update the TWAP period configuration
     * @param state The price state storage
     * @param newTwapPeriod New TWAP period in seconds
     */
    function setTwapPeriod(
        PriceState storage state,
        uint32 newTwapPeriod
    ) internal {
        if (newTwapPeriod < MIN_TWAP_PERIOD) {
            state.twapPeriod = MIN_TWAP_PERIOD;
        } else if (newTwapPeriod > MAX_TWAP_PERIOD) {
            state.twapPeriod = MAX_TWAP_PERIOD;
        } else {
            state.twapPeriod = newTwapPeriod;
        }
    }
} 