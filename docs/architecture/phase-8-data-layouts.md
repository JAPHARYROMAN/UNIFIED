# Phase 8 Data and Storage Layouts

Status: implementation boundary for synthetic local engineering

## Data authority rules

Phase 8 stores the same workflow in several systems, but authority does not move between
them:

- source contracts are authoritative for source locks, burns, custody, and settlements;
- destination contracts are authoritative for verification, execution, results, and
  tombstones;
- the home loan account is authoritative for loan economics;
- the home bridge hub and canonical UFT are authoritative for backing and canonical
  supply;
- the satellite `WrappedUFT` contract is authoritative for wrapped supply;
- authenticated finalized events are authoritative inputs to projections and accounting;
- PostgreSQL owns durable coordination and immutable journal records but cannot create a
  chain effect; and
- Redpanda, MinIO, providers, and application read models are replayable evidence or
  delivery systems, never economic authority.

Every stored record uses canonical integer token units, explicit asset identities, UTC
timestamps, a schema version, source authority, correlation and causation identifiers,
and a stable integrity commitment. No generic JSON payload is accepted by an on-chain
dispatcher.

## Canonical Solidity types

`CrossChainTypes.sol` defines fixed-width enums and structs. Enum ordinal values are
append-only; an existing value can never be renamed to a different meaning.

```text
Domain {
  chainId
  coordinator
  configurationHash
}

Lane {
  laneId
  sourceChainId
  sourceComponent
  destinationChainId
  destinationComponent
  aggregateId
  actionFamily
}

MessageEnvelope {
  schemaVersion
  messageId
  protocolId
  sourceChainId
  sourceCoordinator
  sourceComponent
  destinationChainId
  destinationCoordinator
  destinationComponent
  laneId
  sourceNonce
  aggregateId
  actionType
  payloadHash
  createdAt
  expiresAt
  routePolicyHash
  adapterSetPolicyHash
  sourceFinalityPolicyHash
  destinationFinalityPolicyHash
  correlationId
  causationMessageId
  supersededMessageId
}

SourceEventProof {
  sourceBlockHash
  sourceBlockNumber
  sourceBlockTimestamp
  transactionHash
  transactionIndex
  receiptRoot
  receiptProofHash
  logIndex
  eventHash
  finalityHeadHash
  finalityHeadNumber
  requiredDepth
  headerAuthorityHash
  finalityPolicyHash
}

FinalityCertificate {
  messageId
  sourceProofHash
  signerSetHash
  signerSetVersion
  signatures[]
}

ExecutionResult {
  messageId
  laneId
  sourceNonce
  actionType
  target
  resultHash
  executedAt
}

MessageTombstone {
  originalMessageId
  originalInstructionHash
  recoveryNonce
  reasonCode
  tombstonedAt
}
```

Dynamic signatures are bounded to the registered signer-set size. Proof bytes are not
stored wholesale on chain; the certificate stores commitments and the exact fields
needed for verification and audit. All ABI hashes use `abi.encode`, never
`abi.encodePacked`.

## Registries and coordinator storage

### `ChainRegistry`

```text
chain ID -> append-only ChainVersion[]
ChainVersion {
  version
  coordinator
  finalityVerifier
  configurationHash
  activatedAtBlock
  deprecatedAtBlock?
  status
}
```

### `RouteRegistry`

```text
route ID -> append-only RouteVersion[]
RouteVersion {
  version
  sourceChainId
  sourceComponent
  destinationChainId
  destinationComponent
  actionFamily
  adapterId
  adapterCodeHash
  providerSetHash
  finalityPolicyHash
  signerSetHash
  absoluteCap
  chainCap
  adapterCap
  activatedAtBlock
  deprecatedAtBlock?
  status
}
```

The `routePolicyHash` commits to every field that can affect source authentication,
destination dispatch, finality, ordering, or exposure. Provider preference order is
operational data and is not part of the economic message identity; the approved provider
set commitment is.

