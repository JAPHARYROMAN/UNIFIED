# ADR 0017: Phase 7C Canonical External Settlement Boundary

Status: accepted for synthetic local engineering

Date: 2026-07-24

## Context

Phase 7A can authenticate and reconcile synthetic provider evidence. Phase 7B can
calculate a principal-only allocation and exact reversal against a synthetic obligation
projection. Neither phase controls the loan's registered settlement token or canonical
on-chain debt.

The current loan account reduces debt, transfers settlement tokens to the lender, and
marks zero-principal loans terminal in one transaction. A terminal loan cannot be
reopened, while collateral may subsequently be released against terminal zero debt.
Calling that path while an external payment remains reversible would therefore permit an
off-chain reversal after irreversible debt closure, payout, refund, or collateral
release.

A provider, converter, EVM transaction, and ledger also cannot share one atomic commit.
Phase 7C must make the EVM transaction the canonical economic commit and recover every
other step idempotently around it.

## Decision

1. Phase 7C supports only synthetic, local, mature external settlement. It adds no live
   provider, real financial data, production credential, real fund, public testnet, or
   mainnet integration.
2. `PAYMENT_STATUS_FINAL` remains provider finality and is not reinterpreted. A separate
   canonicalization-eligibility record requires an unreversed payment, exact matched
   reconciliation, immutable finality and conversion policies, and an elapsed reversal
   deadline.
3. Reserve-backed early finalization is unavailable. The protocol neither represents nor
   claims funded reserve coverage in this slice. Canonicalization before the reversal
   deadline fails closed.
4. A loan is eligible only when its immutable `policySetHash` proves a reviewed mature
   external-settlement policy. The complete supplied policy set must hash to the active
   loan terms and contain exactly one compatible registered policy. Loans without that
   binding remain direct-token-repayment only.
5. The first slice is one provider payment, one loan, one registered settlement token,
   one lender, principal-only, and a fixed one-to-one conversion. The source provider
   asset and target token retain distinct asset identities. Their denomination and
   precision must match, source units must equal target units, and fees, slippage, and
   rounding must be zero.
6. The synthetic converter/finalizer bears all upstream risk after the policy deadline.
   It must deliver the exact registered loan token in the canonical EVM transaction.
   Provider evidence alone cannot mint, credit, or substitute for tokens.
7. A canonical repayment gateway uses the existing `PAYMENT_FINALIZER_ROLE`, a
   capability-scoped emergency adapter control, `LoanRegistry`, `AssetRegistry`, and the
   loan's immutable policy set. A separate current `ACCOUNTING_ATTESTER_ROLE` signs the
   domain-separated eligibility commitment. The finalizer must be distinct from the
   gateway, loan, lender, borrower, and attester, and no caller selects a payout, refund,
   token, or collateral recipient.
8. Before value moves, the gateway verifies the canonical loan account and ID, reviewed
   factory/version provenance, active lifecycle, expected state nonce and debt, exact
   target asset and token, nonzero evidence and policy commitments, elapsed reversal
   deadline, and unique payment and allocation identities. The attestation independently
   binds the final unreversed provider record, exact matched reconciliation, source and
   target assets and units, original Phase 7A journals, finality deadline, policies, and
   intended gateway.
9. In one EVM transaction the gateway pulls exact gross tokens from the finalizer,
   allocates `min(gross, canonical principal)` to the existing loan repayment path,
   transfers exact excess to the registry borrower, and verifies sender, gateway,
   lender, borrower, and debt balance changes. Failure of any leg rolls back every leg.
10. The gateway must retain no newly supplied settlement balance and exposes no general
    rescue or withdrawal route. Fee-on-transfer, rebasing, callback-dependent, foreign,
    inactive, or balance-mismatching assets fail closed.
11. The payment ID and allocation ID bind one instruction digest and one result. Exact
    replay returns the recorded result without another economic effect. Conflicting
    reuse, stale debt, a direct-repayment race, or a second canonicalization fails.
12. The gateway never calls collateral custody. A borrower may use the existing,
    separate release path after successful gateway execution has produced terminal zero
    debt. The custody contract does not wait for the off-chain `CONFIRMED` state; a
    same-chain reorganization removes the repayment and any dependent release from
    canonical history together. Because execution waits through the reversal window, no
    unresolved contractual provider-reversal risk remains.
