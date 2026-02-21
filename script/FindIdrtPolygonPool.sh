#!/bin/bash
rpc_url="https://polygon-mainnet.g.alchemy.com/v2/K9PzwLloeXxcOuFEx_fgR"
factory="0x1F98431c8aD98523631AE4a59f267346ea31F984"

usdc="0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359"
idrt="0x554cd6bdD03214b10AafA3e0D4D42De0C5D2937b"

echo "=== USDC / IDRT ==="
for fee in 100 500 3000 10000; do
    echo "Fee $fee:"
    cast call $factory "getPool(address,address,uint24)(address)" $usdc $idrt $fee --rpc-url $rpc_url
done
