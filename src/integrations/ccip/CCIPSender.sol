// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IBridgeAdapter.sol";
import "../../vaults/PayChainVault.sol";
import "../../ccip/IRouterClient.sol";
import "../../ccip/Client.sol";

/**
 * @title CCIPSender
 * @notice Bridge Adapter for sending CCIP messages
 */
contract CCIPSender is IBridgeAdapter, Ownable {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    PayChainVault public vault;
    IRouterClient public router;
    
    /// @notice mapping(chain CAIP-2 string => CCIP chainSelector)
    mapping(string => uint64) public chainSelectors;
    
    /// @notice mapping(chain CAIP-2 string => Remote Adapter Address (bytes))
    mapping(string => bytes) public destinationAdapters;

    /// @notice Gas limits per destination chain
    mapping(string => uint256) public destinationGasLimits;
    
    /// @notice Default gas limit for destinations
    uint256 public constant DEFAULT_GAS_LIMIT = 200_000;

    // ============ Constructor ============

    constructor(
        address _vault,
        address _router
    ) Ownable(msg.sender) {
        vault = PayChainVault(_vault);
        router = IRouterClient(_router);
    }

    // ============ Admin Functions ============

    function setChainSelector(string calldata chainId, uint64 selector) external onlyOwner {
        chainSelectors[chainId] = selector;
    }
    
    function setDestinationAdapter(string calldata chainId, bytes calldata adapter) external onlyOwner {
        destinationAdapters[chainId] = adapter;
    }

    /// @notice Set custom gas limit for a destination chain
    /// @param chainId CAIP-2 chain identifier
    /// @param gasLimit Gas limit for execution on destination
    function setDestinationGasLimit(string calldata chainId, uint256 gasLimit) external onlyOwner {
        require(gasLimit >= 100_000, "Gas limit too low");
        destinationGasLimits[chainId] = gasLimit;
    }

    // ============ IBridgeAdapter Implementation ============

    function quoteFee(BridgeMessage calldata message) external view override returns (uint256 fee) {
         uint64 destChainSelector = chainSelectors[message.destChainId];
         require(destChainSelector != 0, "Chain not supported");

         Client.EVM2AnyMessage memory ccipMessage = _buildMessage(message);
         return router.getFee(destChainSelector, ccipMessage);
    }

    function sendMessage(BridgeMessage calldata message) external payable override returns (bytes32 messageId) {
        uint64 destChainSelector = chainSelectors[message.destChainId];
        require(destChainSelector != 0, "Chain not supported");

        // 1. Pull tokens from Vault to Here
        vault.pushTokens(message.sourceToken, address(this), message.amount);

        // 2. Approve Bridge Router
        IERC20(message.sourceToken).forceApprove(address(router), message.amount);

        // 3. Build & Send Message
        Client.EVM2AnyMessage memory ccipMessage = _buildMessage(message);
        
        // Router returns bytes32 messageId
        messageId = router.ccipSend{value: msg.value}(destChainSelector, ccipMessage);
        
        return messageId;
    }

    // ============ Internal Helpers ============

    function _buildMessage(BridgeMessage calldata message) internal view returns (Client.EVM2AnyMessage memory) {
        bytes memory destAdapter = destinationAdapters[message.destChainId];
        require(destAdapter.length > 0, "Dest adapter not set");

        // Construct token amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: message.sourceToken,
            amount: message.amount
        });

        // Get gas limit for destination chain (fallback to default)
        uint256 gasLimit = destinationGasLimits[message.destChainId];
        if (gasLimit == 0) {
            gasLimit = DEFAULT_GAS_LIMIT;
        }

        // Use EVMExtraArgsV2 for enhanced control
        // allowOutOfOrderExecution = false ensures strict message ordering
        bytes memory extraArgs = Client._argsToBytes(
            Client.EVMExtraArgsV2({
                gasLimit: gasLimit,
                allowOutOfOrderExecution: false
            })
        );
        
        return Client.EVM2AnyMessage({
            receiver: destAdapter, // Send to configured Remote Adapter
            data: abi.encode(message.paymentId, message.destToken, message.receiver, message.minAmountOut), // Encode User Receiver & Slippage in Payload
            tokenAmounts: tokenAmounts,
            extraArgs: extraArgs,
            feeToken: address(0) // Pay in Native
        });
    }
}
