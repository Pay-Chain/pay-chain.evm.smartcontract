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

abstract contract DeployCommon is Script {
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

    function deploySystem(DeploymentConfig memory config) internal returns (
        PayChainGateway gateway_, 
        PayChainRouter router_, 
        TokenRegistry registry_
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
        TokenSwapper swapper = new TokenSwapper(
            config.uniswapUniversalRouter,
            config.uniswapPoolManager,
            config.bridgeToken
        );
        swapper.setVault(address(vault));
        console.log("TokenSwapper deployed at:", address(swapper));

        // 4. Set Swapper in Gateway
        gateway_.setSwapper(address(swapper));
        gateway_.setEnableSourceSideSwap(config.enableSourceSideSwap);

        // 5. Deploy Adapters (Only if addresses provided)
        if (config.ccipRouter != address(0)) {
            CCIPSender ccipSender = new CCIPSender(address(vault), config.ccipRouter);
            console.log("CCIPSender deployed at:", address(ccipSender));
            
            CCIPReceiverAdapter ccipReceiver = new CCIPReceiverAdapter(config.ccipRouter, address(gateway_));
            console.log("CCIPReceiverAdapter deployed at:", address(ccipReceiver));
            ccipReceiver.setSwapper(address(swapper));
            
            vault.setAuthorizedSpender(address(ccipSender), true);
            vault.setAuthorizedSpender(address(ccipReceiver), true);
            gateway_.setAuthorizedAdapter(address(ccipReceiver), true);
            
            // Note: Register adapter in Router manually or here if chain IDs known
        }

        if (config.hyperbridgeHost != address(0)) {
            HyperbridgeSender hyperbridgeSender = new HyperbridgeSender(address(vault), config.hyperbridgeHost, address(gateway_));
            console.log("HyperbridgeSender deployed at:", address(hyperbridgeSender));

            HyperbridgeReceiver hyperbridgeReceiver = new HyperbridgeReceiver(config.hyperbridgeHost, address(gateway_), address(vault));
            console.log("HyperbridgeReceiver deployed at:", address(hyperbridgeReceiver));
            hyperbridgeReceiver.setSwapper(address(swapper));
            
            vault.setAuthorizedSpender(address(hyperbridgeSender), true);
            vault.setAuthorizedSpender(address(hyperbridgeReceiver), true);
            gateway_.setAuthorizedAdapter(address(hyperbridgeReceiver), true);
        }

        if (config.layerZeroEndpointV2 != address(0)) {
            LayerZeroSenderAdapter lzSender = new LayerZeroSenderAdapter(config.layerZeroEndpointV2);
            console.log("LayerZeroSenderAdapter deployed at:", address(lzSender));

            LayerZeroReceiverAdapter lzReceiver = new LayerZeroReceiverAdapter(
                config.layerZeroEndpointV2,
                address(gateway_),
                address(vault)
            );
            console.log("LayerZeroReceiverAdapter deployed at:", address(lzReceiver));
            lzReceiver.setSwapper(address(swapper));

            vault.setAuthorizedSpender(address(lzSender), true);
            vault.setAuthorizedSpender(address(lzReceiver), true);
            gateway_.setAuthorizedAdapter(address(lzReceiver), true);
        }

        // 6. Configure Authorizations
        vault.setAuthorizedSpender(address(gateway_), true);
        vault.setAuthorizedSpender(address(swapper), true);
        
        console.log("Vault authorizations set.");

        // 7. Final Configuration
        // Init: Register the bridge token as supported
        registry_.setTokenSupport(config.bridgeToken, true);
        console.log("Registered bridge token as supported:", config.bridgeToken);

        vm.stopBroadcast();
        
        return (gateway_, router_, registry_);
    }
}
