// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/PayChainRouter.sol";
import "../src/TokenSwapper.sol";

contract DeployBaseFixes is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // --- Addresses on Base ---
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address gateway = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
        address routerAddress = 0x304185d7B5Eb9790Dc78805D2095612F7a43A291;
        address tokenSwapper = 0x8fd8Df03D50514f9386a0adE7E6aEE4003399933;
        address host = 0x6FFe92e4d7a9D589549644544780e6725E84b248; 
        
        address uniswapV3Router = 0x2626664c2603336E57B271c5C0b26F421741e481;
        address uniswapV2Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

        // 1. Fix TokenSwapper (Base -> Base #1002 Fix)
        TokenSwapper(tokenSwapper).setV3Router(uniswapV3Router);
        console.log("Updated TokenSwapper V3 Router to:", uniswapV3Router);

        // 2. Fix HyperbridgeSender (Base -> Polygon EXCESSIVE_INPUT_AMOUNT Fix)
        
        // Deploy new HyperbridgeSender
        HyperbridgeSender newSender = new HyperbridgeSender(vault, host, gateway);
        console.log("New HyperbridgeSender deployed at:", address(newSender));

        // Configure Swap Router override (Use V2 Router for fee quotes/buffer)
        newSender.setSwapRouter(uniswapV2Router);
        console.log("Set Swap Router to V2:", uniswapV2Router);

        // Configure Polygon destination
        // State Machine ID: EVM-137 (0x45564d2d313337)
        string memory chainId = "eip155:137";
        bytes memory smId = hex"45564d2d313337";
        bytes memory dest = abi.encodePacked(address(0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD));
        
        newSender.setStateMachineId(chainId, smId);
        newSender.setDestinationContract(chainId, dest);
        newSender.setDefaultTimeout(3600);
        
        console.log("Configured Hyperbridge Sender for chain:", chainId);

        // Update PayChainRouter to use new sender for Polygon
        // AdapterType 0 for Hyperbridge
        PayChainRouter(routerAddress).registerAdapter(chainId, 0, address(newSender));
        console.log("Updated PayChainRouter adapter for chain:", chainId);

        vm.stopBroadcast();
    }
}
