# Phase 7C Engineering Exit Review

Date: 2026-07-25

Decision: PASS for the bounded synthetic mature canonical external-settlement milestone

Live provider, production settlement, reserve, public-network, or real-fund
authorization: NOT GRANTED

## Reviewed scope

This review covers the accepted Phase 7C boundary, synthetic mature-settlement policy,
exact-token canonical repayment gateway, exclusive allocation-mode claim, durable
canonicalization coordinator, authenticated local EVM projection, reversal and
reorganization handling, exact conversion/allocation/payout/refund accounting, generated
interfaces, append-only SQL evidence, simulations, risk and assumption records, and
internal security review merged through commit `168899e`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Provider evidence alone cannot reduce canonical debt | PASS | exact reconciliation, immutable mature policy, independent attestation, elapsed reversal deadline, exclusive allocation claim, and exact registered-token delivery are required |
| Canonical token movement and debt mutation are atomic | PASS | one EVM transaction pulls gross units, repays principal, pays the canonical lender, refunds canonical borrower excess, and retains no new gateway balance |
| One payment creates at most one economic result | PASS | immutable payment/allocation digest, exact terminal replay, conflicting reuse rejection, state nonce and debt checks, and one shared Phase 7B/7C payment claim |
| Durable success posting is exact and atomic | PASS | `commit_canonical_external_settlement(...)` locks authoritative rows and commits the exact confirmation, conversion, event, complete seven/eight-journal batch, payout, and optional refund in one transaction |
| Reversal races cannot reopen settled debt | PASS | durable quarantine, authenticated submitted-failure proof, atomic reversal and tombstone, and submitted-origin late-success incident semantics |
| Chain facts are authenticated and resource bounded | PASS | signed headers, transaction and receipt Merkle-Patricia inclusion, canonical receipt/log decoding, same-header enrichment, monotonic observations, finality, and aggregate proof/input limits |
| Reorganization authority is complete and restart-safe | PASS | pinned policy and observer authority, orphaned event and raw-payload evidence, confirmation/replacement/detection heads, monotonic times, restart-rehydrated coordinator capability, and alternate-authority rejection |
| Deep reorganization compensates the whole batch once | PASS | exact confirmation binding, complete linked opposite journals, one owned incident, immutable originals, replay safety, and partial/conflicting rejection |
| Source and target value remain conserved | PASS | distinct asset identities, fixed one-to-one units, zero fees/slippage/rounding, balanced journals, exact payout/refund bounds, and complete reconciliation evidence |
| Interfaces and persistence remain reproducible | PASS | additive Protobuf, deterministic four-language bindings, append-only migration 000009, ABI compatibility, generated-code freshness, and disposable PostgreSQL lifecycle |
| Critical and existential risks are owned and controlled | PASS | `RISK-PHASE7C-001` through `RISK-PHASE7C-006` have accountable owners, evidence, expiry, validation, and `CONTROLLED_LOCAL_ONLY` status |

PR #35 passed all four protected GitHub checks and merged as `168899e`. The pinned
Foundry v1.7.1 suite passed 78 tests, including 17 focused Phase 7C contract scenarios.
Full Go tests and vet, 20-repeat focused stress runs, 37 Python tests, TypeScript
compilation, schema compatibility, deterministic generated-code and ABI checks, contract
size, privacy and privileged-surface gates, dependency and secret scanning, the clean
PostgreSQL 17.6 migration/fixture cycle, and the disposable local smoke/reset cycle
passed. Independent protocol, accounting/composition, specification/SQL, technical-exit,
and governance-exit reviews found no critical or existential issue inside this bounded
scope.

## Authority and commit separation

- A provider `FINAL` record cannot itself mutate a loan.
- The finalizer must supply exact registered tokens and is distinct from the accounting
  attester, gateway, loan, lender, and borrower.
- The gateway derives lender and borrower recipients from canonical state and has no
  collateral, rescue, mint, swap, reserve, or general-withdrawal authority.
- The chain indexer derives facts from signed local headers and authenticated trie
  inclusion; decoded caller-authored logs alone create no authority.
- Accounting consumes opaque coordinator-issued confirmation and reorganization
  authority and cannot originate settlement rights.
- Deep reorganization creates append-only compensating evidence and never rewrites the
  original economic history.

## Deployment blockers and residual boundary

This exit remains synthetic and local-only. The pinned Ed25519 observer is an assumed
uncompromised test trust root, not EVM consensus or a production light client. A
production chain authority requires a separate accepted design and independently
verifiable source.

Migration 000009 does not establish a least-privilege runtime database role. Revoking
direct settlement-table writes and granting only the supported function execution
remains deployment-blocking. Service executables also lack live provider, converter, EVM
RPC, broker, and production ledger-listener wiring.

The mature deadline is assumed to extinguish the provider's contractual reversal right.
Legal and operational validation is required before using that rule with any real
provider; a later contradiction remains synthetic converter risk in this milestone.

## Deferred capabilities

This exit does not approve live providers or converters, real financial or restricted
data, real funds, production credentials or keys, public testnet or mainnet deployment,
reserve-backed early settlement, reserve coverage, cross-denomination FX, non-unit
conversion, fees, slippage, rounding, interest or penalty waterfalls, multiple loans or
lenders, automatic collateral release, or caller-selected payout/refund recipients.

## Next milestone

Phase 8 may begin only under a separately accepted cross-chain boundary covering
home-chain authority, message source and destination binding, finality and replay,
fully-backed wrapped UFT conservation, bridge-exposure limits, route compromise, provider
failover, and timeout recovery. No cross-chain value path may be added by interpreting
this bounded Phase 7C exit as production authority.
