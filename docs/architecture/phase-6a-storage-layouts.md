# Phase 6A Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

The layouts were captured with `forge inspect <contract> storage-layout`. Role manager
and registry dependencies are immutable constructor values and consume no linear slots.

| Contract | Slot | Stored value |
|---|---:|---|
| `IdentityProviderRegistry` | 0 | provider record mapping |
|  | 1 | append-only provider IDs |
|  | 2 | credential-schema mapping |
|  | 3 | append-only schema IDs |
| `CredentialRegistry` | 0 | credential record mapping |
|  | 1 | append-only credential IDs |
| `CreditDecisionRegistry` | 0 | decision record mapping |
|  | 1 | append-only decision IDs |
|  | 2 | current decision by subject commitment, asset, and product |
| `ExposureManager` | 0 | loan ID to reservation mapping |
|  | 1 | append-only reservation loan IDs |
|  | 2 | subject commitment and asset to reserved/active totals |

All contracts are non-upgradeable. A semantic or layout change requires a new deployment
and explicit integration version; stored credential, decision, and exposure history
cannot be replaced in place.
