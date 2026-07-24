# Phase 7C Internal Security Review

Date: 2026-07-24

Scope: synthetic mature-settlement policy, canonical exact-token gateway, allocation-mode
exclusion, provider-reversal guard, canonicalization coordinator, chain projection,
conversion/allocation/payout/refund accounting, append-only evidence, generated
interfaces, and independent simulations.

## Reviewed properties

- Provider `FINAL` cannot mutate a loan. Canonical preparation additionally requires an
  exact matched reconciliation, immutable policy and journal commitments, a mature
  reversal deadline, and an exclusive allocation-mode claim.
- Phase 7B and Phase 7C require one explicitly shared payment/allocation registry and
  store. PostgreSQL routes both modes through one unique payment claim under the payment
  row lock, so concurrent processes cannot take both economic paths. A canonical claim
  remains permanent through failure and retry.
- The complete policy set hashes to immutable loan terms. Exactly one historically
  registered mature-settlement policy, code hash, configuration, factory, and protocol
  version are accepted. Deprecation for new origination does not disable an active loan's
  bound repayment route.
- The finalizer and independent accounting attester hold separate current roles and are
  distinct from the gateway, loan, lender, and borrower. The attestation is domain
  separated by chain, gateway, finalizer, policy set, and full instruction. Solidity and
  Go share one ABI/legacy-Keccak encoder and a fixed golden digest.
- The gateway requires elapsed reversal maturity and exact source-to-target units, pulls
  the active registered loan token, reduces canonical debt through the existing loan
  account, pays its canonical lender, refunds only exact excess to the registry borrower,
  and retains no new balance.
- Payment and allocation identities bind one digest and result. Exact terminal replay
  returns the stored result; conflicting reuse, stale debt/state, or a direct-repayment
  race fails without another effect.
- The gateway exposes no reserve, mint, swap, general withdrawal, arbitrary recipient,
  provider callback, or collateral call. Adapter disable does not block the protected
  direct repayment route.
- A reversal while prepared, failed, or submitted is durably quarantined before the Phase
  7A transition and accounting path. Retry remains blocked until the reversal atomically
  commits through the Phase 7A path and creates a permanent allocation tombstone. A
  contradiction after confirmation produces incident evidence only and cannot reopen
  debt or reverse settled lender/refund journals.
- Submitted reversal resolution requires an opaque indexer-produced reverted-transaction
  proof matching the stored chain, gateway, transaction, canonical receipt block, and
  finality head. Prepared and failed plans reject transaction proof. The SQL resolver
  derives the Phase 7A opposite journals and commits them with the reversal event,
  resolution, coordinator transition, and tombstone in one transaction.
- The gateway indexer accepts only headers signed by the configured synthetic chain
  observer and verifies both transaction and receipt Merkle-Patricia inclusion at one
  transaction index. It decodes gateway logs only from an inclusion-verified successful
  receipt and derives reverted-transaction evidence only from its canonical receipt
  store after configured head depth. Legacy and typed receipts require canonical status,
  cumulative gas, exact bloom, and bounded logs; trie child references are canonical.
  Per-proof limits are supplemented by block-wide proof-count, proof-byte, and total
  input limits. Signed observation time is monotonic across appends and replacements.
  Identical signed headers admit only same-time, same-signature, nonconflicting proof
  enrichment.
- The immutable finality-policy hash binds chain, gateway, depth, and observer key, so
  confirmation, failure, reversal, and reorganization evidence from an alternate
  authority is rejected. A shallow reorg removes provisional evidence. A deep reorg
  preserves transaction index, receipt root/proof, policy/authority, orphaned and
  confirmation-head signatures, replacement and detected-head signatures, submission
  time, and monotonic detection time. Only the coordinator can bind that envelope to the
  durable plan, commit the state transition, and issue the opaque authority restored
  after restart. Accounting derives linked opposites for the entire batch and commits
  them atomically with its owned incident.
