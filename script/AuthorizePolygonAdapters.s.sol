// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";

contract AuthorizePolygonAdapters is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Polygon Mainnet Addresses
        address payable vaultAddress = payable(0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c);
        
        address gateway = 0x7a4f3b606D90e72555A36cB370531638fad19Bf8;
        address hyperbridgeSender = 0xeC25Af21e16aD82eD7060DcC90a1D07255253e28;
        address hyperbridgeReceiver = 0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD;
        address ccipSender = 0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500;
        address swapper = 0xF043b0b91C8F5b6C2DC63897f1632D6D15e199A9;

        vm.startBroadcast(deployerPrivateKey);

        PayChainVault vault = PayChainVault(vaultAddress);
        
        console2.log("Authorizing Gateway:", gateway);
        vault.setAuthorizedSpender(gateway, true);
        
        console2.log("Authorizing HyperbridgeSender:", hyperbridgeSender);
        vault.setAuthorizedSpender(hyperbridgeSender, true);
        
        console2.log("Authorizing HyperbridgeReceiver:", hyperbridgeReceiver);
        vault.setAuthorizedSpender(hyperbridgeReceiver, true);
        
        console2.log("Authorizing CCIPSender:", ccipSender);
        vault.setAuthorizedSpender(ccipSender, true);
        
        console2.log("Authorizing Swapper:", swapper);
        vault.setAuthorizedSpender(swapper, true);

        vm.stopBroadcast();
    }
}
