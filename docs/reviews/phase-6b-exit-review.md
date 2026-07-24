# Phase 6B Engineering Exit Review

Date: 2026-07-24

Decision: PASS for the bounded synthetic underwritten-activation engineering milestone

Production identity, underwriting, lending, or payment-rail authorization: NOT GRANTED

## Reviewed scope

This review covers the accepted Phase 6B boundary, the policy-isolated version-3
underwritten loan factory, direct borrower and signed-lender authorization, exact-decision
and product binding, atomic exposure and funding conservation, terminal release, generated
interfaces, final audit evidence, rollback simulation, and internal security review merged
through commit `6835a8e`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| One borrower transaction creates one fully recognized loan | PASS | reservation, tender selection, offer consumption, registration, exact funding, loan activation, exposure activation, and fulfillment execute atomically |
| Borrower and lender authorize the same activation | PASS | direct tender-owner call, EIP-712 offer, deterministic loan ID, activation agreement, and opaque consent commitment |
| The active decision matches the exact product and economics | PASS | borrower, asset, product, policy ID/version, amount, duration, credential, freshness, and lineage are rechecked in the activation transaction |
| An underwritten product cannot select the legacy path | PASS | version 2 rejects the underwritten-policy marker and version 3 requires one exact marker |
| Failed activation leaves no partial state or funds movement | PASS | EVM funding-failure rollback and independent six-stage failure injection restore the initial state |
| Emergency controls stop only new activation | PASS | global and dedicated new-loan pauses reject activation while repayment, closure, and exposure release remain available |
| Recognized exposure remains until canonical zero-debt terminal state | PASS | exact principal becomes active exposure and permissionless release requires the registered account to be terminal with zero outstanding principal |
| Audit evidence is immutable, final, and privacy bounded | PASS | additive Protobuf, Go validation, SQL completeness constraints, opaque commitments, and the privacy-surface gate |
| Interfaces remain compatible and deterministic | PASS | Buf compatibility and regeneration checks pass for Solidity, Go, TypeScript, and Python; ABI compatibility covers 34 contracts |
| Production runtime bytecode remains deployable | PASS | 120 production artifacts pass the 24,576-byte optimized gate; the version-3 factory runtime is 11,581 bytes |
| Critical and existential risks have owners and controls | PASS | four Phase 6B risks and two assumptions have evidence, expiry, validation, and accountable roles |

The pinned Foundry suite contains 61 passing tests. Phase 6B contributes seven scenarios
covering activation and repayment, both pause domains, consent/product/asset/amount/duration
mismatch, funding rollback, legacy-policy rejection, replay, revocation, supersession, and
terminal release. The two UFT invariants each complete 128,000 calls. Seventeen Python
tests, all Go tests, the TypeScript build, schema compatibility, generated-code freshness,
dependency audits, the complete foundation check, all four protected GitHub checks, and
the disposable five-service local smoke/reset cycle pass.

## Authority and conservation separation

- The borrower owns the tender and directly submits the final activation.
- The lender signs the exact version-3 offer and cannot be substituted by the borrower.
- The underwriter records an immutable decision but cannot activate or fund a loan.
- Only an approved underwritten product policy can enter the version-3 path.
- Only the version-3 factory receives both loan-factory and exposure-factory roles.
- The funding manager transfers exact registered settlement assets and retains no lending
  discretion.
- Repayment goes directly to the canonical account and does not depend on the factory.
- Terminal zero-debt exposure release is permissionless and cannot redirect funds.
- The ledger accepts only final opaque control evidence and cannot mutate posted history.

## Deferred capabilities

This exit does not claim completion or approval of:

- production identity, consent, underwriting, adverse-action, fairness, or model-risk
  processes;
- live bank, card, payment, oracle, bridge, identity, bureau, or sanctions providers;
- interest, schedules, collateral, syndication, default, liquidation, write-off, reserve,
  insurance, or recovery behavior for underwritten loans;
- delegated or relayed consent, a restricted data vault, raw identity data, ZK credentials,
  or global uniqueness;
- cross-asset limits or conversion, portfolio concentration, loss absorption, or capital
  adequacy;
- provider callback authentication, provisional settlement, reversal, chargeback, refund,
  suspense, or reconciliation workflows;
- independent privacy, legal, accounting, model-risk, or production security approval;
- public testnet approval, production keys, real unsecured funds, or mainnet use.

A generic version-2 local loan remains possible, but it cannot include the marker required
to claim Phase 6B underwriting. Different subject commitments also remain different
exposure subjects. Product and provider limits therefore remain zero outside synthetic
local engineering.

## Next milestone

Phase 7 may begin only with a separate accepted boundary for payment intents, provider
routing and idempotency, authenticated callbacks, provisional versus final settlement,
reversals and chargebacks, suspense accounting, reconciliation exceptions, outage
recovery, and privacy-safe evidence. The first slice must use mocked providers and
synthetic funds; no live bank or card rail may be configured before its security,
accounting, operational, and legal authorities approve the boundary.
