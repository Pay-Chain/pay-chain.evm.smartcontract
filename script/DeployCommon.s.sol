// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/PayChainRouter.sol";
import "../src/PayChainGateway.sol";
import "../src/TokenRegistry.sol";
import "../src/TokenSwapper.sol";
import "../src/integrations/ccip/CCIPSender.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "../src/integrations/layerzero/LayerZeroSenderAdapter.sol";
import "../src/integrations/layerzero/LayerZeroReceiverAdapter.sol";

interface IHyperbridgeCfgCommon {
    function setStateMachineId(string calldata chainId, bytes calldata stateMachineId) external;
    function setDestinationContract(string calldata chainId, bytes calldata destination) external;
}

interface ICCIPCfgCommon {
    function setChainSelector(string calldata chainId, uint64 selector) external;
    function setDestinationAdapter(string calldata chainId, bytes calldata adapter) external;
    function setDestinationGasLimit(string calldata chainId, uint256 gasLimit) external;
    function setDestinationFeeToken(string calldata chainId, address feeToken) external;
    function setDestinationExtraArgs(string calldata chainId, bytes calldata extraArgs) external;
}

interface ICCIPReceiverCfgCommon {
    function setTrustedSender(uint64 chainSelector, bytes calldata sender) external;
    function setSourceChainAllowed(uint64 chainSelector, bool allowed) external;
}

interface ILayerZeroCfgCommon {
    function setRoute(string calldata destChainId, uint32 dstEid, bytes32 peer) external;
    function setEnforcedOptions(string calldata destChainId, bytes calldata options) external;
    function registerDelegate() external;
}

interface ILayerZeroReceiverCfgCommon {
    function setPeer(uint32 _eid, bytes32 _peer) external;
}

