// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "uniswap-hooks/base/BaseHook.sol";

import "./AutoMoveRangeHookBase.sol";
import "./AutoMoveRangeStablecoinHook.sol";
import "./AutoMoveRangeVolatileHook.sol";

/**
 * @title AutoMoveRangeHookFactory
 * @dev Factory contract for deploying different variants of AutoMoveRangeHook
 */
contract AutoMoveRangeHookFactory {
    // Hook type enum to identify which hook variant to deploy
    enum HookType {
        STANDARD,
        STABLECOIN,
        VOLATILE
    }
    
    // Emitted when a new hook is deployed
    event HookDeployed(address hookAddress, address owner, HookType hookType);
    
    // PoolManager instance
    IPoolManager public immutable poolManager;
    
    // Owner of the factory
    address public owner;
    
    // Custom error for unauthorized access
    error Unauthorized();
    
    /**
     * @dev Modifier to restrict function access to owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Constructor that initializes the factory with the PoolManager
     * @param _poolManager Address of the PoolManager
     */
    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        owner = msg.sender;
    }
    
    /**
     * @dev Deploy a new hook instance of the specified type
     * @param hookOwner Owner of the new hook
     * @param hookType Type of hook to deploy
     * @param salt Salt for deterministic deployment
     * @return hook Address of the deployed hook
     */
    function deployHook(
        address hookOwner, 
        HookType hookType, 
        bytes32 salt
    ) external returns (address hook) {
        if (hookType == HookType.STANDARD) {
            // Not directly instantiable as it's abstract
            revert("Standard hook is abstract, use specialized variants");
        } else if (hookType == HookType.STABLECOIN) {
            // Deploy stablecoin-optimized hook
            AutoMoveRangeStablecoinHook stableHook = new AutoMoveRangeStablecoinHook{salt: salt}(poolManager);
            stableHook.transferOwnership(hookOwner);
            hook = address(stableHook);
        } else if (hookType == HookType.VOLATILE) {
            // Deploy volatile-optimized hook
            AutoMoveRangeVolatileHook volatileHook = new AutoMoveRangeVolatileHook{salt: salt}(poolManager);
            volatileHook.transferOwnership(hookOwner);
            hook = address(volatileHook);
        } else {
            revert("Invalid hook type");
        }
        
        // Emit event
        emit HookDeployed(hook, hookOwner, hookType);
        
        return hook;
    }
    
    /**
     * @dev Calculate the hook address before deployment
     * @param hookType Type of hook to deploy
     * @param salt The salt for the deterministic deployment
     * @return The address where the hook would be deployed
     */
    function predictHookAddress(HookType hookType, bytes32 salt) external view returns (address) {
        // Calculate the address using CREATE2
        bytes32 bytecodeHash;
        
        if (hookType == HookType.STABLECOIN) {
            bytecodeHash = keccak256(
                abi.encodePacked(
                    type(AutoMoveRangeStablecoinHook).creationCode,
                    abi.encode(poolManager)
                )
            );
        } else if (hookType == HookType.VOLATILE) {
            bytecodeHash = keccak256(
                abi.encodePacked(
                    type(AutoMoveRangeVolatileHook).creationCode,
                    abi.encode(poolManager)
                )
            );
        } else {
            revert("Invalid or unsupported hook type");
        }
        
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }
    
    /**
     * @dev Transfer ownership of the factory
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        owner = newOwner;
    }
} 