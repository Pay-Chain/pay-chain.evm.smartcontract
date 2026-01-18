// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IPayChain.sol";
import "./libraries/FeeCalculator.sol";

/**
 * @title PayChain
 * @notice Base contract for cross-chain payment gateway
 * @dev This is the main contract with core payment logic.
 *      Bridge-specific implementations inherit from this contract.
 *
 * Inheritance:
 * - PayChainCCIP.sol → for EVM ↔ SVM (Solana)
 * - PayChainHyperbridge.sol → for EVM ↔ EVM
 */
abstract contract PayChain is IPayChain, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using FeeCalculator for uint256;

    // ============ State Variables ============

    mapping(bytes32 => Payment) public payments;
    mapping(bytes32 => PaymentRequest) public paymentRequests;
    mapping(address => bool) public supportedTokens;

    address public feeRecipient;

    uint256 public constant FIXED_BASE_FEE = 0.50e6; // $0.50 in 6 decimals
    uint256 public constant FEE_RATE_BPS = 30; // 0.3%
    uint256 public constant REQUEST_EXPIRY_TIME = 15 minutes;
    uint256 public constant PAYMENT_TIMEOUT = 1 hours;

    // ============ Structs ============

    struct PaymentRequest {
        bytes32 id;
        address merchant;
        address receiver;
        address token;
        uint256 amount;
        string description;
        uint256 expiresAt;
        bool isPaid;
        address payer;
        bytes32 paymentId;
    }

    // ============ Events (additional) ============

    event TokenSupportUpdated(address token, bool supported);

    // ============ Constructor ============

    constructor(address _feeRecipient) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    // ============ Core Payment Functions ============

    /**
     * @notice Create a payment request for merchants (same-chain payments)
     * @param receiver Receiver wallet address
     * @param token Token address for payment
     * @param amount Amount requested
     * @param description Description of the payment
     */
    function createPaymentRequest(
        address receiver,
        address token,
        uint256 amount,
        string calldata description
    ) external nonReentrant whenNotPaused returns (bytes32 requestId) {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(receiver != address(0), "Invalid receiver");

        requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                receiver,
                token,
                amount,
                block.timestamp
            )
        );

        uint256 expiresAt = block.timestamp + REQUEST_EXPIRY_TIME;

        paymentRequests[requestId] = PaymentRequest({
            id: requestId,
            merchant: msg.sender,
            receiver: receiver,
            token: token,
            amount: amount,
            description: description,
            expiresAt: expiresAt,
            isPaid: false,
            payer: address(0),
            paymentId: bytes32(0)
        });

        emit PaymentRequestCreated(
            requestId,
            msg.sender,
            receiver,
            token,
            amount,
            expiresAt
        );

        return requestId;
    }

    /**
     * @notice Pay a payment request (same-chain payment)
     * @param requestId Payment request ID to pay
     */
    function payRequest(bytes32 requestId) external nonReentrant whenNotPaused {
        PaymentRequest storage request = paymentRequests[requestId];
        require(request.id == requestId, "Request not found");
        require(!request.isPaid, "Already paid");
        require(block.timestamp <= request.expiresAt, "Request expired");

        // Calculate fees
        uint256 platformFee = request.amount.calculatePlatformFee(
            FIXED_BASE_FEE,
            FEE_RATE_BPS
        );
        uint256 totalAmount = request.amount + platformFee;

        // Transfer tokens from payer
        IERC20(request.token).safeTransferFrom(
            msg.sender,
            address(this),
            totalAmount
        );

        // Transfer amount to receiver
        IERC20(request.token).safeTransfer(request.receiver, request.amount);

        // Transfer fee to fee recipient
        IERC20(request.token).safeTransfer(feeRecipient, platformFee);

        // Update request status
        request.isPaid = true;
        request.payer = msg.sender;

        emit RequestPaymentReceived(
            requestId,
            msg.sender,
            request.receiver,
            request.token,
            request.amount
        );
    }

    /**
     * @notice Process refund for failed/expired payment
     * @param paymentId Payment ID to refund
     */
    function processRefund(bytes32 paymentId) external nonReentrant {
        Payment storage payment = payments[paymentId];
        require(
            payment.status == PaymentStatus.Failed ||
                (payment.status == PaymentStatus.Pending &&
                    block.timestamp >= payment.createdAt + PAYMENT_TIMEOUT),
            "Cannot refund"
        );
        require(payment.sender != address(0), "Payment not found");

        payment.status = PaymentStatus.Refunded;

        // Refund only the amount (fee is not refunded per PRD)
        IERC20(payment.sourceToken).safeTransfer(
            payment.sender,
            payment.amount
        );

        emit PaymentRefunded(paymentId, payment.amount);
    }

    // ============ Admin Functions ============

    function setSupportedToken(
        address token,
        bool supported
    ) external onlyOwner {
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    function markPaymentFailed(bytes32 paymentId) external onlyOwner {
        Payment storage payment = payments[paymentId];
        require(payment.status == PaymentStatus.Processing, "Not processing");
        payment.status = PaymentStatus.Failed;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Receive native tokens for bridge fees
    receive() external payable {}

    // ============ View Functions ============

    function getPayment(
        bytes32 paymentId
    ) external view returns (Payment memory) {
        return payments[paymentId];
    }

    function getPaymentRequest(
        bytes32 requestId
    ) external view returns (PaymentRequest memory) {
        return paymentRequests[requestId];
    }

    function isRequestExpired(bytes32 requestId) external view returns (bool) {
        return block.timestamp > paymentRequests[requestId].expiresAt;
    }

    // ============ Internal Helpers ============

    function _getChainId() internal view returns (string memory) {
        return string(abi.encodePacked("eip155:", _uint2str(block.chainid)));
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
        uint256 k = length;
        while (_i != 0) {
            k--;
            bstr[k] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }

    // ============ Abstract Functions (for bridge implementations) ============

    /**
     * @dev Create a cross-chain payment - implemented by bridge contracts
     */
    function createPayment(
        bytes calldata destChainId,
        bytes calldata receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external virtual returns (bytes32 paymentId);

    /**
     * @dev Execute a pending payment - implemented by bridge contracts
     */
    function executePayment(bytes32 paymentId) external payable virtual;
}
