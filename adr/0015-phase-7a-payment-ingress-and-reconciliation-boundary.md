# ADR 0015: Phase 7A Payment Ingress and Reconciliation Boundary

Status: accepted for synthetic local engineering

Date: 2026-07-24

## Context

Phase 6B closes a synthetic same-chain loan-activation path, but external payment rails
introduce different authorities and failure modes. A request, provider authorization,
callback, or provisional capture is not final settlement. Provider delivery is at least
once and may be duplicated, delayed, reordered, forged, or contradictory. Raw callbacks
may contain restricted financial data, while accounting must preserve immutable,
balanced, denomination-specific provisional, final, reversal, suspense, and
reconciliation records.

Connecting a live bank or card adapter before these controls exist would allow external
events to produce duplicate effects, false finality, hidden differences, or unauthorized
loan and collateral changes.

## Decision

1. Phase 7A is an off-chain payment-ingress and reconciliation foundation. It adds no
   production Solidity payment router and grants no on-chain role.
2. The first implementation uses injected synthetic providers and exact integer units in
   one declared asset. It performs no network request and stores no bank account, PAN,
   cardholder, identity, or other real provider data.
3. A payment intent binds one payment ID, idempotency key, payer reference, optional loan
   reference, rail, provider, asset, exact amount, purpose, expiry, and schema version.
   Reuse of an idempotency key with different content fails closed.
4. Payment states remain explicit:
   `CREATED -> PROCESSING -> PROVISIONAL -> FINAL`, with bounded `FAILED`, `REVERSED`,
   and `DISPUTED` paths. Initiation, authorization, and provisional evidence never imply
   final settlement.
5. Every callback is size-bounded, retained immutably before normalization, and linked to
   provider ID, provider event ID, payment ID, raw-payload hash, signature evidence,
   provider occurrence time, and Unified ingestion time.
6. The synthetic callback verifier uses a pinned Ed25519 public key and a
   domain-separated canonical payload. The provider must be active, the signature valid,
   the callback unexpired, and provider, payment, asset, amount, and reference exact.
7. Provider event IDs are unique inside the provider namespace. An identical replay
   returns the prior result. Reuse with different bytes or meaning creates a visible
   reconciliation exception and no repeated economic effect.
8. Callback order is not trusted. Unknown payments, unknown providers, invalid
   signatures, stale evidence, impossible transitions, and conflicting statuses enter an
   immutable quarantine record. They are never silently discarded or auto-finalized.
9. Provisional and final balances use distinct accounts. Each state-changing provider
   event produces at most one balanced, immutable, idempotent journal or linked reversal.
10. The first slice may recognize provider settlement and reverse that recognition, but
    it does not allocate payments to loan debt, release collateral, refund users, initiate
    payouts, or reinstate loan obligations. Those require a later accepted Phase 7B
    allocation boundary.
11. Reconciliation compares an immutable synthetic provider statement with canonical
    payment and ledger evidence for one provider, asset, and as-of time. Every difference
    records expected units, observed units, reason, owner, age, deadline, and status.
12. Suspense and reconciliation differences cannot be allocated, refunded, released,
    treated as revenue, or counted as available reserves in this slice.
13. Canonical Protobuf is the interface source. Solidity, Go, TypeScript, and Python
    bindings remain deterministic generated derivatives even though Phase 7A executes
    off-chain.
14. Tests must cover authentication, expiry, exact binding, identical replay,
    conflicting replay, out-of-order delivery, unknown callback quarantine, provisional
    versus final journals, reversal linkage, outage retry, reconciliation difference
    visibility, and integer conservation.
15. This boundary authorizes only mocked local engineering. It authorizes no live bank,
    card, payment or FX provider, real financial data, raw card data, real funds,
    production credentials, public testnet integration, or mainnet deployment.

## Consequences

- External authority is normalized behind a fail-closed ingress rather than being allowed
  to mutate loans or collateral directly.
- An authenticated callback is evidence, not unilateral authority to declare arbitrary
  economics or erase prior accounting.
- Provisional/final distinctions, callback idempotency, immutable reversal, quarantine,
  and reconciliation become testable before any live adapter exists.
- Phase 7 payment allocation, refunds, chargebacks against loan debt, FX, payouts, and
  production operations remain separate review gates.
