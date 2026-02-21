#!/bin/bash
export USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
export USDT=0xc2132D05D31c914a87C6611C10748AEb04B58e8F
export WETH=0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
export DAI=0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063
export FACTORY=0x1F98431c8aD98523631AE4a59f267346ea31F984
export RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR

echo "=== USDC / USDT ==="
echo "Fee 100:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $USDT 100 --rpc-url $RPC_URL
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $USDT 500 --rpc-url $RPC_URL
echo "Fee 3000:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $USDT 3000 --rpc-url $RPC_URL

echo "=== USDC / WETH ==="
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $WETH 500 --rpc-url $RPC_URL
echo "Fee 3000:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $WETH 3000 --rpc-url $RPC_URL

echo "=== USDC / DAI ==="
echo "Fee 100:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $DAI 100 --rpc-url $RPC_URL
echo "Fee 500:"
cast call $FACTORY "getPool(address,address,uint24)(address)" $USDC $DAI 500 --rpc-url $RPC_URL
