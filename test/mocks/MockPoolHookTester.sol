// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {AutoMoveRangeHookBase} from "../../src/AutoMoveRangeHookBase.sol";

/**
 * @title MockPoolHookTester
 * @dev A mock implementation of AutoMoveRangeHookBase for testing
 */
contract MockPoolHookTester is AutoMoveRangeHookBase {
    constructor(IPoolManager _poolManager) AutoMoveRangeHookBase(_poolManager) {}
    
    // Override the abstract functions
    function _shouldUseCustomConfig(PoolKey calldata) internal override pure returns (bool) {
        return false;
    }
} 