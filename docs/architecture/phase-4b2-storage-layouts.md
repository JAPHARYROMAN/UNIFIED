# Phase 4B2 Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

All dependency addresses and the treasury are immutable constructor values.
OpenZeppelin's reentrancy guard uses its namespaced storage location.

| Contract | Slot | Stored value |
|---|---:|---|
| `LiquidationEngine` | 0 | liquidation ID to immutable plan and status mapping |
|  | 1 | liquidation ID to highest English bid mapping |
|  | 2 | liquidation ID to completed settlement mapping |
|  | 3 | collateral ID to active liquidation ID mapping |
|  | 4 | settlement token and account to refundable bid amount mapping |

The contract is non-upgradeable. A semantic change requires a new engine deployment and
an explicit governance decision; the Phase 4B1 manager permits only one binding, so a
replacement requires a versioned manager rather than an in-place storage mutation.
