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
            feeRecipient: feeRecipient
        });

        console.log("Deploying to Base...");
        (,, TokenRegistry registry) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Register additional tokens
        address usde = vm.envOr("BASE_USDE", address(0));
        if (usde != address(0)) {
            registry.setTokenSupport(usde, true);
            console.log("Registered BASE_USDE:", usde);
        }

        address weth = vm.envOr("BASE_WETH", address(0));
        if (weth != address(0)) {
            registry.setTokenSupport(weth, true);
            console.log("Registered BASE_WETH:", weth);
        }

        address cbeth = vm.envOr("BASE_CBETH", address(0));
        if (cbeth != address(0)) {
            registry.setTokenSupport(cbeth, true);
            console.log("Registered BASE_CBETH:", cbeth);
        }

        address cbbtc = vm.envOr("BASE_CBBTC", address(0));
        if (cbbtc != address(0)) {
            registry.setTokenSupport(cbbtc, true);
            console.log("Registered BASE_CBBTC:", cbbtc);
        }

        address wbtc = vm.envOr("BASE_WBTC", address(0));
        if (wbtc != address(0)) {
            registry.setTokenSupport(wbtc, true);
            console.log("Registered BASE_WBTC:", wbtc);
        }

        address idrx = vm.envOr("BASE_IDRX", address(0));
        if (idrx != address(0)) {
            registry.setTokenSupport(idrx, true);
            console.log("Registered BASE_IDRX:", idrx);
        }

        vm.stopBroadcast();
    }
}
