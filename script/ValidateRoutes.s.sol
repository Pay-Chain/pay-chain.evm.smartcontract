// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IBridgeAdapter.sol";

interface IRouterView {
    function hasAdapter(string memory destChainId, uint8 bridgeType) external view returns (bool);
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
    function quotePaymentFee(
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view returns (uint256 fee);
}

contract ValidateRoutes is Script {
    function run() external view {
        address router = vm.envAddress("ROUTE_ROUTER_ADDRESS");
        string memory destCaip2 = vm.envString("ROUTE_DEST_CAIP2");
        uint8 bridgeType = uint8(vm.envUint("ROUTE_VALIDATE_BRIDGE_TYPE"));

        IRouterView r = IRouterView(router);
        bool has = r.hasAdapter(destCaip2, bridgeType);
        console.log("hasAdapter:", has);

        if (!has) {
            return;
        }

        address adapter = r.getAdapter(destCaip2, bridgeType);
        console.log("adapter:", adapter);

        bool configured = IBridgeAdapter(adapter).isRouteConfigured(destCaip2);
        console.log("isRouteConfigured:", configured);

        if (!configured) {
            return;
        }

        IBridgeAdapter.BridgeMessage memory msgStruct = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(0),
            receiver: address(0),
            sourceToken: vm.envAddress("ROUTE_VALIDATE_SOURCE_TOKEN"),
            destToken: vm.envAddress("ROUTE_VALIDATE_DEST_TOKEN"),
            amount: vm.envUint("ROUTE_VALIDATE_AMOUNT"),
            destChainId: destCaip2,
            minAmountOut: 0
        });

        try r.quotePaymentFee(destCaip2, bridgeType, msgStruct) returns (uint256 fee) {
            console.log("quotePaymentFee:", fee);
        } catch {
            console.log("quotePaymentFee: reverted");
        }
    }
}

