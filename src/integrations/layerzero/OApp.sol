// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OApp
 * @notice Minimal LayerZero V2 OApp base contract.
 * @dev Provides trusted peer management and standard modifiers/checks.
 *      Excludes full lzReceive logic (implemented in adapter) but provides the auth check.
 */
abstract contract OApp is Ownable {
    
    // ============ Standard LZ V2 Interface ============

    /// @notice LayerZero V2 Origin struct — matches EndpointV2 callback signature
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    /// @notice Emitted when a peer is set for an endpoint ID.
    event PeerSet(uint32 eid, bytes32 peer);

    /// @notice Emitted when the endpoint address is updated.
    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);

    error InvalidEndpoint();
    error OnlyEndpoint();
    error InvalidPeer();
    error NoPeer(uint32 eid);
    error InvalidDelegate();

    // ============ State Variables ============

    /// @notice The LayerZero Endpoint address
    address public endpoint;

    /// @notice Mapping from source endpoint ID to trusted peer (bytes32 address)
    mapping(uint32 => bytes32) public peers;

    // ============ Modifiers ============

    /// @dev Modifier to ensure only the endpoint can call.
    /// @dev Modifier to ensure only the endpoint can call.
    modifier onlyEndpoint() {
        _onlyEndpoint();
        _;
    }

    function _onlyEndpoint() internal view {
        if (msg.sender != endpoint) revert OnlyEndpoint();
    }

    // ============ Constructor ============

    /**
     * @param _endpoint The LayerZero Endpoint address
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint
     */
    constructor(address _endpoint, address _delegate) Ownable(_delegate) {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        endpoint = _endpoint;
    }

    // ============ Admin Functions ============

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @notice Sets the LayerZero Endpoint address.
     * @param _endpoint The new endpoint address.
     */
    function setEndpoint(address _endpoint) external onlyOwner {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        emit EndpointUpdated(endpoint, _endpoint);
        endpoint = _endpoint;
    }

    // ============ Internal Functions ============

    /**
     * @dev Internal function to check if the path is initialized (trusted peer check).
     * @param _origin The origin struct containing srcEid and sender.
     * @return trusted True if the sender is a trusted peer for the srcEid.
     */
    function _allowInitializePath(Origin calldata _origin) internal view virtual returns (bool) {
        return peers[_origin.srcEid] == _origin.sender;
    }
}
