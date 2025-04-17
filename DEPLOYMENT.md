# AutoMoveRangeHook Deployment Guide

## 📋 Pre-Deployment Checklist

### 1. Contract Preparation
- [ ] All tests passing (`forge test -vvv`)
- [ ] 100% test coverage for critical functions
- [ ] Gas optimization completed
- [ ] Latest Solidity compiler version (^0.8.24)
- [ ] All dependencies up to date
- [ ] NatSpec documentation complete

### 2. Security
- [ ] Security audit completed
- [ ] All critical and high issues resolved
- [ ] Known issues documented
- [ ] Emergency procedures documented
- [ ] Multisig wallets configured

### 3. Configuration
- [ ] Initial parameters determined:
  ```solidity
  defaultRebalanceThreshold = 10;    // 10% threshold
  defaultTickRange = 120;            // ~1% range
  defaultCooldownPeriod = 12 hours;  // 12 hours cooldown
  feeCollectionInterval = 24 hours;  // 24 hours between collections
  minReinvestmentAmount = 0.001 ether;
  ```
- [ ] Owner address configured
- [ ] Guardian address configured
- [ ] Emergency contacts list prepared

## 🚀 Deployment Procedure

### 1. Testnet Deployment
```bash
# 1. Deploy to testnet
forge script script/Deploy.s.sol \
  --rpc-url $TESTNET_RPC \
  --private-key $DEPLOYER_KEY \
  --broadcast

# 2. Verify contract
forge verify-contract \
  $CONTRACT_ADDRESS \
  src/AutoMoveRangeHookBase.sol:AutoMoveRangeHookBase \
  --chain-id $CHAIN_ID
```

### 2. Testnet Verification
- [ ] Deploy test tokens
- [ ] Create test pools
- [ ] Execute test transactions
- [ ] Verify all hook callbacks
- [ ] Test emergency procedures

### 3. Beta Environment
- [ ] Deploy to Uniswap V4 beta
- [ ] Complete 5 RFQ fills
- [ ] Document transaction hashes
- [ ] Get approval from Uniswap team

### 4. Production Deployment

#### Step 1: Contract Deployment
```bash
# Deploy to mainnet
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC \
  --private-key $DEPLOYER_KEY \
  --broadcast
```

#### Step 2: Contract Verification
```bash
# Verify on Etherscan
forge verify-contract \
  $CONTRACT_ADDRESS \
  src/AutoMoveRangeHookBase.sol:AutoMoveRangeHookBase \
  --chain-id 1
```

#### Step 3: Initial Setup
```solidity
// Transfer ownership to multisig
hook.transferOwnership(MULTISIG_ADDRESS);

// Set guardian
hook.setGuardian(GUARDIAN_ADDRESS);

// Configure initial parameters
hook.setDefaultRebalanceThreshold(10);
hook.setDefaultTickRange(120);
hook.setDefaultCooldownPeriod(12 hours);
```

#### Step 4: Pool Creation
- [ ] Create initial pools with selected pairs
- [ ] Add initial liquidity
- [ ] Verify rebalancing functionality
- [ ] Monitor first 24 hours closely

## 📊 Post-Deployment Verification

### 1. Functional Verification
- [ ] Owner functions working
- [ ] Guardian functions working
- [ ] Rebalancing executing correctly
- [ ] Fee collection working
- [ ] Emergency pause working

### 2. Monitoring Setup
- [ ] Tenderly alerts configured
- [ ] Gas usage monitoring
- [ ] Position tracking
- [ ] Price feeds monitoring
- [ ] Rebalancing event tracking

### 3. Documentation
- [ ] Deployment addresses documented
- [ ] Initial parameters documented
- [ ] Admin procedures documented
- [ ] Emergency procedures documented

## 🆘 Emergency Procedures

### 1. Contract Pause
```solidity
// Call pause function (guardian or owner)
hook.pause()
```

### 2. Emergency Withdrawal
```solidity
// Remove liquidity from all active positions
hook.emergencyWithdraw()
```

### 3. Contact List
```
Owner Multisig: [ADDRESS]
Guardian: [ADDRESS]
Technical Contact: [EMAIL/PHONE]
Emergency Contact: [EMAIL/PHONE]
```

## 📝 Maintenance Procedures

### 1. Regular Checks
- Daily monitoring of:
  - Gas usage
  - Rebalancing frequency
  - Fee collection
  - Position status

### 2. Parameter Updates
```solidity
// Example: Update rebalance threshold
hook.setDefaultRebalanceThreshold(newValue);
```

### 3. Version Control
- Document all parameter changes
- Keep deployment history
- Track contract upgrades 