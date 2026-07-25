# Phase 8 Local Release Evidence Contract

Status: frozen implementation contract for the local test-value Phase 8 exit

## Authority and gate order

Phase 8 has one authoritative generated bundle:

```text
protocol/deployments/local/phase8-release-evidence.json
```

The deploy-only blueprint and authenticated-flow file are transient assembly
inputs under reset-controlled roots. Per-domain files may remain deployment
diagnostics. The worker, release gate, and reset gate never treat any of those
inputs as authority and never fall back to them.

The gate order is:

```powershell
pwsh ./scripts/check-phase8-release-evidence.ps1 -Stage pre-reset
pwsh ./scripts/local-reset.ps1
pwsh ./scripts/check-phase8-release-evidence.ps1 -Stage post-reset
```

The pre-reset gate validates the completed bundle against both live Anvil RPCs,
the live labeled PostgreSQL container, receipts, calldata, ABI snapshots, and
runtime bytecode. Reset removes generated deployment and ephemeral report
directories. The post-reset gate accepts no manifest and independently requires
all labeled containers, volumes, and networks and both generated directories to
be absent. CI logs are the durable reset proof; no shadow evidence cache is
retained.

Generation starts with `runDeployOnly`, which creates configured contracts and
`phase8-live-blueprint.json` without executing synthetic messages. The
platform-neutral authenticated runner then drives the eight live messages and
writes `.cache/phase8-release/phase8-authenticated-flow.json`. Each of its
sixteen source/execution inclusions has already passed the production Phase 7C
signed-header transaction/receipt MPT verifier. The assembler accepts only
those two inputs plus the matching live RPC state; it has no
`phase8-evm-evidence.json` or synthetic-flow fallback.

The assembler may temporarily write the authoritative path with all
deployment/flow identity sections, the
`deployment_flow_sha256`, and `durable: null`. The worker consumes only that
path and records the same commitment. The augmenter atomically replaces
`durable: null` with complete evidence. The intermediate file is not valid
release evidence and cannot pass the gate.

Deployment diagnostics may declare
`proof_boundary: SYNTHETIC_SIGNED_HEADER_FIXTURE` while the proof producer is
not available. Such an artifact is explicitly `NOT READY`: it cannot populate
the authoritative completed bundle and the semantic gate always rejects it.

## Common representation

The final bundle conforms to:

```text
infrastructure/local/cross-chain/phase8-release-evidence.schema.json
```

The semantic and live validator is:

```text
tools/check_phase8_release_evidence.py
```

Required top-level fields are:

```text
schema_version = 1
artifact_type = PHASE8_RELEASE_EVIDENCE
environment = local
contains_real_value = false
run_id
protocol_id
proof_boundary = AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT
generated_at
source_commit
deployment_flow_sha256
domains
routes
exposure_policy
recovery
providers
flow
durable
reset
validation
```

Hashes are lowercase `0x`-prefixed Keccak-256 unless a field ends in
`sha256`. SHA-256 values are lowercase unprefixed 64-character hex. Addresses
are lowercase 20-byte hex. Units are canonical unsigned decimal strings.
Counts, versions, timestamps, indexes, and block numbers are JSON integers.

`source_commit` must equal the checked-out Git HEAD and the tracked worktree
must be clean. The bundle may contain public keys and public signatures. A key
name containing `private_key`, `mnemonic`, `seed`, `secret`, or raw signing
material is forbidden.

`deployment_flow_sha256` is SHA-256 over the UTF-8 JSON object containing,
exactly, `protocol_id`, `proof_boundary`, `domains`, `routes`,
`exposure_policy`, `recovery`, `providers`, and `flow`. Keys are recursively
sorted, `ensure_ascii` is false, separators are `,` and `:`, and there is no
trailing newline. No floats are permitted.

Addresses are unique within a domain. Equal deterministic deployment addresses
on different chains are valid because identity is `(chain_id, address)`.
Every address used outside a domain-contained contract record is
chain-qualified or accompanied by its chain and domain.

## Domains and deployed contracts

The home chain is 31337 and the satellite chain is 31338. Each domain records:

```text
chain_id
chain_version
rpc_url
genesis_hash
configuration_hash
activation_block
activation_timestamp
registry_status = ACTIVE
observer_fixture
observer_public_key_ed25519
observer_authority_hash
confirmation_depth
signer_set
contracts
registry_bindings
finality_policies
```

