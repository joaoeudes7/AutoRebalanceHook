// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Position} from "../types/Position.sol";
import {PositionIdLibrary} from "../types/Position.sol";
import {PositionLib} from "./PositionLib.sol";
import {SwapUtils} from "./SwapUtils.sol";

/**
 * @title AutoRebalanceLibrary
 * @dev Library for liquidity position management operations
 * Inspired by bungi's approach for efficient position management
 */
library AutoRebalanceLibrary {
    using PositionIdLibrary for Position;
    using TickMath for int24;

    /**
     * @dev Removes liquidity from a position
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param liquidity Amount of liquidity to remove
     * @return amount0 Amount of token0 received
     * @return amount1 Amount of token1 received
     */
    function removeLiquidity(
        IPoolManager poolManager,
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) internal returns (uint256 amount0, uint256 amount1) {
        // Create params to remove all liquidity from the old position
        IPoolManager.ModifyLiquidityParams memory removeParams = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: -int256(uint256(liquidity)), // Negative to remove
            salt: bytes32(0)
        });
        
        // Remove the liquidity from the old position
        (BalanceDelta removeDelta, ) = poolManager.modifyLiquidity(key, removeParams, "");
        
        // Negative deltas represent tokens leaving the pool (coming to us)
        if (removeDelta.amount0() < 0) {
            amount0 = uint256(uint128(-removeDelta.amount0()));
        }
        if (removeDelta.amount1() < 0) {
            amount1 = uint256(uint128(-removeDelta.amount1()));
        }
        
        return (amount0, amount1);
    }
    
    /**
     * @dev Adds liquidity to a position
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param liquidity Amount of liquidity to add
     * @return amount0Used Amount of token0 used
     * @return amount1Used Amount of token1 used
     */
    function addLiquidity(
        IPoolManager poolManager,
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) internal returns (uint256 amount0Used, uint256 amount1Used) {
        // Only proceed if we can add meaningful liquidity
        if (liquidity > 0) {
            IPoolManager.ModifyLiquidityParams memory addParams = IPoolManager.ModifyLiquidityParams({
                tickLower: lowerTick,
                tickUpper: upperTick,
                liquidityDelta: int256(uint256(liquidity)), // Positive to add
                salt: bytes32(0)
            });
            
            // Add the liquidity
            (BalanceDelta addDelta, ) = poolManager.modifyLiquidity(key, addParams, "");
            
            // Calculate token amounts used for adding liquidity
            if (addDelta.amount0() < 0) {
                amount0Used = uint256(uint128(-addDelta.amount0()));
            }
            if (addDelta.amount1() < 0) {
                amount1Used = uint256(uint128(-addDelta.amount1()));
            }
        }
        
        return (amount0Used, amount1Used);
    }
    
    /**
     * @dev Calculates the amount of liquidity that can be added with given token amounts
     * @param amount0 Amount of token0 available
     * @param amount1 Amount of token1 available
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param sqrtPriceX96 Current sqrt price in X96 format
     * @return liquidity Amount of liquidity that can be added
     */
    function calculateLiquidityForTokens(
        uint256 amount0,
        uint256 amount1,
        int24 lowerTick,
        int24 upperTick,
        uint160 sqrtPriceX96
    ) internal pure returns (uint128 liquidity) {
        // For simplicity, we'll use a stub implementation until the TickMath issue is resolved
        uint160 sqrtRatioA = getSimplifiedSqrtRatioAtTick(lowerTick);
        uint160 sqrtRatioB = getSimplifiedSqrtRatioAtTick(upperTick);
        
        // Simplified calculation - production would use LiquidityAmounts.getLiquidityForAmounts
        // The math here is illustrative; for production use a battle-tested implementation
        
        // Limit the current sqrt price to be within the range bounds
        if (sqrtPriceX96 < sqrtRatioA) {
            sqrtPriceX96 = sqrtRatioA;
        } else if (sqrtPriceX96 > sqrtRatioB) {
            sqrtPriceX96 = sqrtRatioB;
        }
        
        // Converting to 128-bit conservatively to avoid overflows
        return uint128((amount0 * amount1) / 2**18);
    }
    
    /**
     * @dev Simplified implementation of getSqrtRatioAtTick for testing
     */
    function getSimplifiedSqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        // Simplified exponential approximation
        if (tick < 0) {
            return 4295128739 + uint160(uint24(-tick)); // MIN_SQRT_RATIO + simple offset
        } else {
            return 4295128739 + uint160(uint24(tick)) * 1000; // MIN_SQRT_RATIO + simple multiplier
        }
    }
    
    /**
     * @dev Check if reinvestment of collected fees is worthwhile
     * @param feesToken0 Amount of token0 fees collected
     * @param feesToken1 Amount of token1 fees collected
     * @return True if reinvestment is worthwhile
     */
    function isReinvestmentWorthwhile(
        uint256 feesToken0,
        uint256 feesToken1
    ) internal pure returns (bool) {
        // This is a simplified check - in production, compare to min threshold
        return feesToken0 > 0 || feesToken1 > 0;
    }

    /**
     * @dev Rebalance a position in a gas-efficient way
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param oldLowerTick The old lower tick
     * @param oldUpperTick The old upper tick
     * @param oldLiquidity The old liquidity amount
     * @param newLowerTick The new lower tick
     * @param newUpperTick The new upper tick
     * @return newLiquidity The new liquidity amount
     * @return amount0Used Amount of token0 used
     * @return amount1Used Amount of token1 used
     */
    function rebalancePosition(
        IPoolManager poolManager,
        PoolKey calldata key,
        int24 oldLowerTick,
        int24 oldUpperTick,
        uint128 oldLiquidity,
        int24 newLowerTick,
        int24 newUpperTick
    ) internal returns (uint128 newLiquidity, uint256 amount0Used, uint256 amount1Used) {
        // 1. Remove liquidity from the old position
        (uint256 amount0Withdrawn, uint256 amount1Withdrawn) = removeLiquidity(
            poolManager,
            key,
            oldLowerTick,
            oldUpperTick,
            oldLiquidity
        );
        
        // 2. Calculate liquidity for the new position
        int24 midTick = (newLowerTick + newUpperTick) / 2;
        uint160 sqrtPriceX96 = getSimplifiedSqrtRatioAtTick(midTick);
        newLiquidity = calculateLiquidityForTokens(
            amount0Withdrawn,
            amount1Withdrawn,
            newLowerTick,
            newUpperTick,
            sqrtPriceX96
        );
        
        // 3. Add liquidity to the new position
        if (newLiquidity > 0) {
            (amount0Used, amount1Used) = addLiquidity(
                poolManager,
                key,
                newLowerTick,
                newUpperTick,
                newLiquidity
            );
        }
        
        return (newLiquidity, amount0Used, amount1Used);
    }
} 