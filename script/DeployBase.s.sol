// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBase is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BASE_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BASE_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("BASE_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("BASE_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BASE_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BASE_USDC", address(0)), // Default bridge token
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("BASE_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to Base...");
        (,, TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Register additional tokens in Registry
        address usdc = config.bridgeToken; // Already registered in deploySystem
        address usde = vm.envOr("BASE_USDE", address(0));
        address weth = vm.envOr("BASE_WETH", address(0));
        address cbbtc = vm.envOr("BASE_CBBTC", address(0));
        address wbtc = vm.envOr("BASE_WBTC", address(0));
        address idrx = vm.envOr("BASE_IDRX", address(0));
        address cbeth = vm.envOr("BASE_CBETH", address(0));

        if (usde != address(0)) registry.setTokenSupport(usde, true);
        if (weth != address(0)) registry.setTokenSupport(weth, true);
        if (cbbtc != address(0)) registry.setTokenSupport(cbbtc, true);
        if (wbtc != address(0)) registry.setTokenSupport(wbtc, true);
        if (idrx != address(0)) registry.setTokenSupport(idrx, true);
        if (cbeth != address(0)) registry.setTokenSupport(cbeth, true);

        // 2. Configure V3 Pools on Swapper
        if (idrx != address(0) && usdc != address(0)) {
            swapper.setV3Pool(idrx, usdc, 100);
            console.log("Configured IDRX/USDC V3 pool");
        }
        if (usdc != address(0) && wbtc != address(0)) {
            swapper.setV3Pool(usdc, wbtc, 100);
            console.log("Configured USDC/WBTC V3 pool");
        }
        if (usdc != address(0) && weth != address(0)) {
            swapper.setV3Pool(usdc, weth, 100);
            console.log("Configured USDC/WETH V3 pool");
        }
        if (usdc != address(0) && cbbtc != address(0)) {
            swapper.setV3Pool(usdc, cbbtc, 500);
            console.log("Configured USDC/cbBTC V3 pool");
        }
        if (usdc != address(0) && usde != address(0)) {
            swapper.setV3Pool(usdc, usde, 100);
            console.log("Configured USDC/USDe V3 pool");
        }
        if (usdc != address(0) && cbeth != address(0)) {
            swapper.setV3Pool(usdc, cbeth, 500);
            console.log("Configured USDC/cbETH V3 pool");
        }

        // 3. Configure Multi-hop Paths
        if (wbtc != address(0) && idrx != address(0)) {
            address[] memory pathWbtcIdrx = new address[](3);
            pathWbtcIdrx[0] = wbtc;
            pathWbtcIdrx[1] = usdc;
            pathWbtcIdrx[2] = idrx;
            swapper.setMultiHopPath(wbtc, idrx, pathWbtcIdrx);
            console.log("Configured WBTC -> USDC -> IDRX");
        }
        if (idrx != address(0) && weth != address(0)) {
            address[] memory pathIdrxWeth = new address[](3);
            pathIdrxWeth[0] = idrx;
            pathIdrxWeth[1] = usdc;
            pathIdrxWeth[2] = weth;
            swapper.setMultiHopPath(idrx, weth, pathIdrxWeth);
            console.log("Configured IDRX -> USDC -> WETH");
        }
        if (idrx != address(0) && usde != address(0)) {
            address[] memory pathIdrxUsde = new address[](3);
            pathIdrxUsde[0] = idrx;
            pathIdrxUsde[1] = usdc;
            pathIdrxUsde[2] = usde;
            swapper.setMultiHopPath(idrx, usde, pathIdrxUsde);
            console.log("Configured IDRX -> USDC -> USDe");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Base complete.");
    }
}
