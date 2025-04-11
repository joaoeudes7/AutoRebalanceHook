// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PositionLib} from "./PositionLib.sol";
import {OracleLib} from "./OracleLib.sol";
import {RebalanceLib} from "./RebalanceLib.sol";
import {AutoCompoundLib} from "./AutoCompoundLib.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

/**
 * @title HookLib
 * @dev Library for handling Uniswap V4 hook-specific functions
 */
library HookLib {
    /**
     * @dev Get hook permissions
     */
    function getPermissions() internal pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @dev Handle after initialize hook
     */
    function handleAfterInitialize(
        mapping(bytes32 => PositionLib.Position) storage positions,
        mapping(bytes32 => OracleLib.PriceState) storage priceStates,
        PoolKey calldata key,
        int24 tick,
        int24 defaultTickRange,
        uint32 twapWindow
    ) internal returns (bytes4) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        
        // Initialize position tracking with default range
        positions[poolId] = PositionLib.Position({
            lowerTick: tick - defaultTickRange,
            upperTick: tick + defaultTickRange,
            liquidity: 0,
            isActive: true,
            lastFeeCollectionTimestamp: block.timestamp,
            token0Balance: 0,
            token1Balance: 0
        });
        
        // Initialize price observation state
        OracleLib.initialize(priceStates[poolId], 24, twapWindow);
        
        // Record the first observation
        OracleLib.recordObservation(priceStates[poolId], tick);
        
        return BaseHook.afterInitialize.selector;
    }

    /**
     * @dev Handle after swap hook
     */
    function handleAfterSwap(
        mapping(bytes32 => PositionLib.Position) storage positions,
        mapping(bytes32 => OracleLib.PriceState) storage priceStates,
        PoolKey calldata key,
        bool useManipulationProtection,
        uint256 rebalanceThreshold,
        uint256 feeCollectionInterval,
        uint256 minReinvestmentAmount,
        int24 rangeTicks
    ) internal returns (bytes4, int128) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        PositionLib.Position storage position = positions[poolId];
        
        // Get current tick with manipulation protection
        int24 currentTick = RebalanceLib.getCurrentTick(
            key,
            position,
            priceStates[poolId],
            useManipulationProtection
        );
        
        // Check if rebalance is needed
        if (RebalanceLib.needsRebalance(position, currentTick, rebalanceThreshold)) {
            (int24 newLowerTick, int24 newUpperTick) = RebalanceLib.calculateNewRange(
                currentTick,
                key.tickSpacing,
                rangeTicks
            );
            
            RebalanceLib.setNewRange(
                key,
                poolId,
                position,
                newLowerTick,
                newUpperTick
            );
        }
        
        // Handle fee auto-compounding
        if (AutoCompoundLib.isFeeCollectionDue(position.lastFeeCollectionTimestamp, feeCollectionInterval)) {
            AutoCompoundLib.handleFeeCompounding(
                key,
                position,
                currentTick,
                minReinvestmentAmount
            );
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }
} 