// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebalanceStrategy} from "./IRebalanceStrategy.sol";
import {IFeeCollectionStrategy} from "./IFeeCollectionStrategy.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @title IAutoRebalanceHook
 * @notice Interface for the AutoRebalanceHook
 * @dev Defines methods for managing the hook and its modular components
 */
interface IAutoRebalanceHook {
    /**
     * @notice Set the rebalance strategy for a pool
     * @param poolKey The pool key
     * @param strategy The strategy contract address
     * @return success Whether the operation was successful
     */
    function setRebalanceStrategy(PoolKey calldata poolKey, IRebalanceStrategy strategy) external returns (bool success);
    
    /**
     * @notice Set the fee collection strategy for a pool
     * @param poolKey The pool key
     * @param strategy The strategy contract address
     * @return success Whether the operation was successful
     */
    function setFeeCollectionStrategy(PoolKey calldata poolKey, IFeeCollectionStrategy strategy) external returns (bool success);
    
    /**
     * @notice Set the position manager for a pool
     * @param poolKey The pool key
     * @param manager The position manager contract address
     * @return success Whether the operation was successful
     */
    function setPositionManager(PoolKey calldata poolKey, IPositionManager manager) external returns (bool success);
    
    /**
     * @notice Get the current rebalance strategy for a pool
     * @param poolKey The pool key
     * @return strategy The current strategy
     */
    function getRebalanceStrategy(PoolKey calldata poolKey) external view returns (IRebalanceStrategy strategy);
    
    /**
     * @notice Get the current fee collection strategy for a pool
     * @param poolKey The pool key
     * @return strategy The current strategy
     */
    function getFeeCollectionStrategy(PoolKey calldata poolKey) external view returns (IFeeCollectionStrategy strategy);
    
    /**
     * @notice Get the current position manager for a pool
     * @param poolKey The pool key
     * @return manager The current manager
     */
    function getPositionManager(PoolKey calldata poolKey) external view returns (IPositionManager manager);
    
    /**
     * @notice Configure pool parameters
     * @param poolKey The pool key
     * @param tickRange Tick range for positions
     * @param rebalanceThreshold Threshold percentage for rebalancing
     * @param cooldownPeriod Cooldown period between rebalances
     * @param feeCollectionInterval Interval between fee collections
     * @return success Whether the operation was successful
     */
    function configurePool(
        PoolKey calldata poolKey,
        int24 tickRange,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod,
        uint256 feeCollectionInterval
    ) external returns (bool success);
    
    /**
     * @notice Manually trigger rebalancing for a pool
     * @param poolKey The pool key
     * @return success Whether the operation was successful
     */
    function manuallyRebalance(PoolKey calldata poolKey) external returns (bool success);
    
    /**
     * @notice Manually trigger fee collection for a pool
     * @param poolKey The pool key
     * @return success Whether the operation was successful
     */
    function manuallyCollectFees(PoolKey calldata poolKey) external returns (bool success);
} 