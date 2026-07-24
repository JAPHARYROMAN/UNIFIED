# Phase 4A Internal Security Review

Review date: 2026-07-24

Scope: Phase 4A oracle, interest, schedule, servicing, schemas, service parity, and ABIs

Disposition: approved for local and testnet engineering only

## Review result

No unresolved existential or critical finding was identified. This is an internal
engineering review, not an independent audit and not authorization for production
oracle feeds, collateral, liquidation, or funds.

Evidence covers `INV-INT-003`, `INV-INT-006` through `INV-INT-008`,
`INV-ORC-001` through `INV-ORC-008`, `INV-LOAN-012` through `INV-LOAN-015`,
and `INV-LIQ-001`, `INV-LIQ-002`, and `INV-LIQ-012` at the servicing predicate
boundary. Commencement, extinguishment, and canonical principal bounds remain caller
obligations for the Phase 4B loan integration.

## Findings

| ID | Severity | Status | Finding and disposition |
|---|---|---|---|
| P4A-SEC-001 | Medium | Accepted boundary | Oracle adapter calls are synchronous and can consume unpredictable gas or return adversarial values. Calls are bounded to eight approved sources, failures are excluded, quorum is mandatory, and no production adapter is present. Owner: Security Authority. |
| P4A-SEC-002 | Medium | Mitigated | The asset-only circuit status assumes one canonical quote pair. The router enforces that restriction and also exposes pair-specific status. Multi-quote support requires a new aggregation policy. Owner: Protocol Architecture Authority. |
| P4A-SEC-003 | Medium | Accepted boundary | Interest is simple actual/365 and rounds down twice. Compound, negative, utilization, and revenue-linked models are unsupported and must not be represented as this policy. Owner: Accounting and Economic Risk Authority. |
| P4A-SEC-004 | Medium | Mitigated | Servicing roles attest final payments, cures, and default evidence. Role separation, expiries, evidence hashes, objective time gates, and state nonces limit the surface; production use still requires independent attestation and dispute systems. Owner: Security Authority. |
| P4A-SEC-005 | Low | Accepted | Block timestamps have normal validator skew. Due, grace, cure, benchmark-age, and oracle-age settings must not depend on sub-block precision. Owner: Protocol Architecture Authority. |

## Explicitly blocked

No Phase 4A result alone can move collateral or proceeds. Multi-asset custody, UFT
exposure ceilings, LTV health, direct sale, partial liquidation, lender claim, borrower
surplus, auction escrow, failed-auction handling, and liquidation accounting remain
Phase 4B work with separate tests and review.
