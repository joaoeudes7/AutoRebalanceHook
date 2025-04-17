// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "./MockERC20.sol";

contract Fixtures is Test {
    IPoolManager public manager;
    MockERC20 public currency0;
    MockERC20 public currency1;
    
    function deployFreshManagerAndRouters() internal {
        // Deploy a fresh pool manager
        manager = IPoolManager(address(new PoolManager(500_000)));
        
        // Label for better trace output
        vm.label(address(manager), "PoolManager");
    }
    
    function deployMintAndApprove2Currencies() internal {
        // Deploy mock tokens
        currency0 = new MockERC20("Token 0", "TKN0", 18);
        currency1 = new MockERC20("Token 1", "TKN1", 18);
        
        // Ensure currency0 address is less than currency1
        if (address(currency0) > address(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }
        
        // Label for better trace output
        vm.label(address(currency0), "Token0");
        vm.label(address(currency1), "Token1");
        
        // Mint tokens to test contract
        currency0.mint(address(this), type(uint128).max);
        currency1.mint(address(this), type(uint128).max);
        
        // Approve pool manager to spend tokens
        currency0.approve(address(manager), type(uint256).max);
        currency1.approve(address(manager), type(uint256).max);
    }
    
    function deployCodeTo(
        string memory what,
        bytes memory constructorArgs,
        address where
    ) internal {
        // Deploy contract to specific address
        string[] memory commands = new string[](3);
        commands[0] = "forge";
        commands[1] = "build";
        commands[2] = "--extra-output-files";
        bytes memory bytecode = vm.ffi(commands);
        
        // Append constructor args
        bytecode = abi.encodePacked(bytecode, constructorArgs);
        
        // Deploy to specified address
        vm.etch(where, bytecode);
    }
} 