// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/gateway/fee/strategies/FeeStrategyMarketAdaptiveV1.sol";
import "../src/gateway/fee/FeePolicyManager.sol";

contract DeployGatewayModular is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address registry = vm.envAddress("GW_MOD_TOKEN_REGISTRY");
        bool deployAdaptive = vm.envOr("GW_MOD_DEPLOY_ADAPTIVE", false);
        uint256 baseBps = vm.envOr("GW_MOD_ADAPTIVE_BASE_BPS", uint256(20));
        uint256 boostBps = vm.envOr("GW_MOD_ADAPTIVE_BOOST_BPS", uint256(10));
        uint256 minBps = vm.envOr("GW_MOD_ADAPTIVE_MIN_BPS", uint256(5));
        uint256 maxBps = vm.envOr("GW_MOD_ADAPTIVE_MAX_BPS", uint256(100));

        vm.startBroadcast(pk);

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

        vm.stopBroadcast();

        console.log("DeployGatewayModular complete");
        console.log("validator:", address(validator));
        console.log("quoter:", address(quoter));
        console.log("executor:", address(executor));
        console.log("privacy:", address(privacy));
        console.log("defaultStrategy:", address(defaultStrategy));
        console.log("feePolicyManager:", address(manager));
        console.log("adaptiveStrategy:", adaptiveStrategy);
    }
}
