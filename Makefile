-include .env

.DEFAULT_GOAL := help

.PHONY: help env-check build test clean \
	deploy-base-dry deploy-bsc-dry deploy-arbitrum-dry deploy-polygon-dry \
	deploy-base deploy-bsc deploy-arbitrum deploy-polygon \
	deploy-base-verify deploy-bsc-verify deploy-arbitrum-verify deploy-polygon-verify

VERBOSITY ?= -vvvv
SLOW ?= --slow

help:
	@echo "Pay-Chain EVM deploy commands"
	@echo ""
	@echo "Core:"
	@echo "  make env-check             - check required env vars"
	@echo "  make build                 - forge build"
	@echo "  make test                  - forge test --offline"
	@echo ""
	@echo "Dry run (no broadcast):"
	@echo "  make deploy-base-dry"
	@echo "  make deploy-bsc-dry"
	@echo "  make deploy-arbitrum-dry"
	@echo "  make deploy-polygon-dry"
	@echo ""
	@echo "Broadcast deploy:"
	@echo "  make deploy-base"
	@echo "  make deploy-bsc"
	@echo "  make deploy-arbitrum"
	@echo "  make deploy-polygon"
	@echo ""
	@echo "Broadcast + verify:"
	@echo "  make deploy-base-verify"
	@echo "  make deploy-bsc-verify"
	@echo "  make deploy-arbitrum-verify"
	@echo "  make deploy-polygon-verify"

env-check:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(FEE_RECIPIENT_ADDRESS)" || (echo "Missing FEE_RECIPIENT_ADDRESS" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BSC_RPC_URL)" || (echo "Missing BSC_RPC_URL" && exit 1)
	@test -n "$(ARBITRUM_RPC_URL)" || (echo "Missing ARBITRUM_RPC_URL" && exit 1)
	@test -n "$(POLYGON_RPC_URL)" || (echo "Missing POLYGON_RPC_URL" && exit 1)

build:
	@forge build

compile:
	@forge compile

test:
	@forge test --offline

clean:
	@forge clean

deploy-base-dry: env-check
	@forge script script/DeployBase.s.sol:DeployBase \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-bsc-dry: env-check
	@forge script script/DeployBSC.s.sol:DeployBSC \
		--rpc-url $(BSC_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-arbitrum-dry: env-check
	@forge script script/DeployArbitrum.s.sol:DeployArbitrum \
		--rpc-url $(ARBITRUM_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-base: env-check
	@forge script script/DeployBase.s.sol:DeployBase \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-bsc: env-check
	@forge script script/DeployBSC.s.sol:DeployBSC \
		--rpc-url $(BSC_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-arbitrum: env-check
	@forge script script/DeployArbitrum.s.sol:DeployArbitrum \
		--rpc-url $(ARBITRUM_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-base-verify: env-check
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/DeployBase.s.sol:DeployBase \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

deploy-bsc-verify: env-check
	@test -n "$(BSCSCAN_API_KEY)" || (echo "Missing BSCSCAN_API_KEY" && exit 1)
	@forge script script/DeployBSC.s.sol:DeployBSC \
		--rpc-url $(BSC_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BSCSCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

deploy-arbitrum-verify: env-check
	@test -n "$(ARBISCAN_API_KEY)" || (echo "Missing ARBISCAN_API_KEY" && exit 1)
	@forge script script/DeployArbitrum.s.sol:DeployArbitrum \
		--rpc-url $(ARBITRUM_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ARBISCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

deploy-polygon-dry: env-check
	@forge script script/DeployPolygon.s.sol:DeployPolygon \
		--rpc-url $(POLYGON_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-polygon: env-check
	@forge script script/DeployPolygon.s.sol:DeployPolygon \
		--rpc-url $(POLYGON_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-polygon-verify: env-check
	@test -n "$(POLYGONSCAN_API_KEY)" || (echo "Missing POLYGONSCAN_API_KEY" && exit 1)
	@forge script script/DeployPolygon.s.sol:DeployPolygon \
		--rpc-url $(POLYGON_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(POLYGONSCAN_API_KEY) \
		--chain polygon \
		$(VERBOSITY) $(SLOW)