### `SyntheticFinalityVerifier`

```text
signer-set hash -> immutable SignerSetVersion
SignerSetVersion {
  version
  threshold
  signers[]
  validFrom
  validUntil
  status
}
```

The verifier keeps no mutable success oracle. It validates an exact certificate against
the route-pinned signer-set and policy versions.

### `CrossChainCoordinator`

```text
lane ID -> next outbound nonce
lane ID -> next inbound nonce
message ID -> immutable envelope fields
message ID -> terminal execution result
message ID -> permanent tombstone
message ID -> acknowledgement commitment
recovery lane ID -> next recovery nonce
```

The result and tombstone mappings are mutually exclusive. A successful execution stores
the immutable envelope fields keyed by their recomputed message ID before the target
call returns from the same transaction. Exact
replay reads the stored result. There is no method that deletes a consumed nonce, result,
acknowledgement, or tombstone.

### `CrossChainRecoveryController`

```text
recovery ID -> request digest
recovery ID -> signer bitmap
recovery ID -> state
original message ID -> recovery ID
```

The request digest binds the original message ID and immutable envelope, route versions,
assets, amount, source and destination state commitments, expiry, reason, recovery
action, nonce, and authorizer-set version. A recovery record cannot directly write the
coordinator result or tombstone mappings.

## Satellite loan storage

`CrossChainLoanAccount` is a new home-authoritative account rather than an upgrade to an
existing `CoreLoanAccount`. Its immutable fields are:

```text
loanId
protocolId
homeChainId
borrower
lender
principalAssetId
principalUnits
satelliteChainId
satelliteLoanComponent
collateralVault
settlementVault
collateralAssetId
collateralUnits
crossChainPolicyHash
policySetHash
routePolicyHash
factory
protocolVersion
```

Its bounded mutable state is:

```text
canonical loan state
outstanding principal units
loan state nonce
collateral position commitment
disbursement instruction/result commitments
cumulative finalized repayment units
direct home payment IDs and result commitments
release instruction/result commitments
last accepted action sequence by action family
```

It stores no provider identity, retry count, arbitrary target, arbitrary recipient,
mutable rate, or generic remote call.

`SatelliteLoanComponent` stores the home loan identity and the action sequence/result
for each exact command. It cannot store or mutate canonical debt or terms.

`SatelliteCollateralVault` stores:

```text
positionId
homeChainId
homeLoanAccount
loanId
borrower
asset
units
policySetHash
lockTransactionCommitment
state = NONE | LOCKED | RELEASED
releaseMessageId?
```

The key `(satellite chain, vault, asset, positionId)` is unique. The position has one
home loan and one borrower for its lifetime. There is no fractional or reusable
collateral state in Phase 8.

`SatelliteSettlementVault` stores:

```text
loanId
homeLoanAccount
borrower
lender
settlementAsset
authorizedDisbursementUnits
mintedEscrowUnits
disbursedUnits
cumulativeBurnedRepaymentUnits
disbursementMessageId
repayment IDs -> exact wrapped burn result
```

Each disbursement result binds pre/post vault and borrower balances. Each repayment
result binds the borrower balance, wrapped total-supply delta, home lender, and intended
canonical backing release. The vault has no caller-selected lender or borrower and no
general withdrawal function.

## Wrapped UFT storage

### `UFTBridgeHub`

Immutable configuration:

```text
protocolId
homeChainId
canonicalUFT
chainRegistry
routeRegistry
coordinator
exposurePolicy
emergencyController
```

Mutable storage:

```text
route ID -> canonical escrow units
chain ID -> canonical escrow units
adapter ID -> canonical escrow units
aggregate canonical escrow units
lock ID -> immutable lock instruction and state
burn ID -> immutable redemption or permanent-burn instruction and state
message ID -> exact bridge result
```

The hub's actual canonical UFT balance must equal the sum of route escrow units. Backing
is restricted at lock time and reduced only by an exact finalized wrapped burn followed
by canonical release or burn, or by exact tombstone-authorized compensation of an
unexecuted mint.

