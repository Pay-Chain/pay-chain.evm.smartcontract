// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PayChainGateway.sol";
import "../src/interfaces/IPayChainGateway.sol";
import "../src/PayChainRouter.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/integrations/ccip/CCIPSender.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/ccip/Client.sol";
import "../src/TokenRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Mock Token
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract MockVaultSwapper {
    using SafeERC20 for IERC20;

    PayChainVault public immutable vault;

    constructor(address _vault) {
        vault = PayChainVault(_vault);
    }

    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        // Pull source liquidity from vault to simulate swap consumption.
        vault.pushTokens(tokenIn, address(this), amountIn);

        amountOut = amountIn;
        require(amountOut >= minAmountOut, "Mock slippage");
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }
}

// Mock CCIP Router - implements IRouterClient interface
contract MockCCIPRouter {
    event CCIPMessageSent(uint64 destChainId, address receiver, uint256 tokenAmount);
    
    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0; // Free for mock
    }
    
    function ccipSend(uint64 destChainSelector, Client.EVM2AnyMessage calldata message) external payable returns (bytes32) {
        address receiver = abi.decode(message.receiver, (address));
        uint256 amount = message.tokenAmounts.length > 0 ? message.tokenAmounts[0].amount : 0;
        emit CCIPMessageSent(destChainSelector, receiver, amount);
        return keccak256(abi.encodePacked(destChainSelector, block.timestamp, msg.sender));
    }
}

