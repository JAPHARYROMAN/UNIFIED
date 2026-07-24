# Phase 7C Canonical External Settlement

Status: implemented for synthetic local engineering

## Authority and commit flow

```text
synthetic provider FINAL + exact reconciliation
                         |
                         v
mature-settlement policy proof + elapsed reversal deadline
                         |
                         v
PREPARED canonicalization lease
                         |
                         v
synthetic converter supplies exact registered loan token
                         |
                         v
one EVM transaction
  pull gross token units
  -> repay canonical principal
  -> pay lender through CoreLoanAccount
  -> refund exact excess to registry borrower
  -> retain zero new units
                         |
                         v
configured chain finality
                         |
                         v
exact durable CONFIRMED/submitted-origin INCIDENT snapshot
                         |
                         v
one callable, replay-safe SQL success commit
```

The provider remains authoritative for its external record. The payment service is
authoritative for authentication and provider reconciliation. The converter proves value
only by transferring the registered target token. The loan account remains authoritative
for debt and terminal state. The finalized gateway event is authoritative for the
canonicalization result. The ledger records, but cannot originate, those rights.

## Eligibility boundary

Phase 7A `FINAL` is necessary but insufficient. A canonicalization is eligible only when:

```text
provider payment is FINAL and unreversed
AND provider/payment/amount/asset binding is exact
AND reconciliation is MATCHED with zero difference and unmatched items
AND active loan policy set proves mature external settlement
AND now >= reversal deadline
AND canonical loan is active with expected debt and state nonce
AND no Phase 7B allocation or journals exist
AND payment allocation mode is atomically claimed as CANONICAL_GATEWAY
```

The complete policy set is supplied to the gateway and must hash to the loan's immutable
`policySetHash`. Exactly one historically registered mature-settlement policy with the
reviewed interface, code hash, and compatible configuration must be present, and the loan
factory/version provenance must be approved. Current origination-active status is not
rechecked: deprecating a policy for new loans cannot remove an existing loan's repayment
route. Older loans without the binding remain on their direct-token route.

Matched reconciliation is off-chain evidence. A separate current
`ACCOUNTING_ATTESTER_ROLE` signs a domain-separated eligibility digest binding the final
provider record, exact reconciliation result, source/target assets and units, original
journals, policies, deadline, loan, payment, allocation, finalizer, chain, and gateway.
The gateway verifies that attestation; caller-supplied zero-difference fields alone are
not authority.

## Canonical gateway

The gateway is a narrow adapter, not a payment processor or collateral agent. It:

- resolves the account and borrower from `LoanRegistry`;
- resolves the exact active token from `AssetRegistry`;
- checks the loan ID, settlement token, terms, lifecycle, debt, and state nonce;
- checks the mature-settlement policy and adapter emergency state;
- accepts calls only from a current `PAYMENT_FINALIZER_ROLE` that is distinct from the
  gateway, loan, lender, borrower, and accounting attester;
- derives lender and borrower recipients from canonical state;
- pulls exactly the gross token amount from the finalizer;
- sends `min(gross, debt)` through `CoreLoanAccount.repay`;
- sends `gross - principal` directly to the registry borrower;
- verifies exact balance deltas and zero newly retained gateway balance; and
- stores one instruction digest and result for each payment/allocation pair.

No caller can redirect a payout or refund. No provider callback calls the gateway
directly. No mint, FX, arbitrary swap, general withdrawal, or collateral call exists.

## Conservation

The provider asset and token are distinct assets with the same denomination and
precision. The fixed first-slice conversion has zero fee, slippage, or rounding:

```text
source provider units = target token units
gross target tokens   = principal tokens + borrower excess tokens
debt before           = principal tokens + debt after
gateway retained      = 0
```

Different denominations and non-unit conversion rates are rejected. The conversion
record still preserves distinct source and target identities, the fixed rate, timestamp,
original provider custody, target-token delivery, and risk assumption. Future FX must
also record quote and execution rates, rational rounding, fees, slippage, and residuals.

## Cross-domain state machine

```text
ELIGIBLE -> PREPARED -> SUBMITTED -> CONFIRMED
               ^             |            |
               |             v            v
               +-- FAILED  QUARANTINED  INCIDENT
                    |          |    |
        exact retry +          |    +-- authenticated late success --> INCIDENT
                               |
                               +-- reversal resolution --> FAILED + TOMBSTONED

PREPARED | FAILED | SUBMITTED -- provider reversal --> QUARANTINED
```

- `PREPARED` atomically proves that no Phase 7B allocation or journals exist and claims
  the payment allocation mode as `CANONICAL_GATEWAY`. Phase 7B rejects claimed payments,
  and Phase 7C rejects previously allocated payments.
- `SUBMITTED` records the intended chain, gateway, calldata hash, sender, nonce, and
  transaction hash. It is not success.