### `BridgeExposurePolicy`

```text
policy version
frozen circulating-supply reference units
circulating-supply evidence hash
per-route absolute cap
per-chain absolute cap
per-adapter absolute cap
aggregate absolute cap
per-route percentage ceiling <= 5%
aggregate percentage ceiling <= 15%
effective block
status
```

Policy versions are append-only. Exposure increases use the newly activated delayed
version. The frozen reference is derived from synthetic canonical supply and registered
non-circulating fixture balances, cannot exceed canonical total supply, and is never
accepted from a bridge caller. Lower limits apply to new locks while all exit paths
remain callable.

### `WrappedUFT`

Immutable configuration:

```text
name and symbol
decimals = canonical UFT decimals
canonical home chain ID
canonical UFT address
home bridge hub
satellite coordinator
route policy hash
```

Mutable storage is standard ERC-20 balances, allowances, and total supply plus:

```text
mint message ID -> mint result
burn ID -> burn result
```

The only issuance primitive is coordinator-restricted and accepts a verified typed mint
instruction. It has no role-grantable generic minter, post-deployment canonical identity
change, voting checkpoints, collateral adapter, rescue mint, or upgrade hook.

## Protobuf schema

`schemas/proto/unified/v1/crosschain.proto` becomes the canonical wire source. Existing
`finance.proto.CrossChainMessage` remains readable for compatibility but is not
sufficient authority for Phase 8 execution. It is deprecated only after all consumers
move to the versioned Phase 8 envelope.

The schema defines:

- `CrossChainActionType`, with the six loan actions and UFT mint, redemption,
  permanent-burn, cancellation, tombstone, and acknowledgement actions;
- `CrossChainMessageState` and `CrossChainRecoveryState`;
- `CrossChainDomain`, `CrossChainLane`, `CrossChainMessageEnvelope`;
- typed payload messages for every supported action;
- `AuthenticatedSourceEvent`, `SyntheticFinalityCertificate`;
- `ProviderDeliveryAttempt`, `CrossChainExecutionResult`, `CrossChainAcknowledgement`;
- `CrossChainCancellationRequest`, `CrossChainTombstone`, `CrossChainCompensation`;
- `BridgeExposureSnapshot`, `WrappedUFTBackingSnapshot`;
- `CrossChainReconciliationDifference`; and
- source/destination reorganization and incident evidence.

`CrossChainMessageState` uses the exact canonical values:

```text
CREATED
SOURCE_FINALIZING
SOURCE_FINAL
SENT
RELAYED
VERIFIED
EXECUTED
ACK_PENDING
ACKNOWLEDGED
REJECTED
FAILED
EXPIRED
RECOVERY_PENDING
DESTINATION_TOMBSTONED
SOURCE_COMPENSATED
RECOVERED
DISPUTED
```

Database checks and language enums use these meanings without aliases. Shorter state
vocabularies in governing specifications are mapped projections, not additional states.

### Required envelope fields

```text
schema_version
message_id
protocol_id
source_chain_id
source_coordinator
source_component
destination_chain_id
destination_coordinator
destination_component
lane_id
source_nonce
aggregate_id
action_type
typed_action_payload
payload_hash
created_at
expires_at
route_policy_hash
adapter_set_policy_hash
source_finality_policy_hash
destination_finality_policy_hash
correlation_id
causation_message_id
superseded_message_id
```

Identifiers, addresses, integers, hashes, and timestamps use the existing shared types
where compatible. The canonical Solidity digest fields are never represented as
floating-point numbers or human-formatted amounts. Generated bindings must be
deterministic in Solidity, Go, TypeScript, and Python, and golden fixtures must prove
cross-language digest parity.

Typed payloads include every identity and amount used by destination execution. A
consumer rejects an action when the selected oneof type, `action_type`, schema version,
or recomputed `payload_hash` disagree.

