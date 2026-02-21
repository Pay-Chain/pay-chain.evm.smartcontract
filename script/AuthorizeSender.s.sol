// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/vaults/PayChainVault.sol";

contract AuthorizeSender is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        address payable vaultAddress = payable(0x4CD0C58C998ADaFb8c477191bAE7013436126628);
        address senderAddress = 0x58C67aCc6B225e6bFdEedb1edd2E018dfc90432e;

        vm.startBroadcast(deployerPrivateKey);

        PayChainVault vault = PayChainVault(vaultAddress);
        vault.setAuthorizedSpender(senderAddress, true);

        vm.stopBroadcast();
    }
}