13. The off-chain coordinator uses durable compare-and-set states:
    `PREPARED -> SUBMITTED -> CONFIRMED`, with bounded `FAILED`, `QUARANTINED`, and
    `INCIDENT` outcomes. Preparing atomically proves that no Phase 7B allocation or
    journals exist and claims the payment allocation mode as `CANONICAL_GATEWAY`.
    Phase 7B allocation and reversal reject that claim; Phase 7C rejects an existing
    synthetic allocation. Submission remains uncertain until canonical chain finality;
    confirmation is rebuilt from the gateway event.
14. A reversal before submission cancels the non-posting canonicalization plan. A
    reversal while submitted is quarantined without changing the Phase 7A payment or
    posting any reversal journal. After confirmed mature settlement, a contradictory
    provider message records `INCIDENT` evidence only: it causes no
    `FINAL -> REVERSED` transition and no Phase 7A or Phase 7B reversal journal. It
    cannot reopen terminal debt, claw back lender or borrower transfers, or invalidate
    released collateral.
15. The Phase 7C path uses a new non-posting waterfall plan and never calls the Phase 7B
    economic allocation path. After the gateway event reaches configured chain
    finality, one idempotent `PostBatch` records separately balanced source conversion,
    target-token custody, canonical allocation, lender payout, and borrower refund
    journals. A failed transaction or reorganization before final posting produces none.
    A deep reorganization after posting creates linked compensating journals and an owned
    incident; it never edits history.
16. Immutable conversion evidence binds the original unreversed Phase 7A final journals
    and provider account, provider/payment reference, source asset and units, target
    token asset and units, fixed one-to-one rate, zero fee/slippage/rounding, finalizer,
    gateway transaction, and the finalizer's irrevocable acquisition or discharge of the
    provider asset and assumption of later provider-reversal risk. The source account is
    derived from the original journal, never supplied by the caller.
17. The first-slice source and target identities remain distinct even though their
    denominated units convert one-to-one. Cross-denomination FX, non-unit rates, fees,
    slippage, and rounding require a later boundary with explicit valuation policy.
18. Late, contradictory, or impossible provider evidence is retained as an owned
    incident with immutable source evidence and reconciliation status. No reserve,
    recovery, expense, or debt journal is inferred without separately approved economic
    evidence.
19. Protobuf remains the canonical interface source. Eligibility, instruction,
    submission, confirmation, payout, refund, and incident evidence generate
    deterministic Solidity, Go, TypeScript, and Python projections.
20. Tests must cover partial, full, and excess settlement; premature finality; mismatched
    reconciliation; wrong asset, policy, loan, state nonce, or debt; unauthorized and
    disabled finalizers; replay and conflict; direct-repayment races; exact transfer
    rollback; coordinator crashes; reorgs; ledger outages; reversals before, during, and
    after canonicalization; and collateral release only after successful gateway
    execution has produced terminal zero debt.
21. Reserve-backed early settlement, cross-denomination FX, interest and fee
    waterfalls, multiple loans or lenders, live payouts, production refund operations,
    and automatic collateral release remain unavailable.

## Consequences

- Actual target-token delivery, not provider testimony, becomes the economic precondition
  for canonical debt mutation.
- Existing reviewed loan accounts can be reused only when their immutable policy set
  already binds the mature-settlement mode and their factory/version provenance is
  approved. The gateway validates the exact set hash, historical registration,
  interface, code hash, and configuration compatibility, but does not require the policy
  to remain active for new origination. Deprecation cannot remove an active loan's bound
  repayment route.
- Lender payout and borrower excess refund share the debt-mutation transaction, removing
  an intermediate withdrawal authority and its double-spend risk.
- The first slice makes no reserve solvency claim. Supporting earlier finalization later
  will require a separately reviewed segregated reserve vault, coverage measurement,
  loss waterfall, and collateral-release interlock.
- Cross-domain atomicity is expressed honestly as a recoverable saga whose canonical
  commit is the finalized EVM event.
