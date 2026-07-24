# Phase 7B Engineering Exit Review

Date: 2026-07-24

Decision: PASS for the bounded synthetic final-payment allocation milestone

Canonical debt, collateral-release, refund, payout, or real-fund authorization: NOT GRANTED

## Reviewed scope

This review covers the accepted Phase 7B boundary, versioned synthetic obligations,
matched-final-payment eligibility, deterministic principal and refundable-excess
allocation, atomic accounting, exact reversal restoration, non-executing collateral
eligibility, generated interfaces, append-only SQL evidence, simulations, and internal
security review merged through commit `16c4ac2`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Only matched final payment evidence allocates | PASS | provisional, difference, unmatched-item, foreign-asset, and stale-version inputs fail without effects |
| One payment allocates at most once | PASS | deterministic allocation identity, payment uniqueness, exact obligation compare-and-set, and replay/conflict tests |
| The first-slice waterfall is deterministic | PASS | principal is `min(payment, debt)` and every remaining unit is refundable excess |
| Overpayment cannot become hidden revenue | PASS | gross equals principal plus `2150 Refund Payable`; no revenue account or refund execution exists |
| Allocation accounting is atomic and balanced | PASS | unallocated liability, receivable, lender claim, lender payable, and refund payable post in one batch |
| Accounting failure leaves the projector unchanged | PASS | injected outage preserves the prior debt/version and permits one safe retry |
| Reversal restores exact original components once | PASS | exact provider/payment/allocation binding, linked opposite batch, versioned debt restoration, and replay protection |
| Collateral release is not executable | PASS | eligibility is read-only evidence and requires zero projection debt plus every active reversal-risk deadline |
| Interfaces and persistence remain reproducible | PASS | additive Protobuf, four-language generation, Buf compatibility, append-only migration 000008, and local smoke/reset |
| Critical and existential risks have owners and controls | PASS | four Phase 7B risks and two assumptions have evidence, expiry, validation, and accountable roles |

Six focused Go scenarios cover partial allocation, overpayment, finality and reconciliation
holds, stale/asset mismatch, accounting rollback, replay, exact reversal, linked journals,
and release eligibility. Three allocation simulations are included in 25 passing Python
tests. The unchanged pinned Solidity suite retains 61 passing tests. Schema compatibility,
generated-code freshness, ABI compatibility, privacy gates, dependency audits, the full
foundation check, all four protected GitHub checks, and the disposable five-service local
smoke/reset cycle pass.

## Authority separation

- Phase 7A authenticates settlement but cannot choose the loan waterfall.
- The allocation projector consumes synthetic evidence but cannot access a chain, token,
  provider network, collateral contract, refund service, or payout service.
- The ledger adapter posts only the supplied conserved allocation and cannot change
  projector state.
- Reversal reuses historical allocation components; current policy cannot reinterpret
  them.
- Release eligibility is evidence only and cannot mark a loan terminal or move custody.
- Public schemas label the obligation as a snapshot and preserve source evidence/version.

## Deferred capabilities

This exit does not approve canonical on-chain debt mutation, settlement-asset conversion,
collateral release, loan terminal marking, lender payout, borrower refund, interest,
fees, penalties, schedules, multi-loan allocation, reserve coverage, losses, delinquency
changes, live providers, real financial data, production credentials, real funds, public
testnet integration, or mainnet use.

Projected zero debt is not authoritative loan state. Any future canonical adapter must
recheck actual debt, settlement assets, accounting, provider finality, reversal risk, and
custody policy atomically under a separately accepted boundary.

## Next milestone

Phase 7C may begin only with a separate accepted boundary for canonical settlement-asset
conversion and loan mutation. It must resolve atomicity across external settlement and
on-chain debt, late reversals, reserve coverage, lender payout, borrower refund, and
collateral custody before any real payment rail or fund is introduced.
