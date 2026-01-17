// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPayChain
 * @notice Interface for PayChain cross-chain payment gateway
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

    function createPayment(
        string calldata destChainId,
        address receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external returns (bytes32 paymentId);

    function processRefund(bytes32 paymentId) external;
}
