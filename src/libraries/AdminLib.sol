// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AdminLib
 * @dev Library for handling administrative functions in AutoRebalanceHook
 */
library AdminLib {
    error InvalidConfig();

    /**
     * @dev Initialize admin settings
     */
    function initialize(
        address owner,
        address guardian,
        uint256 rebalanceThreshold,
        uint256 feeCollectionInterval,
        uint256 minReinvestmentAmount,
        int24 defaultTickRange,
        int24 maxTickDeviation,
        uint32 twapWindow
    ) internal view returns (
        address,
        address,
        uint256,
        uint256,
        uint256,
        int24,
        int24,
        uint32
    ) {
        // Initialize with default values
        owner = msg.sender;
        guardian = msg.sender;
        
        // Set default values
        rebalanceThreshold = 10;               // 10%
        feeCollectionInterval = 1 days;
        minReinvestmentAmount = 10 * 10**18;   // $10 equivalent
        defaultTickRange = 100;                // Approx 1% range
        
        // Anti-manipulation defaults
        maxTickDeviation = 512;                // ~5% price deviation
        twapWindow = 60 minutes;               // 1 hour TWAP window

        return (
            owner,
            guardian,
            rebalanceThreshold,
            feeCollectionInterval,
            minReinvestmentAmount,
            defaultTickRange,
            maxTickDeviation,
            twapWindow
        );
    }

    /**
     * @dev Handle ownership transfer
     */
    function handleTransferOwnership(address newOwner) internal pure returns (address) {
        if (newOwner == address(0)) revert InvalidConfig();
        return newOwner;
    }

    /**
     * @dev Validate configuration parameters
     */
    function validateConfig(
        uint256 threshold,
        uint256 interval,
        int24 tickRange,
        uint32 window
    ) internal pure {
        if (threshold == 0 || threshold > 50) revert InvalidConfig();
        if (interval < 1 hours || interval > 30 days) revert InvalidConfig();
        if (tickRange < 10 || tickRange > 2000) revert InvalidConfig();
        if (window < 30 minutes || window > 24 hours) revert InvalidConfig();
    }
} 