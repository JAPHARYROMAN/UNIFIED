# Phase 4B1 Internal Security Review

Review date: 2026-07-24

Scope: collateral vault, manager, UFT controls, schemas, ABIs, and tests

Disposition: approved for local and testnet engineering with liquidation engine unset

## Review result

No unresolved existential or critical finding was identified. Evidence covers
`INV-COL-001` through `INV-COL-007`, `INV-COL-009`, `INV-COL-010`, and the
mechanical no-double-disposition portion of `INV-LIQ-004`. Substitution, valuation,
liquidation eligibility, proceeds, auctions, and accounting remain blocked.

## Findings

| ID | Severity | Status | Finding and disposition |
|---|---|---|---|
| P4B1-SEC-001 | Medium | Mitigated | NFT receiver callbacks are an external reentrancy surface. Deposits and dispositions are guarded, callbacks match one exact expected transfer, and unsolicited or batch callbacks revert. Owner: Security Authority. |
| P4B1-SEC-002 | Medium | Accepted boundary | UFT debt ceiling value is a risk-council attestation rather than an on-chain market-cap derivation. Phase 4B2 must derive it from finalized Phase 4A observations before production. Owner: Accounting and Economic Risk Authority. |
| P4B1-SEC-003 | Medium | Mitigated | A UFT burn can make existing percentage exposure noncompliant. The manager exposes continuous compliance status; the later health engine must block new risk and trigger policy action. Existing custody is never silently released. Owner: Security Authority. |
| P4B1-SEC-004 | Medium | Accepted boundary | The liquidation-engine address is immutable once set and has mechanical disposition power. Deployment must leave it unset until the Phase 4B2 engine and its eligibility tests pass. Owner: Release Authority. |
| P4B1-SEC-005 | Low | Accepted | Native release can fail for a recipient contract that rejects value. Borrower-selected release is restricted to the original borrower, and failure preserves custody atomically. Owner: Protocol Architecture Authority. |

## Explicitly blocked

Substitution, oracle valuation, LTV, margin calls, direct sale, lender claim, Dutch and
English auctions, NFT auction expiry, borrower surplus, bad debt, and liquidation
accounting are not implemented or authorized by this milestone.
