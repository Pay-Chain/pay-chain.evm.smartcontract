// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";

interface IRouterRotateHB {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
}

interface IGatewayRotateHB {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
}

interface IVaultRotateHB {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

contract RotateHyperbridgeSender is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        // ----------------------------
        // Base mainnet hardcoded values
        // Source of truth: CHAIN_BASE.md (+ existing route script values)
        // ----------------------------
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address gateway = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
        address router = 0x304185d7B5Eb9790Dc78805D2095612F7a43A291;
        address host = 0x6FFe92e4d7a9D589549644544780e6725E84b248;

        string memory destCaip2 = "eip155:137";
        bytes memory stateMachineId = hex"45564d2d313337"; // EVM-137
        address destContract = 0x86b15744F1CC682e8a7236Bb7B2d02dA957958aD;

        address swapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        address swapper = 0x6E331897BCa189678cd60E966F1b1c94517E946E;
        uint256 relayerTip = 0;
        uint64 timeoutSec = 3600;

        bool setDefaultBridge = true;
        bool deauthorizeOld = true;
        address oldSender = 0x8C14627Ae4a3e1CeD0C8A981b73641fE99f370D8;

        vm.startBroadcast(pk);

        HyperbridgeSender newSender = new HyperbridgeSender(vault, host, gateway);

        if (swapRouter != address(0)) {
            newSender.setSwapRouter(swapRouter);
        }
        if (swapper != address(0)) {
            newSender.setSwapper(swapper);
        }

        newSender.setStateMachineId(destCaip2, stateMachineId);
        newSender.setDestinationContract(destCaip2, abi.encodePacked(destContract));
        newSender.setDefaultTimeout(timeoutSec);
        if (relayerTip > 0) {
            newSender.setRelayerFeeTip(destCaip2, relayerTip);
        }

        IVaultRotateHB(vault).setAuthorizedSpender(address(newSender), true);
        IGatewayRotateHB(gateway).setAuthorizedAdapter(address(newSender), true);
        IRouterRotateHB(router).registerAdapter(destCaip2, 0, address(newSender));

        if (setDefaultBridge) {
            IGatewayRotateHB(gateway).setDefaultBridgeType(destCaip2, 0);
        }

        if (deauthorizeOld && oldSender != address(0)) {
            IVaultRotateHB(vault).setAuthorizedSpender(oldSender, false);
            IGatewayRotateHB(gateway).setAuthorizedAdapter(oldSender, false);
        }

        vm.stopBroadcast();

        console.log("RotateHyperbridgeSender complete");
        console.log("New HyperbridgeSender:", address(newSender));
        console.log("Destination CAIP2:", destCaip2);
        console.log("Host:", host);
        console.log("Vault:", vault);
        console.log("Gateway:", gateway);
        console.log("Router:", router);
    }
}
