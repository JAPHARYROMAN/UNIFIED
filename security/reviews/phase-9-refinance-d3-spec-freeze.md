# Phase 9 D3 Specification-Freeze Review

Decision: PASS

Review date: 2026-07-27

Reviewed candidate commit: `5d076f5042063f2ef5c58602ee5c047e2a86c913`

Reviewed parent commit: `8b4aadf7c286321aa6c7eea808b670c36ae568c2`

Reviewed tree: `fb4783a756321cebbb8ca473c022a8138c73aa9b`

Architecture reviewer: `/root/phase9_linked_module_checker`

Security reviewer: `/root/phase9_topology_security_review`

Tooling and feasibility reviewer: `/root/phase9_topology_smoke_harness`

## Scope

This review accepts ADR 0025 and the associated ADR 0021, reference-evidence,
acceptance, architecture, backlog, and fail-closed control-tool updates as the
synthetic-local D3 specification freeze. It does not activate
`executeRefinance`, `cancelRefinance`, `refundCommitment`, or any other method.
`UNI-REFI-001` and `UNI-REFI-002` remain `TODO`, `P9-REFI-001` remains absent,
and the bundled D1-D4 control hash intentionally remains stale.

No real funds, public network, production key, external provider, production
asset, live loan, mainnet deployment, insurance guarantee, or legal-recovery
authority is granted.

## Reviewed decisions

- Old-position evidence commits only to bounded public observations at one
  `uint64(block.number)`, recomputed before effects, after payoff, and before
  completion. It does not claim proof of inaccessible private checkpoint arrays.
- Four fixed payout legs reject zero, coordinator, and settlement-token
  recipients before effects. Canonical aliases remain separate legs and
  reconcile through strictly increasing unsigned-`uint160` unique-recipient
  aggregates plus exact coordinator outflow.
- Quote components, resolver-returned replacement debt/tranches/positions, and
  one `uint64(block.timestamp)` execution time have exact typed evidence
  preimages.
- `EXECUTING` is provisional, unversioned, non-evented, and never a terminal
  replay state. Success persists one direct
  `FUNDING_ESCROWED -> COMPLETED` version increment and transition.
- First execution derives its operation ID from the consumed quote's stored
  pre-payoff debt version. Terminal replay makes no dependency call and proves
  the supplied processed operation through the complete stored terminal tuple
  and exact nonzero execution-event reconstruction.
- Cancellation replay remains storage-only after arbitrary partial or final
  refunds. It validates the bounded commitment inventory and reconstructs the
  pre-cancellation version as
  `stateVersion - refundedCommitmentCount - 1` before matching the permitted
  reason-specific processed operation ID.
- Lien handoff is a bounded sorted four-phase barrier: begin all, verify all
  pending, complete all, and verify all active. Only the canonical lien registry
  is called from the first begin through the last active verification.

## Superseded failed candidate

Commit `8b4aadf7c286321aa6c7eea808b670c36ae568c2` failed independent review because
it required terminal execute replay to recompute an operation ID from an
unstored quote debt version while also prohibiting the quote call. Review also
found that funded cancellation replay did not retain enough direct evidence
after refunds advanced the state version. Commit `5d076f5` closes both findings
without adding ABI, storage, selector, compiler, or module authority. The failed
candidate is not approval evidence.

## Verification

- Architecture review: PASS; 207 semantic/checkpoint tests and linked-module
  checks passed with no P0, P1, or P2 finding.
- Security review: PASS; 268 focused tests and local-prohibition checks passed
  with no P0, P1, or P2 finding.
- Tooling and feasibility review: PASS for the specification freeze; 207 tests,
  exact formula checks, mutation controls, and forbidden stale-wording checks
  passed with no specification finding.
- The reviewed commit changed no Solidity source, ABI snapshot, storage
  snapshot, schema, compiler setting, checkpoint registry, release evidence, or
  generated artifact.
- The incomplete linked runtimes remained Validation `22,275`, Request `24,052`,
  Lifecycle `13,362`, and Coordinator `5,549` bytes.

## Deliberately open implementation gates

The full Phase 9 and storage gates stop at the expected
`Phase 9 current control-bundle hash is stale` condition. An in-memory hash
substitution reaches the expected uncheckpointed D1-D2 source rejection. These
are fail-closed implementation controls, not specification defects and not
permission to refresh the hash.

A compiling maximum-path D1-D4 prototype and measured EIP-170 report remain
mandatory before D3 activation. The Request module has only 524 bytes of current
headroom, and incomplete-slice size success is not bundled completion evidence.
Any implementation, checkpoint, hash refresh, method activation, or production
authority requires a new exact-commit review.
