// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PaymentKitaVault.sol";
import "./IRouterClient.sol";
import "./Client.sol";

/**
 * @title CCIPSender
 * @notice Bridge Adapter for sending CCIP messages
 */
contract CCIPSender is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PaymentKitaVault public vault;
    IRouterClient public router;
    
    /// @notice mapping(chain CAIP-2 string => CCIP chainSelector)
    mapping(string => uint64) public chainSelectors;
    
    /// @notice mapping(chain CAIP-2 string => Remote Adapter Address (bytes))
    mapping(string => bytes) public destinationAdapters;

    /// @notice Gas limits per destination chain
    mapping(string => uint256) public destinationGasLimits;

    /// @notice Optional raw CCIP extraArgs override per destination chain.
    /// If empty, sender builds default EVMExtraArgsV2(gasLimit, allowOutOfOrder=false).
    mapping(string => bytes) public destinationExtraArgs;

    /// @notice Optional CCIP fee token per destination chain. address(0) => native.
    mapping(string => address) public destinationFeeTokens;
    
    /// @notice Default gas limit for destinations
    uint256 public constant DEFAULT_GAS_LIMIT = 200_000;

    /// @notice Allowed upstream contracts that may dispatch sendMessage (e.g. PaymentKitaRouter)
    mapping(address => bool) public authorizedCallers;

    error ChainSelectorMissing(string chainId);
    error DestinationAdapterMissing(string chainId);
    error UnauthorizedCaller(address caller);
    error InsufficientNativeFee(uint256 provided, uint256 required);
    error DestinationChainNotSupported(uint64 selector);
    error InvalidMsgValueForFeeToken(uint256 provided);
    error InvalidPayer();
    error NativeFeeRefundFailed(address payer, uint256 amount);

    event ChainConfigSet(string indexed chainId, uint64 selector, address destAdapter);
    event AuthorizedCallerUpdated(address indexed caller, bool allowed);
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event DestinationExtraArgsSet(string indexed chainId, bytes extraArgs);
    event DestinationFeeTokenSet(string indexed chainId, address feeToken);
    event NativeFeeSettled(
        bytes32 indexed paymentId,
        address indexed payer,
        uint256 requiredFee,
        uint256 providedFee,
        uint256 refundedFee
    );

    // ============ Constructor ============

    constructor(
        address _vault,
        address _router
    ) Ownable(msg.sender) {
        vault = PaymentKitaVault(_vault);
        router = IRouterClient(_router);
    }

    // ============ Admin Functions ============

    function setChainSelector(string calldata chainId, uint64 selector) external onlyOwner {
        chainSelectors[chainId] = selector;
    }
    
    function setDestinationAdapter(string calldata chainId, bytes calldata adapter) external onlyOwner {
        destinationAdapters[chainId] = adapter;
    }

    /// @notice Set chain config in a single call (selector + destination adapter)
    /// @param chainId CAIP-2 chain identifier
    /// @param selector CCIP chain selector
    /// @param destAdapter Remote adapter address on destination chain
    function setChainConfig(string calldata chainId, uint64 selector, address destAdapter) external onlyOwner {
        chainSelectors[chainId] = selector;
        destinationAdapters[chainId] = abi.encode(destAdapter);
        emit ChainConfigSet(chainId, selector, destAdapter);
    }

    /// @notice Diagnostic: verify chain config exists
    /// @param chainId CAIP-2 chain identifier
    /// @return selector The CCIP chain selector
    /// @return destAdapter The destination adapter address
    function getChainConfig(string calldata chainId) external view returns (uint64 selector, address destAdapter) {
        selector = chainSelectors[chainId];
        bytes memory adapter = destinationAdapters[chainId];
        if (adapter.length > 0) {
            destAdapter = abi.decode(adapter, (address));
        }
    }

    /// @notice Set custom gas limit for a destination chain
    /// @param chainId CAIP-2 chain identifier
    /// @param gasLimit Gas limit for execution on destination
    function setDestinationGasLimit(string calldata chainId, uint256 gasLimit) external onlyOwner {
        require(gasLimit >= 100_000, "Gas limit too low");
        destinationGasLimits[chainId] = gasLimit;
    }

    /// @notice Set raw CCIP extraArgs for destination chain.
    /// @dev Pass empty bytes to clear and fallback to default extraArgs derivation.
    function setDestinationExtraArgs(string calldata chainId, bytes calldata extraArgs) external onlyOwner {
        destinationExtraArgs[chainId] = extraArgs;
        emit DestinationExtraArgsSet(chainId, extraArgs);
    }

    /// @notice Set fee token for destination chain.
    /// @dev address(0) means pay fee in native gas token.
    function setDestinationFeeToken(string calldata chainId, address feeToken) external onlyOwner {
        destinationFeeTokens[chainId] = feeToken;
        emit DestinationFeeTokenSet(chainId, feeToken);
    }

    /// @notice Authorize a contract to call sendMessage
    function setAuthorizedCaller(address caller, bool allowed) external onlyOwner {
        require(caller != address(0), "Invalid caller");
        authorizedCallers[caller] = allowed;
        emit AuthorizedCallerUpdated(caller, allowed);
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        emit VaultUpdated(address(vault), _vault);
        vault = PaymentKitaVault(_vault);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        emit RouterUpdated(address(router), _router);
        router = IRouterClient(_router);
    }

    // ============ IBridgeAdapter Implementation ============

    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
         uint64 destChainSelector = chainSelectors[message.destChainId];
         if (destChainSelector == 0) revert ChainSelectorMissing(message.destChainId);
         if (!router.isChainSupported(destChainSelector)) revert DestinationChainNotSupported(destChainSelector);

         Client.EVM2AnyMessage memory ccipMessage = _buildMessage(message);
         return router.getFee(destChainSelector, ccipMessage);
    }

    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32 messageId) {
        if (!authorizedCallers[msg.sender]) revert UnauthorizedCaller(msg.sender);

        uint64 destChainSelector = chainSelectors[message.destChainId];
        if (destChainSelector == 0) revert ChainSelectorMissing(message.destChainId);
        if (!router.isChainSupported(destChainSelector)) revert DestinationChainNotSupported(destChainSelector);

        // 1. Build message and validate fee requirements before touching vault balances.
        Client.EVM2AnyMessage memory ccipMessage = _buildMessage(message);
        uint256 requiredFee = router.getFee(destChainSelector, ccipMessage);
        address feeToken = ccipMessage.feeToken;

        if (feeToken == address(0)) {
            if (msg.value < requiredFee) revert InsufficientNativeFee(msg.value, requiredFee);
        } else if (msg.value != 0) {
            revert InvalidMsgValueForFeeToken(msg.value);
        }

        // 2. Pull source token from vault to this adapter.
        vault.pushTokens(message.sourceToken, address(this), message.amount);

        // 3. Approve CCIP router allowances.
        // If feeToken == sourceToken, aggregate allowance for both token transfer and fee payment.
        if (feeToken != address(0) && feeToken == message.sourceToken) {
            IERC20(message.sourceToken).forceApprove(address(router), message.amount + requiredFee);
        } else {
            IERC20(message.sourceToken).forceApprove(address(router), message.amount);
            if (feeToken != address(0) && requiredFee > 0) {
                IERC20(feeToken).forceApprove(address(router), requiredFee);
            }
        }

        if (feeToken == address(0)) {
            // Router returns bytes32 messageId
            messageId = router.ccipSend{value: requiredFee}(destChainSelector, ccipMessage);

            uint256 refundedFee = msg.value - requiredFee;
            if (refundedFee > 0) {
                if (message.payer == address(0)) revert InvalidPayer();
                (bool ok, ) = payable(message.payer).call{value: refundedFee}("");
                if (!ok) revert NativeFeeRefundFailed(message.payer, refundedFee);
            }

            emit NativeFeeSettled(message.paymentId, message.payer, requiredFee, msg.value, refundedFee);
        } else {
            messageId = router.ccipSend(destChainSelector, ccipMessage);
        }

        return messageId;
    }

    function isRouteConfigured(string calldata chainId) external view override returns (bool) {
        return chainSelectors[chainId] != 0 && destinationAdapters[chainId].length > 0;
    }

    function getRouteConfig(
        string calldata chainId
    ) external view override returns (bool configured, bytes memory configA, bytes memory configB) {
        uint256 gasLimit = destinationGasLimits[chainId];
        if (gasLimit == 0) {
            gasLimit = DEFAULT_GAS_LIMIT;
        }
        bytes memory adapter = destinationAdapters[chainId];
        return (
            chainSelectors[chainId] != 0 && adapter.length > 0,
            abi.encode(chainSelectors[chainId], gasLimit),
            adapter
        );
    }

    // ============ Internal Helpers ============

    function _buildMessage(BridgeMessage calldata message) internal view returns (Client.EVM2AnyMessage memory) {
        bytes memory destAdapter = destinationAdapters[message.destChainId];
        if (destAdapter.length == 0) revert DestinationAdapterMissing(message.destChainId);

        // Construct token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: message.sourceToken,
            amount: message.amount
        });

        bytes memory extraArgs = _resolveExtraArgs(message.destChainId);
        address feeToken = destinationFeeTokens[message.destChainId];
        
        return Client.EVM2AnyMessage({
            receiver: destAdapter, // Send to configured Remote Adapter
            data: abi.encode(message.paymentId, message.destToken, message.receiver, message.minAmountOut, message.sourceToken),
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: feeToken
        });
    }

    function _resolveExtraArgs(string calldata chainId) internal view returns (bytes memory extraArgs) {
        extraArgs = destinationExtraArgs[chainId];
        if (extraArgs.length > 0) {
            return extraArgs;
        }

        // Fallback default extra args
        uint256 gasLimit = destinationGasLimits[chainId];
        if (gasLimit == 0) {
            gasLimit = DEFAULT_GAS_LIMIT;
        }

        return Client._argsToBytes(
            Client.EVMExtraArgsV2({
                gasLimit: gasLimit,
                allowOutOfOrderExecution: false
            })
        );
    }
}