- `CONFIRMED` requires the exact gateway event at configured chain finality.
- A finalized reverted receipt or pre-finality orphan moves the same operation to
  `FAILED` under indexer-owned evidence. Its `CANONICAL_GATEWAY` claim is never released
  to Phase 7B; only the exact payment, allocation, and instruction may retry when no
  reversal quarantine or tombstone exists.
- A crash after broadcast is recovered from chain state and events.
- A ledger outage after confirmation is recovered by exact SQL command replay. It never
  causes an EVM retry or a second economic batch.
- If authenticated success wins serialization against a submitted reversal resolution,
  the payment remains `FINAL`, the quarantine is consumed into an owned `INCIDENT`, and
  no reversal accounting or tombstone is created.

## Authenticated EVM evidence

The configured indexer accepts raw EVM facts only under a header signed by its pinned
Ed25519 observer. It derives the header hash, parent, transaction root, receipt root,
height, and timestamp from canonical RLP; verifies transaction and receipt
Merkle-Patricia inclusion at one index; and decodes status and gateway logs only from the
included receipt. Legacy and EIP-2718 typed receipts require a canonical status,
canonical cumulative gas, an exact 256-byte logs bloom, and bounded canonical logs.
Trie children are either an embedded RLP list shorter than 32 bytes or an exact 32-byte
hash; noncanonical short-string references are rejected.

Authenticated input is bounded per node and proof and, across a block, to 4,096 receipt
proofs, 32 MiB of proof nodes, and 64 MiB total input. Signed observation time is
non-decreasing across canonical appends and replacements. Re-ingesting the identical
signed header may only enrich it with additional verified, nonconflicting receipt/event
proofs under the same observation and signature; it cannot rewrite established facts or
create a reorganization.

The finality-policy hash binds chain, gateway, confirmation depth, and observer public
key. Confirmation, failure, reversal, and reorganization consumers compare it with the
durable plan. Reorganization detection also cannot predate submission or the confirmed
projection it contradicts. This Ed25519 observer is an explicit synthetic local/test
trust root, not an EVM consensus or light-client proof.

## Reversal semantics

A reversal received while the plan is `PREPARED`, `FAILED`, or `SUBMITTED` first creates
a durable quarantine without changing payment state or posting an economic journal.
Resolution then performs the Phase 7A reversal, linked opposite journals, failed
coordinator transition, and permanent allocation-mode tombstone atomically. A submitted
plan additionally requires the exact reverted receipt and transaction to be proven at
the same trie index under the receipt and transaction roots of an authenticated EVM
header. That receipt block and the finality head are separately bound to a pinned header
authority and an immutable finality-policy hash; caller-authored status, logs, block
facts, or failure text are never authority. No retry is possible between quarantine and
that single resolution commit, and the resulting tombstone prevents every later retry.

Confirmed Phase 7C settlement is intentionally mature and irreversible. A provider
message contradicting it after the reversal deadline is an owned converter incident, not
a valid loan reversal. The canonicalization latch is checked before the ordinary
`FINAL -> REVERSED` callback path, so the contradiction emits no Phase 7A or Phase 7B
reversal journal. It cannot:

- reopen a terminal loan;
- duplicate or claw back lender payout;
- duplicate or claw back borrower refund;
- reverse a completed collateral disposition; or
- create a reserve or loss claim without separate evidence.

Reserve-backed early settlement is not implemented. No component may describe a reserve
as funded or available.

## Accounting boundary

The canonical path uses a new non-posting waterfall plan and atomically excludes Phase 7B
economic posting so allocation cannot be recognized twice. The sole supported callable
durable success path is
`commit_canonical_external_settlement(confirmation_projection, conversion_evidence_hash,
converted_at, target_book_id)`. It locks the payment and coordinator rows and requires
the input to equal the exact stored `snapshot.Confirmation`. Authority is either:

- durable `CONFIRMED` with a non-incident confirmation; or
- durable submitted-origin `INCIDENT` with an incident confirmation and the exact
  consumed pending reversal, submission, quarantine, and resolution authority.

`SUBMITTED`, unresolved `QUARANTINED`, a prepared/failed origin masquerading as late
success, stale time, changed content, or a partial prior write fails closed. In one SQL
transaction the function records conversion evidence, the gateway event, confirmation,
seven/eight independently balanced journals and links, lender payout, and optional
borrower refund. Exact replay returns the same deterministic identities. The in-memory
`PostBatch` remains an isolated accounting proof of the same journal conservation; it is
not a second durable success authority.

The durable journal batch is:

