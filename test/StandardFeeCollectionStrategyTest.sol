// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {StandardFeeCollectionStrategy} from "../src/strategies/StandardFeeCollectionStrategy.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract StandardFeeCollectionStrategyTest is Test {
    StandardFeeCollectionStrategy strategy;
    address owner;
    address nonOwner;
    
    // Mock parameters for testing
    bytes32 mockPoolId = bytes32(uint256(1));
    PoolKey mockPoolKey;
    int24 mockLowerTick = -100;
    int24 mockUpperTick = 100;
    uint256 mockMinReinvestmentAmount = 100;
    
    function setUp() public {
        owner = address(this);
        nonOwner = address(0x1);
        
        strategy = new StandardFeeCollectionStrategy();
        
        // Initialize a mock PoolKey
        mockPoolKey = PoolKey({
            currency0: Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)), // Mock USDC
            currency1: Currency.wrap(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)), // Mock WETH
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        // Set a fixed timestamp for testing
        vm.warp(1000000);
    }
    
    /*//////////////////////////////////////////////////////////////
                         OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testConstructor() public view {
        assertEq(strategy.owner(), owner, "Owner should be set to the deployer");
    }
    
    function testTransferOwnership() public {
        strategy.transferOwnership(nonOwner);
        assertEq(strategy.owner(), nonOwner, "Owner should be updated");
    }
    
    function testTransferOwnership_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(StandardFeeCollectionStrategy.Unauthorized.selector));
        strategy.transferOwnership(nonOwner);
    }
    
    function testTransferOwnership_ZeroAddress() public {
        vm.expectRevert("New owner is the zero address");
        strategy.transferOwnership(address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                     SHOULD COLLECT FEES TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testShouldCollectFees_BeforeInterval() public view {
        // Given the block.timestamp is 1000000 (from setUp)
        // and lastCollection is 999400 (600 seconds or 10 minutes ago)
        // and interval is 3600 seconds (1 hour)
        // then the function should return false
        uint256 lastCollection = 999400; // 10 minutes ago
        uint256 interval = 3600;         // 1 hour interval
        
        bool result = strategy.shouldCollectFees(mockPoolId, lastCollection, interval);
        assertFalse(result, "Should not collect fees before interval has passed");
    }
    
    function testShouldCollectFees_AfterInterval() public view {
        // Given the block.timestamp is 1000000 (from setUp)
        // and lastCollection is 996400 (3600 seconds or 1 hour ago)
        // and interval is 3600 seconds (1 hour)
        // then the function should return true
        uint256 lastCollection = 996400; // 1 hour ago
        uint256 interval = 3600;         // 1 hour interval
        
        bool result = strategy.shouldCollectFees(mockPoolId, lastCollection, interval);
        assertTrue(result, "Should collect fees after interval has passed");
    }
    
    function testShouldCollectFees_ExactlyAtInterval() public view {
        // Given the block.timestamp is 1000000 (from setUp)
        // and lastCollection is 996400 (3600 seconds or 1 hour ago)
        // and interval is 3600 seconds (1 hour)
        // then the function should return true
        uint256 lastCollection = 996400; // 1 hour ago
        uint256 interval = 3600;         // 1 hour interval
        
        bool result = strategy.shouldCollectFees(mockPoolId, lastCollection, interval);
        assertTrue(result, "Should collect fees exactly at interval");
    }
    
    /*//////////////////////////////////////////////////////////////
                         COLLECT FEES TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCollectFees() public view {
        (uint256 feesToken0, uint256 feesToken1) = strategy.collectFees(
            IPoolManager(address(0)),
            mockPoolKey,
            mockPoolId,
            mockLowerTick,
            mockUpperTick,
            mockMinReinvestmentAmount
        );
        
        assertEq(feesToken0, 0, "No fees should be collected for token0");
        assertEq(feesToken1, 0, "No fees should be collected for token1");
    }
    
    /*//////////////////////////////////////////////////////////////
                      SHOULD REINVEST FEES TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testShouldReinvestFees_BothZero() public view {
        uint256 token0Amount = 0;
        uint256 token1Amount = 0;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format
        
        bool result = strategy.shouldReinvestFees(token0Amount, token1Amount, minAmount, price);
        assertFalse(result, "Should not reinvest when both amounts are zero");
    }
    
    function testShouldReinvestFees_Token0AboveMin() public view {
        uint256 token0Amount = 150;
        uint256 token1Amount = 0;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format
        
        bool result = strategy.shouldReinvestFees(token0Amount, token1Amount, minAmount, price);
        assertTrue(result, "Should reinvest when token0 is above minimum");
    }
    
    function testShouldReinvestFees_Token1AboveMin() public view {
        uint256 token0Amount = 0;
        uint256 token1Amount = 150;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format
        
        bool result = strategy.shouldReinvestFees(token0Amount, token1Amount, minAmount, price);
        assertTrue(result, "Should reinvest when token1 is above minimum");
    }
    
    function testShouldReinvestFees_BothBelowMin() public view {
        uint256 token0Amount = 50;
        uint256 token1Amount = 50;
        uint256 minAmount = 100;
        uint160 price = 79228162514264337593543950336; // 1.0 in Q64.96 format
        
        bool result = strategy.shouldReinvestFees(token0Amount, token1Amount, minAmount, price);
        assertFalse(result, "Should not reinvest when both are below minimum");
    }
    
    /*//////////////////////////////////////////////////////////////
                            NAME TEST
    //////////////////////////////////////////////////////////////*/
    
    function testGetName() public view {
        string memory name = strategy.getName();
        assertEq(name, "StandardFeeCollectionStrategy", "Strategy name should match");
    }
    
    /*//////////////////////////////////////////////////////////////
                           FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_ShouldCollectFees(uint256 lastCollection, uint256 interval) public view {
        // Constrain values to reasonable bounds
        // We know block.timestamp is 1000000 from setUp
        lastCollection = bound(lastCollection, 0, 1000000);
        interval = bound(interval, 1, 1000000);
        
        bool result = strategy.shouldCollectFees(mockPoolId, lastCollection, interval);
        bool expected = (1000000 >= lastCollection + interval);
        
        assertEq(result, expected, "ShouldCollectFees result should match expected value");
    }
    
    function testFuzz_ShouldReinvestFees(
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 minAmount
    ) public view {
        // Constrain values to reasonable bounds
        token0Amount = bound(token0Amount, 0, 1e18);
        token1Amount = bound(token1Amount, 0, 1e18);
        minAmount = bound(minAmount, 1, 1e18);
        uint160 price = 79228162514264337593543950336; // Fixed 1.0 price for simplicity
        
        bool result = strategy.shouldReinvestFees(token0Amount, token1Amount, minAmount, price);
        bool expected = (token0Amount >= minAmount || token1Amount >= minAmount);
        
        assertEq(result, expected, "ShouldReinvestFees result should match expected value");
    }
} 