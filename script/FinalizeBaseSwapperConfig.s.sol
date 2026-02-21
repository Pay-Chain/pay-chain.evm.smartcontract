// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TokenSwapper.sol";

contract FinalizeBaseSwapperConfig is Script {
    address constant SWAPPER = 0xf3C1e99f464920640b02008643A41FeB2EDc1327;
    address constant GATEWAY = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
    
    address constant IDRX = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant USDe = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(payable(SWAPPER));

        // 1. Authorize Gateway to call Swapper
        console.log("Authorizing Gateway on TokenSwapper...");
        swapper.setAuthorizedCaller(GATEWAY, true);

        // 2. Configure Direct V3 Pools
        console.log("Configuring IDRX <> USDC (Fee 100)...");
        swapper.setV3Pool(IDRX, USDC, 100);

        console.log("Configuring USDC <> WBTC (Fee 100)...");
        swapper.setV3Pool(USDC, WBTC, 100);

        console.log("Configuring USDC <> WETH (Fee 100)...");
        swapper.setV3Pool(USDC, WETH, 100);

        console.log("Configuring USDC <> cbBTC (Fee 500)...");
        swapper.setV3Pool(USDC, cbBTC, 500);

        console.log("Configuring USDC <> USDe (Fee 100)...");
        swapper.setV3Pool(USDC, USDe, 100);

        // 3. Configure Multi-hop
        console.log("Configuring WBTC -> USDC -> IDRX...");
        address[] memory pathWbtcIdrx = new address[](3);
        pathWbtcIdrx[0] = WBTC;
        pathWbtcIdrx[1] = USDC;
        pathWbtcIdrx[2] = IDRX;
        swapper.setMultiHopPath(WBTC, IDRX, pathWbtcIdrx);

        console.log("Configuring IDRX -> USDC -> WETH...");
        address[] memory pathIdrxWeth = new address[](3);
        pathIdrxWeth[0] = IDRX;
        pathIdrxWeth[1] = USDC;
        pathIdrxWeth[2] = WETH;
        swapper.setMultiHopPath(IDRX, WETH, pathIdrxWeth);

        console.log("Configuring IDRX -> USDC -> USDe...");
        address[] memory pathIdrxUsde = new address[](3);
        pathIdrxUsde[0] = IDRX;
        pathIdrxUsde[1] = USDC;
        pathIdrxUsde[2] = USDe;
        swapper.setMultiHopPath(IDRX, USDe, pathIdrxUsde);

        vm.stopBroadcast();
        console.log("Final configuration for Base TokenSwapper complete.");
    }
}
