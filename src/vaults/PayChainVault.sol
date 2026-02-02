// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PayChainVault
 * @notice Central vault for holding PayChain Protocol assets
 * @dev Handles user deposits, approvals, and withdrawals by authorized components (Gateway/Adapters)
 */
contract PayChainVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice Authorized spenders (Gateway, Adapters, TokenSwapper)
    mapping(address => bool) public authorizedSpenders;

    // ============ Events ============

    event SpenderAuthorized(address indexed spender, bool authorized);
    event TokensDeposited(address indexed user, address indexed token, uint256 amount);
    event TokensWithdrawn(address indexed to, address indexed token, uint256 amount);

    // ============ Errors ============

    error Unauthorized();
    error InvalidAddress();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        if (!authorizedSpenders[msg.sender] && msg.sender != owner()) {
            revert Unauthorized();
        }
        _;
    }

    // ============ Core Logic ============

    /**
     * @notice Pull tokens from user to vault
     * @dev Used by Gateway to collect payment
     * @param token Token to transfer
     * @param from User address
     * @param amount Amount to transfer
     */
    function pullTokens(
        address token,
        address from,
        uint256 amount
    ) external onlyAuthorized nonReentrant {
        IERC20(token).safeTransferFrom(from, address(this), amount);
        emit TokensDeposited(from, token, amount);
    }

    /**
     * @notice Push tokens from vault to destination
     * @dev Used by Adapters/Swapper to move funds
     * @param token Token to transfer
     * @param to Destination address
     * @param amount Amount to transfer
     */
    function pushTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyAuthorized nonReentrant {
        IERC20(token).safeTransfer(to, amount);
        emit TokensWithdrawn(to, token, amount);
    }

    /**
     * @notice Approve token usage by an external contract (e.g. 3rd party bridge/router)
     * @dev Only authorized components can request approvals (e.g. Swapper or Adapter)
     * @param token Token to approve
     * @param spender Spender address
     * @param amount Amount to approve
     */
    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external onlyAuthorized {
        IERC20(token).forceApprove(spender, amount);
    }

    // ============ Admin Functions ============

    /**
     * @notice Authorize a contract to spend/move vault funds
     * @param spender Address to authorize
     * @param authorized Status
     */
    function setAuthorizedSpender(address spender, bool authorized) external onlyOwner {
        if (spender == address(0)) revert InvalidAddress();
        authorizedSpenders[spender] = authorized;
        emit SpenderAuthorized(spender, authorized);
    }

    /**
     * @notice Emergency withdrawal of funds
     * @param token Token address
     * @param to Recipient
     * @param amount Amount
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        IERC20(token).safeTransfer(to, amount);
    }
}
