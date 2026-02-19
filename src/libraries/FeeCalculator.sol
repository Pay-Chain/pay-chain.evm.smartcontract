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
}