## PostgreSQL migrations

Phase 8 uses three additive migrations.

### `000010_crosschain_messages.sql`

Schemas and tables:

```text
crosschain.chains
crosschain.chain_versions
crosschain.routes
crosschain.route_versions
crosschain.signer_sets
crosschain.messages
crosschain.message_transitions
crosschain.source_proofs
crosschain.finality_certificates
crosschain.provider_attempts
crosschain.execution_results
crosschain.acknowledgements
crosschain.recovery_requests
crosschain.tombstones
crosschain.compensations
crosschain.reorganizations
crosschain.incidents
crosschain.outbox
crosschain.inbox
```

`crosschain.messages` includes:

```text
message_id PK
schema_version
protocol_id
source_chain_id
source_coordinator
source_component
destination_chain_id
destination_coordinator
destination_component
lane_id
source_nonce
aggregate_id
action_type
payload_hash
message_created_at
expires_at
route_policy_hash
adapter_set_policy_hash
source_finality_policy_hash
destination_finality_policy_hash
correlation_id
causation_message_id
superseded_message_id
state
state_version
created_at
updated_at
```

The `state` constraint admits only the canonical `CrossChainMessageState` values listed
above.

Required uniqueness includes:

```text
(source_chain_id, source_coordinator, lane_id, source_nonce)
(destination_chain_id, destination_coordinator, message_id)
(destination_chain_id, destination_coordinator, lane_id, source_nonce)
(source_chain_id, transaction_hash, log_index)
(message_id, provider_id, attempt_number)
original_message_id in tombstones
original_message_id in terminal compensations
```

State transitions are CAS updates of the current row plus an append-only transition
insert in one transaction. Execution results, tombstones, and compensations have
cross-table exclusion triggers so mutually exclusive terminal outcomes cannot coexist.
Inbox acquisition and the corresponding durable effect commit atomically. Outbox
delivery is at-least-once; destination execution remains at-most-once.

### `000011_satellite_loan_accounting.sql`

Tables:

```text
crosschain.loan_routes
crosschain.collateral_positions
crosschain.disbursement_authorizations
crosschain.disbursement_results
crosschain.repayment_results
crosschain.direct_home_repayment_results
crosschain.collateral_release_authorizations
crosschain.collateral_release_results
ledger.satellite_custody_links
ledger.satellite_settlement_links
```

Uniqueness spans loan, collateral position, disbursement message, repayment message,
release message, transaction/log, and journal idempotency identities. Database
constraints enforce one loan per collateral position, one disbursement, cumulative
repayment not above principal for the first slice, and one release after the exact home
authorization. A direct home repayment has a unique payment ID, changes only canonical
loan debt and lender balance, and cannot consume a wrapped burn or change bridge backing.

The callable commit functions accept only the exact stored finalized chain projection.
They derive recipients, assets, amounts, and journal roles from registered immutable
records rather than caller JSON. Exact replay returns the original record identities.

### `000012_wrapped_uft.sql`

Tables:

```text
crosschain.bridge_locks
crosschain.wrapped_mints
crosschain.wrapped_burns
crosschain.canonical_releases
crosschain.canonical_burns
crosschain.bridge_exposure_snapshots
crosschain.bridge_backing_snapshots
crosschain.bridge_reconciliations
crosschain.bridge_reconciliation_differences
ledger.bridge_journal_links
```

Uniqueness spans route and lock ID, burn ID, message ID, source transaction/log,
destination transaction/log, recipient, and journal idempotency identity. Triggers
require lock before mint, burn before release, one terminal disposition per burn, exact
amount equality, and the registered route, token, hub, and wrapped-token identities.

Exposure snapshots store the numerator, denominator, circulating-supply evidence, every
applicable absolute cap, percentage ceiling, policy version, block identity, and
calculated headroom. They are evidence and cannot override the hub's on-chain cap check.

## Least-privilege database boundary

Migration 000010 creates or documents:

- a `NOLOGIN` schema owner;
- a runtime role with `CONNECT` and schema `USAGE`;
- read access to immutable reference and projection tables;
- execute access only to reviewed transition and accounting functions; and
- no direct insert, update, delete, truncate, trigger-disable, role-grant, or DDL rights
  on authoritative message, result, tombstone, compensation, reconciliation, or ledger
  tables.

Test fixtures prove the runtime role cannot forge a finalized proof, execution result,
tombstone, bridge mint, loan repayment, reconciliation closure, or journal. Migration
and break-glass roles are absent from service configuration.

## Go service state

`services/cross-chain-coordinator` is divided into:

```text
message/
  canonical digest, validation, lane ordering, state transitions
provider/
  provider interface, exact-byte attempts, failover policy
recovery/
  expiry, cancellation, tombstone, compensation, incident
store/
  database/sql CAS repositories, outbox/inbox, restart rehydration
reconciliation/
  cross-domain, vault, backing, supply, nonce, and ledger comparison
```

The service stores no private fallback authority. Constructors require the shared SQL
store, chain-specific indexers, exact route configuration, provider registry, and
ledger/reconciliation adapters. A production-looking default or silent in-memory store
is forbidden.

Provider workers persist the exact serialized envelope and proof hash before submission.
Retries read those immutable bytes. A successful provider response changes only attempt
state. Chain observers, not providers, create verified destination results.

After restart, workers rehydrate current CAS state and reconcile it with both canonical
chains before sending. If chain and SQL disagree, the message enters a visible exception
or incident; the service does not infer success from a delivery receipt.

## Event and object storage

Redpanda topics are versioned and include:

```text
unified.crosschain.source-finalized.v1
unified.crosschain.delivery-requested.v1
unified.crosschain.destination-executed.v1
unified.crosschain.acknowledged.v1
unified.crosschain.recovery-requested.v1
unified.crosschain.tombstoned.v1
unified.crosschain.reconciliation-difference.v1
unified.crosschain.incident.v1
```

Every consumer uses an inbox key based on the canonical event or message ID. Publishing
uses a transactional outbox. Topics may redeliver and reorder; no consumer relies on
broker ordering for economic safety.

MinIO stores bounded raw synthetic RLP headers, transaction and receipt proof nodes,
certificates, provider receipts, and reconciliation evidence. PostgreSQL stores their
content hashes, sizes, media/schema types, authority, retention class, and object
version. Object storage cannot replace the exact on-chain and relational commitments.

## Ledger data

The Phase 8 account codes and their definitions are frozen in 8A before use:

```text
1410 Canonical Assets Locked for Bridging
1420 Cross-Chain Settlement Receivable
1430 Satellite Asset Receivable
2230 Bridge Backing Liability
5120 Cross-Chain Messaging Expense
5320 Bridge Loss
7150 UFT Locked in Bridge Escrow Control
7160 Wrapped UFT Outstanding Control
9150 Pending Cross-Chain Settlement
9180 Ledger-to-Chain Reconciliation Difference
```

Each journal row retains:

```text
message ID
source and destination chain
route and policy versions
loan, position, lock, or burn ID
source and destination transaction/log identities
asset ID and native integer units
finality and proof commitments
accounting authority
idempotency key
correlation and causation IDs
```

Different asset identities never share an unbalanced journal. Source locks, destination
mints, satellite custody, disbursement, lender settlement, wrapped burns, canonical
releases, permanent burns, and compensations remain separate postings tied to their
actual finalized effects. Pending and expired messages stay in suspense or control
records; they are not cash, revenue, loss, or final settlement.

Posted journals and links are append-only. Corrections and deep-reorganization handling
use linked opposites with the original evidence and incident authority. A ledger outage
after chain execution replays the exact posting command; it never resubmits the chain
action.

## Reconciliation layouts

Each reconciliation run stores:

