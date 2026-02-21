// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployPolygon is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("POLYGON_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("POLYGON_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr(
                "POLYGON_LAYERZERO_ENDPOINT_V2",
                address(0)
            ),
            uniswapUniversalRouter: vm.envOr(
                "POLYGON_UNIVERSAL_ROUTER",
                address(0)
            ),
            uniswapPoolManager: vm.envOr("POLYGON_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("POLYGON_USDC", address(0)), // Default bridge token
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr(
                "POLYGON_ENABLE_SOURCE_SIDE_SWAP",
                vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false)
            )
        });

        console.log("Deploying to Polygon...");
        (, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Register additional tokens in Registry
        address usdc = config.bridgeToken; // Already registered in deploySystem
        address idrt = vm.envOr("POLYGON_IDRT", address(0));
        address usdt = vm.envOr("POLYGON_USDT", address(0));
        address weth = vm.envOr("POLYGON_WETH", address(0));
        address dai = vm.envOr("POLYGON_DAI", address(0));

        if (idrt != address(0)) registry.setTokenSupport(idrt, true);
        if (usdt != address(0)) registry.setTokenSupport(usdt, true);
        if (weth != address(0)) registry.setTokenSupport(weth, true);
        if (dai != address(0)) registry.setTokenSupport(dai, true);

        // 2. Configure V3 Pools on Swapper
        if (usdc != address(0) && usdt != address(0)) {
            swapper.setV3Pool(usdc, usdt, 100);
            console.log("Configured USDC/USDT V3 pool");
        }
        if (usdc != address(0) && weth != address(0)) {
            swapper.setV3Pool(usdc, weth, 500);
            console.log("Configured USDC/WETH V3 pool");
        }
        if (usdc != address(0) && dai != address(0)) {
            swapper.setV3Pool(usdc, dai, 100);
            console.log("Configured USDC/DAI V3 pool");
        }
        if (idrt != address(0) && usdc != address(0)) {
            swapper.setV3Pool(idrt, usdc, 500); // Assuming 500 based on standard Polygon pools
            console.log("Configured IDRT/USDC V3 pool");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Polygon complete.");
    }
}
