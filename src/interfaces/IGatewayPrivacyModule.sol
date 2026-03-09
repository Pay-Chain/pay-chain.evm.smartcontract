// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGatewayPrivacyModule {
    function recordPrivacyIntent(
        bytes32 paymentId,
        bytes32 intentId,
        address stealthReceiver,
        address sender
    ) external;

    function recordPrivacyForward(
        bytes32 paymentId,
        address stealthReceiver,
        address finalReceiver,
        address token,
        uint256 amount,
        address caller
    ) external;
}