- Opaque coordinator confirmations and coordinator-issued durable reorg capabilities are
  the only accounting authority. Chain, gateway, loan account, token, finalizer,
  attester, nonces, raw event payload, finality, recipients, instruction, and complete
  reorg provenance remain bound through durable accounting.
- Source provider and target token assets remain distinct. Fixed one-to-one conversion,
  zero fee/slippage/rounding, derived source account, unreversed Phase 7A journals,
  payment-specific unallocated balance, and exact target custody are checked before the
  seven/eight-journal batch commits.
- `commit_canonical_external_settlement(...)` is the sole supported callable durable
  success path.
  It locks payment and coordinator rows, requires the request to equal the stored
  confirmation, and accepts only normal durable `CONFIRMED` authority or submitted-origin
  durable `INCIDENT` authority with the exact consumed pending reversal. It commits
  conversion, gateway event, confirmation, all journals and links, payout, and optional
  refund in one transaction. Exact replay returns deterministic identities; submitted,
  unresolved quarantine, wrong-origin incident, stale-time, partial, and changed-content
  requests fail closed.
- Generated messages remain additive, append-only SQL records reject mutation, and public
  schemas contain opaque commitments rather than raw bank, card, identity, or credential
  data.

## Adversarial coverage

- partial, full, and excess repayment;
- exact terminal replay and conflicting payment/allocation reuse;
- unauthorized, expired, same-party, and invalid attester/finalizer authority;
- premature deadline and mismatched provider, reconciliation, journal, policy, asset,
  amount, debt, state nonce, factory, and protocol-version evidence;
- inactive or fee-on-transfer token behavior and atomic balance rollback;
- direct-repayment race, adapter disable, and unchanged direct repayment liveness;
- Phase 7B/7C allocation conflict, full-content claim replay, changed-content rejection,
  and accounting-outage retry with permanent claim retention;
- reversal during prepared, submitted, and confirmed states;
- canonical success racing a submitted reversal, with shared-row serialization,
  deterministic winner semantics, durable incident consumption, and restart replay;
- crash/retry, indexer-verified transaction failure, head-advanced event replay,
  fabricated header/transaction/receipt/proof rejection, alternate-authority rejection,
  canonical gas/bloom and trie-child rejection, proof-count and aggregate-byte bounds,
  monotonic append/replacement rejection, same-header proof enrichment and conflict,
  provisional-promotion rejection, shallow reorg, deep reorg, full-authority restart
  rehydration, stale writers, and ledger outage;
- concurrent Phase 7B/7C SQL claims, authoritative Phase 7A eligibility, complete
  journal roles, exact-snapshot success commit, submitted-origin incident success,
  deterministic success replay, partial/conflicting success rejection, and
  recipient-provenance conflicts;
- source/target conservation, payout/refund bounds, journal idempotency/conflict, and
  whole-batch compensation.

## Residual boundary

All provider records, conversion evidence, roles, assets, accounts, and funds are
synthetic. The mature deadline is assumed to extinguish the provider's contractual
reversal right; a later contradiction is owned by the synthetic converter and does not
create a protocol reserve claim. No live provider, real financial data, real fund,
production key, reserve-backed early settlement, non-unit conversion, cross-denomination
FX, automatic collateral release, public testnet, or mainnet use is authorized.

Service executables have no runtime provider, RPC, broker, or database-listener wiring.
The reviewed durability evidence is the shared SQL allocation store, coordinator CAS
store and history, constrained settlement schema, opaque typed adapters, restart tests,
and disposable PostgreSQL lifecycle. The Ed25519 observer remains an assumed
uncompromised local/test trust root and is not an EVM consensus or light-client proof.
Migration 000009 does not establish a least-privilege runtime database role; revoking
direct table writes and granting execution of the supported commit function is a
deployment-blocking infrastructure control.
No unresolved critical or existential finding remains inside this bounded local scope;
the separate bounded engineering exit remains pending.
