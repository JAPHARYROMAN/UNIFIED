# Phase 4A Risk and Servicing Foundation

Status: implemented for local and testnet engineering; not approved for production use

## Boundary

Phase 4A provides deterministic inputs for later collateral and liquidation work. It
does not custody an asset, decide an LTV, initiate liquidation, conduct an auction, or
modify an active Phase 3 loan.

| Area | Component | Deterministic control |
|---|---|---|
| Oracle | `OracleRouter` | Approved bounded source set, one canonical quote, 18-decimal normalization, freshness, median, deviation filter, evidence hash, circuit breaker. |
| Interest | `InterestEngine` | Ray precision, actual/365 simple interest, floor/cap, benchmark age, round down. |
| Schedule | `ScheduleEngine` | Bullet, equal principal, annuity, interest-only, balloon, custom, holiday offset, final-item remainder. |
| Servicing | `ServicingEngine` | Objective due/grace/cure/default times, separated roles, monotonic evidence-bearing state nonce. |
| Service parity | `risk-engine/calculation` | Independent Go interest and schedule implementation using exact base-10 integers and the same canonical vectors. |

## Oracle decision path

```text
governance configures pair and approved adapters
  -> permissionless update reads enabled adapters
  -> reject failed, zero, future, stale, or non-normalizable observations
  -> sort normalized values and choose deterministic median
  -> exclude observations beyond maximum median deviation
  -> require the configured accepted-source quorum
  -> store price, oldest observation time, maximum round, and source evidence hash
  -> otherwise enter safe mode and make price() revert
```

For UFT, the Phase 4B deployment profile must configure the tokenomics baseline of at
least three independent sources, 30-minute maximum staleness, and 7.5% maximum
deviation. This repository uses mocks only.

## Calculation convention

```text
annual_interest = floor(principal * annual_rate_ray / 1e27)
period_interest = floor(annual_interest * elapsed_seconds / 31,536,000)
```

The order is normative. Combining the divisions into a different expression can change
rounding and is not compatible. Rates are capped at 1,000% annualized in the engine as a
defensive numerical bound; product policy must use a much lower approved cap.

Schedule principal always sums exactly to original principal. Equal division remainder
is placed in the last installment. Annuity power operations round down at every ray
multiplication, and the final installment absorbs remaining principal.

## Servicing authority

- `SERVICER_ROLE` configures a record and may accelerate only a delinquent obligation.
- `PAYMENT_FINALIZER_ROLE` applies final payments.
- `RISK_COUNCIL_ROLE` records cure evidence and confirms default only after the cure
  deadline.
- Any caller may evaluate time-based current, grace, and delinquency status.
- `DEFAULTED` alone exposes the `liquidationEligible` predicate for Phase 4B.

## Evidence

- Foundry tests cover fresh median aggregation, decimal normalization, provenance,
  staleness, deviation safe mode, recovery, fixed and capped variable interest,
  schedule remainder and holidays, annuity conservation, cure priority, objective
  default, and final repayment.
- Go tests reproduce the Solidity fixed-interest, capped-variable-interest,
  equal-principal remainder, holiday, and annuity-conservation vectors.
- Buf verifies the new risk schema is additive against the frozen v0.1 baseline.
