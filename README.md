# Auto-Rebalance Hook for Uniswap V4

A secure, MEV-resistant liquidity management hook for Uniswap V4 that automatically rebalances positions as prices move and reinvests collected fees.

## Key Features

### 1. Manipulation-Resistant Rebalancing

This implementation adds robust protection against price manipulation attacks that could force harmful rebalancing:

- **Time-Weighted Average Price (TWAP) Oracle**: Maintains a circular buffer of price observations to calculate a time-weighted average price, providing protection against short-term price manipulations.
- **Manipulation Detection**: Detects suspicious price movements by comparing current tick to TWAP, and falls back to the TWAP-based tick for rebalancing decisions when manipulation is detected.
- **Configurable Parameters**: Customizable TWAP window (30 minutes to 24 hours) and deviation thresholds that can be adjusted by the contract owner.

### 2. Slippage-Protected Swap Functionality

Protection against front-running and sandwich attacks:

- **Deadline Enforcement**: Transactions expire after a user-defined deadline, preventing execution of stale transactions.
- **Minimum Output Guarantee**: Ensures swaps meet minimum expected output requirements, protecting against adverse price movements.
- **Adaptive Price Limits**: Uses buffer-enhanced price limits to prevent extreme slippage.

### 3. Enhanced Security Features

- **Role-Based Access Control**: Separation between owner (full control) and guardian (emergency actions only).
- **Emergency Pause**: Ability to pause all automated rebalancing and critical operations.
- **Token Recovery**: Owner can recover accidentally sent tokens or ETH.

## Architecture

The contract is organized into modular components:

1. **AutoRebalanceHook.sol**: Main contract implementing Uniswap V4 hooks for rebalancing liquidity.
2. **OracleLib.sol**: Library for TWAP oracle implementation and manipulation detection.
3. **SwapUtils.sol**: Library for secure swap execution with MEV protection.
4. **PositionLib.sol**: Library for tracking and managing liquidity positions.
5. **TickLib.sol**: Library for tick-related calculations.
6. **IAutoRebalanceHook.sol**: Interface defining the contract's external API.

## Usage

### Setup and Deployment

1. Deploy the AutoRebalanceHook contract, passing in the Uniswap V4 PoolManager address.
2. Configure manipulation protection parameters based on your risk tolerance:
   - `setUseManipulationProtection(true/false)` - Enable/disable protection
   - `setMaxTickDeviation(value)` - Maximum allowed deviation from TWAP
   - `setTwapWindow(value)` - TWAP window duration

### MEV-Protected Operations

When executing swaps, use the protected swap function to prevent sandwich attacks:

```solidity
function protectedSwap(
    PoolKey calldata key,
    bool zeroForOne,
    int256 amountSpecified,
    uint256 minAmountOut,
    uint256 deadline
) external returns (uint256 amountIn, uint256 amountOut);
```

### Monitoring Manipulation Attempts

The contract emits a `PotentialManipulationDetected` event when unusual price movements are detected, enabling off-chain monitoring.

## Security Best Practices

1. **Manipulation Detection**: The hook tracks price observations over time to detect and mitigate potential manipulation attempts.
2. **Safe Parameter Bounds**: All configuration parameters have safety bounds to prevent misconfiguration.
3. **Access Control**: Critical functions are protected by appropriate access controls.
4. **Gas Efficiency**: Optimized for gas efficiency while maintaining robust security guarantees.

## Acknowledgements

This implementation builds on insights from the following resources:
- [Uniswap V4 Hooks Documentation](https://github.com/ora-io/awesome-uniswap-hooks)
- [Sandwich Attack Mitigation Strategies](https://github.com/ora-io/awesome-uniswap-hooks/blob/main/docs/research/sandwich-resistant-hook.md)
- [Thorns in the Rose: Security Risks in Uniswap v4](https://github.com/ora-io/awesome-uniswap-hooks#articles)

## Overview

The AutoRebalanceHook provides automated management of Uniswap V4 liquidity positions with these key features:

1. **Automatic Rebalancing**: Detects when positions move out of range and repositions liquidity around the current price.
2. **Fee Collection & Reinvestment**: Periodically collects trading fees and reinvests them back into the position.
3. **Optimized Token Ratios**: Calculates and maintains optimal token ratios for efficient liquidity provision.
4. **Configurable Parameters**: Customizable thresholds and intervals for various operations.

## Configuration Parameters

- `rebalanceThreshold`: Percentage threshold for triggering rebalance (default: 10%)
- `