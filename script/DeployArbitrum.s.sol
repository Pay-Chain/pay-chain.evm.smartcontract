// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployArbitrum is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("ARBITRUM_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("ARBITRUM_HYPERBRIDGE_HOST", address(0)),
            uniswapUniversalRouter: vm.envOr("ARBITRUM_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("ARBITRUM_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("ARBITRUM_USDC", address(0)), 
            feeRecipient: feeRecipient
        });

        console.log("Deploying to Arbitrum...");
        deploySystem(config);
    }
}
