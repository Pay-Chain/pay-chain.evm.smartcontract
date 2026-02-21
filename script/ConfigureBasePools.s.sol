// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";

contract ConfigureBasePools is Script {
    address constant TOKEN_SWAPPER = 0x8fd8Df03D50514f9386a0adE7E6aEE4003399933;
    address constant IDRX = 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint24 constant POOL_FEE = 100;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenSwapper swapper = TokenSwapper(TOKEN_SWAPPER);

        console.log("Configuring IDRX/USDC V3 pool on TokenSwapper...");
        console.log("TokenSwapper:", address(swapper));
        console.log("IDRX:", IDRX);
        console.log("USDC:", USDC);
        console.log("Fee:", POOL_FEE);

        try swapper.setV3Pool(IDRX, USDC, POOL_FEE) {
            console.log("Successfully configured V3 pool for IDRX/USDC");
        } catch Error(string memory reason) {
            console.log("Failed to configure V3 pool:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("Failed to configure V3 pool (low level)");
        }

        vm.stopBroadcast();
    }
}
