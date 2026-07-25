# Foundation Ownership and Workstream Charters

Ownership is role-based until remote teams are configured. One person may hold
multiple roles during local foundation work, but independent Security and Release
approval is mandatory before public testnet.

| Authority role | Foundation accountability |
|---|---|
| Program Authority | Scope, registry approval, backlog, escalation |
| Protocol Architecture Authority | Domain boundaries, ADRs, protocol interfaces |
| Security Authority | Threats, invariants, keys, security gates |
| Accounting and Economic Risk Authority | Money, ledger, UFT economics, reconciliation |
| Release Authority | CI, provenance, environments, release and rollback |

## WS-SPEC — Specification governance

- **Owns:** `constitution/`, `docs/specifications/`, `docs/reviews/`.
- **Produces:** registry, dependency map, baseline tags.
- **Consumes:** ADR decisions and review evidence.
- **Invariants:** authority hierarchy; immutable tagged history.
- **Threats:** silent semantic drift; stale references.
- **Acceptance:** registry hashes and cross-reference checks pass.
- **Accountable:** Program Authority.

## WS-SCHEMA — Shared interfaces

- **Owns:** `schemas/`, generated type projections.
- **Produces:** identifiers, money, asset, command, event, loan, finance, and
  governance contracts.
- **Consumes:** domain model, data architecture, protocol API.
- **Invariants:** one source schema; deterministic generation; explicit versions.
- **Threats:** incompatible wire changes; numeric ambiguity.
- **Acceptance:** Buf lint/build/breaking and generated-code freshness pass.
- **Accountable:** Protocol Architecture Authority.

## WS-PROTOCOL — Solidity protocol

- **Owns:** `protocol/`.
- **Produces:** foundation interfaces, kernel and registries, fixed-supply UFT,
  allocation and vesting controls, fee-router skeleton, signed offers, atomic
  funding, versioned core loan accounts, bounded liquidation execution, deterministic
  syndicate vaults, conserved lender-position rights, and synthetic-local payoff,
  refinance, lien-handoff, restructuring, funded-protection, guarantee, write-off,
  subrogation, and recovery controls.
- **Consumes:** generated Solidity types and protocol invariants.
- **Invariants:** no mint path; no hidden superuser; checked authority.
- **Threats:** unsafe privilege; ABI or storage drift.
- **Acceptance:** Foundry unit and stateful invariant tests, ABI compatibility,
  runtime-size, storage-layout, and Solidity compiler checks pass.
- **Accountable:** Protocol Architecture Authority.

## WS-LEDGER — Accounting and resolution foundation

- **Owns:** `services/foundation-ledger/`, `services/resolution-coordinator/`.
- **Produces:** balanced posting kernel, loan subledger, linked reversals,
  finality-gated loan accounting, identity/credit control evidence, Phase 9 resolution
  projections and coordination, protection, loss, recovery, solvency, reconciliation
  records, and migrations.
- **Consumes:** finance schemas and accounting rules.
- **Invariants:** balanced entries; idempotency; immutable posted history.
- **Threats:** duplicate posting; unbalanced journals; currency mixing.
- **Acceptance:** unit tests and local PostgreSQL smoke test pass.
- **Accountable:** Accounting and Economic Risk Authority.

## WS-INDEX — Chain events and projections

- **Owns:** `services/chain-indexer/`.
- **Produces:** canonical event ingestion, finality labels, tender and loan
  projections, reorg handling, replay, and rebuild.
- **Consumes:** reviewed contract ABIs and canonical event schemas.
- **Invariants:** projections are reproducible; orphaned events cannot remain canonical.
- **Threats:** reorg corruption; duplicate events; projection authority confusion.
- **Acceptance:** parent, replacement, finality, payment uniqueness, and rebuild tests pass.
- **Accountable:** Protocol Architecture Authority.

## WS-API — Core application boundary

- **Owns:** `services/core-api/`.
- **Produces:** authenticated tender, offer, loan, portfolio, and unsigned
  transaction-preparation boundaries.
