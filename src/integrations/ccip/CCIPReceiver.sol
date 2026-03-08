// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CCIPReceiverBase.sol";
import "./Client.sol";
import "../../PaymentKitaGateway.sol";
import "../../vaults/PaymentKitaVault.sol";
import "../../TokenSwapper.sol";

/**
 * @title CCIPReceiverAdapter
 * @notice Bridge Adapter for receiving CCIP messages with trust model
 * @dev Phase 1.3: Added trustedSenders, allowedSourceChains, 4-field decode
 */
contract CCIPReceiverAdapter is CCIPReceiverBase, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PaymentKitaGateway public gateway;
    PaymentKitaVault public vault;
    TokenSwapper public swapper;

    /// @notice Trusted sender addresses per source chain selector
    mapping(uint64 => bytes) public trustedSenders;

    /// @notice Allowed source chain selectors
    mapping(uint64 => bool) public allowedSourceChains;

    /// @notice Failed message payloads for manual retry
    mapping(bytes32 => bytes) public failedMessages;
    mapping(bytes32 => bytes) public failedMessageReasons;
    mapping(bytes32 => uint256) public failedMessageRetryCount;
    mapping(bytes32 => bytes32) public failedMessagePaymentIds;

    // ============ Events ============

    event TrustedSenderSet(uint64 indexed chainSelector, bytes sender);
    event SourceChainAllowed(uint64 indexed chainSelector, bool allowed);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event CCIPPaymentReceived(
        bytes32 indexed paymentId,
        address receiver,
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bool swapped
    );
    event CCIPMessageProcessingFailed(
        bytes32 indexed messageId,
        bytes32 indexed paymentId,
        uint64 indexed sourceChainSelector,
        bytes reason
    );
    event CCIPMessageRetried(bytes32 indexed messageId, bool success, bytes reason, uint256 retryCount);

    // ============ Errors ============

    error UntrustedSourceChain(uint64 chainSelector);
    error UntrustedSender(uint64 chainSelector, bytes sender);
    error PayloadDecodeFailed();
    error FailedMessageNotFound(bytes32 messageId);
    error UnauthorizedProcessor(address caller);
    
    // ============ Constructor ============

    constructor(
        address _ccipRouter,
        address _gateway
    ) CCIPReceiverBase(_ccipRouter) Ownable(msg.sender) {
        gateway = PaymentKitaGateway(_gateway);
        vault = gateway.vault();
    }

    // ============ Admin Functions ============

    /// @notice Set trusted sender for a source chain
    function setTrustedSender(uint64 chainSelector, bytes calldata sender) external onlyOwner {
        trustedSenders[chainSelector] = sender;
        allowedSourceChains[chainSelector] = true;
        emit TrustedSenderSet(chainSelector, sender);
        emit SourceChainAllowed(chainSelector, true);
    }

    /// @notice Toggle source chain allowance
    function setSourceChainAllowed(uint64 chainSelector, bool allowed) external onlyOwner {
        allowedSourceChains[chainSelector] = allowed;
        emit SourceChainAllowed(chainSelector, allowed);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = TokenSwapper(_swapper);
    }

    function setRouter(address _ccipRouter) external onlyOwner {
        address oldRouter = getRouter();
        _setRouter(_ccipRouter);
        emit RouterUpdated(oldRouter, _ccipRouter);
    }

    function setGateway(address _gateway) external onlyOwner {
        require(_gateway != address(0), "Invalid gateway");
        address oldVault = address(vault);
        emit GatewayUpdated(address(gateway), _gateway);
        gateway = PaymentKitaGateway(_gateway);
        vault = gateway.vault();
        emit VaultUpdated(oldVault, address(vault));
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    /// @notice Retry failed message processing
    function retryFailedMessage(bytes32 messageId) external onlyOwner {
        bytes memory encoded = failedMessages[messageId];
        if (encoded.length == 0) revert FailedMessageNotFound(messageId);

        Client.Any2EVMMessage memory message = abi.decode(encoded, (Client.Any2EVMMessage));
        uint256 retryCount = failedMessageRetryCount[messageId] + 1;
        failedMessageRetryCount[messageId] = retryCount;

        try this.processMessageEntry(message) {
            delete failedMessages[messageId];
            delete failedMessageReasons[messageId];
            delete failedMessageRetryCount[messageId];
            delete failedMessagePaymentIds[messageId];
            emit CCIPMessageRetried(messageId, true, bytes(""), retryCount);
        } catch (bytes memory reason) {
            failedMessageReasons[messageId] = reason;
            emit CCIPMessageRetried(messageId, false, reason, retryCount);
        }
    }

    /// @notice Diagnostic helper to inspect failed message status
    function getFailedMessageStatus(
        bytes32 messageId
    ) external view returns (bool exists, bytes32 paymentId, bytes memory reason, uint256 retryCount) {
        exists = failedMessages[messageId].length > 0;
        paymentId = failedMessagePaymentIds[messageId];
        reason = failedMessageReasons[messageId];
        retryCount = failedMessageRetryCount[messageId];
    }

    // ============ CCIPReceiver Implementation ============

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // --- Trust checks ---
        if (!allowedSourceChains[message.sourceChainSelector]) {
            revert UntrustedSourceChain(message.sourceChainSelector);
        }

        bytes memory trusted = trustedSenders[message.sourceChainSelector];
        if (trusted.length > 0 && keccak256(message.sender) != keccak256(trusted)) {
            revert UntrustedSender(message.sourceChainSelector, message.sender);
        }

        // Business processing is fail-open with failure ledger + manual retry.
        try this.processMessageEntry(message) {
            // Success path is emitted by _processMessage.
        } catch (bytes memory reason) {
            bytes32 paymentId = _extractPaymentId(message.data);
            failedMessages[message.messageId] = abi.encode(message);
            failedMessageReasons[message.messageId] = reason;
            failedMessagePaymentIds[message.messageId] = paymentId;
            emit CCIPMessageProcessingFailed(message.messageId, paymentId, message.sourceChainSelector, reason);
        }
    }

    /// @dev External entry used to enable try/catch for processing failures.
    /// Callable only by this contract via `this.processMessageEntry(...)`.
    function processMessageEntry(Client.Any2EVMMessage calldata message) external {
        if (msg.sender != address(this)) revert UnauthorizedProcessor(msg.sender);
        _processMessage(message);
    }

    function _processMessage(Client.Any2EVMMessage memory message) internal {
        // --- 4-field decode (matches CCIPSender._buildMessage payload) ---
        (
            bytes32 paymentId,
            address destToken,
            address receiver,
            uint256 minAmountOut,
            address encodedSourceToken
        ) = _decodePayload(message.data);

        // V1 payload has no source token; fallback means received token should equal destination token.
        address sourceToken = encodedSourceToken == address(0) ? destToken : encodedSourceToken;

        // --- Extract received token/amount ---
        require(message.destTokenAmounts.length > 0, "No tokens received");
        address receivedToken = message.destTokenAmounts[0].token;
        require(receivedToken == sourceToken, "Token Mismatch");
        uint256 receivedAmount = message.destTokenAmounts[0].amount;

        uint256 settledAmount = receivedAmount;
        address settledToken = receivedToken;
        bool swapped = false;

        if (sourceToken != destToken) {
            require(address(swapper) != address(0), "Swapper not configured");

            // Move received bridged token to vault and perform vault-based swap.
            IERC20(receivedToken).safeTransfer(address(vault), receivedAmount);
            settledAmount = swapper.swapFromVault(receivedToken, destToken, receivedAmount, minAmountOut, receiver);
            settledToken = destToken;
            swapped = true;
        } else {
            IERC20(receivedToken).safeTransfer(receiver, receivedAmount);
        }

        // --- Notify Gateway ---
        gateway.finalizeIncomingPayment(paymentId, receiver, settledToken, settledAmount);

        emit CCIPPaymentReceived(paymentId, receiver, settledToken, settledAmount, minAmountOut, swapped);
    }

    function _extractPaymentId(bytes memory data) internal pure returns (bytes32 paymentId) {
        if (data.length >= 32) {
            assembly {
                paymentId := mload(add(data, 32))
            }
        }
    }

    function _decodePayload(
        bytes memory data
    ) internal pure returns (bytes32 paymentId, address destToken, address receiver, uint256 minAmountOut, address sourceToken) {
        if (data.length >= 160) {
            (paymentId, destToken, receiver, minAmountOut, sourceToken) = abi.decode(
                data,
                (bytes32, address, address, uint256, address)
            );
            return (paymentId, destToken, receiver, minAmountOut, sourceToken);
        }

        (paymentId, destToken, receiver, minAmountOut) = abi.decode(data, (bytes32, address, address, uint256));
        return (paymentId, destToken, receiver, minAmountOut, address(0));
    }
}
