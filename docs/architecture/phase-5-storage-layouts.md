# Phase 5 Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

These layouts were captured with `forge inspect <contract> storage-layout`. OpenZeppelin's
reentrancy guard uses namespaced storage and therefore does not consume a linear slot.

## PositionManager

| Slot | Stored value |
|---:|---|
| 0 | role manager |
| 1 | authorized vault |
| 2 | settlement token |
| 3 | loan ID |
| 4 | funding-activated flag |
| 5 | total issued shares |
| 6 | total outstanding principal |
| 7 | tranche mapping |
| 8 | ordered tranche IDs |
| 9 | position mapping |
| 10 | lifetime position IDs |
| 11 | position IDs by tranche |
| 12 | accrued distribution by position |
| 13 | withdrawable balance by owner |
| 14 | current votes by owner |
| 15 | vote checkpoints by owner |
| 16 | total-vote checkpoints |
| 17 | initialized flag |

## SyndicateVault

| Slot | Stored value |
|---:|---|
| 0 | factory |
| 1 | loan registry |
| 2 | position manager |
| 3 | settlement token |
| 4–15 | funding-round terms |
| 16–30 | universal loan terms |
| 31 | round status |
| 32 | total committed |
| 33 | outstanding principal |
| 34 | commitment mapping |
| 35 | lifetime commitment IDs |
| 36 | processed payment IDs |
| 37 | initialized flag |

## SyndicateFactory

The factory has no linear mutable storage. Its registries, emergency controller, and
clone implementation addresses are immutable constructor values. Inherited authority
and reentrancy state use immutable or namespaced storage.

All three contracts are non-upgradeable. A semantic or layout change requires new
implementation and factory deployment with a new protocol version; deployed clones
cannot be changed in place.
