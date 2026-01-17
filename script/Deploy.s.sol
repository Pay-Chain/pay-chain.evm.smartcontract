// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChain.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ccipRouter = vm.envAddress("CCIP_ROUTER_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        PayChain payChain = new PayChain(ccipRouter, feeRecipient);

        console.log("PayChain deployed at:", address(payChain));

        vm.stopBroadcast();
    }
}