abstract contract DeployCommon is Script {
    struct RouteBootstrapConfig {
        bool enabled;
        string destCaip2;
        uint8 defaultBridgeType;

        bytes hbStateMachineId;
        bytes hbDestinationContract;

        uint64 ccipChainSelector;
        bytes ccipDestinationAdapter;
        uint256 ccipGasLimit;
        address ccipFeeToken;
        bytes ccipExtraArgs;
        uint64 ccipSourceChainSelector;
        bytes ccipTrustedSender;
        bool ccipSourceChainAllowed;

        uint32 lzDstEid;
        bytes32 lzDstPeer;
        bytes lzOptions;
        uint32 lzSrcEid;
        bytes32 lzSrcPeer;
    }

    struct DeploymentConfig {
        address ccipRouter;
        address hyperbridgeHost;
        address layerZeroEndpointV2;
        address uniswapUniversalRouter;
        address uniswapPoolManager;
        address bridgeToken;
        address feeRecipient; // Not strictly deployment config but needed
        bool enableSourceSideSwap;
    }

    function deploySystem(
        DeploymentConfig memory config
    ) internal returns (
        PayChainGateway gateway_,
        PayChainRouter router_,
        TokenRegistry registry_,
        TokenSwapper swapper_
    ) {
        RouteBootstrapConfig memory noRoute;
        return deploySystem(config, noRoute);
    }

    function deploySystem(
        DeploymentConfig memory config,
        RouteBootstrapConfig memory routeConfig
    ) internal returns (
        PayChainGateway gateway_, 
        PayChainRouter router_, 
        TokenRegistry registry_,
        TokenSwapper swapper_
    ) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Components
        registry_ = new TokenRegistry();
        console.log("TokenRegistry deployed at:", address(registry_));

        // Validation: Mainnet requires a real token address
        require(config.bridgeToken != address(0), "DEPLOYMENT ERROR: Bridge Token (BASE_USDC) must be set in .env");



        PayChainVault vault = new PayChainVault();
        console.log("PayChainVault deployed at:", address(vault));

        PayChainRouter routerInstance = new PayChainRouter();
        router_ = routerInstance;
        console.log("PayChainRouter deployed at:", address(router_));

        // 2. Deploy Gateway
        gateway_ = new PayChainGateway(
            address(vault),
            address(router_),
            address(registry_),
            config.feeRecipient
        );
        console.log("PayChainGateway deployed at:", address(gateway_));

        // 3. Deploy Swapper
        swapper_ = new TokenSwapper(
            config.uniswapUniversalRouter,
            config.uniswapPoolManager,
            config.bridgeToken
        );
        swapper_.setVault(address(vault));
        console.log("TokenSwapper deployed at:", address(swapper_));

        // 4. Set Swapper in Gateway
        gateway_.setSwapper(address(swapper_));
        gateway_.setEnableSourceSideSwap(config.enableSourceSideSwap);

        // 5. Authorize Gateway on Swapper
        swapper_.setAuthorizedCaller(address(gateway_), true);
        console.log("Gateway authorized on Swapper.");

        // 6. Deploy Adapters (Only if addresses provided)
        address ccipSenderAddr = address(0);
        address ccipReceiverAddr = address(0);
        address lzSenderAddr = address(0);
        address lzReceiverAddr = address(0);
        address hbSenderAddr = address(0);
        if (config.ccipRouter != address(0)) {
            CCIPSender ccipSender = new CCIPSender(address(vault), config.ccipRouter);
            console.log("CCIPSender deployed at:", address(ccipSender));
            ccipSenderAddr = address(ccipSender);
            ccipSender.setAuthorizedCaller(address(router_), true);
            console.log("CCIPSender authorized caller (router):", address(router_));
            
            CCIPReceiverAdapter ccipReceiver = new CCIPReceiverAdapter(config.ccipRouter, address(gateway_));
            console.log("CCIPReceiverAdapter deployed at:", address(ccipReceiver));
            ccipReceiverAddr = address(ccipReceiver);
            ccipReceiver.setSwapper(address(swapper_));
            
            vault.setAuthorizedSpender(address(ccipSender), true);
            vault.setAuthorizedSpender(address(ccipReceiver), true);
            gateway_.setAuthorizedAdapter(address(ccipReceiver), true);
            swapper_.setAuthorizedCaller(address(ccipReceiver), true);
            
            // Note: Register adapter in Router manually or here if chain IDs known
        }

        if (config.hyperbridgeHost != address(0)) {
            HyperbridgeSender hyperbridgeSender = new HyperbridgeSender(
                address(vault),
                config.hyperbridgeHost,
                address(gateway_),
                address(router_)
            );
            console.log("HyperbridgeSender deployed at:", address(hyperbridgeSender));
            hbSenderAddr = address(hyperbridgeSender);

            HyperbridgeReceiver hyperbridgeReceiver = new HyperbridgeReceiver(config.hyperbridgeHost, address(gateway_), address(vault));
            console.log("HyperbridgeReceiver deployed at:", address(hyperbridgeReceiver));
            hyperbridgeReceiver.setSwapper(address(swapper_));
            
            vault.setAuthorizedSpender(address(hyperbridgeSender), true);
            vault.setAuthorizedSpender(address(hyperbridgeReceiver), true);
            gateway_.setAuthorizedAdapter(address(hyperbridgeReceiver), true);
            swapper_.setAuthorizedCaller(address(hyperbridgeReceiver), true);
        }

        if (config.layerZeroEndpointV2 != address(0)) {
            LayerZeroSenderAdapter lzSender = new LayerZeroSenderAdapter(config.layerZeroEndpointV2, address(router_));
            console.log("LayerZeroSenderAdapter deployed at:", address(lzSender));
            lzSenderAddr = address(lzSender);
            lzSender.registerDelegate();

            LayerZeroReceiverAdapter lzReceiver = new LayerZeroReceiverAdapter(
                config.layerZeroEndpointV2,
                address(gateway_),
                address(vault)
            );
            console.log("LayerZeroReceiverAdapter deployed at:", address(lzReceiver));
            lzReceiverAddr = address(lzReceiver);
            lzReceiver.setSwapper(address(swapper_));

            vault.setAuthorizedSpender(address(lzSender), true);
            vault.setAuthorizedSpender(address(lzReceiver), true);
            gateway_.setAuthorizedAdapter(address(lzReceiver), true);
            swapper_.setAuthorizedCaller(address(lzReceiver), true);
        }

        // 6. Configure Authorizations
        vault.setAuthorizedSpender(address(gateway_), true);
        vault.setAuthorizedSpender(address(swapper_), true);
        
        console.log("Vault authorizations set.");

        // 7. Final Configuration
        // Init: Register the bridge token as supported
        registry_.setTokenSupport(config.bridgeToken, true);
        console.log("Registered bridge token as supported:", config.bridgeToken);

        // 8. Optional route registration/configuration in common deploy (script-driven)
        // Chain-specific script provides values, DeployCommon only executes uniform wiring.
        if (routeConfig.enabled && bytes(routeConfig.destCaip2).length > 0) {
            if (hbSenderAddr != address(0)) {
                router_.registerAdapter(routeConfig.destCaip2, 0, hbSenderAddr);
                if (routeConfig.hbStateMachineId.length > 0) {
                    IHyperbridgeCfgCommon(hbSenderAddr).setStateMachineId(routeConfig.destCaip2, routeConfig.hbStateMachineId);
                }
                if (routeConfig.hbDestinationContract.length > 0) {
                    IHyperbridgeCfgCommon(hbSenderAddr).setDestinationContract(routeConfig.destCaip2, routeConfig.hbDestinationContract);
                }
            }

            if (ccipSenderAddr != address(0)) {
                router_.registerAdapter(routeConfig.destCaip2, 1, ccipSenderAddr);
                if (routeConfig.ccipChainSelector > 0) {
                    ICCIPCfgCommon(ccipSenderAddr).setChainSelector(routeConfig.destCaip2, routeConfig.ccipChainSelector);
                }
                if (routeConfig.ccipDestinationAdapter.length > 0) {
                    ICCIPCfgCommon(ccipSenderAddr).setDestinationAdapter(routeConfig.destCaip2, routeConfig.ccipDestinationAdapter);
                }
                if (routeConfig.ccipGasLimit > 0) {
                    ICCIPCfgCommon(ccipSenderAddr).setDestinationGasLimit(routeConfig.destCaip2, routeConfig.ccipGasLimit);
                }
                if (routeConfig.ccipFeeToken != address(0)) {
                    ICCIPCfgCommon(ccipSenderAddr).setDestinationFeeToken(routeConfig.destCaip2, routeConfig.ccipFeeToken);
                }
                if (routeConfig.ccipExtraArgs.length > 0) {
                    ICCIPCfgCommon(ccipSenderAddr).setDestinationExtraArgs(routeConfig.destCaip2, routeConfig.ccipExtraArgs);
                }
            }

            if (ccipReceiverAddr != address(0) && routeConfig.ccipSourceChainSelector > 0) {
                if (routeConfig.ccipTrustedSender.length > 0) {
                    ICCIPReceiverCfgCommon(ccipReceiverAddr).setTrustedSender(
                        routeConfig.ccipSourceChainSelector,
                        routeConfig.ccipTrustedSender
                    );
                } else if (routeConfig.ccipSourceChainAllowed) {
                    ICCIPReceiverCfgCommon(ccipReceiverAddr).setSourceChainAllowed(
                        routeConfig.ccipSourceChainSelector,
                        true
                    );
                }
            }

            if (lzSenderAddr != address(0)) {
                router_.registerAdapter(routeConfig.destCaip2, 2, lzSenderAddr);
                if (routeConfig.lzDstEid > 0 && routeConfig.lzDstPeer != bytes32(0)) {
                    ILayerZeroCfgCommon(lzSenderAddr).setRoute(routeConfig.destCaip2, routeConfig.lzDstEid, routeConfig.lzDstPeer);
                }
                if (routeConfig.lzOptions.length > 0) {
                    ILayerZeroCfgCommon(lzSenderAddr).setEnforcedOptions(routeConfig.destCaip2, routeConfig.lzOptions);
                }
                ILayerZeroCfgCommon(lzSenderAddr).registerDelegate();

                if (routeConfig.lzSrcEid > 0 && routeConfig.lzSrcPeer != bytes32(0) && lzReceiverAddr != address(0)) {
                    ILayerZeroReceiverCfgCommon(lzReceiverAddr).setPeer(routeConfig.lzSrcEid, routeConfig.lzSrcPeer);
                }
            }

            gateway_.setDefaultBridgeType(routeConfig.destCaip2, routeConfig.defaultBridgeType);
            console.log("Configured default bridge type for route:", routeConfig.defaultBridgeType);
        }

        vm.stopBroadcast();
        
        return (gateway_, router_, registry_, swapper_);
    }
}
