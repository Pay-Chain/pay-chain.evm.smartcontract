// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPayChain.sol";
import "./libraries/FeeCalculator.sol";

/**
 * @title PayChain
 * @notice Cross-chain stablecoin payment gateway contract
 * @dev Integrates with Chainlink CCIP for cross-chain messaging
 */
contract PayChain is IPayChain, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using FeeCalculator for uint256;

    // State variables
    mapping(bytes32 => Payment) public payments;
    mapping(address => bool) public supportedTokens;
    mapping(string => bool) public supportedChains;
    
    address public ccipRouter;
    address public feeRecipient;
    
    uint256 public constant FIXED_BASE_FEE = 0.50e6; // $0.50 in 6 decimals
    uint256 public constant FEE_RATE_BPS = 30; // 0.3%

    // Events
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

    event PaymentExecuted(
        bytes32 indexed paymentId,
        bytes32 ccipMessageId
    );

    event PaymentCompleted(
        bytes32 indexed paymentId,
        uint256 destAmount
    );

    event PaymentRefunded(
        bytes32 indexed paymentId,
        uint256 refundAmount
    );

    event TokenSupportUpdated(address token, bool supported);
    event ChainSupportUpdated(string chainId, bool supported);

    constructor(address _ccipRouter, address _feeRecipient) Ownable(msg.sender) {
        ccipRouter = _ccipRouter;
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Create a new cross-chain payment
     * @param destChainId Destination chain ID in CAIP-2 format
     * @param receiver Receiver address on destination chain
     * @param sourceToken Source token address
     * @param destToken Destination token address
     * @param amount Amount to send (before fees)
     */
    function createPayment(
        string calldata destChainId,
        address receiver,
        address sourceToken,
        address destToken,
        uint256 amount
    ) external nonReentrant returns (bytes32 paymentId) {
        require(supportedTokens[sourceToken], "Source token not supported");
        require(supportedChains[destChainId], "Destination chain not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Calculate fees
        uint256 platformFee = amount.calculatePlatformFee(FIXED_BASE_FEE, FEE_RATE_BPS);
        uint256 totalAmount = amount + platformFee;

        // Transfer tokens from sender
        IERC20(sourceToken).safeTransferFrom(msg.sender, address(this), totalAmount);

        // Generate payment ID
        paymentId = keccak256(
            abi.encodePacked(
                msg.sender,
                receiver,
                destChainId,
                amount,
                block.timestamp
            )
        );

        // Store payment
        payments[paymentId] = Payment({
            sender: msg.sender,
            receiver: receiver,
            sourceChainId: _getChainId(),
            destChainId: destChainId,
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
            receiver,
            destChainId,
            sourceToken,
            destToken,
            amount,
            platformFee,
            "CCIP"
        );

        return paymentId;
    }

    /**
     * @notice Process refund for failed payment
     * @param paymentId Payment ID to refund
     */
    function processRefund(bytes32 paymentId) external nonReentrant {
        Payment storage payment = payments[paymentId];
        require(payment.status == PaymentStatus.Failed, "Payment not failed");
        require(payment.sender != address(0), "Payment not found");

        payment.status = PaymentStatus.Refunded;

        // Refund only the amount (fee is not refunded)
        IERC20(payment.sourceToken).safeTransfer(payment.sender, payment.amount);

        emit PaymentRefunded(paymentId, payment.amount);
    }

    // Admin functions
    function setSupportedToken(address token, bool supported) external onlyOwner {
        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setSupportedChain(string calldata chainId, bool supported) external onlyOwner {
        supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    // Internal functions
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
            bstr[k] = bytes1(uint8(48 + _i % 10));
            _i /= 10;
        }
        return string(bstr);
    }
}
