# Unified

Unified is a governed, multi-language foundation for a decentralized credit and
financial coordination protocol. This repository implements the reviewed
foundation baseline, Phase 2 protocol-kernel/UFT milestone, and Phase 3 core
loan/accounting engineering milestone, plus the Phase 4A deterministic risk foundation:
shared schemas and bindings, append-only registries, scoped authority, a
fixed-supply token, genesis allocation and vesting controls, a fee-router
skeleton, signed tender and offer flow, atomic principal-only loans, balanced
loan accounting, deterministic chain projections, authenticated API boundaries,
multi-source oracle safety, cross-language interest and schedule calculations,
objective servicing transitions, engineering gates, and a reproducible local environment.

No production loan behavior, real token deployment, real funds, production keys,
external provider, bridge, oracle, or mainnet integration is included.

## Repository map

- `constitution/` — highest-authority constitutional specification.
- `docs/specifications/` — subordinate architecture and delivery specifications.
- `adr/` and `rfcs/` — accepted decisions and proposed cross-domain changes.
- `schemas/` — canonical Protobuf interfaces and frozen compatibility baselines.
- `protocol/` — Solidity foundation, kernel, UFT, core loan contracts, tests,
  reviewed ABIs, and local deployment scripts.
- `services/` — Go accounting, chain-projection, and core API kernels plus
  database migrations.
- `apps/` — TypeScript experience-layer skeletons.
- `models/` — Python model and simulation skeletons.
- `packages/generated/` — generated Solidity, Go, TypeScript, and Python types.
- `infrastructure/local/` — local-only EVM, PostgreSQL, broker, object storage,
  and mock-provider topology.
- `security/` — invariant, threat, risk, and assumption traceability.
- `tools/` and `scripts/` — conformance, generation, bootstrap, and smoke checks.

## Quick start

Prerequisites are pinned in `.mise.toml`. With the pinned tools available:

```powershell
corepack enable
pnpm install --frozen-lockfile
uv sync --frozen
pwsh ./scripts/generate.ps1
pwsh ./scripts/check-foundation.ps1
```

To run the isolated local infrastructure:

```powershell
pwsh ./scripts/local-up.ps1
pwsh ./scripts/smoke-local.ps1
pwsh ./scripts/local-reset.ps1
```

The local reset removes only Docker resources carrying the
`com.unified.environment=local` label.

## Baseline status

The v0.1 documents are approved as the implementation baseline for this
foundation. They are not production ratification, legal approval, an economic
promise, or an independent security audit. See
`docs/reviews/baseline-review-v0.1.md` and `docs/specifications/registry.yaml`.

The Phase 2 boundary and storage layouts are documented in
`docs/architecture/phase-2-kernel.md` and
`docs/architecture/phase-2-storage-layouts.md`. The Phase 3 boundary, flow, and
storage layouts are documented in `docs/architecture/phase-3-loan-accounting.md`
and `docs/architecture/phase-3-storage-layouts.md`. Their internal security
reviews authorize local and testnet engineering only; they do not authorize
production funds, token distribution, or public lending.
