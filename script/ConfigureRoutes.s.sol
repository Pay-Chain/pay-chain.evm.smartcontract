// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

interface IRouterCfg {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
}

interface IGatewayCfg {
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
}

interface IHyperbridgeCfg {
    function setStateMachineId(string calldata chainId, bytes calldata stateMachineId) external;
    function setDestinationContract(string calldata chainId, bytes calldata destination) external;
}

interface ICCIPCfg {
    function setChainSelector(string calldata chainId, uint64 selector) external;
    function setDestinationAdapter(string calldata chainId, bytes calldata adapter) external;
    function setDestinationGasLimit(string calldata chainId, uint256 gasLimit) external;
}

interface ILayerZeroCfg {
    function setRoute(string calldata destChainId, uint32 dstEid, bytes32 peer) external;
    function setEnforcedOptions(string calldata destChainId, bytes calldata options) external;
}

contract ConfigureRoutes is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        string memory destCaip2 = vm.envString("ROUTE_DEST_CAIP2");
        uint8 defaultBridgeType = uint8(vm.envUint("ROUTE_DEFAULT_BRIDGE_TYPE"));

        address router = vm.envAddress("ROUTE_ROUTER_ADDRESS");
        address gateway = vm.envAddress("ROUTE_GATEWAY_ADDRESS");

        vm.startBroadcast(pk);

        // Register Hyperbridge adapter if provided
        address hbAdapter = vm.envOr("ROUTE_HYPERBRIDGE_ADAPTER", address(0));
        if (hbAdapter != address(0)) {
            IRouterCfg(router).registerAdapter(destCaip2, 0, hbAdapter);
            console.log("Registered Hyperbridge adapter:", hbAdapter);
        }

        // Register CCIP adapter if provided
        address ccipAdapter = vm.envOr("ROUTE_CCIP_ADAPTER", address(0));
        if (ccipAdapter != address(0)) {
            IRouterCfg(router).registerAdapter(destCaip2, 1, ccipAdapter);
            console.log("Registered CCIP adapter:", ccipAdapter);
        }

        // Register LayerZero adapter if provided
        address lzAdapter = vm.envOr("ROUTE_LAYERZERO_ADAPTER", address(0));
        if (lzAdapter != address(0)) {
            IRouterCfg(router).registerAdapter(destCaip2, 2, lzAdapter);
            console.log("Registered LayerZero adapter:", lzAdapter);
        }

        IGatewayCfg(gateway).setDefaultBridgeType(destCaip2, defaultBridgeType);
        console.log("Set default bridge type:", defaultBridgeType);

        // Hyperbridge route config
        if (hbAdapter != address(0)) {
            bytes memory smId = vm.parseBytes(vm.envString("ROUTE_HYPERBRIDGE_STATE_MACHINE_ID_HEX"));
            bytes memory dst = vm.parseBytes(vm.envString("ROUTE_HYPERBRIDGE_DEST_CONTRACT_HEX"));
            IHyperbridgeCfg(hbAdapter).setStateMachineId(destCaip2, smId);
            IHyperbridgeCfg(hbAdapter).setDestinationContract(destCaip2, dst);
            console.log("Configured Hyperbridge route");
        }

        // CCIP route config
        if (ccipAdapter != address(0)) {
            uint64 selector = uint64(vm.envUint("ROUTE_CCIP_CHAIN_SELECTOR"));
            bytes memory dstAdapter = vm.parseBytes(vm.envString("ROUTE_CCIP_DEST_ADAPTER_HEX"));
            uint256 gasLimit = vm.envOr("ROUTE_CCIP_GAS_LIMIT", uint256(200000));
            ICCIPCfg(ccipAdapter).setChainSelector(destCaip2, selector);
            ICCIPCfg(ccipAdapter).setDestinationAdapter(destCaip2, dstAdapter);
            ICCIPCfg(ccipAdapter).setDestinationGasLimit(destCaip2, gasLimit);
            console.log("Configured CCIP route");
        }

        // LayerZero route config
        if (lzAdapter != address(0)) {
            uint32 dstEid = uint32(vm.envUint("ROUTE_LAYERZERO_DST_EID"));
            bytes32 peer = vm.parseBytes32(vm.envString("ROUTE_LAYERZERO_PEER_BYTES32"));
            bytes memory opts = vm.parseBytes(vm.envOr("ROUTE_LAYERZERO_OPTIONS_HEX", string("0x")));
            ILayerZeroCfg(lzAdapter).setRoute(destCaip2, dstEid, peer);
            ILayerZeroCfg(lzAdapter).setEnforcedOptions(destCaip2, opts);
            console.log("Configured LayerZero route");
        }

        vm.stopBroadcast();
    }
}

