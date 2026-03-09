// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/ccip/Client.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "../src/integrations/layerzero/LayerZeroReceiverAdapter.sol";
import "../src/integrations/layerzero/OApp.sol";

contract MockTokenPF is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockGatewayPF {
    address public vaultAddress;
    mapping(bytes32 => address) public privacyStealthByPayment;

    bool public shouldFinalizeForwardRevert;
    bool public finalizeIncomingCalled;
    bool public finalizePrivacyForwardCalled;
    bool public reportPrivacyForwardFailureCalled;

    bytes32 public lastPaymentId;
    address public lastReceiver;
    address public lastToken;
    uint256 public lastAmount;

    constructor(address _vaultAddress) {
        vaultAddress = _vaultAddress;
    }

    function vault() external view returns (PaymentKitaVault) {
        return PaymentKitaVault(vaultAddress);
    }

    function setPrivacyStealth(bytes32 paymentId, address stealth) external {
        privacyStealthByPayment[paymentId] = stealth;
    }

    function setFinalizeForwardRevert(bool shouldRevert) external {
        shouldFinalizeForwardRevert = shouldRevert;
    }

    function finalizeIncomingPayment(bytes32 paymentId, address receiver, address token, uint256 amount) external {
        finalizeIncomingCalled = true;
        lastPaymentId = paymentId;
        lastReceiver = receiver;
        lastToken = token;
        lastAmount = amount;
    }

    function finalizePrivacyForward(bytes32 paymentId, address token, uint256 amount) external {
        if (shouldFinalizeForwardRevert) {
            revert("FORWARD_FAIL");
        }
        finalizePrivacyForwardCalled = true;
        lastPaymentId = paymentId;
        lastToken = token;
        lastAmount = amount;
    }

    function reportPrivacyForwardFailure(bytes32 paymentId, string calldata) external {
        reportPrivacyForwardFailureCalled = true;
        lastPaymentId = paymentId;
    }
}

