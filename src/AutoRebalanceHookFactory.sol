// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import "./AutoRebalanceHook.sol";

/**
 * @title AutoRebalanceHookFactory
 * @dev Factory contract for deploying AutoRebalanceHook instances
 */
contract AutoRebalanceHookFactory {
    // Emitted when a new hook is deployed
    event HookDeployed(address hookAddress, address owner);
    
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
     * @dev Deploy a new AutoRebalanceHook instance
     * @param hookOwner Owner of the new hook
     * @param salt Salt for deterministic deployment
     * @return hook Address of the deployed hook
     */
    function deployHook(address hookOwner, bytes32 salt) external returns (AutoRebalanceHook hook) {
        // Create the hook implementation
        hook = new AutoRebalanceHook{salt: salt}(poolManager);
        
        // Transfer ownership to the specified owner
        hook.transferOwnership(hookOwner);
        
        // Emit event
        emit HookDeployed(address(hook), hookOwner);
        
        return hook;
    }
    
    /**
     * @dev Calculate the hook address before deployment
     * @param salt The salt for the deterministic deployment
     * @return The address where the hook would be deployed
     */
    function predictHookAddress(bytes32 salt) external view returns (address) {
        // Calculate the address using CREATE2
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(AutoRebalanceHook).creationCode,
                abi.encode(poolManager)
            )
        );
        
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