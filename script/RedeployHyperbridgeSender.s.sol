// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";
import "../src/PayChainGateway.sol";
import "../src/PayChainRouter.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/layerzero/LayerZeroReceiverAdapter.sol";

contract RedeployHyperbridgeSender is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Existing Addresses on Base Mainnet
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address gateway = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
        address router = 0x304185d7B5Eb9790Dc78805D2095612F7a43A291;
        address ccipReceiver = 0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1;
        address lzReceiver = 0x4864138d5Dc8a5bcFd4228D7F784D1F32859986f;
        address hbReceiver = 0xf4348E2e6AF1860ea9Ab0F3854149582b608b5e2;

        // Configuration
        address routerV4 = vm.envOr("BASE_POOL_MANAGER", address(0));
        address universalRouter = vm.envOr("BASE_UNIVERSAL_ROUTER", address(0));
        address bridgeToken = vm.envOr("BASE_USDC", address(0));
        address quoterV3 = 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a;
        address swapRouterV3 = 0x2626664c2603336E57B271c5C0b26F421741e481;
        address hbHost = vm.envOr("BASE_HYPERBRIDGE_HOST", address(0));

        vm.startBroadcast(deployerPrivateKey);

        // 1. Redeploy TokenSwapper with fixes
        TokenSwapper newSwapper = new TokenSwapper(
            universalRouter,
            routerV4,
            bridgeToken
        );
        newSwapper.setVault(vault);
        newSwapper.setQuoterV3(quoterV3);
        newSwapper.setV3Router(swapRouterV3);
        console.log("New TokenSwapper deployed at:", address(newSwapper));

        // 2. Authorize Components on New Swapper
        newSwapper.setAuthorizedCaller(gateway, true);
        newSwapper.setAuthorizedCaller(ccipReceiver, true);
        newSwapper.setAuthorizedCaller(lzReceiver, true);
        newSwapper.setAuthorizedCaller(hbReceiver, true);
        console.log(
            "Authorized Gateway and all receiver adapters on new Swapper"
        );

        // 3. Update all components to use new Swapper
        PayChainGateway(gateway).setSwapper(address(newSwapper));
        CCIPReceiverAdapter(ccipReceiver).setSwapper(address(newSwapper));
        LayerZeroReceiverAdapter(lzReceiver).setSwapper(address(newSwapper));
        HyperbridgeReceiver(hbReceiver).setSwapper(address(newSwapper));
        console.log(
            "Updated all receiver adapters and gateway to use new Swapper"
        );

        // 4. Redeploy HyperbridgeSender
        HyperbridgeSender newSender = new HyperbridgeSender(
            vault,
            hbHost,
            gateway
        );
        console.log("New HyperbridgeSender deployed at:", address(newSender));

        // 5. Configure New Sender
        newSwapper.setAuthorizedCaller(address(newSender), true);
        PayChainGateway(gateway).setAuthorizedAdapter(address(newSender), true);
        PayChainVault(vault).setAuthorizedSpender(address(newSender), true);
        console.log("New HyperbridgeSender authorized and configured");

        // 6. Register on Router (Polygon destination)
        string memory chainId = "eip155:137";
        PayChainRouter(router).registerAdapter(chainId, 0, address(newSender));
        console.log("Registered new Hyperbridge sender on Router for Polygon");

        // 7. Configure Destination Contract on Sender
        bytes memory smId = hex"45564d2d313337";
        bytes memory dest = abi.encodePacked(
            address(0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD)
        );
        newSender.setStateMachineId(chainId, smId);
        newSender.setDestinationContract(chainId, dest);
        newSender.setDefaultTimeout(3600);
        console.log("Configured Hyperbridge Sender destination details");

        vm.stopBroadcast();

        console.log("-----------------------------------------");
        console.log("Deployment and Configuration Complete!");
        console.log("New Sender Address:", address(newSender));
        console.log("New Swapper Address:", address(newSwapper));
        console.log("-----------------------------------------");
    }
}
