# Phase 3 Internal Security Review

Review date: 2026-07-24

Scope: Phase 3 contracts, schemas, ledger, indexer, API, migrations, and deployment script

Disposition: approved for local and testnet engineering only

## Review result

No unresolved existential or critical finding was identified. This is an internal
engineering review, not an independent audit and not authorization for production funds.

The implementation evidence covers `INV-ACC-001` through `INV-ACC-005`,
`INV-LOAN-001` through `INV-LOAN-015`, `INV-PAY-001` through `INV-PAY-003`,
`INV-PAY-007` through `INV-PAY-009`, and the applicable authority and numerical
invariants.

## Evidence

- Offer replay: exact EIP-712 offer hash, immutable offer ID, expiry, nonce range and
  individual cancellation, one-time consumption, and rollback tests.
- Atomic activation: tender selection, offer consumption, deterministic clone,
  registration, exact funding, activation, and fulfillment occur in one factory
  transaction; a forced transfer failure leaves no partial state.
- Debt and settlement: principal is reduced before the external token call under a
  reentrancy guard, and any transfer failure rolls back. Exact balance deltas reject
  fee-on-transfer and rebasing behavior.
- Closure: a zero balance moves lifecycle, servicing, and funding to terminal states and
  marks the canonical registry terminal. No activation path exists on the account after
  activation.
- Accounting: atomic multi-journal posting, per-asset balance validation, immutable
  copies, one linked reversal, event idempotency, loan dimensions, and finality gating.
- Indexer: canonical parent validation, transactional reorg replacement, payment-ID
  uniqueness, and deep-equal rebuild tests.
- API: every route requires authentication; lender attribution is checked; transaction
  preparation is unsigned and contains no private signing material.
- Interfaces: additive Protobuf compatibility and deterministic four-language
  generation; reviewed ABI snapshots for all five Phase 3 contracts.

## Findings

| ID | Severity | Status | Finding and disposition |
|---|---|---|---|
| P3-SEC-001 | Medium | Accepted boundary | `OfferManager` verifies ECDSA account signatures and does not implement ERC-1271 contract-wallet signatures. Smart-contract lenders are not admitted in Phase 3. Owner: Protocol Architecture Authority. Backlog: `UNI-SIGN-001`. |
| P3-SEC-002 | Medium | Mitigated | Exact before-and-after balance checks make fee-on-transfer, rebasing, and adversarial settlement tokens revert, but admission still depends on correct asset-registry governance. Only reviewed standard ERC-20 assets may be activated. Owner: Security Authority. |
| P3-SEC-003 | Medium | Mitigated | The Go ledger and API stores are engineering kernels, not production persistence or identity systems. Local-only execution and the no-real-value boundary remain enforced. Owner: Release Authority. Backlog: `UNI-PERSIST-001`. |
| P3-SEC-004 | Low | Accepted | Offer, tender, and maturity gates use block timestamps and therefore tolerate normal validator timestamp skew. Deadlines must not be configured at sub-block precision. Owner: Protocol Architecture Authority. |
| P3-SEC-005 | Low | Mitigated | A lender may sign multiple offers with the same nonce; consuming or cancelling one invalidates the shared nonce. Interfaces must display that grouping behavior. Unique offer IDs still prevent signature replay. Owner: Protocol Architecture Authority. |

## Explicitly deferred attack surfaces

Collateral custody, price oracles, interest accrual, delinquency, default, liquidation,
syndication, refinancing, secondary markets, fiat, cards, external identity, bridges,
governance voting, real custody, production persistence, and production operations are
absent. Each requires its own threat-model delta, tests, and review before merge.
