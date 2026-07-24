# Phase 7A Data Layouts

Phase 7A adds no production Solidity contract, storage slot, on-chain role, or external
network listener.

## In-memory engineering layout

The payment orchestrator separates:

- immutable provider configuration;
- immutable payment-intent identity plus explicit aggregate state;
- provider-scoped event results for economic idempotency;
- an append-only raw callback ingress sequence;
- append-only quarantine records and separate resolution evidence.

The accounting component owns only payment-to-journal references, provider event
idempotency, reconciliation runs, visible exceptions, and separate resolution evidence.
It receives no provider private key and cannot change a payment state.

## PostgreSQL evidence layout

Migration `000007_payment_reconciliation.sql` adds:

- `payment_intent`;
- `provider_callback_ingress`;
- `payment_state_event`;
- `payment_callback_quarantine` and its resolution table;
- `payment_reconciliation_run`, provider-statement, exception, and resolution tables;
- chart accounts `1100`, `1120`, `9120`, `9130`, and `9140`.

All Phase 7A tables reject update and delete operations. State changes are new versioned
events; corrections are linked journal reversals or separate resolution records.
Provider event uniqueness, aggregate version uniqueness, exact positive integer units,
allowed transitions, journal cardinality, reconciliation status, ownership, and
deadlines are database constrained.

Raw callback bytes are limited to 64 KiB and are synthetic-only. Public schemas expose
their hash, not the raw payload. A production provider store requires a new restricted-
financial-data design and migration review.
