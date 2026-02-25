// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/integrations/layerzero/LayerZeroSenderAdapter.sol";
import "../src/integrations/layerzero/LayerZeroReceiverAdapter.sol";

interface IRouterRotateLZ {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
}

interface IGatewayRotateLZ {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface IVaultRotateLZ {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ILZReceiverView {
    function swapper() external view returns (address);
    function peers(uint32 srcEid) external view returns (bytes32);
}

interface ILZSenderView {
    function dstEids(string calldata destChainId) external view returns (uint32);
    function peers(string calldata destChainId) external view returns (bytes32);
}

contract RotateLayerZeroAdapters is Script {
    uint8 internal constant BRIDGE_TYPE_LAYERZERO = 2;
    address internal constant LZ_ENDPOINT_V2_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;

    struct RotateConfig {
        address endpoint;
        address router;
        address gateway;
        address vault;
        string destCaip2;
        uint32 dstEid;
        uint32 srcEid;
        bytes32 dstPeer;
        bytes32 srcPeer;
        bytes options;
        bool deauthorizeOld;
        bool setDefaultBridgeType;
        address oldSender;
        address oldReceiver;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        RotateConfig memory cfg = _resolveRotateConfig();
        require(cfg.dstPeer != bytes32(0), "RotateLZ: dst peer not configured");

        vm.startBroadcast(pk);

        LayerZeroSenderAdapter newSender = new LayerZeroSenderAdapter(cfg.endpoint, cfg.router);
        LayerZeroReceiverAdapter newReceiver = new LayerZeroReceiverAdapter(cfg.endpoint, cfg.gateway, cfg.vault);

        address receiverSwapper = address(0);
        if (cfg.oldReceiver != address(0)) {
            receiverSwapper = ILZReceiverView(cfg.oldReceiver).swapper();
        }
        if (receiverSwapper != address(0)) {
            newReceiver.setSwapper(receiverSwapper);
        }

        newSender.setRoute(cfg.destCaip2, cfg.dstEid, cfg.dstPeer);
        if (cfg.options.length > 0) {
            newSender.setEnforcedOptions(cfg.destCaip2, cfg.options);
        }
        newSender.registerDelegate();

        if (cfg.srcEid > 0 && cfg.srcPeer != bytes32(0)) {
            newReceiver.setPeer(cfg.srcEid, cfg.srcPeer);
        }

        IVaultRotateLZ(cfg.vault).setAuthorizedSpender(address(newReceiver), true);
        IVaultRotateLZ(cfg.vault).setAuthorizedSpender(address(newSender), true);
        IGatewayRotateLZ(cfg.gateway).setAuthorizedAdapter(address(newReceiver), true);
        IRouterRotateLZ(cfg.router).registerAdapter(cfg.destCaip2, BRIDGE_TYPE_LAYERZERO, address(newSender));
        if (cfg.setDefaultBridgeType) {
            IGatewayRotateLZ(cfg.gateway).setDefaultBridgeType(cfg.destCaip2, BRIDGE_TYPE_LAYERZERO);
        }

        if (cfg.deauthorizeOld) {
            if (cfg.oldReceiver != address(0)) {
                IGatewayRotateLZ(cfg.gateway).setAuthorizedAdapter(cfg.oldReceiver, false);
                IVaultRotateLZ(cfg.vault).setAuthorizedSpender(cfg.oldReceiver, false);
            }
            if (cfg.oldSender != address(0)) {
                IVaultRotateLZ(cfg.vault).setAuthorizedSpender(cfg.oldSender, false);
            }
        }

        // Readback assertions (fail-fast)
        require(
            IRouterRotateLZ(cfg.router).getAdapter(cfg.destCaip2, BRIDGE_TYPE_LAYERZERO) == address(newSender),
            "RotateLZ: router adapter mismatch"
        );
        require(ILZSenderView(address(newSender)).dstEids(cfg.destCaip2) == cfg.dstEid, "RotateLZ: dstEid mismatch");
        require(ILZSenderView(address(newSender)).peers(cfg.destCaip2) == cfg.dstPeer, "RotateLZ: dst peer mismatch");
        if (cfg.srcEid > 0 && cfg.srcPeer != bytes32(0)) {
            require(ILZReceiverView(address(newReceiver)).peers(cfg.srcEid) == cfg.srcPeer, "RotateLZ: src peer mismatch");
        }
        if (cfg.setDefaultBridgeType) {
            require(
                IGatewayRotateLZ(cfg.gateway).defaultBridgeTypes(cfg.destCaip2) == BRIDGE_TYPE_LAYERZERO,
                "RotateLZ: default bridge mismatch"
            );
        }

        vm.stopBroadcast();

        console.log("RotateLayerZeroAdapters complete");
        console.log("New LZ sender:", address(newSender));
        console.log("New LZ receiver:", address(newReceiver));
        console.log("Dest CAIP2:", cfg.destCaip2);
        console.log("dstEid:", cfg.dstEid);
        console.log("Router:", cfg.router);
        console.log("Gateway:", cfg.gateway);
        console.log("Vault:", cfg.vault);
    }

    function _resolveRotateConfig() internal returns (RotateConfig memory cfg) {
        // Single profile key to switch all per-chain values.
        // Supported: auto | base | polygon | arbitrum
        string memory profile = vm.envOr("LZ_ROTATE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = RotateConfig({
                endpoint: LZ_ENDPOINT_V2_MAINNET,
                router: 0x1d7550079DAe36f55F4999E0B24AC037D092249C,
                gateway: 0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D,
                vault: 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7,
                destCaip2: "eip155:137",
                dstEid: 30109,
                srcEid: 30109,
                dstPeer: vm.parseBytes32(vm.envString("BASE_LZ_ROTATE_DST_PEER_BYTES32")),
                srcPeer: _parseBytes32OrZero(vm.envOr("BASE_LZ_ROTATE_SRC_PEER_BYTES32", string(""))),
                options: _parseBytesOrEmpty(vm.envOr("BASE_LZ_ROTATE_OPTIONS_HEX", string(""))),
                deauthorizeOld: vm.envOr("BASE_LZ_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("BASE_LZ_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478,
                oldReceiver: 0x4864138d5Dc8a5bcFd4228D7F784D1F32859986f
            });
        } else if (_eq(profile, "polygon") || (_eq(profile, "auto") && block.chainid == 137)) {
            cfg = RotateConfig({
                endpoint: LZ_ENDPOINT_V2_MAINNET,
                router: 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4,
                gateway: 0x7a4f3b606D90e72555A36cB370531638fad19Bf8,
                vault: 0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c,
                destCaip2: "eip155:8453",
                dstEid: 30184,
                srcEid: 30184,
                dstPeer: vm.parseBytes32(vm.envString("POLYGON_LZ_ROTATE_DST_PEER_BYTES32")),
                srcPeer: _parseBytes32OrZero(vm.envOr("POLYGON_LZ_ROTATE_SRC_PEER_BYTES32", string(""))),
                options: _parseBytesOrEmpty(vm.envOr("POLYGON_LZ_ROTATE_OPTIONS_HEX", string(""))),
                deauthorizeOld: vm.envOr("POLYGON_LZ_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("POLYGON_LZ_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e,
                oldReceiver: 0x67AAc121bc447F112389921A8B94c3D6FCBd98f9
            });
        } else if (_eq(profile, "arbitrum") || (_eq(profile, "auto") && block.chainid == 42161)) {
            cfg = RotateConfig({
                endpoint: LZ_ENDPOINT_V2_MAINNET,
                router: 0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e,
                gateway: 0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8,
                vault: 0x12306CA381813595BeE3c64b19318419C9E12f02,
                destCaip2: "eip155:8453",
                dstEid: 30184,
                srcEid: 30184,
                dstPeer: vm.parseBytes32(vm.envString("ARBITRUM_LZ_ROTATE_DST_PEER_BYTES32")),
                srcPeer: _parseBytes32OrZero(vm.envOr("ARBITRUM_LZ_ROTATE_SRC_PEER_BYTES32", string(""))),
                options: _parseBytesOrEmpty(vm.envOr("ARBITRUM_LZ_ROTATE_OPTIONS_HEX", string(""))),
                deauthorizeOld: vm.envOr("ARBITRUM_LZ_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("ARBITRUM_LZ_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0x263a3a83755613c50Dc42329D9B7771d91D8c1c1,
                oldReceiver: 0x7A356d451157F2AE128AD6Bd21Aa77605fAae09c
            });
        } else {
            revert("RotateLZ: unknown profile or chainid");
        }

        // Keep only optional core overrides for emergency/hotfix.
        cfg.endpoint = vm.envOr("LZ_ROTATE_ENDPOINT", cfg.endpoint);
        cfg.router = vm.envOr("LZ_ROTATE_ROUTER", cfg.router);
        cfg.gateway = vm.envOr("LZ_ROTATE_GATEWAY", cfg.gateway);
        cfg.vault = vm.envOr("LZ_ROTATE_VAULT", cfg.vault);
        cfg.destCaip2 = vm.envOr("LZ_ROTATE_DEST_CAIP2", cfg.destCaip2);
        cfg.dstEid = uint32(vm.envOr("LZ_ROTATE_DST_EID", uint256(cfg.dstEid)));
        cfg.srcEid = uint32(vm.envOr("LZ_ROTATE_SRC_EID", uint256(cfg.srcEid)));
        cfg.setDefaultBridgeType = vm.envOr("LZ_ROTATE_SET_DEFAULT_BRIDGE", cfg.setDefaultBridgeType);
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _parseBytes32OrZero(string memory value) internal returns (bytes32) {
        if (bytes(value).length == 0) return bytes32(0);
        return vm.parseBytes32(value);
    }

    function _parseBytesOrEmpty(string memory value) internal returns (bytes memory) {
        if (bytes(value).length == 0) return bytes("");
        return vm.parseBytes(value);
    }
}
