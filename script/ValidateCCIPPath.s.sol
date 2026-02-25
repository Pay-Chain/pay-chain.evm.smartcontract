// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/IBridgeAdapter.sol";

interface IRouterCCIPValidate {
    function hasAdapter(string memory destChainId, uint8 bridgeType) external view returns (bool);
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
    function quotePaymentFee(
        string calldata destChainId,
        uint8 bridgeType,
        IBridgeAdapter.BridgeMessage calldata message
    ) external view returns (uint256 fee);
}

interface IGatewayCCIPValidate {
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface ICCIPSenderValidate {
    function chainSelectors(string calldata chainId) external view returns (uint64);
    function destinationAdapters(string calldata chainId) external view returns (bytes memory);
    function destinationGasLimits(string calldata chainId) external view returns (uint256);
    function destinationExtraArgs(string calldata chainId) external view returns (bytes memory);
    function destinationFeeTokens(string calldata chainId) external view returns (address);
    function authorizedCallers(address caller) external view returns (bool);
    function isRouteConfigured(string calldata chainId) external view returns (bool);
}

interface ICCIPReceiverValidate {
    function allowedSourceChains(uint64 chainSelector) external view returns (bool);
    function trustedSenders(uint64 chainSelector) external view returns (bytes memory);
}

contract ValidateCCIPPath is Script {
    struct ValidateConfig {
        address router;
        address gateway;
        string destCaip2;
        uint8 bridgeType;
        bool strict;
        address expectedAuthorizedCaller;
        bytes32 expectedDestAdapter;
        uint64 expectedDestChainSelector;
        uint64 sourceChainSelector;
        address receiver;
        bytes32 trustedSender;
        address sourceToken;
        address destToken;
        uint256 amount;
    }

    function run() external {
        ValidateConfig memory cfg = _resolveValidateConfig();
        IRouterCCIPValidate r = IRouterCCIPValidate(cfg.router);

        bool has = r.hasAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("hasAdapter:", has);
        if (cfg.strict) require(has, "CCIP validate: adapter missing");
        if (!has) return;

        address sender = r.getAdapter(cfg.destCaip2, cfg.bridgeType);
        console.log("sender:", sender);

        ICCIPSenderValidate s = ICCIPSenderValidate(sender);
        bool configured = s.isRouteConfigured(cfg.destCaip2);
        console.log("sender route configured:", configured);
        if (cfg.strict) require(configured, "CCIP validate: route not configured");

        uint64 selector = s.chainSelectors(cfg.destCaip2);
        bytes memory destAdapter = s.destinationAdapters(cfg.destCaip2);
        uint256 gasLimit = s.destinationGasLimits(cfg.destCaip2);
        bytes memory extraArgs = s.destinationExtraArgs(cfg.destCaip2);
        address feeToken = s.destinationFeeTokens(cfg.destCaip2);

        console.log("chainSelector:", selector);
        console.log("destAdapterLen:", destAdapter.length);
        console.log("gasLimit:", gasLimit);
        console.log("extraArgsLen:", extraArgs.length);
        console.log("feeToken:", feeToken);

        if (cfg.strict) {
            require(selector == cfg.expectedDestChainSelector, "CCIP validate: chainSelector mismatch");
            if (cfg.expectedDestAdapter != bytes32(0)) {
                require(destAdapter.length == 32, "CCIP validate: dest adapter length");
                bytes32 actualDestAdapter;
                assembly {
                    actualDestAdapter := mload(add(destAdapter, 32))
                }
                require(actualDestAdapter == cfg.expectedDestAdapter, "CCIP validate: dest adapter mismatch");
            }
        }

        if (cfg.expectedAuthorizedCaller != address(0)) {
            bool callerAllowed = s.authorizedCallers(cfg.expectedAuthorizedCaller);
            console.log("authorizedCaller:", callerAllowed);
            if (cfg.strict) require(callerAllowed, "CCIP validate: sender caller not authorized");
        }

        if (cfg.gateway != address(0)) {
            uint8 defaultBridge = IGatewayCCIPValidate(cfg.gateway).defaultBridgeTypes(cfg.destCaip2);
            console.log("gateway default bridge:", defaultBridge);
            if (cfg.strict) require(defaultBridge == cfg.bridgeType, "CCIP validate: default bridge mismatch");
        }

        if (cfg.receiver != address(0) && cfg.sourceChainSelector > 0) {
            ICCIPReceiverValidate receiver = ICCIPReceiverValidate(cfg.receiver);
            bool allowed = receiver.allowedSourceChains(cfg.sourceChainSelector);
            bytes memory trusted = receiver.trustedSenders(cfg.sourceChainSelector);
            console.log("receiver source allowed:", allowed);
            console.log("receiver trusted sender len:", trusted.length);

            if (cfg.strict) {
                require(allowed, "CCIP validate: source chain not allowed");
                if (cfg.trustedSender != bytes32(0)) {
                    require(trusted.length == 32, "CCIP validate: trusted sender length");
                    bytes32 trustedBytes;
                    assembly {
                        trustedBytes := mload(add(trusted, 32))
                    }
                    require(trustedBytes == cfg.trustedSender, "CCIP validate: trusted sender mismatch");
                }
            }
        }

        if (cfg.sourceToken != address(0) && cfg.destToken != address(0) && cfg.amount > 0) {
            IBridgeAdapter.BridgeMessage memory m = IBridgeAdapter.BridgeMessage({
                paymentId: bytes32(0),
                receiver: address(0),
                sourceToken: cfg.sourceToken,
                destToken: cfg.destToken,
                amount: cfg.amount,
                destChainId: cfg.destCaip2,
                minAmountOut: 0,
                payer: address(0)
            });
            try r.quotePaymentFee(cfg.destCaip2, cfg.bridgeType, m) returns (uint256 fee) {
                console.log("quotePaymentFee:", fee);
                if (cfg.strict) require(fee > 0, "CCIP validate: quote zero");
            } catch {
                if (cfg.strict) revert("CCIP validate: quote reverted");
                console.log("quotePaymentFee: reverted");
            }
        }
    }

    function _resolveValidateConfig() internal returns (ValidateConfig memory cfg) {
        string memory profile = vm.envOr("CCIP_VALIDATE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = ValidateConfig({
                router: 0x1d7550079DAe36f55F4999E0B24AC037D092249C,
                gateway: 0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D,
                destCaip2: vm.envOr("BASE_CCIP_VALIDATE_DEST_CAIP2", string("eip155:137")),
                bridgeType: uint8(vm.envOr("BASE_CCIP_VALIDATE_BRIDGE_TYPE", uint256(1))),
                strict: vm.envOr("BASE_CCIP_VALIDATE_STRICT", true),
                expectedAuthorizedCaller: vm.envOr("BASE_CCIP_VALIDATE_AUTH_CALLER", address(0x1d7550079DAe36f55F4999E0B24AC037D092249C)),
                expectedDestAdapter: bytes32(0),
                expectedDestChainSelector: uint64(vm.envOr("BASE_CCIP_VALIDATE_DEST_SELECTOR", uint256(4051577828743386545))),
                sourceChainSelector: uint64(vm.envOr("BASE_CCIP_VALIDATE_SOURCE_SELECTOR", uint256(15971525489660198786))),
                receiver: vm.envOr("BASE_CCIP_VALIDATE_RECEIVER", address(0)),
                trustedSender: bytes32(0),
                sourceToken: vm.envOr("BASE_CCIP_VALIDATE_SOURCE_TOKEN", address(0)),
                destToken: vm.envOr("BASE_CCIP_VALIDATE_DEST_TOKEN", address(0)),
                amount: vm.envOr("BASE_CCIP_VALIDATE_AMOUNT", uint256(0))
            });
        } else {
            revert("CCIP validate: unknown profile or chainid");
        }

