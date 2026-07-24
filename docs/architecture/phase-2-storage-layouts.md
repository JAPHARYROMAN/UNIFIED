# Phase 2 Storage Layouts

Compiler: Solidity `0.8.36`
Foundry: `1.7.1`
OpenZeppelin Contracts: `5.6.1`
Optimizer: enabled, 200 runs

These layouts were inspected with `forge inspect <contract> storage-layout`. Immutable
values are embedded in bytecode and therefore do not consume storage slots.

| Contract | Slot | Stored value |
|---|---:|---|
| `RoleManager` | 0 | role/account expiry mapping |
|  | 1 | role-to-admin-role mapping |
| `EmergencyController` | 0 | action ID to emergency action mapping |
| `AssetRegistry` | 0 | asset ID to immutable identity and activation record |
| `PolicyRegistry` | 0 | semantic-version key to policy record |
|  | 1 | implementation to code hash |
|  | 2 | semantic-version key to activation timestamp |
| `LoanRegistry` | 0 | loan ID to append-only loan record |
| `LoanFactory` | 0 | implementation version to implementation |
| `VersionedLoanAccount` | 0 | loan ID |
|  | 1 | borrower |
|  | 2 | agreement hash |
|  | 3 | protocol version at offset 0; factory at offset 4; initialized flag at offset 24 |
| `UnifiedToken` | 0 | ERC-20 balances |
|  | 1 | ERC-20 allowances |
|  | 2 | total supply |
|  | 3–4 | name and symbol |
|  | 5–6 | EIP-712 name and version fallback |
|  | 7 | permit nonces |
| `AllocationVault` | 0 | bound token |
|  | 1 | cumulative released amount |
| `VestingPoolVault` | 0 | bound token |
|  | 1 | committed grant amount |
|  | 2 | grant records |
| `UFTBurner` | 0 | cumulative burned amount |
| `ProtocolFeeRouter` | 0 | packed six-field revenue split |
|  | 1 | burn-suspension flags |
|  | 2 | distribution nonce |
|  | 3 | undistributed amount by asset ID |

## Compatibility policy

No Phase 2 contract uses an upgradeable proxy. A changed implementation must be
registered under a new version and must not mutate an existing registry identity.

`VersionedLoanAccount` is cloned and initialized, so its version-1 slot ordering is
frozen. Any later implementation that reads version-1 state must retain slots 0–3
exactly and append new storage only after slot 3. A storage-layout change requires an
ADR, a compatibility test, and review of active-loan migration behavior.

The UFT token is non-upgradeable. Its inherited OpenZeppelin storage layout is pinned by
the exact package and compiler versions above.
