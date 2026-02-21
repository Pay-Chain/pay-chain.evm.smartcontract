// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainGateway.sol";
import "../src/TokenSwapper.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/interfaces/ISwapper.sol";

contract CheckBaseConfig is Script {
    function run() external {
        // HyperbridgeSender on Base
        address senderAddress = 0x58C67aCc6B225e6bFdEedb1edd2E018dfc90432e;
        HyperbridgeSender sender = HyperbridgeSender(payable(senderAddress));

        vm.startBroadcast();

        // 1. Get Gateway
        address gatewayAddress = address(sender.gateway());
        console.log("Gateway Address:", gatewayAddress);
        PayChainGateway gateway = PayChainGateway(gatewayAddress);

        // 2. Get Swapper
        ISwapper swapper = gateway.swapper();
        console.log("Swapper Address:", address(swapper));
        TokenSwapper tokenSwapper = TokenSwapper(payable(address(swapper)));

        // 3. Check Routes for IDRX -> USDC
        // IDRX on Base: 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22
        // USDC on Base: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        address idrx = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        console.log("Checking IDRX -> USDC route...");
        (bool exists, bool isDirect, address[] memory path) = tokenSwapper.findRoute(idrx, usdc);
        console.log("Route Exists:", exists);
        console.log("Is Direct:", isDirect);
        console.log("Path Length:", path.length);
        
            // 3. Helper to get pair key (Client-side implementation of _getPairKey)
            bytes32 pairKey = _getPairKey(idrx, usdc);
            console.log("Pair Key:", vm.toString(pairKey));

            console.log("Checking direct pool config...");
            
            // directPools(bytes32) returns (uint24 fee, int24 tickSpacing, address hooks, bytes memory hookData, bool isActive)
            try tokenSwapper.directPools(pairKey) returns (uint24 fee, int24 tick, address hooks, bytes memory hookData, bool isActive) {
                 console.log("Direct Pool Active:", isActive);
                 console.log("Direct Pool Fee:", fee);
            } catch {
                 console.log("Failed to query directPools");
            }

            console.log("Checking V3 pool config...");
            // v3Pools(bytes32) returns (uint24 feeTier, bool isActive)
            try tokenSwapper.v3Pools(pairKey) returns (uint24 feeTier, bool isActive) {
                console.log("V3 Pool Active:", isActive);
                console.log("V3 Pool Fee:", feeTier);
            } catch {
                console.log("Failed to query v3Pools");
            }
            // Removed extra brace

        // 4. Check SwapRouter Config
        console.log("Checking SwapRouterV3...");
        address v3Router = tokenSwapper.swapRouterV3();
        console.log("SwapRouterV3 Address:", v3Router);
        
        console.log("Checking UniversalRouter...");
        address univRouter = tokenSwapper.universalRouter();
        console.log("UniversalRouter Address:", univRouter);
        
        // 5. Check Authorization
        address vaultAddress = address(tokenSwapper.vault());
        console.log("Swapper Vault:", vaultAddress);

        try PayChainVault(vaultAddress).authorizedSpenders(address(tokenSwapper)) returns (bool authorized) {
            console.log("TokenSwapper Authorized on Vault:", authorized);
        } catch {
             console.log("Failed to check authorization (maybe incorrect vault interface or address)");
        }

        console.log("Checking Gateway Authorization on Swapper...");
        try tokenSwapper.authorizedCallers(gatewayAddress) returns (bool allowed) {
            console.log("Gateway Authorized on Swapper:", allowed);
        } catch {
            console.log("Failed to check gateway authorization on swapper");
        }

        vm.stopBroadcast();
    }

    function _getPairKey(address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a < b ? a : b, a < b ? b : a));
    }
}
