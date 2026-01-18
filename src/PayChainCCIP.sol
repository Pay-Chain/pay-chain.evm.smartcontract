// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./PayChain.sol";
import "./ccip/Client.sol";
import "./ccip/IRouterClient.sol";
import "./ccip/CCIPReceiver.sol";

/**
 * @title PayChainCCIP
 * @notice Cross-chain payment gateway using Chainlink CCIP
 * @dev For EVM ↔ SVM (Solana) transfers
 *
 * Inherits from:
 * - PayChain (core payment logic)
 * - CCIPReceiver (CCIP message handling)
 */
contract PayChainCCIP is PayChain, CCIPReceiver {
    using SafeERC20 for IERC20;
    using FeeCalculator for uint256;

    // ============ State Variables ============

    /// @notice CCIP chain selectors (CAIP-2 chain ID → CCIP selector)
    mapping(string => uint64) public chainSelectors;

    /// @notice Supported destination chains
    mapping(string => bool) public supportedChains;

    // ============ Events ============

    event ChainSelectorUpdated(string chainId, uint64 selector);
    event ChainSupportUpdated(string chainId, bool supported);

    // ============ Constructor ============

    constructor(
        address _ccipRouter,
        address _feeRecipient
    ) PayChain(_feeRecipient) CCIPReceiver(_ccipRouter) {}

    // ============ Cross-Chain Payment Functions ============

    /**
     * @notice Create a cross-chain payment via CCIP
     * @param destChainId Destination chain ID (CAIP-2 format as bytes)
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
        string memory destChainString = string(destChainId);

        require(supportedTokens[sourceToken], "Source token not supported");
        require(
            supportedChains[destChainString],
            "Destination chain not supported"
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
            destChainId: destChainString,
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
            destChainString,
            sourceToken,
            destToken,
            amount,
            platformFee,
            "CCIP"
        );

        return paymentId;
    }

    /**
     * @notice Execute a pending payment via CCIP
     * @param paymentId Payment ID to execute
     */
    function executePayment(
        bytes32 paymentId
    ) external payable override nonReentrant whenNotPaused {
        Payment storage payment = payments[paymentId];
        require(payment.status == PaymentStatus.Pending, "Payment not pending");
        require(payment.sender == msg.sender, "Not payment sender");

        uint64 destChainSelector = chainSelectors[payment.destChainId];
        require(destChainSelector != 0, "Chain selector not set");

        // Prepare token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: payment.sourceToken,
            amount: payment.amount
        });

        // Build CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(payment.receiver),
            data: abi.encode(paymentId, payment.amount, payment.destToken),
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // Pay in native token
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: 200_000,
                    allowOutOfOrderExecution: true
                })
            )
        });

        // Calculate CCIP fee
        uint256 ccipFee = IRouterClient(i_ccipRouter).getFee(
            destChainSelector,
            message
        );
        require(msg.value >= ccipFee, "Insufficient native for CCIP fee");

        // Approve router to transfer tokens
        IERC20(payment.sourceToken).approve(i_ccipRouter, payment.amount);

        // Send via CCIP
        bytes32 messageId = IRouterClient(i_ccipRouter).ccipSend{
            value: ccipFee
        }(destChainSelector, message);

        // Update payment status
        payment.status = PaymentStatus.Processing;

        // Transfer platform fee to recipient
        IERC20(payment.sourceToken).safeTransfer(feeRecipient, payment.fee);

        emit PaymentExecuted(paymentId, messageId);

        // Refund excess native token
        if (msg.value > ccipFee) {
            (bool success, ) = msg.sender.call{value: msg.value - ccipFee}("");
            require(success, "Refund failed");
        }
    }

    // ============ CCIP Receiver ============

    /**
     * @notice Handle incoming CCIP messages
     * @param message CCIP message
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // Decode payment data
        (bytes32 paymentId, uint256 amount, ) = abi.decode(
            message.data,
            (bytes32, uint256, address)
        );

        // Get receiver from sender bytes
        address receiver = abi.decode(message.sender, (address));

        // If tokens were sent, they're in destTokenAmounts
        if (message.destTokenAmounts.length > 0) {
            address receivedToken = message.destTokenAmounts[0].token;
            uint256 receivedAmount = message.destTokenAmounts[0].amount;

            // Transfer tokens to receiver
            IERC20(receivedToken).safeTransfer(receiver, receivedAmount);

            emit PaymentCompleted(paymentId, receivedAmount);
        }
    }

    // ============ Admin Functions ============

    function setChainSelector(
        string calldata chainId,
        uint64 selector
    ) external onlyOwner {
        chainSelectors[chainId] = selector;
        emit ChainSelectorUpdated(chainId, selector);
    }

    function setSupportedChain(
        string calldata chainId,
        bool supported
    ) external onlyOwner {
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /// @notice Withdraw native tokens (for CCIP fees)
    function withdrawNative(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }
}
