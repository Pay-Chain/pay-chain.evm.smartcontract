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
	set-bridge-token-dry set-bridge-token-broadcast check-bridge-token \
	set-v1-status-dry set-v1-status-broadcast check-v1-status \
	validate-gateway-v2-dry \
	set-fee-strategy-dry set-fee-strategy-broadcast validate-fee-strategy-dry \
	validate-gateway-selector-gate \
	validate-bytecode-gate validate-security-regression validate-phase7-gate privacy-regression \
	deploy-gateway-modular-dry deploy-gateway-modular-broadcast \
	deploy-gateway-modular-v2-dry deploy-gateway-modular-v2-broadcast deploy-gateway-modular-v2-verify \
	wire-gateway-modules-dry wire-gateway-modules-broadcast \
	validate-gateway-modular-dry validate-gateway-compat-dry \
	ccip-rotate-dry ccip-rotate-broadcast ccip-rotate-verify ccip-rotate

VERBOSITY ?= -vvvv
SLOW ?= --slow

help:
	@echo "Payment-Kita EVM deploy commands"
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
	@echo "Bridge token lane config (Phase 1 V2 normalization):"
	@echo "  make set-bridge-token-dry      - requires BRIDGE_TOKEN_* env"
	@echo "  make set-bridge-token-broadcast"
	@echo "  make check-bridge-token"
	@echo ""
	@echo "Gateway V1 status scripts (legacy/optional, V2 gateway may not support):"
	@echo "  make set-v1-status-dry         - requires GATEWAY_V1_STATUS_* env"
	@echo "  make set-v1-status-broadcast"
	@echo "  make check-v1-status"
	@echo ""
	@echo "Gateway V2 readiness gate (Phase 7):"
	@echo "  make validate-gateway-v2-dry   - requires GW_VALIDATE_* env"
	@echo ""
	@echo "Gateway fee strategy rollout (Phase 5):"
	@echo "  make set-fee-strategy-dry      - requires GW_FEE_* env"
	@echo "  make set-fee-strategy-broadcast"
	@echo "  make validate-fee-strategy-dry"
	@echo ""
	@echo "Gateway ABI/selector gate (Phase 6):"
	@echo "  make validate-gateway-selector-gate"
	@echo ""
	@echo "Gateway bytecode/security gate (Phase 7):"
	@echo "  make validate-bytecode-gate      - enforce EIP-170 + runtime margin"
	@echo "  make validate-security-regression - run core gateway/adapter/fee suites"
	@echo "  make validate-phase7-gate         - run both gates"
	@echo "  make privacy-regression           - run privacy path regression suites"
	@echo ""
	@echo "Gateway modular rollout (Phase 6):"
	@echo "  make deploy-gateway-modular-dry"
	@echo "  make deploy-gateway-modular-broadcast"
	@echo "  make deploy-gateway-modular-v2-dry"
	@echo "  make deploy-gateway-modular-v2-broadcast"
	@echo "  make deploy-gateway-modular-v2-verify"
	@echo "  make wire-gateway-modules-dry"
	@echo "  make wire-gateway-modules-broadcast"
	@echo "  make validate-gateway-modular-dry"
	@echo "  make validate-gateway-compat-dry"
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
	@forge script script/RedeployPaymentKitaGatewayV2.s.sol:RedeployPaymentKitaGatewayV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

redeploy-gateway-v2:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@forge script script/RedeployPaymentKitaGatewayV2.s.sol:RedeployPaymentKitaGatewayV2 \
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

set-bridge-token-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BRIDGE_TOKEN_GATEWAY)" || (echo "Missing BRIDGE_TOKEN_GATEWAY" && exit 1)
	@test -n "$(BRIDGE_TOKEN_DEST_CAIP2)" || (echo "Missing BRIDGE_TOKEN_DEST_CAIP2" && exit 1)
	@test -n "$(BRIDGE_TOKEN_SOURCE_TOKEN)" || (echo "Missing BRIDGE_TOKEN_SOURCE_TOKEN" && exit 1)
	@forge script script/SetBridgeTokenForDest.s.sol:SetBridgeTokenForDest \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

set-bridge-token-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BRIDGE_TOKEN_GATEWAY)" || (echo "Missing BRIDGE_TOKEN_GATEWAY" && exit 1)
	@test -n "$(BRIDGE_TOKEN_DEST_CAIP2)" || (echo "Missing BRIDGE_TOKEN_DEST_CAIP2" && exit 1)
	@test -n "$(BRIDGE_TOKEN_SOURCE_TOKEN)" || (echo "Missing BRIDGE_TOKEN_SOURCE_TOKEN" && exit 1)
	@forge script script/SetBridgeTokenForDest.s.sol:SetBridgeTokenForDest \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

