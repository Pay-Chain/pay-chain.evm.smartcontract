// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";

contract AuthorizeBaseAdapters is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Base Mainnet Addresses - Lowercase to bypass checksum validation
        address payable vaultAddress = payable(0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7);
        address gateway = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
        address hyperbridgeSender = 0x58C67aCc6B225e6bFdEedb1edd2E018dfc90432e;
        address hyperbridgeReceiver = 0xf4348E2e6AF1860ea9Ab0F3854149582b608b5e2;
        address ccipSender = 0xc60b6f567562c756bE5E29f31318bb7793852850;
        address lzSender = 0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478;
        address swapper = 0xa9c076CDa14107a31e654EeFCb99109c5eEC4dC3;

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
        
        console2.log("Authorizing LZSender:", lzSender);
        vault.setAuthorizedSpender(lzSender, true);
        
        console2.log("Authorizing Swapper:", swapper);
        vault.setAuthorizedSpender(swapper, true);

        vm.stopBroadcast();
    }
}
