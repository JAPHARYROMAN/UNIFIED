# Phase 7A Internal Security Review

Date: 2026-07-24

Scope: synthetic payment intent lifecycle, provider configuration, callback ingestion,
authentication, raw evidence retention, idempotency, ordering, quarantine, provisional
and final journals, reversal, provider-to-ledger reconciliation, schemas, migration,
simulation, and local smoke/reset.

## Reviewed properties

- `INV-PAY-001` and `INV-PAY-002`: creation, processing, and provisional evidence do not
  allocate loan debt, release collateral, or claim final settlement.
- `INV-PAY-003` and `INV-PAY-009`: provider-scoped event results and journal keys prevent
  duplicate state changes or economic postings.
- `INV-PAY-004`: callbacks require an active exact provider, pinned Ed25519 key, canonical
  domain-separated payload, expiry, and payment/provider/reference/asset/amount binding.
- `INV-PAY-005`: recognized reversal posts atomic linked opposites without editing
  history; loan-obligation restoration remains unavailable pending Phase 7B.
- `INV-PAY-006`: no Phase 7A package imports or calls a collateral component.
- `INV-PAY-007` and `INV-PAY-008`: only one exact asset and canonical integer units enter
  a payment; FX, fees, and cross-asset netting are unavailable.
- `INV-PAY-011`, `INV-ACC-005`, and `INV-ACC-007`: aggregate and per-reference mismatch,
  owner, deadline, age, snapshot hashes, exception, and resolution evidence remain
  visible and separate from available value.

## Threat checks

- Raw callback evidence is retained before provider lookup, parsing, normalization, or
  state transition. Oversize input retains only hashes and cannot allocate unbounded raw
  storage.
- Invalid signatures, inactive or unknown providers, stale evidence, unknown payments,
  amount/asset/reference mismatch, impossible order, and event-ID conflicts create no
  accounting effect.
- Exact callback replay returns the original journal references. Conflicting reuse of a
  provider event ID is quarantined and cannot overwrite the original result.
- An accounting outage leaves the payment in its prior state and permits a safe retry.
- Provisional and final journals use distinct accounts and exact denomination balance.
- A final reversal offsets both the final-recognition and provisional-recognition
  journals in one ledger batch.
- Reconciliation compares payment ID and provider reference as well as total units;
  offsetting unknown entries cannot hide behind equal aggregate totals.
- Reconciliation and quarantine resolutions are separate immutable evidence and do not
  silently post corrections or replay a rejected callback.
- Public payment schemas contain opaque references and evidence hashes only; the payment
  privacy-surface gate rejects obvious raw bank and card fields.
- SQL tables reject mutation, constrain transitions and journal evidence, and keep every
  nonzero or unmatched difference in exception state.

## Residual boundary

The Ed25519 provider configuration, payloads, statements, payer references, and funds are
synthetic. The in-memory raw store is not an encrypted regulated-data vault. There is no
public webhook, network adapter, key rotation workflow, mTLS, HSM, production
observability, incident automation, or provider statement fetch.

Phase 7A does not allocate a final payment to a loan, reinstate obligations after a
chargeback, release collateral, refund, disburse, pay out, convert currency, recognize
fees, use reserves, or resolve suspense financially. Those require later boundaries and
security, accounting, operational, privacy, and legal approval.

No live provider, real financial data, production credential, real fund, public testnet,
or mainnet use is authorized.
