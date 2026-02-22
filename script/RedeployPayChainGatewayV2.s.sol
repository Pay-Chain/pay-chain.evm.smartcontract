// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainGateway.sol";

interface IVaultGatewayV2 {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface IGatewayConfigSource {
    function swapper() external view returns (address);
    function enableSourceSideSwap() external view returns (bool);
    function platformFeePolicy()
        external
        view
        returns (bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee);
}

contract RedeployPayChainGatewayV2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address vault = vm.envAddress("GATEWAY_V2_VAULT");
        address router = vm.envAddress("GATEWAY_V2_ROUTER");
        address tokenRegistry = vm.envAddress("GATEWAY_V2_TOKEN_REGISTRY");
        address feeRecipient = vm.envAddress("GATEWAY_V2_FEE_RECIPIENT");

        address oldGateway = vm.envOr("GATEWAY_V2_OLD_GATEWAY", address(0));
        bool deauthorizeOldGateway = vm.envOr("GATEWAY_V2_DEAUTHORIZE_OLD_GATEWAY", false);
        bool copyConfigFromOldGateway = vm.envOr("GATEWAY_V2_COPY_CONFIG_FROM_OLD", true);

        uint256 adapterCount = vm.envOr("GATEWAY_V2_ADAPTER_COUNT", uint256(0));
        uint256 defaultRouteCount = vm.envOr("GATEWAY_V2_DEFAULT_ROUTE_COUNT", uint256(0));

        vm.startBroadcast(pk);

        PayChainGateway gatewayV2 = new PayChainGateway(vault, router, tokenRegistry, feeRecipient);

        // Authorize new gateway in vault so it can pull/push user funds.
        IVaultGatewayV2(vault).setAuthorizedSpender(address(gatewayV2), true);

        // Optional: copy selected runtime config from old gateway.
        if (copyConfigFromOldGateway && oldGateway != address(0)) {
            _copyConfig(gatewayV2, oldGateway);
        }

        // Authorize existing adapters in new gateway for markPaymentFailed/finalization callback paths.
        for (uint256 i = 0; i < adapterCount; i++) {
            address adapter = vm.envAddress(_keyWithIndex("GATEWAY_V2_ADAPTER_", i));
            gatewayV2.setAuthorizedAdapter(adapter, true);
        }

        // Optional: set default bridge type for known routes.
        // Requires:
        // - GATEWAY_V2_DEFAULT_ROUTE_COUNT
        // - GATEWAY_V2_ROUTE_DEST_<i> (e.g. eip155:137)
        // - GATEWAY_V2_ROUTE_BRIDGE_TYPE_<i> (0/1/2)
        for (uint256 i = 0; i < defaultRouteCount; i++) {
            string memory destCaip2 = vm.envString(_keyWithIndex("GATEWAY_V2_ROUTE_DEST_", i));
            uint256 bridgeTypeRaw = vm.envUint(_keyWithIndex("GATEWAY_V2_ROUTE_BRIDGE_TYPE_", i));
            require(bridgeTypeRaw <= type(uint8).max, "bridge type overflow");
            // forge-lint: disable-next-line(unsafe-typecast)
            gatewayV2.setDefaultBridgeType(destCaip2, uint8(bridgeTypeRaw));
        }

        if (deauthorizeOldGateway && oldGateway != address(0)) {
            IVaultGatewayV2(vault).setAuthorizedSpender(oldGateway, false);
        }

        vm.stopBroadcast();

        console.log("RedeployPayChainGatewayV2 complete");
        console.log("GatewayV2:", address(gatewayV2));
        console.log("Vault:", vault);
        console.log("Router:", router);
        console.log("TokenRegistry:", tokenRegistry);
        console.log("FeeRecipient:", feeRecipient);
        if (oldGateway != address(0)) {
            console.log("OldGateway:", oldGateway);
            console.log("DeauthorizeOldGateway:", deauthorizeOldGateway);
            console.log("CopyConfigFromOldGateway:", copyConfigFromOldGateway);
        }
    }

    function _copyConfig(PayChainGateway gatewayV2, address oldGateway) internal {
        IGatewayConfigSource old = IGatewayConfigSource(oldGateway);

        address oldSwapper = old.swapper();
        if (oldSwapper != address(0)) {
            gatewayV2.setSwapper(oldSwapper);
        }
        gatewayV2.setEnableSourceSideSwap(old.enableSourceSideSwap());

        (bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee) =
            old.platformFeePolicy();
        gatewayV2.setPlatformFeePolicy(enabled, perByteRate, overheadBytes, minFee, maxFee);
    }

    function _keyWithIndex(string memory prefix, uint256 index) internal pure returns (string memory) {
        return string.concat(prefix, _uintToString(index));
    }

    function _uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
