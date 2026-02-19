// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@hyperbridge/core/apps/HyperApp.sol";
import {PostRequest} from "@hyperbridge/core/libraries/Message.sol";
import "../../vaults/PayChainVault.sol";
import "../../PayChainGateway.sol";
import "../../TokenSwapper.sol";

/**
 * @title HyperbridgeReceiver
 * @notice Bridge Adapter for receiving Hyperbridge messages (ISMP)
 */
contract HyperbridgeReceiver is HyperApp, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainGateway public gateway;
    PayChainVault public vault;
    TokenSwapper public swapper;

    /// @notice Whether to automatically process refunds on timeout
    bool public autoRefundOnTimeout;

    event PostRequestTimedOut(bytes32 indexed paymentId, bool refunded);
    event TrustedSenderSet(bytes32 indexed sourceChainHash, bytes trustedSender);
    event AutoRefundOnTimeoutSet(bool enabled);
    
    // ============ Constructor ============

    constructor(
        address _host,
        address _gateway,
        address _vault
    ) Ownable(msg.sender) {
        _HYPERBRIDGE_HOST = _host; // HyperApp internal var
        gateway = PayChainGateway(_gateway);
        vault = PayChainVault(_vault);
    }

    /// @notice Trusted senders on source chains (sourceChainHash => senderAddressBytes)
    mapping(bytes32 => bytes) public trustedSenders;

    /// @notice Set a trusted sender for a specific source chain
    /// @param sourceChainId The Hyperbridge state machine ID of the source chain (e.g. "EVM-1")
    /// @param trustedSender The address of the trusted sender contract on that chain
    function setTrustedSender(bytes calldata sourceChainId, bytes calldata trustedSender) external onlyOwner {
        bytes32 sourceHash = keccak256(sourceChainId);
        trustedSenders[sourceHash] = trustedSender;
        emit TrustedSenderSet(sourceHash, trustedSender);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = TokenSwapper(_swapper);
    }

    /// @notice Enable or disable automatic refund processing on timeout
    function setAutoRefundOnTimeout(bool _enabled) external onlyOwner {
        autoRefundOnTimeout = _enabled;
        emit AutoRefundOnTimeoutSet(_enabled);
    }

    // ============ HyperApp Implementation ============
    
    // HyperApp usually requires implementing `onAccept`
    // Depending on version, it might be `onPost` or `onGet` support.
    // Assuming simple `onAccept` for PostRequest.

    function onAccept(IncomingPostRequest calldata request) external override onlyHost {

        // 0. Verify Source & Sender (CRITICAL FIX)
        bytes32 sourceHash = keccak256(request.request.source);
        bytes memory trustedSender = trustedSenders[sourceHash];
        require(trustedSender.length > 0, "Source chain not trusted");
        
        // Compare byte arrays by hashing
        require(
            keccak256(request.request.from) == keccak256(trustedSender),
            "Unauthorized sender"
        );

        // 1. Decode Body
        (
            bytes32 paymentId,
            uint256 amount,
            address destToken,
            address receiver,
            uint256 minAmountOut,
            address sourceToken
        ) = _decodePayload(request.request.body);
        require(amount >= minAmountOut, "Insufficient amount out");

        // 2. Liquidity Management
        // Hyperbridge here is used as Messaging. We need to release funds from Vault.
        // Adapter must be authorized on Vault.
        
        // Check if swap needed? For now assuming destToken is what defines the payout.
        // We verify we have enough balance in Vault? Vault check handles it.
        
        uint256 settledAmount = amount;
        address settledToken = destToken;

        if (sourceToken != address(0) && sourceToken != destToken) {
            require(address(swapper) != address(0), "Swapper not configured");
            settledAmount = swapper.swapFromVault(sourceToken, destToken, amount, minAmountOut, receiver);
        } else {
            vault.pushTokens(destToken, receiver, amount);
        }

        // 3. Notify Gateway
        gateway.finalizeIncomingPayment(
            paymentId,
            receiver,
            settledToken,
            settledAmount
        );
    }
    
    // Internal state for host helper
    address private immutable _HYPERBRIDGE_HOST;
    
    function host() public view override returns (address) {
        return _HYPERBRIDGE_HOST;
    }

    // ============ Timeout Handler ============

    /// @notice Handle timed-out post requests from Hyperbridge
    /// @dev Called by the ISMP host when a dispatched message is not delivered before timeout
    /// @param request The original PostRequest that timed out
    function onPostRequestTimeout(PostRequest memory request) external override onlyHost {
        // Decode only paymentId with backward-compatible payload handling
        (bytes32 paymentId,,,,,) = _decodePayload(request.body);
        gateway.markPaymentFailed(paymentId, "HYPERBRIDGE_TIMEOUT");

        // HB-2: Optionally process refund atomically
        bool refunded = false;
        if (autoRefundOnTimeout) {
            gateway.processRefund(paymentId);
            refunded = true;
        }

        emit PostRequestTimedOut(paymentId, refunded);
    }

    function _decodePayload(
        bytes memory data
    )
        internal
        pure
        returns (
            bytes32 paymentId,
            uint256 amount,
            address destToken,
            address receiver,
            uint256 minAmountOut,
            address sourceToken
        )
    {
        if (data.length >= 192) {
            (paymentId, amount, destToken, receiver, minAmountOut, sourceToken) = abi.decode(
                data,
                (bytes32, uint256, address, address, uint256, address)
            );
            return (paymentId, amount, destToken, receiver, minAmountOut, sourceToken);
        }

        (paymentId, amount, destToken, receiver, minAmountOut) = abi.decode(
            data,
            (bytes32, uint256, address, address, uint256)
        );
        return (paymentId, amount, destToken, receiver, minAmountOut, destToken);
    }
}