- **Consumes:** canonical schemas and rebuildable projections.
- **Invariants:** deny by default; attributable commands; no private signing material.
- **Threats:** identity spoofing; command replay; signing-key exposure.
- **Acceptance:** authentication, attribution, validation, and preparation tests pass.
- **Accountable:** Security Authority.

## WS-RISK — Deterministic risk and servicing

- **Owns:** `protocol/src/risk/`, `services/risk-engine/`.
- **Produces:** approved oracle aggregation, interest calculations, repayment schedules,
  servicing/default predicates, deterministic synthetic underwriting rules, canonical
  payoff-component inputs, reserve stress haircuts, and modeled-loss fixture metrics.
- **Consumes:** immutable policy references, asset identities, and final observations.
- **Invariants:** deterministic debt; fresh approved prices; cure priority; explicit safe mode.
- **Threats:** oracle manipulation; calculation drift; premature default or liquidation.
- **Acceptance:** Foundry and independent Go vectors, ABI review, and risk traceability pass.
- **Accountable:** Accounting and Economic Risk Authority.

## WS-IDENTITY — Identity and restricted evidence

- **Owns:** public identity commitment interfaces and future restricted identity services.
- **Produces:** provider/schema approvals, subject-bound credential attestations,
  revocation evidence, consent controls, and privacy classifications.
- **Consumes:** provider authority, credential policy, legal basis, and retention rules.
- **Invariants:** no raw public identity; subject binding; validity; scoped uniqueness;
  prospective revocation.
- **Threats:** identity theft; synthetic identity; credential replay; public data leakage;
  malicious providers; insider access.
- **Acceptance:** commitment, binding, validity, revocation, privacy, and multi-wallet
  exposure tests pass.
- **Accountable:** Security Authority.

## WS-CUSTODY — Collateral custody

- **Owns:** `protocol/src/collateral/`.
- **Produces:** per-loan vaults, multi-asset custody, release gates, exposure records,
  reproducible direct/Dutch/English liquidation, auction escrow, and proceeds waterfalls.
- **Consumes:** canonical loans, asset registry identities, debt state, and risk policy.
- **Invariants:** custody existence; exact identity; no double release; borrower surplus rights.
- **Threats:** unsolicited callbacks; accounting drift; premature release; UFT reflexivity.
- **Acceptance:** mixed-bundle, release, concentration, liquidation, auction failure,
  proceeds conservation, and residual bad-debt tests pass.
- **Accountable:** Security Authority.

## WS-SYNDICATE — Funding and lender rights

- **Owns:** `protocol/src/syndicate/` and syndication accounting interfaces.
- **Produces:** bounded funding rounds, canonical aggregate loan accounts, ordered
  tranches, lender positions, voting checkpoints, and transfer cut-offs.
- **Consumes:** canonical assets, policy approvals, loans, emergency state, and final
  accounting events.
- **Invariants:** funding, shares, payments, votes, transfers, and refunds conserve.
- **Threats:** duplicate claims; waterfall bypass; accrued-right replay; encumbrance escape.
- **Acceptance:** funding, refund, priority, residual, lifecycle, transfer, vote, and
  accounting tests pass.
- **Accountable:** Protocol Architecture Authority.

## WS-PLATFORM — Toolchain and delivery

- **Owns:** `.github/`, `infrastructure/`, `scripts/`, `tools/`.
- **Produces:** pinned bootstrap, CI, local topology, evidence.
- **Consumes:** all workstream build and test requirements.
- **Invariants:** reproducibility; no real secrets; local-only isolation.
- **Threats:** supply-chain compromise; environment confusion; destructive reset.
- **Acceptance:** clean bootstrap and all foundation checks pass.
- **Accountable:** Release Authority.

## WS-SECURITY — Verification traceability

- **Owns:** `security/`.
- **Produces:** invariant catalog, risk and assumption registers, threat mappings.
- **Consumes:** formal verification and threat specifications.
- **Invariants:** every critical risk has an owner; evidence is attributable.
- **Threats:** unowned risk; narrative-only security claims.
- **Acceptance:** traceability and risk-owner checks pass.
- **Accountable:** Security Authority.
