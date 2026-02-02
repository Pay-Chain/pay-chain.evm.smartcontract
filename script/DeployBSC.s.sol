// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBSC is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");
        
        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BSC_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BSC_HYPERBRIDGE_HOST", address(0)),
            uniswapUniversalRouter: vm.envOr("BSC_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BSC_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BSC_USDC", address(0)), 
            feeRecipient: feeRecipient
        });

        console.log("Deploying to BSC...");
        deploySystem(config);
    }
}
