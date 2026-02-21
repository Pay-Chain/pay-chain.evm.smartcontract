// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";

contract VerifyAllBaseRoutes is Script {
    address constant SWAPPER = 0x96562f9A774AA5dc1B3E251Df3B78EBaE682B984;
    
    address constant IDRX = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant USDe = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;

    TokenSwapper swapper;

    function run() external {
        swapper = TokenSwapper(SWAPPER);
        
        console.log("=== Base Route Verification ===");
        
        checkRoute("USDC -> WBTC", USDC, WBTC);
        checkRoute("USDC -> WETH", USDC, WETH);
        checkRoute("USDC -> cbBTC", USDC, cbBTC);
        checkRoute("USDC -> USDe", USDC, USDe);
        
        checkRoute("IDRX -> USDC", IDRX, USDC);
        checkRoute("IDRX -> WBTC", IDRX, WBTC);
        checkRoute("IDRX -> WETH", IDRX, WETH);
        checkRoute("IDRX -> USDe", IDRX, USDe);
    }

    function checkRoute(string memory label, address tokenIn, address tokenOut) internal view {
        (bool exists, bool isDirect, ) = swapper.findRoute(tokenIn, tokenOut);
        
        console.log(label);
        console.log("  Route Exists:", exists);
        if (exists) {
            console.log("  Is Direct:", isDirect);
        }
        
        // Also check V3 pool specifically
        bytes32 pairKey = keccak256(abi.encodePacked(tokenIn < tokenOut ? tokenIn : tokenOut, tokenIn < tokenOut ? tokenOut : tokenIn));
        (uint24 fee, bool active) = swapper.v3Pools(pairKey);
        console.log("  V3 Pool Active:", active);
        if (active) {
            console.log("  V3 Fee:", fee);
        }
        console.log("-------------------");
    }
}
