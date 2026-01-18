// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Client.sol";
import "./IRouterClient.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IAny2EVMMessageReceiver
 * @notice Interface for receiving cross-chain messages
 */
interface IAny2EVMMessageReceiver {
    /// @notice Called by the Router to deliver a message.
    /// If this reverts, any token transfers also revert.
    /// @param message CCIP Message
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}

/**
 * @title CCIPReceiver
 * @notice Base contract for receiving CCIP messages
 */
abstract contract CCIPReceiver is IAny2EVMMessageReceiver, IERC165 {
    address internal immutable i_ccipRouter;

    constructor(address router) {
        if (router == address(0)) revert InvalidRouter(address(0));
        i_ccipRouter = router;
    }

    /// @notice IERC165 supports an interface id
    /// @param interfaceId The interface identifier, as specified in ERC-165
    /// @return True if the contract supports interfaceId, false otherwise
    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual override returns (bool) {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IAny2EVMMessageReceiver
    function ccipReceive(
        Client.Any2EVMMessage calldata message
    ) external virtual override onlyRouter {
        _ccipReceive(message);
    }

    /// @notice Override this function in your implementation.
    /// @param message Any2EVMMessage
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal virtual;

    /// @notice Return the current router
    /// @return CCIP router address
    function getRouter() public view returns (address) {
        return i_ccipRouter;
    }

    error InvalidRouter(address router);

    /// @dev only calls from the set router are accepted.
    modifier onlyRouter() {
        if (msg.sender != i_ccipRouter) revert InvalidRouter(msg.sender);
        _;
    }
}
