# Phase 7B Final Payment Allocation and Reversal

Status: implemented for synthetic local engineering; not canonical loan authority

## Authority flow

```text
Phase 7A FINAL payment + exact matched reconciliation
                         |
                         v
versioned obligation snapshot + immutable waterfall/finality policies
                         |
                         v
synthetic allocation projector
  principal = min(final units, outstanding principal)
  excess    = final units - principal
                         |
                         v
atomic balanced allocation journals
  clear unallocated payment
  reduce principal receivable
  reduce lender principal claim
  create lender repayment payable
  preserve excess as refund payable

authenticated provider reversal
                         |
                         v
linked opposite journals + exact projected obligation restoration
```

The projector does not call `CoreLoanAccount`, `LoanRegistry`, a collateral contract, a
token, a provider, or a payout service.

## First-slice waterfall

The product is principal-only:

```text
gross final payment = principal allocation + refundable excess
principal allocation = min(gross final payment, outstanding principal)
projected debt after = outstanding principal - principal allocation
```

All values are canonical positive integer units in one exact asset. A zero allocation,
foreign denomination, stale obligation version, unmatched reconciliation, or provisional
payment fails without state or journal mutation.

## Accounting

Allocation uses two atomic journals.

For payment allocation:

```text
Debit  9120 Unallocated Loan Payment      gross units
Credit 1310 Principal Receivable          principal units
Credit 2150 Refund Payable                excess units, when nonzero
```

For lender claims:

```text
Debit  2310 Lender Principal Claims       principal units
Credit 2130 Lender Repayment Payable      principal units
```

A reversal posts linked opposites for every allocation journal in one batch. It does not
edit or delete the original. Phase 7A separately reverses provider-settlement journals.
Refund and lender payable execution are unavailable.

## Idempotency and concurrency

- Allocation identity binds payment, loan, obligation version, amount, waterfall policy,
  finality policy, and evidence.
- Payment ID is globally single-allocation inside the projector.
- Loan obligation updates use exact aggregate-version compare-and-set semantics.
- The journals and projector state commit only after all validation and posting succeed.
- Replay returns the original result; conflicting reuse fails.
- Reversal binds the allocation and can be recorded once.

## Reversal restoration

For one allocation:

```text
post-reversal projected debt
= pre-allocation projected debt

restored principal = originally allocated principal
removed refund credit = originally recorded excess
```

The original waterfall is reused; no current policy can reinterpret a historical
allocation. Payout, refund, interest recalculation, delinquency, reserve coverage, and
canonical loan reopening remain unavailable.

## Collateral-release evidence

The first slice may compute, but never execute, release eligibility:

```text
projected debt == 0
AND payment == FINAL
AND allocation not reversed
AND reconciliation matched exactly
AND now >= reversal-risk deadline
```

This evidence is insufficient for production custody because projected debt is not the
canonical on-chain obligation. A future adapter must recheck canonical state and custody
policy atomically.

## Acceptance properties

- `INV-PAY-002` and `INV-PAY-003`: only matched final evidence allocates and one payment
  allocates at most once.
- `INV-INT-011`: the immutable principal-then-excess waterfall is deterministic.
- `INV-INT-012` and `INV-PAY-010`: excess becomes refund payable and cannot become
  revenue or exceed received value.
- `INV-PAY-005`: reversal restores exactly the originally allocated principal and
  payable components once.
- `INV-PAY-006`: no collateral call exists; release eligibility remains false before the
  reversal deadline and after reversal.
- `INV-ACC-002`, `INV-ACC-003`, and `INV-ACC-004`: journals are balanced, immutable,
  linked, atomic, and idempotent.
- `INV-PAY-011`: an unmatched reconciliation blocks allocation.

## Implemented slice

- a versioned synthetic obligation projector with exact compare-and-set allocation;
- deterministic principal-then-refundable-excess arithmetic;
- separate atomic allocation/lender-claim journals and linked reversal batches;
- exact provider/payment reversal binding and idempotent restoration;
- non-executing collateral-release eligibility across every unreversed payment risk
  deadline on the projected loan;
- additive allocation/reversal/release Protobuf and deterministic four-language bindings;
- append-only SQL evidence, synthetic fault simulations, and an internal security review.

## Explicitly unavailable

- live providers or real financial data;
- on-chain loan mutation or external settlement conversion into a token;
- interest, fee, penalty, cost, schedule, or multi-loan waterfalls;
- lender payout, borrower refund, withdrawal, or disbursement;
- collateral release or canonical terminal marking;
- chargeback fees, reserves, insurance, losses, or delinquency changes;
- production credentials, real funds, public testnet, or mainnet deployment.
