# Phase 7A Engineering Exit Review

Date: 2026-07-24

Decision: PASS for the bounded synthetic payment-ingress and reconciliation milestone

Live provider, production payment, loan-allocation, or real-fund authorization: NOT GRANTED

## Reviewed scope

This review covers the accepted Phase 7A boundary, immutable payment intents, synthetic
provider configuration, retain-before-normalize callback ingestion, Ed25519
authentication, exact binding, replay and ordering controls, quarantine, provisional and
final journals, linked reversal, provider-to-ledger reconciliation, generated interfaces,
append-only SQL evidence, simulations, privacy controls, and internal security review
merged through commit `1ffef0e`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Payment identity and intent idempotency fail closed | PASS | legal-entity scoped key, immutable content hash, exact provider/rail/asset/integer amount, and conflicting-reuse tests |
| Raw callback evidence is retained before normalization | PASS | append-only size-bounded ingress records preserve raw/signature hashes and synthetic payload bytes before verification or parsing |
| Provider callbacks are authenticated and exactly bound | PASS | active injected provider, pinned Ed25519 key, domain-separated canonical bytes, expiry, provider/event/payment/reference/asset/amount checks |
| Duplicate, conflicting, and reordered delivery creates no repeated effect | PASS | exact replay returns original journal IDs; conflicting event reuse and impossible order quarantine without new accounting |
| Provisional and final settlement remain distinct | PASS | bank/card pending accounts are separate from final cash or processor receivable; no loan or collateral integration exists |
| Recognized reversal preserves immutable accounting | PASS | one ledger batch posts linked opposites for every applicable final and provisional journal |
| Unknown and invalid evidence remains visible | PASS | immutable quarantine reason, owner, deadline, raw hash, evidence hash, and separate resolution record |
| Provider-to-ledger mismatches cannot be hidden by netting | PASS | both total units and payment/provider references are compared; zero-net offsetting unknown items still create an exception |
| Suspense and reconciliation remain owned and unavailable | PASS | expected, observed, difference, unmatched count, snapshots, owner, deadline, age class, status, and resolution evidence are explicit |
| Public interfaces are compatible and privacy bounded | PASS | additive Protobuf, deterministic four-language projections, Buf compatibility, and payment privacy-surface checks |
| Database and local topology are reproducible | PASS | migration constrains exact bindings, state transitions, journals, immutable evidence, statements, and exceptions; local smoke/reset passes |
| Critical and existential risks have owners and controls | PASS | five Phase 7A risks and two assumptions have evidence, expiry, validation, and accountable roles |

Fourteen focused Go tests cover intent conflicts, authentication, exact replay,
quarantine, ordering, outage retry, provider reversal capability, bounded raw payloads,
bank/card journals, atomic reversal, per-reference reconciliation, suspense aging, and
orchestrator-to-ledger integration. Five payment simulations are included in 22 passing
Python tests. The pinned unchanged Solidity suite retains 61 passing tests, and 112
production artifacts pass the optimized runtime-size gate. Schema compatibility,
generated-code freshness, Go vet, Go/Node/Python dependency audits, the complete
foundation check, all four protected GitHub checks, and the disposable five-service local
smoke/reset cycle pass.

## Authority and data separation

- The caller creates an opaque intent but cannot assert provider settlement.
- The injected provider public key authenticates evidence but cannot post a journal
  directly.
- The orchestrator changes only payment state and cannot access the ledger internals,
  loans, collateral, tokens, treasury, or a provider network.
- The ledger adapter accepts a narrow transition and cannot sign callbacks or change
  payment state.
- Reconciliation observes payment and ledger evidence but cannot silently post a
  correction, clear suspense, or replay a callback.
- Quarantine and reconciliation resolutions are new evidence records, not mutations of
  the original provider payload, state event, or journal.
- Public schemas contain opaque references and hashes rather than raw bank, cardholder,
  identity, or credential data.

## Deferred capabilities

This exit does not claim completion or approval of:

- a public webhook, live bank/card/payment provider, provider SDK, statement fetch, mTLS,
  HSM, production key rotation, or provider-compromise recovery;
- real bank, cardholder, payment, identity, or restricted financial data;
- final payment allocation to principal, interest, fees, penalties, or borrower credit;
- chargeback or reversal restoration of loan obligations and servicing state;
- collateral release, refund, payout, withdrawal, deposit, or disbursement;
- processor fees, chargeback fees, reserves, insurance coverage, or loss recognition;
- FX quotes, conversion, slippage, rounding, partial allocation, split tender, or
  multi-currency netting;
- automatic suspense correction, write-off, revenue recognition, or operational
  exception workflow;
- independent privacy, legal, accounting, operational, or production security approval;
- production credentials, real funds, public testnet integration, or mainnet use.

The local raw callback store is not a production restricted-data vault. Provider
configuration and statements are synthetic, and no network listener or fund-moving
capability exists.

## Next milestone

Phase 7B may begin only with a separate accepted boundary for final payment allocation,
the immutable loan waterfall, overpayment credit, refund authority, idempotent allocation,
chargeback and reversal restoration, servicing-state effects, and collateral release
after the applicable finality predicate. The first slice must continue using synthetic
same-asset payments and mocked providers; live rails and real funds remain prohibited.
