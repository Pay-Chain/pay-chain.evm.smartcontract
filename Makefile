-include .env

.PHONY: all test clean deploy-base deploy-bsc deploy-arbitrum

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

# Install the Modules
install :; forge install cyfrin/foundry-devops@0.0.11 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit && forge install foundry-rs/forge-std@v1.5.3 --no-commit

# Update Dependencies
update:; forge update

# Build
build:; forge build

# Test
test :; forge test 

# Snapshot
snapshot :; forge snapshot

# Format
format :; forge fmt

# Anvil
anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

# Deploy to Base
deploy-base:
	@forge script script/DeployBase.s.sol:DeployBase --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv --slow

# Deploy to BSC
deploy-bsc:
	@forge script script/DeployBSC.s.sol:DeployBSC --rpc-url $(BSC_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BSCSCAN_API_KEY) -vvvv

# Deploy to Arbitrum
deploy-arbitrum:
	@forge script script/DeployArbitrum.s.sol:DeployArbitrum --rpc-url $(ARBITRUM_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ARBISCAN_API_KEY) -vvvv --slow

# Deploy Gateway (Common)
deploy-gateway:
	@forge script script/DeployGateway.s.sol:DeployGateway --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast -vvvv
