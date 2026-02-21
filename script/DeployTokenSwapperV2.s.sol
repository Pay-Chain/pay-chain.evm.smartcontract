// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";
import "../src/PayChainGateway.sol";
import "../src/vaults/PayChainVault.sol";

contract DeployTokenSwapperV2 is Script {
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;
    address constant POOL_MANAGER = 0x8a10731ced25c43D739B92067645CF0019e778E2;
    address constant BRIDGE_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC

    address constant GATEWAY = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
    address constant VAULT = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
    
    // V3 Router on Base
    address constant SWAP_ROUTER_V3 = 0x2626664c2603336E57B271c5C0b26F421741e481;
    // V3 Quoter on Base
    address constant QUOTER_V3 = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a; 

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying TokenSwapperV2...");
        
        TokenSwapper swapper = new TokenSwapper(
            UNIVERSAL_ROUTER,
            POOL_MANAGER,
            BRIDGE_TOKEN
        );
        console.log("TokenSwapperV2 deployed at:", address(swapper));

        // 1. Configure Swapper Basics
        swapper.setVault(VAULT);
        swapper.setV3Router(SWAP_ROUTER_V3);
        swapper.setQuoterV3(QUOTER_V3);
        
        // 2. Authorize Gateway on TokenSwapper
        console.log("Authorizing Gateway on TokenSwapper...");
        swapper.setAuthorizedCaller(GATEWAY, true);
        
        // 3. Authorize Swapper on Vault
        console.log("Authorizing Swapper on Vault...");
        PayChainVault(VAULT).setAuthorizedSpender(address(swapper), true);
        
        // 4. Update Gateway to use new Swapper
        console.log("Updating Gateway...");
        PayChainGateway(GATEWAY).setSwapper(address(swapper));

        // 5. Configure Direct V3 Pools
        console.log("Configuring Direct V3 Pools...");
        swapper.setV3Pool(0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22, BRIDGE_TOKEN, 100); // IDRX <> USDC
        swapper.setV3Pool(BRIDGE_TOKEN, 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c, 100); // USDC <> WBTC
        swapper.setV3Pool(BRIDGE_TOKEN, 0x4200000000000000000000000000000000000006, 100); // USDC <> WETH
        swapper.setV3Pool(BRIDGE_TOKEN, 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf, 500); // USDC <> cbBTC
        swapper.setV3Pool(BRIDGE_TOKEN, 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34, 100); // USDC <> USDe

        // 6. Configure Multi-hop Routes
        console.log("Configuring Multi-hop Routes...");

        // WBTC -> USDC -> IDRX
        address[] memory pathWbtcIdrx = new address[](3);
        pathWbtcIdrx[0] = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
        pathWbtcIdrx[1] = BRIDGE_TOKEN;
        pathWbtcIdrx[2] = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
        swapper.setMultiHopPath(pathWbtcIdrx[0], pathWbtcIdrx[2], pathWbtcIdrx);

        // IDRX -> USDC -> WETH
        address[] memory pathIdrxWeth = new address[](3);
        pathIdrxWeth[0] = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
        pathIdrxWeth[1] = BRIDGE_TOKEN;
        pathIdrxWeth[2] = 0x4200000000000000000000000000000000000006;
        swapper.setMultiHopPath(pathIdrxWeth[0], pathIdrxWeth[2], pathIdrxWeth);

        // IDRX -> USDC -> USDe
        address[] memory pathIdrxUsde = new address[](3);
        pathIdrxUsde[0] = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
        pathIdrxUsde[1] = BRIDGE_TOKEN;
        pathIdrxUsde[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
        swapper.setMultiHopPath(pathIdrxUsde[0], pathIdrxUsde[2], pathIdrxUsde);
        
        vm.stopBroadcast();
        console.log("Deployment and configuration complete.");
    }
}
