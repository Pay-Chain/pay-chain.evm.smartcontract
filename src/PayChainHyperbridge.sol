// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PayChain.sol";
import "@hyperbridge/core/apps/HyperApp.sol";
import "@hyperbridge/core/interfaces/IDispatcher.sol";
import "@hyperbridge/core/libraries/Message.sol";

/**
 * @title PayChainHyperbridge
 * @notice Cross-chain payment gateway using Hyperbridge ISMP
 * @dev For EVM ↔ EVM transfers
 *
 * Inherits from:
 * - PayChain (core payment logic)
 * - HyperApp (Hyperbridge SDK)
 */
contract PayChainHyperbridge is PayChain, HyperApp {
    using SafeERC20 for IERC20;
    using FeeCalculator for uint256;

    // ============ State Variables ============

    /// @notice Hyperbridge Host address (immutable per chain)
    address private immutable _hyperbridgeHost;

    /// @notice Destination contract for cross-chain calls
    address public destinationContract;

    /// @notice Supported chains (keccak256(stateMachineId) → bool)
    mapping(bytes32 => bool) public supportedChains;

    // ============ Events ============

    event ChainSupportUpdated(bytes stateMachineId, bool supported);
    event DestinationContractUpdated(address destination);

    // ============ Constructor ============

    constructor(address _host, address _feeRecipient) PayChain(_feeRecipient) {
        require(_host != address(0), "Invalid host");
        _hyperbridgeHost = _host;
    }

    // ============ HyperApp Override ============

    function host() public view override returns (address) {
        return _hyperbridgeHost;
    }

    // ============ Cross-Chain Payment Functions ============

    /**
     * @notice Create a cross-chain payment via Hyperbridge
     * @param destChainId Destination StateMachine ID (e.g., "EVM-8453" for Base)
     * @param receiver Receiver address (as bytes)
     * @param sourceToken Source token address
     * @param destToken Destination token address
     * @param amount Amount to send (before fees)
     */
    function createPayment(
        bytes calldata destChainId,
        bytes calldata receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external override nonReentrant whenNotPaused returns (bytes32 paymentId) {
        require(supportedTokens[sourceToken], "Source token not supported");
        require(
            supportedChains[keccak256(destChainId)],
            "Destination chain not supported"
        );
        require(
            destinationContract != address(0),
            "Destination contract not set"
        );
        require(amount > 0, "Amount must be greater than 0");

        // Calculate fees
        uint256 platformFee = amount.calculatePlatformFee(
            FIXED_BASE_FEE,
            FEE_RATE_BPS
        );
        uint256 totalAmount = amount + platformFee;

        // Transfer tokens from sender
        IERC20(sourceToken).safeTransferFrom(
            msg.sender,
            address(this),
            totalAmount
        );

        // Generate payment ID
        paymentId = keccak256(
            abi.encodePacked(
                msg.sender,
                receiver,
                destChainId,
                amount,
                block.timestamp,
                block.chainid
            )
        );

        // Store payment
        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: abi.decode(receiver, (address)),
            sourceChainId: _getChainId(),
            destChainId: string(destChainId),
            sourceToken: sourceToken,
            destToken: destToken,
            amount: amount,
            fee: platformFee,
            status: PaymentStatus.Pending,
            createdAt: block.timestamp
        });

        emit PaymentCreated(
            paymentId,
            msg.sender,
            abi.decode(receiver, (address)),
            string(destChainId),
            sourceToken,
            destToken,
            amount,
            platformFee,
            "Hyperbridge"
        );

        return paymentId;
    }

    /**
     * @notice Execute a pending payment via Hyperbridge ISMP
     * @param paymentId Payment ID to execute
     */
    function executePayment(
        bytes32 paymentId
    ) external payable override nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.status == PaymentStatus.Pending, "Payment not pending");
        require(payment.sender == msg.sender, "Not payment sender");

        // Build ISMP POST request body
        bytes memory body = abi.encode(
            paymentId,
            abi.encode(payment.receiver),
            payment.amount,
            payment.sourceToken
        );

        // Build DispatchPost
        DispatchPost memory postRequest = DispatchPost({
            dest: bytes(payment.destChainId),
            to: abi.encodePacked(destinationContract),
            body: body,
            timeout: uint64(PAYMENT_TIMEOUT),
            fee: 0,
            payer: address(this)
        });

        // Get fee quote and dispatch
        uint256 requiredFee = quoteNative(postRequest);
        require(
            msg.value >= requiredFee,
            "Insufficient native for Hyperbridge fee"
        );

        // Dispatch via Hyperbridge
        bytes32 commitment = IDispatcher(_hyperbridgeHost).dispatch{
            value: msg.value
        }(postRequest);

        // Update payment status
        payment.status = PaymentStatus.Processing;

        // Transfer platform fee to recipient
        IERC20(payment.sourceToken).safeTransfer(feeRecipient, payment.fee);

        emit PaymentExecuted(paymentId, commitment);

        // Refund excess
        if (msg.value > requiredFee) {
            (bool success, ) = msg.sender.call{value: msg.value - requiredFee}(
                ""
            );
            require(success, "Refund failed");
        }
    }

    // ============ Hyperbridge Callbacks ============

    /**
     * @notice Handle incoming POST request from Hyperbridge
     * @param incoming The incoming POST request
     */
    function onAccept(
        IncomingPostRequest calldata incoming
    ) external override onlyHost {
        // Decode the POST request body
        (
            bytes32 paymentId,
            bytes memory receiverBytes,
            uint256 amount,
            address token
        ) = abi.decode(
                incoming.request.body,
                (bytes32, bytes, uint256, address)
            );

        // Convert receiver bytes to address
        address receiver = abi.decode(receiverBytes, (address));

        // Transfer tokens to receiver
        IERC20(token).safeTransfer(receiver, amount);

        emit PaymentCompleted(paymentId, amount);
    }

    /**
     * @notice Handle POST request timeout
     * @param request The timed-out request
     */
    function onPostRequestTimeout(
        PostRequest memory request
    ) external override onlyHost {
        // Decode to get payment ID
        (bytes32 paymentId, , , ) = abi.decode(
            request.body,
            (bytes32, bytes, uint256, address)
        );

        Payment storage payment = payments[paymentId];
        if (payment.status == PaymentStatus.Processing) {
            payment.status = PaymentStatus.Failed;
        }
    }

    // ============ Admin Functions ============

    function setSupportedChain(
        bytes calldata stateMachineId,
        bool supported
    ) external onlyOwner {
        supportedChains[keccak256(stateMachineId)] = supported;
        emit ChainSupportUpdated(stateMachineId, supported);
    }

    function setDestinationContract(address _destination) external onlyOwner {
        require(_destination != address(0), "Invalid destination");
        destinationContract = _destination;
        emit DestinationContractUpdated(_destination);
    }

    function isSupportedChain(
        bytes calldata stateMachineId
    ) external view returns (bool) {
        return supportedChains[keccak256(stateMachineId)];
    }
}
