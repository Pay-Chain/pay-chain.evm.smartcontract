// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";

contract ConfigureIdrtPolygonPools is Script {
    address constant TOKEN_SWAPPER = 0xF043b0b91C8F5b6C2DC63897f1632D6D15e199A9;
    address constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant IDRT = 0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(TOKEN_SWAPPER);

        console.log("Configuring V3 pools on Polygon TokenSwapper:", address(swapper));

        // USDC / IDRT (Fee: 3000)
        swapper.setV3Pool(USDC, IDRT, 3000);
        console.log("Configured V3 pool for USDC/IDRT (fee 3000)");

        vm.stopBroadcast();
    }
}
