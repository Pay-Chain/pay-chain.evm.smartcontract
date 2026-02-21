// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TokenSwapper.sol";
import "../src/PayChainGateway.sol";
import "../src/vaults/PayChainVault.sol";

contract VerifyAllPolygonRoutes is Script {
    // Polygon Contracts
    TokenSwapper constant swapper = TokenSwapper(0xF043b0b91C8F5b6C2DC63897f1632D6D15e199A9);
    PayChainGateway constant gateway = PayChainGateway(0x7a4f3b606D90e72555A36cB370531638fad19Bf8);
    TokenRegistry constant registry = TokenRegistry(0xd2C69EA4968e9F7cc8C0F447eB9b6DFdFFb1F8D7);
    
    // Polygon Tokens
    address constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address constant DAI  = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant IDRT = 0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b;

    function run() external {
        console.log("== Polygon Configuration Verification ==");
        
        // 1. Check Registry Supported Tokens
        console.log("== Registry Supported Tokens ==");
        console.log("USDC Supported:", registry.isTokenSupported(USDC));
        console.log("USDT Supported:", registry.isTokenSupported(USDT));
        console.log("WETH Supported:", registry.isTokenSupported(WETH));
        console.log("DAI Supported:", registry.isTokenSupported(DAI));
        console.log("IDRT Supported:", registry.isTokenSupported(IDRT));
        
        // 2. Check Routes from USDC (Bridge Token) to others
        console.log("\n== TokenSwapper Routes ==");
        checkRoute("USDC -> USDT", USDC, USDT);
        checkRoute("USDC -> WETH", USDC, WETH);
        checkRoute("USDC -> DAI", USDC, DAI);
        checkRoute("USDT -> USDC", USDT, USDC);
        checkRoute("WETH -> USDC", WETH, USDC);
        checkRoute("DAI -> USDC", DAI, USDC);
        checkRoute("USDC -> IDRT", USDC, IDRT);
        checkRoute("IDRT -> USDC", IDRT, USDC);
    }

    function checkRoute(string memory label, address tokenIn, address tokenOut) internal view {
        (bool exists, bool isDirect, address[] memory path) = swapper.findRoute(tokenIn, tokenOut);
        
        console.log(label);
        console.log("  Route Exists:", exists);
        if (exists) {
            console.log("  Is Direct:", isDirect);
            if (!isDirect) {
                console.log("  Multi-hop Path Length:", path.length);
            }
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