Home and satellite observer keys, observer-authority hashes, configuration
hashes, and signer-set hashes are distinct. Each signer set is version 1,
two-of-three, uses the canonical bytewise-sorted Anvil addresses, and covers
the complete flow validity interval.

Every contract record has an exact reviewed ABI:

```text
address
runtime_code_hash
abi_path
abi_sha256
deployment_kind
deployment_tx_hash
deployment_block_number
```

`CREATE_TRANSACTION` requires a successful receipt whose `contractAddress`
equals the manifest address. The loan account is `INTERNAL_CREATE2` and also
records `creation_event` with the factory emitter, canonical
`CrossChainLoanCreated(bytes32,address,address,address,bytes32)` signature and
topic, loan ID, and indexed ID/address topic positions. Its factory receipt,
event, created address, ABI, and live code must all match.

Home contracts include role manager, chain registry, emergency controller,
route registry, finality verifier, coordinator, recovery controller, canonical
UFT, loan registry, bridge exposure policy, bridge hub, loan-account deployer,
loan factory, loan policy, and the created loan account. Satellite contracts
include role manager, chain registry, emergency controller, route registry,
finality verifier, coordinator, recovery controller, collateral token, wrapped
UFT, satellite loan component, collateral vault, and settlement vault.

Both chain registries must contain both domain version-1 records with the exact
coordinator, verifier, live code hashes, configuration hash, activation
timestamp, and ACTIVE status. Both verifiers must contain both active signer
sets. Each route registry and verifier must expose its exact manifest
`chainRegistry()` binding.

## Routes, finality, exposure, recovery, and providers

The bundle contains exactly these seven route purposes:

```text
MINT
REPORT
REPAYMENT
ALTERNATE_REPAYMENT
BRIDGE_EXIT
DISBURSEMENT
COLLATERAL_RELEASE
```

Each route contains every Solidity `RouteConfig` field and:

```text
purpose
version
route_policy_hash
source_domain
destination_domain
home_registration_tx_hash
home_registration_block_number
satellite_registration_tx_hash
satellite_registration_block_number
home_registry_hash
satellite_registry_hash
```

`route_policy_hash`, `home_registry_hash`, and `satellite_registry_hash` must
equal:

```text
keccak256(abi.encode("UNIFIED_XCHAIN_ROUTE_V1", routeConfig))
```

The validator checks the exact live route tuple and one canonical registration
event and successful registration receipt on each domain.

Each domain contains source and destination-evidence finality policies for all
seven routes. Every policy contains all Solidity
`FinalityPolicyConfig` fields plus `route_purpose` and `policy_hash`.
`policy_hash` must equal:

```text
keccak256(
  abi.encode("UNIFIED_SYNTHETIC_FINALITY_POLICY_V1", finalityPolicyConfig)
)
```

The exact tuples must exist on both live verifiers.

The home MINT route pins one active bridge exposure policy. The bundle records
the exact policy version and hash, frozen circulating-supply reference and
evidence hash, route/chain/adapter/aggregate absolute caps, route and aggregate
percentage ceilings, activation delay, and activation timestamp. The validator
recomputes
`keccak256(abi.encode("UNIFIED_BRIDGE_EXPOSURE_POLICY_V1", exposureConfig))`,
requires byte equality with the live policy tuple, requires the live MINT route
to select that policy, and requires the supply reference to equal the synthetic
canonical token's immutable `MAX_SUPPLY`. A cap increase or any supply
reference/evidence change remains subject to the minimum risk-increase delay.

Recovery is `TOMBSTONE_THEN_COMPENSATE`, version 1, two-of-three. The validator
recomputes its authorizer-set hash and checks each controller's
`authorizerSetHash`, signer array, coordinator, route registry, and verifier.
Provider A and B are distinct loopback transports with
`authority: TRANSPORT_ONLY`. Their bytewise-sorted `(id, authority)` pairs
define `UNIFIED_LOCAL_ADAPTER_SET_POLICY_V1`; every route pins that exact hash.

## Full-flow and cryptographic evidence

The flow has chain-qualified loan-account and asset references, positive
principal/collateral units, eight ordered messages with action ordinals
1, 5, 2, 6, 7, 8, 9, and 10, three broadcast replays, and exact terminal state.

Each message contains:

```text
sequence
route_purpose
envelope
payload
source
provider_attempts
destination
acknowledgement
source_final = true
destination_executed = true
```

