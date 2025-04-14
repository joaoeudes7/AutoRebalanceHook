// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import "./AutoMoveRangeHookBase.sol";
import "./libraries/FeesLib.sol";
import "./libraries/TickLib.sol";
import "./libraries/SwapUtils.sol";

/**
 * @title AutoMoveRangeVolatileHook
 * @notice Specialized hook for volatile pairs with wider price ranges and volatility-aware rebalancing
 * @dev Optimized for pairs like ETH/BTC, ETH/USDC where price movement is significant
 */
contract AutoMoveRangeVolatileHook is AutoMoveRangeHookBase {
    // Volatile-specific configuration
    uint256 public volatileRebalanceThreshold = 15;   // 15% for volatile pairs (less sensitive)
    int24 public volatileTickRange = 200;             // ~2% range (wider)
    uint256 public volatileCooldownPeriod = 24 hours; // 24 hours (less frequent rebalancing)
    
    // Volatility tracking
    uint256 public averageVolatility24h;              // Average volatility over 24h in basis points
    uint32 public volatilityMultiplier = 150;        // 1.5x, adjusts range based on volatility
    uint256 public lastVolatilityUpdate;              // Last time volatility was updated
    
    // List of known volatile tokens
    mapping(address => bool) public isVolatileToken;
    
    // Events
    event VolatileTokenAdded(address token);
    event VolatileTokenRemoved(address token);
    event VolatileConfigUpdated(string name, uint256 oldValue, uint256 newValue);
    event VolatilityUpdated(uint256 oldValue, uint256 newValue);
    
    /**
     * @dev Constructor
     * @param _poolManager Uniswap V4 pool manager
     */
    constructor(IPoolManager _poolManager) AutoMoveRangeHookBase(_poolManager) {
        // Initialize defaults for volatile pairs
        volatileRebalanceThreshold = 15;   // 15% threshold
        volatileTickRange = 200;           // Much wider range than stable pairs
        volatileCooldownPeriod = 24 hours; // Less frequent rebalancing
        
        // Pre-register common volatile tokens
        // These addresses should be updated for the specific network
        // Addresses shown are for Ethereum mainnet
        isVolatileToken[address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)] = true; // WETH
        isVolatileToken[address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)] = true; // WBTC
        isVolatileToken[address(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0)] = true; // MATIC
        isVolatileToken[address(0x50D1c9771902476076eCFc8B2A83Ad6b9355a4c9)] = true; // FTT
        isVolatileToken[address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984)] = true; // UNI
        isVolatileToken[address(0xD533a949740bb3306d119CC777fa900bA034cd52)] = true; // CRV
    }
    
    /**
     * @dev Determine if this hook should use custom config for volatile pairs
     * @return True if should use custom volatile settings
     */
    function _shouldUseCustomConfig(PoolKey calldata key) internal view override returns (bool) {
        return isVolatilePair(key);
    }
    
    /**
     * @dev Returns configuration parameters for volatile pairs
     * @return tickRange Tick range for the position
     * @return rebalanceThreshold Threshold percentage for rebalancing
     * @return cooldownPeriod Cooldown period between rebalances
     */
    function _getConfigForPair(bool useCustomConfig) internal view override returns (
        int24 tickRange,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod
    ) {
        // For volatile pairs, use wider ranges with higher thresholds
        if (useCustomConfig) {
            return (
                volatileTickRange, 
                volatileRebalanceThreshold,
                volatileCooldownPeriod
            );
        }
        
        // Otherwise use default values from base contract
        return (
            defaultTickRange,
            defaultRebalanceThreshold,
            defaultCooldownPeriod
        );
    }
    
    /**
     * @dev Updates metrics after a swap for volatile pairs
     */
    function _updateMetrics(
        bytes32 poolId,
        int256 amountSpecified,
        BalanceDelta /* delta */,
        int24 currentTick
    ) internal override {
        // First, update basic metrics through parent implementation
        super._updateMetrics(poolId, amountSpecified, BalanceDelta.wrap(0), currentTick);
        
        // Now, update volatile-specific metrics
        PoolMetrics storage metrics = poolMetrics[poolId];
        
        // Get volatility factor from price state
        PriceState storage priceState = priceStates[poolId];
        
        // Update metric for range calculation
        metrics.volatility24h = calculateAdjustedVolatility(
            priceState.volatilityBasisPoints, 
            uint256(volatilityMultiplier)  // Cast to uint256 for the calculation
        );
    }
    
    /**
     * @dev Calculate adjusted volatility based on raw volatility and multiplier
     * @param rawVolatility Raw volatility in basis points
     * @param multiplier Multiplier to adjust volatility
     * @return Adjusted volatility
     */
    function calculateAdjustedVolatility(
        uint32 rawVolatility, 
        uint256 multiplier  // Changed to uint256 to match calling type
    ) internal pure returns (uint256) {
        // Apply multiplier and ensure we don't exceed reasonable values
        uint256 adjusted = (uint256(rawVolatility) * multiplier) / 100;
        
        // Cap at a reasonable maximum
        if (adjusted > 5000) {
            adjusted = 5000; // 50% as maximum
        }
        
        return adjusted;
    }
    
    /**
     * @dev Executes rebalance logic with volatility-aware range
     */
    function _executeRebalance(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal override {
        // Get volatility metrics for this pool
        PairConfig storage config = pairConfigs[poolId];
        PoolMetrics storage metrics = poolMetrics[poolId];
        
        // Determine range based on volatility
        int24 rangeToUse = calculateDynamicRangeBasedOnVolatility(
            config.tickRange,
            metrics.volatility24h
        );
        
        // Calculate new optimal range with volatility factor applied
        (int24 newLowerTick, int24 newUpperTick) = _calculateOptimalRange(
            currentTick,
            key.tickSpacing,
            rangeToUse
        );
        
        // Update position
        position.lowerTick = newLowerTick;
        position.upperTick = newUpperTick;
        position.lastRebalance = block.timestamp;
        position.isInRange = true;
        
        // Emit range reset event
        emit RangeReset(poolId, newLowerTick, newUpperTick);
    }
    
    /**
     * @dev Calculate dynamic range based on observed volatility
     * @param baseRange Base range width
     * @param volatility24h 24h volatility in basis points
     * @return Dynamic range width
     */
    function calculateDynamicRangeBasedOnVolatility(
        int24 baseRange,
        uint256 volatility24h
    ) internal pure returns (int24) {
        // Calculate dynamic range factor based on volatility
        uint256 rangeFactor;
        
        // Scale the range based on volatility
        // At 0 volatility, use the base range
        // At high volatility, expand the range
        if (volatility24h <= 500) {
            // Low volatility: 1x to 1.5x of base range
            rangeFactor = 100 + (volatility24h * 100 / 500);
        } else if (volatility24h <= 2000) {
            // Medium volatility: 1.5x to 3x of base range
            rangeFactor = 150 + ((volatility24h - 500) * 150 / 1500);
        } else {
            // High volatility: 3x to 5x of base range
            rangeFactor = 300 + ((volatility24h - 2000) * 200 / 3000);
            if (rangeFactor > 500) rangeFactor = 500; // Cap at 5x
        }
        
        // Apply the factor to the base range
        return int24((int256(baseRange) * int256(rangeFactor)) / 100);
    }
    
    /**
     * @dev Collects fees with strategy optimized for volatile pairs
     */
    function _collectFees(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position
    ) internal override {
        // Update last fee collection timestamp
        position.lastFeeCollection = block.timestamp;
        
        // For volatile pairs, possibly reinvest in a more conservative range
        bool isVolatile = _shouldUseCustomConfig(key);
        
        if (isVolatile) {
            // For volatile pairs, we might want to adjust how fees are reinvested
            // based on current market conditions
            // Implementation details would depend on V4 fee handling
            
            // Keep track of collected fees
            uint256 feesToken0 = 0;
            uint256 feesToken1 = 0;
            
            // Emit fee collection event
            emit FeesCollected(poolId, feesToken0, feesToken1);
        } else {
            // For non-volatile pairs, use the base implementation
            super._collectFees(key, poolId, position);
        }
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Add a token to the volatile token list
     * @param token Token address to add
     */
    function addVolatileToken(address token) external onlyOwner {
        isVolatileToken[token] = true;
        emit VolatileTokenAdded(token);
    }
    
    /**
     * @dev Remove a token from the volatile token list
     * @param token Token address to remove
     */
    function removeVolatileToken(address token) external onlyOwner {
        isVolatileToken[token] = false;
        emit VolatileTokenRemoved(token);
    }
    
    /**
     * @dev Update volatile tick range
     * @param newTickRange New tick range for volatile pairs
     */
    function setVolatileTickRange(int24 newTickRange) external onlyOwner {
        require(newTickRange > 0, "Invalid tick range");
        int24 oldValue = volatileTickRange;
        volatileTickRange = newTickRange;
        emit ConfigUpdated("volatileTickRange", uint256(uint24(oldValue)), uint256(uint24(newTickRange)));
    }
    
    /**
     * @dev Update volatile rebalance threshold
     * @param newThreshold New rebalance threshold for volatile pairs
     */
    function setVolatileRebalanceThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 50, "Invalid threshold");
        uint256 oldValue = volatileRebalanceThreshold;
        volatileRebalanceThreshold = newThreshold;
        emit ConfigUpdated("volatileRebalanceThreshold", oldValue, newThreshold);
    }
    
    /**
     * @dev Update volatile cooldown period
     * @param newPeriod New cooldown period for volatile pairs
     */
    function setVolatileCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Invalid period");
        uint256 oldValue = volatileCooldownPeriod;
        volatileCooldownPeriod = newPeriod;
        emit ConfigUpdated("volatileCooldownPeriod", oldValue, newPeriod);
    }
    
    /**
     * @dev Update volatility multiplier
     * @param newMultiplier New volatility multiplier
     */
    function setVolatilityMultiplier(uint32 newMultiplier) external onlyOwner {
        require(newMultiplier >= 50 && newMultiplier <= 200, "Invalid multiplier");
        uint32 oldValue = volatilityMultiplier;
        volatilityMultiplier = newMultiplier;
        emit ConfigUpdated("volatilityMultiplier", uint256(oldValue), uint256(newMultiplier));
    }
    
    /**
     * @dev Check if a pair is considered volatile (contains at least one volatile token)
     * @param key Pool key
     * @return True if pair is volatile
     */
    function isVolatilePair(PoolKey calldata key) public view returns (bool) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        
        return isVolatileToken[token0] || isVolatileToken[token1];
    }
} 