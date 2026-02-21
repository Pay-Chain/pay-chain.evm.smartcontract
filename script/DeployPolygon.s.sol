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
        (, , TokenRegistry registry) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Register additional tokens
        address idrt = vm.envOr("POLYGON_IDRT", address(0));
        if (idrt != address(0)) {
            registry.setTokenSupport(idrt, true);
            console.log("Registered POLYGON_IDRT:", idrt);
        }

        address usdt = vm.envOr("POLYGON_USDT", address(0));
        if (usdt != address(0)) {
            registry.setTokenSupport(usdt, true);
            console.log("Registered POLYGON_USDT:", usdt);
        }

        address weth = vm.envOr("POLYGON_WETH", address(0));
        if (weth != address(0)) {
            registry.setTokenSupport(weth, true);
            console.log("Registered POLYGON_WETH:", weth);
        }

        address dai = vm.envOr("POLYGON_DAI", address(0));
        if (dai != address(0)) {
            registry.setTokenSupport(dai, true);
            console.log("Registered POLYGON_DAI:", dai);
        }

        vm.stopBroadcast();
    }
}
