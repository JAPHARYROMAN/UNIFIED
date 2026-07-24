# ADR 0011: Phase 4B2 Reproducible Liquidation

Status: accepted for local and testnet engineering

Date: 2026-07-24

## Context

Phase 4B1 intentionally exposed only a mechanical collateral-disposition capability.
Binding an address to that capability without independent eligibility, price, auction,
settlement-finality, waterfall, and accounting controls would permit arbitrary seizure.

## Decision

1. A liquidation case is created only by the risk council after the canonical servicing
   engine reports default and the loan still has outstanding debt.
2. The case binds the loan's pre-committed policy-set hash, one collateral item and
   quantity, a trigger snapshot, a route, a canonical fresh oracle observation, a
   deterministic valuation, bounded costs and incentive, and immutable timestamps.
3. Supported routes are fixed-price direct sale, linearly descending Dutch auction,
   and ascending English auction. ERC-721 lots use the English route without special
   custody exceptions. Partial quantities are allowed for fungible and ERC-1155 assets.
4. One collateral item may have only one active liquidation case. Completion,
   cancellation, or safe failure clears the active-case lock.
5. Direct and Dutch buyers provide exact reviewed settlement-token units atomically.
   English bids are escrowed in the same token; outbid and failed-auction refunds use a
   pull balance so a hostile recipient cannot block later bids or settlement.
6. Execution rechecks default eligibility, outstanding debt, collateral custody, and
   the exact canonical oracle observation. Stale or replaced evidence blocks transfer.
7. Proceeds follow a deterministic waterfall: bounded execution costs, bounded
   incentive, secured principal claim, then borrower surplus. The lender payment calls
   the canonical loan account, so it reduces debt before any later recovery route.
8. Gross proceeds must equal all allocations, and debt before settlement must equal the
   secured claim paid plus explicit residual bad debt.
9. Deployment and governance binding are separate actions. The deployment script cannot
   configure the collateral manager. Governance may bind the reviewed engine once.

## Consequences

- Failed, expired, stale, cured, or repaid cases do not move collateral.
- The same liquidation inputs and timestamps reproduce the price and waterfall.
- The current milestone does not implement lender in-kind claims, negotiated recovery,
  off-chain collateral, insurance recovery, or legal write-off. Residual bad debt remains
  visible and legally outstanding until a later recovery/write-off policy is implemented.
- No production asset, provider, key, auction, fund, or mainnet deployment is authorized.
