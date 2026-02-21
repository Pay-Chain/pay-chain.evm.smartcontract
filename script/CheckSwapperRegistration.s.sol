// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/PayChainGateway.sol";

contract CheckSwapperRegistration is Script {
    // Source of Truth from CHAIN_BASE.md
    address constant VAULT = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
    address constant GATEWAY = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
    address constant NEW_SWAPPER = 0x96562f9A774AA5dc1B3E251Df3B78EBaE682B984;

    function run() external {
        console.log("Checking Swapper Registration on Base...");
        console.log("Vault:", VAULT);
        console.log("Gateway:", GATEWAY);
        console.log("New Swapper:", NEW_SWAPPER);

        // 1. Check Vault Authorization
        PayChainVault vault = PayChainVault(VAULT);
        bool isAuthorized = vault.authorizedSpenders(NEW_SWAPPER);
        console.log("Is Swapper authorized in Vault:", isAuthorized);

        // 2. Check Gateway Configuration
        PayChainGateway gateway = PayChainGateway(GATEWAY);
        address currentSwapper = address(gateway.swapper());
        console.log("Current Swapper in Gateway:", currentSwapper);
        
        if (currentSwapper == NEW_SWAPPER) {
            console.log("SUCCESS: Gateway is using the new swapper.");
        } else {
            console.log("WARNING: Gateway is using a different swapper:", currentSwapper);
        }

        if (isAuthorized) {
            console.log("SUCCESS: New swapper is authorized in Vault.");
        } else {
            console.log("WARNING: New swapper is NOT authorized in Vault.");
        }
    }
}
