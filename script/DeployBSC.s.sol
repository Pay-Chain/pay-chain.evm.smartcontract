// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBSC is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BSC_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BSC_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("BSC_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("BSC_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BSC_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BSC_USDC", address(0)), 
            feeRecipient: feeRecipient
        });

        console.log("Deploying to BSC...");
        (,, TokenRegistry registry) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Register additional tokens
        address usdc = vm.envOr("BSC_USDC", address(0));
        if (usdc != address(0)) {
            registry.setTokenSupport(usdc, true);
            console.log("Registered BSC_USDC:", usdc);
        }

        address usdt = vm.envOr("BSC_USDT", address(0));
        if (usdt != address(0)) {
            registry.setTokenSupport(usdt, true);
            console.log("Registered BSC_USDT:", usdt);
        }

        address wbnb = vm.envOr("BSC_WBNB", address(0));
        if (wbnb != address(0)) {
            registry.setTokenSupport(wbnb, true);
            console.log("Registered BSC_WBNB:", wbnb);
        }

        address idrx = vm.envOr("BSC_IDRX", address(0));
        if (idrx != address(0)) {
            registry.setTokenSupport(idrx, true);
            console.log("Registered BSC_IDRX:", idrx);
        }

        vm.stopBroadcast();
    }
}
