// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CCIPReceiverBase.sol";
import "./Client.sol";
import "../../PayChainGateway.sol";
import "../../vaults/PayChainVault.sol";
import "../../TokenSwapper.sol";

/**
 * @title CCIPReceiverAdapter
 * @notice Bridge Adapter for receiving CCIP messages with trust model
 * @dev Phase 1.3: Added trustedSenders, allowedSourceChains, 4-field decode
 */
contract CCIPReceiverAdapter is CCIPReceiverBase, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainGateway public gateway;
    PayChainVault public vault;
    TokenSwapper public swapper;

    /// @notice Trusted sender addresses per source chain selector
    mapping(uint64 => bytes) public trustedSenders;

    /// @notice Allowed source chain selectors
    mapping(uint64 => bool) public allowedSourceChains;

    // ============ Events ============

    event TrustedSenderSet(uint64 indexed chainSelector, bytes sender);
    event SourceChainAllowed(uint64 indexed chainSelector, bool allowed);
    event CCIPPaymentReceived(
        bytes32 indexed paymentId,
        address receiver,
        address token,
        uint256 amount,
        uint256 minAmountOut,
        bool swapped
    );

    // ============ Errors ============

    error UntrustedSourceChain(uint64 chainSelector);
    error UntrustedSender(uint64 chainSelector, bytes sender);
    error PayloadDecodeFailed();
    
    // ============ Constructor ============

    constructor(
        address _ccipRouter,
        address _gateway
    ) CCIPReceiverBase(_ccipRouter) Ownable(msg.sender) {
        gateway = PayChainGateway(_gateway);
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
