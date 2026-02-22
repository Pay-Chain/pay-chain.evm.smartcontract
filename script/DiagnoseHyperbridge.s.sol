// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/TokenSwapper.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/PayChainGateway.sol";

contract DiagnoseHyperbridge is Script {
    address constant SENDER = 0xE6AFaA8334A1862845450B4a3fdE8cF57620faCd;
    address constant SWAPPER = 0x8fd8Df03D50514f9386a0adE7E6aEE4003399933;
    address constant GATEWAY = 0xBaB8d97Fbdf6788BF40B01C096CFB2cC661ba642;

    function run() external {
        HyperbridgeSender sender = HyperbridgeSender(payable(SENDER));
        TokenSwapper swapper = TokenSwapper(SWAPPER);
        
        address feeToken = sender.getFeeToken();
        console.log("Hyperbridge Fee Token:", feeToken);
        
        address senderSwapper = address(sender.swapper());
        console.log("Sender's Swapper:", senderSwapper);
        
        bool isAuthorized = swapper.authorizedCallers(SENDER);
        console.log("Sender Authorized in Swapper:", isAuthorized);
        
        address quoter = swapper.quoterV3();
        console.log("Swapper QuoterV3:", quoter);
        
        address weth = swapper.bridgeToken(); // Wait, bridgeToken is usually USDC? 
        // Let's check Uniswap V2 Router WETH
        address v2Router = sender.swapRouter();
        if (v2Router == address(0)) {
             v2Router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // Default used in my deploy script
        }
        address WETH = IUniswapV2Router02HB(v2Router).WETH();
        console.log("WETH Address:", WETH);

        bytes32 pairKey = keccak256(abi.encodePacked(WETH < feeToken ? WETH : feeToken, WETH < feeToken ? feeToken : WETH));
        (uint24 feeTier, bool active) = swapper.v3Pools(pairKey);
        console.log("V3 Pool (WETH/FeeToken) Active:", active);

        // Deploy a fresh swapper to test local code changes
        TokenSwapper freshSwapper = new TokenSwapper(
            swapper.universalRouter(),
            swapper.poolManager(),
            swapper.bridgeToken()
        );
        console.log("Fresh TokenSwapper deployed locally");

        freshSwapper.setAuthorizedCaller(SENDER, true);
        freshSwapper.setQuoterV3(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);
        freshSwapper.setV3Pool(WETH, feeToken, feeTier); // Use same pool config

        console.log("Testing fresh swapper...");
        uint256 amountOutView = freshSwapper.getQuote(WETH, feeToken, 1 ether);
        console.log("Fresh Swapper getQuote(WETH -> FeeToken):", amountOutView);

        try freshSwapper.getRealQuote(WETH, feeToken, 1 ether) returns (uint256 amountOutReal) {
            console.log("Fresh Swapper getRealQuote(WETH -> FeeToken):", amountOutReal);
        } catch {
            console.log("Fresh Swapper getRealQuote FAILED");
        }
    }
}
