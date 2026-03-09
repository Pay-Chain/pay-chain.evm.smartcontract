// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPaymentKitaGateway.sol";
import "./interfaces/IBridgeAdapter.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IGatewayValidatorModule.sol";
import "./interfaces/IGatewayQuoteModule.sol";
import "./interfaces/IGatewayExecutionModule.sol";
import "./interfaces/IGatewayPrivacyModule.sol";
import "./interfaces/IFeePolicyManager.sol";
import "./libraries/PaymentLib.sol";
import "./libraries/FeeCalculator.sol";
import "./vaults/PaymentKitaVault.sol";
import "./PaymentKitaRouter.sol";
import "./TokenRegistry.sol";

interface IVaultSwapper {
    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);
}

/**
 * @title PaymentKitaGateway
 * @notice Main Entry Point for PaymentKita Protocol
 * @dev Handles user interactions, payment requests, and orchestrates Vault/Router.
 */
contract PaymentKitaGateway is IPaymentKitaGateway, Ownable, ReentrancyGuard, Pausable {
    error InvalidBridgeOption(uint8 bridgeOption);
    error BridgeRouteNotConfigured(string destChainId, uint8 bridgeType);
    error RequestFlowDisabled();
    error QuoteModuleNotConfigured();
    error ExecutionModuleNotConfigured();
    error ValidatorModuleNotConfigured();
    error FeePolicyManagerNotConfigured();

    // ============ State Variables ============

    PaymentKitaVault public vault;
    PaymentKitaRouter public router;
    TokenRegistry public tokenRegistry;
    ISwapper public swapper;
    // Phase-1 modular facade pointers (non-breaking, optional wiring).
    address public validatorModule;
    address public quoteModule;
    address public executionModule;
    address public privacyModule;
    address public feePolicyManager;
    bool public enableSourceSideSwap;

    mapping(bytes32 => Payment) private payments;
    mapping(bytes32 => IBridgeAdapter.BridgeMessage) private paymentMessages;
    mapping(bytes32 => bytes32) public paymentToBridgeMessage;
    mapping(bytes32 => bytes32) public bridgeMessageToPayment;
    mapping(bytes32 => uint8) public paymentBridgeType;
    mapping(bytes32 => uint8) public paymentRetryCount;
    bool private _isRoutingMessage;
    
    /// @notice Default bridge type for a destination chain: destChainId => bridgeType
    mapping(string => uint8) public defaultBridgeTypes;
    /// @notice Source-side bridge token per destination lane
    mapping(string => address) public bridgeTokenByDestCaip2;

    address public feeRecipient;
    string public currentChainCaip2;

    uint256 public constant FIXED_BASE_FEE = 0.50e6; // $0.50 (assuming 6 decimals USDC/USDT)
    uint256 public constant FEE_RATE_BPS = 30; // 0.3%
    uint8 public constant MAX_RETRY_ATTEMPTS = 3;
    uint8 public constant BRIDGE_OPTION_DEFAULT = 255;
    uint8 public constant BRIDGE_OPTION_HYPERBRIDGE = 0;
    uint8 public constant BRIDGE_OPTION_CCIP = 1;
    uint8 public constant BRIDGE_OPTION_LAYERZERO = 2;

    struct PlatformFeePolicy {
        bool enabled;
        uint256 perByteRate;
        uint256 overheadBytes;
        uint256 minFee;
        uint256 maxFee;
    }

    struct PaymentCostSnapshot {
        uint256 platformFeeToken;
        uint256 bridgeFeeNative;
        uint256 bridgeFeeTokenEq;
        uint256 totalSourceTokenRequired;
    }

    struct PaymentCostQuote {
        uint256 platformFee;
        uint256 bridgeFeeNative;
        uint256 totalSourceTokenRequired;
        uint8 bridgeType;
        bool bridgeQuoteOk;
        string bridgeQuoteReason;
    }

    PlatformFeePolicy public platformFeePolicy;
    mapping(bytes32 => PaymentCostSnapshot) private paymentCostSnapshots;

    // ============ Events ============
    
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event TokenRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event DefaultBridgeTypeSet(string destChainId, uint8 bridgeType);
    event BridgeTokenForDestSet(string destChainId, address bridgeTokenSource);
    event SourceSideSwapToggled(bool enabled);
    event PaymentRetryRequested(bytes32 indexed paymentId, bytes32 indexed previousMessageId, uint8 retryCount);
    event MessageRoutingLockUpdated(bool locked);
    event RouteFailed(bytes32 indexed paymentId, bytes reason);
    event PaymentFailed(bytes32 indexed paymentId, string reason);
    event PlatformFeePolicyUpdated(
        bool enabled,
        uint256 perByteRate,
        uint256 overheadBytes,
        uint256 minFee,
        uint256 maxFee
    );
    event PlatformFeeCharged(bytes32 indexed paymentId, address indexed token, uint256 amount, address indexed recipient);
    event BridgeFeeCharged(bytes32 indexed paymentId, uint8 bridgeType, uint256 nativeAmount, uint256 tokenEquivalent);
    event NativeFeeBufferUpdated(uint256 oldBps, uint256 newBps);
    event PaymentCostSnapshotted(
        bytes32 indexed paymentId,
        uint256 platformFeeToken,
        uint256 bridgeFeeNative,
        uint256 bridgeFeeTokenEq,
        uint256 totalSourceTokenRequired
    );
    event PrivacyPaymentCreated(bytes32 indexed paymentId, bytes32 indexed intentId, address indexed stealthReceiver);
    event PrivacyForwardRequested(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount
    );
    event PrivacyForwardCompleted(
        bytes32 indexed paymentId,
        address indexed stealthReceiver,
        address indexed finalReceiver,
        address token,
        uint256 amount
    );
    event PrivacyForwardFailed(bytes32 indexed paymentId, uint8 retryCount, string reason);
    event GatewayModulesUpdated(
        address indexed validatorModule,
        address indexed quoteModule,
        address indexed executionModule,
        address privacyModule
    );
    event FeePolicyManagerUpdated(address indexed oldManager, address indexed newManager);

    // ============ Diagnostics ============

    /// @notice Stores last revert data per payment for observability (read by diagnostics API)
    mapping(bytes32 => bytes) public lastRouteError;

    /// @notice Authorized receiver adapters that can call markPaymentFailed
    mapping(address => bool) public isAuthorizedAdapter;
    uint256 public nativeFeeBufferBps = 500; // 5%
    mapping(bytes32 => bytes32) public privacyIntentByPayment;
    mapping(bytes32 => address) public privacyStealthByPayment;
    mapping(bytes32 => address) public privacyFinalReceiverByPayment;
    mapping(bytes32 => bool) public privacyForwardCompleted;
    mapping(bytes32 => uint8) public privacyForwardRetryCount;

    // ============ Constructor ============

    constructor(
        address _vault,
        address _router,
        address _tokenRegistry,
        address _feeRecipient
    ) Ownable(msg.sender) {
        require(_vault != address(0), "Invalid vault");
        require(_router != address(0), "Invalid router");
        require(_tokenRegistry != address(0), "Invalid registry");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        vault = PaymentKitaVault(_vault);
        router = PaymentKitaRouter(_router);
        tokenRegistry = TokenRegistry(_tokenRegistry);
        feeRecipient = _feeRecipient;
        currentChainCaip2 = string(abi.encodePacked("eip155:", _uint2str(block.chainid)));
    }

    // ============ Admin Functions ============

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        emit RouterUpdated(address(router), _router);
        router = PaymentKitaRouter(_router);
    }

    function setTokenRegistry(address _tokenRegistry) external onlyOwner {
        require(_tokenRegistry != address(0), "Invalid registry");
        emit TokenRegistryUpdated(address(tokenRegistry), _tokenRegistry);
        tokenRegistry = TokenRegistry(_tokenRegistry);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = ISwapper(_swapper);
    }

    function setGatewayModules(
        address _validatorModule,
        address _quoteModule,
        address _executionModule,
        address _privacyModule
    ) external onlyOwner {
        require(_validatorModule != address(0), "Invalid validator module");
        require(_quoteModule != address(0), "Invalid quote module");
        require(_executionModule != address(0), "Invalid execution module");
        require(_privacyModule != address(0), "Invalid privacy module");

        validatorModule = _validatorModule;
        quoteModule = _quoteModule;
        executionModule = _executionModule;
        privacyModule = _privacyModule;

        emit GatewayModulesUpdated(_validatorModule, _quoteModule, _executionModule, _privacyModule);
    }

    function setFeePolicyManager(address _manager) external onlyOwner {
        require(_manager != address(0), "Invalid fee manager");
        emit FeePolicyManagerUpdated(feePolicyManager, _manager);
        feePolicyManager = _manager;
    }

    function setEnableSourceSideSwap(bool enabled) external onlyOwner {
        enableSourceSideSwap = enabled;
        emit SourceSideSwapToggled(enabled);
    }

    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external onlyOwner {
        defaultBridgeTypes[destChainId] = bridgeType;
        emit DefaultBridgeTypeSet(destChainId, bridgeType);
    }

    function setBridgeTokenForDest(string calldata destChainId, address bridgeTokenSource) external onlyOwner {
        require(bridgeTokenSource != address(0), "Invalid bridge token");
        require(tokenRegistry.isTokenSupported(bridgeTokenSource), "Bridge token not supported");
        bridgeTokenByDestCaip2[destChainId] = bridgeTokenSource;
        emit BridgeTokenForDestSet(destChainId, bridgeTokenSource);
    }

    function setAuthorizedAdapter(address adapter, bool authorized) external onlyOwner {
        isAuthorizedAdapter[adapter] = authorized;
    }

    function setPlatformFeePolicy(
        bool enabled,
        uint256 perByteRate,
        uint256 overheadBytes,
        uint256 minFee,
        uint256 maxFee
    ) external onlyOwner {
        require(maxFee == 0 || minFee <= maxFee, "Invalid fee cap");
        platformFeePolicy = PlatformFeePolicy({
            enabled: enabled,
            perByteRate: perByteRate,
            overheadBytes: overheadBytes,
            minFee: minFee,
            maxFee: maxFee
        });

        emit PlatformFeePolicyUpdated(enabled, perByteRate, overheadBytes, minFee, maxFee);
    }

    function setNativeFeeBufferBps(uint256 bps) external onlyOwner {
        require(bps <= 5000, "Buffer too high");
        emit NativeFeeBufferUpdated(nativeFeeBufferBps, bps);
        nativeFeeBufferBps = bps;
    }

    // ============ Core: Cross-Chain Payment ============

    /// @notice Internal payment creation logic shared by V2 entrypoints
    function _createPaymentInternal(
        bytes memory destChainIdBytes,
        bytes memory receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 minAmountOut,
        uint8 bridgeOption
    ) internal returns (bytes32 paymentId) {
        require(destChainIdBytes.length > 0, "Empty dest chain ID");
        bridgeOption; // same-chain path ignores bridge option by design

        string memory destChainId = string(destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
        require(keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId)), "Only same-chain");

        address receiver = _validateCreateAndDecodeReceiver(
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            false
        );

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            destChainIdBytes,
            receiverBytes,
            sourceToken,
            destToken,
            amount,
            minAmountOut
        );
        uint256 platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            sourceToken,
            destToken,
            amount,
            payloadLength,
            0,
            0
        );
        uint256 totalAmount = amount + platformFee;

        vault.pullTokens(sourceToken, msg.sender, totalAmount);
        vault.pushTokens(sourceToken, feeRecipient, platformFee);

        paymentId = PaymentLib.calculatePaymentId(
            msg.sender,
            receiver,
            destChainId,
            sourceToken,
            amount,
            block.timestamp
        );

        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            fee: platformFee,
            status: PaymentStatus.Completed,
            createdAt: block.timestamp
        });

        paymentCostSnapshots[paymentId] = PaymentCostSnapshot({
            platformFeeToken: platformFee,
            bridgeFeeNative: 0,
            bridgeFeeTokenEq: 0,
            totalSourceTokenRequired: totalAmount
        });
        emit PaymentCostSnapshotted(paymentId, platformFee, 0, 0, totalAmount);
        emit PlatformFeeCharged(paymentId, sourceToken, platformFee, feeRecipient);
        uint256 settledAmount = amount;
        if (sourceToken == destToken) {
            vault.pushTokens(sourceToken, receiver, amount);
        } else {
            require(destToken != address(0), "Invalid destination token");
            require(tokenRegistry.isTokenSupported(destToken), "Destination token not supported");
            require(address(swapper) != address(0), "Swapper not configured");
            settledAmount = IVaultSwapper(address(swapper)).swapFromVault(
                sourceToken,
                destToken,
                amount,
                minAmountOut,
                receiver
            );
        }

        emit PaymentCompleted(paymentId, settledAmount);
        if (executionModule != address(0)) {
            IGatewayExecutionModule(executionModule).onSameChainSettled(
                paymentId,
                receiver,
                sourceToken == destToken ? sourceToken : destToken,
                settledAmount
            );
        }
        emit PaymentCreated(
            paymentId,
            msg.sender,
            receiver,
            destChainId,
            sourceToken,
            destToken,
            amount,
            platformFee,
            "SameChain"
        );
    }

    // ============ Phase-0 V2 (non-breaking wrappers) ============

    function createPayment(PaymentRequestV2 calldata req)
        external
        payable
        override
        nonReentrant
        whenNotPaused
        returns (bytes32 paymentId)
    {
        require(req.mode == PaymentMode.REGULAR, "Use createPaymentPrivate for privacy");
        return _createPaymentV2Internal(req, req.bridgeOption, req.receiverBytes);
    }

    function createPaymentPrivate(
        PaymentRequestV2 calldata req,
        PrivateRouting calldata privacy
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        require(req.mode == PaymentMode.PRIVACY, "Invalid mode for private payment");
        require(privacy.intentId != bytes32(0), "Missing privacy intent");
        require(privacy.stealthReceiver != address(0), "Invalid stealth receiver");

        address finalReceiver = _validateCreateAndDecodeReceiver(
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            false
        );

        bytes memory privateReceiverBytes = abi.encode(privacy.stealthReceiver);
        paymentId = _createPaymentV2Internal(req, req.bridgeOption, privateReceiverBytes);

        privacyIntentByPayment[paymentId] = privacy.intentId;
        privacyStealthByPayment[paymentId] = privacy.stealthReceiver;
        privacyFinalReceiverByPayment[paymentId] = finalReceiver;
        privacyForwardCompleted[paymentId] = false;

        if (privacyModule != address(0)) {
            IGatewayPrivacyModule(privacyModule).recordPrivacyIntent(
                paymentId,
                privacy.intentId,
                privacy.stealthReceiver,
                msg.sender
            );
        }
        emit PrivacyPaymentCreated(paymentId, privacy.intentId, privacy.stealthReceiver);
    }

    function createPaymentDefaultBridge(
        PaymentRequestV2 calldata req
    ) external payable override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        require(req.mode == PaymentMode.REGULAR, "Use createPaymentPrivate for privacy");
        return _createPaymentV2Internal(req, BRIDGE_OPTION_DEFAULT, req.receiverBytes);
    }

    function quotePaymentCost(
        PaymentRequestV2 calldata req
    )
        external
        view
        override
        returns (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        )
    {
        PaymentRequestV2 memory reqMem = req;
        PaymentCostQuote memory quote = _quotePaymentCostInternal(reqMem);
        platformFee = quote.platformFee;
        bridgeFeeNative = quote.bridgeFeeNative;
        totalSourceTokenRequired = quote.totalSourceTokenRequired;
        bridgeType = quote.bridgeType;
        bridgeQuoteOk = quote.bridgeQuoteOk;
        bridgeQuoteReason = quote.bridgeQuoteReason;
    }

    function previewApproval(
        PaymentRequestV2 calldata req
    ) external view override returns (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee) {
        approvalToken = req.sourceToken;
        PaymentRequestV2 memory reqMem = req;
        PaymentCostQuote memory quote = _quotePaymentCostInternal(reqMem);
        approvalAmount = quote.totalSourceTokenRequired;
        requiredNativeFee = quote.bridgeQuoteOk ? _applyNativeFeeBuffer(quote.bridgeFeeNative) : 0;
    }

    function _routeWithStoredMessage(bytes32 paymentId, uint256 nativeFeeValue) internal {
        require(!_isRoutingMessage, "Routing reentrancy");
        _isRoutingMessage = true;
        emit MessageRoutingLockUpdated(true);

        IBridgeAdapter.BridgeMessage storage message = paymentMessages[paymentId];
        bytes32 bridgeMessageId;
        try router.routePayment{value: nativeFeeValue}(message.destChainId, paymentBridgeType[paymentId], message) returns (
            bytes32 routedMessageId
        ) {
            bridgeMessageId = routedMessageId;
        } catch (bytes memory reason) {
            _isRoutingMessage = false;
            emit MessageRoutingLockUpdated(false);
            emit RouteFailed(paymentId, reason);
            lastRouteError[paymentId] = reason;
            // Forward the original adapter error instead of a generic message
            assembly { revert(add(reason, 0x20), mload(reason)) }
        }

        require(bridgeMessageId != bytes32(0), "Invalid bridge message id");
        paymentToBridgeMessage[paymentId] = bridgeMessageId;
        bridgeMessageToPayment[bridgeMessageId] = paymentId;
        emit PaymentExecuted(paymentId, bridgeMessageId);

        _isRoutingMessage = false;
        emit MessageRoutingLockUpdated(false);
    }

    // ============ Incoming Payment Handler ============

    /**
     * @notice Finalize an incoming cross-chain payment
     * @dev Only callable by authorized Adapters
     */
    function finalizeIncomingPayment(
        bytes32 paymentId,
        address /* receiver */,
        address /* token */,
        uint256 amount
    ) external {
        // Simple auth check: Sender must be authorized in Vault (simplifies permission management)
        require(vault.authorizedSpenders(msg.sender), "Unauthorized adapter");

        emit PaymentCompleted(paymentId, amount);
        if (executionModule != address(0)) {
            IGatewayExecutionModule(executionModule).onIncomingFinalized(paymentId, amount);
        }
        
        // Note: The Adapter is responsible for transferring the tokens to the receiver.
        // We just record the event/state here.
    }

    function finalizePrivacyForward(bytes32 paymentId, address token, uint256 amount) external override {
        require(vault.authorizedSpenders(msg.sender), "Unauthorized adapter");
        require(!privacyForwardCompleted[paymentId], "Privacy forward already completed");

        address stealthReceiver = privacyStealthByPayment[paymentId];
        address finalReceiver = privacyFinalReceiverByPayment[paymentId];
        require(stealthReceiver != address(0), "Privacy payment not found");
        require(finalReceiver != address(0), "Missing final receiver");

        emit PrivacyForwardRequested(paymentId, stealthReceiver, finalReceiver, token, amount);

        privacyForwardCompleted[paymentId] = true;
        if (privacyModule != address(0)) {
            IGatewayPrivacyModule(privacyModule).recordPrivacyForward(
                paymentId,
                stealthReceiver,
                finalReceiver,
                token,
                amount,
                msg.sender
            );
        }

        emit PrivacyForwardCompleted(paymentId, stealthReceiver, finalReceiver, token, amount);
    }

    function reportPrivacyForwardFailure(bytes32 paymentId, string calldata reason) external override {
        require(vault.authorizedSpenders(msg.sender), "Unauthorized adapter");
        require(!privacyForwardCompleted[paymentId], "Privacy forward already completed");
        require(privacyStealthByPayment[paymentId] != address(0), "Privacy payment not found");

        privacyForwardRetryCount[paymentId] += 1;
        emit PrivacyForwardFailed(paymentId, privacyForwardRetryCount[paymentId], reason);
    }

    // ============ Internal Helper ============

    function _calculatePlatformFeeByPolicy(
        string memory sourceChainId,
        string memory destChainId,
        address sourceToken,
        address destToken,
        uint256 amount,
        uint256 payloadLength,
        uint256 bridgeFeeNative,
        uint256 swapImpactBps
    ) internal view returns (uint256) {
        if (feePolicyManager == address(0)) revert FeePolicyManagerNotConfigured();
        uint8 tokenDecimals = _getTokenDecimals(sourceToken);
        uint256 scaledFixedBaseFee = FeeCalculator.scaleFeeByDecimals(FIXED_BASE_FEE, tokenDecimals);
        return
            IFeePolicyManager(feePolicyManager).computePlatformFee(
                bytes(sourceChainId),
                bytes(destChainId),
                sourceToken,
                destToken,
                amount,
                bridgeFeeNative,
                swapImpactBps,
                platformFeePolicy.enabled,
                payloadLength,
                platformFeePolicy.overheadBytes,
                platformFeePolicy.perByteRate,
                platformFeePolicy.minFee,
                platformFeePolicy.maxFee,
                scaledFixedBaseFee,
                FEE_RATE_BPS
            );
    }

    function _validateCreateAndDecodeReceiver(
        bytes memory receiverBytes,
        address sourceToken,
        address destToken,
        uint256 amount,
        bool requireDestTokenSupported
    ) internal view returns (address receiver) {
        if (validatorModule == address(0)) revert ValidatorModuleNotConfigured();
        return
            IGatewayValidatorModule(validatorModule).validateCreate(
                address(tokenRegistry),
                receiverBytes,
                sourceToken,
                destToken,
                amount,
                true,
                requireDestTokenSupported
            );
    }

    function _resolveBridgeType(string memory destChainId, uint8 bridgeOption) internal view returns (uint8 bridgeType) {
        if (bridgeOption == BRIDGE_OPTION_DEFAULT) {
            bridgeType = defaultBridgeTypes[destChainId];
        } else if (
            bridgeOption == BRIDGE_OPTION_HYPERBRIDGE ||
            bridgeOption == BRIDGE_OPTION_CCIP ||
            bridgeOption == BRIDGE_OPTION_LAYERZERO
        ) {
            bridgeType = bridgeOption;
        } else {
            revert InvalidBridgeOption(bridgeOption);
        }

        if (!router.hasAdapter(destChainId, bridgeType)) {
            revert BridgeRouteNotConfigured(destChainId, bridgeType);
        }
    }

    function _resolveBridgeTokenSource(string memory destChainId, address requestBridgeToken) internal view returns (address) {
        address resolved = requestBridgeToken;
        if (resolved == address(0)) {
            resolved = bridgeTokenByDestCaip2[destChainId];
        }
        require(resolved != address(0), "Bridge token not configured");
        require(tokenRegistry.isTokenSupported(resolved), "Bridge token not supported");
        return resolved;
    }

    function _tryResolveBridgeType(
        string memory destChainId,
        uint8 bridgeOption
    ) internal view returns (bool ok, uint8 bridgeType, string memory reason) {
        if (bridgeOption == BRIDGE_OPTION_DEFAULT) {
            bridgeType = defaultBridgeTypes[destChainId];
        } else if (
            bridgeOption == BRIDGE_OPTION_HYPERBRIDGE ||
            bridgeOption == BRIDGE_OPTION_CCIP ||
            bridgeOption == BRIDGE_OPTION_LAYERZERO
        ) {
            bridgeType = bridgeOption;
        } else {
            return (false, 255, "invalid_bridge_option");
        }

        if (!router.hasAdapter(destChainId, bridgeType)) {
            return (false, bridgeType, "bridge_route_not_configured");
        }
        return (true, bridgeType, "");
    }

    function _tryResolveBridgeTokenSource(
        string memory destChainId,
        address requestBridgeToken
    ) internal view returns (bool ok, address resolved, string memory reason) {
        resolved = requestBridgeToken;
        if (resolved == address(0)) {
            resolved = bridgeTokenByDestCaip2[destChainId];
        }
        if (resolved == address(0)) {
            return (false, address(0), "bridge_token_not_configured");
        }
        if (!tokenRegistry.isTokenSupported(resolved)) {
            return (false, address(0), "bridge_token_not_supported");
        }
        return (true, resolved, "");
    }

    function _quotePaymentCostInternal(
        PaymentRequestV2 memory req
    ) internal view returns (PaymentCostQuote memory q) {
        q.bridgeType = 255;

        if (req.amountInSource == 0) {
            q.bridgeQuoteReason = "amount_must_be_gt_zero";
            return q;
        }
        if (req.sourceToken == address(0)) {
            q.bridgeQuoteReason = "invalid_source_token";
            return q;
        }
        if (req.destChainIdBytes.length == 0) {
            q.bridgeQuoteReason = "empty_dest_chain_id";
            return q;
        }
        if (req.receiverBytes.length == 0) {
            q.bridgeQuoteReason = "empty_receiver";
            return q;
        }

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            req.destChainIdBytes,
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut
        );
        q.platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            payloadLength,
            0,
            0
        );
        q.totalSourceTokenRequired = req.amountInSource + q.platformFee;

        if (isSameChain) {
            q.bridgeQuoteOk = true;
            q.bridgeQuoteReason = "";
            return q;
        }

        (bool bridgeTypeOk, uint8 resolvedBridgeType, string memory bridgeTypeReason) = _tryResolveBridgeType(
            destChainId,
            req.bridgeOption
        );
        if (!bridgeTypeOk) {
            q.bridgeType = resolvedBridgeType;
            q.bridgeQuoteReason = bridgeTypeReason;
            return q;
        }
        q.bridgeType = resolvedBridgeType;

        (bool bridgeTokenOk, address bridgeTokenSource, string memory bridgeTokenReason) = _tryResolveBridgeTokenSource(
            destChainId,
            req.bridgeTokenSource
        );
        if (!bridgeTokenOk) {
            q.bridgeQuoteReason = bridgeTokenReason;
            return q;
        }

        if (quoteModule == address(0)) {
            q.bridgeQuoteReason = "quote_module_not_configured";
            return q;
        }

        (q.bridgeQuoteOk, q.bridgeFeeNative, q.bridgeQuoteReason) = IGatewayQuoteModule(quoteModule).quoteBridgeForV2(
            address(router),
            address(swapper),
            enableSourceSideSwap,
            destChainId,
            req.receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut,
            q.bridgeType,
            bridgeTokenSource
        );
    }

    function _createPaymentV2Internal(
        PaymentRequestV2 calldata req,
        uint8 bridgeOption,
        bytes memory receiverBytes
    ) internal returns (bytes32 paymentId) {
        require(req.destChainIdBytes.length > 0, "Empty dest chain ID");

        string memory destChainId = string(req.destChainIdBytes);
        string memory sourceChainId = currentChainCaip2;
        bool isSameChain = keccak256(bytes(destChainId)) == keccak256(bytes(sourceChainId));

        // Same-chain keeps existing behavior for compatibility.
        if (isSameChain) {
            return _createPaymentInternal(
                req.destChainIdBytes,
                receiverBytes,
                req.sourceToken,
                req.destToken,
                req.amountInSource,
                req.minDestAmountOut,
                bridgeOption
            );
        }

        address receiver = _validateCreateAndDecodeReceiver(
            receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            false
        );

        uint8 bridgeType = _resolveBridgeType(destChainId, bridgeOption);
        address bridgeTokenSource = _resolveBridgeTokenSource(destChainId, req.bridgeTokenSource);

        uint256 payloadLength = FeeCalculator.payloadLengthForPayment(
            req.destChainIdBytes,
            receiverBytes,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            req.minDestAmountOut
        );
        uint256 platformFee = _calculatePlatformFeeByPolicy(
            sourceChainId,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            payloadLength,
            0,
            0
        );
        uint256 totalAmount = req.amountInSource + platformFee;

        // Pull user funds and collect platform fee in source token first.
        vault.pullTokens(req.sourceToken, msg.sender, totalAmount);
        vault.pushTokens(req.sourceToken, feeRecipient, platformFee);

        paymentId = PaymentLib.calculatePaymentId(
            msg.sender,
            receiver,
            destChainId,
            req.sourceToken,
            req.amountInSource,
            block.timestamp
        );

        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            sourceToken: req.sourceToken,
            destToken: req.destToken,
            amount: req.amountInSource,
            fee: platformFee,
            status: PaymentStatus.Processing,
            createdAt: block.timestamp
        });

        uint256 bridgedAmount = req.amountInSource;
        address bridgedSourceToken = req.sourceToken;
        if (bridgedSourceToken != bridgeTokenSource) {
            require(enableSourceSideSwap, "Source-side swap disabled");
            require(address(swapper) != address(0), "Swapper not configured");
            (bool exists,,) = swapper.findRoute(bridgedSourceToken, bridgeTokenSource);
            require(exists, "No route to bridge token");

            bridgedAmount = IVaultSwapper(address(swapper)).swapFromVault(
                bridgedSourceToken,
                bridgeTokenSource,
                req.amountInSource,
                req.minBridgeAmountOut,
                address(vault)
            );
            bridgedSourceToken = bridgeTokenSource;
        } else {
            bridgedSourceToken = bridgeTokenSource;
        }

        if (
            router.bridgeModes(bridgeType) == PaymentKitaRouter.BridgeMode.TOKEN_BRIDGE &&
            bridgedSourceToken != req.destToken
        ) {
            revert("TOKEN_BRIDGE requires same token");
        }

        IBridgeAdapter.BridgeMessage memory bridgeMessage = IBridgeAdapter.BridgeMessage({
            paymentId: paymentId,
            receiver: receiver,
            sourceToken: bridgedSourceToken,
            destToken: req.destToken,
            amount: bridgedAmount,
            destChainId: destChainId,
            minAmountOut: req.minDestAmountOut,
            payer: msg.sender
        });
        paymentMessages[paymentId] = bridgeMessage;
        paymentBridgeType[paymentId] = bridgeType;

        if (quoteModule == address(0)) revert QuoteModuleNotConfigured();
        (bool quoteOk, uint256 requiredNativeFee, string memory quoteReason) = IGatewayQuoteModule(quoteModule)
            .quotePaymentFeeSafe(address(router), destChainId, bridgeType, bridgeMessage);
        require(quoteOk, quoteReason);
        if (executionModule == address(0)) revert ExecutionModuleNotConfigured();
        IGatewayExecutionModule(executionModule).beforeRoute(
            paymentId,
            destChainId,
            bridgeType,
            msg.value,
            requiredNativeFee
        );

        paymentCostSnapshots[paymentId] = PaymentCostSnapshot({
            platformFeeToken: platformFee,
            bridgeFeeNative: msg.value,
            bridgeFeeTokenEq: 0,
            totalSourceTokenRequired: totalAmount
        });
        emit PaymentCostSnapshotted(paymentId, platformFee, msg.value, 0, totalAmount);
        emit PlatformFeeCharged(paymentId, req.sourceToken, platformFee, feeRecipient);
        emit BridgeFeeCharged(paymentId, bridgeType, msg.value, 0);

        _routeWithStoredMessage(paymentId, msg.value);

        emit PaymentCreated(
            paymentId,
            msg.sender,
            receiver,
            destChainId,
            req.sourceToken,
            req.destToken,
            req.amountInSource,
            platformFee,
            bridgeType == 0 ? "Hyperbridge" : (bridgeType == 1 ? "CCIP" : "LayerZero")
        );
    }

    function _applyNativeFeeBuffer(uint256 fee) internal view returns (uint256) {
        if (fee == 0 || nativeFeeBufferBps == 0) return fee;
        return fee + ((fee * nativeFeeBufferBps) / 10_000);
    }

    function _getTokenDecimals(address token) internal view returns (uint8) {
        uint8 regDec = tokenRegistry.tokenDecimals(token);
        if (regDec > 0) return regDec;
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        if (ok && data.length >= 32) {
            uint256 decRaw = abi.decode(data, (uint256));
            if (decRaw > 0 && decRaw <= type(uint8).max) {
                // forge-lint: disable-next-line(unsafe-typecast)
                return uint8(decRaw);
            }
        }
        return 6;
    }
    
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        bytes memory digits = "0123456789";
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = digits[j % 10];
            j /= 10;
        }
        return string(bstr);
    }

    // Implement abstract functions from interface
    function executePayment(bytes32 paymentId) external payable override nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(
            payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed,
            "Invalid payment status"
        );
        require(bytes(paymentMessages[paymentId].destChainId).length > 0, "No bridge message");

        payment.status = PaymentStatus.Processing;
        _routeWithStoredMessage(paymentId, msg.value);
    }
    
    function retryMessage(bytes32 messageId) external override nonReentrant whenNotPaused {
        bytes32 paymentId = bridgeMessageToPayment[messageId];
        require(paymentId != bytes32(0), "Message not found");

        Payment storage payment = payments[paymentId];
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(paymentRetryCount[paymentId] < MAX_RETRY_ATTEMPTS, "Retry limit reached");

        paymentRetryCount[paymentId] += 1;
        emit PaymentRetryRequested(paymentId, messageId, paymentRetryCount[paymentId]);

        // Retry with the stored bridge payload. For bridge types requiring native fee,
        // callers should use executePayment(paymentId) to provide msg.value.
        _routeWithStoredMessage(paymentId, 0);
    }

    function processRefund(bytes32 paymentId) external override {
        Payment storage payment = payments[paymentId];
        require(payment.sender == msg.sender || msg.sender == owner(), "Unauthorized");
        require(payment.status == PaymentStatus.Failed, "Not failed");
        
        payment.status = PaymentStatus.Refunded;
        
        // Return funds from Vault
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Adapter-safe fail+refund path for timeout/failure callbacks
    /// @dev Allows authorized adapters to atomically fail and refund a payment.
    function adapterFailAndRefund(bytes32 paymentId, string calldata reason) external {
        require(isAuthorizedAdapter[msg.sender], "Not authorized adapter");
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        require(
            payment.status == PaymentStatus.Processing || payment.status == PaymentStatus.Failed,
            "Invalid payment status"
        );

        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);

        payment.status = PaymentStatus.Refunded;
        vault.pushTokens(payment.sourceToken, payment.sender, payment.amount);
        emit PaymentRefunded(paymentId, payment.amount);
    }

    /// @notice Mark a payment as failed (called by authorized adapters on timeout/bridge failure)
    function markPaymentFailed(bytes32 paymentId, string calldata reason) external {
        require(isAuthorizedAdapter[msg.sender], "Not authorized adapter");
        Payment storage payment = payments[paymentId];
        require(payment.sender != address(0), "Payment not found");
        payment.status = PaymentStatus.Failed;
        emit PaymentFailed(paymentId, reason);
    }
    
    function getPayment(bytes32 paymentId) external view override returns (Payment memory) {
        return payments[paymentId];
    }
    
}
