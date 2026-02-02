// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapper
 * @notice Interface for DEX token swapping functionality
 * @dev Implement this interface to integrate different DEX protocols
 */
interface ISwapper {
    /// @notice Swap tokens with slippage protection
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens to swap
    /// @param minAmountOut Minimum output amount (slippage protection)
    /// @param recipient Address to receive output tokens
    /// @return amountOut Actual output amount received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut);

    /// @notice Get a quote for a swap without executing
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens
    /// @return amountOut Expected output amount
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Estimate gas for a swap route
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @param amountIn Amount of input tokens
    /// @return estimatedGas Estimated gas cost
    /// @return hopCount Number of hops in the route
    function estimateSwapGas(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 estimatedGas, uint256 hopCount);

    /// @notice Get full swap quote with gas estimate
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token  
    /// @param amountIn Amount of input tokens
    /// @return amountOut Expected output amount
    /// @return estimatedGas Estimated gas cost
    /// @return hopCount Number of hops
    /// @return path Array of token addresses in the swap path
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (
        uint256 amountOut,
        uint256 estimatedGas,
        uint256 hopCount,
        address[] memory path
    );

    /// @notice Find the best route for a token swap
    /// @param tokenIn Address of the input token
    /// @param tokenOut Address of the output token
    /// @return exists Whether a route exists
    /// @return isDirect Whether the route is a direct swap
    /// @return path Array of token addresses in the route
    function findRoute(
        address tokenIn,
        address tokenOut
    ) external view returns (bool exists, bool isDirect, address[] memory path);
}
