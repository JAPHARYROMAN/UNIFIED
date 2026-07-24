# Phase 4A Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

`InterestEngine` and `ScheduleEngine` are stateless. Their configuration is passed in
calldata and included in the caller's immutable policy evidence.

| Contract | Slot | Stored value |
|---|---:|---|
| `OracleRouter` | 0 | pair configuration mapping |
|  | 1 | pair source arrays |
|  | 2 | latest canonical observation mapping |
|  | 3 | pair circuit-breaker mapping |
|  | 4 | asset circuit-breaker mapping |
|  | 5 | canonical quote asset mapping |
| `ServicingEngine` | 0 | loan ID to servicing record mapping |

All Phase 4A contracts are non-upgradeable. Any semantic change requires a new
implementation and policy version. A future caller must retain the exact rounding and
timestamp conventions or explicitly version its results as incompatible.
