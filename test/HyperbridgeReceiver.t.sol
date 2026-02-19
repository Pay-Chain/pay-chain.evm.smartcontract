// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "@hyperbridge/core/apps/HyperApp.sol";

contract MockPathway {}

contract MockGateway {
    function finalizeIncomingPayment(bytes32, address, address, uint256) external {}
    function markPaymentFailed(bytes32, string calldata) external {}
}

contract MockVault {
    function pushTokens(address, address, uint256) external {}
}

contract HyperbridgeReceiverTest is Test {
    HyperbridgeReceiver receiver;
    MockGateway gateway;
    MockVault vault;
    address host = makeAddr("host");
    address swapper = makeAddr("swapper");

    bytes constant SOURCE_CHAIN = bytes("EVM-1");
    bytes constant OTHER_CHAIN = bytes("EVM-2");
    bytes constant SENDER = hex"1111111111111111111111111111111111111111"; // 20 bytes
    bytes constant BAD_SENDER = hex"2222222222222222222222222222222222222222";

    function setUp() public {
        gateway = new MockGateway();
        vault = new MockVault();
        receiver = new HyperbridgeReceiver(host, address(gateway), address(vault));
        receiver.setSwapper(swapper);
    }

    function test_RevertIf_NotHost() public {
        IncomingPostRequest memory req;
        vm.expectRevert(HyperApp.UnauthorizedCall.selector);
        receiver.onAccept(req);
    }

    function test_RevertIf_SourceNotTrusted() public {
        vm.prank(host);
        
        // PostRequest with untrusted source
        PostRequest memory post;
        post.source = SOURCE_CHAIN;
        post.from = SENDER;
        post.body = abi.encode(bytes32(0), uint256(100), address(0), address(0), uint256(0), address(0));

        IncomingPostRequest memory req;
        req.request = post;

        vm.expectRevert("Source chain not trusted");
        receiver.onAccept(req);
    }

    function test_RevertIf_SenderNotTrusted() public {
        // Trust chain but verify sender
        receiver.setTrustedSender(SOURCE_CHAIN, SENDER);

        vm.prank(host);
        
        PostRequest memory post;
        post.source = SOURCE_CHAIN;
        post.from = BAD_SENDER; // Wrong sender
        post.body = abi.encode(bytes32(0), uint256(100), address(0), address(0), uint256(0), address(0));

        IncomingPostRequest memory req;
        req.request = post;

        vm.expectRevert("Unauthorized sender");
        receiver.onAccept(req);
    }

    function test_SuccessIf_Trusted() public {
        receiver.setTrustedSender(SOURCE_CHAIN, SENDER);

        vm.prank(host);
        
        PostRequest memory post;
        post.source = SOURCE_CHAIN;
        post.from = SENDER;
        // Valid body to pass decoding
        // forge-lint: disable-next-line(unsafe-typecast)
        post.body = abi.encode(bytes32("pid"), uint256(100), address(0x10), address(0x20), uint256(0), address(0));

        IncomingPostRequest memory req;
        req.request = post;

        // Mock vault call or expect it
        // Since we didn't mock vault, it might revert on vault.pushTokens call if addresses are random
        // but we just want to pass the security check.
        // We'll mock the vault call to maintain isolation if needed, but here let's see where it fails.
        // It should pass security checks and fail at vault interaction if anything.

        // Actually, we can just assert it does NOT revert with security errors.
        // Or we can mock the vault using `vm.mockCall`.


        receiver.onAccept(req);
    }
}
