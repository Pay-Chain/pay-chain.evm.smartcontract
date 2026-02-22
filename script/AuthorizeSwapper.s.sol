// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";

contract AuthorizeSwapper is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Addresses on Base Mainnet
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address swapper = 0x1B5Ac8f181C5e19fd45370b97bcC2B0A3390f099;

        vm.startBroadcast(deployerPrivateKey);

        // Authorize TokenSwapper in Vault
        PayChainVault(vault).setAuthorizedSpender(swapper, true);
        console.log("Authorized TokenSwapper in PayChainVault");

        vm.stopBroadcast();
    }
}
