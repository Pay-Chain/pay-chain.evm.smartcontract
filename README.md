# Pay-Chain EVM Smart Contracts

Cross-chain payment smart contracts for EVM chains built with Solidity and Foundry.

## Tech Stack

- **Language**: Solidity ^0.8.20
- **Framework**: Foundry
- **Testing**: Forge
- **Dependencies**: OpenZeppelin, Chainlink CCIP

## Getting Started

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
```

## Contracts

- `PayChain.sol` - Main payment gateway contract
- `FeeCalculator.sol` - Fee calculation library
- `interfaces/` - Contract interfaces

## Supported Networks (Phase 1)

| Network | Chain ID | Type |
|---------|----------|------|
| Base Sepolia | 84532 | Testnet |
| BSC Sepolia | 97 | Testnet |

## Environment Variables

Copy `.env.example` to `.env`:

```env
PRIVATE_KEY=your-private-key
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BSC_SEPOLIA_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545
ETHERSCAN_API_KEY=your-api-key
```
