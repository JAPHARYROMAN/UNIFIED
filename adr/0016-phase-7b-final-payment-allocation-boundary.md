# ADR 0016: Phase 7B Final Payment Allocation and Reversal Boundary

Status: accepted for synthetic local engineering

Date: 2026-07-24

## Context

Phase 7A authenticates synthetic provider evidence and distinguishes provisional from
final settlement, but deliberately leaves all amounts in unallocated payment accounts.
A separate allocation authority is required because provider settlement does not itself
decide which obligation components are valid, which waterfall applies, whether excess is
refundable, or how a later reversal restores debt and lender claims.

The current version-3 loan account is exact-token and principal-only. It cannot safely
treat off-chain provider evidence as a token transfer, and it has no reversible external
payment path. Phase 7B must therefore prove allocation and accounting controls without
claiming to mutate canonical on-chain debt or release collateral.

## Decision

1. Phase 7B adds a synthetic off-chain allocation projector and accounting adapter. It
   adds no Solidity role, external-payment function, token movement, or loan-account
   mutation.
2. The first slice is one payment, one loan, one exact asset, one lender, principal-only,
   zero-interest, and local-only. Interest, fees, penalties, costs, schedules, and split
   allocations remain unavailable.
3. Allocation requires a Phase 7A payment in `FINAL` state, exact provider/payment
   reference, a matching reconciliation result with no difference or unmatched item, and
   a nonzero finality-policy hash.
4. A versioned obligation snapshot binds loan, borrower, lender, asset, outstanding
   principal, aggregate version, source authority, source evidence, and as-of time.
   Stale, superseded, foreign-asset, or zero-debt snapshots fail closed.
5. The allocation ID binds payment, loan, obligation version, exact amount, waterfall
   policy, finality policy, and evidence. One payment may produce at most one final
   allocation.
6. The immutable first-slice waterfall is:
   `principal -> refundable borrower credit`. Principal receives the lesser of final
   payment units and outstanding principal. Every excess unit becomes refund payable and
   never revenue.
7. Allocation clears exact unallocated-payment liability, reduces principal receivable,
   reduces lender principal claim, creates lender repayment payable, and records any
   excess as refund payable through balanced atomic journals.
8. The projector reduces only its synthetic obligation snapshot and records principal,
   excess, pre/post debt, journal IDs, policy hashes, evidence, and version. It is not
   canonical loan state and cannot mark an on-chain loan terminal.
9. A reversal or chargeback requires an existing non-reversed allocation, exact payment
   and provider reversal evidence, reason, and evidence hash. It restores the same
   principal and lender claim components and removes the same refund/payable components
   through linked opposite journals.
10. Reversal is idempotent and cannot restore debt twice. It creates a new projector
    version; original allocation and journals remain immutable.
11. Collateral-release eligibility is evidence only. It may be true only when projected
    debt is zero, the payment and allocation are unreversed, reconciliation is matched,
    and the configured reversal-risk deadline has passed. Phase 7B contains no collateral
    call and cannot release an asset.
12. Refund execution and lender payout are unavailable. Refund and lender payable
    balances remain liabilities for later controlled settlement.
13. Canonical Protobuf remains the interface source. Allocation, excess, reversal,
    obligation, and release-eligibility evidence generate deterministic Solidity, Go,
    TypeScript, and Python projections.
14. Tests must cover provisional rejection, reconciliation hold, exact partial and full
    allocation, overpayment, duplicate/conflicting allocation, stale obligation version,
    asset mismatch, atomic journal failure, exact reversal restoration, replay, and
    collateral eligibility before/after the risk deadline and reversal.
15. This boundary authorizes no live provider, real financial data, on-chain debt
    mutation, collateral release, refund, payout, production credential, real fund,
    public testnet integration, or mainnet deployment.

## Consequences

- Provider finality, obligation authority, accounting posting, and collateral custody
  remain separate.
- The system can prove deterministic allocation, overpayment protection, and reversal
  restoration without pretending that an off-chain projection is canonical loan state.
- A later integration must define how settled provider value becomes the loan's actual
  settlement asset and how canonical debt changes atomically.
- Production chargebacks, payouts, refunds, collateral release, interest waterfalls, and
  multi-loan allocation remain separate milestones.
