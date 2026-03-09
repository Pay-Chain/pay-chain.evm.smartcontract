// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../src/PaymentKitaGateway.sol";
import "../src/PaymentKitaRouter.sol";
import "../src/TokenRegistry.sol";
import "../src/vaults/PaymentKitaVault.sol";
import "../src/integrations/ccip/CCIPSender.sol";
import "../src/integrations/ccip/CCIPReceiver.sol";
import "../src/integrations/ccip/CCIPReceiverBase.sol";
import "../src/integrations/hyperbridge/HyperbridgeSender.sol";
import "../src/integrations/hyperbridge/HyperbridgeReceiver.sol";
import "../src/integrations/layerzero/LayerZeroSenderAdapter.sol";
import "../src/gateway/fee/strategies/FeeStrategyDefaultV1.sol";
import "../src/integrations/ccip/Client.sol";

contract MockERC20Decimals is ERC20 {
    uint8 private immutable _decimalsValue;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimalsValue = decimals_;
        _mint(msg.sender, 1_000_000_000 * 10 ** uint256(decimals_));
    }

    function decimals() public view override returns (uint8) {
        return _decimalsValue;
    }
}

contract MutableConfigHardeningTest is Test {
    PaymentKitaVault internal vault;
    PaymentKitaRouter internal router;
    TokenRegistry internal registry;
    PaymentKitaGateway internal gateway;

    CCIPSender internal ccipSender;
    CCIPReceiverAdapter internal ccipReceiver;
    HyperbridgeSender internal hyperSender;
    HyperbridgeReceiver internal hyperReceiver;
    LayerZeroSenderAdapter internal lzSender;
    FeeStrategyDefaultV1 internal feeStrategy;

    address internal owner = address(this);
    address internal attacker = address(0xBEEF);
    address internal ccipRouterA = address(0xCA11);
    address internal ccipRouterB = address(0xCA12);
    address internal hbHostA = address(0xB100);
    address internal hbHostB = address(0xB101);
    address internal lzEndpoint = address(0xE001);
    address internal lzRouterA = address(0xE010);
    address internal lzRouterB = address(0xE011);

    function setUp() public {
        vault = new PaymentKitaVault();
        router = new PaymentKitaRouter();
        registry = new TokenRegistry();
        gateway = new PaymentKitaGateway(address(vault), address(router), address(registry), owner);

        ccipSender = new CCIPSender(address(vault), ccipRouterA);
        ccipReceiver = new CCIPReceiverAdapter(ccipRouterA, address(gateway));
        hyperSender = new HyperbridgeSender(address(vault), hbHostA, address(gateway), owner);
        hyperReceiver = new HyperbridgeReceiver(hbHostA, address(gateway), address(vault));
        lzSender = new LayerZeroSenderAdapter(lzEndpoint, lzRouterA);
        feeStrategy = new FeeStrategyDefaultV1(address(registry));
    }

    function testBrutal_RewireLoops_AllMutableSetters() public {
        for (uint256 i = 1; i <= 20; i++) {
            address newAddrA = vm.addr(0x100000 + i);
            address newAddrB = vm.addr(0x200000 + i);

            gateway.setTokenRegistry(newAddrA);
            gateway.setFeeRecipient(newAddrB);

            ccipSender.setVault(newAddrA);
            ccipSender.setRouter(newAddrB);

            ccipReceiver.setGateway(address(gateway));
            ccipReceiver.setVault(address(vault));
            ccipReceiver.setRouter(newAddrA);

            hyperSender.setGateway(address(gateway));
            hyperSender.setVault(address(vault));
            hyperSender.setRouter(newAddrA);
            hyperSender.setHost(newAddrB);

            hyperReceiver.setGateway(address(gateway));
            hyperReceiver.setVault(address(vault));
            hyperReceiver.setHost(newAddrA);

            lzSender.setRouter(newAddrB);

            feeStrategy.setTokenRegistry(newAddrA);
        }
    }

    function testBrutal_NonOwnerBlocked_AllCriticalSetters() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        gateway.setTokenRegistry(address(1));
        vm.expectRevert();
        gateway.setFeeRecipient(address(1));

        vm.expectRevert();
        ccipSender.setVault(address(1));
        vm.expectRevert();
        ccipSender.setRouter(address(1));

        vm.expectRevert();
        ccipReceiver.setGateway(address(1));
        vm.expectRevert();
        ccipReceiver.setVault(address(1));
        vm.expectRevert();
        ccipReceiver.setRouter(address(1));

        vm.expectRevert();
        hyperSender.setGateway(address(1));
        vm.expectRevert();
        hyperSender.setVault(address(1));
        vm.expectRevert();
        hyperSender.setRouter(address(1));
        vm.expectRevert();
        hyperSender.setHost(address(1));

        vm.expectRevert();
        hyperReceiver.setGateway(address(1));
        vm.expectRevert();
        hyperReceiver.setVault(address(1));
        vm.expectRevert();
        hyperReceiver.setHost(address(1));

        vm.expectRevert();
        lzSender.setRouter(address(1));

        vm.expectRevert();
        feeStrategy.setTokenRegistry(address(1));

        vm.stopPrank();
    }

    function testBrutal_CcipReceiverRouterGateSwitch() public {
        Client.Any2EVMMessage memory msgData;
        msgData.sourceChainSelector = 777;

        vm.prank(ccipRouterA);
        vm.expectRevert();
        ccipReceiver.ccipReceive(msgData);

        ccipReceiver.setRouter(ccipRouterB);

        vm.prank(ccipRouterA);
        vm.expectRevert(abi.encodeWithSelector(CCIPReceiverBase.InvalidRouter.selector, ccipRouterA));
        ccipReceiver.ccipReceive(msgData);

        vm.prank(ccipRouterB);
        vm.expectRevert();
        ccipReceiver.ccipReceive(msgData);
    }

    function testBrutal_HyperSenderRouterGateSwitch() public {
        IBridgeAdapter.BridgeMessage memory bridgeMsg = IBridgeAdapter.BridgeMessage({
            paymentId: bytes32(uint256(1)),
            receiver: address(0x1234),
            sourceToken: address(0),
            destToken: address(0),
            amount: 100,
            destChainId: "eip155:137",
            minAmountOut: 0,
            payer: owner
        });

        address newRouter = address(0x9999);
        hyperSender.setRouter(newRouter);
        assertEq(hyperSender.router(), newRouter);

        vm.expectRevert(HyperbridgeSender.NotRouter.selector);
        hyperSender.sendMessage{value: 1}(bridgeMsg);
    }

    function testBrutal_LayerZeroSenderRouterGateSwitch() public {
        assertEq(lzSender.router(), lzRouterA);
        lzSender.setRouter(lzRouterB);
        assertEq(lzSender.router(), lzRouterB);
    }

    function testBrutal_FeeStrategyRegistryRewireChangesFeeScale() public {
        MockERC20Decimals token = new MockERC20Decimals("IDRX", "IDRX", 2);

        TokenRegistry reg6 = new TokenRegistry();
        reg6.setTokenSupport(address(token), true);
        reg6.setTokenDecimals(address(token), 6);

        TokenRegistry reg18 = new TokenRegistry();
        reg18.setTokenSupport(address(token), true);
        reg18.setTokenDecimals(address(token), 18);

        FeeStrategyDefaultV1 strat = new FeeStrategyDefaultV1(address(reg6));

        uint256 amount = 100_000;
        uint256 feeAt6 = strat.computePlatformFee("", "", address(token), address(0), amount, 0, 0);
        strat.setTokenRegistry(address(reg18));
        uint256 feeAt18 = strat.computePlatformFee("", "", address(token), address(0), amount, 0, 0);

        assertEq(strat.tokenRegistry(), address(reg18));
        assertGt(feeAt6, 0);
        assertGt(feeAt18, 0);
    }
}