check-bridge-token:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BRIDGE_TOKEN_GATEWAY)" || (echo "Missing BRIDGE_TOKEN_GATEWAY" && exit 1)
	@test -n "$(BRIDGE_TOKEN_DEST_CAIP2)" || (echo "Missing BRIDGE_TOKEN_DEST_CAIP2" && exit 1)
	@forge script script/CheckBridgeTokenForDest.s.sol:CheckBridgeTokenForDest \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

set-v1-status-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GATEWAY_V1_STATUS_GATEWAY)" || (echo "Missing GATEWAY_V1_STATUS_GATEWAY" && exit 1)
	@test -n "$(GATEWAY_V1_STATUS_MODE)" || (echo "Missing GATEWAY_V1_STATUS_MODE" && exit 1)
	@forge script script/SetGatewayV1Status.s.sol:SetGatewayV1Status \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

set-v1-status-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GATEWAY_V1_STATUS_GATEWAY)" || (echo "Missing GATEWAY_V1_STATUS_GATEWAY" && exit 1)
	@test -n "$(GATEWAY_V1_STATUS_MODE)" || (echo "Missing GATEWAY_V1_STATUS_MODE" && exit 1)
	@forge script script/SetGatewayV1Status.s.sol:SetGatewayV1Status \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

check-v1-status:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GATEWAY_V1_STATUS_GATEWAY)" || (echo "Missing GATEWAY_V1_STATUS_GATEWAY" && exit 1)
	@forge script script/CheckGatewayV1Status.s.sol:CheckGatewayV1Status \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

validate-gateway-v2-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_VALIDATE_GATEWAY)" || (echo "Missing GW_VALIDATE_GATEWAY" && exit 1)
	@test -n "$(GW_VALIDATE_ROUTER)" || (echo "Missing GW_VALIDATE_ROUTER" && exit 1)
	@test -n "$(GW_VALIDATE_DEST_CAIP2)" || (echo "Missing GW_VALIDATE_DEST_CAIP2" && exit 1)
	@test -n "$(GW_VALIDATE_SOURCE_TOKEN)" || (echo "Missing GW_VALIDATE_SOURCE_TOKEN" && exit 1)
	@test -n "$(GW_VALIDATE_DEST_TOKEN)" || (echo "Missing GW_VALIDATE_DEST_TOKEN" && exit 1)
	@test -n "$(GW_VALIDATE_RECEIVER)" || (echo "Missing GW_VALIDATE_RECEIVER" && exit 1)
	@test -n "$(GW_VALIDATE_AMOUNT)" || (echo "Missing GW_VALIDATE_AMOUNT" && exit 1)
	@forge script script/ValidateGatewayV2Readiness.s.sol:ValidateGatewayV2Readiness \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

set-fee-strategy-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/SetGatewayFeeStrategy.s.sol:SetGatewayFeeStrategy \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

set-fee-strategy-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/SetGatewayFeeStrategy.s.sol:SetGatewayFeeStrategy \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

validate-fee-strategy-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_FEE_GATEWAY)" || (echo "Missing GW_FEE_GATEWAY" && exit 1)
	@forge script script/ValidateFeeStrategy.s.sol:ValidateFeeStrategy \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

validate-gateway-selector-gate:
	@methods="$$(forge inspect PaymentKitaGateway methodIdentifiers)"; \
	required_sigs="createPayment((bytes,bytes,address,address,address,uint256,uint256,uint256,uint8,uint8)) createPaymentPrivate((bytes,bytes,address,address,address,uint256,uint256,uint256,uint8,uint8),(bytes32,address)) createPaymentDefaultBridge((bytes,bytes,address,address,address,uint256,uint256,uint256,uint8,uint8)) quotePaymentCost((bytes,bytes,address,address,address,uint256,uint256,uint256,uint8,uint8)) previewApproval((bytes,bytes,address,address,address,uint256,uint256,uint256,uint8,uint8))"; \
	forbidden_sigs="createPayment(bytes,bytes,address,address,uint256) createPaymentWithSlippage(bytes,bytes,address,address,uint256,uint256) createPaymentRequest(address,address,uint256,string) payRequest(bytes32) isRequestExpired(bytes32) setV1LaneDisabled(string,bool) setV1GlobalDisabled(bool) v1DisabledGlobal() v1DisabledByDestCaip2(string)"; \
	for sig in $$required_sigs; do \
		echo "$$methods" | grep -F "$$sig" >/dev/null || { echo "Selector gate failed: missing required method '$$sig'"; exit 1; }; \
	done; \
	for sig in $$forbidden_sigs; do \
		if echo "$$methods" | grep -F "$$sig" >/dev/null; then \
			echo "Selector gate failed: legacy method still present '$$sig'"; \
			exit 1; \
		fi; \
	done; \
	echo "Selector gate passed: final methods present, legacy methods absent"

