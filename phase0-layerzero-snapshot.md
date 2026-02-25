# Phase 0 Snapshot - LayerZero Baseline

Timestamp (UTC): `2026-02-24T00:08:35Z`

## Status
- Repo baseline snapshot: ✅ Completed
- On-chain readback snapshot: ⚠ Blocked in this runtime

Reason blocker:
1. `cast` panic bug (`Attempted to create a NULL object` from `system-configuration` crate).
2. Direct RPC `curl` call failed with host resolution in this runtime.

Impact:
- Baseline address/config dari dokumen chain tersedia.
- Verifikasi live on-chain harus dijalankan dari mesin lokal kamu (command disediakan di bawah).

## Baseline Addresses (from chain docs)

## Base
Source: `pay-chain.evm.smartcontract/CHAIN_BASE.md`
- Router: `0x1d7550079DAe36f55F4999E0B24AC037D092249C`
- Gateway: `0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D`
- Vault: `0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7`
- LayerZeroSenderAdapter: `0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478`
- LayerZeroReceiverAdapter: `0x4864138d5Dc8a5bcFd4228D7F784D1F32859986f`

## Polygon
Source: `pay-chain.evm.smartcontract/CHAIN_POLYGON.md`
- Router: `0xb4a911eC34eDaaEFC393c52bbD926790B9219df4`
- Gateway: `0x7a4f3b606D90e72555A36cB370531638fad19Bf8`
- Vault: `0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c`
- LayerZeroSenderAdapter: `0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e`
- LayerZeroReceiverAdapter: `0x67AAc121bc447F112389921A8B94c3D6FCBd98f9`

## Arbitrum
Source: `pay-chain.evm.smartcontract/CHAIN_ARBITRUM.md`
- Router: `0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e`
- Gateway: `0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8`
- Vault: `0x12306CA381813595BeE3c64b19318419C9E12f02`
- LayerZeroSenderAdapter: `0x263a3a83755613c50Dc42329D9B7771d91D8c1c1`
- LayerZeroReceiverAdapter: `0x7A356d451157F2AE128AD6Bd21Aa77605fAae09c`

## Required On-Chain Readback (run locally)

## Base (dest Polygon)
```bash
cast call 0x1d7550079DAe36f55F4999E0B24AC037D092249C \
"getAdapter(string,uint8)(address)" "eip155:137" 2 --rpc-url "$BASE_RPC_URL"

cast call 0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478 \
"dstEids(string)(uint32)" "eip155:137" --rpc-url "$BASE_RPC_URL"

cast call 0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478 \
"peers(string)(bytes32)" "eip155:137" --rpc-url "$BASE_RPC_URL"

cast call 0xD37f7315ea96eD6b3539dFc4bc87368D9F2b7478 \
"isRouteConfigured(string)(bool)" "eip155:137" --rpc-url "$BASE_RPC_URL"
```

## Polygon (dest Base)
```bash
cast call 0xb4a911eC34eDaaEFC393c52bbD926790B9219df4 \
"getAdapter(string,uint8)(address)" "eip155:8453" 2 --rpc-url "$POLYGON_RPC_URL"

cast call 0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e \
"dstEids(string)(uint32)" "eip155:8453" --rpc-url "$POLYGON_RPC_URL"

cast call 0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e \
"peers(string)(bytes32)" "eip155:8453" --rpc-url "$POLYGON_RPC_URL"

cast call 0xCC37C9AF29E58a17AE1191159B4BA67f56D1Bd1e \
"isRouteConfigured(string)(bool)" "eip155:8453" --rpc-url "$POLYGON_RPC_URL"
```

## Arbitrum (dest Base)
```bash
cast call 0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e \
"getAdapter(string,uint8)(address)" "eip155:8453" 2 --rpc-url "$ARBITRUM_RPC_URL"

cast call 0x263a3a83755613c50Dc42329D9B7771d91D8c1c1 \
"dstEids(string)(uint32)" "eip155:8453" --rpc-url "$ARBITRUM_RPC_URL"

cast call 0x263a3a83755613c50Dc42329D9B7771d91D8c1c1 \
"peers(string)(bytes32)" "eip155:8453" --rpc-url "$ARBITRUM_RPC_URL"

cast call 0x263a3a83755613c50Dc42329D9B7771d91D8c1c1 \
"isRouteConfigured(string)(bool)" "eip155:8453" --rpc-url "$ARBITRUM_RPC_URL"
```

## Receiver Peer Check (after obtaining srcEid)
Gunakan `srcEid` dari route sender chain lawan.

Contoh:
```bash
cast call <RECEIVER_ADDR> "peers(uint32)(bytes32)" <SRC_EID> --rpc-url <RPC_URL>
```

## Phase 0 Completion Criteria
- Semua command readback di atas mengembalikan nilai non-empty dan konsisten dengan route yang diharapkan.
- Snapshot output disimpan (copy-paste) ke dokumen ini atau lampiran terpisah.

