// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {AutoMoveRangeHookBase} from "../src/AutoMoveRangeHookBase.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

contract AutoMoveRangeHookBaseTest is Test, Fixtures {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    AutoMoveRangeHookBase hook;
    PoolKey key;
    bytes32 poolId;
    
    // Test constants
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;  // 1:1 price
    bytes constant ZERO_BYTES = bytes("");
    
    function setUp() public {
        // Deploy pool manager and other dependencies
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        
        // Deploy the hook with correct flags
        address hookAddress = address(uint160(
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.AFTER_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.AFTER_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        ));
        
        // Deploy hook implementation
        bytes memory constructorArgs = abi.encode(address(manager));
        deployCodeTo("AutoMoveRangeHookBase.sol:AutoMoveRangeHookBase", constructorArgs, hookAddress);
        hook = AutoMoveRangeHookBase(hookAddress);
        
        // Create pool
        key = PoolKey(
            Currency.wrap(address(currency0)),
            Currency.wrap(address(currency1)),
            3000,    // 0.3% fee tier
            60,      // tick spacing
            IHooks(hook)
        );
        poolId = key.toId();
        
        // Initialize pool
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    // ========== CORE FUNCTIONS ==========
    
    /// @notice Test optimal liquidity calculation under normal conditions
    function test_calculateOptimalLiquidity_balancedTokens() public {
        // Setup test data
        int24 currentTick = 0;  // Price = 1
        int24 tickLower = -60;  // Lower bound
        int24 tickUpper = 60;   // Upper bound
        uint256 amount0 = 1e18; // 1 token0
        uint256 amount1 = 1e18; // 1 token1
        
        // Calculate liquidity
        uint128 liquidity = hook.calculateOptimalLiquidity(
            currentTick,
            tickLower,
            tickUpper,
            amount0,
            amount1
        );
        
        // Verify liquidity is non-zero and reasonable
        assertTrue(liquidity > 0, "Liquidity should be non-zero");
        
        // Verify liquidity can be used to add position
        (uint256 token0Amount, uint256 token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        
        // Verify calculated amounts are within bounds
        assertTrue(token0Amount <= amount0, "Token0 amount exceeds available");
        assertTrue(token1Amount <= amount1, "Token1 amount exceeds available");
    }
    
    /// @notice Test optimal liquidity calculation with imbalanced tokens
    function test_calculateOptimalLiquidity_imbalancedTokens() public {
        // Setup test data with imbalanced token amounts
        int24 currentTick = 0;
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint256 amount0 = 2e18;  // 2 token0
        uint256 amount1 = 1e18;  // 1 token1
        
        uint128 liquidity = hook.calculateOptimalLiquidity(
            currentTick,
            tickLower,
            tickUpper,
            amount0,
            amount1
        );
        
        assertTrue(liquidity > 0, "Liquidity should be non-zero");
        
        // Verify amounts
        (uint256 token0Amount, uint256 token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        
        assertTrue(token0Amount <= amount0, "Token0 amount exceeds available");
        assertTrue(token1Amount <= amount1, "Token1 amount exceeds available");
    }
    
    /// @notice Test optimal liquidity calculation with zero amounts
    function test_calculateOptimalLiquidity_zeroAmounts() public {
        int24 currentTick = 0;
        int24 tickLower = -60;
        int24 tickUpper = 60;
        
        uint128 liquidity = hook.calculateOptimalLiquidity(
            currentTick,
            tickLower,
            tickUpper,
            0,
            0
        );
        
        assertEq(liquidity, 0, "Liquidity should be zero with zero amounts");
    }
    
    /// @notice Test rebalancing under normal market conditions
    function test_executeRebalance_normalConditions() public {
        // Add initial liquidity
        addLiquidity(1e18, 1e18);
        
        // Simulate price movement
        simulateSwap(true, 1e17);  // Swap that moves price
        
        // Get current tick
        int24 currentTick = getCurrentTick(key);
        
        // Trigger rebalance
        hook.manuallyRebalance(key);
        
        // Verify position was updated
        (int24 newLower, int24 newUpper) = getPositionTicks(poolId);
        assertTrue(currentTick >= newLower, "Current tick below range");
        assertTrue(currentTick < newUpper, "Current tick above range");
    }
    
    /// @notice Test rebalancing during high volatility
    function test_executeRebalance_priceVolatility() public {
        // Add initial liquidity
        addLiquidity(1e18, 1e18);
        
        // Simulate volatile market conditions
        for (uint i = 0; i < 5; i++) {
            simulateSwap(true, 1e17);
            simulateSwap(false, 1e17);
        }
        
        // Trigger rebalance
        hook.manuallyRebalance(key);
        
        // Verify position
        (int24 newLower, int24 newUpper) = getPositionTicks(poolId);
        int24 currentTick = getCurrentTick(key);
        assertTrue(currentTick >= newLower && currentTick < newUpper, "Position not centered");
    }

    // ========== HELPER FUNCTIONS ==========
    
    function addLiquidity(uint256 amount0, uint256 amount1) internal {
        // Implementation
    }
    
    function simulateSwap(bool zeroForOne, uint256 amount) internal {
        // Implementation
    }
    
    function getCurrentTick(PoolKey memory _key) internal view returns (int24) {
        // Implementation
    }
    
    function getPositionTicks(bytes32 _poolId) internal view returns (int24 lower, int24 upper) {
        // Implementation
    }
} 