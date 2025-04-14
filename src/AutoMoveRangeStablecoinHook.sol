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
 * @title AutoMoveRangeStablecoinHook
 * @notice Specialized hook for stablecoin pairs with narrow price ranges and more frequent rebalancing
 * @dev Optimized for pairs like USDC/USDT, DAI/USDC, etc. where price movement is minimal
 */
contract AutoMoveRangeStablecoinHook is AutoMoveRangeHookBase {
    // Stablecoin-specific configuration
    uint256 public stableRebalanceThreshold = 2;      // 2% for stable pairs (more sensitive)
    int24 public stableTickRange = 20;                // ~0.2% range (narrower)
    uint256 public stableCooldownPeriod = 6 hours;    // 6 hours (more frequent rebalancing)
    
    // List of known stablecoin addresses
    mapping(address => bool) public isStablecoin;
    
    // Events
    event StablecoinAdded(address stablecoin);
    event StablecoinRemoved(address stablecoin);
    event StableConfigUpdated(string name, uint256 oldValue, uint256 newValue);
    
    /**
     * @dev Constructor
     * @param _poolManager Uniswap V4 pool manager
     */
    constructor(IPoolManager _poolManager) AutoMoveRangeHookBase(_poolManager) {
        // Initialize defaults for stablecoins
        stableRebalanceThreshold = 2;      // 2% threshold
        stableTickRange = 20;              // Much narrower range than volatile pairs
        stableCooldownPeriod = 6 hours;    // More frequent rebalancing
        
        // Pre-register common stablecoins
        // These addresses should be updated for the specific network
        // Addresses shown are for Ethereum mainnet
        isStablecoin[address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)] = true; // USDC
        isStablecoin[address(0xdAC17F958D2ee523a2206206994597C13D831ec7)] = true; // USDT
        isStablecoin[address(0x6B175474E89094C44Da98b954EedeAC495271d0F)] = true; // DAI
        isStablecoin[address(0x4Fabb145d64652a948d72533023f6E7A623C7C53)] = true; // BUSD
        isStablecoin[address(0x8E870D67F660D95d5be530380D0eC0bd388289E1)] = true; // PAX
        isStablecoin[address(0x0000000000085d4780B73119b644AE5ecd22b376)] = true; // TUSD
    }
    
    /**
     * @dev Determines if the pool should use stablecoin settings
     * @param key Pool key
     * @return True if this is a stablecoin pair
     */
    function _shouldUseCustomConfig(PoolKey calldata key) internal view override returns (bool) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        
        // If both tokens are registered stablecoins, use stablecoin settings
        return isStablecoin[token0] && isStablecoin[token1];
    }
    
    /**
     * @dev Returns configuration parameters for stablecoin or standard pairs
     * @param useCustomConfig Whether to use custom stablecoin configuration
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
            // Use stablecoin settings
            return (
                stableTickRange,
                stableRebalanceThreshold,
                stableCooldownPeriod
            );
        } else {
            // Fall back to base implementation for non-stablecoin pairs
            return super._getConfigForPair(useCustomConfig);
        }
    }
    
    /**
     * @dev Executes rebalance logic with optimizations for stablecoins
     */
    function _executeRebalance(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal override {
        // Check if it's a stablecoin pair
        bool isStablePair = _shouldUseCustomConfig(key);
        
        // For stablecoin pairs, use a more centered approach
        if (isStablePair) {
            PairConfig storage config = pairConfigs[poolId];
            
            // For stablecoins, try to center more aggressively around the current tick
            // since price movement is expected to be minimal
            int24 tickLower = TickLib.calculateLowerTick(currentTick, key.tickSpacing, config.tickRange);
            int24 tickUpper = TickLib.calculateUpperTick(currentTick, key.tickSpacing, config.tickRange);
            
            // Update position
            position.lowerTick = tickLower;
            position.upperTick = tickUpper;
            position.lastRebalance = block.timestamp;
            position.isInRange = true;
            
            // Emit event
            emit RangeReset(poolId, tickLower, tickUpper);
        } else {
            // For non-stablecoins, use the base implementation
            super._executeRebalance(key, poolId, position, currentTick);
        }
    }
    
    /**
     * @dev Collects and compounds fees more aggressively for stablecoin pairs
     */
    function _collectFees(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position
    ) internal override {
        // Update last fee collection timestamp
        position.lastFeeCollection = block.timestamp;
        
        // For stablecoin pairs, collect and reinvest fees more frequently
        // Implementation would depend on how fee collection works in V4
        
        // Emit fee collection event
        emit FeesCollected(poolId, 0, 0);
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Registers a new stablecoin address
     * @param stablecoin Address to register
     */
    function addStablecoin(address stablecoin) external onlyOwner {
        require(stablecoin != address(0), "Invalid stablecoin address");
        isStablecoin[stablecoin] = true;
        emit StablecoinAdded(stablecoin);
    }
    
    /**
     * @dev Removes a stablecoin from the registry
     * @param stablecoin Address to remove
     */
    function removeStablecoin(address stablecoin) external onlyOwner {
        isStablecoin[stablecoin] = false;
        emit StablecoinRemoved(stablecoin);
    }
    
    /**
     * @dev Updates stablecoin rebalance threshold
     * @param newThreshold New threshold percentage
     */
    function setStableRebalanceThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 10, "Invalid threshold for stablecoins");
        uint256 oldValue = stableRebalanceThreshold;
        stableRebalanceThreshold = newThreshold;
        emit StableConfigUpdated("stableRebalanceThreshold", oldValue, newThreshold);
    }
    
    /**
     * @dev Updates stablecoin tick range
     * @param newRange New tick range
     */
    function setStableTickRange(int24 newRange) external onlyOwner {
        require(newRange > 0 && newRange <= 100, "Invalid range for stablecoins");
        int24 oldValue = stableTickRange;
        stableTickRange = newRange;
        emit StableConfigUpdated("stableTickRange", uint256(uint24(oldValue)), uint256(uint24(newRange)));
    }
    
    /**
     * @dev Updates stablecoin cooldown period
     * @param newPeriod New cooldown period in seconds
     */
    function setStableCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Invalid period");
        uint256 oldValue = stableCooldownPeriod;
        stableCooldownPeriod = newPeriod;
        emit StableConfigUpdated("stableCooldownPeriod", oldValue, newPeriod);
    }
} 