```text
run ID and type
home and satellite chain heads and finality policies
route and policy versions
contract and token identities
source balances and event totals
destination balances and event totals
ledger balances and control totals
pending message set
calculated difference
evidence hashes
started/completed times
owner and status
```

Each difference stores:

```text
difference ID
run ID
dimension and reason code
expected and observed integer units
asset ID
message/loan/position/lock/burn references
source evidence
severity
detected time
owner
resolution deadline
status
resolution or opposite-journal reference
```

Critical supply, backing, double-execution, double-collateral, or double-release
differences pause new route exposure and open an incident. Closing a difference requires
new reconciled evidence; changing its status cannot rewrite the original values.

## Local deployment manifests

The home manifest records:

```text
chain ID 31337
genesis/configuration hash
RPC and observer fixture name
confirmation depth
observer public key
finality signer-set hash
all registry, coordinator, loan, UFT, bridge, and policy addresses
deployment transaction and block identities
ABI and bytecode hashes
```

The satellite manifest records the analogous chain ID `31338`, coordinator, verifier,
loan component, collateral vault, settlement vault, wrapped UFT, route, and deployment
identities.

Addresses are never copied between manifests without their chain ID. The smoke harness
verifies every manifest identity against deployed bytecode before seeding synthetic
assets or submitting a message.

Provider A and B configurations contain only local URLs and fixture identifiers.
Observer, finality, relayer, borrower, lender, and governance keys are obvious test-only
fixtures generated for the local run and destroyed by reset.

## Rebuild and retention

The canonical rebuild order is:

```text
chain registries and route versions
-> authenticated source event archive
-> source-finality projections
-> messages and transition history
-> destination execution, result, ack, and tombstone projections
-> loan, bridge, custody, and wrapped-supply projections
-> immutable accounting links
-> reconciliations, differences, and incidents
```

A rebuilt projection must produce the same message digests, terminal outcomes, nonce
heads, collateral ownership, loan debt, bridge escrow, wrapped supply, journal
idempotency keys, and open differences. Provider attempt history is useful operational
evidence but is not required to reconstruct economic authority.

Raw proof retention must be long enough to reproduce every active message, unresolved
recovery, open incident, journal, and bridge obligation. Phase 8 local tests retain all
synthetic evidence. Production retention and jurisdictional deletion rules are deferred.

## Storage acceptance properties

- one `(lane_id, nonce)` has one immutable message ID and envelope;
- one message has at most one execution result or tombstone, never both;
- one source event key has one canonical projection at a given chain history;
- one provider attempt can be replayed without becoming execution authority;
- one collateral position belongs to one loan for its lifetime;
- one disbursement, repayment event, release, mint, burn, canonical release, permanent
  burn, compensation, or journal idempotency key creates at most one effect;
- the hub token balance equals the sum of route escrow obligations;
- wrapped supply and escrow snapshots satisfy the route and global backing equations;
- SQL and language encoders reproduce the Solidity digest golden vectors exactly;
- runtime database credentials cannot manufacture terminal or financial authority;
- append-only triggers reject mutation and deletion of proofs, transitions, results,
  tombstones, compensation, journals, differences, and incidents;
- every projection is restart-rehydratable and rebuildable from retained canonical
  evidence; and
- reset removes only the explicitly named local fixture volumes and regenerates a clean
  synthetic topology.

## Production data deferrals

The Phase 8 layouts do not define production signer custody, HSM/KMS records, real
provider secrets, public endpoints, personal data, financial account identifiers, live
asset metadata, chain-specific consensus proofs, bridge vendor evidence, production
retention, regional backup, disaster recovery, regulatory books, tax records, or
cross-jurisdiction reconciliation.

No field named `manual_override`, `force_success`, `force_mint`, `force_release`,
`force_unlock`, or equivalent is permitted. Any future production recovery record must
retain multi-party authorization, independently verifiable source and destination
evidence, amount bounds, immutable replay-safe identifiers, complete audit provenance,
and an accounting disposition.