validate-bytecode-gate:
	@report="$$(forge build --sizes)"; \
	echo "$$report" >/tmp/paymentkita-forge-sizes.txt; \
	line="$$(echo "$$report" | rg "PaymentKitaGateway\\s+\\|" | head -n1)"; \
	[ -n "$$line" ] || { echo "Bytecode gate failed: PaymentKitaGateway row not found"; exit 1; }; \
	runtime_margin="$$(echo "$$line" | awk -F'|' '{gsub(/[ ,]/, "", $$5); print $$5}')"; \
	runtime_size="$$(echo "$$line" | awk -F'|' '{gsub(/[ ,]/, "", $$3); print $$3}')"; \
	[ -n "$$runtime_margin" ] || { echo "Bytecode gate failed: runtime margin parse failed"; exit 1; }; \
	[ -n "$$runtime_size" ] || { echo "Bytecode gate failed: runtime size parse failed"; exit 1; }; \
	[ "$$runtime_size" -le 24576 ] || { echo "Bytecode gate failed: runtime size $$runtime_size exceeds EIP-170 limit"; exit 1; }; \
	[ "$$runtime_margin" -gt 500 ] || { echo "Bytecode gate failed: runtime margin $$runtime_margin <= 500"; exit 1; }; \
	echo "Bytecode gate passed: runtime_size=$$runtime_size runtime_margin=$$runtime_margin"

validate-security-regression:
	@forge test --offline --match-path test/PaymentKitaGateway.V2Phase1.t.sol
	@forge test --offline --match-path test/FeePolicyAndStrategy.t.sol
	@forge test --offline --match-path test/BridgeAdapters.t.sol
	@forge test --offline --match-path test/PaymentKitaGateway.Revert.t.sol

validate-phase7-gate:
	@$(MAKE) validate-bytecode-gate
	@$(MAKE) validate-security-regression

privacy-regression:
	@forge test --offline --match-contract PaymentKitaGatewayV2Phase1Test --match-test Privacy
	@forge test --offline --match-contract PrivacyForwardAdaptersPhase2Test
	@forge test --offline --match-contract HyperbridgeReceiverTest

deploy-gateway-modular-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/DeployGatewayModular.s.sol:DeployGatewayModular \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-gateway-modular-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@forge script script/DeployGatewayModular.s.sol:DeployGatewayModular \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-gateway-modular-v2-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GWV2_OLD_GATEWAY)" || (echo "Missing GWV2_OLD_GATEWAY" && exit 1)
	@forge script script/DeployGatewayModularV2.s.sol:DeployGatewayModularV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

deploy-gateway-modular-v2-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GWV2_OLD_GATEWAY)" || (echo "Missing GWV2_OLD_GATEWAY" && exit 1)
	@forge script script/DeployGatewayModularV2.s.sol:DeployGatewayModularV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

deploy-gateway-modular-v2-verify:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(BASESCAN_API_KEY)" || (echo "Missing BASESCAN_API_KEY" && exit 1)
	@test -n "$(GWV2_OLD_GATEWAY)" || (echo "Missing GWV2_OLD_GATEWAY" && exit 1)
	@forge script script/DeployGatewayModularV2.s.sol:DeployGatewayModularV2 \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(BASESCAN_API_KEY) \
		$(VERBOSITY) $(SLOW)

wire-gateway-modules-dry:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_MOD_GATEWAY)" || (echo "Missing GW_MOD_GATEWAY" && exit 1)
	@forge script script/WireGatewayModules.s.sol:WireGatewayModules \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		$(VERBOSITY)

wire-gateway-modules-broadcast:
	@test -n "$(PRIVATE_KEY)" || (echo "Missing PRIVATE_KEY" && exit 1)
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_MOD_GATEWAY)" || (echo "Missing GW_MOD_GATEWAY" && exit 1)
	@forge script script/WireGatewayModules.s.sol:WireGatewayModules \
		--rpc-url $(BASE_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		$(VERBOSITY) $(SLOW)

validate-gateway-modular-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_MOD_GATEWAY)" || (echo "Missing GW_MOD_GATEWAY" && exit 1)
	@forge script script/ValidateGatewayModularReadiness.s.sol:ValidateGatewayModularReadiness \
		--rpc-url $(BASE_RPC_URL) \
		$(VERBOSITY)

validate-gateway-compat-dry:
	@test -n "$(BASE_RPC_URL)" || (echo "Missing BASE_RPC_URL" && exit 1)
	@test -n "$(GW_COMPAT_GATEWAY)" || (echo "Missing GW_COMPAT_GATEWAY" && exit 1)
	@forge script script/ValidateGatewayCompatibility.s.sol:ValidateGatewayCompatibility \
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
