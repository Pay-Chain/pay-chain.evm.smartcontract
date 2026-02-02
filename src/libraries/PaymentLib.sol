// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPayChainGateway.sol";

/**
 * @title PaymentLib
 * @notice Library for payment data structures and hashing
 */
library PaymentLib {
    function calculatePaymentId(
        address sender,
        address receiver,
        string memory destChainId,
        address sourceToken,
        uint256 amount,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                sender,
                receiver,
                destChainId,
                sourceToken,
                amount,
                timestamp
            )
        );
    }
}
