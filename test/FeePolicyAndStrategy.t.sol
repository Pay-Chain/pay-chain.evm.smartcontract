// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/PaymentKitaGateway.sol";
import "../src/PaymentKitaRouter.sol";
import "../src/TokenRegistry.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/gateway/fee/FeePolicyManager.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/interfaces/IFeeStrategy.sol";
import "../src/gateway/modules/GatewayValidatorModule.sol";
import "../src/gateway/modules/GatewayQuoteModule.sol";
import "../src/gateway/modules/GatewayExecutionModule.sol";
import "../src/gateway/modules/GatewayPrivacyModule.sol";

contract MockFeeToken is ERC20 {
    constructor() ERC20("Mock Fee Token", "MFT") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract MockFixedFeeStrategy is IFeeStrategy {
    uint256 public immutable fixedFee;

    constructor(uint256 _fixedFee) {
        fixedFee = _fixedFee;
    }

    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address,
        address,
        uint256,
        uint256,
        uint256
    ) external view returns (uint256) {
        return fixedFee;
    }
}

contract MockRevertingFeeStrategy is IFeeStrategy {
    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address,
        address,
        uint256,
        uint256,
        uint256
    ) external pure returns (uint256) {
        revert("mock_strategy_revert");
    }
}

contract FeePolicyAndStrategyTest is Test {
    PaymentKitaGateway gateway;
    PaymentKitaRouter router;
    TokenRegistry registry;
    PaymentKitaVault vault;

    FeePolicyManager manager;
    FeeStrategyDefaultV1 defaultStrategy;
    GatewayValidatorModule validatorModule;
    GatewayQuoteModule quoteModule;
    GatewayExecutionModule executionModule;
    GatewayPrivacyModule privacyModule;
    MockFeeToken feeToken;
    MockFixedFeeStrategy fixed42;
    MockRevertingFeeStrategy revertingStrategy;

    address receiver = address(0xBEEF);
    address sourceToken;
    address destToken;

    function setUp() public {
        registry = new TokenRegistry();
        vault = new PaymentKitaVault();
        router = new PaymentKitaRouter();
        gateway = new PaymentKitaGateway(address(vault), address(router), address(registry), address(this));
        feeToken = new MockFeeToken();
        sourceToken = address(feeToken);
        destToken = address(feeToken);
        registry.setTokenSupport(sourceToken, true);
        registry.setTokenSupport(destToken, true);

        validatorModule = new GatewayValidatorModule();
        quoteModule = new GatewayQuoteModule();
        executionModule = new GatewayExecutionModule();
        privacyModule = new GatewayPrivacyModule();
        gateway.setGatewayModules(
            address(validatorModule),
            address(quoteModule),
            address(executionModule),
            address(privacyModule)
        );

        defaultStrategy = new FeeStrategyDefaultV1(address(registry));
        fixed42 = new MockFixedFeeStrategy(42);
        revertingStrategy = new MockRevertingFeeStrategy();
        manager = new FeePolicyManager(address(defaultStrategy));
    }

    function testFeePolicyManager_DefaultResolve() public {
        address resolved = address(manager.resolveStrategy());
        assertEq(resolved, address(defaultStrategy));
    }

    function testFeePolicyManager_SetActiveResolve() public {
        manager.setActiveStrategy(address(fixed42));
        address resolved = address(manager.resolveStrategy());
        assertEq(resolved, address(fixed42));
    }

    function testFeePolicyManager_ClearActiveFallbackToDefault() public {
        manager.setActiveStrategy(address(fixed42));
        manager.clearActiveStrategy();
        address resolved = address(manager.resolveStrategy());
        assertEq(resolved, address(defaultStrategy));
    }

    function testGateway_UsesActiveStrategyForQuote() public {
        gateway.setFeePolicyManager(address(manager));
        manager.setActiveStrategy(address(fixed42));

        string memory sameChainId = string.concat("eip155:", vm.toString(block.chainid));
        IPaymentKitaGateway.PaymentRequestV2 memory req;
        req.destChainIdBytes = bytes(sameChainId);
        req.receiverBytes = abi.encode(receiver);
        req.sourceToken = sourceToken;
        req.bridgeTokenSource = sourceToken;
        req.destToken = sourceToken;
        req.amountInSource = 100 ether;
        req.minBridgeAmountOut = 0;
        req.minDestAmountOut = 0;
        req.mode = IPaymentKitaGateway.PaymentMode.REGULAR;
        req.bridgeOption = 255;
        (
            uint256 platformFee,
            ,
            ,
            ,
            ,

        ) = gateway.quotePaymentCost(req);

        assertEq(req.destChainIdBytes, bytes(sameChainId));
        assertEq(platformFee, 42);
    }

    function testGateway_FallbacksToLegacyWhenStrategyReverts() public {
        gateway.setFeePolicyManager(address(manager));
        manager.setActiveStrategy(address(revertingStrategy));

        string memory sameChainId = string.concat("eip155:", vm.toString(block.chainid));
        IPaymentKitaGateway.PaymentRequestV2 memory req;
        req.destChainIdBytes = bytes(sameChainId);
        req.receiverBytes = abi.encode(receiver);
        req.sourceToken = sourceToken;
        req.bridgeTokenSource = sourceToken;
        req.destToken = sourceToken;
        req.amountInSource = 100 ether;
        req.minBridgeAmountOut = 0;
        req.minDestAmountOut = 0;
        req.mode = IPaymentKitaGateway.PaymentMode.REGULAR;
        req.bridgeOption = 255;
        (
            uint256 platformFee,
            ,
            ,
            ,
            ,

        ) = gateway.quotePaymentCost(req);

        // Legacy fallback formula now scales by token decimals (18 here).
        assertEq(req.destChainIdBytes, bytes(sameChainId));
        assertEq(platformFee, 300000000000000000);
    }
}
