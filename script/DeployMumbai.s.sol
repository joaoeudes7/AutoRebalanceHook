// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {AutoMoveRangeHookFactory} from "../src/AutoMoveRangeHookFactory.sol";
import {AutoMoveRangeStablecoinHook} from "../src/AutoMoveRangeStablecoinHook.sol";
import {AutoMoveRangeVolatileHook} from "../src/AutoMoveRangeVolatileHook.sol";

contract DeployMumbai is Script {
    // Mumbai testnet V4 pool manager address - update this with the actual address
    address constant MUMBAI_POOL_MANAGER = address(0); // Replace with actual V4 PoolManager address on Mumbai

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        IPoolManager poolManager = IPoolManager(MUMBAI_POOL_MANAGER);
        AutoMoveRangeHookFactory factory = new AutoMoveRangeHookFactory(poolManager);

        // Configure Mumbai stablecoins (use test addresses if available, or same as mainnet)
        bytes32 salt = keccak256(abi.encodePacked("stablecoin", block.timestamp));
        address stablecoinHookAddress = factory.deployHook(
            msg.sender, 
            AutoMoveRangeHookFactory.HookType.STABLECOIN, 
            salt
        );
        
        AutoMoveRangeStablecoinHook stablecoinHook = AutoMoveRangeStablecoinHook(stablecoinHookAddress);
        
        // Use testnet addresses if available, otherwise these can be mainnet addresses
        // Mumbai often has the same token addresses as mainnet for testing
        stablecoinHook.addStablecoin(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // Test USDC on Mumbai (use actual testnet address)
        stablecoinHook.addStablecoin(0xc2132D05D31c914a87C6611C10748AEb04B58e8F); // Test USDT on Mumbai (use actual testnet address)
        
        // Deploy volatile hook
        bytes32 volatileSalt = keccak256(abi.encodePacked("volatile", block.timestamp));
        address volatileHookAddress = factory.deployHook(
            msg.sender, 
            AutoMoveRangeHookFactory.HookType.VOLATILE, 
            volatileSalt
        );
        
        AutoMoveRangeVolatileHook volatileHook = AutoMoveRangeVolatileHook(volatileHookAddress);
        
        // Register Mumbai volatile tokens
        volatileHook.addVolatileToken(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0); // Test MATIC on Mumbai (use actual testnet address)
        volatileHook.addVolatileToken(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6); // Test WBTC on Mumbai (use actual testnet address)

        console.log("Factory deployed to:", address(factory));
        console.log("Stablecoin Hook deployed to:", stablecoinHookAddress);
        console.log("Volatile Hook deployed to:", volatileHookAddress);

        vm.stopBroadcast();
    }
} 