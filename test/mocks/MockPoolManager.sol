// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import "forge-std/console.sol";

contract MockPoolManager {
    using PoolIdLibrary for PoolKey;

    // Storage for pool states
    mapping(bytes32 => uint160) public sqrtPriceX96;
    mapping(bytes32 => int24) public currentTick;
    mapping(bytes32 => uint128) public liquidity;
    mapping(bytes32 => bool) public initialized;

    // Events for logging
    event PoolInitialized(bytes32 indexed poolId, uint160 sqrtPriceX96);
    event LiquidityModified(bytes32 indexed poolId, int256 liquidityDelta);
    event SwapExecuted(bytes32 indexed poolId, bool zeroForOne, int256 amountSpecified);

    function initialize(PoolKey calldata key, uint160 _sqrtPriceX96) external returns (int24 tick) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        require(!initialized[poolId], "Pool already initialized");

        sqrtPriceX96[poolId] = _sqrtPriceX96;
        currentTick[poolId] = 0; // Mock initial tick
        initialized[poolId] = true;

        console.log("Pool initialized with sqrtPriceX96:", _sqrtPriceX96);
        emit PoolInitialized(poolId, _sqrtPriceX96);
        
        // Call the hook's afterInitialize function
        if (address(key.hooks) != address(0)) {
            IHooks(address(key.hooks)).afterInitialize(address(this), key, _sqrtPriceX96, 0);
        }
        
        return 0;
    }

    function modifyLiquidity(
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta delta) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        require(initialized[poolId], "Pool not initialized");

        // Call beforeAddLiquidity hook if adding liquidity
        if (params.liquidityDelta > 0 && address(key.hooks) != address(0)) {
            IHooks(address(key.hooks)).beforeAddLiquidity(address(this), key, params, hookData);
        } else if (params.liquidityDelta < 0 && address(key.hooks) != address(0)) {
            IHooks(address(key.hooks)).beforeRemoveLiquidity(address(this), key, params, hookData);
        }

        // Update liquidity
        if (params.liquidityDelta > 0) {
            liquidity[poolId] += uint128(uint256(params.liquidityDelta));
        } else if (params.liquidityDelta < 0) {
            // Use absolute value of liquidityDelta
            uint128 absLiquidityDelta = uint128(uint256(-params.liquidityDelta));
            liquidity[poolId] = absLiquidityDelta > liquidity[poolId] ? 0 : liquidity[poolId] - absLiquidityDelta;
        }

        console.log("Liquidity modified. Delta:", params.liquidityDelta);
        console.log("New liquidity:", liquidity[poolId]);
        emit LiquidityModified(poolId, params.liquidityDelta);

        // Call afterAddLiquidity hook if adding liquidity
        if (params.liquidityDelta > 0 && address(key.hooks) != address(0)) {
            IHooks(address(key.hooks)).afterAddLiquidity(address(this), key, params, BalanceDelta.wrap(0), BalanceDelta.wrap(0), hookData);
        }

        // Mock token transfers
        return BalanceDelta.wrap(0);
    }

    function swap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external returns (BalanceDelta delta) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        require(initialized[poolId], "Pool not initialized");

        // Mock price update
        if (params.zeroForOne) {
            currentTick[poolId] -= 1;
        } else {
            currentTick[poolId] += 1;
        }

        console.log("Swap executed. ZeroForOne:", params.zeroForOne);
        console.log("Amount specified:", params.amountSpecified);
        emit SwapExecuted(poolId, params.zeroForOne, params.amountSpecified);

        // Call afterSwap hook
        if (address(key.hooks) != address(0)) {
            IHooks(address(key.hooks)).afterSwap(address(this), key, params, BalanceDelta.wrap(0), hookData);
        }

        // Mock token transfers
        return BalanceDelta.wrap(0);
    }

    function take(Currency currency, address to, uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function settle(Currency currency) external pure returns (uint256) {
        return 0;
    }

    function mint(Currency currency, address to, uint256 amount) external {}
    function burn(Currency currency, address to, uint256 amount) external {}

    // Helper functions for testing
    function getSqrtPriceX96(bytes32 poolId) external view returns (uint160) {
        return sqrtPriceX96[poolId];
    }

    function getCurrentTick(bytes32 poolId) external view returns (int24) {
        return currentTick[poolId];
    }

    function getLiquidity(bytes32 poolId) external view returns (uint128) {
        return liquidity[poolId];
    }

    // Added to support tests that need slot0 data
    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint16, uint16) {
        bytes32 poolIdBytes = keccak256(abi.encode(poolId));
        return (
            sqrtPriceX96[poolIdBytes], 
            currentTick[poolIdBytes],
            uint16(0),   // mock for lpFeeRate 
            uint16(0)    // mock for protocolFeeRate
        );
    }
} 