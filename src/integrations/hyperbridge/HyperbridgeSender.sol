// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PayChainVault.sol";
import "../../PayChainGateway.sol";
import "@hyperbridge/core/apps/HyperApp.sol";
import {IDispatcher, DispatchPost, PostRequest} from "@hyperbridge/core/interfaces/IDispatcher.sol";


interface IUniswapV2Router02HB {
    function WETH() external view returns (address);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

interface ISwapperHB {
    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient) external returns (uint256 amountOut);
}

interface IWETHHB {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function approve(address guy, uint wad) external returns (bool);
}

/**
 * @title HyperbridgeSender
 * @notice Bridge Adapter for sending Hyperbridge ISMP messages
 * @dev Implements full ISMP dispatch using Hyperbridge host/dispatcher
 * 
 * Architecture:
 * - PayChain uses a Liquidity Network model on top of ISMP messaging
 * - Tokens are locked in the source Vault
 * - ISMP message instructs the destination receiver to release tokens
 * - No native token bridging - messaging only
 */
contract HyperbridgeSender is IBridgeAdapter, HyperApp, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainVault public vault;
    PayChainGateway public gateway;
    
    // Internal state for host helper
    address private immutable _HYPERBRIDGE_HOST;
    
    /// @notice State machine identifiers for destination chains
    /// @dev Format: "POLKADOT-1000", "EVM-1", "EVM-42161", etc.
    mapping(string => bytes) public stateMachineIds;
    
    /// @notice Destination PayChain receiver contract addresses
    mapping(string => bytes) public destinationContracts;

    /// @notice Default timeout for requests (1 hour)
    uint64 public defaultTimeout = 3600;

    // ============ Events ============

    /// @notice Optional swap router override (e.g. QuickSwap) to fix staticcall issues
    address public swapRouter;

    /// @notice Optional TokenSwapper for V4/V3 quotes and swaps
    ISwapperHB public swapper;


    // ============ Events ============

    event MessageDispatched(
        bytes32 indexed commitment,
        string indexed destChainId,
        bytes32 paymentId,
        uint256 amount,
        address receiver
    );

    event StateMachineIdSet(string indexed chainId, bytes stateMachineId);
    event DestinationContractSet(string indexed chainId, bytes destination);
    event TimeoutUpdated(uint64 oldTimeout, uint64 newTimeout);
    event PostRequestTimedOut(bytes32 indexed paymentId);
    event SwapRouterSet(address indexed router);
    event SwapperSet(address indexed swapper);


    // ============ Errors ============

    error StateMachineIdNotSet(string chainId);
    error DestinationNotSet(string chainId);
    error InvalidTimeout();
    error ZeroAddress();
    error NativeFeeQuoteUnavailable();
    error InsufficientNativeFee(uint256 required, uint256 provided);
    error FeeQuoteFailed(uint256 amount, address[] path);

    // ============ Constructor ============

    constructor(
        address _vault,
        address _host,
        address _gateway
    ) Ownable(msg.sender) {
        if (_vault == address(0) || _host == address(0) || _gateway == address(0)) revert ZeroAddress();
        vault = PayChainVault(_vault);
        gateway = PayChainGateway(_gateway);
        _HYPERBRIDGE_HOST = _host;
    }

    // ============ Admin Functions ============

    /// @notice Set a custom swap router for fee quotes
    /// @param _router Address of the Uniswap V2 compatible router
    function setSwapRouter(address _router) external onlyOwner {
        swapRouter = _router;
        emit SwapRouterSet(_router);
    }

    /// @notice Set the TokenSwapper for V4/V3 quotes and swaps
    /// @param _swapper Address of the TokenSwapper contract
    function setSwapper(address _swapper) external onlyOwner {
        swapper = ISwapperHB(_swapper);
        emit SwapperSet(_swapper);
    }


    /// @notice Set the state machine identifier for a chain
    /// @param chainId CAIP-2 chain identifier (e.g., "eip155:1")
    /// @param stateMachineId Hyperbridge state machine ID (e.g., "EVM-1")
    function setStateMachineId(string calldata chainId, bytes calldata stateMachineId) external onlyOwner {
        stateMachineIds[chainId] = stateMachineId;
        emit StateMachineIdSet(chainId, stateMachineId);
    }

    /// @notice Set the destination contract for a chain
    /// @param chainId CAIP-2 chain identifier
    /// @param destination Encoded destination contract address
    function setDestinationContract(string calldata chainId, bytes calldata destination) external onlyOwner {
        require(destination.length == 20, "Invalid address length");
        destinationContracts[chainId] = destination;
        emit DestinationContractSet(chainId, destination);
    }

    /// @notice Update the default timeout
    /// @param newTimeout New timeout in seconds
    function setDefaultTimeout(uint64 newTimeout) external onlyOwner {
        if (newTimeout < 300) revert InvalidTimeout(); // Minimum 5 minutes
        emit TimeoutUpdated(defaultTimeout, newTimeout);
        defaultTimeout = newTimeout;
    }

    // ============ IBridgeAdapter Implementation ============

    /// @notice Quote the fee in native currency for sending a message via Hyperbridge
    /// @dev Hyperbridge expects DispatchPost.fee in fee-token units. This method converts
    ///      that fee-token requirement to native using the host configured swap router.
    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
        uint256 feeTokenAmount = _feeTokenAmount(message);
        address feeToken = IDispatcher(host()).feeToken();
        
        // Use configured router or fallback to host's router
        address currentRouter = swapRouter;
        if (currentRouter == address(0)) {
            currentRouter = IDispatcher(host()).uniswapV2Router();
        }
        
        if (currentRouter == address(0)) revert NativeFeeQuoteUnavailable();
        address weth = IUniswapV2Router02HB(currentRouter).WETH();

        // Tier 1 & 2: TokenSwapper (V4 & V3)
        if (address(swapper) != address(0)) {
            // Estimate native fee using rate from swapper
            // Since ISwapper doesn't have getAmountsIn, we use getQuote for a trial amount
            uint256 trialAmount = 1 ether;
            try swapper.getQuote(weth, feeToken, trialAmount) returns (uint256 amountOut) {
                if (amountOut > 0) {
                     // feeTokenAmount * (trialAmount / amountOut)
                     uint256 estimatedFee = (feeTokenAmount * trialAmount) / amountOut;
                     // Add 10% safety margin
                     return (estimatedFee * 110) / 100;
                }
            } catch {}
        }

        // Tier 3: Uniswap V2 Fallback
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = feeToken;

        try IUniswapV2Router02HB(currentRouter).getAmountsIn(feeTokenAmount, path) returns (uint256[] memory amountsIn) {
            if (amountsIn.length == 0) revert NativeFeeQuoteUnavailable();
            // Add a small safety margin to reduce underfunded dispatches under fast price movement.
            return (amountsIn[0] * 110) / 100; // +10%
        } catch {
            revert FeeQuoteFailed(feeTokenAmount, path);
        }
    }

    /// @notice Return raw Hyperbridge fee-token amount (not native)
    function quoteFeeTokenAmount(BridgeMessage calldata message) external view returns (uint256) {
        return _feeTokenAmount(message);
    }

    /// @notice Quote token-denominated fee required by Hyperbridge dispatcher
    function _feeTokenAmount(BridgeMessage calldata message) internal view returns (uint256 feeTokenAmount) {
        bytes memory smId = stateMachineIds[message.destChainId];
        if (smId.length == 0) revert StateMachineIdNotSet(message.destChainId);

        // Calculate payload size
        bytes memory body = _encodePayload(message);
        
        // Get per-byte fee from dispatcher
        uint256 perByteFee = IDispatcher(host()).perByteFee(smId);
        
        // Calculate fee based on message size
        // Body + overhead for ISMP message structure
        uint256 messageSize = body.length + 256; // 256 bytes overhead estimate
        return messageSize * perByteFee;
    }

    /// @notice Send a cross-chain message via Hyperbridge ISMP
    /// @param message The bridge message containing payment details
    /// @return commitment The request commitment (message ID)
    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32 commitment) {
        bytes memory smId = stateMachineIds[message.destChainId];
        if (smId.length == 0) revert StateMachineIdNotSet(message.destChainId);
        
        bytes memory destContract = destinationContracts[message.destChainId];
        if (destContract.length == 0) revert DestinationNotSet(message.destChainId);

        address feeToken = IDispatcher(host()).feeToken();
        uint256 feeTokenAmount = _feeTokenAmount(message);
        uint256 nativeQuote = this.quoteFee(message);
        if (msg.value < nativeQuote) revert InsufficientNativeFee(nativeQuote, msg.value);

        // Encode the payment instruction payload
        bytes memory body = _encodePayload(message);

        // Tier 1 & 2: TokenSwapper (V4 & V3)
        bool swapped = false;
        if (address(swapper) != address(0)) {
            address currentRouter = swapRouter;
            if (currentRouter == address(0)) {
                currentRouter = IDispatcher(host()).uniswapV2Router();
            }
            address weth = IUniswapV2Router02HB(currentRouter).WETH();

            // 1. Wrap native to WETH
            IWETHHB(weth).deposit{value: nativeQuote}();
            
            // 2. Approve swapper
            IERC20(weth).forceApprove(address(swapper), nativeQuote);
            
            // 3. Swap WETH to feeToken
            try swapper.swap(weth, feeToken, nativeQuote, feeTokenAmount, address(this)) returns (uint256 amountOut) {
                if (amountOut >= feeTokenAmount) {
                    swapped = true;
                } else {
                    // Not enough tokens swapped, unwrap back to native for V2 fallback
                    IWETHHB(weth).withdraw(nativeQuote);
                }
            } catch {
                // Swap failed, unwrap back to native for V2 fallback
                IWETHHB(weth).withdraw(nativeQuote);
            }
        }

        // Build DispatchPost request
        DispatchPost memory request = DispatchPost({
            dest: smId,
            to: destContract,
            body: body,
            timeout: defaultTimeout,
            fee: feeTokenAmount,
            payer: swapped ? address(this) : msg.sender
        });

        if (swapped) {
            // Direct fee token payment
            IERC20(feeToken).forceApprove(host(), feeTokenAmount);
            commitment = IDispatcher(host()).dispatch{value: 0}(request);
        } else {
            // Tier 3: Uniswap V2 Fallback (Dispatcher internal swap)
            commitment = IDispatcher(host()).dispatch{value: nativeQuote}(request);
        }

        // Refund excess native tokens
        uint256 refund = msg.value - nativeQuote;
        if (refund > 0) {
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
        }

        emit MessageDispatched(
            commitment,
            message.destChainId,
            message.paymentId,
            message.amount,
            message.receiver
        );

        return commitment;
    }


    // ============ View Functions ============

    /// @notice Check if a chain is configured
    /// @param chainId CAIP-2 chain identifier
    /// @return configured Whether the chain has both SM ID and destination set
    function isChainConfigured(string calldata chainId) external view returns (bool configured) {
        return stateMachineIds[chainId].length > 0 && destinationContracts[chainId].length > 0;
    }

    /// @notice IBridgeAdapter compatibility helper
    function isRouteConfigured(string calldata chainId) external view override returns (bool configured) {
        return stateMachineIds[chainId].length > 0 && destinationContracts[chainId].length > 0;
    }

    /// @notice Return route config diagnostics blobs
    function getRouteConfig(
        string calldata chainId
    ) external view override returns (bool configured, bytes memory configA, bytes memory configB) {
        bytes memory sm = stateMachineIds[chainId];
        bytes memory dst = destinationContracts[chainId];
        return (sm.length > 0 && dst.length > 0, sm, dst);
    }

    /// @notice Get the fee token used by Hyperbridge
    /// @return feeToken The ERC20 fee token address
    function getFeeToken() external view returns (address feeToken) {
        return IDispatcher(host()).feeToken();
    }

    // ============ HyperApp Support ============

    function host() public view override returns (address) {
        return _HYPERBRIDGE_HOST;
    }

    /// @notice Handle timed-out post requests from Hyperbridge
    /// @dev Called by the ISMP host when a dispatched message is not delivered before timeout
    /// @param request The original PostRequest that timed out
    function onPostRequestTimeout(PostRequest calldata request) external override onlyHost {
        bytes32 paymentId = _decodePaymentId(request.body);
        
        gateway.markPaymentFailed(paymentId, "HYPERBRIDGE_TIMEOUT");
        gateway.processRefund(paymentId);

        emit PostRequestTimedOut(paymentId);
    }

    // ============ Internal Functions ============

    /// @notice Encode the payment instruction payload
    /// @param message The bridge message
    /// @return body Encoded payload bytes
    function _encodePayload(BridgeMessage calldata message) internal pure returns (bytes memory body) {
        // Encode payment details for the destination receiver
        // Format: (paymentId, amount, destToken, receiver, minAmountOut)
        body = abi.encode(
            message.paymentId,
            message.amount,
            message.destToken,
            message.receiver,
            message.minAmountOut,
            message.sourceToken
        );
    }

    function _decodePaymentId(bytes memory data) internal pure returns (bytes32 paymentId) {
        // We only care about the first element, paymentId.
        // Try decoding with full signature to be safe, or just first field.
        // abi.decode parses strictly.
        // We know the sourceToken might or might not be there depending on version, 
        // but _encodePayload above includes it.
        
        // Attempt full decode
        if (data.length >= 192) {
            (paymentId, , , , , ) = abi.decode(
                data,
                (bytes32, uint256, address, address, uint256, address)
            );
            return paymentId;
        }
        
        // Fallback for older messages
        (paymentId, , , , ) = abi.decode(
            data,
            (bytes32, uint256, address, address, uint256)
        );
        return paymentId;
    }

    // ============ Receive & Withdraw ============

    /// @notice Allow receiving ETH (e.g. from Host refunds)
    receive() external payable {}

    /// @notice Rescue ETH stuck in contract
    function withdrawEth(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw failed");
    }
}

