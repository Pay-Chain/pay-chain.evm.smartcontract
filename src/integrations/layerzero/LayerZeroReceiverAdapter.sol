// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../PayChainGateway.sol";
import "../../vaults/PayChainVault.sol";

/**
 * @title LayerZeroReceiverAdapter
 * @notice Minimal LayerZero receiver adapter for PayChain finalize callback.
 * @dev Endpoint implementation is chain-specific; this adapter trusts the configured endpoint.
 */
contract LayerZeroReceiverAdapter is Ownable {
    address public endpoint;
    PayChainGateway public gateway;
    PayChainVault public vault;

    mapping(uint32 => bytes32) public trustedPeers;

    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event TrustedPeerSet(uint32 indexed srcEid, bytes32 peer);
    event LayerZeroMessageAccepted(bytes32 indexed paymentId, uint32 indexed srcEid, address receiver, address token, uint256 amount);

    error InvalidEndpoint();
    error UnauthorizedEndpoint();
    error UntrustedPeer(uint32 srcEid, bytes32 peer);

    constructor(address _endpoint, address _gateway, address _vault) Ownable(msg.sender) {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        endpoint = _endpoint;
        gateway = PayChainGateway(_gateway);
        vault = PayChainVault(_vault);
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        emit EndpointUpdated(endpoint, _endpoint);
        endpoint = _endpoint;
    }

    function setTrustedPeer(uint32 srcEid, bytes32 peer) external onlyOwner {
        trustedPeers[srcEid] = peer;
        emit TrustedPeerSet(srcEid, peer);
    }

    /**
     * @notice Entry-point expected to be called by the LayerZero endpoint.
     * @dev Payload format must match LayerZeroSenderAdapter payload encoding.
     */
    function lzReceive(uint32 srcEid, bytes32 sender, bytes calldata payload) external {
        if (msg.sender != endpoint) revert UnauthorizedEndpoint();
        if (trustedPeers[srcEid] != sender) revert UntrustedPeer(srcEid, sender);

        (bytes32 paymentId, uint256 amount, address token, address receiver, ) = abi.decode(
            payload,
            (bytes32, uint256, address, address, uint256)
        );

        vault.pushTokens(token, receiver, amount);
        gateway.finalizeIncomingPayment(paymentId, receiver, token, amount);

        emit LayerZeroMessageAccepted(paymentId, srcEid, receiver, token, amount);
    }
}

