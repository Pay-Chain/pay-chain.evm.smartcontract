// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CCIPReceiverBase.sol";
import "./Client.sol";
import "../../PayChainGateway.sol";

/**
 * @title CCIPReceiverAdapter
 * @notice Bridge Adapter for receiving CCIP messages
 */
contract CCIPReceiverAdapter is CCIPReceiverBase, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainGateway public gateway;
    
    // ============ Constructor ============

    constructor(
        address _ccipRouter,
        address _gateway
    ) CCIPReceiverBase(_ccipRouter) Ownable(msg.sender) {
        gateway = PayChainGateway(_gateway);
    }

    // ============ CCIPReceiver Implementation ============

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // 1. Decode Payment Data
        // Message data: (paymentId, destToken, receiver) 
        // Note: CCIP sends tokens to this contract
        (bytes32 paymentId, address destToken, address receiver) = abi.decode(
            message.data,
            (bytes32, address, address)
        );

        // 2. Extract received token/amount
        // We assume single token transfer
        address receivedToken = message.destTokenAmounts[0].token;
        require(receivedToken == destToken, "Token Mismatch");
        uint256 receivedAmount = message.destTokenAmounts[0].amount;

        // 3. Validation
        // Ensure receivedToken matches destToken (or handle mismatch/swap)
        // For simple MVP: require match. Real implementation would swap.
        // If swap needed: Call Swapper?
        // Let's implement basic Transfer.
        
        // address receiver = abi.decode(message.receiver, (address)); // REMOVED: receiver is in data

        // 4. Transfer to Receiver
        IERC20(receivedToken).safeTransfer(receiver, receivedAmount);

        // 5. Notify Gateway
        gateway.finalizeIncomingPayment(
            paymentId,
            receiver,
            receivedToken,
            receivedAmount
        );
    }
}
