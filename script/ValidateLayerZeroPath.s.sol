// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IBridgeAdapter.sol";

interface IRouterLZValidate {
    function hasAdapter(string memory destChainId, uint8 bridgeType) external view returns (bool);
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
    function quotePaymentFee(
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view returns (uint256 fee);
}

interface IGatewayLZValidate {
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface ILayerZeroSenderValidate {
    function dstEids(string calldata destChainId) external view returns (uint32);
    function peers(string calldata destChainId) external view returns (bytes32);
    function enforcedOptions(string calldata destChainId) external view returns (bytes memory);
    function isRouteConfigured(string calldata destChainId) external view returns (bool);
}

interface ILayerZeroReceiverValidate {
    function getPathState(
        uint32 _srcEid,
        bytes32 _sender
    ) external view returns (bool peerConfigured, bool trusted, bytes32 configuredPeer, uint64 expectedNonce);

    function peers(uint32 _eid) external view returns (bytes32);
}

contract ValidateLayerZeroPath is Script {
    struct ValidateConfig {
        address router;
        address gateway;
        address receiver;
        string destCaip2;
        uint8 bridgeType;
        bool strict;
        uint32 dstEid;
        bytes32 dstPeer;
        uint32 srcEid;
        bytes32 srcSender;
        address sourceToken;
        address destToken;
        uint256 amount;
    }

    function run() external {
        ValidateConfig memory cfg = _resolveValidateConfig();

        IRouterLZValidate r = IRouterLZValidate(cfg.router);
        bool has = r.hasAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("hasAdapter:", has);
        if (cfg.strict) require(has, "LZ validate: adapter missing");
        if (!has) return;

        address sender = r.getAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("sender:", sender);

        ILayerZeroSenderValidate s = ILayerZeroSenderValidate(sender);
        bool configured = s.isRouteConfigured(cfg.destCaip2);
        console.log("sender route configured:", configured);
        if (cfg.strict) require(configured, "LZ validate: sender route not configured");

        uint32 actualDstEid = s.dstEids(cfg.destCaip2);
        bytes32 actualDstPeer = s.peers(cfg.destCaip2);
        bytes memory opts = s.enforcedOptions(cfg.destCaip2);

        console.log("actualDstEid:", actualDstEid);
        console.logBytes32(actualDstPeer);
        console.log("optionsLen:", opts.length);

        if (cfg.strict) {
            require(actualDstEid == cfg.dstEid, "LZ validate: dstEid mismatch");
            require(actualDstPeer == cfg.dstPeer, "LZ validate: dstPeer mismatch");
        }

        if (cfg.gateway != address(0)) {
            uint8 defaultBridge = IGatewayLZValidate(cfg.gateway).defaultBridgeTypes(cfg.destCaip2);
            console.log("gateway default bridge:", defaultBridge);
            if (cfg.strict) require(defaultBridge == cfg.bridgeType, "LZ validate: default bridge mismatch");
        }

        if (cfg.receiver != address(0) && cfg.srcEid > 0 && cfg.srcSender != bytes32(0)) {
            try ILayerZeroReceiverValidate(cfg.receiver).getPathState(cfg.srcEid, cfg.srcSender) returns (
                bool peerConfigured,
                bool trusted,
                bytes32 configuredPeer,
                uint64 expectedNonce
            ) {
                console.log("receiver peerConfigured:", peerConfigured);
                console.log("receiver trusted:", trusted);
                console.logBytes32(configuredPeer);
                console.log("receiver expectedNonce:", expectedNonce);

                if (cfg.strict) {
                    require(peerConfigured, "LZ validate: receiver peer not configured");
                    require(trusted, "LZ validate: receiver peer not trusted");
                    require(configuredPeer == cfg.srcSender, "LZ validate: receiver peer mismatch");
                }
            } catch {
                // Backward compatibility for older receiver contracts
                // that do not expose getPathState().
                try ILayerZeroReceiverValidate(cfg.receiver).peers(cfg.srcEid) returns (bytes32 configuredPeerFallback) {
                    bool peerConfiguredFallback = configuredPeerFallback != bytes32(0);
                    bool trustedFallback = peerConfiguredFallback && configuredPeerFallback == cfg.srcSender;

                    console.log("receiver peerConfigured (fallback):", peerConfiguredFallback);
                    console.log("receiver trusted (fallback):", trustedFallback);
                    console.logBytes32(configuredPeerFallback);

                    if (cfg.strict) {
                        require(peerConfiguredFallback, "LZ validate: receiver peer not configured");
                        require(trustedFallback, "LZ validate: receiver peer mismatch");
                    }
                } catch {
                    if (cfg.strict) revert("LZ validate: receiver path read failed");
                    console.log("receiver path check: reverted");
                }
            }
        }

        if (cfg.sourceToken != address(0) && cfg.destToken != address(0) && cfg.amount > 0) {
            IBridgeAdapter.BridgeMessage memory m = IBridgeAdapter.BridgeMessage({
                paymentId: bytes32(0),
                receiver: address(0),
                sourceToken: cfg.sourceToken,
                destToken: cfg.destToken,
                amount: cfg.amount,
                destChainId: cfg.destCaip2,
                minAmountOut: 0,
                payer: address(0)
            });
            try r.quotePaymentFee(cfg.destCaip2, cfg.bridgeType, m) returns (uint256 fee) {
                console.log("quotePaymentFee:", fee);
                if (cfg.strict) require(fee > 0, "LZ validate: quote zero");
            } catch {
                if (cfg.strict) revert("LZ validate: quote reverted");
                console.log("quotePaymentFee: reverted");
            }
        }
    }

    function _resolveValidateConfig() internal returns (ValidateConfig memory cfg) {
        string memory profile = vm.envOr("LZ_VALIDATE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = ValidateConfig({
                router: 0x1d7550079DAe36f55F4999E0B24AC037D092249C,
                gateway: 0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D,
                receiver: vm.envOr("BASE_LZ_VALIDATE_RECEIVER", 0x4864138d5Dc8a5bcFd4228D7F784D1F32859986f),
                destCaip2: vm.envOr("BASE_LZ_VALIDATE_DEST_CAIP2", string("eip155:137")),
                bridgeType: uint8(vm.envOr("BASE_LZ_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("BASE_LZ_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("BASE_LZ_VALIDATE_DST_EID", uint256(30109))),
                dstPeer: vm.parseBytes32(vm.envString("BASE_LZ_VALIDATE_DST_PEER_BYTES32")),
                srcEid: uint32(vm.envOr("BASE_LZ_VALIDATE_SRC_EID", uint256(30109))),
                srcSender: vm.parseBytes32(vm.envString("BASE_LZ_VALIDATE_SRC_SENDER_BYTES32")),
                sourceToken: vm.envOr("BASE_LZ_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("BASE_LZ_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("BASE_LZ_VALIDATE_AMOUNT", uint256(0))
            });
        } else if (_eq(profile, "polygon") || (_eq(profile, "auto") && block.chainid == 137)) {
            cfg = ValidateConfig({
                router: 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4,
                gateway: 0x7a4f3b606D90e72555A36cB370531638fad19Bf8,
                receiver: vm.envOr("POLYGON_LZ_VALIDATE_RECEIVER", 0x67AAc121bc447F112389921A8B94c3D6FCBd98f9),
                destCaip2: vm.envOr("POLYGON_LZ_VALIDATE_DEST_CAIP2", string("eip155:8453")),
                bridgeType: uint8(vm.envOr("POLYGON_LZ_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("POLYGON_LZ_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("POLYGON_LZ_VALIDATE_DST_EID", uint256(30184))),
                dstPeer: vm.parseBytes32(vm.envString("POLYGON_LZ_VALIDATE_DST_PEER_BYTES32")),
                srcEid: uint32(vm.envOr("POLYGON_LZ_VALIDATE_SRC_EID", uint256(30184))),
                srcSender: vm.parseBytes32(vm.envString("POLYGON_LZ_VALIDATE_SRC_SENDER_BYTES32")),
                sourceToken: vm.envOr("POLYGON_LZ_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("POLYGON_LZ_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("POLYGON_LZ_VALIDATE_AMOUNT", uint256(0))
            });
        } else if (_eq(profile, "arbitrum") || (_eq(profile, "auto") && block.chainid == 42161)) {
            cfg = ValidateConfig({
                router: 0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e,
                gateway: 0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8,
                receiver: vm.envOr("ARBITRUM_LZ_VALIDATE_RECEIVER", 0x7A356d451157F2AE128AD6Bd21Aa77605fAae09c),
                destCaip2: vm.envOr("ARBITRUM_LZ_VALIDATE_DEST_CAIP2", string("eip155:8453")),
                bridgeType: uint8(vm.envOr("ARBITRUM_LZ_VALIDATE_BRIDGE_TYPE", uint256(2))),
                strict: vm.envOr("ARBITRUM_LZ_VALIDATE_STRICT", true),
                dstEid: uint32(vm.envOr("ARBITRUM_LZ_VALIDATE_DST_EID", uint256(30184))),
                dstPeer: vm.parseBytes32(vm.envString("ARBITRUM_LZ_VALIDATE_DST_PEER_BYTES32")),
                srcEid: uint32(vm.envOr("ARBITRUM_LZ_VALIDATE_SRC_EID", uint256(30184))),
                srcSender: vm.parseBytes32(vm.envString("ARBITRUM_LZ_VALIDATE_SRC_SENDER_BYTES32")),
                sourceToken: vm.envOr("ARBITRUM_LZ_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("ARBITRUM_LZ_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("ARBITRUM_LZ_VALIDATE_AMOUNT", uint256(0))
            });
        } else {
            revert("LZ validate: unknown profile or chainid");
        }

        // Optional global overrides for emergency checks.
        cfg.router = vm.envOr("LZ_VALIDATE_ROUTER", cfg.router);
        cfg.gateway = vm.envOr("LZ_VALIDATE_GATEWAY", cfg.gateway);
        cfg.receiver = vm.envOr("LZ_VALIDATE_RECEIVER", cfg.receiver);
        cfg.destCaip2 = vm.envOr("LZ_VALIDATE_DEST_CAIP2", cfg.destCaip2);
        cfg.bridgeType = uint8(vm.envOr("LZ_VALIDATE_BRIDGE_TYPE", uint256(cfg.bridgeType)));
        cfg.strict = vm.envOr("LZ_VALIDATE_STRICT", cfg.strict);
        cfg.dstEid = uint32(vm.envOr("LZ_VALIDATE_DST_EID", uint256(cfg.dstEid)));
        cfg.srcEid = uint32(vm.envOr("LZ_VALIDATE_SRC_EID", uint256(cfg.srcEid)));
        cfg.sourceToken = vm.envOr("LZ_VALIDATE_SOURCE_TOKEN", cfg.sourceToken);
        cfg.destToken = vm.envOr("LZ_VALIDATE_DEST_TOKEN", cfg.destToken);
        cfg.amount = vm.envOr("LZ_VALIDATE_AMOUNT", cfg.amount);

        string memory dstPeerHex = vm.envOr("LZ_VALIDATE_DST_PEER_BYTES32", string(""));
        if (bytes(dstPeerHex).length > 0) {
            cfg.dstPeer = vm.parseBytes32(dstPeerHex);
        }
        string memory srcSenderHex = vm.envOr("LZ_VALIDATE_SRC_SENDER_BYTES32", string(""));
        if (bytes(srcSenderHex).length > 0) {
            cfg.srcSender = vm.parseBytes32(srcSenderHex);
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
