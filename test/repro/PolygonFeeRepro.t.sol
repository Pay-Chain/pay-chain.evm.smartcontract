// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/PayChainRouter.sol";
import "../../src/interfaces/IBridgeAdapter.sol";

contract PolygonFeeRepro is Test {
    PayChainRouter router = PayChainRouter(0xb4a911eC34eDaaEFC393c52bbD926790B9219df4);
    string destChainId = "eip155:8453";
    uint8 bridgeType = 0; // Hyperbridge

    function setUp() public {
        vm.createSelectFork("https://polygon-bor.publicnode.com");
    }

    function test_repro_quotePaymentFee() public {
        IBridgeAdapter.BridgeMessage memory message = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(uint256(1)),
            receiver: address(0x01),
            sourceToken: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, // USDC
            destToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // Base USDC
            amount: 1000000,
            destChainId: destChainId,
            minAmountOut: 0
        });

        uint256 fee = router.quotePaymentFee(destChainId, bridgeType, message);
        console.log("Fee quoted:", fee);
    }
}
