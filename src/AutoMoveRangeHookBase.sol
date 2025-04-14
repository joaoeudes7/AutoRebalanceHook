// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";
import {CurrencySettler} from "uniswap-hooks/utils/CurrencySettler.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

import "./libraries/RebalanceLib.sol";
import "./libraries/TickLib.sol";
import "./libraries/PositionLib.sol";
import "./libraries/SwapUtils.sol";
import "./libraries/SecurityLib.sol";
import "./libraries/AdminLib.sol";
import "./libraries/FeesLib.sol";
import "./libraries/PoolLib.sol";

/**
 * @title AutoMoveRangeHookBase
 * @notice Base implementation for hooks that automatically rebalance liquidity positions
 * @dev Abstract contract to be inherited by specific implementations
 */
abstract contract AutoMoveRangeHookBase is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    // ========== CUSTOM ERRORS ==========
    error Unauthorized();
    error InvalidConfig();
    error FailedToRebalance();
    error InvalidState();
    error ContractPaused();

    // ========== EVENTS ==========
    event PositionUpdated(bytes32 indexed poolId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    event RangeReset(bytes32 indexed poolId, int24 newLowerTick, int24 newUpperTick);
    event ConfigUpdated(string name, uint256 oldValue, uint256 newValue);
    event PairConfigSet(bytes32 indexed poolId, bool isCustom, int24 tickRange, uint256 rebalanceThreshold);
    event MetricsUpdated(bytes32 indexed poolId, uint256 volume24h, uint256 fees24h, uint256 volatility24h, uint256 gasPrice);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event PausedEvent(address indexed account);
    event UnpausedEvent(address indexed account);
    event FeesCollected(bytes32 indexed poolId, uint256 feesToken0, uint256 feesToken1);
    event NarrowRangeRebalanceExecuted(bytes32 indexed poolId, int24 newLowerTick, int24 newUpperTick);
    
    // ========== CONSTANTS ==========
    uint256 private constant HOUR = 3600;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant PRICE_HISTORY_LENGTH = 24;
    bytes internal constant ZERO_BYTES = bytes("");
    
    // ========== DATA STRUCTURES ==========
    // Custom price state structure for manipulation detection
    struct PriceState {
        uint32 lastObservationTime;
        int56 tickCumulative;
        bool initialized;
        int24 averageTick;
        uint32 volatilityBasisPoints;
    }
    
    // ========== STATE VARIABLES ==========
    
    // Access control
    address public owner;
    address public guardian;
    bool public paused;
    
    // Default configuration (can be overridden by specific implementations)
    uint256 public defaultRebalanceThreshold = 10;    // 10% threshold by default
    int24 public defaultTickRange = 120;              // Approximately 1% range
    uint256 public defaultCooldownPeriod = 12 hours;  // 12 hours cooldown by default
    uint256 public feeCollectionInterval = 24 hours;  // 24 hours between fee collections
    uint256 public minReinvestmentAmount = 0.001 ether; // Minimum amount to reinvest
    
    // Price protection
    bool public useManipulationProtection = true;
    int24 public maxTickDeviation = 50;               // Maximum tick deviation for manipulation detection
    uint32 public twapWindow = 3600;                  // 1 hour TWAP window
    
    // Position tracking
    struct Position {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint256 lastRebalance;
        uint256 lastFeeCollection;
        bool active;
        bool isInRange;
        uint256 token0Balance;
        uint256 token1Balance;
    }
    
    // Pool configuration
    struct PairConfig {
        bool isConfigured;
        bool isCustomConfig;
        int24 tickRange;
        uint256 rebalanceThreshold;
        uint256 cooldownPeriod;
    }
    
    // Pool metrics for analytics
    struct PoolMetrics {
        uint256 lastUpdateTime;   // Last time metrics were updated
        uint256 volumeLast24h;    // Volume in last 24 hours
        uint256 feesLast24h;      // Fees in last 24 hours
        uint256 volatility24h;    // Basis points (1/10000)
        uint256 avgGasPrice;      // Last known gas price in gwei
        int24 lastTick;           // Last known tick
    }
    
    // State mappings
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => PairConfig) public pairConfigs;
    mapping(bytes32 => PoolMetrics) public poolMetrics;
    mapping(bytes32 => PriceState) public priceStates;
    
    // ========== MODIFIERS ==========
    
    /**
     * @dev Restricts function access to contract owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Restricts function access to owner or guardian
     */
    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != guardian) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Prevents function execution when contract is paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    
    // ========== CONSTRUCTOR ==========
    
    /**
     * @dev Constructor to initialize the hook with its dependencies
     * @param _poolManager Uniswap V4 pool manager
     */
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = msg.sender;
        guardian = msg.sender;
    }
    
    // ========== HOOK PERMISSIONS ==========
    
    /**
     * @dev Returns hook permissions needed for this contract
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
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
    
    // ========== HOOK CALLBACKS ==========
    
    /**
     * @dev Callback after pool initialization
     */
    function _afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal virtual override returns (bytes4) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        
        // Determine if custom configuration should be used, can be overridden by child contracts
        bool useCustomConfig = _shouldUseCustomConfig(key);
        
        // Get configuration parameters based on pair type
        (int24 rangeToUse, uint256 rebalanceThreshold, uint256 cooldownPeriod) = _getConfigForPair(useCustomConfig);
        
        // Set up pair configuration
        pairConfigs[poolId] = PairConfig({
            isConfigured: true,
            isCustomConfig: useCustomConfig,
            tickRange: rangeToUse,
            rebalanceThreshold: rebalanceThreshold,
            cooldownPeriod: cooldownPeriod
        });
        
        // Calculate initial range
        (int24 tickLower, int24 tickUpper) = _calculateOptimalRange(
            tick,
            key.tickSpacing,
            rangeToUse
        );
        
        // Set up position
        positions[poolId] = Position({
            lowerTick: tickLower,
            upperTick: tickUpper,
            liquidity: 0,
            lastRebalance: block.timestamp,
            lastFeeCollection: block.timestamp,
            active: true,
            isInRange: true,
            token0Balance: 0,
            token1Balance: 0
        });
        
        // Initialize price state for manipulation detection
        priceStates[poolId] = PriceState({
            lastObservationTime: uint32(block.timestamp),
            tickCumulative: 0,
            initialized: true,
            averageTick: tick,
            volatilityBasisPoints: 0
        });
        
        // Emit event
        emit RangeReset(poolId, tickLower, tickUpper);
        
        return BaseHook.afterInitialize.selector;
    }
    
    /**
     * @dev Callback before adding liquidity
     */
    function _beforeAddLiquidity(
        address /* sender */,
        PoolKey calldata /* key */,
        IPoolManager.ModifyLiquidityParams calldata /* params */,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        // Allow custom behavior in derived contracts
        return BaseHook.beforeAddLiquidity.selector;
    }
    
    /**
     * @dev Callback after adding liquidity
     */
    function _afterAddLiquidity(
        address /* sender */,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta /* delta */,
        BalanceDelta /* feeDelta */,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        if (params.liquidityDelta > 0) {
            bytes32 poolId = keccak256(abi.encode(key.toId()));
            Position storage position = positions[poolId];
            position.liquidity = uint128(uint256(params.liquidityDelta) + uint256(position.liquidity));
            
            // Update position ticks if they're different (user may be adding to a different range)
            if (position.lowerTick != params.tickLower || position.upperTick != params.tickUpper) {
                position.lowerTick = params.tickLower;
                position.upperTick = params.tickUpper;
            }
            
            // Update position status
            position.active = true;
            
            emit PositionUpdated(poolId, position.lowerTick, position.upperTick, position.liquidity);
        }
        
        return (BaseHook.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }
    
    /**
     * @dev Callback before removing liquidity
     */
    function _beforeRemoveLiquidity(
        address /* sender */,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        if (params.liquidityDelta < 0) {
            bytes32 poolId = keccak256(abi.encode(key.toId()));
            Position storage position = positions[poolId];
            
            if (position.lowerTick == params.tickLower && 
                position.upperTick == params.tickUpper) {
                int256 absLiquidityDelta = params.liquidityDelta < 0 ? -params.liquidityDelta : params.liquidityDelta;
                if (uint256(absLiquidityDelta) >= uint256(position.liquidity)) {
                    position.active = false;
                    position.liquidity = 0;
                } else {
                    position.liquidity = uint128(uint256(position.liquidity) - uint256(absLiquidityDelta));
                }
            }
        }
        return BaseHook.beforeRemoveLiquidity.selector;
    }
    
    /**
     * @dev Callback after swap execution
     */
    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal virtual override returns (bytes4, int128) {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        Position storage position = positions[poolId];
        
        // Skip processing for inactive positions
        if (!position.active) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Get current tick from pool - using correct interface method
        int24 currentTick;
        {
            // Note: Accessing the current tick through poolManager
            // Different implementations of IPoolManager might have different methods to access this information
            // Use whatever method is available in your implementation
            currentTick = PoolLib.getCurrentTick(poolManager, key);
        }
        
        // Update position range status
        position.isInRange = (currentTick >= position.lowerTick && currentTick < position.upperTick);
        
        // Update metrics for analytics
        _updateMetrics(poolId, params.amountSpecified, delta, currentTick);
        
        // Check if rebalance is needed - uses RebalanceLib
        if (_shouldRebalance(poolId, position, currentTick)) {
            // Execute rebalance logic - can be customized in derived contracts
            _executeRebalance(key, poolId, position, currentTick);
        }
        
        // Check if fee collection is due
        if (_shouldCollectFees(poolId, position)) {
            // Execute fee collection logic
            _collectFees(key, poolId, position);
        }
        
        return (BaseHook.afterSwap.selector, 0);
    }
    
    // ========== INTERNAL FUNCTIONS ==========
    
    /**
     * @dev Determines if a custom configuration should be used for a pool
     * @return True if custom configuration should be used
     */
    function _shouldUseCustomConfig(PoolKey calldata /* key */) internal virtual returns (bool) {
        // Override in derived contracts to implement specific logic
        return false;
    }
    
    /**
     * @dev Returns configuration parameters based on pair type
     * @return tickRange Tick range for the position
     * @return rebalanceThreshold Threshold percentage for rebalancing
     * @return cooldownPeriod Cooldown period between rebalances
     */
    function _getConfigForPair(bool /* useCustomConfig */) internal virtual view returns (
        int24 tickRange,
        uint256 rebalanceThreshold,
        uint256 cooldownPeriod
    ) {
        // Base implementation uses default values
        return (
            defaultTickRange,
            defaultRebalanceThreshold,
            defaultCooldownPeriod
        );
    }
    
    /**
     * @dev Calculate optimal tick range for a position
     * @param currentTick Current tick
     * @param tickSpacing Tick spacing of the pool
     * @param rangeTicks Number of ticks to use for range
     * @return lowerTick Lower tick of the range
     * @return upperTick Upper tick of the range
     */
    function _calculateOptimalRange(
        int24 currentTick,
        int24 tickSpacing,
        int24 rangeTicks
    ) internal pure returns (int24 lowerTick, int24 upperTick) {
        lowerTick = TickLib.calculateLowerTick(currentTick, tickSpacing, rangeTicks);
        upperTick = TickLib.calculateUpperTick(currentTick, tickSpacing, rangeTicks);
        return (lowerTick, upperTick);
    }
    
    /**
     * @dev Updates pool metrics based on swap data
     */
    function _updateMetrics(
        bytes32 poolId,
        int256 amountSpecified,
        BalanceDelta /* delta */,
        int24 currentTick
    ) internal virtual {
        PoolMetrics storage metrics = poolMetrics[poolId];
        
        // Update last known tick
        metrics.lastTick = currentTick;
        
        // Record observation for manipulation detection
        PriceState storage priceState = priceStates[poolId];
        
        // Update price state with new observation
        uint32 currentTime = uint32(block.timestamp);
        if (currentTime > priceState.lastObservationTime) {
            // Calculate elapsed time
            uint32 timeElapsed = currentTime - priceState.lastObservationTime;
            
            // Update tick cumulative
            priceState.tickCumulative += int56(currentTick) * int56(uint56(timeElapsed));
            
            // Update price state
            priceState.lastObservationTime = currentTime;
            
            // Update average tick - Fix type conversion issue
            // Convert types properly to avoid division errors
            priceState.averageTick = int24(int256(priceState.tickCumulative) / int256(uint256(timeElapsed)));
            
            // Calculate volatility (simplified)
            int256 tickDiff = currentTick - priceState.averageTick;
            if (tickDiff < 0) tickDiff = -tickDiff;
            
            priceState.volatilityBasisPoints = uint32(uint256(tickDiff) * BASIS_POINTS / uint256(int256(defaultTickRange)));
        }
        
        // Other metrics update logic
        // Calculate volume
        uint256 volume = amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
        
        // Update metrics
        metrics.lastUpdateTime = block.timestamp;
        metrics.volumeLast24h = volume; // This is simplified, should accumulate over 24h
        
        // Update gas price - simplified implementation
        metrics.avgGasPrice = uint256(tx.gasprice);
    }
    
    /**
     * @dev Determines if a position should be rebalanced
     */
    function _shouldRebalance(
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal view returns (bool) {
        // Check if position is active
        if (!position.active) return false;
        
        // Get pool configuration
        PairConfig storage config = pairConfigs[poolId];
        
        // Check cooldown period
        if (block.timestamp < position.lastRebalance + config.cooldownPeriod) {
            return false;
        }
        
        // Check if out of range
        if (currentTick < position.lowerTick || currentTick >= position.upperTick) {
            return true;
        }
        
        // Calculate deviation from center of range
        int24 rangeMidpoint = position.lowerTick + (position.upperTick - position.lowerTick) / 2;
        uint256 rangeWidth = uint24(position.upperTick - position.lowerTick);
        
        // Calculate distance from midpoint as percentage
        uint256 deviation;
        if (currentTick > rangeMidpoint) {
            deviation = (uint24(currentTick - rangeMidpoint) * 100) / rangeWidth;
        } else {
            deviation = (uint24(rangeMidpoint - currentTick) * 100) / rangeWidth;
        }
        
        // Compare with rebalance threshold
        return deviation >= config.rebalanceThreshold;
    }
    
    /**
     * @dev Executes rebalance logic
     */
    function _executeRebalance(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal virtual {
        // Get pool configuration
        PairConfig storage config = pairConfigs[poolId];
        
        // Calculate new range
        (int24 newLowerTick, int24 newUpperTick) = _calculateOptimalRange(
            currentTick,
            key.tickSpacing,
            config.tickRange
        );
        
        // Update position ticks
        position.lowerTick = newLowerTick;
        position.upperTick = newUpperTick;
        position.lastRebalance = block.timestamp;
        position.isInRange = true;
        
        // Emit range reset event
        emit RangeReset(poolId, newLowerTick, newUpperTick);
    }
    
    /**
     * @dev Determines if fees should be collected
     */
    function _shouldCollectFees(
        bytes32 /* poolId */,
        Position storage position
    ) internal view returns (bool) {
        return position.active && (block.timestamp >= position.lastFeeCollection + feeCollectionInterval);
    }
    
    /**
     * @dev Collects fees from the position
     */
    function _collectFees(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position
    ) internal virtual {
        // Update last fee collection timestamp
        position.lastFeeCollection = block.timestamp;
        
        // Skip if position has no liquidity
        if (position.liquidity == 0) {
            emit FeesCollected(poolId, 0, 0);
            return;
        }
        
        // Use FeesLib to collect fees from the position
        (uint256 feesToken0, uint256 feesToken1) = FeesLib.collectFees(
            poolManager,
            key,
            position.lowerTick,
            position.upperTick
        );
        
        // Update token balances with collected fees
        position.token0Balance += feesToken0;
        position.token1Balance += feesToken1;
        
        // Get current price to determine if reinvestment is worthwhile
        uint160 sqrtPriceX96;
        int24 currentTick;
        
        // Get current pool state
        {
            // Using PoolLib to get current tick and price
            currentTick = PoolLib.getCurrentTick(poolManager, key);
            sqrtPriceX96 = PoolLib.getSqrtPriceX96(poolManager, key);
        }
        
        // Check if reinvestment is worthwhile
        if (FeesLib.isReinvestmentWorthwhile(
            position.token0Balance, 
            position.token1Balance,
            minReinvestmentAmount,
            sqrtPriceX96
        )) {
            // Calculate if swap is needed to optimize token balances
            bool needSwap;
            bool zeroForOne;
            uint256 amountToSwap;
            
            // Use SwapUtils to calculate optimal swap
            (needSwap, zeroForOne, amountToSwap) = SwapUtils.calculateSwapForBalance(
                position.token0Balance,
                position.token1Balance,
                sqrtPriceX96,
                position.lowerTick,
                position.upperTick
            );
            
            // Perform swap if needed
            if (needSwap && amountToSwap > 0) {
                if (zeroForOne) {
                    // Swap token0 for token1
                    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                        zeroForOne: true,
                        amountSpecified: int256(amountToSwap),
                        sqrtPriceLimitX96: 4295128740 // MIN_SQRT_RATIO + 1
                    });
                    
                    BalanceDelta swapDelta = poolManager.swap(key, params, ZERO_BYTES);
                    
                    // Update token balances after swap
                    position.token0Balance -= uint256(uint128(-swapDelta.amount0()));
                    position.token1Balance += uint256(uint128(swapDelta.amount1()));
                } else {
                    // Swap token1 for token0
                    IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                        zeroForOne: false,
                        amountSpecified: int256(amountToSwap),
                        sqrtPriceLimitX96: 1461446703485210103287273052203988822378723970341 // MAX_SQRT_RATIO - 1
                    });
                    
                    BalanceDelta swapDelta = poolManager.swap(key, params, ZERO_BYTES);
                    
                    // Update token balances after swap
                    position.token0Balance += uint256(uint128(swapDelta.amount0()));
                    position.token1Balance -= uint256(uint128(-swapDelta.amount1()));
                }
            }
            
            // Add liquidity with rebalanced tokens
            uint128 liquidityAdded = FeesLib.reinvestFees(
                poolManager,
                key,
                position.lowerTick,
                position.upperTick,
                position.token0Balance,
                position.token1Balance
            );
            
            // Update position liquidity
            position.liquidity += liquidityAdded;
            
            // Reset token balances to zero since they're now reinvested
            position.token0Balance = 0;
            position.token1Balance = 0;
        }
        
        // Emit fee collection event
        emit FeesCollected(poolId, feesToken0, feesToken1);
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Transfers ownership to a new address
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    
    /**
     * @dev Sets a new guardian address
     * @param newGuardian New guardian address
     */
    function setGuardian(address newGuardian) external onlyOwner {
        require(newGuardian != address(0), "New guardian is the zero address");
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(oldGuardian, newGuardian);
    }
    
    /**
     * @dev Pauses the contract
     */
    function pause() external onlyAuthorized {
        paused = true;
        emit PausedEvent(msg.sender);
    }
    
    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyAuthorized {
        paused = false;
        emit UnpausedEvent(msg.sender);
    }
    
    /**
     * @dev Updates default rebalance threshold
     * @param newThreshold New threshold value
     */
    function setDefaultRebalanceThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0 && newThreshold <= 50, "Invalid threshold");
        uint256 oldValue = defaultRebalanceThreshold;
        defaultRebalanceThreshold = newThreshold;
        emit ConfigUpdated("defaultRebalanceThreshold", oldValue, newThreshold);
    }
    
    /**
     * @dev Updates default tick range
     * @param newRange New tick range
     */
    function setDefaultTickRange(int24 newRange) external onlyOwner {
        require(newRange > 0, "Invalid range");
        int24 oldValue = defaultTickRange;
        defaultTickRange = newRange;
        emit ConfigUpdated("defaultTickRange", uint256(uint24(oldValue)), uint256(uint24(newRange)));
    }
    
    /**
     * @dev Updates default cooldown period
     * @param newPeriod New cooldown period in seconds
     */
    function setDefaultCooldownPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Invalid period");
        uint256 oldValue = defaultCooldownPeriod;
        defaultCooldownPeriod = newPeriod;
        emit ConfigUpdated("defaultCooldownPeriod", oldValue, newPeriod);
    }
    
    /**
     * @dev Updates fee collection interval
     * @param newInterval New interval in seconds
     */
    function setFeeCollectionInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Invalid interval");
        uint256 oldValue = feeCollectionInterval;
        feeCollectionInterval = newInterval;
        emit ConfigUpdated("feeCollectionInterval", oldValue, newInterval);
    }
    
    /**
     * @dev Sets minimum reinvestment amount
     * @param newAmount New minimum amount
     */
    function setMinReinvestmentAmount(uint256 newAmount) external onlyOwner {
        uint256 oldValue = minReinvestmentAmount;
        minReinvestmentAmount = newAmount;
        emit ConfigUpdated("minReinvestmentAmount", oldValue, newAmount);
    }
    
    /**
     * @dev Toggles price manipulation protection
     * @param useProtection Whether to use protection
     */
    function setUseManipulationProtection(bool useProtection) external onlyOwner {
        bool oldValue = useManipulationProtection;
        useManipulationProtection = useProtection;
        emit ConfigUpdated("useManipulationProtection", oldValue ? 1 : 0, useProtection ? 1 : 0);
    }
    
    // ========== MANUAL OPERATIONS ==========
    
    /**
     * @dev Manually triggers position rebalancing
     * @param key Pool key
     */
    function manuallyRebalance(PoolKey calldata key) external onlyAuthorized whenNotPaused {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        Position storage position = positions[poolId];
        
        // Ensure position is active
        require(position.active, "Position not active");
        
        // Get current tick - using correct interface method
        int24 currentTick;
        {
            // Note: Accessing the current tick through poolManager
            // Different implementations of IPoolManager might have different methods to access this information
            // Use whatever method is available in your implementation
            currentTick = PoolLib.getCurrentTick(poolManager, key);
        }
        
        // Execute rebalance
        _executeRebalance(key, poolId, position, currentTick);
    }
    
    /**
     * @dev Manually triggers fee collection
     * @param key Pool key
     */
    function manuallyCollectFees(PoolKey calldata key) external onlyAuthorized whenNotPaused {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        Position storage position = positions[poolId];
        
        // Ensure position is active
        require(position.active, "Position not active");
        
        // Collect fees
        _collectFees(key, poolId, position);
    }

    // Replace JITRebalanceExecuted event with NarrowRangeRebalanceExecuted
    function _executeNarrowRangeRebalance(
        PoolKey calldata key,
        bytes32 poolId,
        Position storage position,
        int24 currentTick
    ) internal {
        // Calculate narrow concentrated range around the current price
        // This is more capital efficient for immediate liquidity
        int24 tickLower = TickLib.calculateNarrowLowerTick(currentTick, key.tickSpacing, 1);
        int24 tickUpper = TickLib.calculateNarrowUpperTick(currentTick, key.tickSpacing, 1);
        
        // If we have existing liquidity, remove it first
        if (position.liquidity > 0) {
            // Remove existing liquidity
            (BalanceDelta balanceDelta,) = poolManager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: position.lowerTick,
                    tickUpper: position.upperTick,
                    liquidityDelta: -int256(uint256(position.liquidity)),
                    salt: 0
                }),
                new bytes(0)
            );
            
            // Update token balances from removed liquidity
            position.token0Balance += uint256(uint128(balanceDelta.amount0()));
            position.token1Balance += uint256(uint128(balanceDelta.amount1()));
        }
        
        // Calculate new liquidity with collected tokens
        uint128 newLiquidity = _calculateOptimalLiquidity(
            currentTick,
            tickLower,
            tickUpper,
            position.token0Balance,
            position.token1Balance
        );
        
        if (newLiquidity > 0) {
            // Add liquidity in the narrow range (concentrated around current price)
            (BalanceDelta delta,) = poolManager.modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper, 
                    liquidityDelta: int256(uint256(newLiquidity)),
                    salt: 0
                }),
                new bytes(0)
            );
            
            // Update position with new range and liquidity
            position.lowerTick = tickLower;
            position.upperTick = tickUpper;
            position.liquidity = newLiquidity;
            position.lastRebalance = block.timestamp;
            position.isInRange = true;
            
            // Update token balances
            position.token0Balance -= uint256(uint128(-delta.amount0()));
            position.token1Balance -= uint256(uint128(-delta.amount1()));
            
            // Emit range reset event
            emit RangeReset(poolId, tickLower, tickUpper);
        }
    }

    // Helper function to calculate optimal liquidity for the given range and token balances
    function _calculateOptimalLiquidity(
        int24 currentTick,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        // Get sqrt prices at the ticks
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(currentTick);
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        
        // Calculate liquidity amount based on available tokens
        // This is a simplified calculation - in production,
        // you should use LiquidityAmounts from v4-periphery
        
        uint256 liquidity = 0;
        if (currentTick < tickLower) {
            // Current price is below the range
            // Only token0 is used
            liquidity = amount0 * (sqrtPriceUpperX96 - sqrtPriceLowerX96) / 
                       (sqrtPriceLowerX96 * sqrtPriceUpperX96);
        } else if (currentTick < tickUpper) {
            // Current price is within the range
            // Both tokens are used
            uint256 liquidity0 = amount0 * sqrtPriceX96 / 
                               (sqrtPriceUpperX96 - sqrtPriceX96);
            uint256 liquidity1 = amount1 / 
                               (sqrtPriceX96 - sqrtPriceLowerX96);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            // Current price is above the range
            // Only token1 is used
            liquidity = amount1 / (sqrtPriceUpperX96 - sqrtPriceLowerX96);
        }
        
        // Ensure we're within uint128 range
        if (liquidity > type(uint128).max) {
            liquidity = type(uint128).max;
        }
        
        return uint128(liquidity);
    }

    // Rename manuallyExecuteJITRebalance to manuallyExecuteNarrowRangeRebalance and update comments
    /**
     * @notice Manually triggers concentrated narrow-range rebalancing
     * @dev Creates a very narrow position around the current price for max capital efficiency
     * @param key Pool key
     */
    function manuallyExecuteNarrowRangeRebalance(PoolKey calldata key) external onlyAuthorized whenNotPaused {
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        Position storage position = positions[poolId];
        
        // Ensure position is active
        require(position.active, "Position not active");
        
        // Get current tick using the PoolLib implementation
        int24 currentTick = PoolLib.getCurrentTick(poolManager, key);
        
        // Execute narrow range rebalance
        _executeNarrowRangeRebalance(key, poolId, position, currentTick);
        
        // Emit event
        emit NarrowRangeRebalanceExecuted(poolId, position.lowerTick, position.upperTick);
    }
} 