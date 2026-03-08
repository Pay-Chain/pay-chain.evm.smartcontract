// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/PaymentKitaGateway.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/gateway/fee/strategies/FeeStrategyMarketAdaptiveV1.sol";

interface IExistingGatewayView {
    function router() external view returns (address);
    function vault() external view returns (address);
    function tokenRegistry() external view returns (address);
    function feeRecipient() external view returns (address);
    function swapper() external view returns (address);
    function enableSourceSideSwap() external view returns (bool);
    function platformFeePolicy()
        external
        view
        returns (bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee);
}

interface IVaultAuth {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ISwapperAuth {
    function setAuthorizedCaller(address caller, bool allowed) external;
}

interface IPrivacyAuth {
    function setAuthorizedGateway(address gateway, bool allowed) external;
}

contract DeployGatewayModularV2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address oldGateway = vm.envAddress("GWV2_OLD_GATEWAY");
        address router = vm.envOr("GWV2_ROUTER", IExistingGatewayView(oldGateway).router());
        address vault = vm.envOr("GWV2_VAULT", IExistingGatewayView(oldGateway).vault());
        address registry = vm.envOr("GWV2_TOKEN_REGISTRY", IExistingGatewayView(oldGateway).tokenRegistry());
        address feeRecipient = vm.envOr("GWV2_FEE_RECIPIENT", IExistingGatewayView(oldGateway).feeRecipient());
        address swapperOverride = vm.envOr("GWV2_SWAPPER", address(0));

        bool copySourceSideSwap = vm.envOr("GWV2_COPY_SOURCE_SIDE_SWAP", true);
        bool copyPlatformFeePolicy = vm.envOr("GWV2_COPY_PLATFORM_FEE_POLICY", true);
        bool deauthorizeOldGateway = vm.envOr("GWV2_DEAUTHORIZE_OLD_GATEWAY", false);

        bool deployAdaptive = vm.envOr("GWV2_DEPLOY_ADAPTIVE", false);
        uint256 baseBps = vm.envOr("GWV2_ADAPTIVE_BASE_BPS", uint256(20));
        uint256 boostBps = vm.envOr("GWV2_ADAPTIVE_BOOST_BPS", uint256(10));
        uint256 minBps = vm.envOr("GWV2_ADAPTIVE_MIN_BPS", uint256(5));
        uint256 maxBps = vm.envOr("GWV2_ADAPTIVE_MAX_BPS", uint256(100));

        vm.startBroadcast(pk);

        PaymentKitaGateway gateway = new PaymentKitaGateway(vault, router, registry, feeRecipient);
        GatewayValidatorModule validator = new GatewayValidatorModule();
        GatewayQuoteModule quoter = new GatewayQuoteModule();
        GatewayExecutionModule executor = new GatewayExecutionModule();
        GatewayPrivacyModule privacy = new GatewayPrivacyModule();
        FeeStrategyDefaultV1 defaultStrategy = new FeeStrategyDefaultV1(registry);
        FeePolicyManager manager = new FeePolicyManager(address(defaultStrategy));

        address adaptiveStrategy = address(0);
        if (deployAdaptive) {
            FeeStrategyMarketAdaptiveV1 adaptive = new FeeStrategyMarketAdaptiveV1(baseBps, boostBps, minBps, maxBps);
            adaptiveStrategy = address(adaptive);
        }

        gateway.setGatewayModules(address(validator), address(quoter), address(executor), address(privacy));
        gateway.setFeePolicyManager(address(manager));
        IPrivacyAuth(address(privacy)).setAuthorizedGateway(address(gateway), true);

        address swapper = swapperOverride;
        if (swapper == address(0)) {
            swapper = IExistingGatewayView(oldGateway).swapper();
        }
        if (swapper != address(0)) {
            gateway.setSwapper(swapper);
            ISwapperAuth(swapper).setAuthorizedCaller(address(gateway), true);
            IVaultAuth(vault).setAuthorizedSpender(swapper, true);
        }

        if (copySourceSideSwap) {
            gateway.setEnableSourceSideSwap(IExistingGatewayView(oldGateway).enableSourceSideSwap());
        }
        if (copyPlatformFeePolicy) {
            try IExistingGatewayView(oldGateway).platformFeePolicy() returns (
                bool enabled, uint256 perByteRate, uint256 overheadBytes, uint256 minFee, uint256 maxFee
            ) {
                gateway.setPlatformFeePolicy(enabled, perByteRate, overheadBytes, minFee, maxFee);
            } catch {
                console.log("Skip copy platformFeePolicy: old gateway does not expose it");
            }
        }

        IVaultAuth(vault).setAuthorizedSpender(address(gateway), true);

        _setDefaultBridgeTypeIfProvided(gateway, "GWV2_DEFAULT_DEST_1", "GWV2_DEFAULT_BRIDGE_TYPE_1");
        _setDefaultBridgeTypeIfProvided(gateway, "GWV2_DEFAULT_DEST_2", "GWV2_DEFAULT_BRIDGE_TYPE_2");
        _setDefaultBridgeTypeIfProvided(gateway, "GWV2_DEFAULT_DEST_3", "GWV2_DEFAULT_BRIDGE_TYPE_3");
        _setDefaultBridgeTypeIfProvided(gateway, "GWV2_DEFAULT_DEST_4", "GWV2_DEFAULT_BRIDGE_TYPE_4");

        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_1");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_2");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_3");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_4");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_5");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_6");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_7");
        _authorizeAdapterIfProvided(gateway, "GWV2_ADAPTER_8");

        if (deauthorizeOldGateway) {
            IVaultAuth(vault).setAuthorizedSpender(oldGateway, false);
            if (swapper != address(0)) {
                ISwapperAuth(swapper).setAuthorizedCaller(oldGateway, false);
            }
        }

        vm.stopBroadcast();

        console.log("DeployGatewayModularV2 complete");
        console.log("oldGateway:", oldGateway);
        console.log("newGateway:", address(gateway));
        console.log("router:", router);
        console.log("vault:", vault);
        console.log("tokenRegistry:", registry);
        console.log("feeRecipient:", feeRecipient);
        console.log("swapper:", swapper);
        console.log("validator:", address(validator));
        console.log("quote:", address(quoter));
        console.log("execution:", address(executor));
        console.log("privacy:", address(privacy));
        console.log("defaultStrategy:", address(defaultStrategy));
        console.log("feePolicyManager:", address(manager));
        console.log("adaptiveStrategy:", adaptiveStrategy);
    }

    function _setDefaultBridgeTypeIfProvided(PaymentKitaGateway gateway, string memory destKey, string memory typeKey) internal {
        string memory dest = vm.envOr(destKey, string(""));
        if (bytes(dest).length == 0) return;
        uint8 bridgeType = uint8(vm.envOr(typeKey, uint256(255)));
        require(bridgeType <= 2, "invalid bridge type");
        gateway.setDefaultBridgeType(dest, bridgeType);
    }

    function _authorizeAdapterIfProvided(PaymentKitaGateway gateway, string memory adapterKey) internal {
        address adapter = vm.envOr(adapterKey, address(0));
        if (adapter == address(0)) return;
        gateway.setAuthorizedAdapter(adapter, true);
    }
}
