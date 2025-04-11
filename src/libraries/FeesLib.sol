// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @title FeesLib
 * @dev Library for fee collection and reinvestment functionality
 */
library FeesLib {
    /**
     * @dev Collect fees from a position
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @return feesToken0 Amount of token0 fees collected
     * @return feesToken1 Amount of token1 fees collected
     */
    function collectFees(
        IPoolManager poolManager,
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick
    ) internal returns (uint256 feesToken0, uint256 feesToken1) {
        // Set up parameters to collect fees
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: 0, // Just collecting fees
            salt: 0
        });
        
        // Call modifyLiquidity with zero liquidityDelta to collect fees
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(key, params, "");
        
        // Process fees - positive deltas represent fees collected
        if (delta.amount0() > 0) {
            feesToken0 = uint256(uint128(delta.amount0()));
        }
        
        if (delta.amount1() > 0) {
            feesToken1 = uint256(uint128(delta.amount1()));
        }
        
        return (feesToken0, feesToken1);
    }
    
    /**
     * @dev Reinvest fees by adding liquidity
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     * @return liquidityAdded Amount of liquidity added
     */
    function reinvestFees(
        IPoolManager poolManager,
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint128 liquidityAdded) {
        // Calculate liquidity to add based on available tokens
        // This would normally use a function to calculate the maximum liquidity
        uint128 liquidityToAdd = calculateLiquidityForAmounts(
            lowerTick,
            upperTick,
            amount0,
            amount1
        );
        
        // Set up parameters to add liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: int256(uint256(liquidityToAdd)),
            salt: 0
        });
        
        // Add the liquidity
        poolManager.modifyLiquidity(key, params, "");
        
        return liquidityToAdd;
    }
    
    /**
     * @dev Calculate liquidity amount for given token amounts
     * @param lowerTick Lower tick of the position
     * @param upperTick Upper tick of the position
     * @param amount0 Amount of token0 available
     * @param amount1 Amount of token1 available
     * @return liquidity Amount of liquidity that can be added
     */
    function calculateLiquidityForAmounts(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        // This should be implemented according to Uniswap V3's math
        // For now, return a placeholder value
        // Silence the unused parameter warnings by referencing them
        if (false) {
            lowerTick;
            upperTick;
            amount0;
            amount1;
        }
        
        liquidity = 0;
        return liquidity;
    }
    
    /**
     * @dev Determines if collected fees are worth reinvesting
     * @param amount0 Amount of token0 fees
     * @param amount1 Amount of token1 fees
     * @param minAmount Minimum amount threshold
     * @param price Current price in Q64.96 format
     * @return isWorthwhile True if reinvestment is economical
     */
    function isReinvestmentWorthwhile(
        uint256 amount0,
        uint256 amount1,
        uint256 minAmount,
        uint160 price
    ) internal pure returns (bool isWorthwhile) {
        // Skip if both fees are zero
        if (amount0 == 0 && amount1 == 0) {
            return false;
        }
        
        // Convert to a common denomination (using token1 as the base)
        // price is in Q64.96 format (token1/token0)
        uint256 totalValueInToken1 = amount1;
        if (amount0 > 0) {
            // Convert amount0 to token1 equivalent using the current price
            totalValueInToken1 += (amount0 * uint256(price)) >> 96;
        }
        
        // Compare against threshold
        return totalValueInToken1 >= minAmount;
    }
} 