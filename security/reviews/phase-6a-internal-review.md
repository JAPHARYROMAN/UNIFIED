# Phase 6A Internal Security Review

Date: 2026-07-24

Scope: identity provider and schema authority, credential and decision registries,
exposure reservations, canonical schema/bindings, synthetic underwriting and simulations,
append-only audit controls, deployment script, and Phase 6 tests.

## Reviewed properties

- INV-ID-001/002: credential issuance requires an approved provider/schema/operator and
  binds one opaque subject commitment to one account.
- INV-ID-003/007: not-yet-valid, expired, revoked, or disabled-provider credentials fail
  the next decision or activation check.
- INV-ID-004: public types contain commitments and provenance only; the privacy-surface
  gate rejects obvious raw personal-data fields.
- INV-ID-005: scope and epoch are exact equality checks and no broader uniqueness is
  represented.
- INV-UW-001/003/004/005: decisions bind immutable versioned provenance, exact product,
  asset, amount, duration, feature time, expiry, and monotonic supersession lineage.
- INV-UW-002/008: reserved plus active exact-asset exposure aggregates by subject
  commitment across wallets and cannot exceed the currently used decision limit.
- INV-UW-006: the rules engine rejects stale, future, duplicate, unknown, or incomplete
  feature evidence and hashes a canonical sorted representation.
- INV-UW-007/009: manual override and anonymous unsecured products are unavailable.

## Threat checks

- Registrar, issuer, underwriter, exposure factory, revocation, and loan factory roles
  are separate.
- A risk revoker can suspend or revoke but cannot restore a provider or issue a decision.
- Credential or provider revocation between reservation and activation fails closed; EVM
  rollback prevents a partially registered test loan.
- Only a contract with the exposure-factory role can reserve. Every reservation has a
  unique loan ID and short expiry.
- Terminal release rechecks canonical loan identity and zero outstanding principal.
- Same-subject, second-wallet reservations count the first wallet's pending and active
  exposure.
- Final audit evidence covers provider/schema authority changes and rejects provisional
  input, conflicting event or record-sequence replay, missing commitments, and incomplete
  decision or exposure records.

## Residual boundary

This is an internal engineering review, not a privacy, legal, model-risk, cryptographic,
fairness, or production security audit. Commitment entropy and provider deduplication
cannot be verified by the public protocol. Different commitments can bypass aggregation.
No raw PII, live provider, production model, ZK circuit, consent vault, public reputation,
activation adapter, real unsecured funds, production key, or mainnet use is authorized.
