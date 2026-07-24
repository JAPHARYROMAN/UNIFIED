# Phase 7A Payment Ingress and Reconciliation

Status: accepted boundary; implementation pending

## Scope

Phase 7A builds the smallest provider-independent payment foundation that can safely
receive synthetic external evidence. It is deliberately off-chain and local-only.

```text
payment intent
     |
     v
payment orchestrator -----> immutable intent + explicit state
     ^
     |
size-bounded raw callback
     |
     +--> retain raw evidence
     +--> verify provider + Ed25519 signature + expiry
     +--> deduplicate provider:event
     +--> normalize exact payment/asset/amount/status
     |
     +--> valid transition --> balanced ledger journal
     |
     +--> unknown/conflict/invalid --> quarantine + reconciliation exception

synthetic provider statement
     |
     v
reconciliation run --> match or owned visible difference
```

The orchestrator never directly mutates a loan, position, collateral vault, token,
treasury, or user balance.

## Canonical intent

One immutable intent binds:

```text
payment ID + idempotency key + correlation ID
+ payer reference + optional loan ID
+ provider + rail + purpose
+ exact asset + integer units
+ expiry + schema version
```

An idempotent replay with identical content returns the existing intent. Reusing the key
for different content is a conflict. IDs and references are opaque synthetic values and
must not encode bank, card, identity, or other sensitive data.

## Provider trust boundary

The local provider registry is dependency-injected and contains only:

```text
provider ID + active status + rail
+ Ed25519 public key + supported asset
+ reversal capability + configuration version
```

The signed callback body is a domain-separated canonical encoding of provider ID,
provider event ID, payment ID, provider reference, state, asset, units, occurrence time,
expiry, and evidence commitment. Unified verifies the exact raw bytes before parsing the
normalized event. The provider occurrence time is evidence; the ingestion clock controls
receipt and expiry decisions.

The local implementation may persist synthetic raw callback bytes to prove retain-before-
normalize ordering. Production raw financial payload storage requires a separate
restricted-data design covering encryption, access, retention, deletion, legal hold,
redaction, and key rotation.

## State and finality

```text
CREATED -> PROCESSING -> PROVISIONAL -> FINAL
    |          |              |           |
    +------> FAILED           +------> REVERSED
                              +------> DISPUTED
                                          ^
                     conflict/quarantine--+
```

Only an allowed, authenticated transition can change state. `PROCESSING` and
`PROVISIONAL` remain reversible and cannot authorize final debt reduction or collateral
release. `FINAL` means only that the configured synthetic provider-settlement predicate
passed; Phase 7A still does not allocate the amount to a loan.

## Accounting mapping

The first slice uses existing chart meanings and exact one-asset journals:

| Transition | Debit | Credit |
|---|---|---|
| Bank provisional | `9140 Pending Bank Settlement` | `9120 Unallocated Loan Payment` |
| Card provisional | `9130 Pending Card Settlement` | `9120 Unallocated Loan Payment` |
| Bank final | `1100 Cash and Fiat at Banks` | `9140 Pending Bank Settlement` |
| Card final | `1120 Card Processor Receivable` | `9130 Pending Card Settlement` |

A reversal posts linked opposite journals; it never edits the original. If a callback is
quarantined or disputed before a valid posting, no economic journal is emitted. Phase 7A
has no revenue, refund, debt-allocation, chargeback-fee, reserve, or write-off posting.

## Idempotency and ordering

- Intent idempotency is scoped to the local legal entity and caller boundary.
- Callback uniqueness is scoped to `provider ID + provider event ID`.
- Journal idempotency uses the canonical provider event and transition.
- Exact callback replay returns the original result and journal references.
- Conflicting replay produces one visible exception and no new journal.
- Later events do not make an earlier contradictory event safe; invalid order enters
  quarantine.
- Provider retry after an outage is safe because no effect depends on broker offset or
  delivery count.

## Quarantine and reconciliation

Every quarantine item records a reason code, provider/event/payment references,
raw-payload hash, evidence hash, received time, owner, resolution deadline, and immutable
status history. It contains no raw secret in logs or error text.

A reconciliation run binds:

```text
run ID + provider + asset + as-of time
+ provider snapshot hash + ledger snapshot hash
+ expected integer units + observed integer units
+ difference + materiality + owner + deadline + status
```

A zero difference is matched. A nonzero or unmatched item remains open and cannot be
silently netted, moved to revenue, or marked resolved without a linked resolution
evidence record. Phase 7A supports synthetic resolution evidence only; it does not post a
financial correction automatically.

## Acceptance properties

- `INV-PAY-001` and `INV-PAY-002`: request, callback, processing, and provisional states
  do not claim final settlement or loan allocation.
- `INV-PAY-003` and `INV-PAY-009`: one provider event produces at most one state effect
  and one posting.
- `INV-PAY-004`: active provider, exact signed bytes, expiry, and payment binding are
  verified before normalization changes state.
- `INV-PAY-005`: a recognized reversal uses linked opposite journals without duplicate
  settlement recognition; loan restoration is deferred to Phase 7B.
- `INV-PAY-006`: no Phase 7A path calls collateral release.
- `INV-PAY-007` and `INV-PAY-008`: one exact asset and integer units are conserved; FX is
  unavailable.
- `INV-PAY-011`, `INV-ACC-005`, and `INV-ACC-007`: mismatches remain owned and visible,
  while suspense cannot be treated as available value.

## Explicitly unavailable

- live bank/card/payment/FX provider network calls;
- webhooks exposed to the public internet;
- real bank accounts, PANs, tokens, cardholder or identity data;
- loan payment allocation, collateral release, refund, payout, or debt reinstatement;
- FX, fees, partial allocation, split tender, or multi-currency netting;
- automatic exception resolution or suspense write-off;
- production credentials, real funds, public testnet, or mainnet deployment.
