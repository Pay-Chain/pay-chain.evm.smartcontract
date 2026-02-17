// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Client.sol";

/**
 * @title IRouterClient
 * @notice Interface for CCIP Router client
 */
interface IRouterClient {
    error UnsupportedDestinationChain(uint64 destChainSelector);
    error InsufficientFeeTokenAmount();
    error InvalidMsgValue();

    function isChainSupported(uint64 chainSelector) external view returns (bool supported);

    function getSupportedTokens(uint64 chainSelector) external view returns (address[] memory tokens);

    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32);
}

