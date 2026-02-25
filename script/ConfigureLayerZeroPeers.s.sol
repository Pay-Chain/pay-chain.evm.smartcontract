// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IRouterLZCfg {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
}

interface IGatewayLZCfg {
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface ILayerZeroSenderCfg {
    function setRoute(string calldata destChainId, uint32 dstEid, bytes32 peer) external;
    function setEnforcedOptions(string calldata destChainId, bytes calldata options) external;
    function registerDelegate() external;
    function dstEids(string calldata destChainId) external view returns (uint32);
    function peers(string calldata destChainId) external view returns (bytes32);
    function enforcedOptions(string calldata destChainId) external view returns (bytes memory);
}

interface ILayerZeroReceiverCfg {
    function setPeer(uint32 _eid, bytes32 _peer) external;
    function peers(uint32 _eid) external view returns (bytes32);
}

contract ConfigureLayerZeroPeers is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address sender = vm.envAddress("LZ_CFG_SENDER");
        address receiver = vm.envAddress("LZ_CFG_RECEIVER");
        string memory destCaip2 = vm.envString("LZ_CFG_DEST_CAIP2");
        uint32 dstEid = uint32(vm.envUint("LZ_CFG_DST_EID"));
        bytes32 dstPeer = vm.parseBytes32(vm.envString("LZ_CFG_DST_PEER_BYTES32"));

        address router = vm.envOr("LZ_CFG_ROUTER", address(0));
        address gateway = vm.envOr("LZ_CFG_GATEWAY", address(0));
        uint8 defaultBridgeType = uint8(vm.envOr("LZ_CFG_DEFAULT_BRIDGE_TYPE", uint256(255)));

        string memory optionsHex = vm.envOr("LZ_CFG_OPTIONS_HEX", string(""));
        uint32 srcEid = uint32(vm.envOr("LZ_CFG_SRC_EID", uint256(0)));
        string memory srcPeerHex = vm.envOr("LZ_CFG_SRC_PEER_BYTES32", string(""));

        vm.startBroadcast(pk);

        if (router != address(0)) {
            IRouterLZCfg(router).registerAdapter(destCaip2, 2, sender);
        }
        if (gateway != address(0) && defaultBridgeType != type(uint8).max) {
            IGatewayLZCfg(gateway).setDefaultBridgeType(destCaip2, defaultBridgeType);
        }

        ILayerZeroSenderCfg(sender).setRoute(destCaip2, dstEid, dstPeer);
        if (bytes(optionsHex).length > 0) {
            ILayerZeroSenderCfg(sender).setEnforcedOptions(destCaip2, vm.parseBytes(optionsHex));
        }
        ILayerZeroSenderCfg(sender).registerDelegate();

        if (srcEid > 0 && bytes(srcPeerHex).length > 0) {
            ILayerZeroReceiverCfg(receiver).setPeer(srcEid, vm.parseBytes32(srcPeerHex));
        }

        vm.stopBroadcast();

        // Read-back verification
        uint32 rbDstEid = ILayerZeroSenderCfg(sender).dstEids(destCaip2);
        bytes32 rbDstPeer = ILayerZeroSenderCfg(sender).peers(destCaip2);
        bytes memory rbOptions = ILayerZeroSenderCfg(sender).enforcedOptions(destCaip2);

        console.log("LZ sender:", sender);
        console.log("LZ receiver:", receiver);
        console.log("destCaip2:", destCaip2);
        console.log("dstEid:", rbDstEid);
        console.logBytes32(rbDstPeer);
        console.log("optionsLen:", rbOptions.length);

        if (srcEid > 0 && bytes(srcPeerHex).length > 0) {
            bytes32 rbSrcPeer = ILayerZeroReceiverCfg(receiver).peers(srcEid);
            console.log("srcEid:", srcEid);
            console.logBytes32(rbSrcPeer);
        }

        if (router != address(0)) {
            address rbAdapter = IRouterLZCfg(router).getAdapter(destCaip2, 2);
            console.log("router adapter type2:", rbAdapter);
        }
        if (gateway != address(0) && defaultBridgeType != type(uint8).max) {
            uint8 rbBridge = IGatewayLZCfg(gateway).defaultBridgeTypes(destCaip2);
            console.log("gateway default bridge:", rbBridge);
        }
    }
}
