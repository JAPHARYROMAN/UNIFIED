# Phase 9 Atomic Refinance Boundary Review

Decision: PASS

Review date: 2026-07-26

Reviewed candidate commit: `8c873bd3023fda849a1a0db320c0e72044bd9e27`

Reviewed parent commit: `f2ba8c2d18eb61109df78ed5bf32bd526679ffbb`

Implementation author: `/root`

Architecture reviewer: `/root/phase9_boundary_final_arch_review`

Security reviewer: `/root/phase9_payoff_recheck_security`

Tooling and gate reviewer: `/root/phase9_boundary_full_gate`

## Scope

This review accepts ADR 0021 and the synthetic-local Phase 9 refinance
specification, schema, risk, evidence, and compatibility boundary. It does not
accept or activate successful refinance business logic. `UNI-REFI-001` and
`UNI-REFI-002` remain `TODO`, the provisional `P9-REFI-001` package is absent
from the implementation-checkpoint registry, and unopened mutators retain their
fail-closed bodies.

The reviewed boundary is restricted to chain `31337`, synthetic assets and
parties, disposable local keys and state, mocked providers, and
`contains_real_value=false`. It grants no Phase 8, public-network, production,
live-fund, legal, custody, insurance, recovery, or external-provider authority.

## Reviewed decisions

- The request sequence is acyclic: replacement identity and predicted clones,
  internal quote, refinance identity, then refinance-bound creation identity.
- The borrower-authenticated coordinator transaction atomically creates or
  validates the old bootstrap fixture, transfers exact synthetic collateral
  into custody, records positions and liens, issues the quote, and creates only
  dormant replacement clones.
- The existing old-loan nonce word provides a checked single-active lock without
  a new slot. Cancellation or expiry terminalizes the quote, funded exits remain
  locked through `REFUNDABLE`, and exact terminal replay remains inert.
- Execution atomically consumes the quote, pays exact canonical recipients,
  closes debt, marks the old loan terminal in `LoanRegistry`, hands off every
  senior lien, issues owner-funder replacement positions, activates replacement
  debt, clears attributed escrow, and records reconstructible terminal evidence.
- Old position and checkpoint values remain nominal issuance history. Every
  present rights consumer must join the canonical registry/account debt; old
  effective claim, voting, payment, and authorization rights are zero after
  terminal payoff.
- The deployment evidence permits only nonce-ordered top-level `CREATE`
  transactions followed by the one predeclared factory-role initialization.
  Late or post-hoc repair is rejection evidence, not authority.
- Protobuf field 24 is the additive corroborative raw 20-byte replacement
  position-manager address. Protobuf remains the source and all four generated
  targets are deterministic.
- ABI additions have exact ownership: `RefinanceCoordinator` owns
  `RefinanceStateTransitioned` and `UnknownFundingCommitment(bytes32)`;
  `LienRegistry` owns `UnknownLienHandoff(bytes32)`. No selector or storage
  addition is authorized.
- Checkpoint schema v2 preserves the accepted Payoff package, pins its historical
  identity, enforces method-level monotonic activation, and rejects the
  provisional refinance package until its exact evidence paths are frozen.

## Bound evidence

- Acceptance inventory: exactly 80 unique `P9R-*` rows.
- Current control-bundle hash:
  `sha256:c7b547b17af4d5e9f9afb9410c0cef12e25762462982f35176aa43918ddd4f9d`.
- Refinance descriptor hash:
  `d18e2784420ec0665fbd5da1ed9a69abe79f08e25d75b2dfdc66a32fee10668b`.
- Historical Payoff reviewed commit:
  `b1a510685fec84539a64cc81725a2ed51acbe489`.
- Historical Payoff source, source-set, dependency, implementation-evidence,
  ABI, storage, review hashes, reviewers, and PASS status are unchanged.

## Verification

The exact reviewed candidate completed:

- canonical foundation gate: PASS, exit `0`, 72.461 seconds;
- Python suites: 296 plus 45 tests;
- focused boundary suites: 143 tests;
- Node checkpoint and warning-policy suite: 24 tests;
- strict mypy: 44 files;
- ABI compatibility: 66 contracts;
- storage compatibility: 14 contracts, 1 implemented;
- Buf lint, build, and breaking-against-parent checks;
- Phase 9 schema, boundary, checkpoint, generated-artifact, privilege, privacy,
  deployment-pin, contract-size, and documentation controls; and
- generated freshness: 54 tracked generated files, zero changed and zero new.

The worktree was clean before and after each exact-commit review. The compiler
reported only the classified OpenZeppelin keyword, frozen-stub mutability, and
existing contract-size warnings. Forge was unavailable in the local environment;
the canonical gate emitted its expected warning and skipped Forge while the
Solidity ABI/storage compilers and compatibility controls passed. GitHub CI must
run the pinned Foundry suite before merge.

## Reviewer verdicts

- Architecture: PASS; no remaining P0, P1, or P2 finding.
- Security: PASS; authority, value conservation, replay, exit liveness,
  historical-right extinction, local-only isolation, and risk ownership verified.
- Tooling: PASS; exact ABI ownership, schema generation, checkpoint history,
  control hashing, storage compatibility, and fail-closed provisional activation
  verified.

Any implementation, evidence, deployment, or checkpoint bytes added after the
reviewed candidate require a new exact-commit review. This review record is
metadata about the accepted boundary and cannot be used as implementation or
production authorization.
