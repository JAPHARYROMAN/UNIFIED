# Phase 7C Data and Storage Layouts

Status: implemented for synthetic local engineering

## Solidity

`FixedMatureExternalSettlementPolicy` is immutable and non-upgradeable. It stores:

- source provider asset ID;
- target registered token asset ID;
- conversion-policy hash;
- finality-policy hash; and
- minimum reversal delay.

`CanonicalExternalSettlementGateway` is immutable and non-upgradeable. Constructor
configuration binds the role manager, loan registry, asset registry, policy registry,
emergency controller, one approved loan factory, and one protocol version.

The only mutable economic identity storage is:

```text
payment ID    -> instruction digest
allocation ID -> instruction digest
payment ID    -> immutable settlement result
```

The instruction digest includes chain ID, gateway, finalizer, exact immutable loan policy
set, provider and reconciliation commitments, original journal set, source and target
assets and units, expected debt and state nonce, maturity deadline, attester, evidence,
and journal reference. The gateway has no proxy slot, upgrade hook, reserve balance,
arbitrary recipient, collateral reference, or general withdrawal mapping.

## Go coordination

The shared allocation-mode registry stores:

```text
payment ID -> allocation ID + mode + digest + canonical state
allocation ID -> payment ID
reversed payment ID -> permanent tombstone
```

Mode is exactly `SYNTHETIC_PROJECTION` or `CANONICAL_GATEWAY`. Phase 7A, Phase 7B,
and Phase 7C constructors require the same allocation-mode registry explicitly; none
silently creates a private latch or store. The registry has explicit in-memory and
`database/sql` stores, and both modes acquire the same durable payment claim. Canonical
states are `PREPARED`, `SUBMITTED`, `CONFIRMED`, `FAILED`, `QUARANTINED`, and
`INCIDENT`. Compare-and-set transitions bind the original digest. A canonical claim is
never released to Phase 7B, and a tombstoned payment cannot be reclaimed.

The settlement coordinator stores the immutable non-posting plan, versioned submission,
confirmed gateway event, pending reversal, tombstone, and reorganization evidence in a
versioned CAS snapshot plus append-only history. A submission binds chain, gateway,
sender, nonce, calldata hash, transaction hash, and time. An authenticated confirmation
binds the exact Solidity ABI/Keccak instruction digest, raw event payload,
transaction/receipt trie index and proof, signed receipt-block header, event/log/block
identity, and separately signed finality head. Only an indexer-owned,
inclusion-verified finalized reverted receipt may move a
submitted plan to `FAILED`; the canonical claim remains reserved for exact retry.
Prepared, failed, and submitted reversals first persist `QUARANTINED`. One SQL
transaction then derives and posts the Phase 7A opposite journals, records the reversal
and submitted-transaction failure proof when required, moves the coordinator to
`FAILED`, and creates the permanent tombstone before any retry is permitted. Submitted
resolution accepts only inclusion-verified indexer proof matching the stored chain,
gateway, transaction, and immutable finality-policy hash; prepared and failed resolution
accepts no transaction proof. All
coordinator states, claims, pending reversals, confirmations, and tombstones rehydrate
after restart. The combined snapshot retains the submission time; orphaned transaction
index, receipt root/proof, and receipt-header signature; policy and authority hashes;
replacement and detected-head signatures; monotonic detection time; and, for a deep
reorganization, the referenced confirmation and its confirmation-head signature. Only
`RecordReorg` can bind that full authority to the plan and commit its state transition.
The resulting opaque coordinator capability is reconstructed from a validated snapshot
after restart and is the only reorganization authority accepted by accounting.

The chain indexer verifies a pinned authority signature over each raw EVM header, derives
the block hash, parent, transaction root, receipt root, height, and timestamp from that
header, and verifies transaction and receipt Merkle-Patricia inclusion at one index. It
derives transaction identity from the included transaction and derives receipt status
and gateway logs only from the included receipt. It rejects noncanonical cumulative gas,
logs bloom, RLP, compact paths, and short-string trie child references. A prefix-complete
receipt set derives block-global log indexes without caller input. Per-proof limits are
supplemented by block-wide limits of 4,096 receipt proofs, 32 MiB of proof nodes, and
64 MiB total authenticated input.

The complete canonical gateway ABI log is then projected independently from loan
repayment events. It records payment/allocation uniqueness, source/target assets,
principal/excess, debt-before/after, recipients, gateway, transaction/log identity,
receipt root, inclusion-proof commitment, signed receipt header, evidence, and finality.
Its domain-separated finality-policy hash binds chain, gateway, confirmation depth, and
header-authority public key. Signed observation time is non-decreasing across canonical
appends and replacements. An identical signed header can only receive same-observation,
same-signature, nonconflicting proof enrichment; it cannot be replaced or backdated.
Only the indexer can promote a canonical projection after its configured signed-head
depth; callers cannot construct a verified projection. Replacing a block removes every
receipt and projection at and above the fork height and emits a lossless reorganization
envelope with orphaned/replacement block and complete signed authority evidence.

