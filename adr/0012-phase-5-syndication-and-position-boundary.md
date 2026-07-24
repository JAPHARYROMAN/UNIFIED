# ADR 0012: Phase 5 Syndication and Lender-Position Boundary

Status: accepted for local and testnet engineering

Date: 2026-07-24

## Context

The Phase 3 account has one lender and sends every principal payment directly to that
lender. Adding multiple lenders through parallel balances or freely transferable tokens
would risk issuing claims above funded principal, duplicating transferred rights,
misallocating accrued payments, and violating tranche priority.

## Decision

1. Each syndicated loan uses a deterministic, non-upgradeable `SyndicateVault` as its
   canonical loan account. A factory registers the vault before commitments begin.
2. The vault accepts only one registry-approved exact-transfer ERC-20 settlement asset.
   Commitment IDs are unique, funds remain escrowed until finalization, and the same
   units cannot back two commitments.
3. A round binds minimum, target, and maximum funding, open/close timestamps, borrower,
   agreement hash, policy-set hash, tranche definitions, and refund rules before opening.
   Activation fixes funded principal to the exact accepted commitments.
4. A failed or cancelled round marks the loan terminal and gives every funded commitment
   an exact pull refund. No borrower disbursement or lender position is created.
5. A successful round atomically disburses accepted principal to the borrower. Each
   commitment can then activate exactly one position whose share units equal its funded
   principal units. Aggregate issued shares can never exceed funded principal.
6. One non-tokenized `PositionManager` per vault is authoritative for tranche and position
   rights. This milestone does not create an ERC-20, ERC-721, or ERC-1155 representation.
7. Tranche seniority and transfer policy are immutable after funding opens. Principal
   repayment and recovery distribute senior-first; recognized loss absorbs junior-first.
   Within a tranche, allocations are deterministic and pro rata with an explicit residual
   rule. At most eight tranches and 64 positions per tranche bound settlement work.
8. A position may be issued, split, merged, freely transferred where its immutable policy
   permits, pledged, frozen, released, claimed, and redeemed. Share conservation is
   checked on every mutation.
9. Transfer checkpoints all accrued distributions to the seller at one block cut-off.
   Only future distributions and voting power move to the buyer. Historical owner voting
   power remains queryable and cannot be reused after transfer.
10. Pledged or frozen positions cannot transfer, split, merge, or redeem as unencumbered
    property. Pledge release cannot change total economic rights.
11. The vault exposes the Phase 4 debt/repayment interface. Liquidation recovery pays the
    vault once; the vault reduces aggregate debt and applies the same tranche waterfall.
    Its lender identity is the position manager, not an additional economic claim.
12. Chain events and the Unified ledger separately reconcile commitments, disbursement,
    issued shares, distributions, transfers, losses, refunds, and residual amounts.

## Consequences

- Phase 5 changes ownership and priority of lender rights without changing borrower debt.
- The bounded position count favors reviewable deterministic settlement over unbounded
  public-pool scalability. A future pooled design requires a new accumulator model and ADR.
- Eligible-buyer identity, jurisdiction restrictions, borrower-consent workflows, public
  listings, tokenized positions, interest-bearing claims, and off-chain commitments remain
  deferred until their Phase 6/secondary-market policies exist.
- No production funds, live identity/provider data, public market, key, or mainnet
  deployment is authorized.
