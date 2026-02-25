#!/usr/bin/env bash
set -euo pipefail

# Verify latest rotated LayerZero adapters on Base.
# Usage:
#   BASESCAN_API_KEY=... BASE_RPC_URL=... ./script/VerifyLayerZeroBase.sh
#
# Optional overrides:
#   LZ_SENDER_ADDR=0x...
#   LZ_RECEIVER_ADDR=0x...
#   LZ_ENDPOINT=0x...
#   BASE_ROUTER_ADDR=0x...
#   BASE_GATEWAY_ADDR=0x...
#   BASE_VAULT_ADDR=0x...

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${BASESCAN_API_KEY:?Missing BASESCAN_API_KEY}"

LZ_SENDER_ADDR="${LZ_SENDER_ADDR:-0x54A139b53eA67Aa59a60Adc353B4C6fC3a00b3D6}"
LZ_RECEIVER_ADDR="${LZ_RECEIVER_ADDR:-0xDa17664D9cdD9524D8c1583a84325FBB5a1cFDA8}"

LZ_ENDPOINT="${LZ_ENDPOINT:-0x1a44076050125825900e736c501f859c50fE728c}"
BASE_ROUTER_ADDR="${BASE_ROUTER_ADDR:-0x1d7550079DAe36f55F4999E0B24AC037D092249C}"
BASE_GATEWAY_ADDR="${BASE_GATEWAY_ADDR:-0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D}"
BASE_VAULT_ADDR="${BASE_VAULT_ADDR:-0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7}"

echo "Generating constructor args..."
SENDER_ARGS="$(cast abi-encode "constructor(address,address)" "$LZ_ENDPOINT" "$BASE_ROUTER_ADDR")"
RECEIVER_ARGS="$(cast abi-encode "constructor(address,address,address)" "$LZ_ENDPOINT" "$BASE_GATEWAY_ADDR" "$BASE_VAULT_ADDR")"

# forge verify-contract expects hex without 0x prefix
SENDER_ARGS="${SENDER_ARGS#0x}"
RECEIVER_ARGS="${RECEIVER_ARGS#0x}"

echo "Sender:   $LZ_SENDER_ADDR"
echo "Receiver: $LZ_RECEIVER_ADDR"

echo ""
echo "Submitting sender verification..."
set +e
forge verify-contract \
  --chain base \
  --watch \
  --etherscan-api-key "$BASESCAN_API_KEY" \
  "$LZ_SENDER_ADDR" \
  src/integrations/layerzero/LayerZeroSenderAdapter.sol:LayerZeroSenderAdapter \
  --constructor-args "$SENDER_ARGS"
SENDER_RC=$?
set -e

echo ""
echo "Submitting receiver verification..."
set +e
forge verify-contract \
  --chain base \
  --watch \
  --etherscan-api-key "$BASESCAN_API_KEY" \
  "$LZ_RECEIVER_ADDR" \
  src/integrations/layerzero/LayerZeroReceiverAdapter.sol:LayerZeroReceiverAdapter \
  --constructor-args "$RECEIVER_ARGS"
RECEIVER_RC=$?
set -e

if [[ $SENDER_RC -eq 0 && $RECEIVER_RC -eq 0 ]]; then
  echo ""
  echo "Verification succeeded for both contracts."
  exit 0
fi

echo ""
echo "forge verify failed for at least one contract."
echo "If forge crashes on this machine, use BaseScan UI with these args:"
echo ""
echo "Sender contract:"
echo "  Address: $LZ_SENDER_ADDR"
echo "  Contract: src/integrations/layerzero/LayerZeroSenderAdapter.sol:LayerZeroSenderAdapter"
echo "  Constructor args (no 0x): $SENDER_ARGS"
echo ""
echo "Receiver contract:"
echo "  Address: $LZ_RECEIVER_ADDR"
echo "  Contract: src/integrations/layerzero/LayerZeroReceiverAdapter.sol:LayerZeroReceiverAdapter"
echo "  Constructor args (no 0x): $RECEIVER_ARGS"
echo ""
echo "BaseScan links:"
echo "  https://basescan.org/address/$LZ_SENDER_ADDR#code"
echo "  https://basescan.org/address/$LZ_RECEIVER_ADDR#code"
exit 1
