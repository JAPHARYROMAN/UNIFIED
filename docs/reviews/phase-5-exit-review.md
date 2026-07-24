# Phase 5 Engineering Exit Review

Date: 2026-07-24

Decision: PASS for the bounded principal-only local/testnet engineering milestone

Production or full-product authorization: NOT GRANTED

## Reviewed scope

This review covers the accepted Phase 5 boundary, deterministic syndicate creation,
funding and refund lifecycle, tranche and position rights, principal distribution,
voting checkpoints, generated interfaces, accounting controls, risk simulation, and
internal security review merged through commit `81ef054`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Aggregate lender rights never exceed funded obligations | PASS | exact escrow, one pending position per commitment, atomic activation, and share/principal conservation tests |
| Repayment waterfalls are deterministic | PASS | senior-first contract tests, 256-run fuzzing, fixed residual allocation, and independent Python vectors |
| Position transfers do not duplicate rights | PASS | same-block seller accrual cut-off, claim snapshot, vote checkpoints, policy gates, and cross-owner split rejection |
| Accrued interest is assigned correctly at transfer | DEFERRED | this implementation is principal-only; no interest entitlement is represented or claimed |
| Refunds occur when funding thresholds fail | PASS | failed and borrower-cancelled rounds expose exact immutable-recipient pull refunds and reject replay |
| Tranche-loss simulations pass | PASS | deterministic junior-first boundary vectors pass; on-chain legal write-off remains intentionally unavailable |
| Accounting reconciles lender and borrower principal | PASS | finality-gated activation, commitment, refund, transfer, and distribution journals conserve by asset, lender, and tranche |
| Interfaces remain compatible and deterministic | PASS | additive Protobuf passes Buf checks and regenerates identical Solidity, Go, TypeScript, and Python projections |
| Production runtime bytecode remains deployable | PASS | 105 production artifacts pass the 24,576-byte optimized gate; new runtimes are 13,474, 11,753, and 4,917 bytes |
| Critical and existential risks have owners and controls | PASS | four Phase 5 risks and two assumptions have evidence, expiry, validation, and accountable roles |

The pinned Foundry suite contains 46 passing tests. Phase 5 contributes ten scenarios,
including 256-run payment-waterfall fuzzing. The two existing UFT invariants each complete
128,000 calls. The complete foundation check, dependency audits, all four protected
GitHub checks, and the disposable five-service local smoke/reset cycle pass.

## Authority and settlement separation

- The borrower may define and cancel a pre-activation round but cannot issue positions.
- The factory validates canonical assets, policy approval, emergency state, and loan
  identity but cannot move lender funds after creation.
- The vault owns escrow and aggregate borrower debt but cannot edit tranche policy.
- The position manager can be called for issuance and distributions only by its vault.
- Cross-owner movement requires an evidence-bearing transfer; split remains same-owner.
- The risk council may freeze a position but cannot redirect accrued distributions.
- The ledger accepts final events and cannot mutate posted history.
- Repayment remains available even when new-loan creation is paused.

## Deferred capabilities

This exit does not claim completion or approval of:

- interest, coupon, penalty, fee, or accrued-interest transfer allocation;
- on-chain loss recognition, legal write-off, forgiveness, insurance, or reserves;
- paid secondary-market settlement, public listings, or tokenized positions;
- eligible-buyer identity, jurisdiction, consent, or suitability enforcement;
- unbounded pools or more than eight tranches and 64 lifetime positions;
- external custody, off-chain commitment rails, live providers, or cross-chain rights;
- independent audit, formal proof completion, public testnet approval, or mainnet use.

## Next milestone

Phase 6 may begin only with a separate accepted boundary for privacy-preserving identity,
credential revocation, restricted data custody, exposure aggregation, explainable
underwriting, and unsecured-credit loss limits. Raw identity data must never enter public
contracts, and no live personal data or production provider may be introduced during the
engineering slice.
