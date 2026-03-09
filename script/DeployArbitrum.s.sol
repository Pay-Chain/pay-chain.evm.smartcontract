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
        (, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool strict = strictTokenRegistration();

        // 1. Register tokens + decimals
        address usdc = config.bridgeToken;
        address usdt = vm.envOr("ARBITRUM_USDT", address(0));
        address usd0 = vm.envOr("ARBITRUM_USDTO", address(0));
        address weth = vm.envOr("ARBITRUM_WETH", address(0));

        uint256 usdcDec = vm.envOr("ARBITRUM_USDC_DECIMAL", uint256(0));
        uint256 usdtDec = vm.envOr("ARBITRUM_USDT_DECIMAL", uint256(0));
        uint256 usd0Dec = vm.envOr("ARBITRUM_USDTO_DECIMAL", uint256(0));
        uint256 wethDec = vm.envOr("ARBITRUM_WETH_DECIMAL", uint256(0));

        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "ARBITRUM_USDC", "ARBITRUM_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usdt, usdtDec, strict, "ARBITRUM_USDT", "ARBITRUM_USDT_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usd0, usd0Dec, strict, "ARBITRUM_USDTO", "ARBITRUM_USDTO_DECIMAL");
        registerTokenWithOptionalDecimals(registry, weth, wethDec, strict, "ARBITRUM_WETH", "ARBITRUM_WETH_DECIMAL");

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
