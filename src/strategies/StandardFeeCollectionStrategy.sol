// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFeeCollectionStrategy} from "../interfaces/IFeeCollectionStrategy.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title StandardFeeCollectionStrategy
 * @notice A standard implementation of fee collection strategy
 * @dev Provides basic fee collection logic that works for most cases
 */
contract StandardFeeCollectionStrategy is IFeeCollectionStrategy {
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
     * @notice Check if fees should be collected for a position
     * @param lastFeeCollection Timestamp of the last fee collection
     * @param collectionInterval Minimum time between fee collections
     * @return shouldCollect True if fees should be collected
     */
    function shouldCollectFees(
        bytes32 /* poolId */,
        uint256 lastFeeCollection,
        uint256 collectionInterval
    ) external view returns (bool shouldCollect) {
        // Base strategy simply checks if enough time has passed since last collection
        return block.timestamp >= lastFeeCollection + collectionInterval;
    }
    
    /**
     * @notice Collect fees from a position
     * @return feesToken0 Amount of token0 fees collected
     * @return feesToken1 Amount of token1 fees collected
     */
    function collectFees(
        IPoolManager /* poolManager */,
        PoolKey calldata /* poolKey */,
        bytes32 /* poolId */,
        int24 /* lowerTick */,
        int24 /* upperTick */,
        uint256 /* minReinvestmentAmount */
    ) external pure returns (uint256 feesToken0, uint256 feesToken1) {
        // Standard implementation simply returns zeros as actual fee collection
        // should be handled by the hook itself
        return (0, 0);
    }
    
    /**
     * @notice Determine if collected fees should be reinvested
     * @param token0Amount Amount of token0 collected
     * @param token1Amount Amount of token1 collected
     * @param minReinvestmentAmount Minimum amount to consider for reinvestment
     * @return shouldReinvest True if fees should be reinvested
     */
    function shouldReinvestFees(
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 minReinvestmentAmount,
        uint160 /* sqrtPriceX96 */
    ) external pure returns (bool shouldReinvest) {
        // Simple logic - reinvest if either token amount is greater than the minimum
        return token0Amount >= minReinvestmentAmount || token1Amount >= minReinvestmentAmount;
    }
    
    /**
     * @notice Get the strategy name
     * @return name The name of the strategy
     */
    function getName() external pure returns (string memory name) {
        return "StandardFeeCollectionStrategy";
    }
} 