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

contract MockSwapper is ISwapperHB {
    uint256 public rate = 1; // 1 native = 1 feeToken
    bool public failSwap = false;
    uint256 public lastAmountIn;

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function setFailSwap(bool _fail) external {
        failSwap = _fail;
    }

    function getQuote(address /*tokenIn*/, address /*tokenOut*/, uint256 amountIn) external view override returns (uint256 amountOut) {
        return amountIn * rate;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient) external override returns (uint256 amountOut) {
        if (failSwap) revert("Swap failed");
        lastAmountIn = amountIn;
        amountOut = amountIn * rate;
        if (amountOut < minAmountOut) return 0;
        
        // Mock transfer feeToken to recipient
        MockERC20(tokenOut).mint(recipient, amountOut);
        // Burn WETH from sender
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        return amountOut;
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

    function transfer(address to, uint256 amount) external virtual returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external virtual returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function mint(address to, uint256 amount) external virtual {
        balanceOf[to] += amount;
    }

    function totalSupply() external pure virtual returns (uint256) { return 0; }
}

contract MockWETH is MockERC20, IWETHHB {
    function deposit() external payable override {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint wad) external override {
        balanceOf[msg.sender] -= wad;
        (bool success, ) = msg.sender.call{value: wad}("");
        require(success, "ETH transfer failed");
    }

    function approve(address spender, uint256 amount) external override(MockERC20, IWETHHB) returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
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
    MockWETH weth;
    MockGateway gateway;
    MockSwapper swapper;

    function setUp() public {
        token = new MockERC20();
        vault = new MockVault(address(token));
        host = new MockHost();
        gateway = new MockGateway();
        sender = new HyperbridgeSender(address(vault), address(host), address(gateway));
        
        weth = new MockWETH();
        router = new MockRouter(address(weth));
        host.setUniswapV2Router(address(router));
        host.setFeeToken(address(token)); // use token as fee token
        
        swapper = new MockSwapper();
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

    function test_SendMessage_WithSwapper_Success() public {
        sender.setSwapper(address(swapper));
        
        address validAddr = address(0x123);
        sender.setDestinationContract("EVM-2", abi.encodePacked(validAddr));
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

        uint256 quotedFee = sender.quoteFee(bridgeMsg);
        
        // Ensure swapper has tokens to give
        token.mint(address(swapper), 1000000); 

        uint256 balanceBefore = address(this).balance;
        sender.sendMessage{value: quotedFee}(bridgeMsg);
        uint256 balanceAfter = address(this).balance;

        assertEq(balanceBefore - balanceAfter, quotedFee);
        // Swapper should have received WETH
        assertEq(weth.balanceOf(address(swapper)), quotedFee);
    }

    function test_SendMessage_FallbackToV2_WhenSwapperFails() public {
        sender.setSwapper(address(swapper));
        swapper.setFailSwap(true);
        
        address validAddr = address(0x123);
        sender.setDestinationContract("EVM-2", abi.encodePacked(validAddr));
        sender.setStateMachineId("EVM-2", bytes("EVM-2"));
        host.setPerByteFee(bytes("EVM-2"), 1);

        IBridgeAdapter.BridgeMessage memory bridgeMsg = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(uint256(2)),
            receiver: address(0x123),
            sourceToken: address(0),
            destToken: address(0),
            amount: 100,
            destChainId: "EVM-2",
            minAmountOut: 0
        });

        uint256 quotedFee = sender.quoteFee(bridgeMsg);
        
        uint256 balanceBefore = address(this).balance;
        sender.sendMessage{value: quotedFee}(bridgeMsg);
        uint256 balanceAfter = address(this).balance;

        // Balance should still decrease by quotedFee because fallback uses ETH
        assertEq(balanceBefore - balanceAfter, quotedFee);
        // WETH should be 0 because it was unwrapped
        assertEq(weth.balanceOf(address(sender)), 0);
    }

    function test_SetSwapper_OnlyOwner() public {
        address newSwapper = address(0x456);
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0xdead)));
        sender.setSwapper(newSwapper);
        
        sender.setSwapper(newSwapper);
        assertEq(address(sender.swapper()), newSwapper);
    }
    
    receive() external payable {}
}
