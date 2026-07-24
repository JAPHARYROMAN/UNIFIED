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

## WS-PROTOCOL — Solidity foundation

- **Owns:** `protocol/`.
- **Produces:** interface and contract skeletons only in this milestone.
- **Consumes:** generated Solidity types and protocol invariants.
- **Invariants:** no mint path; no hidden superuser; checked authority.
- **Threats:** unsafe privilege; ABI or storage drift.
- **Acceptance:** Foundry and Solidity compiler checks pass.
- **Accountable:** Protocol Architecture Authority.

## WS-LEDGER — Accounting foundation

- **Owns:** `services/foundation-ledger/`.
- **Produces:** balanced posting kernel and migration skeleton.
- **Consumes:** finance schemas and accounting rules.
- **Invariants:** balanced entries; idempotency; immutable posted history.
- **Threats:** duplicate posting; unbalanced journals; currency mixing.
- **Acceptance:** unit tests and local PostgreSQL smoke test pass.
- **Accountable:** Accounting and Economic Risk Authority.

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

