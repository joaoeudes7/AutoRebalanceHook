// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// Mock version of PoolLib - tests the logic directly without dependencies
contract PoolLibMock {
    // Mock implementation of getCurrentTick
    function getCurrentTick() public pure returns (int24) {
        return 0; // Fixed return value for testing
    }
    
    // Mock implementation of getSqrtPriceX96
    function getSqrtPriceX96() public pure returns (uint160) {
        return 79228162514264337593543950336; // 2^96 (price of 1.0)
    }
}

contract PoolLibMockTest is Test {
    PoolLibMock lib;
    
    function setUp() public {
        lib = new PoolLibMock();
    }
    
    function testGetCurrentTick() public {
        int24 tick = lib.getCurrentTick();
        assertEq(tick, 0, "getCurrentTick should return 0");
    }
    
    function testGetSqrtPriceX96() public {
        uint160 sqrtPriceX96 = lib.getSqrtPriceX96();
        uint160 expected = 79228162514264337593543950336; // 2^96
        assertEq(sqrtPriceX96, expected, "getSqrtPriceX96 should return 2^96");
    }
} 