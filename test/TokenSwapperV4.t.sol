// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenSwapper.sol";
import "../src/interfaces/IUniswapV4.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ============ Mocks ============

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Interface for MockMintable
interface IMintable {
    function blockTransfer(address to, uint256 amount) external;
}

contract MockUniversalRouter {
    mapping(address => mapping(address => uint256)) public rates; // Rate in output token decimals (1e18 scale for simplicity)
    
    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        rates[tokenIn][tokenOut] = rate;
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256) external payable {
        // 0x10 = V4_SWAP
        if (commands[0] == 0x10) {
            (bytes memory actions, bytes[] memory actionParams) = abi.decode(inputs[0], (bytes, bytes[]));
            
            if (uint8(actions[0]) == 0x06) { // SWAP_EXACT_IN_SINGLE
                IV4Router.ExactInputSingleParams memory params = abi.decode(actionParams[0], (IV4Router.ExactInputSingleParams));
                _handleSwap(params.poolKey, params.zeroForOne, params.amountIn);
            } else if (uint8(actions[0]) == 0x07) { // SWAP_EXACT_IN (MultiHop)
                IV4Router.ExactInputParams memory params = abi.decode(actionParams[0], (IV4Router.ExactInputParams));
                _handleMultiHop(params);
            }
        }
    }

    function _handleSwap(PoolKey memory key, bool zeroForOne, uint256 amountIn) internal {
        address tokenIn = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        address tokenOut = zeroForOne ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
        
        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "MockRouter: No rate");
        
        uint256 amountOut = (amountIn * rate) / 1e18;
        
        // Router Logic: Pull In, Push Out
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "MockRouter transferFrom failed");
        IMintable(tokenOut).blockTransfer(msg.sender, amountOut); // Mock mint or transfer
    }

    function _handleMultiHop(IV4Router.ExactInputParams memory params) internal {
        address tokenIn = Currency.unwrap(params.currencyIn);
        // Simple mock: assume final output is implicit from stored rates A->C directly for test simplicity
        // or iterate paths. For unit test validation, direct A->Z rate is enough to verify plumbing working.
        
        address tokenOut = Currency.unwrap(params.path[params.path.length-1].intermediateCurrency);
        uint256 rate = rates[tokenIn][tokenOut];
        require(rate > 0, "MockRouter: No mh rate");

        uint256 amountOut = (params.amountIn * rate) / 1e18;
        
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn),
            "MockRouter mh transferFrom failed"
        );
        IMintable(tokenOut).blockTransfer(msg.sender, amountOut);
    }
}

