// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainCCIP.sol";
import "../src/PayChainHyperbridge.sol";

/**
 * @title DeployScript
 * @notice Deployment scripts for PayChain contracts
 * @dev Deploy with: forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
 */
contract DeployCCIP is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ccipRouter = vm.envAddress("CCIP_ROUTER_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        PayChainCCIP payChain = new PayChainCCIP(ccipRouter, feeRecipient);

        console.log("PayChainCCIP deployed at:", address(payChain));

        vm.stopBroadcast();
    }
}

contract DeployHyperbridge is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address hyperbridgeHost = vm.envAddress("HYPERBRIDGE_HOST_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        PayChainHyperbridge payChain = new PayChainHyperbridge(
            hyperbridgeHost,
            feeRecipient
        );

        console.log("PayChainHyperbridge deployed at:", address(payChain));

        vm.stopBroadcast();
    }
}
