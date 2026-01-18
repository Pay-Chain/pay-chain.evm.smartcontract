// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPayChain
 * @notice Interface for PayChain cross-chain payment gateway
 * @dev Base interface for all PayChain implementations
 */
interface IPayChain {
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

    function createPayment(
        bytes calldata destChainId,
        bytes calldata receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external returns (bytes32 paymentId);

    function executePayment(bytes32 paymentId) external payable;

    function createPaymentRequest(
        address receiver,
        address token,
        uint256 amount,
        string calldata description
    ) external returns (bytes32 requestId);

    function payRequest(bytes32 requestId) external;

    function processRefund(bytes32 paymentId) external;

    function getPayment(
        bytes32 paymentId
    ) external view returns (Payment memory);

    function isRequestExpired(bytes32 requestId) external view returns (bool);
}