contract PrivacyForwardAdaptersPhase2Test is Test {
    uint64 internal constant CCIP_SRC = 111;
    uint32 internal constant LZ_SRC = 30111;

    function _buildCcipMessage(
        bytes32 paymentId,
        address token,
        address receiver,
        uint256 amount
    ) internal pure returns (Client.Any2EVMMessage memory msgIn) {
        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        msgIn = Client.Any2EVMMessage({
            messageId: keccak256("ccip-msg"),
            sourceChainSelector: CCIP_SRC,
            sender: abi.encode(address(0xA11CE)),
            data: abi.encode(paymentId, token, receiver, uint256(0), token),
            destTokenAmounts: amounts
        });
    }

    function testPhase2_CCIP_PrivacyForwardSuccess() public {
        PaymentKitaVault vault = new PaymentKitaVault();
        MockGatewayPF gateway = new MockGatewayPF(address(vault));
        address ccipRouter = address(0xCC11);

        CCIPReceiverAdapter receiver = new CCIPReceiverAdapter(ccipRouter, address(gateway));
        receiver.setTrustedSender(CCIP_SRC, abi.encode(address(0xA11CE)));

        bytes32 paymentId = keccak256("pid-ccip-success");
        address stealth = address(0xABCD);

        gateway.setPrivacyStealth(paymentId, stealth);

        MockTokenPF token = new MockTokenPF("T", "T");
        token.mint(address(receiver), 100 ether);

        Client.Any2EVMMessage memory msgIn = _buildCcipMessage(paymentId, address(token), stealth, 100 ether);

        vm.prank(ccipRouter);
        receiver.ccipReceive(msgIn);

        assertTrue(gateway.finalizeIncomingCalled());
        assertTrue(gateway.finalizePrivacyForwardCalled());
        assertFalse(gateway.reportPrivacyForwardFailureCalled());
    }

    function testPhase2_CCIP_PrivacyForwardFailureReports() public {
        PaymentKitaVault vault = new PaymentKitaVault();
        MockGatewayPF gateway = new MockGatewayPF(address(vault));
        address ccipRouter = address(0xCC11);

        CCIPReceiverAdapter receiver = new CCIPReceiverAdapter(ccipRouter, address(gateway));
        receiver.setTrustedSender(CCIP_SRC, abi.encode(address(0xA11CE)));

        bytes32 paymentId = keccak256("pid-ccip-fail");
        address stealth = address(0xDEAD);

        gateway.setPrivacyStealth(paymentId, stealth);
        gateway.setFinalizeForwardRevert(true);

        MockTokenPF token = new MockTokenPF("T", "T");
        token.mint(address(receiver), 50 ether);

        Client.Any2EVMMessage memory msgIn = _buildCcipMessage(paymentId, address(token), stealth, 50 ether);

        vm.prank(ccipRouter);
        receiver.ccipReceive(msgIn);

        assertTrue(gateway.finalizeIncomingCalled());
        assertFalse(gateway.finalizePrivacyForwardCalled());
        assertTrue(gateway.reportPrivacyForwardFailureCalled());
    }

    function testPhase2_Hyperbridge_PrivacyForwardSuccess() public {
        PaymentKitaVault vault = new PaymentKitaVault();
        MockGatewayPF gateway = new MockGatewayPF(address(vault));

        HyperbridgeReceiver receiver = new HyperbridgeReceiver(address(this), address(gateway), address(vault));
        vault.setAuthorizedSpender(address(receiver), true);

        bytes memory sourceChain = bytes("EVM-8453");
        bytes memory trustedSender = abi.encode(address(0xBEEF));
        receiver.setTrustedSender(sourceChain, trustedSender);

        MockTokenPF token = new MockTokenPF("HB", "HB");
        token.mint(address(vault), 200 ether);

        bytes32 paymentId = keccak256("pid-hb");
        address stealth = address(0xCAFE);
        gateway.setPrivacyStealth(paymentId, stealth);

        PostRequest memory req;
        req.source = sourceChain;
        req.from = trustedSender;
        req.body = abi.encode(paymentId, uint256(10 ether), address(token), stealth, uint256(0), address(token));

        IncomingPostRequest memory incoming;
        incoming.request = req;

        receiver.onAccept(incoming);

        assertTrue(gateway.finalizeIncomingCalled());
        assertTrue(gateway.finalizePrivacyForwardCalled());
        assertFalse(gateway.reportPrivacyForwardFailureCalled());
    }

    function testPhase2_LayerZero_PrivacyForwardSuccess() public {
        PaymentKitaVault vault = new PaymentKitaVault();
        MockGatewayPF gateway = new MockGatewayPF(address(vault));

        LayerZeroReceiverAdapter receiver = new LayerZeroReceiverAdapter(address(this), address(gateway), address(vault));
        vault.setAuthorizedSpender(address(receiver), true);

        bytes32 peer = bytes32(uint256(uint160(address(0xD00D))));
        receiver.setPeer(LZ_SRC, peer);

        MockTokenPF token = new MockTokenPF("LZ", "LZ");
        token.mint(address(vault), 300 ether);

        bytes32 paymentId = keccak256("pid-lz");
        address stealth = address(0xB0B0);
        gateway.setPrivacyStealth(paymentId, stealth);

        bytes memory payload = abi.encode(paymentId, uint256(25 ether), address(token), stealth, uint256(0), address(token));
        OApp.Origin memory origin = OApp.Origin({srcEid: LZ_SRC, sender: peer, nonce: 1});

        receiver.lzReceive(origin, keccak256("guid-lz"), payload, address(0), bytes(""));

        assertTrue(gateway.finalizeIncomingCalled());
        assertTrue(gateway.finalizePrivacyForwardCalled());
        assertFalse(gateway.reportPrivacyForwardFailureCalled());
    }
}
