-include .env

.DEFAULT_GOAL := help

.PHONY: help env-check build test clean \
	deploy-base-dry deploy-bsc-dry deploy-arbitrum-dry deploy-polygon-dry \
	deploy-base deploy-bsc deploy-arbitrum deploy-polygon \
	deploy-base-verify deploy-bsc-verify deploy-arbitrum-verify deploy-polygon-verify \
	rotate-hb-dry rotate-hb-broadcast rotate-hb-verify rotate-hb \
	redeploy-hb-sender-dry redeploy-hb-sender-broadcast redeploy-hb-sender-verify redeploy-hb-sender \
	redeploy-gateway-v2-dry redeploy-gateway-v2 \
	redeploy-router-gateway-v2-dry redeploy-router-gateway-v2 \
	verify-lz-base \
	lz-config-dry lz-config \
	rotate-lz-dry rotate-lz-broadcast rotate-lz-verify rotate-lz \
	lz-validate-dry \
	ccip-validate-dry \
	ccip-rotate-dry ccip-rotate-broadcast ccip-rotate-verify ccip-rotate

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
	@echo ""
	@echo "Hyperbridge sender rotation (minimal redeploy):"
	@echo "  make rotate-hb-dry"
	@echo "  make rotate-hb-broadcast"
	@echo "  make rotate-hb-verify"
	@echo "  make rotate-hb                - alias to rotate-hb-verify"
	@echo ""
	@echo "Hyperbridge sender redeploy (full helper script):"
	@echo "  make redeploy-hb-sender-dry"
	@echo "  make redeploy-hb-sender-broadcast"
	@echo "  make redeploy-hb-sender-verify"
	@echo "  make redeploy-hb-sender       - alias to redeploy-hb-sender-verify"
	@echo ""
	@echo "Gateway V2 redeploy (keep router/adapters):"
	@echo "  make redeploy-gateway-v2-dry"
	@echo "  make redeploy-gateway-v2"
	@echo ""
	@echo "Router+GatewayV2 rewire (deploy router baru + rotate HB sender):"
	@echo "  make redeploy-router-gateway-v2-dry"
	@echo "  make redeploy-router-gateway-v2"
	@echo ""
	@echo "LayerZero route/peer/delegate config:"
	@echo "  make lz-config-dry            - requires RPC_URL + LZ_CFG_* env"
	@echo "  make lz-config                - broadcast config tx"
	@echo "  make verify-lz-base           - verify rotated LZ sender+receiver on BaseScan"
	@echo ""
	@echo "LayerZero adapter rotation (deploy sender+receiver baru):"
	@echo "  make rotate-lz-dry            - requires RPC_URL + LZ_ROTATE_* env"
	@echo "  make rotate-lz-broadcast"
	@echo "  make rotate-lz-verify         - broadcast + verify (BaseScan)"
	@echo "  make rotate-lz                - alias rotate-lz-verify"
	@echo ""
	@echo "LayerZero path validation gate:"
	@echo "  make lz-validate-dry          - requires RPC_URL + LZ_VALIDATE_* env"
	@echo ""
	@echo "CCIP path validation gate:"
	@echo "  make ccip-validate-dry        - requires BASE_RPC_URL + CCIP_VALIDATE_* env"
	@echo ""
	@echo "CCIP adapter rotation (deploy sender+receiver baru, register+auth+trust):"
	@echo "  make ccip-rotate-dry          - profile-based (CCIP_ROTATE_PROFILE)"
	@echo "  make ccip-rotate-broadcast"
	@echo "  make ccip-rotate-verify       - broadcast + verify explorer"
	@echo "  make ccip-rotate              - alias ccip-rotate-verify"

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

rotate-hb-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RotateHyperbridgeSender.s.sol:RotateHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

rotate-hb-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RotateHyperbridgeSender.s.sol:RotateHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

rotate-hb-verify:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RotateHyperbridgeSender.s.sol:RotateHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

rotate-hb: rotate-hb-verify

redeploy-hb-sender-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RedeployHyperbridgeSender.s.sol:RedeployHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

redeploy-hb-sender-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RedeployHyperbridgeSender.s.sol:RedeployHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

redeploy-hb-sender-verify:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RedeployHyperbridgeSender.s.sol:RedeployHyperbridgeSender \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

redeploy-hb-sender: redeploy-hb-sender-verify

redeploy-gateway-v2-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RedeployPayChainGatewayV2.s.sol:RedeployPayChainGatewayV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

redeploy-gateway-v2:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RedeployPayChainGatewayV2.s.sol:RedeployPayChainGatewayV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

redeploy-router-gateway-v2-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RedeployRouterAndRewireGatewayV2.s.sol:RedeployRouterAndRewireGatewayV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

