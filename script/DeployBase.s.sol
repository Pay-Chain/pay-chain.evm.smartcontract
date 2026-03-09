// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployCommon.s.sol";

contract DeployBase is DeployCommon {
    function run() public {
        address feeRecipient = vm.envAddress("FEE_RECIPIENT_ADDRESS");

        DeploymentConfig memory config = DeploymentConfig({
            ccipRouter: vm.envOr("BASE_CCIP_ROUTER", address(0)),
            hyperbridgeHost: vm.envOr("BASE_HYPERBRIDGE_HOST", address(0)),
            layerZeroEndpointV2: vm.envOr("BASE_LAYERZERO_ENDPOINT_V2", address(0)),
            uniswapUniversalRouter: vm.envOr("BASE_UNIVERSAL_ROUTER", address(0)),
            uniswapPoolManager: vm.envOr("BASE_POOL_MANAGER", address(0)),
            bridgeToken: vm.envOr("BASE_USDC", address(0)),
            feeRecipient: feeRecipient,
            enableSourceSideSwap: vm.envOr("BASE_ENABLE_SOURCE_SIDE_SWAP", vm.envOr("ENABLE_SOURCE_SIDE_SWAP", false))
        });

        console.log("Deploying to Base...");
        (, , TokenRegistry registry, TokenSwapper swapper) = deploySystem(config);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool strict = strictTokenRegistration();

        // 1. Register tokens + decimals (strict mode prevents silent missing env)
        address usdc = config.bridgeToken;
        address usde = vm.envOr("BASE_USDE", address(0));
        address weth = vm.envOr("BASE_WETH", address(0));
        address cbbtc = vm.envOr("BASE_CBBTC", address(0));
        address wbtc = vm.envOr("BASE_WBTC", address(0));
        address idrx = vm.envOr("BASE_IDRX", address(0));
        address cbeth = vm.envOr("BASE_CBETH", address(0));

        uint256 usdcDec = vm.envOr("BASE_USDC_DECIMAL", uint256(0));
        uint256 usdeDec = vm.envOr("BASE_USDE_DECIMAL", uint256(0));
        uint256 wethDec = vm.envOr("BASE_WETH_DECIMAL", uint256(0));
        uint256 cbethDec = vm.envOr("BASE_CBETH_DECIMAL", uint256(0));
        uint256 cbbtcDec = vm.envOr("BASE_CBBTC_DECIMAL", uint256(0));
        uint256 wbtcDec = vm.envOr("BASE_WBTC_DECIMAL", uint256(0));
        uint256 idrxDec = vm.envOr("BASE_IDRX_DECIMAL", uint256(0));

        registerTokenWithOptionalDecimals(registry, usdc, usdcDec, true, "BASE_USDC", "BASE_USDC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, usde, usdeDec, strict, "BASE_USDE", "BASE_USDE_DECIMAL");
        registerTokenWithOptionalDecimals(registry, weth, wethDec, strict, "BASE_WETH", "BASE_WETH_DECIMAL");
        registerTokenWithOptionalDecimals(registry, cbeth, cbethDec, strict, "BASE_CBETH", "BASE_CBETH_DECIMAL");
        registerTokenWithOptionalDecimals(registry, cbbtc, cbbtcDec, strict, "BASE_CBBTC", "BASE_CBBTC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, wbtc, wbtcDec, strict, "BASE_WBTC", "BASE_WBTC_DECIMAL");
        registerTokenWithOptionalDecimals(registry, idrx, idrxDec, strict, "BASE_IDRX", "BASE_IDRX_DECIMAL");

        // 2. Configure V3 Pools on Swapper
        if (idrx != address(0) && usdc != address(0)) {
            swapper.setV3Pool(idrx, usdc, 100);
            console.log("Configured IDRX/USDC V3 pool");
        }
        if (usdc != address(0) && weth != address(0)) {
            swapper.setV3Pool(usdc, weth, 100);
            console.log("Configured USDC/WETH V3 pool");
        }
        if (usdc != address(0) && cbbtc != address(0)) {
            swapper.setV3Pool(usdc, cbbtc, 500);
            console.log("Configured USDC/cbBTC V3 pool");
        }
        if (usdc != address(0) && usde != address(0)) {
            swapper.setV3Pool(usdc, usde, 100);
            console.log("Configured USDC/USDe V3 pool");
        }

        // 3. Configure Multi-hop Paths
        if (usdc != address(0) && cbbtc != address(0) && wbtc != address(0)) {
            address[] memory pathUsdcWbtc = new address[](3);
            pathUsdcWbtc[0] = usdc;
            pathUsdcWbtc[1] = cbbtc;
            pathUsdcWbtc[2] = wbtc;
            swapper.setMultiHopPath(usdc, wbtc, pathUsdcWbtc);
            console.log("Configured USDC -> cbBTC -> WBTC");
        }
        if (usdc != address(0) && weth != address(0) && cbeth != address(0)) {
            address[] memory pathUsdcCbeth = new address[](3);
            pathUsdcCbeth[0] = usdc;
            pathUsdcCbeth[1] = weth;
            pathUsdcCbeth[2] = cbeth;
            swapper.setMultiHopPath(usdc, cbeth, pathUsdcCbeth);
            console.log("Configured USDC -> WETH -> cbETH");
        }
        if (wbtc != address(0) && cbbtc != address(0) && usdc != address(0) && idrx != address(0)) {
            address[] memory pathWbtcIdrx = new address[](4);
            pathWbtcIdrx[0] = wbtc;
            pathWbtcIdrx[1] = cbbtc;
            pathWbtcIdrx[2] = usdc;
            pathWbtcIdrx[3] = idrx;
            swapper.setMultiHopPath(wbtc, idrx, pathWbtcIdrx);
            console.log("Configured WBTC -> cbBTC -> USDC -> IDRX");
        }
        if (cbeth != address(0) && weth != address(0) && usdc != address(0) && idrx != address(0)) {
            address[] memory pathCbethIdrx = new address[](4);
            pathCbethIdrx[0] = cbeth;
            pathCbethIdrx[1] = weth;
            pathCbethIdrx[2] = usdc;
            pathCbethIdrx[3] = idrx;
            swapper.setMultiHopPath(cbeth, idrx, pathCbethIdrx);
            console.log("Configured cbETH -> WETH -> USDC -> IDRX");
        }
        if (idrx != address(0) && weth != address(0)) {
            address[] memory pathIdrxWeth = new address[](3);
            pathIdrxWeth[0] = idrx;
            pathIdrxWeth[1] = usdc;
            pathIdrxWeth[2] = weth;
            swapper.setMultiHopPath(idrx, weth, pathIdrxWeth);
            console.log("Configured IDRX -> USDC -> WETH");
        }
        if (idrx != address(0) && usde != address(0)) {
            address[] memory pathIdrxUsde = new address[](3);
            pathIdrxUsde[0] = idrx;
            pathIdrxUsde[1] = usdc;
            pathIdrxUsde[2] = usde;
            swapper.setMultiHopPath(idrx, usde, pathIdrxUsde);
            console.log("Configured IDRX -> USDC -> USDe");
        }

        vm.stopBroadcast();
        console.log("Deployment and configuration on Base complete.");
    }
}
