// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStrategyRegistry} from "./interfaces/IStrategyRegistry.sol";
import {IRebalanceStrategy} from "./interfaces/IRebalanceStrategy.sol";
import {IFeeCollectionStrategy} from "./interfaces/IFeeCollectionStrategy.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/**
 * @title StrategyRegistry
 * @notice Implementation of the strategy registry
 * @dev Manages registrations and retrievals of modular components
 */
contract StrategyRegistry is IStrategyRegistry {
    // Access control
    address public owner;
    
    // Error codes
    error Unauthorized();
    error StrategyAlreadyRegistered();
    error StrategyNotFound();
    
    // Events
    event RebalanceStrategyRegistered(string name, address strategy);
    event FeeCollectionStrategyRegistered(string name, address strategy);
    event PositionManagerRegistered(string name, address manager);
    event OwnershipTransferred(address previousOwner, address newOwner);
    
    // Storage
    mapping(string => IRebalanceStrategy) private rebalanceStrategies;
    mapping(string => IFeeCollectionStrategy) private feeCollectionStrategies;
    mapping(string => IPositionManager) private positionManagers;
    
    string[] private rebalanceStrategyNames;
    string[] private feeCollectionStrategyNames;
    string[] private positionManagerNames;
    
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
     * @notice Register a rebalance strategy
     * @param strategy The strategy contract address
     * @return success Whether the registration was successful
     */
    function registerRebalanceStrategy(IRebalanceStrategy strategy) external onlyOwner returns (bool success) {
        string memory name = strategy.getName();
        
        if (address(rebalanceStrategies[name]) != address(0)) revert StrategyAlreadyRegistered();
        
        rebalanceStrategies[name] = strategy;
        rebalanceStrategyNames.push(name);
        
        emit RebalanceStrategyRegistered(name, address(strategy));
        return true;
    }
    
    /**
     * @notice Register a fee collection strategy
     * @param strategy The strategy contract address
     * @return success Whether the registration was successful
     */
    function registerFeeCollectionStrategy(IFeeCollectionStrategy strategy) external onlyOwner returns (bool success) {
        string memory name = strategy.getName();
        
        if (address(feeCollectionStrategies[name]) != address(0)) revert StrategyAlreadyRegistered();
        
        feeCollectionStrategies[name] = strategy;
        feeCollectionStrategyNames.push(name);
        
        emit FeeCollectionStrategyRegistered(name, address(strategy));
        return true;
    }
    
    /**
     * @notice Register a position manager
     * @param manager The position manager contract address
     * @return success Whether the registration was successful
     */
    function registerPositionManager(IPositionManager manager) external onlyOwner returns (bool success) {
        string memory name = manager.getName();
        
        if (address(positionManagers[name]) != address(0)) revert StrategyAlreadyRegistered();
        
        positionManagers[name] = manager;
        positionManagerNames.push(name);
        
        emit PositionManagerRegistered(name, address(manager));
        return true;
    }
    
    /**
     * @notice Get a rebalance strategy by name
     * @param name The name of the strategy
     * @return strategy The strategy address
     */
    function getRebalanceStrategy(string calldata name) external view returns (IRebalanceStrategy strategy) {
        strategy = rebalanceStrategies[name];
        if (address(strategy) == address(0)) revert StrategyNotFound();
        return strategy;
    }
    
    /**
     * @notice Get a fee collection strategy by name
     * @param name The name of the strategy
     * @return strategy The strategy address
     */
    function getFeeCollectionStrategy(string calldata name) external view returns (IFeeCollectionStrategy strategy) {
        strategy = feeCollectionStrategies[name];
        if (address(strategy) == address(0)) revert StrategyNotFound();
        return strategy;
    }
    
    /**
     * @notice Get a position manager by name
     * @param name The name of the manager
     * @return manager The manager address
     */
    function getPositionManager(string calldata name) external view returns (IPositionManager manager) {
        manager = positionManagers[name];
        if (address(manager) == address(0)) revert StrategyNotFound();
        return manager;
    }
    
    /**
     * @notice Get all registered rebalance strategies
     * @return names Array of strategy names
     * @return strategies Array of strategy addresses
     */
    function getAllRebalanceStrategies() external view returns (string[] memory names, IRebalanceStrategy[] memory strategies) {
        uint256 length = rebalanceStrategyNames.length;
        names = new string[](length);
        strategies = new IRebalanceStrategy[](length);
        
        for (uint256 i = 0; i < length; i++) {
            names[i] = rebalanceStrategyNames[i];
            strategies[i] = rebalanceStrategies[names[i]];
        }
        
        return (names, strategies);
    }
    
    /**
     * @notice Get all registered fee collection strategies
     * @return names Array of strategy names
     * @return strategies Array of strategy addresses
     */
    function getAllFeeCollectionStrategies() external view returns (string[] memory names, IFeeCollectionStrategy[] memory strategies) {
        uint256 length = feeCollectionStrategyNames.length;
        names = new string[](length);
        strategies = new IFeeCollectionStrategy[](length);
        
        for (uint256 i = 0; i < length; i++) {
            names[i] = feeCollectionStrategyNames[i];
            strategies[i] = feeCollectionStrategies[names[i]];
        }
        
        return (names, strategies);
    }
    
    /**
     * @notice Get all registered position managers
     * @return names Array of manager names
     * @return managers Array of manager addresses
     */
    function getAllPositionManagers() external view returns (string[] memory names, IPositionManager[] memory managers) {
        uint256 length = positionManagerNames.length;
        names = new string[](length);
        managers = new IPositionManager[](length);
        
        for (uint256 i = 0; i < length; i++) {
            names[i] = positionManagerNames[i];
            managers[i] = positionManagers[names[i]];
        }
        
        return (names, managers);
    }
} 