redeploy-router-gateway-v2:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RedeployRouterAndRewireGatewayV2.s.sol:RedeployRouterAndRewireGatewayV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

lz-config-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(RPC_URL)" || (echo "Missing RPC_URL" && exit 1)
	@forge script script/ConfigureLayerZeroPeers.s.sol:ConfigureLayerZeroPeers \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

lz-config:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(RPC_URL)" || (echo "Missing RPC_URL" && exit 1)
	@forge script script/ConfigureLayerZeroPeers.s.sol:ConfigureLayerZeroPeers \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

verify-lz-base:
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@BASESCAN_API_KEY="$(BASESCAN_API_KEY)" ./script/VerifyLayerZeroBase.sh

rotate-lz-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RotateLayerZeroAdapters.s.sol:RotateLayerZeroAdapters \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

rotate-lz-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/RotateLayerZeroAdapters.s.sol:RotateLayerZeroAdapters \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

rotate-lz-verify:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RotateLayerZeroAdapters.s.sol:RotateLayerZeroAdapters \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

rotate-lz: rotate-lz-verify

lz-validate-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/ValidateLayerZeroPath.s.sol:ValidateLayerZeroPath \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

ccip-validate-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/ValidateCCIPPath.s.sol:ValidateCCIPPath \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

ccip-rotate-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@PROFILE=$${CCIP_ROTATE_PROFILE:-base}; \
	case "$$PROFILE" in \
	  base) RPC="$(BASE_RPC_URL)" ;; \
	  polygon) RPC="$(POLYGON_RPC_URL)" ;; \
	  arbitrum) RPC="$(ARBITRUM_RPC_URL)" ;; \
	  bsc) RPC="$(BSC_RPC_URL)" ;; \
	  auto) RPC="$(BASE_RPC_URL)" ;; \
	  *) echo "Unsupported CCIP_ROTATE_PROFILE=$$PROFILE" && exit 1 ;; \
	esac; \
	test -n "$$RPC" || (echo "Missing RPC URL for profile=$$PROFILE" && exit 1); \
	forge script script/RotateCCIPAdapters.s.sol:RotateCCIPAdapters \
		--rpc-url $$RPC \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

ccip-rotate-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@PROFILE=$${CCIP_ROTATE_PROFILE:-base}; \
	case "$$PROFILE" in \
	  base) RPC="$(BASE_RPC_URL)" ;; \
	  polygon) RPC="$(POLYGON_RPC_URL)" ;; \
	  arbitrum) RPC="$(ARBITRUM_RPC_URL)" ;; \
	  bsc) RPC="$(BSC_RPC_URL)" ;; \
	  auto) RPC="$(BASE_RPC_URL)" ;; \
	  *) echo "Unsupported CCIP_ROTATE_PROFILE=$$PROFILE" && exit 1 ;; \
	esac; \
	test -n "$$RPC" || (echo "Missing RPC URL for profile=$$PROFILE" && exit 1); \
	forge script script/RotateCCIPAdapters.s.sol:RotateCCIPAdapters \
		--rpc-url $$RPC \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

ccip-rotate-verify:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@PROFILE=$${CCIP_ROTATE_PROFILE:-base}; \
	case "$$PROFILE" in \
	  base) RPC="$(BASE_RPC_URL)"; API="$(BASESCAN_API_KEY)"; CHAIN="" ;; \
	  polygon) RPC="$(POLYGON_RPC_URL)"; API="$(POLYGONSCAN_API_KEY)"; CHAIN="--chain polygon" ;; \
	  arbitrum) RPC="$(ARBITRUM_RPC_URL)"; API="$(ARBISCAN_API_KEY)"; CHAIN="--chain arbitrum" ;; \
	  bsc) RPC="$(BSC_RPC_URL)"; API="$(BSCSCAN_API_KEY)"; CHAIN="--chain bsc" ;; \
	  auto) RPC="$(BASE_RPC_URL)"; API="$(BASESCAN_API_KEY)"; CHAIN="" ;; \
	  *) echo "Unsupported CCIP_ROTATE_PROFILE=$$PROFILE" && exit 1 ;; \
	esac; \
	test -n "$$RPC" || (echo "Missing RPC URL for profile=$$PROFILE" && exit 1); \
	test -n "$$API" || (echo "Missing explorer API key for profile=$$PROFILE" && exit 1); \
	forge script script/RotateCCIPAdapters.s.sol:RotateCCIPAdapters \
		--rpc-url $$RPC \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $$API \
		$$CHAIN \
		$(VERBOSITY) $(SLOW)

ccip-rotate: ccip-rotate-verify
