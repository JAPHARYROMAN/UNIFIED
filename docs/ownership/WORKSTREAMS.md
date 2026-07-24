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
  funding, versioned core loan accounts, and bounded liquidation execution.
- **Consumes:** generated Solidity types and protocol invariants.
- **Invariants:** no mint path; no hidden superuser; checked authority.
- **Threats:** unsafe privilege; ABI or storage drift.
- **Acceptance:** Foundry unit and stateful invariant tests, ABI compatibility,
  runtime-size, storage-layout, and Solidity compiler checks pass.
- **Accountable:** Protocol Architecture Authority.

## WS-LEDGER — Accounting foundation

- **Owns:** `services/foundation-ledger/`.
- **Produces:** balanced posting kernel, loan subledger, linked reversals,
  finality-gated loan accounting, and migrations.
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
  and servicing/default predicates.
- **Consumes:** immutable policy references, asset identities, and final observations.
- **Invariants:** deterministic debt; fresh approved prices; cure priority; explicit safe mode.
- **Threats:** oracle manipulation; calculation drift; premature default or liquidation.
- **Acceptance:** Foundry and independent Go vectors, ABI review, and risk traceability pass.
- **Accountable:** Accounting and Economic Risk Authority.

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
