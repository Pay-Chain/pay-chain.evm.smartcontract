# DEPLOYMENT CONTRACT
TokenRegistry deployed at: 0xf0A630cd20a1DcaE5f5cBd8876cC2c6cd97afC4d
PaymentKitaVault deployed at: 0x64505bE2844D35284AB58984F93DCEb21BC77464
PaymentKitaRouter deployed at: 0xcb33c2a8A63878e2BF95e10DF753175664936Ddd
PaymentKitaGateway deployed at: 0x0C6C2cC9C2Fb42D2fe591F2C3fee4Db428090ad4
TokenSwapper deployed at: 0xf8D442eFE750Cd41A8d5FCf72209ad456ED1F6c4

Gateway modules wired:
- validator: 0x6f575668D4d00d83f4Aca0568C1C1eF0064d7F81
- quote: 0x1dC8acE2223970f1eD82FC583424574706112213
- execution: 0xf65Fd2370f0b4e80D33cb11dAF30bbdb34267122
- privacy: 0x8E6fF79646DF81eea1bF40B0Ab3c231F870b5459
FeePolicyManager: 0x4e1518E4F87eC11aD7792195f1d2a07CB78aa8E8
Default fee strategy: 0x725a5a3876BaBc892c8D5CEc626540A39c2820A3

CCIPSender deployed at: 0xc95b302BB6B0256a81258de80217c5A7f31dD0B9
CCIPSender authorized caller (router): 0xcb33c2a8A63878e2BF95e10DF753175664936Ddd
CCIPReceiverAdapter deployed at: 0x6f1768AF38198232AcA0224152188A3E05F7C38C
HyperbridgeSender deployed at: 0xf251A2C63185Bf5888D923307fFa8f4DFbAA1D45
HyperbridgeReceiver deployed at: 0x185A66d0937a5754247add09944F2a9ddB1a0e3E
LayerZeroSenderAdapter deployed at: 0x9B31E988dAf6Fe6aba328D2238AA6d0765E59096
LayerZeroReceiverAdapter deployed at: 0x6a14d91108Ca4bbFC46fCbB7A66412d16d15A0e9

# AUTHORIZED ROUTE PATH
Registered bridge token as supported: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Configured IDRX/USDC V3 pool
Configured USDC/WETH V3 pool
Configured USDC/cbBTC V3 pool
Configured USDC/USDe V3 pool
Configured USDC -> cbBTC -> WBTC
Configured USDC -> WETH -> cbETH
Configured WBTC -> cbBTC -> USDC -> IDRX
Configured cbETH -> WETH -> USDC -> IDRX
Configured IDRX -> USDC -> WETH
Configured IDRX -> USDC -> USDe

# CCIP ROUTE STATUS (Base -> Polygon)
Route CAIP2: eip155:137
Bridge type: 1 (CCIP)
Sender chainSelector: 4051577828743386545
Sender destinationAdapter (Polygon receiver): 0xbC75055BdF937353721BFBa9Dd1DCCFD0c70B8dd
Receiver sourceSelector trusted sender (Polygon sender): 0xdf6c1dFEf6A16315F6Be460114fB090Aea4dE500
Gateway default bridge for eip155:137: 1 (CCIP)
Validation: ccip-rotate-verify passed (deploy + rewire + verify)

# LAYERZERO ROUTE STATUS (Base -> Polygon)
Route CAIP2: eip155:137
Bridge type: 2 (LayerZero)
Sender dstEid: 30109
Sender dstPeer: 0x00000000000000000000000067aac121bc447f112389921a8b94c3d6fcbd98f9
Receiver srcEid: 30109
Receiver srcPeer: 0x000000000000000000000000cc37c9af29e58a17ae1191159b4ba67f56d1bd1e
Validation: lz-validate-dry passed (adapter exists, route configured, receiver trusted, fee quote ok)

# AUTHORIZED TOKEN
Registered bridge token as supported: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Registered BASE_USDE: 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34
Registered BASE_WETH: 0x4200000000000000000000000000000000000006
Registered BASE_CBETH: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22
Registered BASE_CBBTC: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
Registered BASE_WBTC: 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c
Registered BASE_IDRX: 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22
