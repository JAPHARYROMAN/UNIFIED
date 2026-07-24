# Phase 6 Identity, Underwriting, and Exposure Boundary

Status: accepted implementation boundary

## Public-state flow

```text
identity registrar
  -> approves provider + credential schema + assurance ceiling
approved provider
  -> issues opaque credential envelope bound to subject commitment + account
underwriter
  -> validates live credential and records immutable decision provenance
approved loan factory
  -> reserves subject/asset exposure before activation
  -> activates the exact loan reservation atomically
canonical loan closure
  -> permits exposure release only after terminal state + zero debt
```

No raw identity or underwriting feature enters this flow. An evidence root proves that a
restricted record existed under a versioned transformation; it is not a public data
locator and must not be reversible by guessing.

## Data classification

| Data | Public engineering representation | Raw form |
|---|---|---|
| Subject | Domain-separated salted commitment and bound account | Restricted provider/vault only |
| Credential claim | Schema, scope, epoch, assurance, validity, claim commitment | Restricted provider/vault only |
| Consent | Purpose/evidence commitment and expiry when required | Restricted operational system |
| Underwriting features | Authenticated evidence root, source and transform versions | Restricted underwriting system |
| Decision | Limit, asset, product, duration, policy/model versions, timestamps | Explanation delivered privately |
| Reputation | Versioned event/evidence references only | No public composite score in this slice |

Public examples use random synthetic identifiers. A deterministic hash of recognizable
personal data is forbidden because dictionary search can recover it.

## Eligibility and revocation

```text
credential usable =
  provider active
  AND schema approved for provider
  AND issuer matches
  AND subject/account binding matches
  AND valid_from <= now < valid_until
  AND not revoked
  AND required scope and epoch match
  AND assurance >= policy minimum
```

Revocation is prospective and immediate for the next public check. Completed funding is
not silently unwound. A compromised provider can be disabled for new decisions without
deleting the immutable evidence that existing decisions used.

## Exposure conservation

For one subject commitment and settlement asset:

```text
recognized exposure = reserved principal + active principal
recognized exposure + proposed reservation <= current decision limit
available decision capacity = limit - recognized exposure
```

Each reservation belongs to one loan ID. Reservation, activation, failed-activation
release, repayment, and terminal release are separate states with idempotent evidence.
Wallet rotation cannot create capacity when the same subject commitment is used. The
system does not claim protection when a malicious or inconsistent provider issues
multiple commitments for one person.

## First engineering slice

Phase 6A may implement:

- append-only provider/schema approval and status;
- commitment-only credential issuance and revocation;
- immutable approved credit decisions;
- bounded exact-asset exposure reservation and release;
- canonical Protobuf and deterministic four-language bindings;
- a pure Go rules engine and synthetic Python exposure/Sybil simulations;
- immutable audit/accounting control records and an internal security review.

Phase 6B requires a separately reviewed activation adapter before any loan factory may
consume a decision. The adapter must preserve borrower consent, lender authorization,
exact funding, reservation atomicity, loan registration, and terminal exposure release.

## Explicit non-goals

The boundary does not approve raw PII storage, production KYC/KYB, sanctions decisions,
biometrics, document processing, ZK proofs, global uniqueness, machine learning, public
reputation scoring, manual overrides, anonymous credit, legal enforceability claims,
cross-asset limits, or production unsecured lending.
