// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @title IPositionManager
 * @notice Interface for position management modules
 * @dev Implements logic for managing liquidity positions
 */
interface IPositionManager {
    /**
     * @notice Create a new position
     * @param poolManager Pool manager instance
     * @param poolKey Pool key
     * @param poolId Pool ID
     * @param lowerTick Lower tick
     * @param upperTick Upper tick
     * @param liquidity Amount of liquidity to add
     * @return success Whether the operation was successful
     * @return delta Balance delta from the operation
     */
    function createPosition(
        IPoolManager poolManager,
        PoolKey calldata poolKey,
        bytes32 poolId,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (bool success, BalanceDelta delta);
    
    /**
     * @notice Update an existing position
     * @param poolManager Pool manager instance
     * @param poolKey Pool key
     * @param poolId Pool ID
     * @param oldLowerTick Current lower tick
     * @param oldUpperTick Current upper tick
     * @param newLowerTick New lower tick
     * @param newUpperTick New upper tick
     * @param currentLiquidity Current liquidity amount
     * @return success Whether the operation was successful
     * @return delta Balance delta from the operation
     */
    function updatePosition(
        IPoolManager poolManager,
        PoolKey calldata poolKey,
        bytes32 poolId,
        int24 oldLowerTick,
        int24 oldUpperTick,
        int24 newLowerTick,
        int24 newUpperTick,
        uint128 currentLiquidity
    ) external returns (bool success, BalanceDelta delta);
    
    /**
     * @notice Calculate optimal liquidity distribution
     * @param currentTick Current pool tick
     * @param lowerTick Lower tick
     * @param upperTick Upper tick
     * @param amount0 Available amount of token0
     * @param amount1 Available amount of token1
     * @param sqrtPriceX96 Current sqrt price
     * @return liquidity Optimal liquidity amount
     */
    function calculateOptimalLiquidity(
        int24 currentTick,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) external pure returns (uint128 liquidity);
    
    /**
     * @notice Get the manager name
     * @return name The name of the position manager
     */
    function getName() external pure returns (string memory name);
} 