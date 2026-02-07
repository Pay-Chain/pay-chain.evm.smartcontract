// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

/**
 * @title DeployGateway
 * @notice Deployment script for Modular PayChain Architecture
 */
contract DeployGateway is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        // Map generic env vars to DeploymentConfig
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("CCIP_ROUTER_ADDRESS", address(0)),
            hyperbridgeHost: vm.envOr("HYPERBRIDGE_HOST_ADDRESS", address(0)),
            uniswapUniversalRouter: vm.envOr("UNISWAP_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("UNISWAP_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BRIDGE_TOKEN", address(0)),
            feeRecipient: feeRecipient
        });

        console.log("Deploying Gateway System (Generic)...");
        deploySystem(config);
    }
}
