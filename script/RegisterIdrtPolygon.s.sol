// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainGateway.sol"; // Contains TokenRegistry interface/contract

contract RegisterIdrtPolygon is Script {
    address constant TOKEN_REGISTRY = 0xd2C69EA4968e9F7cc8C0F447eB9b6DFdFFb1F8D7;
    address constant IDRT = 0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenRegistry registry = TokenRegistry(TOKEN_REGISTRY);

        console.log("Registering IDRT on Polygon TokenRegistry:", address(registry));

        if (!registry.isTokenSupported(IDRT)) {
            registry.setTokenSupport(IDRT, true);
            console.log("Successfully added IDRT to supported tokens");
        } else {
            console.log("IDRT is already supported");
        }

        vm.stopBroadcast();
    }
}
