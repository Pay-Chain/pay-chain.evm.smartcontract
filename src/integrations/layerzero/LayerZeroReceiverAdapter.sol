// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./OApp.sol";
import "../../PayChainGateway.sol";
import "../../vaults/PayChainVault.sol";
import "../../TokenSwapper.sol";

/**
 * @title LayerZeroReceiverAdapter
 * @notice LayerZero V2 receiver adapter with proper Origin struct signature.
 * @dev Phase 1.4: Fixed lzReceive to use Origin struct matching LZ EndpointV2.
 *      Added allowInitializePath and nextNonce for full V2 compliance.
 */
contract LayerZeroReceiverAdapter is OApp {

    // ============ State Variables ============

    PayChainGateway public gateway;
    PayChainVault public vault;
    TokenSwapper public swapper;

    mapping(uint32 => uint64) public inboundNonces;

    // ============ Events ============

    event TrustedPeerSet(uint32 indexed srcEid, bytes32 peer);
    event LayerZeroMessageAccepted(
        bytes32 indexed paymentId,
        uint32 indexed srcEid,
        uint64 nonce,
        address receiver,
        address token,
        uint256 amount,
        bool swapped
    );

    // ============ Errors ============

    error UnauthorizedEndpoint();
    error UntrustedPeer(uint32 srcEid, bytes32 peer);
    error InvalidNonce(uint32 srcEid, uint64 expected, uint64 received);

    // ============ Constructor ============

    constructor(address _endpoint, address _gateway, address _vault) OApp(_endpoint, msg.sender) {
        gateway = PayChainGateway(_gateway);
        vault = PayChainVault(_vault);
    }

    // ============ Admin Functions ============

    function setSwapper(address _swapper) external onlyOwner {
        swapper = TokenSwapper(_swapper);
    }

    // ============ LZ V2 Receiver Interface ============

    /**
     * @notice Entry-point called by the LayerZero V2 Endpoint.
     * @dev Signature: lzReceive(Origin, bytes32, bytes, address, bytes)
     *      This matches the ILayerZeroReceiver interface in LZ V2.
     * @param _origin Origin struct with (srcEid, sender, nonce)

     */
    function lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable onlyEndpoint {
        // Trust: verify sender is a registered peer
        if (!_allowInitializePath(_origin)) {
            revert UntrustedPeer(_origin.srcEid, _origin.sender);
        }

        // LZ-4: Strict sequential nonce validation (mirrors OAppReceiver._acceptNonce)
        uint64 expectedNonce = inboundNonces[_origin.srcEid] + 1;
        if (_origin.nonce != expectedNonce) {
            revert InvalidNonce(_origin.srcEid, expectedNonce, _origin.nonce);
        }
        inboundNonces[_origin.srcEid] = _origin.nonce;

        // Decode payload (supports V1 and V2 formats)
        (
            bytes32 paymentId,
            uint256 amount,
            address destToken,
            address receiver,
            uint256 minAmountOut,
            address sourceToken
        ) = _decodePayload(_message);

        uint256 settledAmount = amount;
        address settledToken = destToken;
        bool swapped = false;

        // S4: destination-side swap when source token differs from destination token.
        if (sourceToken != address(0) && sourceToken != destToken) {
            require(address(swapper) != address(0), "Swapper not configured");
            settledAmount = swapper.swapFromVault(sourceToken, destToken, amount, minAmountOut, receiver);
            swapped = true;
        } else {
            // Legacy/V1 behavior: release destination token directly.
            vault.pushTokens(destToken, receiver, amount);
        }

        gateway.finalizeIncomingPayment(paymentId, receiver, settledToken, settledAmount);

        emit LayerZeroMessageAccepted(paymentId, _origin.srcEid, _origin.nonce, receiver, settledToken, settledAmount, swapped);
    }

    /**
     * @notice LZ V2 path initialization callback. 
     * @dev Returns true only for trusted peers.
     */
    function allowInitializePath(Origin calldata origin) external view returns (bool) {
        return _allowInitializePath(origin);
    }

    /**
     * @notice Returns the next expected nonce for a given source.
     * @param _srcEid Source endpoint ID
     * @param _sender Sender bytes32 address
     */
    function nextNonce(uint32 _srcEid, bytes32 _sender) external view returns (uint64) {
        if (peers[_srcEid] != _sender) return 0;
        return inboundNonces[_srcEid] + 1;
    }

    function _decodePayload(
        bytes calldata data
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
