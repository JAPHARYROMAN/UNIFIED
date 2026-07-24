# Phase 3 Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

These layouts were inspected with `forge inspect <contract> storage-layout`. Immutable
constructor configuration is embedded in bytecode and does not consume storage slots.

| Contract | Slot | Stored value |
|---|---:|---|
| `TenderRegistry` | 0 | tender ID to tender record mapping |
| `OfferManager` | 0–1 | inherited EIP-712 fallback name and version |
|  | 2 | offer ID to immutable offer record mapping |
|  | 3 | lender and nonce consumption mapping |
|  | 4 | lender minimum valid nonce mapping |
| `FundingManager` | 0 | loan ID to finalized funding record mapping |
| `CoreLoanAccount` | 0–14 | accepted universal loan terms snapshot |
|  | 15 | packed loan state vector |
|  | 16 | lender |
|  | 17 | settlement token |
|  | 18 | originating factory |
|  | 19 | canonical loan registry |
|  | 20 | outstanding principal |
|  | 21 | processed payment ID mapping |
|  | 22 | one-time initialization flag |
| `CoreLoanFactory` | — | no persistent slots; all dependencies are immutable |

## Compatibility policy

Phase 3 contracts are non-upgradeable. Every loan is a deterministic clone of the
reviewed `CoreLoanAccount` implementation and cannot change implementation in place.
Version 2 storage is therefore frozen. A future account version must use a distinct
implementation version and explicit migration or coexistence analysis; it must never
reinterpret an active version-2 clone's storage.

Any ABI or storage change requires regenerated snapshots, compatibility analysis,
security review, and updated deployment evidence.
