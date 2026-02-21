#!/bin/bash
export IDRX=0x5Fa92501106d7E4e8b4eF3c4d08112b6f306194C
export USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
export WETH=0x4200000000000000000000000000000000000006
export FACTORY=0x33128a8fC17869897dcE68Ed026d694621f6FDfD
# Source .env for RPC URL
source .env

echo "=== IDRX / USDC ==="
echo "Fee 100:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $USDC 100 --rpc-url $BASE_RPC_URL
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $USDC 500 --rpc-url $BASE_RPC_URL
echo "Fee 3000:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $USDC 3000 --rpc-url $BASE_RPC_URL
echo "Fee 10000:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $USDC 10000 --rpc-url $BASE_RPC_URL

echo "=== IDRX / WETH ==="
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $WETH 500 --rpc-url $BASE_RPC_URL
echo "Fee 3000:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $IDRX $WETH 3000 --rpc-url $BASE_RPC_URL

echo "=== WETH / USDC ==="
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $WETH $USDC 500 --rpc-url $BASE_RPC_URL