```text
Debit  9120 Unallocated Loan Payment [S]      source gross
Credit 9160 Conversion Clearing [S]           source gross

Debit  9160 Conversion Clearing [S]           source gross
Credit 1100/1120 Provider Settlement Asset [S] source gross

Debit  1260 Restricted Settlement Token [D]   target gross
Credit 9160 Conversion Clearing [D]            target gross

Debit  9160 Conversion Clearing [D]            target gross
Credit 9120 Unallocated Loan Payment [D]       target gross

Debit  9120 Unallocated Loan Payment [D]      target gross
Credit 1310 Principal Receivable [D]          principal
Credit 2150 Refund Payable [D]                excess, when nonzero

Debit  2310 Lender Principal Claims [D]       principal
Credit 2130 Lender Repayment Payable [D]      principal

Debit  2130 Lender Repayment Payable [D]      principal
Credit 1260 Restricted Settlement Token [D]  principal

Debit  2150 Refund Payable [D]                excess, when nonzero
Credit 1260 Restricted Settlement Token [D]  excess, when nonzero
```

Each journal balances inside one asset. Conversion evidence binds the original unreversed
Phase 7A final journals and derived provider account, source and target identities and
units, finalizer, one-to-one execution, gateway transaction, and finalizer risk
assumption. `9160` clears independently in both assets. The original payment-specific
`9120` source balance must be wholly unallocated.

A reorg before configured finality removes the event before posting. A deep reorg after
posting creates linked opposites for the whole Phase 7C batch, restores the Phase 7A
provider asset and unallocated liability, and opens an owned incident. The coordinator
accepts a reorg only when its finality policy, header authority, orphaned transaction
index, receipt root/proof, receipt-header signature, confirmation-head signature,
replacement signature, detected-head signature, and monotonic times match the durable
plan or confirmation. It persists that full provenance and issues the opaque,
restart-restored authority required by deep compensation. History is never edited and a
ledger failure never retries the EVM action.

## Collateral custody

The gateway cannot release collateral. A successful full settlement may mark the loan
terminal through its existing repayment path. The borrower can then use the independent
custody function immediately; that contract does not inspect the coordinator's later
`CONFIRMED` state. It rechecks registry terminality, zero canonical principal, exact
borrower recipient, and collateral identity. A same-chain reorganization removes both a
repayment and any dependent release from canonical history.

Waiting through the policy reversal deadline is the first-slice control that resolves
reversal risk. A future reserve-backed early path must add an actual segregated reserve,
coverage reconciliation, deterministic loss substitution, and a custody interlock before
it can alter this rule.

## Acceptance properties

- `INV-PAY-001` and `INV-PAY-002`: provider finality alone cannot reduce debt.
- `INV-PAY-003` and `INV-PAY-009`: one payment creates at most one canonical result.
- `INV-PAY-005`: a valid pre-canonical reversal is quarantined and then atomically
  restores Phase 7A economics while permanently tombstoning the canonical plan; a mature
  confirmed token settlement has no remaining contractual reversal path.
- `INV-PAY-007`, `INV-PAY-008`, and `INV-PAY-010`: distinct source/target identities,
  exact one-to-one conversion, target-token conservation, and refund bounds hold.
- `INV-LOAN-004` and `INV-LOAN-006`: the immutable policy set authorizes the route.
- `INV-LOAN-008`: confirmed terminal debt never reopens.
- `INV-LOAN-011`: debt, lender distribution, refund, and unresolved settlement state are
  accounted in the canonical commit; collateral remains on its explicit custody path.
- `INV-ACC-002` through `INV-ACC-007`: final journals are balanced, immutable,
  idempotent, chain-linked, custody-reconciled, and make no unfunded reserve claim.
- `INV-COL-004` through `INV-COL-006`: no adapter release, wrong-recipient release, or
  double release is possible.

## Implemented slice

- a mature-settlement policy interface and synthetic fixed policy;
- an exact-token canonical repayment gateway and Foundry adversarial tests;
- an explicit shared durable Go allocation-mode claim, restart-safe CAS coordinator,
  strict raw-log/receipt/trie decoder, bounded same-header enrichment, monotonic
  finality/failure/reorg projections, and restart-safe reorg authority;
- a typed finalized-event accounting adapter, one callable exact-snapshot SQL success
  transaction, restart-rehydrated evidence, atomic quarantine/resolution, and
  exact-content single-claim Phase 7B/7C exclusion;
- additive Protobuf and deterministic four-language bindings;
- append-only migration 000009, simulations, risk/assumption traceability, ABI snapshot,
  deployment harness, and internal security review.

## Explicitly unavailable

- live providers, converters, webhooks, or financial data;
- real bank, card, stablecoin, lender, borrower, or protocol funds;
- reserve-backed early settlement or any reserve-coverage representation;
- cross-denomination FX, non-unit conversion rates, fees, slippage, or rounding;
- interest, penalty, cost, multi-loan, or multi-lender waterfalls;
- automatic collateral release or caller-selected payout/refund recipients;
- production credentials, public testnet, or mainnet deployment.
- runtime provider, EVM RPC, broker, or ledger-listener wiring in service executables.
