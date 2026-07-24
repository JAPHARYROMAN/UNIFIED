# ADR 0008: Phase 3 Core Loan and Accounting Boundary

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Protocol Architecture Authority
- **Reviewers:** Security Authority; Accounting and Economic Risk Authority; Release Authority

## Context

Phase 3 must prove one complete, same-chain loan lifecycle without importing the
collateral, oracle, liquidation, cross-chain, fiat, or production-provider risks assigned
to later phases.

## Decision

1. The first loan product is principal-only, zero-interest, same-chain, single-lender,
   and settled in one active registry-approved ERC-20. Fee-on-transfer, rebasing, native,
   collateralized, syndicated, and cross-chain assets are outside this boundary.
2. A borrower publishes a tender. A lender signs an EIP-712 offer with a nonce and
   expiry. Acceptance consumes the offer and nonce once. Counteroffers retain explicit
   parent lineage.
3. The borrower invokes one factory transaction that selects the offer, verifies the
   policy set and asset, deploys and registers the version-2 loan account, transfers
   principal and fee, activates the account, and fulfills the tender. Any failure reverts
   the complete transaction.
4. The loan account stores the accepted agreement snapshot, parties, policy-set hash,
   principal obligation, and orthogonal state vector. A unique payment ID reduces
   principal once. Full principal repayment closes the account and marks the loan
   registry terminal.
5. Chain projections are reproducible derivatives. Reorganizations replace orphaned
   projections. Only final chain events may create authoritative accounting journals.
6. Loan activation posts matched borrower principal receivable and lender principal
   claim entries. A settled origination fee posts the received protocol asset and
   revenue. Principal repayment reduces the matched obligation and claim. Journals are
   balanced, immutable, idempotent, and corrected only by linked reversal.
7. Core APIs authenticate every route and return unsigned, expiring transaction
   preparations. They never receive, persist, or return private signing keys.
8. Public Phase 3 contract ABIs are reviewed snapshots. Interface changes require
   compatibility review and a new ADR when semantics change.

## Consequences

- Smart-contract lender signatures under ERC-1271 are deferred; this version accepts
  ECDSA account signatures only.
- Indexer latency includes the configured finality depth before ledger posting.
- The local in-memory ledger and mock API boundaries demonstrate invariants; production
  persistence, identity, custody, and operations remain prohibited.
- Interest, collateral, default, liquidation, refinancing, fiat, bridge, oracle, and
  provider behavior require later-phase decisions and cannot be inferred from this ADR.
- No real funds, production keys, external providers, mainnet deployment, or production
  authorization is created by this decision.
