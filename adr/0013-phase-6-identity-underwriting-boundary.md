# ADR 0013: Phase 6 Identity, Underwriting, and Exposure Boundary

Status: accepted for local and testnet engineering

Date: 2026-07-24

## Context

Unsecured credit cannot rely on wallet address alone. Publishing personal attributes,
accepting stale or replayed credentials, treating one provider's pseudonym as universal
uniqueness, or authorizing each wallet against an independent limit would create privacy
harm and systemic credit loss. A model score without provenance, expiry, product scope,
or explainable evidence is not an activation authority.

## Decision

1. Public contracts, events, schemas, logs, fixtures, and repository history must contain
   no raw identity, document, income, bank, protected-attribute, or contact data. They may
   contain only opaque identifiers, domain-separated salted commitments, policy/version
   references, validity bounds, and evidence hashes.
2. A commitment to low-entropy personal data is acceptable only when constructed outside
   the public protocol with domain separation and at least 128 bits of secret randomness.
   A plain hash of a name, document number, email, phone number, or date is prohibited.
3. An append-only `IdentityProviderRegistry` approves issuer identities, credential
   schemas, assurance bounds, and status. Registrar, credential issuer, underwriter,
   exposure factory, risk revocation, and release authorities are separate scoped roles.
4. `CredentialRegistry` records one immutable credential envelope: random credential ID,
   subject commitment, bound account, provider and schema IDs, claim commitment, scope,
   epoch, assurance, validity window, and status. The approved issuer submits it directly.
5. Expired, not-yet-valid, revoked, wrong-account, wrong-subject, wrong-scope, or
   disabled-provider credentials cannot support a new decision. Revocation affects the
   next on-chain eligibility check; it does not rewrite a completed transaction.
6. Scope and epoch define the exact meaning of a uniqueness attestation. The system must
   not claim that one provider commitment proves global personhood or prevents a provider
   or cross-provider synthetic identity.
7. `CreditDecisionRegistry` stores only approved decision attestations. Each immutable
   decision binds a subject commitment and account to policy and rules/model versions,
   feature-evidence root, exact settlement asset, product, amount limit, maximum duration,
   issuance time, expiry, and a non-sensitive reason-code commitment.
8. Declines, raw features, explanations, protected attributes, model artifacts, and
   adverse-action detail remain off-chain under restricted access. Public state contains
   no score whose interpretation could expose sensitive information.
9. `ExposureManager` aggregates reserved and active principal by subject commitment and
   exact asset, not wallet. A recognized exposure plus a new reservation cannot exceed
   the valid decision limit. Pending reservations count before atomic loan activation.
10. Reservations bind a unique loan ID, decision, product, duration, borrower account,
    and factory. Only an approved factory may reserve and activate. Release requires
    canonical terminal loan state and zero debt, or a versioned failure/cancellation path.
11. A decision update, provider status change, model update, or manual review cannot
    mutate an existing decision. A new versioned decision is required. Manual overrides
    are unavailable in the first slice.
12. The first underwriting engine is a deterministic, versioned rules engine with
    authenticated feature references, timestamps, explicit reason codes, and synthetic
    test data. It makes no claim of machine-learning quality, legal compliance, fairness,
    global uniqueness, or production creditworthiness.
13. The first slice does not implement a restricted raw-data vault, production identity
    provider, zero-knowledge circuit, public reputation score, anonymous credit, or live
    unsecured disbursement. Those require separate privacy, cryptographic, legal,
    accounting, and economic-risk approval.

## Consequences

- Public state can demonstrate who attested, what version and scope applied, when it was
  valid, and how much exposure was authorized without storing the underlying identity.
- Exposure is conservative: stale or ambiguous state blocks new reservations and may
  leave capacity unavailable until canonical closure is proved.
- One asset is not converted into another for limit calculations. Cross-asset aggregation
  requires an accepted valuation and FX policy.
- Provider compromise and synthetic identity remain residual risks. Initial provider and
  product limits must be zero outside local synthetic tests.
- No real personal data, production provider credential, unsecured production fund, key,
  public testnet approval, or mainnet deployment is authorized.
