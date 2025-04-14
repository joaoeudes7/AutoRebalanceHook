// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {AutoMoveRangeHookFactory} from "../src/AutoMoveRangeHookFactory.sol";
import {AutoMoveRangeStablecoinHook} from "../src/AutoMoveRangeStablecoinHook.sol";
import {AutoMoveRangeVolatileHook} from "../src/AutoMoveRangeVolatileHook.sol";

contract DeployPolygon is Script {
    // Polygon mainnet V4 pool manager address - update this with the actual address
    address constant POLYGON_POOL_MANAGER = address(0); // Replace with actual V4 PoolManager address on Polygon

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the factory
        IPoolManager poolManager = IPoolManager(POLYGON_POOL_MANAGER);
        AutoMoveRangeHookFactory factory = new AutoMoveRangeHookFactory(poolManager);

        // Configure Polygon stablecoins
        bytes32 salt = keccak256(abi.encodePacked("stablecoin", block.timestamp));
        address stablecoinHookAddress = factory.deployHook(
            msg.sender, 
            AutoMoveRangeHookFactory.HookType.STABLECOIN, 
            salt
        );
        
        AutoMoveRangeStablecoinHook stablecoinHook = AutoMoveRangeStablecoinHook(stablecoinHookAddress);
        
        // Register Polygon stablecoins
        stablecoinHook.addStablecoin(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC on Polygon
        stablecoinHook.addStablecoin(0xc2132D05D31c914a87C6611C10748AEb04B58e8F); // USDT on Polygon
        stablecoinHook.addStablecoin(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063); // DAI on Polygon
        stablecoinHook.addStablecoin(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359); // USDC.e on Polygon

        // Deploy volatile hook
        bytes32 volatileSalt = keccak256(abi.encodePacked("volatile", block.timestamp));
        address volatileHookAddress = factory.deployHook(
            msg.sender, 
            AutoMoveRangeHookFactory.HookType.VOLATILE, 
            volatileSalt
        );
        
        AutoMoveRangeVolatileHook volatileHook = AutoMoveRangeVolatileHook(volatileHookAddress);
        
        // Register common volatile tokens on Polygon
        volatileHook.addVolatileToken(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0); // MATIC on Polygon
        volatileHook.addVolatileToken(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6); // WBTC on Polygon
        volatileHook.addVolatileToken(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619); // WETH on Polygon

        console.log("Factory deployed to:", address(factory));
        console.log("Stablecoin Hook deployed to:", stablecoinHookAddress);
        console.log("Volatile Hook deployed to:", volatileHookAddress);

        vm.stopBroadcast();
    }
} 