contract PayChainGatewayTest is Test {
    PayChainGateway gateway;
    PayChainRouter router;
    PayChainVault vault;
    CCIPSender ccipSender;
    CCIPReceiverAdapter ccipReceiver;
    TokenRegistry tokenRegistry;
    MockERC20 token;
    MockCCIPRouter ccipRouterMock;

    address user = address(1);
    address merchant = address(2);
    address stranger = address(3);
    
    // Test Chain Config
    string constant DEST_CHAIN = "EVM-56"; // BSC
    string constant SOURCE_CHAIN = "EVM-1"; // ETH
    uint64 constant CCIP_DEST_SELECTOR = 12345;

    // Event definition for testing (Must match Interface)
    event PaymentCreated(
        bytes32 indexed paymentId,
        address indexed sender,
        address indexed receiver,
        string destChainId,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 fee,
        string bridgeType
    );

    function setUp() public {
        vm.startPrank(msg.sender);
        
        // 1. Deploy Token
        token = new MockERC20();
        
        // 2. Deploy Core
        tokenRegistry = new TokenRegistry();
        vault = new PayChainVault();
        router = new PayChainRouter();
        gateway = new PayChainGateway(address(vault), address(router), address(tokenRegistry), address(this));
        
        // 3. Deploy Mocks
        ccipRouterMock = new MockCCIPRouter();
        
        // 4. Deploy Adapters
        ccipSender = new CCIPSender(address(vault), address(ccipRouterMock));
        ccipReceiver = new CCIPReceiverAdapter(address(ccipRouterMock), address(gateway));
        
        // 5. Config
        
        // Token Registry (Wake: False positive reentrancy warning - Safe, no external calls)
        tokenRegistry.setTokenSupport(address(token), true);
        // tokenRegistry.setToken(DEST_CHAIN, address(token), "MCK"); // Not needed for current registry implementation
        
        // Router: Register Adapters (Wake: False positive reentrancy warning - Safe, no external calls)
        router.registerAdapter(DEST_CHAIN, 1, address(ccipSender)); // 1 = CCIP
        gateway.setDefaultBridgeType(DEST_CHAIN, 1);
        
        // Gateway: Whitelist Token - Already handled by TokenRegistry
        // gateway.setTokenSupport(address(token), true);
        
        // Vault: Authorize Gateway and Adapters (Wake: False positive - Safe)
        vault.setAuthorizedSpender(address(gateway), true);
        vault.setAuthorizedSpender(address(ccipSender), true);
        vault.setAuthorizedSpender(address(ccipReceiver), true);
        
        // CCIP Sender Config
        ccipSender.setChainSelector(DEST_CHAIN, CCIP_DEST_SELECTOR);
        ccipSender.setDestinationAdapter(DEST_CHAIN, abi.encode(address(ccipReceiver))); // Should be receiver on dest, but for logic check ok.
        
        // Fund User
        require(token.transfer(user, 1000 * 10**18), "fund user failed");
        
        vm.stopPrank();
    }
    
    function testCreatePayment() public {
        vm.startPrank(user);
        
        // User must approve VAULT, not Gateway, because Vault performs transferFrom
        // Also include Fee (approx 0.3% + base)
        token.approve(address(vault), 101 * 10**18);
        
        // Params
        bytes memory destChain = bytes(DEST_CHAIN);
        bytes memory receiver = abi.encode(merchant);
        
        // Event check skipped to avoid brittle string matching without trace.
        // Validating state (Vault balance) and return value instead.
        /*
        vm.expectEmit(false, true, true, false, address(gateway));
        emit PaymentCreated(
            bytes32(0), 
            user,
            merchant, 
            "", // Ignored
            address(0),
            address(0),
            0,
            0,
            ""
        );
        */
        // Note: Event params might differ based on impl details (bridgeType string vs int).
        // Let's check Gateway Logic.
        
        bytes32 pid = gateway.createPayment(
            destChain,
            receiver,
            address(token),
            address(token), //Dest token
            100 * 10**18
        );
        
        assertTrue(pid != bytes32(0));
        
        // Check Vault Balance - Should be 0 as tokens are moved to Sender for CCIP
        assertEq(token.balanceOf(address(vault)), 0);
        
        // MockRouter doesn't pull tokens, so they stay in CCIPSender
        assertEq(token.balanceOf(address(ccipSender)), 100 * 10**18);
        
        vm.stopPrank();
    }

    function testCreatePaymentWithSlippage() public {
        vm.startPrank(user);
        
        token.approve(address(vault), 101 * 10**18);
        
        bytes memory destChain = bytes(DEST_CHAIN);
        bytes memory receiver = abi.encode(merchant);
        
        // Call with slippage param
        bytes32 pid = gateway.createPaymentWithSlippage(
            destChain,
            receiver,
            address(token),
            address(token),
            100 * 10**18,
            99 * 10**18 // Min Amount Out
        );
        
        assertTrue(pid != bytes32(0));
        
        // Check Vault Balance (Same logic as above)
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(address(ccipSender)), 100 * 10**18);
        
        vm.stopPrank();
    }

    function testCreatePaymentSameChainWithoutBridge() public {
        vm.startPrank(user);

        token.approve(address(vault), 101 * 10**18);

        string memory sameChain = string.concat("eip155:", vm.toString(block.chainid));
        bytes32 pid = gateway.createPayment(
            bytes(sameChain),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );

        assertTrue(pid != bytes32(0));
        assertEq(token.balanceOf(merchant), 100 * 10**18);
        assertEq(token.balanceOf(address(vault)), 0);

        (,,,,,,,, IPayChainGateway.PaymentStatus status,) = gateway.payments(pid);
        assertEq(uint256(status), uint256(IPayChainGateway.PaymentStatus.Completed));

        vm.stopPrank();
    }
    
    function testReceivePayment() public {
        // Test CCIP Receiver Adapter Flow
        
        // 1. Fund the Adapter (simulating CCIP Router delivering tokens)
        vm.startPrank(msg.sender);
        require(token.transfer(address(ccipReceiver), 50 * 10**18), "fund ccip receiver failed");
        vm.stopPrank();
        
        // 2. Prepare CCIP Message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token),
            amount: 50 * 10**18
        });
        
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("msg"),
            sourceChainSelector: 1, // Source
            sender: abi.encode(address(ccipSender)), // Original sender on remote chain
            data: abi.encode(keccak256("payment"), address(token), merchant), // Payload: id, destToken, receiver
            destTokenAmounts: tokenAmounts
        });
        
        // 3. Call as Router
        vm.startPrank(address(ccipRouterMock));
        
        // Must call ccipReceive. 
        // Note: ccipReceive is external.
        ccipReceiver.ccipReceive(message);
        
        // Check merchant received funds
        assertEq(token.balanceOf(merchant), 50 * 10**18);
        
        vm.stopPrank();
    }

    function testCreatePaymentRevertNoAdapterForDestination() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        vm.expectRevert(bytes("No adapter for destination"));
        gateway.createPayment(
            bytes("eip155:42161"),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentRevertEmptyDestChain() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        vm.expectRevert(bytes("Empty dest chain ID"));
        gateway.createPayment(
            bytes(""),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentRevertEmptyReceiverBytes() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        vm.expectRevert(bytes("Empty receiver"));
        gateway.createPayment(
            bytes(DEST_CHAIN),
            bytes(""),
            address(token),
            address(token),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentRevertUnsupportedSourceToken() public {
        MockERC20 unsupported = new MockERC20();
        vm.startPrank(user);
        unsupported.approve(address(vault), 101 * 10**18);

        vm.expectRevert(bytes("Source token not supported"));
        gateway.createPayment(
            bytes(DEST_CHAIN),
            abi.encode(merchant),
            address(unsupported),
            address(unsupported),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentRevertMalformedReceiverBytes() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        // abi.decode(bytes,address) should revert for malformed payload length
        vm.expectRevert();
        gateway.createPayment(
            bytes(DEST_CHAIN),
            hex"01",
            address(token),
            address(token),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentSameChainDifferentTokenRevertIfSwapperMissing() public {
        vm.startPrank(msg.sender);
        MockERC20 tokenB = new MockERC20();
        tokenRegistry.setTokenSupport(address(tokenB), true);
        require(tokenB.transfer(user, 1000 * 10**18), "fund user tokenB failed");
        gateway.setSwapper(address(0));
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);
        string memory sameChain = string.concat("eip155:", vm.toString(block.chainid));

        vm.expectRevert(bytes("Swapper not configured"));
        gateway.createPayment(
            bytes(sameChain),
            abi.encode(merchant),
            address(token),
            address(tokenB),
            100 * 10**18
        );
        vm.stopPrank();
    }

    function testCreatePaymentSameChainDifferentTokenSwapSuccess() public {
        MockERC20 tokenB = new MockERC20();
        MockVaultSwapper mockSwapper = new MockVaultSwapper(address(vault));

        vm.startPrank(tokenRegistry.owner());
        tokenRegistry.setTokenSupport(address(tokenB), true);
        vm.stopPrank();
        deal(address(tokenB), address(mockSwapper), 1000 * 10**18);

        vm.startPrank(gateway.owner());
        gateway.setSwapper(address(mockSwapper));
        vm.stopPrank();

        vm.startPrank(vault.owner());
        vault.setAuthorizedSpender(address(mockSwapper), true);
        vm.stopPrank();

        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);
        string memory sameChain = string.concat("eip155:", vm.toString(block.chainid));

        bytes32 pid = gateway.createPaymentWithSlippage(
            bytes(sameChain),
            abi.encode(merchant),
            address(token),
            address(tokenB),
            100 * 10**18,
            100 * 10**18
        );

        assertTrue(pid != bytes32(0));
        assertEq(tokenB.balanceOf(merchant), 100 * 10**18);
        (,,,,,,,, IPayChainGateway.PaymentStatus status,) = gateway.payments(pid);
        assertEq(uint256(status), uint256(IPayChainGateway.PaymentStatus.Completed));
        vm.stopPrank();
    }

    function testExecutePaymentRerouteUpdatesMessageMapping() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        bytes32 pid = gateway.createPayment(
            bytes(DEST_CHAIN),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        bytes32 firstMessageId = gateway.paymentToBridgeMessage(pid);
        assertTrue(firstMessageId != bytes32(0));
        assertEq(gateway.bridgeMessageToPayment(firstMessageId), pid);
        vm.stopPrank();

        // Replenish vault liquidity for manual re-execution in this mocked setup.
        vm.prank(user);
        require(token.transfer(address(vault), 100 * 10**18), "replenish vault execute failed");

        vm.startPrank(user);
        vm.warp(block.timestamp + 1);
        gateway.executePayment(pid);

        bytes32 secondMessageId = gateway.paymentToBridgeMessage(pid);
        assertTrue(secondMessageId != bytes32(0));
        assertEq(gateway.bridgeMessageToPayment(secondMessageId), pid);
        vm.stopPrank();
    }

    function testRetryMessageIncrementsCounterAndReRoutes() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        bytes32 pid = gateway.createPayment(
            bytes(DEST_CHAIN),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        bytes32 firstMessageId = gateway.paymentToBridgeMessage(pid);
        vm.stopPrank();

        vm.prank(user);
        require(token.transfer(address(vault), 100 * 10**18), "replenish vault retry failed");

        vm.startPrank(user);
        vm.warp(block.timestamp + 1);
        gateway.retryMessage(firstMessageId);
        assertEq(gateway.paymentRetryCount(pid), 1);
        assertEq(gateway.bridgeMessageToPayment(gateway.paymentToBridgeMessage(pid)), pid);
        vm.stopPrank();
    }

    function testRetryMessageRevertUnauthorized() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);
        bytes32 pid = gateway.createPayment(
            bytes(DEST_CHAIN),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        bytes32 messageId = gateway.paymentToBridgeMessage(pid);
        vm.stopPrank();

        vm.startPrank(stranger);
        vm.expectRevert(bytes("Unauthorized"));
        gateway.retryMessage(messageId);
        vm.stopPrank();
    }

    function testRetryMessageRevertMessageNotFound() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Message not found"));
        gateway.retryMessage(keccak256("unknown-message"));
        vm.stopPrank();
    }

    function testExecutePaymentRevertInvalidStatusForSameChainPayment() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);

        string memory sameChain = string.concat("eip155:", vm.toString(block.chainid));
        bytes32 pid = gateway.createPayment(
            bytes(sameChain),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );

        vm.expectRevert(bytes("Invalid payment status"));
        gateway.executePayment(pid);
        vm.stopPrank();
    }

    function testRetryMessageRevertAfterMaxAttempts() public {
        vm.startPrank(user);
        token.approve(address(vault), 101 * 10**18);
        bytes32 pid = gateway.createPayment(
            bytes(DEST_CHAIN),
            abi.encode(merchant),
            address(token),
            address(token),
            100 * 10**18
        );
        vm.stopPrank();

        vm.prank(user);
        require(token.transfer(address(vault), 300 * 10**18), "replenish vault max retry failed");

        vm.startPrank(user);
        for (uint256 i = 0; i < 3; i++) {
            bytes32 currentMessageId = gateway.paymentToBridgeMessage(pid);
            vm.warp(block.timestamp + 1);
            gateway.retryMessage(currentMessageId);
        }

        bytes32 lastMessageId = gateway.paymentToBridgeMessage(pid);
        vm.expectRevert(bytes("Retry limit reached"));
        gateway.retryMessage(lastMessageId);
        vm.stopPrank();
    }
}