        if (block.chainid == 8453) {
            string memory baseDestAdapterHex = vm.envOr("BASE_CCIP_VALIDATE_DEST_ADAPTER_BYTES32", string(""));
            if (bytes(baseDestAdapterHex).length > 0) {
                cfg.expectedDestAdapter = vm.parseBytes32(baseDestAdapterHex);
            }
            string memory baseTrustedSenderHex = vm.envOr("BASE_CCIP_VALIDATE_TRUSTED_SENDER_BYTES32", string(""));
            if (bytes(baseTrustedSenderHex).length > 0) {
                cfg.trustedSender = vm.parseBytes32(baseTrustedSenderHex);
            }
        }

        // Optional global overrides for emergency checks
        cfg.router = vm.envOr("CCIP_VALIDATE_ROUTER", cfg.router);
        cfg.gateway = vm.envOr("CCIP_VALIDATE_GATEWAY", cfg.gateway);
        cfg.destCaip2 = vm.envOr("CCIP_VALIDATE_DEST_CAIP2", cfg.destCaip2);
        cfg.bridgeType = uint8(vm.envOr("CCIP_VALIDATE_BRIDGE_TYPE", uint256(cfg.bridgeType)));
        cfg.strict = vm.envOr("CCIP_VALIDATE_STRICT", cfg.strict);
        cfg.expectedAuthorizedCaller = vm.envOr("CCIP_VALIDATE_AUTH_CALLER", cfg.expectedAuthorizedCaller);
        cfg.expectedDestChainSelector = uint64(vm.envOr("CCIP_VALIDATE_DEST_SELECTOR", uint256(cfg.expectedDestChainSelector)));
        cfg.sourceChainSelector = uint64(vm.envOr("CCIP_VALIDATE_SOURCE_SELECTOR", uint256(cfg.sourceChainSelector)));
        cfg.receiver = vm.envOr("CCIP_VALIDATE_RECEIVER", cfg.receiver);
        cfg.sourceToken = vm.envOr("CCIP_VALIDATE_SOURCE_TOKEN", cfg.sourceToken);
        cfg.destToken = vm.envOr("CCIP_VALIDATE_DEST_TOKEN", cfg.destToken);
        cfg.amount = vm.envOr("CCIP_VALIDATE_AMOUNT", cfg.amount);

        string memory expectedDestAdapterHex = vm.envOr("CCIP_VALIDATE_DEST_ADAPTER_BYTES32", string(""));
        if (bytes(expectedDestAdapterHex).length > 0) {
            cfg.expectedDestAdapter = vm.parseBytes32(expectedDestAdapterHex);
        }
        string memory trustedSenderHex = vm.envOr("CCIP_VALIDATE_TRUSTED_SENDER_BYTES32", string(""));
        if (bytes(trustedSenderHex).length > 0) {
            cfg.trustedSender = vm.parseBytes32(trustedSenderHex);
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
