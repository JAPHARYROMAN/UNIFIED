# Phase 5 Syndication, Tranches, and Lender Positions

Status: accepted implementation boundary; contracts not yet implemented

## Aggregate boundary

```text
SyndicateFactory
  -> creates and registers one SyndicateVault loan account
     -> escrows exact lender commitments
     -> disburses only after the funding threshold succeeds
     -> accepts canonical repayments and recoveries
     -> applies senior-first distribution / junior-first loss
     -> owns one PositionManager
        -> issues one position per funded commitment
        -> conserves shares through split, merge, and transfer
        -> checkpoints accrued cash and voting rights
        -> blocks unencumbered movement while pledged or frozen
```

The vault is the borrower-facing obligation and settlement boundary. The position
manager is the lender-facing rights boundary. Neither may create borrower debt
independently of funded commitments.

## Conservation model

```text
accepted commitments = borrower disbursement + exact refunds + authorized deductions
issued position shares <= activated funded principal
sum tranche outstanding principal = vault outstanding principal
final payment = position allocations + explicit residual
debt before loss = recognized loss + debt after loss
```

Authorized deductions are zero in the initial slice. Successful activation therefore
requires accepted commitments to equal borrower disbursement exactly.

## Waterfalls

- Principal payments and collateral recoveries apply by ascending seniority rank.
- Losses apply by descending seniority rank.
- Allocations inside one tranche are pro rata by current share units.
- Integer remainder goes to the final eligible position in the immutable iteration order
  so every payment is fully allocated and reproducible.
- A distribution belongs to the position owner at the distribution block. Transfer first
  checkpoints already accrued amounts to the seller, then moves future rights.

## Transfer states

```text
ACTIVE -> PLEDGED -> ACTIVE
ACTIVE -> FROZEN  -> ACTIVE
ACTIVE -> REDEEMED
ACTIVE -> MERGED
```

Only active, freely transferable positions can transfer or split. Merge requires the
same owner, loan, tranche, policy, and active state. Pledged and frozen rights continue
to receive contractual distributions but cannot be conveyed as unencumbered property.

## Bounded scope

The first implementation is principal-only and same-chain, matching the current core
loan boundary. It supports free or prohibited transfer policy only. Identity-gated
buyers, listings, interest cut-offs, borrower consent, external custody, position tokens,
and public market execution require later versioned policy and schema work.