// Extension to allow Router to mint output tokens (simulator)
contract MockMintableERC20 is MockERC20 {
    constructor(string memory n, string memory s) MockERC20(n, s) {}
    function blockTransfer(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ============ Test Suite ============

contract TokenSwapperV4Test is Test {
    TokenSwapper swapper;
    MockUniversalRouter router;
    MockMintableERC20 tokenA;
    MockMintableERC20 tokenB;
    MockMintableERC20 tokenC;

    address owner = address(this);
    address user = address(0x1);

    function setUp() public {
        router = new MockUniversalRouter();
        tokenA = new MockMintableERC20("Token A", "TKA");
        tokenB = new MockMintableERC20("Token B", "TKB");
        tokenC = new MockMintableERC20("Token C", "TKC");

        swapper = new TokenSwapper(address(router), address(0x2) /* PM */, address(tokenB) /* Bridge */);
        
        // Fund Router just in case, though it mints
        tokenA.mint(address(router), 10000e18);
        tokenB.mint(address(router), 10000e18);
        tokenC.mint(address(router), 10000e18);

        // Authorize test contract
        swapper.transferOwnership(owner);
    }

    // --- Admin Tests ---

    function test_Admin_SetDirectPool() public {
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        
        bytes32 key = keccak256(abi.encodePacked(
            address(tokenA) < address(tokenB) ? address(tokenA) : address(tokenB),
            address(tokenA) < address(tokenB) ? address(tokenB) : address(tokenA)
        ));
        
        (uint24 fee, , , bool active) = swapper.directPools(key);
        assertEq(fee, 3000);
        assertTrue(active);
    }

    function test_Admin_Revert_InvalidAddress() public {
        vm.expectRevert(TokenSwapper.InvalidAddress.selector);
        swapper.setDirectPool(address(0), address(tokenB), 3000, 60, address(0));
    }

    // --- Direct Swap Tests ---

    function test_Swap_Direct_Success() public {
        // Config
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        router.setRate(address(tokenA), address(tokenB), 1e18); // 1:1

        // Setup User
        tokenA.mint(user, 100e18);
        vm.startPrank(user);
        tokenA.approve(address(swapper), 100e18);
        
        // authorize user (Swapper requires authorization for callers usually, or we use swapFromVault if valid)
        // But 'swap' function has onlyAuthorized. Let's authorize user.
        vm.stopPrank();
        
        // Add user to authorized or use a pattern wrapper.
        // Actually TokenSwapper `swap` is `onlyAuthorized`. Default msg.sender is owner.
        // Let's test as owner (this contract) for simplicity or add user.
        // The contract defines `authorizedCallers`. "Owner is authorized by default"
        
        // User flow:
        // swapper.swap(tokenA, tokenB, 10e18, 9e18, user);
        // Requires user to be authorized.
        
        // Let's pretend this test contract is the Gateway calling swap
        tokenA.mint(address(this), 100e18);
        tokenA.approve(address(swapper), 100e18);
        
        uint256 balPre = tokenB.balanceOf(user);
        
        uint256 out = swapper.swap(address(tokenA), address(tokenB), 10e18, 9e18, user);
        
        assertEq(out, 10e18); // 1:1 rate
        assertEq(tokenB.balanceOf(user) - balPre, 10e18);
    }

    function test_Swap_Direct_SlippageRevert() public {
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        router.setRate(address(tokenA), address(tokenB), 0.5e18); // 1 -> 0.5 (Severe slippage)

        tokenA.mint(address(this), 100e18);
        tokenA.approve(address(swapper), 100e18);

        vm.expectRevert(TokenSwapper.SlippageExceeded.selector);
        swapper.swap(address(tokenA), address(tokenB), 10e18, 9e18, user); // Expect 9, get 5
    }

    function test_Swap_NoRoute() public {
        tokenA.mint(address(this), 100e18);
        tokenA.approve(address(swapper), 100e18);
        
        vm.expectRevert(TokenSwapper.NoRouteFound.selector);
        swapper.swap(address(tokenA), address(tokenB), 10e18, 0, user);
    }

    // --- Multi-Hop Tests ---

    function test_FindRoute_MultiHop() public {
        // A -> B -> C
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        swapper.setDirectPool(address(tokenB), address(tokenC), 3000, 60, address(0));
        // Bridge token is B (configured in constructor)
        
        (bool exists, bool isDirect, address[] memory path) = swapper.findRoute(address(tokenA), address(tokenC));
        
        assertTrue(exists, "Route should exist");
        assertFalse(isDirect, "Should be multi-hop");
        assertEq(path.length, 3);
        assertEq(path[0], address(tokenA));
        assertEq(path[1], address(tokenB));
        assertEq(path[2], address(tokenC));
    }

    function test_Swap_MultiHop_Success() public {
        // A -> B -> C
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        swapper.setDirectPool(address(tokenB), address(tokenC), 3000, 60, address(0));
        
        // A->C direct rate needed for Mock logic (simplified mock)
        router.setRate(address(tokenA), address(tokenC), 2e18); // 1 A -> 2 C
        
        tokenA.mint(address(this), 100e18);
        tokenA.approve(address(swapper), 100e18);
        
        uint256 balPre = tokenC.balanceOf(user);
        
        uint256 out = swapper.swap(address(tokenA), address(tokenC), 10e18, 0, user);
        
        assertEq(out, 20e18);
        assertEq(tokenC.balanceOf(user) - balPre, 20e18);
    }

    // --- Gas & Quote ---

    function test_GetQuote_RevertNoRoute() public {
        vm.expectRevert(TokenSwapper.NoRouteFound.selector);
        swapper.getQuote(address(tokenA), address(tokenC), 1e18);
    }

    function test_EstimateGas_Direct() public {
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        (uint256 gas, uint256 hops) = swapper.estimateSwapGas(address(tokenA), address(tokenB), 1e18);
        assertEq(gas, 150_000);
        assertEq(hops, 1);
    }

    function test_EstimateGas_MultiHop() public {
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        swapper.setDirectPool(address(tokenB), address(tokenC), 3000, 60, address(0));
        
        (uint256 gas, uint256 hops) = swapper.estimateSwapGas(address(tokenA), address(tokenC), 1e18);
        // 50000 + 2 * 120000 = 290000
        assertEq(gas, 290_000); 
        assertEq(hops, 2);
    }

    // --- Extreme / Fuzz Tests ---

    function testFuzz_Swap_Direct(uint128 amount) public {
        vm.assume(amount > 1000 && amount < 100000e18); // Reasonable range
        
        swapper.setDirectPool(address(tokenA), address(tokenB), 3000, 60, address(0));
        router.setRate(address(tokenA), address(tokenB), 1e18); 

        tokenA.mint(address(this), amount);
        tokenA.approve(address(swapper), amount);
        
        uint256 balPre = tokenB.balanceOf(user);
        uint256 minOut = (uint256(amount) * 90) / 100; // 10% slippage allowed
        
        uint256 out = swapper.swap(address(tokenA), address(tokenB), amount, minOut, user);
        
        assertEq(out, amount); // 1:1 rate
        assertEq(tokenB.balanceOf(user) - balPre, amount);
    }

    // Reentrancy Logic
    error ReentrancyGuardReentrantCall(); // Define custom error matching OZ

    function test_Reentrancy_Guard() public {
        MaliciousToken mal = new MaliciousToken(address(swapper));
        swapper.setDirectPool(address(mal), address(tokenB), 3000, 60, address(0));
        
        mal.mint(address(this), 100e18);
        mal.approve(address(swapper), 100e18);
        mal.enableAttack();

        vm.expectRevert(ReentrancyGuardReentrantCall.selector);
        swapper.swap(address(mal), address(tokenB), 10e18, 0, user);
    }
}

contract MaliciousToken is ERC20 {
    TokenSwapper swapper;
    bool public attack;
    
    constructor(address _s) ERC20("Malicious", "MAL") { 
        swapper = TokenSwapper(_s); 
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function enableAttack() external { attack = true; }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (attack) {
            attack = false; // Prevent infinite loop
            // Attempt to re-enter
            swapper.swap(address(this), address(0), 1, 0, address(0));
        }
        return super.transferFrom(from, to, amount);
    }
}
