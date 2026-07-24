# Unified

Unified is a governed, multi-language foundation for a decentralized credit and
financial coordination protocol. This repository currently implements the
foundation milestone only: specifications, shared schemas, generated language
bindings, compile-tested skeletons, engineering controls, and a reproducible
local environment.

No production loan logic, UFT issuance path, real funds, production keys, or
mainnet integration is included.

## Repository map

- `constitution/` — highest-authority constitutional specification.
- `docs/specifications/` — subordinate architecture and delivery specifications.
- `adr/` and `rfcs/` — accepted decisions and proposed cross-domain changes.
- `schemas/` — canonical Protobuf interfaces and frozen compatibility baselines.
- `protocol/` — Solidity foundation skeletons.
- `services/` — Go financial-service skeletons and database migrations.
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

