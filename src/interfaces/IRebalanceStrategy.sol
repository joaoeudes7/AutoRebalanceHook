// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title IRebalanceStrategy
 * @notice Interface for rebalancing strategy modules
 * @dev Implements logic for when and how to rebalance positions
 */
interface IRebalanceStrategy {
    /**
     * @notice Check if a position should be rebalanced
     * @param poolId The pool ID
     * @param lowerTick Current lower tick of the position
     * @param upperTick Current upper tick of the position
     * @param currentTick The current tick of the pool
     * @param lastRebalance Timestamp of the last rebalance
     * @param rebalanceThreshold Threshold percentage for rebalancing
     * @param cooldownPeriod Minimum time between rebalances
     * @return shouldRebalance True if position should be rebalanced
     */
    function shouldRebalance(
        bytes32 poolId,
        int24 lowerTick,
        int24 upperTick,
        int24 currentTick,
        uint256 lastRebalance,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod
    ) external view returns (bool shouldRebalance);
    
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
    ) external pure returns (int24 lowerTick, int24 upperTick);
    
    /**
     * @notice Get the strategy name
     * @return name The name of the strategy
     */
    function getName() external pure returns (string memory name);
} 