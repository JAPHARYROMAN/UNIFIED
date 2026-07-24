# Phase 7B Internal Security Review

Date: 2026-07-24

Scope: synthetic obligation snapshots, final-payment eligibility, principal-only
waterfall, refundable excess, allocation accounting, lender payable, reversal
restoration, release-eligibility evidence, schemas, migration, and simulations.

## Reviewed properties

- Only exact matched `FINAL` evidence with zero difference and unmatched count allocates.
- Allocation binds payment, loan, obligation version, amount, waterfall, finality policy,
  reconciliation, and evidence; one payment cannot allocate twice.
- Principal plus refundable excess equals gross received units, and debt before equals
  principal plus debt after.
- Allocation journals clear unallocated payment, reduce principal receivable and lender
  claim, and preserve lender/refund liabilities without revenue.
- Accounting failure leaves obligation and allocation state unchanged and retryable.
- Reversal requires exact provider/payment/allocation binding, restores the original
  principal once, removes the same excess credit, and posts linked opposite journals.
- Release eligibility is evidence only, requires zero projected debt and every active
  allocation risk deadline, and becomes false after reversal.
- The projector imports no Solidity, chain, collateral, provider-network, token, refund,
  or payout component and cannot claim canonical loan state.

## Residual boundary

The obligation source, payment, provider, reconciliation, policies, and funds are
synthetic. Projected zero debt is not authoritative on-chain debt and cannot release
collateral or mark a loan terminal. Interest, fees, penalties, schedules, multiple
obligations, payouts, refunds, reserves, losses, delinquency changes, and production
chargeback operations are unavailable.

No live provider, real financial data, canonical debt mutation, production credential,
real fund, public testnet integration, or mainnet use is authorized.