`envelope` is the complete Solidity `MessageEnvelope`. `payload` is the exact
public calldata bytes. Source and acknowledgement evidence each contain the
complete `SourceEventProof`, complete `FinalityCertificate`, proof/certificate
IDs and hashes, all public signatures, and exact transaction/block/index/log
identity. Destination and acknowledgement records contain exact receipt
identity and result/commitment.

There are two independently validated evidence surfaces, and neither
substitutes for the other:

1. The outer `source`, `destination`, and `acknowledgement` receipt fields are
   live local-chain identities. The gate reads those transactions, blocks,
   calldata, logs, stored results, and acknowledgement commitments from Anvil.
2. The nested `proof` and `authenticated_inclusion` fields carry the exact
   signed local header, prefix-complete transaction/receipt RLP and
   Merkle-Patricia proofs, and a contiguous signed confirmation-header chain.
   The gate verifies both trie inclusions, canonical receipt/log decoding,
   Phase 7C inclusion hash, every Ed25519 header signature and parent link,
   configured depth, proof commitment, and ECDSA certificate.

For exit-ready evidence the two surfaces must identify the same source or
destination event. A valid live RPC receipt cannot substitute for a missing or
invalid authenticated inclusion proof, and a valid authenticated proof cannot
substitute for a missing or different live RPC receipt.

`authenticated_inclusion.receipts` is prefix-complete from transaction index
zero through `proof.transaction_index`; the last element is the target, so
there is no caller-selected second target index. This permits derivation of the
block-global log index. Each inclusion records:

```text
header_rlp
header_observed_at_unix_nanos
header_signature_ed25519
receipts[].{
  transaction_index
  transaction_rlp
  transaction_proof_nodes
  receipt_rlp
  receipt_proof_nodes
}
confirmation_headers[].{
  header_rlp
  header_observed_at_unix_nanos
  header_signature_ed25519
}
```

`header_observed_at_unix_nanos` is a canonical unsigned decimal string so its
uint64 signing value is not rounded by JSON tooling. `confirmation_headers`
contains exactly `proof.required_depth` headers, starts at the next height,
links every parent, and ends at the declared finality head. The same Phase 7C
per-node, per-proof, aggregate 32 MiB proof, and aggregate 64 MiB input bounds
apply.

This milestone verifies transaction and receipt MPT inclusion under pinned
Ed25519-authenticated local headers. It does not verify EVM consensus and does
not establish a production light client; the header signer remains an explicit
local/test trust root. The separate live-receipt checks demonstrate execution
on the two ephemeral Anvil chains only.

The validator:

- recomputes lane, message, payload, source-event, acknowledgement,
  observer-header, proof, certificate, route, finality, signer-set, recovery,
  chain-configuration, and adapter-set commitments;
- verifies each 64-byte Ed25519 observer signature against the exact domain
  public key;
- independently recovers a distinct canonical ECDSA two-of-three quorum;
- reconstructs exact `executeMessage` and `recordAcknowledgement` calldata and
  requires byte equality with each live transaction input;
- checks source, execution, and acknowledgement events/receipts and live
  `executionResult`/`acknowledgementCommitment`; and
- requires the exact public proof/certificate evidence to be stored in SQL.

At least one message records retryable Provider A failure followed by Provider
B delivery of the same immutable message, payload, and proof. These attempts
must be observed HTTP effects, not assembler fixtures: the flow runner posts
the exact message ID, serialized envelope and Keccak hash, serialized source
proof and proof hash, and payload hash to the loopback provider. Every response
must identify the configured provider, assert only `TRANSPORT_ONLY`, and state
`contains_real_value: false`. Provider A returns the approved retryable 503
fixture for sequence 1, Provider B accepts the same delivery, and Provider A
accepts sequences 2 through 8.

Each public attempt includes `transport_receipt_hash`, the Keccak-256 hash of
compact recursively sorted-key UTF-8 JSON with exact keys `body` (the parsed
provider response object) and `status_code` (the observed HTTP integer).
Delivered SQL attempts persist this exact receipt hash. Failed public attempts
retain their observed response hash, while their SQL provider-receipt field
remains null.

Mint, repayment, and collateral-release replays each record their destination
chain, broadcast transaction/block identity, original and replay result,
`economic_effect_delta_units: "0"`, and `duplicate_prevented: true`. The
successful replay receipt may not contain another execution or economic event,
and live stored execution remains unchanged.

The exact terminal state is CLOSED, zero outstanding principal, bridge/loan
backing, wrapped supply, route/aggregate exposure, settlement/collateral vault
balance, and duplicate effects, with collateral released and principal
disbursed/repaid exactly once. The validator independently checks loan, hub,
token, vault, collateral-record, disbursement-event, and lender-release state on
the live chains.

