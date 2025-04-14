// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title IFeeCollectionStrategy
 * @notice Interface for fee collection strategy modules
 * @dev Implements logic for when and how to collect fees
 */
interface IFeeCollectionStrategy {
    /**
     * @notice Check if fees should be collected for a position
     * @param poolId The pool ID
     * @param lastFeeCollection Timestamp of the last fee collection
     * @param collectionInterval Minimum time between fee collections
     * @return shouldCollect True if fees should be collected
     */
    function shouldCollectFees(
        bytes32 poolId,
        uint256 lastFeeCollection,
        uint256 collectionInterval
    ) external view returns (bool shouldCollect);
    
    /**
     * @notice Collect fees from a position
     * @param poolManager Pool manager instance
     * @param poolKey Pool key
     * @param poolId Pool ID
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param minReinvestmentAmount Minimum amount to consider for reinvestment
     * @return feesToken0 Amount of token0 fees collected
     * @return feesToken1 Amount of token1 fees collected
     */
    function collectFees(
        IPoolManager poolManager,
        PoolKey calldata poolKey,
        bytes32 poolId,
        int24 lowerTick,
        int24 upperTick,
        uint256 minReinvestmentAmount
    ) external returns (uint256 feesToken0, uint256 feesToken1);
    
    /**
     * @notice Determine if collected fees should be reinvested
     * @param token0Amount Amount of token0 collected
     * @param token1Amount Amount of token1 collected
     * @param minReinvestmentAmount Minimum amount to consider for reinvestment
     * @param sqrtPriceX96 Current sqrt price
     * @return shouldReinvest True if fees should be reinvested
     */
    function shouldReinvestFees(
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 minReinvestmentAmount,
        uint160 sqrtPriceX96
    ) external pure returns (bool shouldReinvest);
    
    /**
     * @notice Get the strategy name
     * @return name The name of the strategy
     */
    function getName() external pure returns (string memory name);
} 