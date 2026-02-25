# Phase 0 - CCIP Baseline Snapshot

Date: 2026-02-25
Owner: Smart Contract Track
Status: Completed

## Objective

Freeze and snapshot the current CCIP state before code patching so post-fix regression can be measured deterministically.

## Sources of Truth Used

1. `pay-chain.evm.smartcontract/CHAIN_BASE.md`
2. `pay-chain.evm.smartcontract/CHAIN_POLYGON.md`
3. `pay-chain.evm.smartcontract/CHAIN_ARBITRUM.md`
4. `pay-chain.evm.smartcontract/.env`
5. `pay-chain.evm.smartcontract/script/DeployCommon.s.sol`
6. `pay-chain.evm.smartcontract/script/ConfigureRoutes.s.sol`

## Current Deployment Inventory (from CHAIN_*.md)

### Base (8453)

- Router: `0x1d7550079DAe36f55F4999E0B24AC037D092249C`
- Gateway: `0xC696dCAC9369fD26AB37d116C54cC2f19B156e4D`
- Vault: `0xe3Be18b812b0645674cCa81f24dC5f7bD62911b7`
- CCIPSender: `0xc60b6f567562c756bE5E29f31318bb7793852850`
- CCIPReceiver: `0x95C8aF513D4a898B125A3EE4a34979ef127Ef1c1`
- CCIP Router (from env): `0x881e3A65B4d4a04dD529061dd0071cf975F58bCD`

### Polygon (137)

- Router: `0xb4a911eC34eDaaEFC393c52bbD926790B9219df4`
- Gateway: `0x7a4f3b606D90e72555A36cB370531638fad19Bf8`
- Vault: `0x6CFc15C526B8d06e7D192C18B5A2C5e3E10F7D8c`
- CCIPSender: `0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500`
- CCIPReceiver: `0xbC75055BdF937353721BFBa9Dd1DCCFD0c70B8dd`
- CCIP Router (from env): `0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe`

### Arbitrum (42161)

- Router: `0x5CF8c2EC1e96e6a5b17146b2BeF67d1012deEF7e`
- Gateway: `0x5a1179675aaE10D8E4B74d5Ff87152016f28F0D8`
- Vault: `0x12306CA381813595BeE3c64b19318419C9E12f02`
- CCIPSender: `0xC9126fACB9201d79EF860F7f4EF2037c69D80a56`
- CCIPReceiver: `0x0Fad39d945785b3d35B7C8a7aa856431c42B75f5`
- CCIP Router (from env): `0x141fa059441E0ca23ce184B6A78bafD2A517DdE8`

### BSC (56)

- CCIP Router (from env): `0x34B03Cb9086d7D758AC55af71584F81A598759FE`
- Chain deployment metadata file is not present in repo (`CHAIN_BSC.md` missing).
- Action item: create BSC deployment snapshot after route validation pass.

## Risk Snapshot (Pre-Patch)

1. Critical: `CCIPSender.sendMessage` has no caller guard.
2. High: receiver trust bootstrap is not automated in common deploy.
3. High: chain-specific deploy scripts do not pass `RouteBootstrapConfig`.
4. Medium: fee execution has no runtime re-quote guard/refund strategy.
5. Medium: route `extraArgs` not configurable per destination.
6. Medium: no explicit `isChainSupported` pre-check in sender.
7. Medium: receiver has no fail-safe message ledger/manual retry path.
8. Low: destination adapter bytes format can be operator-error prone.

## Freeze Checklist (Phase 0 Gate)

- [x] Record active CCIP sender/receiver/router/gateway/vault addresses per chain.
- [x] Record configured CCIP router address per chain from env.
- [x] Record known pre-patch risks and prioritize remediation.
- [ ] Freeze admin write for CCIP config during migration window.
- [ ] Export on-chain route matrix for all chain pairs.
- [ ] Export receiver trust matrix (`allowedSourceChains`, `trustedSenders`) for all active receivers.

## Route Matrix Export Commands (to be executed before Phase 1 broadcast)

Run per source chain:

```bash
cast call <ROUTER> "getAdapter(string,uint8)(address)" "<DEST_CAIP2>" 1 --rpc-url "$RPC_URL"
cast call <SENDER> "getChainConfig(string)(uint64,address)" "<DEST_CAIP2>" --rpc-url "$RPC_URL"
cast call <SENDER> "destinationGasLimits(string)(uint256)" "<DEST_CAIP2>" --rpc-url "$RPC_URL"
```

Run per destination chain:

```bash
cast call <RECEIVER> "allowedSourceChains(uint64)(bool)" <SRC_SELECTOR> --rpc-url "$RPC_URL"
cast call <RECEIVER> "trustedSenders(uint64)(bytes)" <SRC_SELECTOR> --rpc-url "$RPC_URL"
```

## Exit Criteria for Phase 0

1. Baseline address snapshot complete for all target chains.
2. Route/trust export command set documented.
3. Pre-patch risk register documented and agreed.