## Durable evidence

`durable.input_deployment_flow_sha256` equals the recomputed top-level
commitment. `durable.sql.tables` contains `{row_count, ordered_sha256}` for:

```text
crosschain.acknowledgements
crosschain.action_projections
crosschain.bridge_backing_snapshots
crosschain.bridge_exposure_policies
crosschain.bridge_exposure_snapshots
crosschain.bridge_locks
crosschain.bridge_reconciliation_differences
crosschain.bridge_reconciliations
crosschain.canonical_burns
crosschain.canonical_releases
crosschain.chain_versions
crosschain.chains
crosschain.collateral_positions
crosschain.collateral_release_authorizations
crosschain.collateral_release_results
crosschain.compensations
crosschain.direct_home_repayment_evidence
crosschain.direct_home_repayment_results
crosschain.disbursement_authorizations
crosschain.disbursement_results
crosschain.execution_results
crosschain.finality_certificates
crosschain.header_observations
crosschain.incidents
crosschain.inbox
crosschain.loan_cancellation_completions
crosschain.loan_cancellation_requests
crosschain.loan_routes
crosschain.message_transitions
crosschain.messages
crosschain.outbox
crosschain.provider_attempts
crosschain.repayment_results
crosschain.recovery_authorizer_sets
crosschain.recovery_requests
crosschain.reorganizations
crosschain.route_versions
crosschain.routes
crosschain.signer_sets
crosschain.source_proofs
crosschain.tombstones
crosschain.wrapped_burns
crosschain.wrapped_mints
ledger.bridge_journal_links
ledger.crosschain_recovery_journal_links
ledger.satellite_custody_links
ledger.satellite_settlement_links
public.journal
public.journal_entry
```

For a table, `ordered_sha256` is SHA-256 of a recursively key-sorted,
whitespace-free JSON array of `to_jsonb` rows ordered by the table primary
key. `sql.state_sha256` is SHA-256 of the same canonical JSON encoding of the
table-name object mapping to `{ordered_sha256,row_count}`.

The table set is exact: all 49 names are present, no other name is accepted,
and a zero-row table must be declared in `allowed_empty_tables`. Tables needed
to prove the completed workflow, trust configuration, economic effects, and
linked journals may never be declared empty. The canonical eight-message
happy path does not exercise cancellation, so both cancellation authority
tables are present in the commitment and explicitly allowed to be empty.

`ledger.journal_set_sha256` uses the same canonical JSON-array encoding. Each
row is exactly `{"journal": <journal row>, "entries": [<entry rows>]}`;
journals are ordered by `journal_id`, and entries by `line_number`.

The gate independently queries the live labeled PostgreSQL container for every
count/hash and the exact EVM proof/certificate rows. It also recomputes the
linked journal set, journal/entry counts, debit/credit totals, and requires
exact balance. Restart pre/post state hashes and delivery counts are equal,
rehydration is true, and duplicates are prevented. The live reconciliation row
is MATCHED with zero differences. State parity is MATCHED with zero
differences.

`durable.object_store` proves that all sixteen source and acknowledgement
authenticated-inclusion JSON objects were written to the
`crosschain-evidence` bucket under deterministic content-addressed keys. Each
entry records the exact Keccak-256 and byte length, and
`object_set_sha256` commits to the canonical 16-entry mapping. After the local
services are closed and reopened, every object must be fetched and match its
original bytes; `rehydrated` may be true only after that comparison.

## Reset plan and validation summaries

Pre-reset evidence records only:

```text
command = pwsh ./scripts/local-reset.ps1
required_before.{labeled_containers,labeled_volumes,labeled_networks,deployment_artifacts}
expected_after.{labeled_containers,labeled_volumes,labeled_networks,deployment_artifacts}
remove_deployment_directory = true
remove_cache_directory = true
```

Required-before counts are positive; every expected-after count is zero. There
is no pre-reset `completed` assertion and no `validation.reset_complete`.
Post-reset derives absence directly without reading a manifest.

All twelve final validation summary booleans are true: deployment, live code,
trust, explicit proof-boundary disclosure, authenticated inclusion,
Solidity hashes, full flow, replay, restart, balanced journals, reconciliation,
and state parity. They are summaries only; detailed/live checks remain
authoritative.

Changing a required field, commitment preimage, route/action set, terminal
equation, durable table, or reset condition requires an accepted ADR and an
intentional schema-version increment.
