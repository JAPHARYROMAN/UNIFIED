# Phase 4B1 Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

Optimizer: enabled, 200 runs

| Contract | Slot | Stored value |
|---|---:|---|
| `CollateralVault` | 0 | collateral ID to item mapping |
|  | 1 | asset ID to controlled quantity |
|  | 2 | expected NFT callback hash |
| `CollateralManager` | 0 | liquidation engine |
|  | 1 | UFT-backed debt ceiling |
|  | 2 | aggregate UFT-backed debt |
|  | 3 | loan UFT-backed debt mapping |
|  | 4 | collateral asset configuration mapping |
|  | 5 | loan vault mapping |
|  | 6 | collateral ID to loan mapping |
|  | 7 | loan collateral-ID arrays |
|  | 8 | loan/asset exposure mapping |
|  | 9 | borrower/asset exposure mapping |

Immutable loan, manager, registry, and UFT references are embedded in bytecode.
Vaults and the manager are non-upgradeable. A future custody implementation must use
new vault identities and explicit handoff conservation rather than reinterpret these
slots.
