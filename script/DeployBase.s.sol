// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBase is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BASE_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BASE_HYPERBRIDGE_HOST", address(0)),
            uniswapUniversalRouter: vm.envOr("BASE_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BASE_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BASE_USDC", address(0)), // Default bridge token
            feeRecipient: feeRecipient
        });

        console.log("Deploying to Base...");
        deploySystem(config);
    }
}
