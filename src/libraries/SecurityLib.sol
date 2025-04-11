// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SecurityLib
 * @dev Library for handling security-related functions in AutoRebalanceHook
 */
library SecurityLib {
    error Unauthorized();
    error ContractPaused();
    error DeadlineExpired();

    /**
     * @dev Validate that the caller is the owner
     */
    function validateOwner(address caller, address owner) internal pure {
        if (caller != owner) revert Unauthorized();
    }

    /**
     * @dev Validate that the caller is either owner or guardian
     */
    function validateAuthorized(address caller, address owner, address guardian) internal pure {
        if (caller != owner && caller != guardian) revert Unauthorized();
    }

    /**
     * @dev Validate that the contract is not paused
     */
    function validateNotPaused(bool paused) internal pure {
        if (paused) revert ContractPaused();
    }

    /**
     * @dev Validate transaction deadline
     */
    function validateDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) revert DeadlineExpired();
    }

    /**
     * @dev Check for potential price manipulation
     */
    function checkPriceManipulation(
        int24 currentTick,
        int24 twapTick,
        int24 maxDeviation
    ) internal pure returns (bool) {
        int24 deviation = currentTick > twapTick ? 
            currentTick - twapTick : 
            twapTick - currentTick;
        return deviation > maxDeviation;
    }
} 