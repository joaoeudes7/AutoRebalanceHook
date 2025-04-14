// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {PositionLib} from "./PositionLib.sol";
import {SwapUtils} from "./SwapUtils.sol";
import {TickLib} from "./TickLib.sol";
import {OracleLib} from "./OracleLib.sol";
import {AutoMoveLibrary} from "./AutoMoveLibrary.sol";

/**
 * @title RebalanceLib
 * @dev Library for handle rebalancing logic
 */
library RebalanceLib {
    // Custom errors
    error TransactionExpired();
    error InvalidPriceRange();
    error SlippageExceeded(uint256 amountOut, uint256 amountOutMin);
    
    event PotentialManipulationDetected(bytes32 indexed poolId, uint256 timestamp);

    /**
     * @dev Executes a protected swap with slippage protection
     * @param poolManager The pool manager contract
     * @param key The pool key
     * @param zeroForOne Direction of the swap
     * @param amountIn Amount to swap
     * @param amountOutMin Minimum amount to receive
     * @param sqrtPriceLimitX96 Price limit for the swap
     * @return amountInUsed Amount actually swapped
     * @return amountOut Amount received
     */
    function executeProtectedSwap(
        IPoolManager poolManager,
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        uint160 sqrtPriceLimitX96
    ) internal returns (uint256 amountInUsed, uint256 amountOut) {
        // Define swap parameters
        // Use exact input to ensure we don't spend more than amountIn
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        
        // Execute the swap
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        // Calculate amounts in and out
        if (zeroForOne) {
            // Token0 → Token1 swap
            amountInUsed = uint256(uint128(-delta.amount0()));
            amountOut = uint256(uint128(delta.amount1()));
        } else {
            // Token1 → Token0 swap
            amountInUsed = uint256(uint128(-delta.amount1()));
            amountOut = uint256(uint128(delta.amount0()));
        }
        
        // Verify minimum amount out
        if (amountOut < amountOutMin) {
            revert SlippageExceeded(amountOut, amountOutMin);
        }
        
        return (amountInUsed, amountOut);
    }
    
    /**
     * @dev Prepare price limits for swap with slippage protection
     * @param zeroForOne Whether to swap from token0 to token1
     * @return sqrtPriceLimitX96 Price limit for the swap
     */
    function getPriceLimitWithBuffer(bool zeroForOne) internal pure returns (uint160 sqrtPriceLimitX96) {
        if (zeroForOne) {
            // Token0 to Token1 swap (price decreases)
            // Use a higher minimum price than the absolute minimum to limit slippage
            sqrtPriceLimitX96 = 4295128740 + 100000000; // MIN_SQRT_RATIO + buffer
        } else {
            // Token1 to Token0 swap (price increases)
            // Use a lower maximum price than the absolute maximum to limit slippage
            sqrtPriceLimitX96 = 1461446703485210103287273052203988822378723970341 - 100000000; // MAX_SQRT_RATIO - buffer
        }
        
        return sqrtPriceLimitX96;
    }
    
    /**
     * @dev Determines if a position should be rebalanced based on the current tick
     * @param position Current position
     * @param currentTick Current tick
     * @param rebalanceThreshold Threshold percentage for rebalancing
     * @return shouldRebalance Whether position needs rebalancing
     */
    function needsRebalance(
        PositionLib.Position memory position,
        int24 currentTick,
        uint256 rebalanceThreshold
    ) internal pure returns (bool shouldRebalance) {
        // Quick return if position is inactive
        if (!position.isActive) return false;
        
        // Quick return if out of range (definitely needs rebalancing)
        if (currentTick <= position.lowerTick || currentTick >= position.upperTick) {
            return true;
        }
        
        // Calculate distance from current tick to position boundaries as percentage
        uint256 distanceToLower;
        uint256 distanceToUpper;
        uint256 totalRange;
        
        unchecked {
            distanceToLower = uint24(currentTick - position.lowerTick);
            distanceToUpper = uint24(position.upperTick - currentTick);
            totalRange = uint24(position.upperTick - position.lowerTick);
        }
        
        // Calculate how far we are from center as a percentage
        uint256 centerDeviation;
        unchecked {
            if (distanceToLower > distanceToUpper) {
                centerDeviation = ((distanceToLower - distanceToUpper) * 100) / totalRange;
            } else {
                centerDeviation = ((distanceToUpper - distanceToLower) * 100) / totalRange;
            }
        }
        
        return centerDeviation >= rebalanceThreshold;
    }
    
    /**
     * @dev Calculates new optimal tick range based on current tick and spacing
     * @param currentTick Current tick
     * @param tickSpacing Tick spacing
     * @param rangeTicks Number of ticks to use for the range
     * @return lowerTick Lower tick of the new position
     * @return upperTick Upper tick of the new position
     */
    function calculateNewRange(
        int24 currentTick,
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24 lowerTick, int24 upperTick) {
        lowerTick = TickLib.calculateLowerTick(currentTick, tickSpacing, rangeTicks);
        upperTick = TickLib.calculateUpperTick(currentTick, tickSpacing, rangeTicks);
        return (lowerTick, upperTick);
    }
    
    /**
     * @dev Validates transaction deadline
     * @param deadline Transaction deadline
     */
    function validateDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert TransactionExpired();
        }
    }

    /**
     * @dev Get the current tick safely, with manipulation protection if enabled
     */
    function getCurrentTick(
        PoolKey calldata /* key */,
        PositionLib.Position memory position,
        OracleLib.PriceState storage priceState,
        bool useManipulationProtection
    ) internal returns (int24) {
        // For now, use the middle of the position range as an approximation
        int24 currentTick = (position.lowerTick + position.upperTick) / 2;
        
        if (useManipulationProtection) {
            if (OracleLib.checkPriceManipulation(priceState, currentTick)) {
                currentTick = OracleLib.getSafeTickForOperations(priceState, currentTick);
            }
        }
        
        OracleLib.recordObservation(priceState, currentTick);
        return currentTick;
    }

    /**
     * @dev Sets a new range for a position
     */
    function setNewRange(
        PoolKey calldata /* key */,
        bytes32 /* poolId */,
        PositionLib.Position storage position,
        int24 newLowerTick,
        int24 newUpperTick
    ) internal {
        position.lowerTick = newLowerTick;
        position.upperTick = newUpperTick;
    }
} 