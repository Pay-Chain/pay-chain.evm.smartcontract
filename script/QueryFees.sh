#!/bin/bash
source .env

echo "=== USDC / cbBTC ==="
cast call 0xfBB6Eed8e7aa03B138556eeDaF5D271A5E1e43ef "fee()(uint24)" --rpc-url $BASE_RPC_URL

echo "=== USDC / WETH ==="
cast call 0xb4CB800910B228ED3d0834cF79D697127BBB00e5 "fee()(uint24)" --rpc-url $BASE_RPC_URL

echo "=== cbBTC / WBTC ==="
cast call 0xd960B78f53e8A346c577F2C7b3f0a2394E73afb9 "fee()(uint24)" --rpc-url $BASE_RPC_URL
