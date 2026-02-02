// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBridgeAdapter
 * @notice Interface for Cross-Chain Bridge Adapters (CCIP, Hyperbridge, etc.)
 * @dev Adapters handle the specific logic of encoding/decoding and sending/receiving messages for a specific bridge protocol.
 */
interface IBridgeAdapter {
    struct BridgeMessage {
        bytes32 paymentId;
        address receiver;
        address sourceToken;
        address destToken;
        uint256 amount;
        string destChainId; // CAIP-2 or string identifier used by the bridge
        uint256 minAmountOut; // Minimum amount to receive on destination (slippage protection)
    }

    // ============ Sender Functions ============

    /**
     * @notice Send a cross-chain payment via this bridge
     * @param message Struct containing standard payment details
     * @return messageId The bridge-specific message ID
     */
    function sendMessage(BridgeMessage calldata message) external payable returns (bytes32 messageId);

    /**
     * @notice Estimate fee for sending a message
     * @param message Struct containing standard payment details
     * @return fee The estimated fee in native token
     */
    function quoteFee(BridgeMessage calldata message) external view returns (uint256 fee);
    
    // ============ Receiver Functions ============
    
    // Receiver logic is usually internal (callback from bridge), but executed by the Adapter 
    // and then calling back to the Gateway/Router to finalize.
}
