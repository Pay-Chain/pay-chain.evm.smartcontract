// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployArbitrum is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("ARBITRUM_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("ARBITRUM_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("ARBITRUM_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("ARBITRUM_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("ARBITRUM_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("ARBITRUM_USDC", address(0)), 
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("ARBITRUM_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to Arbitrum...");
        (,, TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Register additional tokens in Registry
        address usdc = config.bridgeToken; // Already registered in deploySystem
        address usdt = vm.envOr("ARBITRUM_USDT", address(0));
        address usd0 = vm.envOr("ARBITRUM_USDTO", address(0));
        address weth = vm.envOr("ARBITRUM_WETH", address(0));

        if (usdt != address(0)) registry.setTokenSupport(usdt, true);
        if (usd0 != address(0)) registry.setTokenSupport(usd0, true);
        if (weth != address(0)) registry.setTokenSupport(weth, true);

        // 2. Configure V3 Pools on Swapper
        if (usdc != address(0) && usdt != address(0)) {
            swapper.setV3Pool(usdc, usdt, 100);
            console.log("Configured USDC/USDT V3 pool");
        }
        if (usdc != address(0) && weth != address(0)) {
            swapper.setV3Pool(usdc, weth, 500);
            console.log("Configured USDC/WETH V3 pool");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Arbitrum complete.");
    }
}
