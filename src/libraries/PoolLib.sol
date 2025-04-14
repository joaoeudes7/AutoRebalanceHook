// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

/**
 * @title PoolLib
 * @dev Library for interacting with Uniswap V4 pool functionality
 */
library PoolLib {
    /**
     * @notice Get the current tick of a pool
     * @param poolManager The Uniswap V4 pool manager
     * @param key The pool key
     * @return tick The current tick
     */
    function getCurrentTick(IPoolManager poolManager, PoolKey memory key) internal view returns (int24 tick) {
        // Get the current slot0 data from the pool using StateLibrary
        // Ignoring other return values from getSlot0
        (, tick,,) = StateLibrary.getSlot0(poolManager, key.toId());
        return tick;
    }
    
    /**
     * @notice Get the current sqrt price of a pool
     * @param poolManager The Uniswap V4 pool manager
     * @param key The pool key
     * @return sqrtPriceX96 The current sqrt price
     */
    function getSqrtPriceX96(IPoolManager poolManager, PoolKey memory key) internal view returns (uint160 sqrtPriceX96) {
        // Get the current slot0 data from the pool using StateLibrary
        // Ignoring other return values from getSlot0
        (sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, key.toId());
        return sqrtPriceX96;
    }
} 