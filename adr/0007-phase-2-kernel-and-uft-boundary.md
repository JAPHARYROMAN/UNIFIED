# ADR 0007: Phase 2 Kernel and UFT Boundary

- **Status:** Accepted
- **Date:** 2026-07-24
- **Owner:** Protocol Architecture Authority
- **Reviewers:** Security Authority; Accounting and Economic Risk Authority; Release Authority

## Context

Phase 2 requires the smallest trusted contract kernel, fixed UFT supply, allocation
custody, registries, and a fee-routing skeleton without prematurely implementing loan
economics or authorizing production use.

## Decision

1. UFT is a non-upgradeable OpenZeppelin ERC-20/Permit token pinned to Contracts
   `5.6.1`. Exactly 1 billion UFT is issued in its constructor directly to nine distinct
   named destinations. There is no callable post-genesis issuance path.
2. The protocol root is a non-custodial immutable directory bound to its deployment
   chain and a reviewed chain-configuration hash.
3. Asset, policy, implementation-version, and loan identities are append-only.
   Deprecation or deactivation affects future bindings and does not rewrite historical
   identity.
4. Loan accounts are deterministic minimal clones of an explicitly registered
   implementation version. The version-1 account is an identity shell; Phase 3 behavior
   requires a new version.
5. Administrator, governance, and operational authority are separate deployment
   identities. Operational account grants expire after 30 days by default. Emergency
   actions are capability-scoped and cannot pause repayment or collateral top-up.
6. Generic allocation vaults are custody foundations, not authorization to distribute
   real tokens. Allocation-specific economic envelopes remain a mandatory pre-distribution
   work item.
7. Phase 2 public ABIs are reviewed snapshots. An interface change requires an ADR,
   regenerated snapshots, compatibility analysis, and security review.

## Consequences

- Existing deployed identities cannot be edited in place; changes use new semantic or
  implementation versions.
- The canonical UFT contract cannot be upgraded or recapitalized by minting.
- A future production chain decision remains deferred under ADR 0006.
- No real token deployment, public distribution, mainnet transaction, or production key
  is authorized by this decision.
- The evidence required to change this boundary is recorded in the Phase 2 internal
  security review, storage-layout document, invariant tests, and deployment dry run.
