// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenRegistry
 * @notice Central registry for supported tokens in the PaymentKita protocol
 */
contract TokenRegistry is Ownable {
    // ============ State Variables ============

    mapping(address => bool) public supportedTokens;
    mapping(address => uint8) public tokenDecimals;
    address[] public supportedTokenList;

    // ============ Events ============

    event TokenSupportUpdated(address indexed token, bool supported);
    event TokenDecimalsUpdated(address indexed token, uint8 decimals);

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Admin Functions ============

    function setTokenSupport(address token, bool supported) external onlyOwner {
        require(token != address(0), "Invalid token");

        if (supported && !supportedTokens[token]) {
            supportedTokenList.push(token);
        } else if (!supported && supportedTokens[token]) {
            // Remove from list (opt: expensive, maybe just mark false)
            // For now just mark false. List might contain stale supported=false if we don't swap-pop.
            // Keeping it simple for gas: just update mapping. List is for off-chain convenience or iteration if needed.
        }

        supportedTokens[token] = supported;
        emit TokenSupportUpdated(token, supported);
    }

    function setTokenDecimals(address token, uint8 decimals) external onlyOwner {
        require(token != address(0), "Invalid token");
        tokenDecimals[token] = decimals;
        emit TokenDecimalsUpdated(token, decimals);
    }

    // ============ View Functions ============

    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokenList;
    }
}
