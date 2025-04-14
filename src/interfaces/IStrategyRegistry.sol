// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebalanceStrategy} from "./IRebalanceStrategy.sol";
import {IFeeCollectionStrategy} from "./IFeeCollectionStrategy.sol";
import {IPositionManager} from "./IPositionManager.sol";

/**
 * @title IStrategyRegistry
 * @notice Interface for the strategy registry
 * @dev Manages registration and retrieval of strategy modules
 */
interface IStrategyRegistry {
    /**
     * @notice Register a rebalance strategy
     * @param strategy The strategy contract address
     * @return success Whether the registration was successful
     */
    function registerRebalanceStrategy(IRebalanceStrategy strategy) external returns (bool success);
    
    /**
     * @notice Register a fee collection strategy
     * @param strategy The strategy contract address
     * @return success Whether the registration was successful
     */
    function registerFeeCollectionStrategy(IFeeCollectionStrategy strategy) external returns (bool success);
    
    /**
     * @notice Register a position manager
     * @param manager The position manager contract address
     * @return success Whether the registration was successful
     */
    function registerPositionManager(IPositionManager manager) external returns (bool success);
    
    /**
     * @notice Get a rebalance strategy by name
     * @param name The name of the strategy
     * @return strategy The strategy address
     */
    function getRebalanceStrategy(string calldata name) external view returns (IRebalanceStrategy strategy);
    
    /**
     * @notice Get a fee collection strategy by name
     * @param name The name of the strategy
     * @return strategy The strategy address
     */
    function getFeeCollectionStrategy(string calldata name) external view returns (IFeeCollectionStrategy strategy);
    
    /**
     * @notice Get a position manager by name
     * @param name The name of the manager
     * @return manager The manager address
     */
    function getPositionManager(string calldata name) external view returns (IPositionManager manager);
    
    /**
     * @notice Get all registered rebalance strategies
     * @return names Array of strategy names
     * @return strategies Array of strategy addresses
     */
    function getAllRebalanceStrategies() external view returns (string[] memory names, IRebalanceStrategy[] memory strategies);
    
    /**
     * @notice Get all registered fee collection strategies
     * @return names Array of strategy names
     * @return strategies Array of strategy addresses
     */
    function getAllFeeCollectionStrategies() external view returns (string[] memory names, IFeeCollectionStrategy[] memory strategies);
    
    /**
     * @notice Get all registered position managers
     * @return names Array of manager names
     * @return managers Array of manager addresses
     */
    function getAllPositionManagers() external view returns (string[] memory names, IPositionManager[] memory managers);
} 