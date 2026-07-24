# ADR 0010: Phase 4B1 Collateral Custody Boundary

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Protocol Architecture Authority
- **Reviewers:** Security Authority; Accounting and Economic Risk Authority; Release Authority

## Context

Liquidation cannot be authorized until custody existence, asset identity, release, and
exposure conservation are independently enforced. A per-loan vault also limits the blast
radius of a manager or token failure.

## Decision

1. Every collateralized loan receives a deterministic, dedicated `CollateralVault`.
   The borrower creates the vault, approves it directly, and deposits through the
   `CollateralManager`.
2. The vault supports native asset, standard ERC-20, ERC-721, and ERC-1155 custody.
   Mixed bundles are multiple canonical items in the same loan vault.
3. NFT callbacks are accepted only during an exact vault-initiated transfer. Batch and
   unsolicited callbacks revert. ERC-20 custody and release require exact balance deltas.
4. Asset identity and active status come from the Phase 2 asset registry. Collateral
   kind, enabled status, and UFT classification are risk-council configuration; identity
   and kind cannot be rewritten after first configuration.
5. Borrower release requires canonical terminal loan state, zero outstanding principal,
   the original borrower as recipient, and a nonzero journal reference. A collateral
   unit cannot be released or disposed twice.
6. Only a single governance-bound liquidation engine may call the disposition path.
   Phase 4B1 tests that mechanical path, but does not authorize eligibility, price,
   proceeds, or an auction; those remain Phase 4B2.
7. UFT collateral is always recognized by its canonical asset and token identity. It
   cannot be reconfigured to bypass the 0.25% single-loan and 0.50% borrower supply
   concentration limits. UFT-backed debt must be bound beneath an attested protocol
   ceiling before deposit.
8. UFT debt capacity cannot be freed until debt is zero, the loan is terminal, and no
   UFT remains controlled for the loan.

## Consequences

- Users approve a known per-loan vault rather than a global manager.
- Fee-on-transfer, rebasing, and nonstandard ERC-20 collateral is unsupported.
- Off-chain collateral, substitutions, LP positions, and tokenized real-world assets
  require separate adapters and policy evidence.
- No production collateral, liquidation, live oracle, auction, key, fund, or mainnet
  deployment is authorized.
