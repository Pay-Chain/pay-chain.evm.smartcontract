// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IBridgeAdapter.sol";

/**
 * @title PayChainRouter
 * @notice Manages bridge adapters and routes cross-chain payments
 * @dev Registry for bridge adapters per chain and type
 */
contract PayChainRouter is Ownable, ReentrancyGuard {
    // ============ State Variables ============

    /// @notice Mapping from destChainId (string) => bridgeType (uint8) => Adapter Address
    /// @dev bridgeType: 0 = CCIP, 1 = Hyperbridge (mapped in Gateway)
    mapping(string => mapping(uint8 => address)) public adapters;

    // ============ Events ============

    event AdapterRegistered(string destChainId, uint8 bridgeType, address adapter);
    event PaymentRouted(bytes32 indexed paymentId, string destChainId, uint8 bridgeType, address adapter);

    // ============ Errors ============

    error AdapterNotFound(string destChainId, uint8 bridgeType);
    error InvalidAdapter();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Admin Functions ============

    /**
     * @notice Register or update a bridge adapter
     * @param destChainId Destination chain identifier
     * @param bridgeType Bridge type enum value
     * @param adapter Address of the adapter contract
     */
    function registerAdapter(
        string calldata destChainId,
        uint8 bridgeType,
        address adapter
    ) external onlyOwner {
        if (adapter == address(0)) revert InvalidAdapter();
        adapters[destChainId][bridgeType] = adapter;
        emit AdapterRegistered(destChainId, bridgeType, adapter);
    }

    // ============ View Functions ============

    /**
     * @notice Get adapter for a specific route
     */
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address) {
        return adapters[destChainId][bridgeType];
    }

    /**
     * @notice Check if an adapter is registered for a route
     * @param destChainId Destination chain ID
     * @param bridgeType Bridge type
     * @return True if adapter exists for this route
     */
    function hasAdapter(string memory destChainId, uint8 bridgeType) public view returns (bool) {
        return adapters[destChainId][bridgeType] != address(0);
    }

    /**
     * @notice Estimate fee for a cross-chain payment
     * @param destChainId Destination chain ID
     * @param bridgeType Bridge type
     * @param message Bridge message details
     * @return fee Estimated fee in native token
     */
    function quotePaymentFee(
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view returns (uint256 fee) {
        address adapter = adapters[destChainId][bridgeType];
        if (adapter == address(0)) revert AdapterNotFound(destChainId, bridgeType);
        
        return IBridgeAdapter(adapter).quoteFee(message);
    }

    // ============ Core Logic ============

    /**
     * @notice Route a payment to the appropriate bridge adapter
     * @dev Called by PayChainGateway. Funds should already be in the Vault/approved.
     * @param destChainId Destination chain string
     * @param bridgeType Bridge type
     * @param message Standardized bridge message
     * @return messageId Bridge-specific message ID
     */
    function routePayment(
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external payable nonReentrant returns (bytes32 messageId) {
        address adapter = adapters[destChainId][bridgeType];
        if (adapter == address(0)) revert AdapterNotFound(destChainId, bridgeType);

        emit PaymentRouted(message.paymentId, destChainId, bridgeType, adapter);

        // Delegate to adapter
        // msg.value is passed along for gas/fees
        // Safe: Loop restricted by nonReentrant modifier and trusted adapter registry
        return IBridgeAdapter(adapter).sendMessage{value: msg.value}(message);
    }
}
