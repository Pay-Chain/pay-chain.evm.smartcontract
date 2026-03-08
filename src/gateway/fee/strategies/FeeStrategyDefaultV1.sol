// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../interfaces/IFeeStrategy.sol";
import "../../../libraries/FeeCalculator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20MetadataStrategy {
    function decimals() external view returns (uint8);
}

interface ITokenRegistryDecimals {
    function tokenDecimals(address token) external view returns (uint8);
}

contract FeeStrategyDefaultV1 is IFeeStrategy, Ownable {
    uint256 public constant FIXED_BASE_FEE = 0.50e6;
    uint256 public constant FEE_RATE_BPS = 30;

    address public tokenRegistry;
    event TokenRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    constructor(address registry) Ownable(msg.sender) {
        tokenRegistry = registry;
    }

    function setTokenRegistry(address registry) external onlyOwner {
        emit TokenRegistryUpdated(tokenRegistry, registry);
        tokenRegistry = registry;
    }

    function computePlatformFee(
        bytes calldata,
        bytes calldata,
        address sourceToken,
        address,
        uint256 sourceAmount,
        uint256,
        uint256
    ) external view override returns (uint256 platformFee) {
        uint8 decimals = _resolveDecimals(sourceToken);
        uint256 scaledBaseFee = FeeCalculator.scaleFeeByDecimals(FIXED_BASE_FEE, decimals);
        platformFee = FeeCalculator.calculatePlatformFee(sourceAmount, scaledBaseFee, FEE_RATE_BPS);
    }

    function _resolveDecimals(address token) internal view returns (uint8) {
        if (tokenRegistry != address(0)) {
            uint8 regDec = ITokenRegistryDecimals(tokenRegistry).tokenDecimals(token);
            if (regDec > 0) return regDec;
        }
        try IERC20MetadataStrategy(token).decimals() returns (uint8 dec) {
            if (dec > 0) return dec;
        } catch {}
        return 6;
    }
}
