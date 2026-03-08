// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";

contract UpdateBaseFeeStrategyDefault is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address managerAddr = vm.envAddress("BASE_FEE_POLICY_MANAGER");
        address registryAddr = vm.envAddress("BASE_TOKEN_REGISTRY");

        vm.startBroadcast(pk);

        FeeStrategyDefaultV1 newStrategy = new FeeStrategyDefaultV1(registryAddr);
        FeePolicyManager(managerAddr).setDefaultStrategy(address(newStrategy));

        vm.stopBroadcast();
    }
}
