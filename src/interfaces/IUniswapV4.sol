// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUniswapV4
 * @notice Minimal interfaces for Uniswap V4 integration
 * @dev Based on Uniswap V4 core contracts
 */

/// @notice Represents a currency (address(0) for native ETH)
type Currency is address;

/// @notice Type for pool identifiers
type PoolId is bytes32;

/// @notice Parameters identifying a pool
struct PoolKey {
    /// @dev The lower currency of the pool, sorted numerically
    Currency currency0;
    /// @dev The higher currency of the pool, sorted numerically
    Currency currency1;
    /// @dev The pool swap fee, capped at 1_000_000 (100%)
    uint24 fee;
    /// @dev Ticks spacing for the pool
    int24 tickSpacing;
    /// @dev Address of the hook contract (address(0) for no hooks)
    address hooks;
}

/// @notice Parameters for executing a swap
struct SwapParams {
    /// @dev Whether to swap token0 for token1 (true) or token1 for token0 (false)
    bool zeroForOne;
    /// @dev The amount to swap. If positive, exact input. If negative, exact output.
    int256 amountSpecified;
    /// @dev The sqrt price limit. If zeroForOne, must be less than current price.
    uint160 sqrtPriceLimitX96;
}

/// @notice Return value from swap operations
struct BalanceDelta {
    int128 amount0;
    int128 amount1;
}

/**
 * @title IPoolManager
 * @notice Interface for Uniswap V4 PoolManager singleton
 */
interface IPoolManager {
    /// @notice Initialize a new pool
    /// @param key The pool key identifying the pool
    /// @param sqrtPriceX96 The initial sqrt price of the pool
    /// @param hookData Data to pass to the hook's beforeInitialize and afterInitialize
    /// @return tick The initial tick of the pool
    function initialize(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        bytes calldata hookData
    ) external returns (int24 tick);

    /// @notice All interactions with the pool manager must go through unlock
    /// @param data Arbitrary data passed to the unlock callback
    /// @return The data returned from the unlock callback
    function unlock(bytes calldata data) external returns (bytes memory);

    /// @notice Execute a swap within an unlock callback
    /// @param key The pool to swap in
    /// @param params The swap parameters
    /// @param hookData Data to pass to hooks
    /// @return delta The balance delta of the swap
    function swap(
        PoolKey memory key,
        SwapParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta memory delta);

    /// @notice Sync currency balance into the pool manager
    /// @param currency The currency to sync
    function sync(Currency currency) external;

    /// @notice Take currency from pool manager
    /// @param currency The currency to take
    /// @param to Recipient address
    /// @param amount Amount to take
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice Settle currency into pool manager
    /// @param currency The currency to settle
    /// @return paid Amount that was paid
    function settle(Currency currency) external payable returns (uint256 paid);

    /// @notice Get pool slot0 data
    function getSlot0(PoolId id) external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint24 protocolFee,
        uint24 lpFee
    );
}

/**
 * @title IUnlockCallback
 * @notice Interface for contracts that call poolManager.unlock
 */
interface IUnlockCallback {
    /// @notice Called by PoolManager when a lock is acquired
    /// @param data Data passed to poolManager.unlock
    /// @return result Data to return from unlock
    function unlockCallback(bytes calldata data) external returns (bytes memory result);
}

/**
 * @title IUniversalRouter
 * @notice Interface for Uniswap Universal Router (recommended integration path)
 * @dev The Universal Router provides a simpler interface for executing swaps
 */
interface IUniversalRouter {
    /// @notice Execute a sequence of commands
    /// @param commands Encoded command identifiers
    /// @param inputs Encoded command inputs
    /// @param deadline Transaction deadline timestamp
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;

    /// @notice Execute commands with native ETH refunds
    /// @param commands Encoded command identifiers
    /// @param inputs Encoded command inputs
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs
    ) external payable;
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Get quote for exact input single-hop swap
    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    ) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/**
 * @title IV4Router
 * @notice Interface for Uniswap V4 Router actions used in Universal Router
 */
interface IV4Router {
    struct ExactInputSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    struct ExactInputParams {
        Currency currencyIn;
        PathKey[] path;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    struct PathKey {
        Currency intermediateCurrency;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
    }
}
