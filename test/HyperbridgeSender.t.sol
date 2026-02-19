// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/vaults/PayChainVault.sol";

import "../src/interfaces/IBridgeAdapter.sol";



contract MockRouter is IUniswapV2Router02HB {
    address public weth;
    
    constructor(address _weth) {
        weth = _weth;
    }

    function WETH() external view returns (address) {
        return weth;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata /*path*/) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountOut; // 1:1 rate for simplicity
        amounts[1] = amountOut;
        return amounts;
    }
}

contract MockHost {
    address public uniswapV2Router;
    address public feeToken;
    mapping(bytes => uint256) public perByteFee;

    function setUniswapV2Router(address _router) external {
        uniswapV2Router = _router;
    }

    function setFeeToken(address _token) external {
        feeToken = _token;
    }

    function setPerByteFee(bytes calldata smId, uint256 fee) external {
        perByteFee[smId] = fee;
    }

    function dispatch(DispatchPost calldata post) external payable returns (bytes32) {
        return keccak256(abi.encode(post));
    }
    
    receive() external payable {}
}

contract MockVault is PayChainVault {
    constructor(address _token) PayChainVault() {}
}

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function totalSupply() external pure returns (uint256) { return 0; }
}

contract MockGateway {
    mapping(bytes32 => bool) public refundsProcessed;
    mapping(bytes32 => bool) public paymentsFailed;

    function markPaymentFailed(bytes32 paymentId, string calldata /*reason*/) external {
        paymentsFailed[paymentId] = true;
    }

    function processRefund(bytes32 paymentId) external {
        refundsProcessed[paymentId] = true;
    }
}

contract HyperbridgeSenderTest is Test {
    HyperbridgeSender sender;
    MockHost host;
    MockVault vault;
    MockERC20 token;
    MockRouter router;
    MockERC20 weth;
    MockGateway gateway;

    function setUp() public {
        token = new MockERC20();
        vault = new MockVault(address(token));
        host = new MockHost();
        gateway = new MockGateway();
        sender = new HyperbridgeSender(address(vault), address(host), address(gateway));
        
        weth = new MockERC20();
        router = new MockRouter(address(weth));
        host.setUniswapV2Router(address(router));
        host.setFeeToken(address(token)); // use token as fee token
    }

    function test_RevertIf_DestinationLengthInvalid() public {
        bytes memory invalidDest = new bytes(32); 
        vm.expectRevert("Invalid address length");
        sender.setDestinationContract("EVM-2", invalidDest);

        bytes memory invalidDest2 = new bytes(0);
        vm.expectRevert("Invalid address length");
        sender.setDestinationContract("EVM-2", invalidDest2);
    }

    function test_SetDestinationContract_Success() public {
        address validAddr = address(0x123);
        bytes memory validDest = abi.encodePacked(validAddr); // Should be 20 bytes
        assertEq(validDest.length, 20);

        sender.setDestinationContract("EVM-2", validDest);
        
        // Verify it was set
        bytes memory stored = sender.destinationContracts("EVM-2");
        assertEq(stored, validDest);
    }

    function test_SendMessage_RefundsExcess() public {
        address validAddr = address(0x123);
        bytes memory validDest = abi.encodePacked(validAddr);
        sender.setDestinationContract("EVM-2", validDest);
        sender.setStateMachineId("EVM-2", bytes("EVM-2"));
        
        host.setPerByteFee(bytes("EVM-2"), 1);

        IBridgeAdapter.BridgeMessage memory bridgeMsg = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(uint256(1)),
            receiver: address(0x123),
            sourceToken: address(0),
            destToken: address(0),
            amount: 100,
            destChainId: "EVM-2",
            minAmountOut: 0
        });

        // Calculate expected fee approximate
        // Message size ~ 500 bytes (body + 256)
        // Fee token amount ~ 500 * 1 = 500 wei
        // Native quote (via MockRouter 1:1) = 500 wei + 10% buffer = 550 wei.
        
        uint256 quotedFee = sender.quoteFee(bridgeMsg);
        
        // Send with strict excess
        uint256 sentValue = quotedFee + 1 ether;
        uint256 balanceBefore = address(this).balance;
        
        sender.sendMessage{value: sentValue}(bridgeMsg);
        
        uint256 balanceAfter = address(this).balance;
        
        // Expect balance to decrease by strictly quotedFee (plus gas, but logic is simplified in test environment if we don't track gas)
        // Actually forge test calls preserve balance unless spent?
        // Wait, 'address(this)' is the test contract.
        // It sends 'sentValue'.
        // It should receive 'sentValue - quotedFee' back.
        // So net cost should be 'quotedFee'.
        
        assertEq(balanceBefore - balanceAfter, quotedFee, "Should only pay quoted fee");
    }

    function test_OnPostRequestTimeout_TriggersRefund() public {
        bytes32 paymentId = keccak256("payment-timeout");
        bytes memory body = abi.encode(
            paymentId,
            uint256(100),
            address(0x1),
            address(0x2),
            uint256(0),
            address(0x3)
        );

        PostRequest memory request = PostRequest({
            source: bytes("EVM-1"),
            dest: bytes("EVM-2"),
            nonce: 1,
            from: bytes("sender"),
            to: bytes("receiver"),
            timeoutTimestamp: uint64(block.timestamp),
            body: body
        });

        vm.prank(address(host)); // Mock call from host
        sender.onPostRequestTimeout(request);

        assertTrue(gateway.paymentsFailed(paymentId));
        assertTrue(gateway.refundsProcessed(paymentId));
    }
    
    receive() external payable {}
}
