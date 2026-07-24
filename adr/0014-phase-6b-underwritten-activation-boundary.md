# ADR 0014: Phase 6B Underwritten Loan Activation Boundary

Status: accepted for local and testnet engineering

Date: 2026-07-24

## Context

Phase 6A proves commitment-only eligibility, immutable credit-decision provenance, and
subject-level exposure conservation, but no production loan factory consumes those
controls. Calling the legacy factory through a wrapper would change the borrower identity
to the wrapper. Adding a loose pre-check would permit the decision to change before
funding, leave a reservation after failure, or disburse principal without recognized
exposure. A safe integration must bind borrower and lender authorization to the same
decision and make reservation, funding, registration, and activation one transaction.

## Decision

1. Phase 6B adds a new non-upgradeable `UnderwrittenLoanFactory` with protocol version 3.
   The Phase 3 factory and account remain available for their reviewed version-2 boundary;
   the new factory does not proxy through or mutate the legacy factory.
2. The caller is the borrower, must own the open tender, and must call the final activation
   directly. This direct transaction is acceptance of the exact terms; delegated and
   relayed consent are unavailable in the first slice.
3. A nonzero consent-evidence commitment is public. It contains no raw disclosure or
   personal data and is bound into an activation agreement hash together with the loan,
   tender, offer, borrower, decision, product, asset, principal, maturity, policy set, and
   metadata.
4. The lender authorizes the same agreement through the existing EIP-712 offer. Offer
   identity, economics, timing, policy set, agreement, metadata, nonce, and expiry checks
   remain unchanged.
5. The approved credit decision must be current and bind the exact borrower, subject,
   credential, settlement asset, product, amount ceiling, duration ceiling, and policy
   version used for activation.
6. The approved policy set must contain one active underwritten-credit policy whose
   product hash equals the activation product and whose ID and semantic version equal the
   decision policy. It must also retain the reviewed zero-interest policy required by the
   principal-only account.
7. A policy explicitly marked as requiring underwriting cannot be accepted by the legacy
   version-2 factory. This prevents a policy-governed Phase 6B product from intentionally
   selecting the path that omits exposure controls.
8. In one non-reentrant transaction, the new factory validates authority and emergency
   state, reserves exposure, selects and consumes the offer, deploys and registers the
   deterministic account, pulls and disburses exact principal, activates the account,
   activates exposure, and fulfills the tender.
9. Any revert at any step rolls back the reservation, offer/tender state, clone, registry
   entry, token movement, account state, and evidence events. No asynchronous funding,
   partial activation, or administrative repair path exists in this slice.
10. Both the global new-loan capability and a dedicated underwritten-new-loan capability
    may stop new activation. Neither pause may block repayment, canonical closure, or
    permissionless terminal exposure release.
11. Repayment remains the reviewed direct principal-only `CoreLoanAccount` path. After
    terminal zero debt, anyone may release recognized exposure with a nonzero evidence
    hash. Delayed release is conservative because it withholds capacity rather than
    creating it.
12. Canonical schemas and final audit evidence link the decision, reservation, loan,
    tender, offer, agreement, consent commitment, asset, amount, duration, journal, and
    terminal release without recording raw identity or underwriting features.
13. Tests must cover exact successful activation and repayment, funding failure rollback,
    revoked or superseded decisions, product/policy/asset/amount/duration mismatch,
    consent/agreement mismatch, replay, emergency pause, legacy-policy bypass rejection,
    and terminal release.
14. The first slice is synthetic, same-chain, exact-ERC20, single-lender, zero-interest,
    principal-only, and local/testnet-only. It authorizes no production provider, personal
    data, real unsecured funds, public testnet, production key, or mainnet deployment.

## Consequences

- Underwritten activation becomes an atomic specialization of the reviewed Phase 3 loan
  lifecycle rather than an eligibility check detached from settlement.
- The version-3 factory is granted both loan-factory and exposure-factory roles; no other
  new authority is introduced.
- A failed transaction leaves no reservation to clean up and no lender or borrower balance
  change. Active capacity remains recognized until canonical terminal zero-debt release.
- Generic version-2 local loans are not retroactively reclassified as Phase 6B products.
  Only an approved underwritten-credit policy and version-3 activation may make that claim.
- Interest, collateral, syndication, defaults, loss recognition, cross-asset limits,
  delegated consent, production underwriting, and real identity remain separate milestones.
