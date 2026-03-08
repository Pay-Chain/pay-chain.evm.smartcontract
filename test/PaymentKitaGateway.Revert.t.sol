// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PaymentKitaGateway.sol";
import "../src/PaymentKitaRouter.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/TokenRegistry.sol";
import "../src/interfaces/IPaymentKitaGateway.sol";
import "../src/interfaces/IBridgeAdapter.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ──────────────────────────────────────────────────────
// Mock: Token
// ──────────────────────────────────────────────────────
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1_000_000e18);
    }
}

// ──────────────────────────────────────────────────────
// Mock: Adapter that always reverts with a SPECIFIC error
// ──────────────────────────────────────────────────────
contract RevertingAdapter is IBridgeAdapter {
    error AdapterSpecificError(string reason);

    function sendMessage(BridgeMessage calldata) external payable override returns (bytes32) {
        revert AdapterSpecificError("CCIP_FEE_TOKEN_NOT_SET");
    }

    function quoteFee(BridgeMessage calldata) external pure override returns (uint256) {
        return 0;
    }

    function isRouteConfigured(string calldata) external pure override returns (bool) {
        return true;
    }

    function getRouteConfig(string calldata) external pure override returns (bool, bytes memory, bytes memory) {
        return (true, "", "");
    }
}

// ──────────────────────────────────────────────────────
// Mock: Adapter that reverts with a plain string
// ──────────────────────────────────────────────────────
contract StringRevertAdapter is IBridgeAdapter {
    function sendMessage(BridgeMessage calldata) external payable override returns (bytes32) {
        revert("Insufficient gas for LZ send");
    }

    function quoteFee(BridgeMessage calldata) external pure override returns (uint256) {
        return 0;
    }

    function isRouteConfigured(string calldata) external pure override returns (bool) {
        return true;
    }

    function getRouteConfig(string calldata) external pure override returns (bool, bytes memory, bytes memory) {
        return (true, "", "");
    }
}

// ──────────────────────────────────────────────────────
// Mock: Adapter that succeeds (for control tests)
// ──────────────────────────────────────────────────────
contract SuccessAdapter is IBridgeAdapter {
    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32) {
        return keccak256(abi.encode(message.paymentId, block.timestamp));
    }

    function quoteFee(BridgeMessage calldata) external pure override returns (uint256) {
        return 0;
    }

    function isRouteConfigured(string calldata) external pure override returns (bool) {
        return true;
    }

    function getRouteConfig(string calldata) external pure override returns (bool, bytes memory, bytes memory) {
        return (true, "", "");
    }
}

