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

/**
 * @title DeployGateway
 * @notice Deployment script for Modular PayChain Architecture
 */
contract DeployGateway is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        // External Dependencies (Env or Default)
        address ccipRouterAddr = vm.envOr("CCIP_ROUTER_ADDRESS", address(0)); 
        address hyperbridgeHostAddr = vm.envOr("HYPERBRIDGE_HOST_ADDRESS", address(0));
        address uniswapUniversalRouter = vm.envOr("UNISWAP_ROUTER", address(0));
        address uniswapPoolManager = vm.envOr("UNISWAP_POOL_MANAGER", address(0));
        address bridgeToken = vm.envOr("BRIDGE_TOKEN", address(0));

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
            feeRecipient
        );
        console.log("PayChainGateway deployed at:", address(gateway));

        // 3. Deploy Swapper
        TokenSwapper swapper = new TokenSwapper(
            uniswapUniversalRouter,
            uniswapPoolManager,
            bridgeToken
        );
        swapper.setVault(address(vault));
        console.log("TokenSwapper deployed at:", address(swapper));

        // 4. Set Swapper in Gateway
        gateway.setSwapper(address(swapper));

        // 5. Deploy Adapters
        // CCIP
        CCIPSender ccipSender = new CCIPSender(address(vault), ccipRouterAddr);
        console.log("CCIPSender deployed at:", address(ccipSender));
        
        CCIPReceiverAdapter ccipReceiver = new CCIPReceiverAdapter(ccipRouterAddr, address(gateway));
        console.log("CCIPReceiverAdapter deployed at:", address(ccipReceiver));

        // Hyperbridge
        HyperbridgeSender hyperbridgeSender = new HyperbridgeSender(address(vault), hyperbridgeHostAddr);
        console.log("HyperbridgeSender deployed at:", address(hyperbridgeSender));

        HyperbridgeReceiver hyperbridgeReceiver = new HyperbridgeReceiver(hyperbridgeHostAddr, address(gateway), address(vault));
        console.log("HyperbridgeReceiver deployed at:", address(hyperbridgeReceiver));

        // 6. Configure Authorizations & Routing
        
        // Vault Authorizations
        vault.setAuthorizedSpender(address(gateway), true);
        vault.setAuthorizedSpender(address(router), true); // Router needs to move funds? Router delegates to Adapter.
        // If Router delegates: Adapter needs to move funds.
        vault.setAuthorizedSpender(address(ccipSender), true); 
        vault.setAuthorizedSpender(address(hyperbridgeSender), true);
        vault.setAuthorizedSpender(address(swapper), true);
        vault.setAuthorizedSpender(address(hyperbridgeReceiver), true); // Receiver pushes funds used for payout
        
        console.log("Vault authorizations set.");

        // Router Registration (Example)
        // router.registerAdapter("CHAIN_ID", 0, address(ccipSender));
        // router.registerAdapter("CHAIN_ID", 1, address(hyperbridgeSender));

        // Gateway Configuration
        // gateway.setDefaultBridgeType("CHAIN_ID", 0);

        vm.stopBroadcast();
    }
}
