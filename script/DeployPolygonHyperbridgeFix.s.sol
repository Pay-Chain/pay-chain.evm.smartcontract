// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/PayChainRouter.sol";

contract DeployPolygonHyperbridgeFix is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address vault = 0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c;
        address host = 0xD8d3db17C1dF65b301D45C84405CcAC1395C559a;
        address gateway = 0x7a4f3b606D90e72555A36cB370531638fad19Bf8;
        address routerAddress = 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4;
        address quickSwapRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

        // 1. Deploy new HyperbridgeSender
        HyperbridgeSender newSender = new HyperbridgeSender(vault, host, gateway);
        console.log("New HyperbridgeSender deployed at:", address(newSender));

        // 2. Configure Swap Router override
        newSender.setSwapRouter(quickSwapRouter);
        console.log("Set Swap Router to QuickSwap:", quickSwapRouter);

        // 3. Configure Base destination
        // State Machine ID: EVM-8453 (0x45564d2d38343533)
        // Dest Contract: 0xf4348E2e6AF1860ea9Ab0F3854149582b608b5e2
        
        string memory chainId = "eip155:8453";
        bytes memory smId = hex"45564d2d38343533";
        bytes memory dest = abi.encodePacked(address(0xf4348E2e6AF1860ea9Ab0F3854149582b608b5e2));
        
        newSender.setStateMachineId(chainId, smId);
        newSender.setDestinationContract(chainId, dest);
        newSender.setDefaultTimeout(3600);
        
        console.log("Configured Hyperbridge Sender for chain:", chainId);

        // 4. Update PayChainRouter
        // AdapterType 0 for Hyperbridge
        PayChainRouter(routerAddress).registerAdapter(chainId, 0, address(newSender));
        console.log("Updated PayChainRouter adapter for chain:", chainId);

        vm.stopBroadcast();
    }
}
