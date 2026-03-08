// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenRegistry.sol";

contract DeployBaseTokenRegistryV2 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address usdc = vm.envOr("BASE_USDC", address(0));
        address usde = vm.envOr("BASE_USDE", address(0));
        address weth = vm.envOr("BASE_WETH", address(0));
        address cbeth = vm.envOr("BASE_CBETH", address(0));
        address cbbtc = vm.envOr("BASE_CBBTC", address(0));
        address wbtc = vm.envOr("BASE_WBTC", address(0));
        address idrx = vm.envOr("BASE_IDRX", address(0));

        uint256 usdcDec = vm.envOr("BASE_USDC_DECIMAL", uint256(0));
        uint256 usdeDec = vm.envOr("BASE_USDE_DECIMAL", uint256(0));
        uint256 wethDec = vm.envOr("BASE_WETH_DECIMAL", uint256(0));
        uint256 cbethDec = vm.envOr("BASE_CBETH_DECIMAL", uint256(0));
        uint256 cbbtcDec = vm.envOr("BASE_CBBTC_DECIMAL", uint256(0));
        uint256 wbtcDec = vm.envOr("BASE_WBTC_DECIMAL", uint256(0));
        uint256 idrxDec = vm.envOr("BASE_IDRX_DECIMAL", uint256(0));

        vm.startBroadcast(pk);

        TokenRegistry registry = new TokenRegistry();

        if (usdc != address(0)) registry.setTokenSupport(usdc, true);
        if (usde != address(0)) registry.setTokenSupport(usde, true);
        if (weth != address(0)) registry.setTokenSupport(weth, true);
        if (cbeth != address(0)) registry.setTokenSupport(cbeth, true);
        if (cbbtc != address(0)) registry.setTokenSupport(cbbtc, true);
        if (wbtc != address(0)) registry.setTokenSupport(wbtc, true);
        if (idrx != address(0)) registry.setTokenSupport(idrx, true);

        if (usdc != address(0) && usdcDec > 0) registry.setTokenDecimals(usdc, uint8(usdcDec));
        if (usde != address(0) && usdeDec > 0) registry.setTokenDecimals(usde, uint8(usdeDec));
        if (weth != address(0) && wethDec > 0) registry.setTokenDecimals(weth, uint8(wethDec));
        if (cbeth != address(0) && cbethDec > 0) registry.setTokenDecimals(cbeth, uint8(cbethDec));
        if (cbbtc != address(0) && cbbtcDec > 0) registry.setTokenDecimals(cbbtc, uint8(cbbtcDec));
        if (wbtc != address(0) && wbtcDec > 0) registry.setTokenDecimals(wbtc, uint8(wbtcDec));
        if (idrx != address(0) && idrxDec > 0) registry.setTokenDecimals(idrx, uint8(idrxDec));

        vm.stopBroadcast();

        console2.log("Base TokenRegistry V2 deployed:", address(registry));
    }
}
