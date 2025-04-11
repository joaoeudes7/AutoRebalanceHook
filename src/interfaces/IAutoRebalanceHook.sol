// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @title IAutoRebalanceHook
 * @dev Interface for AutoRebalanceHook contract
 */
interface IAutoRebalanceHook {
    // ========== EVENTS ==========
    
    /**
     * @dev Emitted when a position range is reset
     */
    event RangeReset(bytes32 indexed poolId, int24 newLowerTick, int24 newUpperTick);
    
    /**
     * @dev Emitted when position details are updated
     */
    event PositionUpdated(bytes32 indexed poolId, int24 lowerTick, int24 upperTick, uint128 liquidity);
    
    /**
     * @dev Emitted when fees are collected
     */
    event FeesCollected(bytes32 indexed poolId, uint256 feesToken0, uint256 feesToken1);
    
    /**
     * @dev Emitted when fees are reinvested
     */
    event FeesReinvested(bytes32 indexed poolId, uint256 amountToken0, uint256 amountToken1, uint128 liquidityAdded);
    
    /**
     * @dev Emitted when tokens are swapped
     */
    event TokensSwapped(bytes32 indexed poolId, bool zeroForOne, uint256 amountIn, uint256 amountOut);
    
    /**
     * @dev Emitted when ownership is transferred
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    /**
     * @dev Emitted when guardian is updated
     */
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    
    /**
     * @dev Emitted when contract is paused
     */
    event PausedEvent(address indexed account);
    
    /**
     * @dev Emitted when contract is unpaused
     */
    event UnpausedEvent(address indexed account);
    
    /**
     * @dev Emitted when a threshold parameter is updated
     */
    event ThresholdUpdated(string name, uint256 oldValue, uint256 newValue);
    
    /**
     * @dev Emitted when manipulation protection is toggled
     */
    event ProtectionToggled(bool oldValue, bool newValue);
    
    /**
     * @dev Emitted when potential price manipulation is detected
     */
    event PotentialManipulationDetected(bytes32 indexed poolId, uint256 timestamp);

    // ========== ERRORS ==========
    
    /**
     * @dev Error thrown when an unauthorized caller tries to access a restricted function
     */
    error Unauthorized();
    
    /**
     * @dev Error thrown when the contract is paused
     */
    error ContractPaused();
    
    /**
     * @dev Error thrown when an invalid configuration parameter is provided
     */
    error InvalidConfig();
    
    /**
     * @dev Error thrown when an invalid price range is specified
     */
    error InvalidPriceRange();
    
    /**
     * @dev Error thrown when a rebalance operation fails
     */
    error FailedToRebalance();

    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @dev Get details of a position
     * @param key The pool key
     * @return lowerTick The lower tick of the position
     * @return upperTick The upper tick of the position
     * @return liquidity The liquidity of the position
     * @return isActive Whether the position is active
     * @return lastFeeCollection The timestamp of the last fee collection
     * @return token0Balance The balance of token0 in the position
     * @return token1Balance The balance of token1 in the position
     */
    function getPosition(PoolKey calldata key) external view returns (
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        bool isActive,
        uint256 lastFeeCollection,
        uint256 token0Balance,
        uint256 token1Balance
    );
    
    /**
     * @dev Check if a position needs to be rebalanced
     * @param key The pool key
     * @return Whether rebalancing is needed
     */
    function checkIfRebalanceNeeded(PoolKey calldata key) external view returns (bool);
    
    /**
     * @dev Helper function to check if a position needs rebalance with manipulation detection
     * @param key The pool key
     * @return needsRebalance True if position needs rebalancing
     * @return manipulationDetected True if price manipulation was detected
     */
    function checkIfRebalanceNeededWithManipulationCheck(
        PoolKey calldata key
    ) external returns (bool needsRebalance, bool manipulationDetected);
    
    /**
     * @dev Check if fee collection is due
     * @param key The pool key
     * @return Whether fee collection is due
     */
    function checkIfFeeCollectionDue(PoolKey calldata key) external view returns (bool);

    // ========== ADMIN FUNCTIONS ==========
    
    /**
     * @dev Transfer ownership to a new owner
     * @param newOwner The new owner
     */
    function transferOwnership(address newOwner) external;
    
    /**
     * @dev Set a new guardian
     * @param newGuardian The new guardian
     */
    function setGuardian(address newGuardian) external;
    
    /**
     * @dev Pause the contract
     */
    function pause() external;
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external;
    
    /**
     * @dev Set a new rebalance threshold
     * @param newThreshold The new threshold percentage
     */
    function setRebalanceThreshold(uint256 newThreshold) external;
    
    /**
     * @dev Set a new fee collection interval
     * @param newInterval The new interval in seconds
     */
    function setFeeCollectionInterval(uint256 newInterval) external;
    
    /**
     * @dev Set a new minimum reinvestment amount
     * @param newAmount The new minimum amount
     */
    function setMinReinvestmentAmount(uint256 newAmount) external;
    
    /**
     * @dev Set a new default tick range
     * @param newRange The new tick range (±)
     */
    function setDefaultTickRange(int24 newRange) external;
    
    /**
     * @dev Toggle the use of price manipulation protection
     * @param useProtection Whether to enable/disable protection
     */
    function setUseManipulationProtection(bool useProtection) external;
    
    /**
     * @dev Set the maximum allowed tick deviation for manipulation detection
     * @param newDeviation New maximum deviation
     */
    function setMaxTickDeviation(int24 newDeviation) external;
    
    /**
     * @dev Set the TWAP window for price averaging
     * @param newWindow New window in seconds
     */
    function setTwapWindow(uint32 newWindow) external;

    // ========== OPERATIONAL FUNCTIONS ==========
    
    /**
     * @dev Manually trigger a rebalance
     * @param key The pool key
     */
    function manuallyRebalance(PoolKey calldata key) external;
    
    /**
     * @dev Manually trigger fee collection
     * @param key The pool key
     */
    function manuallyCollectFees(PoolKey calldata key) external;
    
    /**
     * @dev Execute swap with slippage protection to prevent sandwich attacks
     * @param key The pool key
     * @param zeroForOne Direction of swap
     * @param amountSpecified Amount to swap
     * @param minAmountOut Minimum amount to receive
     * @param deadline Transaction deadline
     * @return amountIn Amount swapped in
     * @return amountOut Amount received out
     */
    function protectedSwap(
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountIn, uint256 amountOut);
    
    /**
     * @dev Protected atomic rebalance to prevent sandwich attacks
     * @param key The pool key
     * @param zeroForOne Direction of the swap
     * @param amountIn Amount to swap
     * @param minAmountOut Minimum amount to receive
     * @param targetLowerTick Target lower tick
     * @param targetUpperTick Target upper tick
     * @param deadline Transaction deadline
     * @return success Whether the operation succeeded
     */
    function protectedFlashRebalance(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut,
        int24 targetLowerTick,
        int24 targetUpperTick,
        uint256 deadline
    ) external returns (bool success);
    
    /**
     * @dev Efficient rebalance function using gas-optimized approach from bungi
     * @param key The pool key
     * @param newLowerTick New lower tick for the position
     * @param newUpperTick New upper tick for the position
     * @return success Whether the rebalance succeeded
     */
    function efficientRebalance(
        PoolKey calldata key,
        int24 newLowerTick,
        int24 newUpperTick
    ) external returns (bool success);
    
    /**
     * @dev Recover ERC20 tokens from the contract
     * @param token The token address (0 for ETH)
     * @param to The recipient
     * @param amount The amount to recover
     */
    function recoverTokens(address token, address to, uint256 amount) external;
} 