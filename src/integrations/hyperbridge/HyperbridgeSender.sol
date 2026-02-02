// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PayChainVault.sol";
import {IDispatcher, DispatchPost} from "@hyperbridge/core/interfaces/IDispatcher.sol";
import {IHost} from "@hyperbridge/core/interfaces/IHost.sol";

/**
 * @title HyperbridgeSender
 * @notice Bridge Adapter for sending Hyperbridge ISMP messages
 * @dev Implements full ISMP dispatch using Hyperbridge host/dispatcher
 * 
 * Architecture:
 * - PayChain uses a Liquidity Network model on top of ISMP messaging
 * - Tokens are locked in the source Vault
 * - ISMP message instructs the destination receiver to release tokens
 * - No native token bridging - messaging only
 */
contract HyperbridgeSender is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainVault public vault;
    
    /// @notice The Hyperbridge Host contract (implements IHost & IDispatcher)
    IHost public host;
    
    /// @notice State machine identifiers for destination chains
    /// @dev Format: "POLKADOT-1000", "EVM-1", "EVM-42161", etc.
    mapping(string => bytes) public stateMachineIds;
    
    /// @notice Destination PayChain receiver contract addresses
    mapping(string => bytes) public destinationContracts;

    /// @notice Default timeout for requests (1 hour)
    uint64 public defaultTimeout = 3600;

    // ============ Events ============

    event MessageDispatched(
        bytes32 indexed commitment,
        string indexed destChainId,
        bytes32 paymentId,
        uint256 amount,
        address receiver
    );

    event StateMachineIdSet(string indexed chainId, bytes stateMachineId);
    event DestinationContractSet(string indexed chainId, bytes destination);
    event TimeoutUpdated(uint64 oldTimeout, uint64 newTimeout);

    // ============ Errors ============

    error StateMachineIdNotSet(string chainId);
    error DestinationNotSet(string chainId);
    error InvalidTimeout();
    error ZeroAddress();

    // ============ Constructor ============

    constructor(
        address _vault,
        address _host
    ) Ownable(msg.sender) {
        if (_vault == address(0) || _host == address(0)) revert ZeroAddress();
        vault = PayChainVault(_vault);
        host = IHost(_host);
    }

    // ============ Admin Functions ============

    /// @notice Set the state machine identifier for a chain
    /// @param chainId CAIP-2 chain identifier (e.g., "eip155:1")
    /// @param stateMachineId Hyperbridge state machine ID (e.g., "EVM-1")
    function setStateMachineId(string calldata chainId, bytes calldata stateMachineId) external onlyOwner {
        stateMachineIds[chainId] = stateMachineId;
        emit StateMachineIdSet(chainId, stateMachineId);
    }

    /// @notice Set the destination contract for a chain
    /// @param chainId CAIP-2 chain identifier
    /// @param destination Encoded destination contract address
    function setDestinationContract(string calldata chainId, bytes calldata destination) external onlyOwner {
        destinationContracts[chainId] = destination;
        emit DestinationContractSet(chainId, destination);
    }

    /// @notice Update the default timeout
    /// @param newTimeout New timeout in seconds
    function setDefaultTimeout(uint64 newTimeout) external onlyOwner {
        if (newTimeout < 300) revert InvalidTimeout(); // Minimum 5 minutes
        emit TimeoutUpdated(defaultTimeout, newTimeout);
        defaultTimeout = newTimeout;
    }

    /// @notice Update the Hyperbridge host
    /// @param _newHost New host address
    function setHost(address _newHost) external onlyOwner {
        if (_newHost == address(0)) revert ZeroAddress();
        host = IHost(_newHost);
    }

    // ============ IBridgeAdapter Implementation ============

    /// @notice Quote the fee for sending a message via Hyperbridge
    /// @param message The bridge message to quote
    /// @return fee The estimated fee in native currency
    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
        bytes memory smId = stateMachineIds[message.destChainId];
        if (smId.length == 0) revert StateMachineIdNotSet(message.destChainId);

        // Calculate payload size
        bytes memory body = _encodePayload(message);
        
        // Get per-byte fee from dispatcher
        uint256 perByteFee = IDispatcher(address(host)).perByteFee(smId);
        
        // Calculate fee based on message size
        // Body + overhead for ISMP message structure
        uint256 messageSize = body.length + 256; // 256 bytes overhead estimate
        fee = messageSize * perByteFee;
        
        return fee;
    }

    /// @notice Send a cross-chain message via Hyperbridge ISMP
    /// @param message The bridge message containing payment details
    /// @return commitment The request commitment (message ID)
    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32 commitment) {
        bytes memory smId = stateMachineIds[message.destChainId];
        if (smId.length == 0) revert StateMachineIdNotSet(message.destChainId);
        
        bytes memory destContract = destinationContracts[message.destChainId];
        if (destContract.length == 0) revert DestinationNotSet(message.destChainId);

        // Note: For Liquidity Network model, tokens remain locked in Vault
        // Gateway has already deposited tokens to Vault
        // We just need to send the message to instruct destination to release

        // Encode the payment instruction payload
        bytes memory body = _encodePayload(message);

        // Build DispatchPost request
        DispatchPost memory request = DispatchPost({
            dest: smId,
            to: destContract,
            body: body,
            timeout: defaultTimeout,
            fee: msg.value, // Relayer fee paid via msg.value
            payer: msg.sender
        });

        // Dispatch via Hyperbridge Host
        commitment = IDispatcher(address(host)).dispatch{value: msg.value}(request);

        emit MessageDispatched(
            commitment,
            message.destChainId,
            message.paymentId,
            message.amount,
            message.receiver
        );

        return commitment;
    }

    // ============ View Functions ============

    /// @notice Check if a chain is configured
    /// @param chainId CAIP-2 chain identifier
    /// @return configured Whether the chain has both SM ID and destination set
    function isChainConfigured(string calldata chainId) external view returns (bool configured) {
        return stateMachineIds[chainId].length > 0 && destinationContracts[chainId].length > 0;
    }

    /// @notice Get the fee token used by Hyperbridge
    /// @return feeToken The ERC20 fee token address
    function getFeeToken() external view returns (address feeToken) {
        return IDispatcher(address(host)).feeToken();
    }

    // ============ Internal Functions ============

    /// @notice Encode the payment instruction payload
    /// @param message The bridge message
    /// @return body Encoded payload bytes
    function _encodePayload(BridgeMessage calldata message) internal pure returns (bytes memory body) {
        // Encode payment details for the destination receiver
        // Format: (paymentId, amount, destToken, receiver, minAmountOut)
        body = abi.encode(
            message.paymentId,
            message.amount,
            message.destToken,
            message.receiver,
            message.minAmountOut
        );
    }
}
