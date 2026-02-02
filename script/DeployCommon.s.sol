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

abstract contract DeployCommon is Script {
    struct DeploymentConfig {
        address ccipRouter;
        address hyperbridgeHost;
        address uniswapUniversalRouter;
        address uniswapPoolManager;
        address bridgeToken;
        address feeRecipient; // Not strictly deployment config but needed
    }

    function deploySystem(DeploymentConfig memory config) internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Components
        TokenRegistry registry = new TokenRegistry();
        console.log("TokenRegistry deployed at:", address(registry));

        PayChainVault vault = new PayChainVault();
        console.log("PayChainVault deployed at:", address(vault));

        PayChainRouter router = new PayChainRouter();
        console.log("PayChainRouter deployed at:", address(router));

        // 2. Deploy Gateway
        PayChainGateway gateway = new PayChainGateway(
            address(vault),
            address(router),
            address(registry),
            config.feeRecipient
        );
        console.log("PayChainGateway deployed at:", address(gateway));

        // 3. Deploy Swapper
        TokenSwapper swapper = new TokenSwapper(
            config.uniswapUniversalRouter,
            config.uniswapPoolManager,
            config.bridgeToken
        );
        swapper.setVault(address(vault));
        console.log("TokenSwapper deployed at:", address(swapper));

        // 4. Set Swapper in Gateway
        gateway.setSwapper(address(swapper));

        // 5. Deploy Adapters (Only if addresses provided)
        if (config.ccipRouter != address(0)) {
            CCIPSender ccipSender = new CCIPSender(address(vault), config.ccipRouter);
            console.log("CCIPSender deployed at:", address(ccipSender));
            
            CCIPReceiverAdapter ccipReceiver = new CCIPReceiverAdapter(config.ccipRouter, address(gateway));
            console.log("CCIPReceiverAdapter deployed at:", address(ccipReceiver));
            
            vault.setAuthorizedSpender(address(ccipSender), true);
            vault.setAuthorizedSpender(address(ccipReceiver), true);
            
            // Note: Register adapter in Router manually or here if chain IDs known
        }

        if (config.hyperbridgeHost != address(0)) {
            HyperbridgeSender hyperbridgeSender = new HyperbridgeSender(address(vault), config.hyperbridgeHost);
            console.log("HyperbridgeSender deployed at:", address(hyperbridgeSender));

            HyperbridgeReceiver hyperbridgeReceiver = new HyperbridgeReceiver(config.hyperbridgeHost, address(gateway), address(vault));
            console.log("HyperbridgeReceiver deployed at:", address(hyperbridgeReceiver));
            
            vault.setAuthorizedSpender(address(hyperbridgeSender), true);
            vault.setAuthorizedSpender(address(hyperbridgeReceiver), true);
        }

        // 6. Configure Authorizations
        vault.setAuthorizedSpender(address(gateway), true);
        vault.setAuthorizedSpender(address(swapper), true);
        
        console.log("Vault authorizations set.");

        vm.stopBroadcast();
    }
}
