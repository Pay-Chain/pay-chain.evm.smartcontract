// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeAdapter.sol";

interface ILayerZeroEndpointV2 {
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory);

    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);

    function setDelegate(address _delegate) external;
}

/**
 * @title LayerZeroSenderAdapter
 * @notice LayerZero v2 sender adapter for PayChain routing
 * @dev Minimal endpoint integration without external OApp dependency.
 */
contract LayerZeroSenderAdapter is IBridgeAdapter, Ownable {
    ILayerZeroEndpointV2 public endpoint;

    mapping(string => uint32) public dstEids;
    mapping(string => bytes32) public peers;
    mapping(string => bytes) public enforcedOptions;

    /// @notice Default gas limit for LZ receive execution
    uint128 public constant DEFAULT_LZ_GAS = 200_000;

    event LayerZeroRouteSet(string indexed destChainId, uint32 dstEid, bytes32 peer);
    event LayerZeroOptionsSet(string indexed destChainId, bytes options);
    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);

    error InvalidEndpoint();
    error RouteNotConfigured(string destChainId);
    error InsufficientNativeFee(uint256 required, uint256 provided);

    constructor(address _endpoint) Ownable(msg.sender) {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        if (_endpoint == address(0)) revert InvalidEndpoint();
        emit EndpointUpdated(address(endpoint), _endpoint);
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function setRoute(string calldata destChainId, uint32 dstEid, bytes32 peer) external onlyOwner {
        dstEids[destChainId] = dstEid;
        peers[destChainId] = peer;
        emit LayerZeroRouteSet(destChainId, dstEid, peer);
    }

    function setEnforcedOptions(string calldata destChainId, bytes calldata options) external onlyOwner {
        enforcedOptions[destChainId] = options;
        emit LayerZeroOptionsSet(destChainId, options);
    }

    /// @notice Register this contract as delegate on the LZ endpoint
    function registerDelegate() external onlyOwner {
        endpoint.setDelegate(owner());
    }

    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
        (ILayerZeroEndpointV2.MessagingParams memory params, ) = _buildParams(message);
        ILayerZeroEndpointV2.MessagingFee memory quoted = endpoint.quote(params, address(this));
        return quoted.nativeFee;
    }

    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32 messageId) {
        (ILayerZeroEndpointV2.MessagingParams memory params, uint256 quotedFee) = _buildParams(message);
        if (msg.value < quotedFee) revert InsufficientNativeFee(quotedFee, msg.value);
        ILayerZeroEndpointV2.MessagingReceipt memory receipt = endpoint.send{value: msg.value}(params, msg.sender);
        return receipt.guid;
    }

    function isRouteConfigured(string calldata destChainId) external view override returns (bool) {
        return dstEids[destChainId] != 0 && peers[destChainId] != bytes32(0);
    }

    function getRouteConfig(
        string calldata destChainId
    ) external view override returns (bool configured, bytes memory configA, bytes memory configB) {
        uint32 dstEid = dstEids[destChainId];
        bytes32 peer = peers[destChainId];
        bytes memory options = enforcedOptions[destChainId];
        configured = dstEid != 0 && peer != bytes32(0);
        configA = abi.encode(dstEid, peer);
        configB = options;
    }

    function _buildParams(
        BridgeMessage calldata message
    ) internal view returns (ILayerZeroEndpointV2.MessagingParams memory params, uint256 quotedFee) {
        uint32 dstEid = dstEids[message.destChainId];
        bytes32 peer = peers[message.destChainId];
        if (dstEid == 0 || peer == bytes32(0)) revert RouteNotConfigured(message.destChainId);

        bytes memory payload = abi.encode(
            message.paymentId,
            message.amount,
            message.destToken,
            message.receiver,
            message.minAmountOut,
            message.sourceToken
        );
        bytes memory options = enforcedOptions[message.destChainId];
        if (options.length == 0) {
            options = _buildDefaultOptions();
        }
        params = ILayerZeroEndpointV2.MessagingParams({
            dstEid: dstEid,
            receiver: peer,
            message: payload,
            options: options,
            payInLzToken: false
        });

        ILayerZeroEndpointV2.MessagingFee memory q = endpoint.quote(params, address(this));
        quotedFee = q.nativeFee;
    }

    /// @notice Build default LZ options with gas limit for lzReceive
    function _buildDefaultOptions() internal pure returns (bytes memory) {
        // Type 3 options format: 0x0003 + executor option
        // Executor lzReceive option: type=1, gas=DEFAULT_LZ_GAS, value=0
        return abi.encodePacked(
            uint16(3),           // Options type 3
            uint8(1),            // Worker ID: executor
            uint16(17),          // Option length: 1 + 16 = 17 bytes
            uint8(1),            // Option type: lzReceive
            DEFAULT_LZ_GAS       // Gas limit (uint128)
        );
    }
}
