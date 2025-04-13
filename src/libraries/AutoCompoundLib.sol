// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

import {PositionLib} from "./PositionLib.sol";
import {SwapUtils} from "./SwapUtils.sol";
import {AutoMoveLibrary} from "./AutoMoveLibrary.sol";

/**
 * @title AutoCompoundLib
 * @dev Library for auto-compounding fees and reinvestment logic
 */
library AutoCompoundLib {
    /**
     * @dev Collects fees from a position
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
        // Create modify liquidity params with zero liquidityDelta to collect fees
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: lowerTick,
            tickUpper: upperTick,
            liquidityDelta: 0, // Zero liquidityDelta means we're just collecting fees
            salt: bytes32(0)
        });
        
        // Call modifyLiquidity on the pool manager
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(key, params, "");
        
        // Process returned balance delta - positive values represent fees collected
        if (delta.amount0() > 0) {
            feesToken0 = uint256(uint128(delta.amount0()));
        }
        
        if (delta.amount1() > 0) {
            feesToken1 = uint256(uint128(delta.amount1()));
        }
        
        return (feesToken0, feesToken1);
    }
    
    /**
     * @dev Determines if it's time to collect fees based on last collection time
     * @param lastFeeCollectionTimestamp Timestamp of last fee collection
     * @param feeCollectionInterval Minimum time between fee collections
     * @return isDue Whether fee collection is due
     */
    function isFeeCollectionDue(
        uint256 lastFeeCollectionTimestamp,
        uint256 feeCollectionInterval
    ) internal view returns (bool isDue) {
        return block.timestamp >= lastFeeCollectionTimestamp + feeCollectionInterval;
    }
    
    /**
     * @dev Calculates if a swap is needed to optimize token balances for reinvestment
     * @param feesToken0 Amount of token0 fees
     * @param feesToken1 Amount of token1 fees
     * @param sqrtPriceX96 Current price as a Q64.96 value
     * @param position Current position
     * @return needSwap Whether a swap is needed
     * @return zeroForOne Direction of swap (true if token0 for token1)
     * @return amountToSwap Amount to swap
     */
    function calculateSwapForReinvestment(
        uint256 feesToken0,
        uint256 feesToken1,
        uint160 sqrtPriceX96,
        PositionLib.Position memory position
    ) internal pure returns (bool needSwap, bool zeroForOne, uint256 amountToSwap) {
        return SwapUtils.calculateSwapForBalance(
            feesToken0,
            feesToken1,
            sqrtPriceX96,
            position.lowerTick,
            position.upperTick
        );
    }
    
    /**
     * @dev Reinvests the collected fees by adding liquidity to the position
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param position The current position
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     * @param sqrtPriceX96 Current sqrt price in X96 format
     * @return addedLiquidity Amount of liquidity added
     * @return amount0Used Amount of token0 used
     * @return amount1Used Amount of token1 used
     */
    function reinvestFees(
        IPoolManager poolManager,
        PoolKey calldata key,
        PositionLib.Position memory position,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtPriceX96
    ) internal returns (uint128 addedLiquidity, uint256 amount0Used, uint256 amount1Used) {
        // Calculate liquidity to add based on available tokens
        addedLiquidity = AutoMoveLibrary.calculateLiquidityForTokens(
            amount0,
            amount1,
            position.lowerTick,
            position.upperTick,
            sqrtPriceX96
        );
        
        // Only add liquidity if we calculated a valid amount
        if (addedLiquidity > 0) {
            (amount0Used, amount1Used) = AutoMoveLibrary.addLiquidity(
                poolManager,
                key,
                position.lowerTick,
                position.upperTick,
                addedLiquidity
            );
        }
        
        return (addedLiquidity, amount0Used, amount1Used);
    }

    /**
     * @dev Handle fee compounding for a position
     */
    function handleFeeCompounding(
        PoolKey calldata /* key */,
        PositionLib.Position storage position,
        int24 currentTick,
        uint256 /* minReinvestmentAmount */
    ) internal {
        // Skip if position is out of range
        if (currentTick < position.lowerTick || currentTick > position.upperTick) return;
        
        // Update timestamp to prevent reentrancy
        position.lastFeeCollectionTimestamp = block.timestamp;
    }
} 