The current Ed25519 header authority is an explicit local/test trust root, not an EVM
consensus or light-client proof. It is safe only because every consumer pins the exact
finality-policy hash and this milestone uses no real funds, production keys, providers,
or networks. Selecting a production independently verifiable header source or light
client remains a deployment-blocking ADR.

## Protobuf

`payment.proto` adds:

- allocation-mode and canonicalization-state enums;
- the exact 21-field Solidity instruction and complete digest context;
- the exact 29-word gateway event, inclusion-verified log envelope, and signed-head
  finality proof;
- allocation-mode claim (including its exact claim digest) and eligibility evidence;
- non-posting plan and submission evidence;
- distinct source/target conversion evidence;
- canonical confirmation, lender payout, and borrower refund evidence;
- post-confirmation incident evidence; and
- lossless failed-transaction and deep-reorganization evidence, including receipt proof,
  policy/authority, and orphaned/replacement/detected-head signature commitments. The
  referenced finalized confirmation retains its separate confirmation-head signature.

These are additive messages and fields. Existing Phase 7A and Phase 7B meanings remain
unchanged. Coordinator state/version, exact snapshot authority, conversion evidence, and
target journal book remain relational source-of-truth records; they are intentionally not
duplicated as independent wire authority.

## PostgreSQL

Migration `000009_canonical_external_settlement.sql` adds:

- one unique allocation-mode claim used by both Phase 7B and Phase 7C, with a distinct
  exact-content claim digest and evidence digest;
- current coordinator CAS state and append-only transition history;
- eligibility, plan, and submission history;
- complete decoded gateway-event and finality projection;
- one-to-one source/target conversion evidence;
- canonical settlement confirmation and journal links;
- lender payout and borrower refund evidence;
- incident and deep-reorganization compensation records; and
- accounts `1260` and `9160`.

Every evidence and link table is append-only through `reject_posted_mutation()`.
Uniqueness spans payment, allocation, instruction, transaction/log, conversion,
confirmation, payout, refund, provider event, and compensation identities. The single
payment row and claim serialize concurrent Phase 7B/7C attempts. Eligibility and Phase
7A reversal lock that same payment row. The quarantine function persists the normalized
callback and immutable receipt before visibility; only the atomic reversal resolver can
post the reversal and mint a canonical tombstone. Triggers independently prove the
latest final and unreversed Phase 7A state, matched zero-difference reconciliation,
settled provider statement, exact payment-specific source journals, instruction digest,
finalized-event recipients, and complete journal roles. Deep compensation derives every
opposite journal and commits it with the reorg, owned incident, links, and compensation
evidence atomically and idempotently.

The sole supported callable durable success entry point is
`commit_canonical_external_settlement(jsonb, text, timestamptz, text)`. It locks the
payment and coordinator and accepts only an exact stored `snapshot.Confirmation` under
either normal durable `CONFIRMED` authority or submitted-origin durable `INCIDENT`
authority with the exact consumed pending reversal. It rejects `SUBMITTED`, unresolved
`QUARANTINED`, wrong-origin incidents, stale or changed evidence, and partial conflicts.
One transaction writes conversion, gateway event, confirmation, seven/eight journals and
links, payout, and optional refund; exact replay returns the same deterministic IDs.
Migration 000009 does not define a deployed runtime database role or revoke owner-level
table privileges. A future runtime-grant migration must make this function the permitted
write surface and deny direct success-table inserts before any networked deployment.

Reorganization storage preserves the full coordinator-issued envelope: submission time;
orphaned transaction index, receipt root, inclusion-proof and receipt-header signature;
finality-policy and header-authority hashes; confirmation-head, replacement, and
detected-head signature hashes; fork/depth/head identity; raw evidence; and detection
time. Deep compensation locks and matches that record to the exact durable coordinator
incident authority before deriving opposites.

## Ledger

The in-memory accounting proof stores seven journals without excess and eight with
excess. All journals commit through one `PostBatch`. Source and target assets never share
an unbalanced journal. The poster accepts only the coordinator's verified confirmation;
there is no public structurally forgeable posting authority. The adapter preserves the
chain, gateway, loan account, token, authorities, nonces, raw event hash, finality proof,
parties, and original journal provenance. Deep compensation accepts only an
authority-bound, coordinator-issued reorg capability. A `database/sql` repository
rehydrates durable confirmation and full reorganization evidence after restart.
Coordinator state/version and consumed-reversal authority are read from the exact CAS
snapshot; conversion hash is read from conversion evidence; target book is read from the
generated journal headers. Reorganization never edits the original batch. The
foundation-ledger executable remains an unwired local skeleton rather than a production
listener.

## Python model

The independent model retains only canonical integer units, maturity and reversal state,
conversion conservation, allocation result, and fault outcome. It contains no provider
credential, financial identifier, real account, production key, or network integration.
