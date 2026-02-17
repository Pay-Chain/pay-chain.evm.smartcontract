// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/layerzero/LayerZeroSenderAdapter.sol";
import "../src/integrations/layerzero/LayerZeroReceiverAdapter.sol";
import "../src/vaults/PayChainVault.sol";
import "../src/PayChainGateway.sol";
import "../src/PayChainRouter.sol";
import "../src/TokenRegistry.sol";
import "../src/integrations/ccip/Client.sol";
import {IncomingPostRequest} from "@hyperbridge/core/interfaces/IApp.sol";
import {PostRequest} from "@hyperbridge/core/libraries/Message.sol";
import {DispatchPost} from "@hyperbridge/core/interfaces/IDispatcher.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MKT") {
        _mint(msg.sender, 10_000_000 ether);
    }
}

contract MockHBUniswapRouter {
    address public immutable weth;
    uint256 public multiplier;

    constructor(address _weth, uint256 _multiplier) {
        weth = _weth;
        multiplier = _multiplier;
    }

    function WETH() external view returns (address) {
        return weth;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountOut * multiplier;
        amounts[1] = amountOut;
    }
}

contract MockHyperbridgeDispatcher {
    address public immutable feeTokenAddress;
    address public immutable routerAddress;
    uint256 public perByte;
    uint256 public lastFeeTokenAmount;
    uint256 public lastNativeValue;
    bytes public lastDest;
    bytes public lastTo;
    address public lastPayer;

    constructor(address _feeTokenAddress, address _routerAddress, uint256 _perByte) {
        feeTokenAddress = _feeTokenAddress;
        routerAddress = _routerAddress;
        perByte = _perByte;
    }

    function uniswapV2Router() external view returns (address) {
        return routerAddress;
    }

    function feeToken() external view returns (address) {
        return feeTokenAddress;
    }

    function perByteFee(bytes memory) external view returns (uint256) {
        return perByte;
    }

    function dispatch(DispatchPost memory request) external payable returns (bytes32 commitment) {
        lastFeeTokenAmount = request.fee;
        lastNativeValue = msg.value;
        lastDest = request.dest;
        lastTo = request.to;
        lastPayer = request.payer;
        return keccak256(abi.encode(request.dest, request.to, request.body, request.fee, msg.value, block.timestamp));
    }
}

contract MockHyperbridgeDispatcherNoRouter {
    address public immutable feeTokenAddress;
    uint256 public perByte;

    constructor(address _feeTokenAddress, uint256 _perByte) {
        feeTokenAddress = _feeTokenAddress;
        perByte = _perByte;
    }

    function uniswapV2Router() external pure returns (address) {
        return address(0);
    }

    function feeToken() external view returns (address) {
        return feeTokenAddress;
    }

    function perByteFee(bytes memory) external view returns (uint256) {
        return perByte;
    }
}

contract MockLZEndpoint is ILayerZeroEndpointV2 {
    uint256 public quoteNativeFee = 1e15;
    uint256 public quoteLzFee;
    bytes32 public lastGuid;
    uint64 public nonce;

    function setQuoteNativeFee(uint256 fee) external {
        quoteNativeFee = fee;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: quoteLzFee});
    }

    function send(
        MessagingParams calldata params,
        address
    ) external payable returns (MessagingReceipt memory) {
        nonce += 1;
        lastGuid = keccak256(abi.encode(params.dstEid, params.receiver, params.message, nonce, msg.value));
        return MessagingReceipt({
            guid: lastGuid,
            nonce: nonce,
            fee: MessagingFee({nativeFee: msg.value, lzTokenFee: 0})
        });
    }
}

