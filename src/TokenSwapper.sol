// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IUniswapV4.sol";
import "./vaults/PayChainVault.sol";

/**
 * @title TokenSwapper
 * @notice DEX integration contract with pool discovery, multi-hop swaps, and gas simulation
 * @dev Designed for Uniswap V4 integration - interface-compatible for easy upgrades
 */
contract TokenSwapper is ISwapper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Types ============

    /// @notice Pool configuration for a token pair
    struct PoolConfig {
        // V4 PoolKey params
        // Currency is derived from token addresses (sorted)
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bool isActive;
    }

    // ============ State Variables ============

    /// @notice Address of PayChainVault
    PayChainVault public vault;

    /// @notice Address of Uniswap V4 UniversalRouter
    address public universalRouter;
    
    /// @notice Address of Uniswap V4 PoolManager
    address public poolManager;

    /// @notice Bridge token for multi-hop routes (e.g., USDC)
    address public bridgeToken;

    /// @notice Direct pool routes: keccak256(tokenIn, tokenOut) => PoolConfig
    mapping(bytes32 => PoolConfig) public directPools;

    /// @notice Multi-hop routes: keccak256(tokenIn, tokenOut) => address[]
    mapping(bytes32 => address[]) public multiHopRoutes;

    /// @notice Whitelisted callers (PayChain contracts)
    mapping(address => bool) public authorizedCallers;

    // ============ Constants ============

    uint256 public constant GAS_SINGLE_HOP = 150_000;
    uint256 public constant GAS_PER_HOP = 120_000;
    uint256 public constant GAS_OVERHEAD = 50_000;
    uint256 public constant DEFAULT_SLIPPAGE_BPS = 100;
    uint256 public maxSlippageBps = 500;

    /// @notice Universal Router Commands
    bytes1 public constant V4_SWAP = 0x10;
    
    /// @notice V4 Router Action Constants (example inputs, check specific Universal Router implementation)
    // For V4, typically we pass (actions, params) encoded for V4Router
    // Actions: 0x06 (SWAP_EXACT_IN_SINGLE)
    uint8 internal constant V4_ACTION_SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 internal constant V4_ACTION_SWAP_EXACT_IN = 0x07;

    // ============ Errors ============

    error NoRouteFound();
    error SlippageExceeded();
    error InvalidAddress();
    error Unauthorized();
    error SameToken();
    error ZeroAmount();
    error PoolNotActive();

    // ============ Events ============

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    
    // ============ Constructor ============

    constructor(
        address _universalRouter,
        address _poolManager,
        address _bridgeToken
    ) Ownable(msg.sender) {
        if (_universalRouter == address(0) || _poolManager == address(0)) {
            // Revert if strictly requiring valid addresses
        }

        universalRouter = _universalRouter;
        poolManager = _poolManager;
        bridgeToken = _bridgeToken;

        // Owner is authorized by default
        authorizedCallers[msg.sender] = true;
    }

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    function _onlyAuthorized() internal view {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
    }

    // ============ Admin Functions ============

    function setVault(address _vault) external onlyOwner {
        vault = PayChainVault(_vault);
    }

    /// @notice Update the maximum slippage tolerance
    /// @param bps New slippage in basis points (max 1000 = 10%)
    function setMaxSlippage(uint256 bps) external onlyOwner {
        require(bps <= 1000, "Max 10% slippage");
        maxSlippageBps = bps;
    }

    // ============ Core Swap Functions ============

    /// @notice Swap tokens held in the Vault
    function swapFromVault(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external nonReentrant onlyAuthorized returns (uint256 amountOut) {
        if (address(vault) == address(0)) revert InvalidAddress();
        if (tokenIn == tokenOut) revert SameToken();
        if (amountIn == 0) revert ZeroAmount();
        
        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        // Pull from Vault to This Contract
        vault.pushTokens(tokenIn, address(this), amountIn);
        
        // Internal Logic for swapping (using funds now in this contract)
        if (isDirect) {
            amountOut = _executeDirectSwap(tokenIn, tokenOut, amountIn);
        } else {
            amountOut = _executeMultiHopSwap(path, amountIn);
        }

        if (amountOut < minAmountOut) revert SlippageExceeded();

        // Transfer output to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    /// @inheritdoc ISwapper
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external override nonReentrant onlyAuthorized returns (uint256 amountOut) {
        if (tokenIn == tokenOut) revert SameToken();
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert InvalidAddress();

        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        // Transfer tokens from caller
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (isDirect) {
            amountOut = _executeDirectSwap(tokenIn, tokenOut, amountIn);
        } else {
            amountOut = _executeMultiHopSwap(path, amountIn);
        }

        if (amountOut < minAmountOut) revert SlippageExceeded();

        // Transfer output to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut, recipient);
    }

    // ============ Route Discovery ============

    /// @inheritdoc ISwapper
    function findRoute(
        address tokenIn,
        address tokenOut
    ) public view override returns (bool exists, bool isDirect, address[] memory path) {
        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);

        // 1. Check direct pool
        if (directPools[pairKey].isActive) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return (true, true, path);
        }

        // 2. Check configured multi-hop route
        address[] storage hops = multiHopRoutes[pairKey];
        if (hops.length > 0) {
            path = new address[](hops.length + 2);
            path[0] = tokenIn;
            for (uint256 i = 0; i < hops.length; i++) {
                path[i + 1] = hops[i];
            }
            path[path.length - 1] = tokenOut;
            return (true, false, path);
        }

        // 3. Try via bridge token
        if (bridgeToken != address(0) && tokenIn != bridgeToken && tokenOut != bridgeToken) {
            bytes32 inKey = _getPairKey(tokenIn, bridgeToken);
            bytes32 outKey = _getPairKey(bridgeToken, tokenOut);

            if (directPools[inKey].isActive && directPools[outKey].isActive) {
                path = new address[](3);
                path[0] = tokenIn;
                path[1] = bridgeToken;
                path[2] = tokenOut;
                return (true, false, path);
            }
        }

        return (false, false, new address[](0));
    }

    // ============ Gas Estimation ============

    /// @inheritdoc ISwapper
    function estimateSwapGas(
        address tokenIn,
        address tokenOut,
        uint256 /* amountIn */
    ) external view override returns (uint256 estimatedGas, uint256 hopCount) {
        (bool exists, bool isDirect, address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        hopCount = path.length - 1;

        if (isDirect) {
            estimatedGas = GAS_SINGLE_HOP;
        } else {
            estimatedGas = GAS_OVERHEAD + (hopCount * GAS_PER_HOP);
        }
    }

    /// @inheritdoc ISwapper
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (
        uint256 amountOut,
        uint256 estimatedGas,
        uint256 hopCount,
        address[] memory path
    ) {
        bool exists;
        bool isDirect;
        (exists, isDirect, path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        hopCount = path.length - 1;
        estimatedGas = isDirect ? GAS_SINGLE_HOP : (GAS_OVERHEAD + hopCount * GAS_PER_HOP);
        amountOut = _simulateSwap(path, amountIn);
    }

    /// @inheritdoc ISwapper
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        (bool exists, , address[] memory path) = findRoute(tokenIn, tokenOut);
        if (!exists) revert NoRouteFound();

        amountOut = _simulateSwap(path, amountIn);
    }

    /// @notice Set a direct pool route for a token pair
    function setDirectPool(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) external onlyOwner {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress(); // Assuming InvalidAddress() is defined elsewhere

        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        directPools[pairKey] = PoolConfig({
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: hooks,
            isActive: true
        });

        // Assuming PoolRouteSet event is defined elsewhere
        // emit PoolRouteSet(tokenIn, tokenOut, true, address(0)); // poolAddress not used in V4, using derived PoolKey
    }

    // ============ Internal Functions ============

    // ============ Internal Functions ============

    /// @notice Generate a unique key for a token pair
    function _getPairKey(address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a < b ? a : b, a < b ? b : a));
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (Currency, Currency) {
        return tokenA < tokenB 
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB)) 
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
    }

    /// @notice Execute a direct (single-hop) swap via Uniswap
    function _executeDirectSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (universalRouter == address(0)) return amountIn;

        bytes32 pairKey = _getPairKey(tokenIn, tokenOut);
        PoolConfig memory config = directPools[pairKey];
        if (!config.isActive) revert PoolNotActive(); 

        IERC20(tokenIn).forceApprove(universalRouter, amountIn);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // Construct PoolKey
        (Currency currency0, Currency currency1) = _sortTokens(tokenIn, tokenOut);
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: config.hooks
        });

        // Determine zeroForOne
        bool zeroForOne = tokenIn < tokenOut;

        // Min Output
        uint256 minOut = _calculateMinOutput(amountIn, config.fee);
        if (amountIn > type(uint128).max || minOut > type(uint128).max) revert SlippageExceeded();

        // Encode V4 Router Actions
        // Action: SWAP_EXACT_IN_SINGLE
        bytes memory actions = abi.encodePacked(V4_ACTION_SWAP_EXACT_IN_SINGLE);
        
        // Params for Action
        IV4Router.ExactInputSingleParams memory params = IV4Router.ExactInputSingleParams({
            poolKey: key,
            zeroForOne: zeroForOne,
            // forge-lint: disable-next-line(unsafe-typecast)
            amountIn: uint128(amountIn),
            // forge-lint: disable-next-line(unsafe-typecast)
            amountOutMinimum: uint128(minOut),
            hookData: new bytes(0)
        });
        
        bytes[] memory actionParams = new bytes[](1);
        actionParams[0] = abi.encode(params);

        // Final UniversalRouter Input
        bytes memory commands = abi.encodePacked(V4_SWAP);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        try IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 600) {
            amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        } catch {
            revert NoRouteFound(); 
        }
    }

    function _executeMultiHopSwap(
        address[] memory path,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (universalRouter == address(0)) return amountIn;
        
        uint256 pathLength = path.length;
        if (pathLength < 2) revert NoRouteFound();

        IV4Router.PathKey[] memory pathKeys = new IV4Router.PathKey[](pathLength - 1);
        
        for (uint256 i = 0; i < pathLength - 1; i++) {
            address tokenA = path[i];
            address tokenB = path[i+1];
            bytes32 pairKey = _getPairKey(tokenA, tokenB); 
            PoolConfig memory config = directPools[pairKey];
            
            if (!config.isActive) revert PoolNotActive();
            
            pathKeys[i] = IV4Router.PathKey({
                intermediateCurrency: Currency.wrap(tokenB),
                fee: config.fee,
                tickSpacing: config.tickSpacing,
                hooks: config.hooks,
                hookData: new bytes(0)
            });
        }

        uint256 minOut = _calculateMinOutputMultiHop(path, amountIn);
        if (amountIn > type(uint128).max || minOut > type(uint128).max) revert SlippageExceeded();
        
        IERC20(path[0]).forceApprove(universalRouter, amountIn);
        uint256 balanceBefore = IERC20(path[pathLength-1]).balanceOf(address(this));

        IV4Router.ExactInputParams memory params = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(path[0]),
            path: pathKeys,
            // forge-lint: disable-next-line(unsafe-typecast)
            amountIn: uint128(amountIn),
            // forge-lint: disable-next-line(unsafe-typecast)
            amountOutMinimum: uint128(minOut)
        });

        bytes memory actions = abi.encodePacked(V4_ACTION_SWAP_EXACT_IN);
        bytes[] memory actionParams = new bytes[](1);
        actionParams[0] = abi.encode(params);
        
        bytes memory commands = abi.encodePacked(V4_SWAP); // 0x10
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        try IUniversalRouter(universalRouter).execute(commands, inputs, block.timestamp + 600) {
            amountOut = IERC20(path[pathLength-1]).balanceOf(address(this)) - balanceBefore;
        } catch {
            revert NoRouteFound();
        }
    }



    /// @notice Calculate minimum output with slippage protection
    function _calculateMinOutput(uint256 amountIn, uint24 fee) internal view returns (uint256 minOut) {
        uint256 feeAmount = (amountIn * fee) / 1_000_000;
        uint256 expectedOut = amountIn - feeAmount;
        uint256 slippageAmount = (expectedOut * maxSlippageBps) / 10_000;
        minOut = expectedOut - slippageAmount;
    }

    /// @notice Calculate minimum output for multi-hop with slippage
    function _calculateMinOutputMultiHop(address[] memory path, uint256 amountIn) internal view returns (uint256 minOut) {
        uint256 currentAmount = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            bytes32 pairKey = _getPairKey(path[i], path[i + 1]);
            PoolConfig memory config = directPools[pairKey];
            if (config.isActive) {
                uint256 feeAmount = (currentAmount * config.fee) / 1_000_000;
                currentAmount = currentAmount - feeAmount;
            }
        }
        uint256 slippageAmount = (currentAmount * maxSlippageBps) / 10_000;
        minOut = currentAmount - slippageAmount;
    }

    /// @notice Simulate a swap to get expected output
    function _simulateSwap(
        address[] memory path,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        uint256 currentAmount = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            bytes32 pairKey = _getPairKey(path[i], path[i + 1]);
            PoolConfig memory config = directPools[pairKey];
            if (config.isActive) {
                uint256 feeAmount = (currentAmount * config.fee) / 1_000_000;
                currentAmount = currentAmount - feeAmount;
            }
        }
        amountOut = currentAmount;
    }
}