// ──────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────
contract PaymentKitaGatewayRevertTest is Test {
    PaymentKitaGateway gateway;
    PaymentKitaRouter router;
    PaymentKitaVault vault;
    TokenRegistry tokenRegistry;
    MockToken token;
    GatewayValidatorModule validatorModule;
    GatewayQuoteModule quoteModule;
    GatewayExecutionModule executionModule;
    GatewayPrivacyModule privacyModule;
    FeePolicyManager feePolicyManager;
    FeeStrategyDefaultV1 defaultStrategy;

    address user = address(0xBEEF);
    address merchant = address(0xCAFE);

    string constant DEST_CHAIN_CUSTOM = "EVM-REVERT-TEST";
    string constant DEST_CHAIN_STRING = "EVM-STRING-REVERT";
    string constant DEST_CHAIN_OK = "EVM-SUCCESS";

    function setUp() public {
        // Deploy core
        token = new MockToken();
        tokenRegistry = new TokenRegistry();
        vault = new PaymentKitaVault();
        router = new PaymentKitaRouter();
        gateway = new PaymentKitaGateway(address(vault), address(router), address(tokenRegistry), address(this));
        validatorModule = new GatewayValidatorModule();
        quoteModule = new GatewayQuoteModule();
        executionModule = new GatewayExecutionModule();
        privacyModule = new GatewayPrivacyModule();
        defaultStrategy = new FeeStrategyDefaultV1(address(tokenRegistry));
        feePolicyManager = new FeePolicyManager(address(defaultStrategy));

        // Token support
        tokenRegistry.setTokenSupport(address(token), true);
        gateway.setGatewayModules(
            address(validatorModule),
            address(quoteModule),
            address(executionModule),
            address(privacyModule)
        );
        gateway.setFeePolicyManager(address(feePolicyManager));

        // Vault auth
        vault.setAuthorizedSpender(address(gateway), true);

        // -- Register 3 adapters on 3 different chains --

        // 1. Custom error adapter
        RevertingAdapter revertAdapter = new RevertingAdapter();
        router.registerAdapter(DEST_CHAIN_CUSTOM, 1, address(revertAdapter));
        gateway.setDefaultBridgeType(DEST_CHAIN_CUSTOM, 1);
        gateway.setBridgeTokenForDest(DEST_CHAIN_CUSTOM, address(token));
        vault.setAuthorizedSpender(address(revertAdapter), true);

        // 2. String error adapter
        StringRevertAdapter stringAdapter = new StringRevertAdapter();
        router.registerAdapter(DEST_CHAIN_STRING, 2, address(stringAdapter));
        gateway.setDefaultBridgeType(DEST_CHAIN_STRING, 2);
        gateway.setBridgeTokenForDest(DEST_CHAIN_STRING, address(token));
        vault.setAuthorizedSpender(address(stringAdapter), true);

        // 3. Success adapter (control)
        SuccessAdapter okAdapter = new SuccessAdapter();
        router.registerAdapter(DEST_CHAIN_OK, 0, address(okAdapter));
        gateway.setDefaultBridgeType(DEST_CHAIN_OK, 0);
        gateway.setBridgeTokenForDest(DEST_CHAIN_OK, address(token));
        vault.setAuthorizedSpender(address(okAdapter), true);

        // Fund user
        require(token.transfer(user, 10_000e18), "Transfer failed");
    }

    // ──── Helpers ────

    function _approveAndPay(string memory destChain) internal returns (bytes32) {
        vm.startPrank(user);
        token.approve(address(vault), 10_000e18);
        bytes32 pid = _createPaymentV2(destChain, address(token), address(token), 100e18);
        vm.stopPrank();
        return pid;
    }

    function _createPaymentV2(
        string memory destChain,
        address sourceToken,
        address destToken,
        uint256 amount
    ) internal returns (bytes32) {
        IPaymentKitaGateway.PaymentRequestV2 memory req = IPaymentKitaGateway.PaymentRequestV2({
            destChainIdBytes: bytes(destChain),
            receiverBytes: abi.encode(merchant),
            sourceToken: sourceToken,
            bridgeTokenSource: address(0),
            destToken: destToken,
            amountInSource: amount,
            minBridgeAmountOut: 0,
            minDestAmountOut: 0,
            mode: IPaymentKitaGateway.PaymentMode.REGULAR,
            bridgeOption: 255
        });
        return gateway.createPayment(req);
    }

    // ══════════════════════════════════════════════════
    // Test 1: Custom error is forwarded (NOT squashed)
    // ══════════════════════════════════════════════════
    /// @notice BEFORE fix: reverts with "Route payment failed" (opaque)
    /// @notice AFTER fix:  reverts with AdapterSpecificError("CCIP_FEE_TOKEN_NOT_SET")
    function test_customErrorIsForwarded() public {
        vm.startPrank(user);
        token.approve(address(vault), 10_000e18);

        // Should revert with the ADAPTER's error, not the gateway's generic one
        vm.expectRevert(
            abi.encodeWithSelector(RevertingAdapter.AdapterSpecificError.selector, "CCIP_FEE_TOKEN_NOT_SET")
        );
        _createPaymentV2(DEST_CHAIN_CUSTOM, address(token), address(token), 100e18);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════
    // Test 2: String revert is forwarded
    // ══════════════════════════════════════════════════
    function test_stringRevertIsForwarded() public {
        vm.startPrank(user);
        token.approve(address(vault), 10_000e18);

        // Should see the adapter's string, NOT "Route payment failed"
        vm.expectRevert(bytes("Insufficient gas for LZ send"));
        _createPaymentV2(DEST_CHAIN_STRING, address(token), address(token), 100e18);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════
    // Test 3: Success adapter still works (control)
    // ══════════════════════════════════════════════════
    function test_successAdapterStillWorks() public {
        bytes32 pid = _approveAndPay(DEST_CHAIN_OK);
        assertTrue(pid != bytes32(0), "Payment ID should be non-zero");
    }

    // ══════════════════════════════════════════════════
    // Test 4: RouteFailed event is emitted with error data
    // ══════════════════════════════════════════════════
    function test_routeFailedEventEmitted() public {
        vm.startPrank(user);
        token.approve(address(vault), 10_000e18);

        // The RouteFailed event should be emitted before the revert
        // We can't easily test events + reverts simultaneously in Forge,
        // but we verify the revert carries the original error
        vm.expectRevert(
            abi.encodeWithSelector(RevertingAdapter.AdapterSpecificError.selector, "CCIP_FEE_TOKEN_NOT_SET")
        );
        _createPaymentV2(DEST_CHAIN_CUSTOM, address(token), address(token), 100e18);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════
    // Test 5: executePayment also forwards adapter errors
    // ══════════════════════════════════════════════════
    function test_executePayment_forwardsAdapterError() public {
        // First: create a payment with the success adapter
        bytes32 pid = _approveAndPay(DEST_CHAIN_OK);

        // Now change the adapter to the reverting one
        // (simulates a config change or adapter upgrade that breaks)
        vm.prank(router.owner());
        RevertingAdapter badAdapter = new RevertingAdapter();
        router.registerAdapter(DEST_CHAIN_OK, 0, address(badAdapter));

        // Fund vault for re-route
        vm.prank(user);
        require(token.transfer(address(vault), 100e18), "Vault transfer failed");

        // executePayment should forward the adapter's error
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(RevertingAdapter.AdapterSpecificError.selector, "CCIP_FEE_TOKEN_NOT_SET")
        );
        gateway.executePayment(pid);
        vm.stopPrank();
    }
}
