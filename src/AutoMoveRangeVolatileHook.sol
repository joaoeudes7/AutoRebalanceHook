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
    uint256 public volatilityMultiplier = 150;        // 1.5x, adjusts range based on volatility
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
     * @dev Determines if the pool should use volatile settings
     * @param key Pool key
     * @return True if this is a volatile pair
     */
    function _shouldUseCustomConfig(PoolKey calldata key) internal view override returns (bool) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        
        // If either token is registered as volatile, use volatile settings
        return isVolatileToken[token0] || isVolatileToken[token1];
    }
    
    /**
     * @dev Returns configuration parameters for volatile or standard pairs
     * @param useCustomConfig Whether to use custom volatile configuration
     * @return tickRange Range of ticks for position
     * @return rebalanceThreshold Threshold percentage to trigger rebalance
     * @return cooldownPeriod Time between rebalances
     */
    function _getConfigForPair(bool useCustomConfig) internal view override returns (
        int24 tickRange,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod
    ) {
        if (useCustomConfig) {
            // Use volatile settings
            return (
                volatileTickRange,
                volatileRebalanceThreshold,
                volatileCooldownPeriod
            );
        } else {
            // Fall back to base implementation for non-volatile pairs
            return super._getConfigForPair(useCustomConfig);
        }
    }
    
    /**
     * @dev Updates metrics with additional volatility tracking
     */
    function _updateMetrics(
        bytes32 poolId,
        int256 amountSpecified,
        BalanceDelta delta,
        int24 currentTick
    ) internal override {
        // Call base implementation first
        super._updateMetrics(poolId, amountSpecified, delta, currentTick);
        
        // Access price state
        PriceState storage priceState = priceStates[poolId];
        
        // Update volatility tracking
        if (priceState.volatilityBasisPoints > 0) {
            // Exponential moving average for 24h volatility
            if (averageVolatility24h == 0) {
                averageVolatility24h = priceState.volatilityBasisPoints;
            } else {
                // Simple EMA calculation
                averageVolatility24h = (averageVolatility24h * 9 + priceState.volatilityBasisPoints * 1) / 10;
            }
            
            lastVolatilityUpdate = block.timestamp;
            emit VolatilityUpdated(
                priceState.volatilityBasisPoints, 
                averageVolatility24h
            );
        }
    }
    
    /**
     * @dev Executes rebalance logic with volatility-aware range determination
     */
    function _executeRebalance(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal override {
        // Check if it's a volatile pair
        bool isVolatilePair = _shouldUseCustomConfig(key);
        
        // For volatile pairs, use volatility-aware range calculation
        if (isVolatilePair) {
            PairConfig storage config = pairConfigs[poolId];
            
            // Calculate base range
            int24 baseRange = config.tickRange;
            
            // Adjust range based on volatility
            int24 adjustedRange = baseRange;
            if (averageVolatility24h > 0) {
                // If volatility is high, widen the range
                uint256 volatilityAdjustment = (averageVolatility24h * volatilityMultiplier) / 100;
                adjustedRange = int24(int256((uint256(uint24(baseRange)) * volatilityAdjustment) / 100));
                
                // Ensure range isn't too wide
                if (adjustedRange > 500) adjustedRange = 500;
                
                // Ensure range isn't too narrow
                if (adjustedRange < baseRange) adjustedRange = baseRange;
            }
            
            // Calculate new range with the adjusted range
            int24 tickLower = TickLib.calculateLowerTick(currentTick, key.tickSpacing, adjustedRange);
            int24 tickUpper = TickLib.calculateUpperTick(currentTick, key.tickSpacing, adjustedRange);
            
            // For highly volatile pairs, add a slight bias in the direction of the trend
            PriceState storage priceState = priceStates[poolId];
            if (priceState.initialized && priceState.averageTick != 0) {
                // Check if there's a trend
                int24 trend = currentTick - priceState.averageTick;
                if (trend > 10) {
                    // Upward trend - skew range upward
                    tickLower += int24(int256(uint256(trend > 0 ? uint24(trend) : 0) / 4));
                    tickUpper += int24(int256(uint256(trend > 0 ? uint24(trend) : 0) / 2));
                } else if (trend < -10) {
                    // Downward trend - skew range downward
                    tickLower += int24(int256(trend) / 2);
                    tickUpper += int24(int256(trend) / 4);
                }
                
                // Align to tick spacing
                tickLower = TickLib.alignToSpacing(tickLower, key.tickSpacing);
                tickUpper = TickLib.alignToSpacing(tickUpper, key.tickSpacing);
            }
            
            // Update position
            position.lowerTick = tickLower;
            position.upperTick = tickUpper;
            position.lastRebalance = block.timestamp;
            position.isInRange = true;
            
            // Emit event
            emit RangeReset(poolId, tickLower, tickUpper);
        } else {
            // For non-volatile pairs, use the base implementation
            super._executeRebalance(key, poolId, position, currentTick);
        }
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
        bool isVolatilePair = _shouldUseCustomConfig(key);
        
        if (isVolatilePair) {
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
     * @dev Registers a new volatile token address
     * @param token Address to register
     */
    function addVolatileToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        isVolatileToken[token] = true;
        emit VolatileTokenAdded(token);
    }
    
    /**
     * @dev Removes a token from the volatile registry
     * @param token Address to remove
     */
    function removeVolatileToken(address token) external onlyOwner {
        isVolatileToken[token] = false;
        emit VolatileTokenRemoved(token);
    }
    
    /**
     * @dev Updates volatile rebalance threshold
     * @param newThreshold New threshold percentage
     */
    function setVolatileRebalanceThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 30, "Invalid threshold for volatile pairs");
        uint256 oldValue = volatileRebalanceThreshold;
        volatileRebalanceThreshold = newThreshold;
        emit VolatileConfigUpdated("volatileRebalanceThreshold", oldValue, newThreshold);
    }
    
    /**
     * @dev Updates volatile tick range
     * @param newRange New tick range
     */
    function setVolatileTickRange(int24 newRange) external onlyOwner {
        require(newRange > 50 && newRange <= 1000, "Invalid range for volatile pairs");
        int24 oldValue = volatileTickRange;
        volatileTickRange = newRange;
        emit VolatileConfigUpdated("volatileTickRange", uint256(uint24(oldValue)), uint256(uint24(newRange)));
    }
    
    /**
     * @dev Updates volatile cooldown period
     * @param newPeriod New cooldown period in seconds
     */
    function setVolatileCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Invalid period");
        uint256 oldValue = volatileCooldownPeriod;
        volatileCooldownPeriod = newPeriod;
        emit VolatileConfigUpdated("volatileCooldownPeriod", oldValue, newPeriod);
    }
    
    /**
     * @dev Updates volatility multiplier
     * @param newMultiplier New multiplier (basis points)
     */
    function setVolatilityMultiplier(uint256 newMultiplier) external onlyOwner {
        require(newMultiplier >= 100 && newMultiplier <= 500, "Invalid multiplier (100-500%)");
        uint256 oldValue = volatilityMultiplier;
        volatilityMultiplier = newMultiplier;
        emit VolatileConfigUpdated("volatilityMultiplier", oldValue, newMultiplier);
    }
} 