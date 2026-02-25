// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainRouter.sol";
import "../src/PayChainGateway.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";

interface IVaultRouterRewire {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface IRouterConfigSource {
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
    function bridgeModes(uint8 bridgeType) external view returns (uint8);
}

interface ITokenSwapperRouterRewire {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

contract RedeployRouterAndRewireGatewayV2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // ----------------------------
        // Base mainnet hardcoded values
        // Source of truth: CHAIN_BASE.md (+ current ops scripts)
        // ----------------------------
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address gatewayV2 = 0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D;
        address oldRouter = 0x304185d7B5Eb9790Dc78805D2095612F7a43A291;
        address host = 0x6FFe92e4d7a9D589549644544780e6725E84b248;
        address swapper = 0x6E331897BCa189678cd60E966F1b1c94517E946E;
        address swapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        address oldHyperbridgeSender = 0x6709C0dF1a2a015B3C34d6C7a04a185fbAc4740a;
        bool cleanupOldHyperbridgeSender = false; // set true after cutover is stable

        string memory destCaip2 = "eip155:137";
        bytes memory stateMachineId = hex"45564d2d313337"; // EVM-137
        address destContract = 0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD;
        uint64 timeoutSec = 3600;
        uint256 relayerTip = 0;

        vm.startBroadcast(pk);

        // 1) Deploy new router
        PayChainRouter routerV2 = new PayChainRouter();

        // 2) Preserve bridge mode config from old router (0,1,2)
        for (uint8 bridgeType = 0; bridgeType < 3; bridgeType++) {
            uint8 mode = IRouterConfigSource(oldRouter).bridgeModes(bridgeType);
            routerV2.setBridgeMode(bridgeType, PayChainRouter.BridgeMode(mode));
        }

        // 3) Register existing non-Hyperbridge adapters from old router
        address ccipAdapter = IRouterConfigSource(oldRouter).getAdapter(destCaip2, 1);
        if (ccipAdapter != address(0)) {
            routerV2.registerAdapter(destCaip2, 1, ccipAdapter);
        }

        address lzAdapter = IRouterConfigSource(oldRouter).getAdapter(destCaip2, 2);
        if (lzAdapter != address(0)) {
            routerV2.registerAdapter(destCaip2, 2, lzAdapter);
        }

        // 4) Deploy new Hyperbridge sender bound to new router + GatewayV2
        HyperbridgeSender hbSenderV2 = new HyperbridgeSender(vault, host, gatewayV2, address(routerV2));
        hbSenderV2.setSwapRouter(swapRouter);
        hbSenderV2.setSwapper(swapper);
        hbSenderV2.setStateMachineId(destCaip2, stateMachineId);
        hbSenderV2.setDestinationContract(destCaip2, abi.encodePacked(destContract));
        hbSenderV2.setDefaultTimeout(timeoutSec);
        if (relayerTip > 0) {
            hbSenderV2.setRelayerFeeTip(destCaip2, relayerTip);
        }

        // 5) Register new HB sender in routerV2 + authorize spender/adapter
        routerV2.registerAdapter(destCaip2, 0, address(hbSenderV2));
        IVaultRouterRewire(vault).setAuthorizedSpender(address(hbSenderV2), true);
        PayChainGateway(gatewayV2).setAuthorizedAdapter(address(hbSenderV2), true);

        // 6) Rewire gateway to new router
        PayChainGateway(gatewayV2).setRouter(address(routerV2));
        PayChainGateway(gatewayV2).setDefaultBridgeType(destCaip2, 0);

        // 7) Keep swapper/gateway linkage valid
        try ITokenSwapperRouterRewire(swapper).setAuthorizedCaller(gatewayV2, true) {
            // no-op
        } catch {
            console.log("setAuthorizedCaller(gatewayV2) failed on swapper, skip");
        }

        // 8) Deauthorize old HB sender (optional cleanup)
        if (cleanupOldHyperbridgeSender && oldHyperbridgeSender != address(0)) {
            IVaultRouterRewire(vault).setAuthorizedSpender(oldHyperbridgeSender, false);
            PayChainGateway(gatewayV2).setAuthorizedAdapter(oldHyperbridgeSender, false);
        }

        vm.stopBroadcast();

        console.log("RedeployRouterAndRewireGatewayV2 complete");
        console.log("OldRouter:", oldRouter);
        console.log("NewRouter:", address(routerV2));
        console.log("GatewayV2:", gatewayV2);
        console.log("NewHyperbridgeSender:", address(hbSenderV2));
        console.log("CCIPAdapter:", ccipAdapter);
        console.log("LayerZeroAdapter:", lzAdapter);
    }
}
