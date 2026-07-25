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
policy-isolated exposure controls. Its bounded engineering exit is recorded in
`docs/reviews/phase-6b-exit-review.md`. It does not authorize real unsecured funds.

The Phase 7A boundary and bounded implementation are recorded in
`adr/0015-phase-7a-payment-ingress-and-reconciliation-boundary.md` and
`docs/architecture/phase-7a-payment-ingress-reconciliation.md`, with data layouts in
`docs/architecture/phase-7a-data-layouts.md`. The implementation is limited to synthetic,
local payment ingress, provisional/final accounting, quarantine, and reconciliation.
Its bounded engineering exit is recorded in `docs/reviews/phase-7a-exit-review.md`. Live
providers, real financial data, loan allocation, refunds, payouts, collateral release,
and real funds remain prohibited.

The Phase 7B boundary and synthetic implementation are recorded in
`adr/0016-phase-7b-final-payment-allocation-boundary.md` and
`docs/architecture/phase-7b-final-payment-allocation.md`. They provide a synthetic
principal-only allocation, overpayment-credit, accounting-reversal, and non-executing
collateral-eligibility proof. Canonical loan mutation, refunds, payouts, collateral
release, live providers, and real funds remain prohibited. Its bounded engineering exit
is recorded in `docs/reviews/phase-7b-exit-review.md`.

The Phase 7C boundary and bounded implementation are recorded in
`adr/0017-phase-7c-canonical-external-settlement-boundary.md` and
`docs/architecture/phase-7c-canonical-external-settlement.md`. It permits implementation
of a synthetic mature-only, exact-token gateway and recoverable canonicalization saga,
with layouts in `docs/architecture/phase-7c-data-layouts.md`. Canonical mutation waits
through the reversal deadline, delivers the registered loan token, and atomically pays
the lender and refunds excess. The source provider asset and target token remain
explicitly distinct under a fixed one-to-one first-slice conversion. Reserve-backed
early settlement, cross-denomination FX, live providers, automatic collateral release,
and real funds remain prohibited. The supported durable projection path is one
exact-snapshot, replay-safe SQL success transaction; reorganization authority retains its
complete signed receipt/finality provenance across restart. The local chain indexer
enforces canonical receipt/Merkle-Patricia encoding, same-header proof enrichment,
monotonic signed observations, and aggregate input limits. Its pinned Ed25519 observer is
a synthetic local/test trust root, not EVM consensus or a production light client.
Service executables remain local skeletons without provider, EVM RPC, broker, or
production ledger-listener wiring. Its bounded engineering exit is recorded in
`docs/reviews/phase-7c-exit-review.md`; live-provider, production-chain, reserve-backed,
public-network, collateral-release, and real-fund authority remain prohibited.

The implemented Phase 8 local engineering boundary is recorded in
`adr/0018-phase-8-cross-chain-and-wrapped-uft-boundary.md` and
`docs/architecture/phase-8-cross-chain-protocol.md`, with authoritative layouts in
`docs/architecture/phase-8-data-layouts.md`. The bounded implementation runs a complete
synthetic/local two-domain flow with one canonical home authority, typed at-most-once
messages, transport-only provider failover, fully backed and exposure-capped wUFT,
bounded satellite custody/disbursement/repayment, destination-tombstone recovery, and a
typed cancellation-accounting path.

The internal security decision is recorded in
`security/reviews/phase-8-internal-review.md`, and the authoritative live-evidence,
restart, reconciliation, and reset contract is documented in
`docs/architecture/phase-8-local-release-evidence.md`. Deterministic Protobuf
derivatives cover Solidity, Go, TypeScript, and Python. The durable release commitment
binds exactly 49 SQL tables, balanced evidence-linked journals, sixteen
content-addressed authenticated-inclusion objects, exact replay behavior, state
rehydration across service restart, matched cross-domain reconciliation, and a
reset-controlled local topology. `UNI-REVIEW-011` remains `TODO` for the separate
bounded engineering exit.

Phase 8 does not select or authorize a production home or satellite chain, consensus
or light-client system, bridge provider, relayer, RPC, oracle, identity provider,
signing service, HSM/KMS custody, public testnet, mainnet, production key, real UFT,
real collateral, live loan, treasury asset, or real fund. Every such production
decision requires separate architecture, threat-model, operational-control,
key-ceremony, due-diligence, and independent-review authority.
