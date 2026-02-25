// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/integrations/ccip/CCIPSender.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";

interface IRouterRotateCCIP {
    function registerAdapter(string calldata destChainId, uint8 bridgeType, address adapter) external;
    function getAdapter(string calldata destChainId, uint8 bridgeType) external view returns (address);
}

interface IGatewayRotateCCIP {
    function setAuthorizedAdapter(address adapter, bool authorized) external;
    function setDefaultBridgeType(string calldata destChainId, uint8 bridgeType) external;
    function defaultBridgeTypes(string calldata destChainId) external view returns (uint8);
}

interface IVaultRotateCCIP {
    function setAuthorizedSpender(address spender, bool authorized) external;
}

interface ICCIPSenderView {
    function chainSelectors(string calldata chainId) external view returns (uint64);
    function destinationAdapters(string calldata chainId) external view returns (bytes memory);
    function authorizedCallers(address caller) external view returns (bool);
}

interface ICCIPReceiverView {
    function trustedSenders(uint64 chainSelector) external view returns (bytes memory);
    function allowedSourceChains(uint64 chainSelector) external view returns (bool);
    function swapper() external view returns (address);
}

contract RotateCCIPAdapters is Script {
    uint8 internal constant BRIDGE_TYPE_CCIP = 1;

    address internal constant CCIP_ROUTER_BASE = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;
    address internal constant CCIP_ROUTER_POLYGON = 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
    address internal constant CCIP_ROUTER_ARBITRUM = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    address internal constant CCIP_ROUTER_BSC = 0x34B03Cb9086d7D758AC55af71584F81A598759FE;

    uint64 internal constant SELECTOR_BASE = 15971525489660198786;
    uint64 internal constant SELECTOR_POLYGON = 4051577828743386545;
    uint64 internal constant SELECTOR_ARBITRUM = 4949039107694359620;
    uint64 internal constant SELECTOR_BSC = 11344663589394136015;

    error InvalidHexString();

    struct RotateConfig {
        address ccipRouter;
        address router;
        address gateway;
        address vault;
        string destCaip2;
        uint64 destSelector;
        address destReceiverAdapter;
        uint256 destGasLimit;
        bytes destExtraArgs;
        address destFeeToken;
        uint64 sourceSelector;
        address sourceTrustedSender;
        bool setSourceAllowedWhenTrustedMissing;
        bool deauthorizeOld;
        bool setDefaultBridgeType;
        address oldSender;
        address oldReceiver;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        RotateConfig memory cfg = _resolveRotateConfig();

        require(cfg.ccipRouter != address(0), "RotateCCIP: ccip router missing");
        require(cfg.router != address(0), "RotateCCIP: router missing");
        require(cfg.gateway != address(0), "RotateCCIP: gateway missing");
        require(cfg.vault != address(0), "RotateCCIP: vault missing");
        require(bytes(cfg.destCaip2).length > 0, "RotateCCIP: destCaip2 missing");
        require(cfg.destSelector > 0, "RotateCCIP: dest selector missing");
        require(cfg.destReceiverAdapter != address(0), "RotateCCIP: destination receiver missing");

        vm.startBroadcast(pk);

        CCIPSender newSender = new CCIPSender(cfg.vault, cfg.ccipRouter);
        CCIPReceiverAdapter newReceiver = new CCIPReceiverAdapter(cfg.ccipRouter, cfg.gateway);

        address receiverSwapper = address(0);
        if (cfg.oldReceiver != address(0)) {
            receiverSwapper = ICCIPReceiverView(cfg.oldReceiver).swapper();
        }
        if (receiverSwapper != address(0)) {
            newReceiver.setSwapper(receiverSwapper);
        }

        newSender.setAuthorizedCaller(cfg.router, true);
        newSender.setChainConfig(cfg.destCaip2, cfg.destSelector, cfg.destReceiverAdapter);
        newSender.setDestinationGasLimit(cfg.destCaip2, cfg.destGasLimit);
        if (cfg.destExtraArgs.length > 0) {
            newSender.setDestinationExtraArgs(cfg.destCaip2, cfg.destExtraArgs);
        }
        if (cfg.destFeeToken != address(0)) {
            newSender.setDestinationFeeToken(cfg.destCaip2, cfg.destFeeToken);
        }

        if (cfg.sourceSelector > 0) {
            if (cfg.sourceTrustedSender != address(0)) {
                newReceiver.setTrustedSender(cfg.sourceSelector, abi.encode(cfg.sourceTrustedSender));
            } else if (cfg.setSourceAllowedWhenTrustedMissing) {
                newReceiver.setSourceChainAllowed(cfg.sourceSelector, true);
            }
        }

        IVaultRotateCCIP(cfg.vault).setAuthorizedSpender(address(newSender), true);
        IVaultRotateCCIP(cfg.vault).setAuthorizedSpender(address(newReceiver), true);
        IGatewayRotateCCIP(cfg.gateway).setAuthorizedAdapter(address(newReceiver), true);
        IRouterRotateCCIP(cfg.router).registerAdapter(cfg.destCaip2, BRIDGE_TYPE_CCIP, address(newSender));
        if (cfg.setDefaultBridgeType) {
            IGatewayRotateCCIP(cfg.gateway).setDefaultBridgeType(cfg.destCaip2, BRIDGE_TYPE_CCIP);
        }

        if (cfg.deauthorizeOld) {
            if (cfg.oldReceiver != address(0)) {
                IGatewayRotateCCIP(cfg.gateway).setAuthorizedAdapter(cfg.oldReceiver, false);
                IVaultRotateCCIP(cfg.vault).setAuthorizedSpender(cfg.oldReceiver, false);
            }
            if (cfg.oldSender != address(0)) {
                IVaultRotateCCIP(cfg.vault).setAuthorizedSpender(cfg.oldSender, false);
            }
        }

        require(
            IRouterRotateCCIP(cfg.router).getAdapter(cfg.destCaip2, BRIDGE_TYPE_CCIP) == address(newSender),
            "RotateCCIP: router adapter mismatch"
        );
        require(ICCIPSenderView(address(newSender)).chainSelectors(cfg.destCaip2) == cfg.destSelector, "RotateCCIP: selector mismatch");
        require(ICCIPSenderView(address(newSender)).authorizedCallers(cfg.router), "RotateCCIP: caller auth missing");

        bytes memory configuredDest = ICCIPSenderView(address(newSender)).destinationAdapters(cfg.destCaip2);
        require(
            keccak256(configuredDest) == keccak256(abi.encode(cfg.destReceiverAdapter)),
            "RotateCCIP: destination adapter mismatch"
        );

        if (cfg.sourceSelector > 0) {
            bool sourceAllowed = ICCIPReceiverView(address(newReceiver)).allowedSourceChains(cfg.sourceSelector);
            require(sourceAllowed, "RotateCCIP: source chain not allowed");
            if (cfg.sourceTrustedSender != address(0)) {
                bytes memory trusted = ICCIPReceiverView(address(newReceiver)).trustedSenders(cfg.sourceSelector);
                require(
                    keccak256(trusted) == keccak256(abi.encode(cfg.sourceTrustedSender)),
                    "RotateCCIP: trusted sender mismatch"
                );
            }
        }

        if (cfg.setDefaultBridgeType) {
            require(
                IGatewayRotateCCIP(cfg.gateway).defaultBridgeTypes(cfg.destCaip2) == BRIDGE_TYPE_CCIP,
                "RotateCCIP: default bridge mismatch"
            );
        }

        vm.stopBroadcast();

        console.log("RotateCCIPAdapters complete");
        console.log("New CCIP sender:", address(newSender));
        console.log("New CCIP receiver:", address(newReceiver));
        console.log("Dest CAIP2:", cfg.destCaip2);
        console.log("Dest selector:", uint256(cfg.destSelector));
        console.log("Source selector:", uint256(cfg.sourceSelector));
        console.log("Router:", cfg.router);
        console.log("Gateway:", cfg.gateway);
        console.log("Vault:", cfg.vault);
    }

    function _resolveRotateConfig() internal returns (RotateConfig memory cfg) {
        string memory profile = vm.envOr("CCIP_ROTATE_PROFILE", string("auto"));

        if (_eq(profile, "base") || (_eq(profile, "auto") && block.chainid == 8453)) {
            cfg = RotateConfig({
                ccipRouter: CCIP_ROUTER_BASE,
                router: 0x1d7550079DAe36f55F4999E0B24AC037D092249C,
                gateway: 0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D,
                vault: 0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7,
                destCaip2: vm.envOr("BASE_CCIP_ROTATE_DEST_CAIP2", string("eip155:137")),
                destSelector: uint64(vm.envOr("BASE_CCIP_ROTATE_DEST_SELECTOR", uint256(SELECTOR_POLYGON))),
                destReceiverAdapter: vm.envOr("BASE_CCIP_ROTATE_DEST_RECEIVER", address(0xbC75055BdF937353721BFBa9Dd1DCCFD0c70B8dd)),
                destGasLimit: vm.envOr("BASE_CCIP_ROTATE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("BASE_CCIP_ROTATE_DEST_EXTRA_ARGS_HEX", string(""))),
                destFeeToken: vm.envOr("BASE_CCIP_ROTATE_DEST_FEE_TOKEN", address(0)),
                sourceSelector: uint64(vm.envOr("BASE_CCIP_ROTATE_SOURCE_SELECTOR", uint256(SELECTOR_POLYGON))),
                sourceTrustedSender: vm.envOr("BASE_CCIP_ROTATE_SOURCE_TRUSTED_SENDER", address(0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500)),
                setSourceAllowedWhenTrustedMissing: vm.envOr("BASE_CCIP_ROTATE_ALLOW_SOURCE_WHEN_TRUSTED_EMPTY", true),
                deauthorizeOld: vm.envOr("BASE_CCIP_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("BASE_CCIP_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0xc60b6f567562c756bE5E29f31318bb7793852850,
                oldReceiver: 0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1
            });
        } else if (_eq(profile, "polygon") || (_eq(profile, "auto") && block.chainid == 137)) {
            cfg = RotateConfig({
                ccipRouter: CCIP_ROUTER_POLYGON,
                router: 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4,
                gateway: 0x7a4f3b606D90e72555A36cB370531638fad19Bf8,
                vault: 0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c,
                destCaip2: vm.envOr("POLYGON_CCIP_ROTATE_DEST_CAIP2", string("eip155:8453")),
                destSelector: uint64(vm.envOr("POLYGON_CCIP_ROTATE_DEST_SELECTOR", uint256(SELECTOR_BASE))),
                destReceiverAdapter: vm.envOr("POLYGON_CCIP_ROTATE_DEST_RECEIVER", address(0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1)),
                destGasLimit: vm.envOr("POLYGON_CCIP_ROTATE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("POLYGON_CCIP_ROTATE_DEST_EXTRA_ARGS_HEX", string(""))),
                destFeeToken: vm.envOr("POLYGON_CCIP_ROTATE_DEST_FEE_TOKEN", address(0)),
                sourceSelector: uint64(vm.envOr("POLYGON_CCIP_ROTATE_SOURCE_SELECTOR", uint256(SELECTOR_BASE))),
                sourceTrustedSender: vm.envOr("POLYGON_CCIP_ROTATE_SOURCE_TRUSTED_SENDER", address(0xc60b6f567562c756bE5E29f31318bb7793852850)),
                setSourceAllowedWhenTrustedMissing: vm.envOr("POLYGON_CCIP_ROTATE_ALLOW_SOURCE_WHEN_TRUSTED_EMPTY", true),
                deauthorizeOld: vm.envOr("POLYGON_CCIP_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("POLYGON_CCIP_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500,
                oldReceiver: 0xbC75055BdF937353721BFBa9Dd1DCCFD0c70B8dd
            });
        } else if (_eq(profile, "arbitrum") || (_eq(profile, "auto") && block.chainid == 42161)) {
            cfg = RotateConfig({
                ccipRouter: CCIP_ROUTER_ARBITRUM,
                router: 0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e,
                gateway: 0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8,
                vault: 0x12306CA381813595BeE3c64b19318419C9E12f02,
                destCaip2: vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_CAIP2", string("eip155:8453")),
                destSelector: uint64(vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_SELECTOR", uint256(SELECTOR_BASE))),
                destReceiverAdapter: vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_RECEIVER", address(0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1)),
                destGasLimit: vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_EXTRA_ARGS_HEX", string(""))),
                destFeeToken: vm.envOr("ARBITRUM_CCIP_ROTATE_DEST_FEE_TOKEN", address(0)),
                sourceSelector: uint64(vm.envOr("ARBITRUM_CCIP_ROTATE_SOURCE_SELECTOR", uint256(SELECTOR_BASE))),
                sourceTrustedSender: vm.envOr("ARBITRUM_CCIP_ROTATE_SOURCE_TRUSTED_SENDER", address(0xc60b6f567562c756bE5E29f31318bb7793852850)),
                setSourceAllowedWhenTrustedMissing: vm.envOr("ARBITRUM_CCIP_ROTATE_ALLOW_SOURCE_WHEN_TRUSTED_EMPTY", true),
                deauthorizeOld: vm.envOr("ARBITRUM_CCIP_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("ARBITRUM_CCIP_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: 0xC9126fACB9201d79EF860F7f4EF2037c69D80a56,
                oldReceiver: 0x0Fad39d945785b3d35B7C8a7aa856431c42B75f5
            });
        } else if (_eq(profile, "bsc") || (_eq(profile, "auto") && block.chainid == 56)) {
            cfg = RotateConfig({
                ccipRouter: CCIP_ROUTER_BSC,
                router: vm.envOr("BSC_CCIP_ROTATE_ROUTER", address(0)),
                gateway: vm.envOr("BSC_CCIP_ROTATE_GATEWAY", address(0)),
                vault: vm.envOr("BSC_CCIP_ROTATE_VAULT", address(0)),
                destCaip2: vm.envOr("BSC_CCIP_ROTATE_DEST_CAIP2", string("eip155:8453")),
                destSelector: uint64(vm.envOr("BSC_CCIP_ROTATE_DEST_SELECTOR", uint256(SELECTOR_BASE))),
                destReceiverAdapter: vm.envOr("BSC_CCIP_ROTATE_DEST_RECEIVER", address(0)),
                destGasLimit: vm.envOr("BSC_CCIP_ROTATE_DEST_GAS_LIMIT", uint256(200000)),
                destExtraArgs: _parseBytesOrEmpty(vm.envOr("BSC_CCIP_ROTATE_DEST_EXTRA_ARGS_HEX", string(""))),
                destFeeToken: vm.envOr("BSC_CCIP_ROTATE_DEST_FEE_TOKEN", address(0)),
                sourceSelector: uint64(vm.envOr("BSC_CCIP_ROTATE_SOURCE_SELECTOR", uint256(SELECTOR_BSC))),
                sourceTrustedSender: vm.envOr("BSC_CCIP_ROTATE_SOURCE_TRUSTED_SENDER", address(0)),
                setSourceAllowedWhenTrustedMissing: vm.envOr("BSC_CCIP_ROTATE_ALLOW_SOURCE_WHEN_TRUSTED_EMPTY", true),
                deauthorizeOld: vm.envOr("BSC_CCIP_ROTATE_DEAUTHORIZE_OLD", false),
                setDefaultBridgeType: vm.envOr("BSC_CCIP_ROTATE_SET_DEFAULT_BRIDGE", true),
                oldSender: vm.envOr("BSC_CCIP_ROTATE_OLD_SENDER", address(0)),
                oldReceiver: vm.envOr("BSC_CCIP_ROTATE_OLD_RECEIVER", address(0))
            });
        } else {
            revert("RotateCCIP: unknown profile or chainid");
        }

        cfg.ccipRouter = vm.envOr("CCIP_ROTATE_CCIP_ROUTER", cfg.ccipRouter);
        cfg.router = vm.envOr("CCIP_ROTATE_ROUTER", cfg.router);
        cfg.gateway = vm.envOr("CCIP_ROTATE_GATEWAY", cfg.gateway);
        cfg.vault = vm.envOr("CCIP_ROTATE_VAULT", cfg.vault);
        cfg.destCaip2 = vm.envOr("CCIP_ROTATE_DEST_CAIP2", cfg.destCaip2);
        cfg.destSelector = uint64(vm.envOr("CCIP_ROTATE_DEST_SELECTOR", uint256(cfg.destSelector)));
        cfg.destReceiverAdapter = vm.envOr("CCIP_ROTATE_DEST_RECEIVER", cfg.destReceiverAdapter);
        cfg.destGasLimit = vm.envOr("CCIP_ROTATE_DEST_GAS_LIMIT", cfg.destGasLimit);
        cfg.destFeeToken = vm.envOr("CCIP_ROTATE_DEST_FEE_TOKEN", cfg.destFeeToken);
        cfg.sourceSelector = uint64(vm.envOr("CCIP_ROTATE_SOURCE_SELECTOR", uint256(cfg.sourceSelector)));
        cfg.sourceTrustedSender = vm.envOr("CCIP_ROTATE_SOURCE_TRUSTED_SENDER", cfg.sourceTrustedSender);
        cfg.setSourceAllowedWhenTrustedMissing =
            vm.envOr("CCIP_ROTATE_ALLOW_SOURCE_WHEN_TRUSTED_EMPTY", cfg.setSourceAllowedWhenTrustedMissing);
        cfg.deauthorizeOld = vm.envOr("CCIP_ROTATE_DEAUTHORIZE_OLD", cfg.deauthorizeOld);
        cfg.setDefaultBridgeType = vm.envOr("CCIP_ROTATE_SET_DEFAULT_BRIDGE", cfg.setDefaultBridgeType);
        cfg.oldSender = vm.envOr("CCIP_ROTATE_OLD_SENDER", cfg.oldSender);
        cfg.oldReceiver = vm.envOr("CCIP_ROTATE_OLD_RECEIVER", cfg.oldReceiver);

        string memory globalExtraArgsHex = vm.envOr("CCIP_ROTATE_DEST_EXTRA_ARGS_HEX", string(""));
        if (bytes(globalExtraArgsHex).length > 0) {
            cfg.destExtraArgs = _parseBytesOrEmpty(globalExtraArgsHex);
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _parseBytesOrEmpty(string memory value) internal pure returns (bytes memory) {
        bytes memory s = bytes(value);
        if (s.length == 0) return bytes("");

        uint256 offset = 0;
        if (s.length >= 2 && s[0] == "0" && (s[1] == "x" || s[1] == "X")) {
            offset = 2;
        }

        uint256 hexLen = s.length - offset;
        if (hexLen == 0) return bytes("");
        if (hexLen % 2 != 0) revert InvalidHexString();

        bytes memory out = new bytes(hexLen / 2);
        for (uint256 i = 0; i < out.length; i++) {
            uint8 hi = _fromHexChar(uint8(s[offset + (2 * i)]));
            uint8 lo = _fromHexChar(uint8(s[offset + (2 * i) + 1]));
            out[i] = bytes1((hi << 4) | lo);
        }
        return out;
    }

    function _fromHexChar(uint8 c) internal pure returns (uint8) {
        if (c >= 48 && c <= 57) return c - 48; // 0-9
        if (c >= 97 && c <= 102) return c - 87; // a-f
        if (c >= 65 && c <= 70) return c - 55; // A-F
        revert InvalidHexString();
    }
}
