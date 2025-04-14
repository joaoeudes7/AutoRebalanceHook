# Polygon Deployment Guide for AutoRebalanceHook

This guide provides instructions for deploying the AutoRebalanceHook contracts to Polygon networks.

## Prerequisites

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
2. Clone this repository
3. Install dependencies: `forge install`
4. Have a wallet with MATIC for gas

## Environment Setup

1. Copy the `.env.example` file to `.env`:
   ```
   cp .env.example .env
   ```

2. Edit `.env` and fill in your details:
   ```
   PRIVATE_KEY=your_private_key
   POLYGON_RPC_URL=https://polygon-rpc.com  # Or your preferred RPC provider
   POLYGON_MUMBAI_RPC_URL=https://rpc-mumbai.maticvigil.com  # Or your preferred RPC provider
   POLYGONSCAN_API_KEY=your_polygonscan_api_key
   DEPLOYER_ADDRESS=your_wallet_address
   GAS_PRICE=50000000000  # Adjust based on current gas price (in wei)
   ```

## Deployment Steps

### Testing on Mumbai Testnet First

It's recommended to test deployment on Mumbai testnet before deploying to Polygon mainnet.

1. Update the `MUMBAI_POOL_MANAGER` address in `script/DeployMumbai.s.sol` with the actual Uniswap V4 PoolManager address on Mumbai.

2. Update token addresses in the script to use actual testnet token addresses.

3. Run the deployment script:
   ```
   forge script script/DeployMumbai.s.sol --rpc-url mumbai --broadcast --verify
   ```

### Mainnet Deployment

Once you've confirmed everything works on testnet, you can deploy to Polygon mainnet:

1. Update the `POLYGON_POOL_MANAGER` address in `script/DeployPolygon.s.sol` with the actual Uniswap V4 PoolManager address on Polygon mainnet.

2. Verify that all token addresses in the script are correct.

3. Run the deployment script:
   ```
   forge script script/DeployPolygon.s.sol --rpc-url polygon --broadcast --verify
   ```

## Post-Deployment Steps

After deployment, you should:

1. Verify the contracts are working correctly by interacting with them.
2. Add or remove any additional stablecoins or volatile tokens using the admin functions.
3. Adjust settings like rebalance thresholds or tick ranges if needed.

## Contract Verification

The `--verify` flag in the forge script command should automatically verify your contracts on Polygonscan. If verification fails, you can manually verify them:

```
forge verify-contract <deployed_contract_address> src/AutoMoveRangeHookFactory.sol:AutoMoveRangeHookFactory --etherscan-api-key <your_api_key> --chain polygon
```

Replace `<deployed_contract_address>` with your contract's address and `<your_api_key>` with your Polygonscan API key.

## Important Notes

- Before mainnet deployment, ensure all tests are passing with `forge test`.
- Double-check token addresses - using incorrect addresses can cause issues.
- The V4 PoolManager address must be correct for your hooks to function properly.
- Make sure your deployer wallet has sufficient MATIC for gas fees.
- Consider using a hardware wallet for added security when deploying to mainnet. 