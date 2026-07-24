# Phase 6A Identity, Underwriting, and Exposure Controls

Status: implemented for local and testnet engineering; no live identity or credit use

## Commitment-only credential path

```text
identity registrar
  -> registers immutable provider identity and credential-schema definition
credential issuer
  -> submits random credential ID + salted subject/claim commitments
credential registry
  -> binds provider, schema, account, scope, epoch, assurance, and validity
underwriter
  -> checks the live credential and records an immutable approved decision
```

Provider and schema status can be suspended prospectively by identity revocation
authority. Only the registrar can restore active status. A retired provider cannot be
reactivated. Credential and decision revocation are permanent.

Credential usability requires exact subject, account, scope, and epoch equality; minimum
assurance; a live validity window; and a currently active provider/schema/operator
binding. A provider suspension or credential revocation therefore blocks the next
decision or reservation without rewriting completed history.

## Decision provenance

The public decision contains:

- credential, subject commitment, and bound borrower account;
- credential scope, epoch, and minimum assurance;
- policy identity and semantic version;
- rules, model-set, feature-schema, and feature-evidence hashes;
- feature observation time;
- exact settlement asset and product hash;
- maximum aggregate exposure and duration;
- issuance, expiry, underwriter, and reason-code commitment.
- a monotonic subject/asset/product sequence and previous-decision link.

Only approved decisions are stored. Raw features, declines, explanations, personal
attributes, and model artifacts are not public contract fields. A new decision explicitly
supersedes the current decision for the same subject, asset, and product; the old decision
cannot open another reservation.

## Exposure state machine

```text
NONE -> RESERVED -> ACTIVE -> RELEASED
                   \
                    -> CANCELLED (failed/expired pre-activation only)
```

For each subject commitment and exact asset:

```text
recognized = reserved + active
recognized + proposed <= decision maximum exposure
```

An approved factory contract reserves a unique loan ID for at most 15 minutes. Activation
requires the same factory, a still-usable decision and credential, canonical non-terminal
loan registration, the same borrower, and outstanding principal exactly equal to the
reservation. Cancellation releases only unactivated capacity. Active capacity releases
permissionlessly only after the canonical loan is terminal and reports zero principal.

The Phase 6A repository uses a test harness to prove this interface. No production or
repository loan factory consumes it; that Phase 6B integration remains deferred.

## Deterministic synthetic underwriting

The Go rules engine consumes two authenticated, versioned, timestamped integer features:
synthetic verified-income units and existing-obligation units. For a policy advance rate:

```text
capacity = max(0, floor(income × advance bps / 10,000) - obligations)
decision limit = min(capacity, policy ceiling)
```

It returns a deterministic evidence root, policy/rules/schema provenance, the calculated
limit, and stable reason codes. Stale, future, duplicated, unknown, or unauthenticated
features fail closed. This is a testable rule calculation, not a production credit model,
fairness claim, or legal adverse-action system.

## Audit and schema boundary

`identity.proto` is the canonical public interface for providers, schemas, credentials,
decisions, feature commitments, and exposure reservations. It documents the requirement
for domain separation and secret randomization. Generated Solidity, Go, TypeScript, and
Python bindings are deterministic derivatives.

The finality-gated Go evidence store and migration `000005` record append-only provider,
schema, credential, decision, and exposure lifecycle evidence. The SQL schema independently
requires finality, complete opaque references, and unique record-type/record/sequence keys;
it has no raw identity columns.
The privacy-surface gate rejects obvious personal-data fields from the public identity
schema and Solidity types.

## Residual risks and non-goals

The protocol cannot prove that an opaque commitment was well salted or that one provider
did not issue multiple commitments for the same person. Different commitments remain
different exposure subjects. No raw-data vault, consent service, production provider,
sanctions decision, ZK proof, manual override, public reputation, cross-asset conversion,
live loan activation, or anonymous credit is implemented.
