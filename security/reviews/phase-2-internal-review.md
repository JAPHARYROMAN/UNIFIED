# Phase 2 Internal Security Review

Review date: 2026-07-24
Scope: `protocol/src`, `protocol/test`, and `protocol/script/DeployPhase2.s.sol`
Disposition: approved for local and testnet engineering only

## Review result

No unresolved existential or critical finding was identified. This is an internal
engineering review, not an independent audit and not authorization for production funds.

The review traced the Phase 2 implementation to `INV-SUP-001` through `INV-SUP-007`,
`INV-AUTH-001` through `INV-AUTH-004`, `INV-LOAN-001`, `INV-LOAN-003`,
`INV-LOAN-005`, `INV-LOAN-008`, `INV-GOV-009` through `INV-GOV-011`, and
`INV-NUM-007`.

## Evidence

- Fixed supply and supply equation: stateful Foundry invariants, 256 runs and 128,000
  calls per invariant.
- Genesis allocation: exact balance checks for all nine allocations and a constructor
  assertion that total supply equals the constitutional cap.
- Issuance surface: no external issuance method; the privileged-surface scanner rejects
  any `mint` function declaration.
- Loan identity: deterministic-address, duplicate-ID, agreement-hash, and terminal-state
  tests.
- Policy integrity: runtime code-hash, ERC-165 support, immutable version, activation,
  and prospective-deprecation controls.
- Authority: administrator/governance separation, scoped expiring emergency actions,
  and a hard prohibition on pausing repayment or collateral top-up.
- Revenue: actual-received accounting, 10,000-bps conservation, bounded splits, and
  reserve-deficiency burn suspension.
- Deployment: a clean local EVM simulation completed without broadcasting.
- Runtime size: all production artifacts are below the EIP-170 limit.

## Findings

| ID | Severity | Status | Finding and disposition |
|---|---|---|---|
| P2-SEC-001 | Medium | Mitigated | Generic allocation vaults do not yet encode every community, treasury-mandate, public-sale, staking, insurance, or liquidity sub-envelope. They are role-restricted custody skeletons. Real distribution remains prohibited until the relevant product contract and tokenomics acceptance tests replace or wrap each generic release path. Owner: Economic Risk Authority. Target: before any public token distribution. |
| P2-SEC-002 | Medium | Mitigated | `RoleManager` can express unsafe grants if governance deliberately assigns many operational roles to one account. The canonical deployment script rejects administrator/governance overlap and requires seven mutually distinct operators. Production deployment also requires an independently reviewed role manifest. Owner: Security Authority. |
| P2-SEC-003 | Low | Accepted | The deployment script briefly grants the governance broadcaster the asset-registrar role to register canonical UFT, then revokes it before completing. No user funds or external calls exist during this bootstrap window. The dry-run transaction trace must be retained for any future testnet deployment. Owner: Release Authority. |
| P2-SEC-004 | Informational | Accepted | Thirty-day months are used for vesting math. This matches the baseline monthly model but must be disclosed in grant agreements and interfaces. Owner: Program Authority. |

## Explicitly deferred attack surfaces

Loan economics, accounting postings, collateral custody, oracle use, payments,
liquidation, governance voting, staking, and bridging are absent from this phase. Their
absence is a boundary, not a security claim. Each requires its own threat-model delta,
tests, and security review before implementation can be merged.