contract BridgeAdaptersTest is Test {
    string internal constant DEST_CAIP2 = "eip155:42161";

    function _buildMessage(
        address sourceToken,
        address destToken
    ) internal pure returns (IBridgeAdapter.BridgeMessage memory message) {
        message = IBridgeAdapter.BridgeMessage({
            paymentId: keccak256("payment"),
            receiver: address(0xBEEF),
            sourceToken: sourceToken,
            destToken: destToken,
            amount: 1000,
            destChainId: DEST_CAIP2,
            minAmountOut: 900
        });
    }

    function testHyperbridgeQuoteAndSendMessage() public {
        MockToken feeToken = new MockToken();
        MockHBUniswapRouter uni = new MockHBUniswapRouter(address(0xEeee), 3);
        MockHyperbridgeDispatcher dispatcher = new MockHyperbridgeDispatcher(address(feeToken), address(uni), 2);
        PayChainVault vault = new PayChainVault();
        HyperbridgeSender sender = new HyperbridgeSender(address(vault), address(dispatcher));

        sender.setStateMachineId(DEST_CAIP2, hex"45564d2d3432313631");
        sender.setDestinationContract(DEST_CAIP2, hex"0000000000000000000000001111111111111111111111111111111111111111");

        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(feeToken), address(feeToken));
        uint256 quotedNative = sender.quoteFee(m);
        assertTrue(quotedNative > 0);

        vm.expectRevert();
        sender.sendMessage{value: quotedNative - 1}(m);

        bytes32 messageId = sender.sendMessage{value: quotedNative}(m);
        assertTrue(messageId != bytes32(0));
        assertEq(dispatcher.lastNativeValue(), quotedNative);
        assertEq(dispatcher.lastPayer(), address(this));
        assertTrue(dispatcher.lastFeeTokenAmount() > 0);
    }

    function testHyperbridgeRouteConfigStatus() public {
        MockToken feeToken = new MockToken();
        MockHBUniswapRouter uni = new MockHBUniswapRouter(address(0xEeee), 2);
        MockHyperbridgeDispatcher dispatcher = new MockHyperbridgeDispatcher(address(feeToken), address(uni), 1);
        PayChainVault vault = new PayChainVault();
        HyperbridgeSender sender = new HyperbridgeSender(address(vault), address(dispatcher));

        assertFalse(sender.isRouteConfigured(DEST_CAIP2));

        sender.setStateMachineId(DEST_CAIP2, hex"45564d2d3432313631");
        assertFalse(sender.isRouteConfigured(DEST_CAIP2));

        sender.setDestinationContract(DEST_CAIP2, hex"1234");
        assertTrue(sender.isRouteConfigured(DEST_CAIP2));
    }

    function testHyperbridgeQuoteRevertsWhenNativeQuoteUnavailable() public {
        MockToken feeToken = new MockToken();
        MockHyperbridgeDispatcherNoRouter dispatcher = new MockHyperbridgeDispatcherNoRouter(address(feeToken), 2);
        PayChainVault vault = new PayChainVault();
        HyperbridgeSender sender = new HyperbridgeSender(address(vault), address(dispatcher));

        sender.setStateMachineId(DEST_CAIP2, hex"45564d2d3432313631");
        sender.setDestinationContract(DEST_CAIP2, hex"1234");

        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(feeToken), address(feeToken));
        vm.expectRevert(HyperbridgeSender.NativeFeeQuoteUnavailable.selector);
        sender.quoteFee(m);
    }

    function testRouterQuotePaymentFeeSafeReturnsRouteNotConfigured() public {
        MockToken feeToken = new MockToken();
        MockHBUniswapRouter uni = new MockHBUniswapRouter(address(0xEeee), 2);
        MockHyperbridgeDispatcher dispatcher = new MockHyperbridgeDispatcher(address(feeToken), address(uni), 1);
        PayChainVault vault = new PayChainVault();
        HyperbridgeSender sender = new HyperbridgeSender(address(vault), address(dispatcher));
        PayChainRouter router = new PayChainRouter();

        router.registerAdapter(DEST_CAIP2, 0, address(sender));

        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(feeToken), address(feeToken));
        (bool ok, uint256 fee, string memory reason) = router.quotePaymentFeeSafe(DEST_CAIP2, 0, m);
        assertFalse(ok);
        assertEq(fee, 0);
        assertEq(reason, "route_not_configured");
    }

    function testRouterQuotePaymentFeeSafeReturnsFeeWhenConfigured() public {
        MockToken feeToken = new MockToken();
        MockHBUniswapRouter uni = new MockHBUniswapRouter(address(0xEeee), 2);
        MockHyperbridgeDispatcher dispatcher = new MockHyperbridgeDispatcher(address(feeToken), address(uni), 1);
        PayChainVault vault = new PayChainVault();
        HyperbridgeSender sender = new HyperbridgeSender(address(vault), address(dispatcher));
        PayChainRouter router = new PayChainRouter();

        sender.setStateMachineId(DEST_CAIP2, hex"45564d2d3432313631");
        sender.setDestinationContract(DEST_CAIP2, hex"0000000000000000000000001111111111111111111111111111111111111111");
        router.registerAdapter(DEST_CAIP2, 0, address(sender));

        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(feeToken), address(feeToken));
        (bool ok, uint256 fee, string memory reason) = router.quotePaymentFeeSafe(DEST_CAIP2, 0, m);
        assertTrue(ok);
        assertTrue(fee > 0);
        assertEq(reason, "");
    }

    function testLayerZeroSenderQuoteAndSend() public {
        MockLZEndpoint endpoint = new MockLZEndpoint();
        LayerZeroSenderAdapter sender = new LayerZeroSenderAdapter(address(endpoint));

        sender.setRoute(DEST_CAIP2, 30110, bytes32(uint256(uint160(address(0xCAFE)))));
        sender.setEnforcedOptions(DEST_CAIP2, hex"0001");

        MockToken token = new MockToken();
        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(token), address(token));
        uint256 quotedNative = sender.quoteFee(m);
        assertEq(quotedNative, endpoint.quoteNativeFee());

        vm.expectRevert();
        sender.sendMessage{value: quotedNative - 1}(m);

        bytes32 guid = sender.sendMessage{value: quotedNative}(m);
        assertEq(guid, endpoint.lastGuid());
    }

    function testLayerZeroSenderRevertsWhenRouteMissing() public {
        MockLZEndpoint endpoint = new MockLZEndpoint();
        LayerZeroSenderAdapter sender = new LayerZeroSenderAdapter(address(endpoint));

        MockToken token = new MockToken();
        IBridgeAdapter.BridgeMessage memory m = _buildMessage(address(token), address(token));

        vm.expectRevert();
        sender.quoteFee(m);

        vm.expectRevert();
        sender.sendMessage{value: 1}(m);
    }

    function testLayerZeroReceiverAcceptsTrustedMessageAndReleasesFunds() public {
        MockLZEndpoint endpoint = new MockLZEndpoint();
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));
        LayerZeroReceiverAdapter receiver = new LayerZeroReceiverAdapter(address(endpoint), address(gateway), address(vault));

        MockToken token = new MockToken();
        require(token.transfer(address(vault), 1_000_000), "fund vault lz failed");
        vault.setAuthorizedSpender(address(receiver), true);

        uint32 srcEid = 30111;
        bytes32 peer = bytes32(uint256(uint160(address(0xABCD))));
        receiver.setTrustedPeer(srcEid, peer);

        address payoutReceiver = address(0xBEEF);
        uint256 amount = 10_000;
        bytes memory payload = abi.encode(keccak256("pid"), amount, address(token), payoutReceiver, uint256(0));

        vm.prank(address(endpoint));
        receiver.lzReceive(srcEid, peer, payload);

        assertEq(token.balanceOf(payoutReceiver), amount);
    }

    function testLayerZeroReceiverRevertsForUntrustedPeer() public {
        MockLZEndpoint endpoint = new MockLZEndpoint();
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));
        LayerZeroReceiverAdapter receiver = new LayerZeroReceiverAdapter(address(endpoint), address(gateway), address(vault));

        receiver.setTrustedPeer(30111, bytes32(uint256(uint160(address(0xABCD)))));

        vm.prank(address(endpoint));
        vm.expectRevert();
        receiver.lzReceive(30111, bytes32(uint256(uint160(address(0xDCBA)))), abi.encode(bytes32(0), uint256(0), address(0), address(0), uint256(0)));
    }

    function testCCIPReceiverAdapterRevertsIfNotRouter() public {
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));

        address ccipRouter = address(0xC0FFEE);
        CCIPReceiverAdapter receiver = new CCIPReceiverAdapter(ccipRouter, address(gateway));

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(0x1), amount: 1});
        Client.Any2EVMMessage memory msgObj = Client.Any2EVMMessage({
            messageId: keccak256("x"),
            sourceChainSelector: 1,
            sender: abi.encode(address(0x2)),
            data: abi.encode(keccak256("pid"), address(0x1), address(0x3)),
            destTokenAmounts: tokenAmounts
        });

        vm.expectRevert();
        receiver.ccipReceive(msgObj);
    }

    function testCCIPReceiverAdapterRevertsOnTokenMismatch() public {
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));

        address ccipRouter = address(0xC0FFEE);
        CCIPReceiverAdapter receiver = new CCIPReceiverAdapter(ccipRouter, address(gateway));

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(0x1111), amount: 1});
        Client.Any2EVMMessage memory msgObj = Client.Any2EVMMessage({
            messageId: keccak256("x"),
            sourceChainSelector: 1,
            sender: abi.encode(address(0x2)),
            data: abi.encode(keccak256("pid"), address(0x2222), address(0x3)),
            destTokenAmounts: tokenAmounts
        });

        vm.prank(ccipRouter);
        vm.expectRevert(bytes("Token Mismatch"));
        receiver.ccipReceive(msgObj);
    }

    function testHyperbridgeReceiverRevertsIfNotHost() public {
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));

        address hostAddress = address(0x9999);
        HyperbridgeReceiver receiver = new HyperbridgeReceiver(hostAddress, address(gateway), address(vault));

        IncomingPostRequest memory req = IncomingPostRequest({
            request: PostRequest({
                source: bytes("EVM-8453"),
                dest: bytes("EVM-42161"),
                nonce: 1,
                from: abi.encode(address(0x1)),
                to: abi.encode(address(receiver)),
                timeoutTimestamp: uint64(block.timestamp + 3600),
                body: abi.encode(keccak256("pid"), uint256(1), address(0x1), address(0x2))
            }),
            relayer: address(0xB0B)
        });

        vm.expectRevert(bytes("Not host"));
        receiver.onAccept(req);
    }

    function testHyperbridgeReceiverAcceptsFromHostAndReleasesLiquidity() public {
        PayChainVault vault = new PayChainVault();
        PayChainRouter router = new PayChainRouter();
        TokenRegistry registry = new TokenRegistry();
        PayChainGateway gateway = new PayChainGateway(address(vault), address(router), address(registry), address(this));

        address hostAddress = address(0x9999);
        HyperbridgeReceiver receiver = new HyperbridgeReceiver(hostAddress, address(gateway), address(vault));
        vault.setAuthorizedSpender(address(receiver), true);

        MockToken token = new MockToken();
        require(token.transfer(address(vault), 1_000_000), "fund vault hb failed");

        address payout = address(0xABCD);
        uint256 amount = 12345;
        IncomingPostRequest memory req = IncomingPostRequest({
            request: PostRequest({
                source: bytes("EVM-8453"),
                dest: bytes("EVM-42161"),
                nonce: 1,
                from: abi.encode(address(0x1)),
                to: abi.encode(address(receiver)),
                timeoutTimestamp: uint64(block.timestamp + 3600),
                body: abi.encode(keccak256("pid"), amount, address(token), payout)
            }),
            relayer: address(0xB0B)
        });

        vm.prank(hostAddress);
        receiver.onAccept(req);

        assertEq(token.balanceOf(payout), amount);
    }
}
