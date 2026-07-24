# ADR 0009: Phase 4A Deterministic Risk Foundation

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Protocol Architecture Authority
- **Reviewers:** Security Authority; Accounting and Economic Risk Authority; Release Authority

## Context

Collateral custody and liquidation must not define their own prices, interest, schedules,
or default predicates. Phase 4 therefore begins with deterministic risk and servicing
primitives that can be independently reviewed before any collateral disposition route is
authorized.

## Decision

1. Oracle prices use one governance-configured canonical quote asset per collateral
   asset, up to eight approved adapters, a configured minimum fresh-source quorum,
   median aggregation, decimal normalization to 18 places, outlier rejection, evidence
   hashing, and an explicit circuit-broken safe mode.
2. A failed quorum, stale source set, or excessive deviation blocks the canonical price.
   Safe repayment and collateral top-up paths remain outside the router and therefore
   available.
3. Interest uses integer ray precision (`1e27`), actual/365 simple accrual, and round-down
   division. Variable rates bind a recorded benchmark to spread, floor, cap, maximum
   observation age, and the exact accrual interval. Retroactive observation substitution
   is not supported.
4. Schedule generation supports bullet, equal-principal, annuity, interest-only,
   balloon, custom installments, and explicit payment-holiday offsets. Integer remainder
   is assigned to the final installment so principal conservation is exact.
5. Servicing state is derived from configured due, grace, and cure deadlines. Final
   payments, cure evidence, acceleration, and default require separate bounded roles.
   A valid cure recorded before its deadline has priority over a later default attempt.
6. Solidity and Go use independent implementations with the same canonical integer
   vectors. Protobuf remains the cross-language source for observations, terms,
   schedules, installments, and servicing records.
7. These primitives do not custody collateral, authorize a liquidation, connect to a
   live oracle, or change an active Phase 3 loan. Those actions remain blocked until
   Phase 4B consumes this reviewed boundary.

## Consequences

- Compound and negative interest, utilization curves, revenue share, irregular custom
  schedule execution, and production benchmark adapters require additional policy
  versions.
- The Phase 4A oracle stores only finalized application observations from approved
  adapters; adapter governance remains security-critical.
- No production funds, keys, oracle feeds, collateral deposits, auction, or mainnet
  deployment is authorized.
