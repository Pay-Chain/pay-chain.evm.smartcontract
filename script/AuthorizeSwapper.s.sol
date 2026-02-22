// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";

contract AuthorizeSwapper is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Addresses on Base Mainnet
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address swapper = 0x6E331897BCa189678cd60E966F1b1c94517E946E;

        vm.startBroadcast(deployerPrivateKey);

        // Authorize TokenSwapper in Vault
        PayChainVault(vault).setAuthorizedSpender(swapper, true);
        console.log("Authorized TokenSwapper in PayChainVault");

        vm.stopBroadcast();
    }
}
