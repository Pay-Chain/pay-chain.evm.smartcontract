// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Client.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IAny2EVMMessageReceiver
 * @notice Interface for receiving cross-chain messages
 */
interface IAny2EVMMessageReceiver {
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}

/**
 * @title CCIPReceiverBase
 * @notice Base contract for receiving CCIP messages
 */
abstract contract CCIPReceiverBase is IAny2EVMMessageReceiver, IERC165 {
    address internal immutable I_CCIP_ROUTER;

    constructor(address router) {
        if (router == address(0)) revert InvalidRouter(address(0));
        I_CCIP_ROUTER = router;
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function ccipReceive(Client.Any2EVMMessage calldata message) external virtual override onlyRouter {
        _ccipReceive(message);
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal virtual;

    function getRouter() public view returns (address) {
        return I_CCIP_ROUTER;
    }

    error InvalidRouter(address router);

    modifier onlyRouter() {
        _onlyRouter();
        _;
    }

    function _onlyRouter() internal view {
        if (msg.sender != I_CCIP_ROUTER) revert InvalidRouter(msg.sender);
    }
}

