// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPaymentKita
 * @notice Interface for PaymentKita cross-chain payment gateway
 * @dev Base interface for all PaymentKita implementations
 */
interface IPaymentKitaGateway {
    enum PaymentMode {
        REGULAR,
        PRIVACY
    }

    enum PaymentStatus {
        Pending,
        Processing,
        Completed,
        Failed,
        Refunded
    }

    struct Payment {
        address sender;
        address receiver;
        string sourceChainId;
        string destChainId;
        address sourceToken;
        address destToken;
        uint256 amount;
        uint256 fee;
        PaymentStatus status;
        uint256 createdAt;
    }

    struct PaymentRequestV2 {
        bytes destChainIdBytes;
        bytes receiverBytes;
        address sourceToken;
        address bridgeTokenSource;
        address destToken;
        uint256 amountInSource;
        uint256 minBridgeAmountOut;
        uint256 minDestAmountOut;
        PaymentMode mode;
        // Sentinel bridge option for V2 request:
        // 255 => use default bridge mapping in gateway
        // 0   => Hyperbridge
        // 1   => CCIP
        // 2   => LayerZero
        uint8 bridgeOption;
    }

    struct PrivateRouting {
        bytes32 intentId;
        address stealthReceiver;
    }

    // ============ Events ============

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

    event PaymentExecuted(bytes32 indexed paymentId, bytes32 messageId);

    event PaymentCompleted(bytes32 indexed paymentId, uint256 destAmount);

    event PaymentRefunded(bytes32 indexed paymentId, uint256 refundAmount);

    event PaymentRequestCreated(
        bytes32 indexed requestId,
        address indexed merchant,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 expiresAt
    );

    event RequestPaymentReceived(
        bytes32 indexed requestId,
        address indexed payer,
        address indexed receiver,
        address token,
        uint256 amount
    );

    // ============ Functions ============

    function createPayment(PaymentRequestV2 calldata req) external payable returns (bytes32 paymentId);

    function createPaymentPrivate(
        PaymentRequestV2 calldata req,
        PrivateRouting calldata privacy
    ) external payable returns (bytes32 paymentId);

    function createPaymentDefaultBridge(PaymentRequestV2 calldata req) external payable returns (bytes32 paymentId);

    function executePayment(bytes32 paymentId) external payable;

    function processRefund(bytes32 paymentId) external;

    function getPayment(
        bytes32 paymentId
    ) external view returns (Payment memory);

    function retryMessage(bytes32 messageId) external;

    function quotePaymentCost(
        PaymentRequestV2 calldata req
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 bridgeFeeNative,
            uint256 totalSourceTokenRequired,
            uint8 bridgeType,
            bool bridgeQuoteOk,
            string memory bridgeQuoteReason
        );

    function previewApproval(
        PaymentRequestV2 calldata req
    ) external view returns (address approvalToken, uint256 approvalAmount, uint256 requiredNativeFee);

    function finalizePrivacyForward(bytes32 paymentId, address token, uint256 amount) external;

    function reportPrivacyForwardFailure(bytes32 paymentId, string calldata reason) external;
}
