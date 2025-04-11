// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @title Position
 * @notice Represents a liquidity position in a Uniswap V4 pool
 */
struct Position {
    PoolKey poolKey;
    int24 tickLower;
    int24 tickUpper;
}

/**
 * @title PositionId
 * @notice A typed position ID used for better type safety
 */
type PositionId is bytes32;

/**
 * @title PositionIdLibrary
 * @notice Library for Position conversion and manipulation
 */
library PositionIdLibrary {
    /**
     * @dev Converts a Position to a typed PositionId
     * @param position The position struct
     * @return A typed PositionId
     */
    function toId(Position memory position) internal pure returns (PositionId) {
        return PositionId.wrap(keccak256(abi.encode(position)));
    }

    /**
     * @dev Converts a Position to a uint256 token ID compatible with ERC-6909
     * @param position The position struct
     * @return tokenId A uint256 token ID
     */
    function toTokenId(Position memory position) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(position)));
    }
} 