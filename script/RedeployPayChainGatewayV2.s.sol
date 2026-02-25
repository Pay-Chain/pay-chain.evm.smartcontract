// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PayChainGateway.sol";

interface IVaultGatewayV2 {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ITokenSwapperGatewayV2 {
    function setAuthorizedCaller(address caller, bool allowed) external;
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

        // ----------------------------
        // Base mainnet hardcoded values
        // Source of truth: CHAIN_BASE.md
        // ----------------------------
        address vault = 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7;
        address router = 0x304185d7B5Eb9790Dc78805D2095612F7a43A291;
        address tokenRegistry = 0x19cC8187e5DF6D482EF26443FC11C90123348C8e;
        address feeRecipient = 0xE6A7d99011257AEc28Ad60EFED58A256c4d5Fea3;

        address oldGateway = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;
        bool deauthorizeOldGateway = false;
        bool copyConfigFromOldGateway = true;

        address[] memory adapters = new address[](4);
        // CHAIN_BASE.md active adapters on Base.
        adapters[0] = 0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1; // CCIPReceiverAdapter
        adapters[1] = 0x4864138d5Dc8a5bcFd4228D7F784D1F32859986f; // LayerZeroReceiverAdapter
        adapters[2] = 0xf4348E2e6AF1860ea9Ab0F3854149582b608b5e2; // HyperbridgeReceiver
        adapters[3] = 0x6709C0dF1a2a015B3C34d6C7a04a185fbAc4740a; // HyperbridgeSender

        string[] memory defaultRouteDests = new string[](1);
        uint8[] memory defaultRouteBridgeTypes = new uint8[](1);
        defaultRouteDests[0] = "eip155:137";
        defaultRouteBridgeTypes[0] = 0;

        vm.startBroadcast(pk);

        PayChainGateway gatewayV2 = new PayChainGateway(vault, router, tokenRegistry, feeRecipient);

        // Authorize new gateway in vault so it can pull/push user funds.
        IVaultGatewayV2(vault).setAuthorizedSpender(address(gatewayV2), true);

        // Optional: copy selected runtime config from old gateway.
        if (copyConfigFromOldGateway && oldGateway != address(0)) {
            _copyConfig(gatewayV2, oldGateway);
        }

        // Re-wire swapper auth for new gateway (if swapper already configured/copied).
        address configuredSwapper = address(gatewayV2.swapper());
        if (configuredSwapper != address(0)) {
            // Ensure vault still allows swapper pull/push flows.
            IVaultGatewayV2(vault).setAuthorizedSpender(configuredSwapper, true);
            // Ensure swapper allows calls from new gateway.
            try ITokenSwapperGatewayV2(configuredSwapper).setAuthorizedCaller(address(gatewayV2), true) {
                // no-op
            } catch {
                console.log("setAuthorizedCaller(newGateway) failed on swapper, skip");
            }
        }

        // Authorize existing adapters in new gateway for markPaymentFailed/finalization callback paths.
        for (uint256 i = 0; i < adapters.length; i++) {
            address adapter = adapters[i];
            gatewayV2.setAuthorizedAdapter(adapter, true);
        }

        // Optional: set default bridge type for known routes.
        for (uint256 i = 0; i < defaultRouteDests.length; i++) {
            gatewayV2.setDefaultBridgeType(defaultRouteDests[i], defaultRouteBridgeTypes[i]);
        }

        if (deauthorizeOldGateway && oldGateway != address(0)) {
            IVaultGatewayV2(vault).setAuthorizedSpender(oldGateway, false);
            if (configuredSwapper != address(0)) {
                try ITokenSwapperGatewayV2(configuredSwapper).setAuthorizedCaller(oldGateway, false) {
                    // no-op
                } catch {
                    console.log("setAuthorizedCaller(oldGateway,false) failed on swapper, skip");
                }
            }
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

        // Optional (Track-B): not all legacy gateways expose platformFeePolicy().
        try old.platformFeePolicy() returns (
            bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee
        ) {
            gatewayV2.setPlatformFeePolicy(enabled, perByteRate, overheadBytes, minFee, maxFee);
        } catch {
            console.log("platformFeePolicy() unavailable on old gateway, skip copy");
        }
    }
}
