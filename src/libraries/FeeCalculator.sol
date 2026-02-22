// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FeeCalculator
 * @notice Library for calculating platform fees using hybrid model
 */
library FeeCalculator {
    uint256 constant BPS_DENOMINATOR = 10000;

    /**
     * @notice Calculate platform fee using hybrid model
     * @dev Fee = max(Fixed Base Fee, Amount × Rate%)
     * @param amount Transaction amount
     * @param fixedBaseFee Fixed base fee in token decimals
     * @param feeRateBps Fee rate in basis points (1 bps = 0.01%)
     * @return Platform fee amount
     */
    function calculatePlatformFee(
        uint256 amount,
        uint256 fixedBaseFee,
        uint256 feeRateBps
    ) internal pure returns (uint256) {
        uint256 percentageFee = (amount * feeRateBps) / BPS_DENOMINATOR;
        // Cap fee at fixedBaseFee: min(percentage, fixedCap)
        return percentageFee < fixedBaseFee ? percentageFee : fixedBaseFee;
    }

    /**
     * @notice Calculate total fee including bridge and gas
     * @param amount Transaction amount
     * @param fixedBaseFee Fixed base fee
     * @param feeRateBps Fee rate in basis points
     * @param bridgeFee Bridge fee
     * @param gasFee Gas fee
     * @return Total fee
     */
    function calculateTotalFee(
        uint256 amount,
        uint256 fixedBaseFee,
        uint256 feeRateBps,
        uint256 bridgeFee,
        uint256 gasFee
    ) internal pure returns (uint256) {
        return
            calculatePlatformFee(amount, fixedBaseFee, feeRateBps) +
            bridgeFee +
            gasFee;
    }

    /**
     * @notice Calculate canonical payload length used by Track-B per-byte platform fee.
     * @dev This mirrors payment intent fields, not bridge-specific encoded payload bytes.
     */
    function payloadLengthForPayment(
        bytes calldata destChainIdBytes,
        bytes calldata receiverBytes,
        address /* sourceToken */,
        address /* destToken */,
        uint256 /* amount */,
        uint256 /* minAmountOut */
    ) internal pure returns (uint256) {
        return
            destChainIdBytes.length +
            receiverBytes.length +
            20 + // sourceToken
            20 + // destToken
            32 + // amount
            32; // minAmountOut
    }

    /**
     * @notice Apply optional min/max cap to calculated fee.
     * @param rawFee Base computed fee.
     * @param minFee Lower bound (0 disables min bound).
     * @param maxFee Upper bound (0 disables max bound).
     */
    function applyMinMaxCap(
        uint256 rawFee,
        uint256 minFee,
        uint256 maxFee
    ) internal pure returns (uint256) {
        uint256 capped = rawFee;
        if (minFee > 0 && capped < minFee) {
            capped = minFee;
        }
        if (maxFee > 0 && capped > maxFee) {
            capped = maxFee;
        }
        return capped;
    }

    /**
     * @notice Calculate Track-B per-byte platform fee.
     * @dev fee = (payloadLength + overheadBytes) * perByteRate, then min/max cap.
     */
    function calculatePerBytePlatformFee(
        uint256 payloadLength,
        uint256 overheadBytes,
        uint256 perByteRate,
        uint256 minFee,
        uint256 maxFee
    ) internal pure returns (uint256) {
        uint256 rawFee = (payloadLength + overheadBytes) * perByteRate;
        return applyMinMaxCap(rawFee, minFee, maxFee);
    }
}
