# Phase 5 Internal Security Review

Date: 2026-07-24

Scope: `SyndicateFactory`, `SyndicateVault`, `PositionManager`, the syndication schema,
waterfall model, accounting adapter, migration, deployment script, and Phase 5 tests.

## Reviewed properties

- INV-FUND-001/002/003: exact escrow is conserved, activation below minimum is rejected,
  and round plus tranche capacities prevent overfunding.
- INV-FUND-004/005: one pending position is issued per funded commitment and activated
  share units equal accepted principal.
- INV-FUND-006/007: every payment is fully allocated senior-first, with deterministic
  per-tranche pro rata rounding and one explicit residual receiver.
- INV-FUND-008/009/010: transfer preserves rights, enforces the immutable transfer
  policy, checkpoints seller accrual, and moves only future cash and voting rights.
- INV-FUND-011: pledged and frozen positions retain economic rights but cannot move as
  unencumbered property.
- INV-PAY-003/007: unique payment IDs reduce aggregate debt once and exact-token balance
  deltas equal recorded settlement.
- INV-NUM-004: floor rounding and the residual rule are documented and tested.

## Threat checks

- Deterministic clone predictions and the one-time initializer bind each manager to one
  vault and one loan identity.
- The canonical asset and approved policy registries gate creation; emergency authority
  can pause new syndicate creation but cannot pause repayment.
- Commit, finalize, refund, repay, distribution, and withdrawal external-token paths use
  reentrancy guards and exact balance checks.
- Lifetime limits of eight tranches and 64 positions bound loops used at activation and
  distribution.
- Split and merge store position voting power explicitly, preventing repeated fractional
  rounding from creating votes.
- Split cannot change owner, so it cannot bypass transfer evidence or the economic
  cut-off. Transfer events include the deterministic outstanding claim at that cut-off.
- A fixed residual position prevents a lender from redirecting payment dust by splitting
  or changing iteration order.
- Finality-gated accounting rejects unbalanced distributions, provisional events,
  conflicting idempotency keys, and same-party transfers.

## Residual boundary

This is an internal engineering review, not an independent audit or production approval.
The on-chain loss function is a deterministic preview only; no write-off authority or
borrower-debt mutation exists. Open-round commitments cannot be withdrawn by lenders.
Public trading, paid transfer settlement, identity and jurisdiction checks, interest,
live provider data, and unbounded pools remain unsupported. No production funds, keys,
or mainnet deployment are authorized.
