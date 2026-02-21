// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TokenSwapper.sol";

contract ConfigureMultiHopRoutes is Script {
    address constant SWAPPER = 0xf3C1e99f464920640b02008643A41FeB2EDc1327;
    
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant IDRX = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(SWAPPER);

        // 1. Configure WBTC -> USDC -> IDRX
        console.log("Configuring WBTC -> USDC -> IDRX...");
        address[] memory pathWbtcIdrx = new address[](3);
        pathWbtcIdrx[0] = WBTC;
        pathWbtcIdrx[1] = USDC;
        pathWbtcIdrx[2] = IDRX;
        swapper.setMultiHopPath(WBTC, IDRX, pathWbtcIdrx);

        // 2. Configure IDRX -> USDC -> WETH
        console.log("Configuring IDRX -> USDC -> WETH...");
        address[] memory pathIdrxWeth = new address[](3);
        pathIdrxWeth[0] = IDRX;
        pathIdrxWeth[1] = USDC;
        pathIdrxWeth[2] = WETH;
        swapper.setMultiHopPath(IDRX, WETH, pathIdrxWeth);

        vm.stopBroadcast();
        console.log("Multi-hop routes configured.");
    }
}
