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
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("BSC_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to BSC...");
        (,, TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Register additional tokens in Registry
        address usdc = config.bridgeToken; // Already registered in deploySystem
        address usdt = vm.envOr("BSC_USDT", address(0));
        address wbnb = vm.envOr("BSC_WBNB", address(0));
        address idrx = vm.envOr("BSC_IDRX", address(0));

        if (usdt != address(0)) registry.setTokenSupport(usdt, true);
        if (wbnb != address(0)) registry.setTokenSupport(wbnb, true);
        if (idrx != address(0)) registry.setTokenSupport(idrx, true);

        // 2. Configure V3 Pools on Swapper
        if (usdc != address(0) && usdt != address(0)) {
            swapper.setV3Pool(usdc, usdt, 100);
            console.log("Configured USDC/USDT V3 pool");
        }
        if (usdc != address(0) && wbnb != address(0)) {
            swapper.setV3Pool(usdc, wbnb, 500);
            console.log("Configured USDC/WBNB V3 pool");
        }
        if (usdc != address(0) && idrx != address(0)) {
            swapper.setV3Pool(usdc, idrx, 100);
            console.log("Configured USDC/IDRX V3 pool");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on BSC complete.");
    }
}
