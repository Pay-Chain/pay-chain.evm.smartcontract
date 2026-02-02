// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@hyperbridge/core/apps/HyperApp.sol";
import "../../vaults/PayChainVault.sol";
import "../../PayChainGateway.sol";

/**
 * @title HyperbridgeReceiver
 * @notice Bridge Adapter for receiving Hyperbridge messages (ISMP)
 */
contract HyperbridgeReceiver is HyperApp, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainGateway public gateway;
    PayChainVault public vault;
    
    // ============ Constructor ============

    constructor(
        address _host,
        address _gateway,
        address _vault
    ) Ownable(msg.sender) {
        _hyperbridgeHost = _host; // HyperApp internal var
        gateway = PayChainGateway(_gateway);
        vault = PayChainVault(_vault);
    }

    // ============ HyperApp Implementation ============
    
    // HyperApp usually requires implementing `onAccept`
    // Depending on version, it might be `onPost` or `onGet` support.
    // Assuming simple `onAccept` for PostRequest.

    function onAccept(IncomingPostRequest calldata request) external override {
        // Only Host can call this (checked by HyperApp modifier usually, or we check)
        require(msg.sender == address(host()), "Not host");

        // 1. Decode Body
        (
            bytes32 paymentId,
            uint256 amount,
            address destToken,
            address receiver
        ) = abi.decode(request.request.body, (bytes32, uint256, address, address));

        // 2. Liquidity Management
        // Hyperbridge here is used as Messaging. We need to release funds from Vault.
        // Adapter must be authorized on Vault.
        
        // Check if swap needed? For now assuming destToken is what defines the payout.
        // We verify we have enough balance in Vault? Vault check handles it.
        
        vault.pushTokens(destToken, receiver, amount);

        // 3. Notify Gateway
        gateway.finalizeIncomingPayment(
            paymentId,
            receiver,
            destToken,
            amount
        );
    }
    
    // Internal state for host helper
    address private immutable _hyperbridgeHost;
    
    function host() public view override returns (address) {
        return _hyperbridgeHost;
    }
}
