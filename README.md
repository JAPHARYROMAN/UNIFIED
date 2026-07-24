# Unified

Unified is a governed, multi-language foundation for a decentralized credit and
financial coordination protocol. This repository implements the reviewed
foundation baseline, Phase 2 protocol-kernel/UFT milestone, Phase 3 core
loan/accounting engineering milestone, the Phase 4 deterministic risk/custody/liquidation
foundation, and the bounded Phase 5 syndication foundation:
shared schemas and bindings, append-only registries, scoped authority, a
fixed-supply token, genesis allocation and vesting controls, a fee-router
skeleton, signed tender and offer flow, atomic principal-only loans, balanced
loan accounting, deterministic chain projections, authenticated API boundaries,
multi-source oracle safety, cross-language interest and schedule calculations,
objective servicing transitions, multi-asset per-loan collateral custody, UFT exposure
controls, reproducible direct and auction liquidation, reconciled recovery accounting,
exact funding rounds, deterministic syndicate vaults, conserved lender positions,
senior-first principal waterfalls, checkpointed voting,
engineering gates, and a reproducible local environment.

No production deployment, real token deployment, real funds, production keys,
external provider, bridge, live oracle, or mainnet integration is included.

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

The Phase 4 risk, custody, and liquidation boundaries are documented in
`docs/architecture/phase-4a-risk-servicing.md`,
`docs/architecture/phase-4b1-collateral-custody.md`, and
`docs/architecture/phase-4b2-liquidation.md`. The bounded Phase 4 engineering exit
decision is recorded in `docs/reviews/phase-4-exit-review.md`; it is not production
ratification.

The Phase 5 syndication boundary and implementation are recorded in
`adr/0012-phase-5-syndication-and-position-boundary.md`,
`docs/architecture/phase-5-syndication.md`, and
`docs/architecture/phase-5-storage-layouts.md`. Its bounded engineering exit is recorded
in `docs/reviews/phase-5-exit-review.md`. This is not an authorization for production
lending or trading.

The accepted next engineering boundary for commitment-only identity attestations,
versioned underwriting decisions, and subject-level exposure reservations is recorded in
`adr/0013-phase-6-identity-underwriting-boundary.md`. Raw identity data, production
providers, and live unsecured lending remain prohibited.

The bounded Phase 6A implementation adds commitment-only provider, credential, decision,
and exposure controls plus synthetic underwriting and audit evidence. Its architecture
and layouts are documented in `docs/architecture/phase-6a-identity-underwriting.md` and
`docs/architecture/phase-6a-storage-layouts.md`; its bounded engineering exit is recorded
in `docs/reviews/phase-6a-exit-review.md`. It is not a production identity, underwriting,
or unsecured-credit system. ADR 0014 and
`docs/architecture/phase-6b-underwritten-activation.md` now govern the bounded Phase 6B
implementation: an atomic, synthetic, principal-only version-3 loan activation path with
policy-isolated exposure controls. It does not authorize real unsecured funds.
