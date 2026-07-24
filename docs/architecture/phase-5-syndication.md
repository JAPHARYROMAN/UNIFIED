# Phase 5 Syndication and Lender Positions

Status: implemented for local and testnet engineering; not approved for production funds

## Creation and funding

```text
borrower fixes round, policy set, settlement asset, and ordered tranches
  -> SyndicateFactory derives the loan ID and deterministic clone addresses
  -> PositionManager and SyndicateVault clones initialize once
  -> LoanRegistry records the vault as the canonical loan account
  -> lenders escrow exact settlement units against unique commitment IDs
  -> each commitment creates one pending position with equal share units
  -> target reached early, or close time reached
     -> below minimum: terminal failure and exact pull refunds
     -> at/above minimum: activate positions and disburse exact accepted principal
```

The settlement asset must be active in the canonical asset registry and use exact ERC-20
balance semantics. The approved policy-set hash, agreement hash, borrower, minimum,
target, maximum, timestamps, maturity, and tranche capacities are fixed at creation.
Tranche capacities sum to maximum funding. A round can activate early only after target
funding or after its close time when minimum funding has been met.

Commitments are intentionally irrevocable until borrower cancellation, round failure, or
activation. This avoids commitment churn consuming the bounded 64-position capacity.
There is no lender withdrawal path from an open round.

## Authoritative components

| Component | Authority |
|---|---|
| `SyndicateFactory` | Validates registry dependencies and policies, creates deterministic clones, registers the canonical loan |
| `SyndicateVault` | Holds commitment escrow, disburses principal, owns aggregate debt, accepts unique repayments, applies the payment waterfall |
| `PositionManager` | Owns tranche balances, position shares, accrued distributions, encumbrances, and voting checkpoints |

The factory is non-upgradeable and has no mutable storage. Clone implementations disable
their own initializers; only fresh clone storage can initialize.

## Conservation and priority

For an activated round:

```text
accepted commitment units = borrower disbursement
issued position shares     = activated funded principal
sum tranche principal      = vault outstanding principal
finalized payment          = sum position allocations
```

Payments apply by ascending seniority rank. Within a tranche:

```text
position allocation = floor(payment × position shares / tranche shares)
explicit remainder  = payment - sum(floored allocations)
```

The remainder belongs to the tranche's first issued, nonzero position. The residual
identity follows a merge, so split order and array position cannot redirect rounding.
Losses can be previewed by descending seniority rank, but this milestone does not mutate
borrower debt for a legal write-off. Loss recognition, forgiveness, insurance, and
reserve recovery require a later accepted accounting and authority boundary.

## Position lifecycle

Pending positions activate atomically with borrower disbursement. Active positions may:

- split under the same owner without changing total shares or voting power;
- merge only under one owner and within one tranche;
- transfer only under an immutable freely-transferable policy;
- become pledged or risk-council frozen, which blocks conveyance but not distributions;
- claim accrued settlement units through pull withdrawals; and
- redeem after their tranche principal reaches zero.

Transfer first moves already accrued distributions to the seller's withdrawable balance,
then changes the owner and moves only future distributions and voting power. Voting power
is stored per position and checkpointed by block, so fractional split and merge rounding
cannot create reusable votes. Cross-owner movement must use the transfer path and its
evidence hash; split cannot bypass that cut-off. Each transfer event also records the
position's deterministic outstanding claim units at the cut-off for accounting.

## Phase 4 compatibility

The vault exposes the existing borrower, lender, terms, debt snapshot, repayment, and
repayment-allowed surface used by the Phase 4 liquidation engine. Its reported lender is
the `PositionManager`; this is an aggregate routing identity, not an additional claim.
Liquidation recovery therefore enters the vault once and uses the same senior-first
waterfall as a borrower payment.

## Accounting and interface boundary

`syndication.proto` is the canonical cross-language contract for rounds, commitments,
tranches, positions, transfers, and finalized distributions. Generated Solidity, Go,
TypeScript, and Python projections are derivatives.

The foundation ledger posts only final events. It records commitments, activation and
disbursement, exact refunds, conserved position transfers, and distributions whose
position allocations equal the finalized payment. Financial entries carry lender and
tranche dimensions, while immutable control records retain position identity. Transfers
move the outstanding claim at the recorded cut-off while retaining share units as control
evidence. Migration `000004` adds the tranche dimension and immutable commitment and
transfer evidence tables.

## Bounded deployment scope

The implementation permits at most eight tranches and 64 lifetime position IDs per
vault. It is principal-only, same-chain, and non-tokenized. It does not provide public
listings, paid secondary settlement, eligible-buyer identity, jurisdiction controls,
borrower-consent workflows, interest claims, off-chain commitments, or production
configuration. `DeployPhase5` deploys implementations and a factory only; it creates no
round and authorizes no production use.
