// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";

contract ConfigureDirectRoutes is Script {
    address constant SWAPPER = 0xf3C1e99f464920640b02008643A41FeB2EDc1327;
    
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(SWAPPER);

        // 1. USDC <> WBTC (Fee 100)
        console.log("Configuring USDC <> WBTC (Fee 100)...");
        swapper.setV3Pool(USDC, WBTC, 100);

        // 2. USDC <> WETH (Fee 100)
        console.log("Configuring USDC <> WETH (Fee 100)...");
        swapper.setV3Pool(USDC, WETH, 100);

        // 3. USDC <> cbBTC (Fee 500)
        console.log("Configuring USDC <> cbBTC (Fee 500)...");
        swapper.setV3Pool(USDC, cbBTC, 500);

        vm.stopBroadcast();
        console.log("Configuration complete.");
    }
}
