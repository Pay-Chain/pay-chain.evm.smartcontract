// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";

contract ConfigurePolygonPools is Script {
    address constant TOKEN_SWAPPER = 0xF043b0b91C8F5b6C2DC63897f1632D6D15e199A9;
    address constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant DAI  = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(TOKEN_SWAPPER);

        console.log("Configuring V3 pools on Polygon TokenSwapper:", address(swapper));

        // USDC / USDT (Fee: 100)
        swapper.setV3Pool(USDC, USDT, 100);
        console.log("Configured V3 pool for USDC/USDT (fee 100)");

        // USDC / WETH (Fee: 500)
        swapper.setV3Pool(USDC, WETH, 500);
        console.log("Configured V3 pool for USDC/WETH (fee 500)");

        // USDC / DAI (Fee: 100)
        swapper.setV3Pool(USDC, DAI, 100);
        console.log("Configured V3 pool for USDC/DAI (fee 100)");

        vm.stopBroadcast();
    }
}
