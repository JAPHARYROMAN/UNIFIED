# Phase 9 Refinance Reference Evidence

Status: normative preimage and vector-input boundary; implementation evidence pending

Date: 2026-07-27

## Purpose

This document fixes the independent evidence model required by ADR 0021, ADR 0022,
ADR 0023's candidate-only fixed-module partition, ADR 0025's D3 execution-semantics
freeze, and the `P9R-*` acceptance matrix.
It does not claim that a Solidity implementation or a golden-output bundle exists. The
first accepted implementation checkpoint must
publish the calculated outputs for these exact inputs from Solidity, Go,
TypeScript, and Python and prove byte equality.

All formulas use Solidity `abi.encode`, never `abi.encodePacked`. A quoted domain
is encoded as a Solidity `string`. Identifiers and hashes are `bytes32`; EVM
identities are `address`; economic amounts are `uint256`; timestamps, nonces, and
state versions are `uint64`; counts are `uint32`; enum values use their declared
ABI enum width. Dynamic tuple arrays are committed as
`keccak256(abi.encode(array))` before use in an outer preimage.

The reference implementation must reject overflow, truncation, zero or substituted
addresses, wrong field widths, omitted fields, alternative ordering, packed
encoding, and a digest with the correct aggregate but a changed member.

## Protobuf-to-EVM normalization

Every `Identifier`, `LoanId`, `PartyId`, `Money`, timestamp, and policy reference
is normalized before an EVM preimage is built:

- non-address `Identifier.value` and every `LoanId.value` are exactly
  `^0x[0-9a-f]{64}$`; required-zero request/quote IDs use 64 zero digits;
- address-bearing `PartyId.value` is exactly
  `^evm:31337:0x[0-9a-f]{40}$`;
- every hash-bearing `bytes` field is exactly 32 bytes and nonzero where required,
  except input `request_digest`, which is exactly zero-length;
- `Money.units` is exactly `^(0|[1-9][0-9]*)$`, parses without loss into
  `0..type(uint256).max`, and its asset value is exactly
  `asset:phase9:p9unit`;
- `asset:phase9:p9unit` maps by direct equality, never by hashing the string, to
  resolver-bound `settlementAssetId =
  0x61737365743a7068617365393a7039756e697400000000000000000000000000`;
- timestamps have nonnegative integral seconds representable as `uint64` and
  `nanos == 0`; and
- `refinance_policy` has exact ID `phase9-refinance`, version `v1`, and an exact
  32-byte nonzero content hash equal to the resolver key.

For `RefinanceRequest.new_position_manager` specifically:

1. the byte string must be exactly 20 bytes;
2. it must decode to a nonzero EVM address;
3. the decoded address must equal the manager independently predicted from the
   factory clone salt and creation-policy binding; and
4. those checks must complete before refinance-ID reconstruction and before any
   nonce, storage, token, debt, lien, position, or event effect.

The field is corroborative only. It never overrides the factory-resolved address
and never grants service-side authority. Zero length and lengths 19, 21, and 32
are mandatory negative vectors. A 20-byte zero value and a 20-byte substituted
nonzero value are also mandatory negatives.

The caller-supplied refinance ID and quote ID are their exact all-zero wire values,
and `request_digest` is canonical empty bytes. They are outputs, not expected-input
digests. State, state version, accepted funding, execution attempts, terminal
evidence, commitment state, and funding result are likewise zero at their respective
entry boundaries. `new_loan_nonce == refinance_nonce`, and that shared value is
nonzero, high-bit clear, and less than `NONCE_MASK`; inequality is rejected during
the pure checks before the old-loan lock write.

Pure normalization/derived-zero/local-key checks and the fixed compiler-linked request
`begin` dispatch precede and perform the local old-loan lock write. The validation
`preflight` and request `complete` dispatches occur only while that lock is active. These
three immutable library dispatches are internal code partitioning, not dependencies or
new authority. The lock is acquired before the first external resolver call; policy, borrower,
new-loan/predicted-manager, bootstrap, quote, and clone validation then occur under the
lock, and any rejection reverts it. After that check, one outer
borrower-authenticated coordinator transaction performs optional old bootstrap clone
creation, old positions/custody/liens, internal quote issuance, quote/refinance-ID
derivation, dormant replacement clone creation, final validation, and `ACCEPTED`
storage. A revert removes all of those effects. Exact request repeat fails at the stale
old-loan refinance nonce before another quote can issue.

The reference model treats `_nextRefinanceNonce[oldLoanId]` as:

```text
ACTIVE_MASK = 0x8000000000000000
NONCE_MASK  = 0x7fffffffffffffff
active(raw) = (raw & ACTIVE_MASK) != 0
nonce(raw)  = raw & NONCE_MASK
next(raw)   = 1 when raw == 0, otherwise raw when not active
```

Acceptance rejects high-bit caller nonce, active raw, mismatch, and
`nonce >= NONCE_MASK`, then stores `ACTIVE_MASK | nonce` before any resolver, token,
registry, factory, quote-engine, provider, or other effect-capable dependency
interaction. The compiler-linked `begin` dispatch that performs the write is not such
an interaction.
Every nonterminal mutator proves exact raw lock ownership. `REFUNDABLE` retains the
lock; `COMPLETED`, `CANCELLED`, `EXPIRED`, and final `REFUNDED` release to `nonce + 1`
after all other terminal effects. Unlocked `NONCE_MASK` is permanently exhausted.
Exact terminal replay is checked before lock ownership. Exact/same-quote/concurrent,
reentrant, wrong-owner, rollback, refundable, maximum, terminal replay, and next-nonce
distinct-quote cases are golden vectors.

## Canonical identity preimages

The exact refinance policy commitment is:

```text
refinance_policy_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_POLICY_V1",
  chainid,
  refinance_coordinator,
  policy_registry,
  old_loan_id,
  new_loan_id,
  borrower,
  old_lender,
  new_position_manager,
  bound_old_policy_set_hash,
  bound_new_policy_set_hash,
  proposed_terms_hash,
  settlement_asset_id,
  collateral_set_hash,
  funding_amount,
  refinance_fee,
  borrower_proceeds,
  expires_at,
  maximum_validity,
  maximum_commitments,
  keccak256(abi.encode(collateral_ids)),
  keccak256(abi.encode(replacement_debt)),
  keccak256(abi.encode(replacement_tranches)),
  keccak256(abi.encode(replacement_positions))
))
```

For this policy preimage `replacement_debt.activeRefinanceId == 0`; the coordinator
injects the derived refinance ID only into the later activation copy. The policy has
hard caps of 16 collateral IDs, 32 commitments, 8 tranches, and 32 positions.

The exact refinance identity remains the frozen data-layout identity:

```text
refinance_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_V1",
  chainid,
  refinance_coordinator,
  old_loan_id,
  new_loan_id,
  borrower,
  old_lender,
  new_position_manager,
  quote_id,
  component_beneficiary_hash,
  old_net_payoff,
  new_principal,
  settlement_asset_id,
  collateral_set_hash,
  lien_version,
  proposed_terms_hash,
  new_policy_set_hash,
  funding_amount,
  refinance_fee,
  borrower_proceeds,
  expires_at,
  refinance_nonce
))
```

`refinance_policy_hash` and `new_loan_nonce` are separately verified bindings;
they are not silently appended to the frozen refinance-ID preimage.
Every request vector supplies the policy-bound `expires_at` as the internal quote's
`valid_until`, requires the returned value to match, and stores
`RefinanceRecord.expiresAt == PayoffQuote.validUntil`. Mismatch vectors fail before the
refinance ID, replacement creation, or accepted record can persist.

Commitment identity and corroborating digest are distinct:

```text
commitment_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_FUNDING_COMMITMENT_V1",
  refinance_id,
  position_id,
  tranche_id,
  funder,
  amount,
  commitment_nonce
))

commitment_digest = keccak256(abi.encode(
  "UNIFIED_REFINANCE_FUNDING_COMMITMENT_DIGEST_V1",
  chainid,
  refinance_coordinator,
  commitment_id,
  refinance_id,
  position_id,
  tranche_id,
  funder,
  amount,
  commitment_nonce,
  refinance_policy_hash,
  expires_at
))
```

The ordered collateral and handoff identities are:

```text
collateral_entry_hash[i] = keccak256(abi.encode(
  collateral_id,
  asset_id,
  quantity,
  vault,
  borrower,
  prior_lien_version
))

collateral_set_hash = keccak256(abi.encode(collateral_entry_hashes))

lien_handoff_id = keccak256(abi.encode(
  "UNIFIED_LIEN_HANDOFF_V1",
  chainid,
  lien_registry,
  refinance_id,
  collateral_id,
  old_loan_id,
  new_loan_id,
  prior_lien_version,
  next_lien_version
))
```

Collateral IDs and entry hashes use the policy-supplied strictly increasing
`bytes32` order. No service-supplied reorder or storage enumeration is valid.

## Factory clone and creation preimages

```text
new_loan_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_REFINANCED_LOAN_V1",
  chainid,
  phase9_loan_factory,
  old_loan_id,
  borrower,
  new_agreement_hash,
  new_policy_set_hash,
  new_loan_nonce
))

loan_account_salt = keccak256(abi.encode(
  "UNIFIED_PHASE9_LOAN_ACCOUNT_CLONE_V1", loan_id
))

position_manager_salt = keccak256(abi.encode(
  "UNIFIED_PHASE9_POSITION_MANAGER_CLONE_V1", loan_id
))

creation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_LOAN_CREATION_V1",
  chainid,
  phase9_loan_factory,
  loan_id,
  source_old_loan_id,
  borrower,
  refinance_id_context,
  new_loan_nonce,
  factory_loan_nonce,
  agreement_hash,
  policy_set_hash,
  creation_mode,
  bootstrap_id,
  predicted_loan_account,
  predicted_position_manager
))

bootstrap_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_LOCAL_BOOTSTRAP_V1",
  chainid,
  phase9_loan_factory,
  policy_registry,
  old_loan_id,
  borrower,
  old_policy_set_hash
))

bootstrap_activation_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_ACTIVATION_V1",
  chainid,
  refinance_coordinator,
  bootstrap_id,
  old_loan_id,
  loan_account,
  keccak256(abi.encode(initial_debt))
))

bootstrap_tranche_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_TRANCHE_V1",
  chainid,
  refinance_coordinator,
  bootstrap_id,
  old_loan_id,
  position_manager,
  tranche_id
))

bootstrap_position_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_POSITION_V1",
  chainid,
  refinance_coordinator,
  bootstrap_id,
  old_loan_id,
  position_manager,
  position_id
))

bootstrap_custody_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
  chainid,
  refinance_coordinator,
  bootstrap_id,
  old_loan_id,
  collateral_custody,
  collateral_id
))

custody_identity_hash = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
  chainid,
  collateral_custody,
  asset_registry,
  bootstrap_custody_operation_id,
  collateral_id,
  asset_id,
  collateral_token,
  collateral_token_runtime_code_hash,
  collateral_token_decimals,
  true, // exactBalanceDelta
  borrower,
  quantity
))

bootstrap_lien_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_LIEN_V1",
  chainid,
  refinance_coordinator,
  bootstrap_id,
  old_loan_id,
  lien_registry,
  collateral_id,
  lien_version
))

bootstrap_custody_result_hash = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_RESULT_V1",
  bootstrap_custody_operation_id,
  collateral_id,
  asset_id,
  collateral_token,
  expected_runtime_code_hash,
  borrower,
  collateral_custody,
  quantity,
  borrower_balance_before,
  borrower_balance_after,
  custody_balance_before,
  custody_balance_after,
  total_custody_before,
  total_custody_after,
  HELD
))
```

Only `bootstrap_custody_operation_id` is passed through a frozen contract selector
and acts as an on-chain replay/identity key. The activation, tranche, position, and
lien operation IDs are deterministic model/event-correlation values only because the
corresponding frozen selectors contain no operation-ID parameter. Reference models
must not treat those correlation hashes as contract authority or processed storage;
on-chain exact replay/conflict derives from initialization and exact record IDs/tuples.

The factory-global loan nonce starts at one, advances only on successful unique
creation, rejects `type(uint64).max`, and cannot wrap. The replacement new-loan nonce
is not another stored counter; it exactly equals the low-63-bit per-old-loan
`refinance_nonce` governed by the tagged coordinator lock. The local-bootstrap tuple
fixes `source_old_loan_id = 0`, `refinance_id_context = 0`, and
`new_loan_nonce = 0`; the replacement tuple uses the source old-loan ID, the
already-derived nonzero refinance-ID context, and the equal nonzero
refinance/new-loan nonce.

A processed `creationId` is classified before the factory reads its current global
nonce or tests fresh-loan absence. Exact replay compares the complete stored and
supplied request, re-resolves the active four-field `resolveLoanCreation` tuple, proves
the stored mode-specific facts and coordinator, verifies both stored clone mappings,
code, and canonical protocol-version-9 registry identity, and returns the stored
account/manager without a write, clone, initialization, registration, nonce change, or
event. It never recomputes the creation ID with the current factory nonce:
the original value is not separately recoverable from the frozen storage after later
creations. First-execution validation, the stored request and creation commitment, and
the emitted `loanNonce` are the historical evidence.

Therefore first execution uses the frozen serial invariant rather than guessing or
enumerating a historical creation. It requires `factory.nextLoanNonce() > 1`, sets
`replacement_factory_loan_nonce = factory.nextLoanNonce() - 1` with checked `uint64`
arithmetic, reads `mapped_account = factory.loanAccount(new_loan_id)` and
`mapped_manager = factory.positionManager(new_loan_id)`, and re-resolves the exact
replacement creation tuple and `mapped_account.configuration()`. It then reconstructs
the existing `UNIFIED_PHASE9_LOAN_CREATION_V1` preimage using that serial, the mapped
clone addresses as the already-proved predictions, `REFINANCE_REPLACEMENT`, zero
bootstrap ID, the source old loan, borrower, derived refinance ID, equal nonzero
refinance/new-loan nonce, agreement hash, and policy-set hash. For the resulting
`derived_creation_id` it requires:

```text
factory.creationRequest(derived_creation_id) == LoanCreationRequest(
  old_loan_id,
  new_loan_nonce,
  refinance_id,
  exact_replacement_configuration,
  derived_creation_id
)
```

The mapped account/manager must contain the expected clone code; configuration must map
the same factory, registry, token/asset, borrower, loan ID, manager, custody, lien,
payoff engine, coordinator, and policy commitments; and factory/account/registry
identity must agree. An intervening later unique factory creation changes
`nextLoanNonce() - 1`, so this synthetic-local first-slice execution fails stale without
consuming the quote or moving value and remains cancellable/refundable. No scan, new
getter, new storage, or alternate creation identity is authorized.

The coordinator's fresh bootstrap and replacement requests supply zero `creationId`
because the frozen coordinator has no implementation-address fields and the factory
has no prediction getter. The factory rejects a fresh nonzero value, derives both
implementation-dependent clone predictions, derives the canonical nonzero creation
ID, and stores only a memory-canonicalized request containing that ID. Direct exact
factory replay supplies the complete stored canonical request. A later zero-ID attempt
for the same loan is a creation collision, not direct factory replay; the outer
refinance request is separately rejected by the consumed old-loan nonce.

For bootstrap replay, the factory revalidates the creation resolver's complete
configuration, mode, and deterministic bootstrap ID. It does not claim to byte-compare
the historical full `resolveBootstrap` payload because no such initial-payload hash is
stored and live debt may legitimately change later. Fresh bootstrap still validates
the complete active debt, tranche, position, custody, and lien payload before effects,
and ADR 0021 requires that resolver record to be immutable. A changed request or
creation-resolver fact under the processed identity reverts
`InvalidPhase9LoanConfiguration`; a different creation identity colliding with an
existing canonical loan reverts `Phase9LoanAlreadyExists(loanId)`.

No new-loan, clone-salt, or bootstrap identity includes a quote/refinance ID.
`creation_id` is computed only after the quote/refinance ID and includes the frozen
`LoanCreationRequest.refinanceId` as `refinance_id_context`: zero for bootstrap and
the already-derived refinance ID for replacement. The dependency order is therefore
acyclic and two changed replacement contexts cannot share one creation identity.

Clone-address evidence also includes the standard OpenZeppelin-compatible EIP-1167
minimal-proxy creation-code hash, factory address, salt, predicted address, actual
address, implementation address, implementation runtime code hash, clone runtime code
hash, and successful single initialization. A literal
`Clones.cloneDeterministic` path is invalid when its `FailedDeployment` or
`InsufficientBalance` errors enter the frozen factory ABI. Private prediction and
`CREATE2` helpers instead use byte-for-byte-equivalent EIP-1167 creation/runtime bytes,
validate implementation and clone code, and map deployment failure to
`InvalidPhase9LoanConfiguration`. The top-level refinance deployment does not use
these salts and is not `CREATE2`.

The account and position-manager implementation instances set their existing final
`_initialized` storage flag with the declaration initializer `= true`; fresh clone
storage remains zero. No explicit no-argument constructor is added to either frozen
ABI. After all validation, the factory reserves its exact request, processed marker,
predicted mappings, and advanced nonce before clone deployment or
initialization/registry effects. It deploys both clones, initializes the account first,
initializes the manager second, registers and verifies the account once, and emits
once. Failure at any step reverts every reservation, clone, initialization, registry,
nonce, and event effect. The manager authenticates the factory without a new slot by
reading the already-initialized account configuration and matching factory, loan ID,
manager, and settlement token.

The creation-policy reference model calls exact
`resolveLoanCreation(policySetHash, loanId)` and accepts only mode
`LOCAL_BOOTSTRAP=1` with nonzero matching bootstrap ID or
`REFINANCE_REPLACEMENT=2` with zero bootstrap ID. Bootstrap also calls exact
`resolveBootstrap(bootstrapId)`. The coordinator, not a forwarded borrower or
`tx.origin`, is the factory caller inside `requestRefinance`; the resolver supplies
the borrower and complete configuration. Every configuration requires nonzero loan,
agreement, policy-set, amendment-policy, protection-policy, recovery-policy, and
settlement-asset hashes, a nonzero borrower, and nonzero deployed contract
dependencies. None of the policy hashes is optional. The settlement asset ID is exact
direct-mapped `asset:phase9:p9unit` from the normalization section, never the test-only
hash of `SYNTHETIC_PHASE9_ASSET`; factory, account, manager, creation source, and
coordinator agree on it and on the exact local-token runtime.

The factory has no asset-source slot and neither adds one nor repurposes a policy
registry. The coordinator alone calls its frozen `_assetRegistry` and validates the
active, exact-balance-delta, six-decimal, address, resolver-runtime-hash, and deployed
runtime tuple. Factory and account independently enforce chain `31337`, the exact asset
ID, active creation-configuration equality, token code, and the exact
`Phase9LocalSyntheticToken` runtime. The manager enforces account-token equality and
that same runtime.

Bootstrap initializes the old account directly `ACTIVE/CURRENT` with a nonzero terms
version, writes the configuration agreement hash only at that version, then the
coordinator installs all old rights/security before quote issuance. Each missing
custody record first calls exact
`resolveCustodyAsset(assetId)` through the custody contract's constructor-bound asset
source. The coordinator recomputes the nonzero operation ID; custody authenticates
that coordinator, reconstructs `CustodyRecord.identityHash` from the passed operation
ID plus the exact token/runtime/active/exact-delta and record tuple, records the
processed operation/`HELD`/checked total before interaction, and proves exact
borrower-to-custody `transferFrom` balance deltas. Only afterward may the lien exist.
Exact same-operation/same-record replay proves attributable custody/aggregate/lien
state without another transfer; changed-record or alternate-operation reuse conflicts.
The original position owner and sole canonical payoff beneficiary equal `oldLender`;
tranche/position claims, claim-bearing debt, and the quote route match exactly, with no
alternate beneficiary. Replacement initializes only `CREATED/NONE` zero debt and no
positions/custody/lien, bound to the one derived refinance. It leaves
`agreementVersionHash(0) == 0`; later activation writes the agreement hash only at the
nonzero effective terms version.

Tranche, position, collateral, custody, and lien vectors are strictly increasing by
unsigned raw `bytes32` identity, equivalent to
`uint256(currentId) > uint256(previousId)`. Tranches compare `trancheId`; positions
compare `positionId`; tranche `priority` is not the ordering comparator. The manager
classifies an existing ID before append ordering: exact full-record replay is inert,
while changed reuse and all activated manager-method failures revert
`InvalidPositionOperation`.

Every position checkpoint series has at most one entry per block. Writers reject a
block number above `type(uint64).max`, overwrite the last entry at the current block,
and append otherwise. Owner checkpoints use only `owner`; voting-power, claim, and
total-vote checkpoints use only `value`. Multiple same-block issuances coalesce the
cumulative total-vote entry, and exact issuance replay writes no checkpoint or event.

## Operation identities

```text
CAPABILITY_PHASE9_REFINANCE_REQUEST =
  keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST")

CAPABILITY_PHASE9_REFINANCE_FUNDING =
  keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING")

request_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REQUEST_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id
))

execute_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EXECUTE_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, quote_id,
  consumed_quote_debt_state_version
))

cancel_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, state_version,
  expires_at, cancellation_reason
))

refund_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REFUND_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, commitment_id,
  amount, funder
))
```

`cancellation_reason` is exact `uint8`: `NONE=0` is invalid,
`BORROWER_CANCELLED=1`, and `EXPIRED=2`. It is derived from caller/deadline
authority, not supplied as arbitrary calldata. The commitment ID is the funding
operation identity. A digest from one action domain is invalid in every other action
domain.

Replay vectors are method-specific: exact request repeats fail the consumed refinance
nonce before another quote; exact funding/cancel/refund and custody/lien setup repeats
are inert; exact execute returns the stored terminal result; exact factory create
returns stored clones; and changed identity reuse conflicts.
On first execution only, `consumed_quote_debt_state_version` is read from the exact
stored quote and used to recompute the operation ID; supplied-ID equality is required
before provisional `EXECUTING`. That first-execution recomputation uses the stored quote
fact, never from the old account's current post-payoff version. Exact terminal replay is
dependency-call-free and does not read the quote or recompute `execute_operation_id` from
any debt version. Execute
replay validates the complete stored terminal tuple: exact nonzero keyed refinance
identity, record `COMPLETED`, attempt one, nonzero processed supplied operation ID,
terminal refinance identity and `COMPLETED` state, nonzero event ID, and matching nonzero
terminal result/evidence. It also requires the exact replay event-ID reconstruction
defined below. Provisional `EXECUTING` cannot replay.

Cancel replay uses a bounded refunded-commitment count and only coordinator storage.
Before any first-execution current-state, old-loan-lock-owner, quote, or dependency read,
validate that the commitment-ID vector is bounded and unique. `CANCELLED` and `EXPIRED`
require the canonical empty inventory; `REFUNDABLE` and `REFUNDED` require length
`1..32`. Every vector ID is nonzero and materializes an exact stored commitment with
`commitmentId == vector_id`, `refinanceId == refinance_id`, and state exactly `FUNDED` or
`REFUNDED`; `NONE`, `CONSUMED`, or any other state conflicts. Checked-count exact entries
whose stored state is `REFUNDED`, then use checked arithmetic:

```text
refunded_count = count(stored commitments with state REFUNDED)
cancellation_prior_version = stored_refinance.stateVersion - refunded_count - 1

borrower_cancel_replay_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, cancellation_prior_version,
  stored_refinance.expiresAt, uint8(1)
))

expiry_cancel_replay_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, cancellation_prior_version,
  stored_refinance.expiresAt, uint8(2)
))
```

The keyed stored refinance identity must match, and the supplied cancel operation ID
must be nonzero and processed. `CANCELLED` accepts only
`borrower_cancel_replay_id`; `EXPIRED` accepts only `expiry_cancel_replay_id`;
`REFUNDABLE` and `REFUNDED` accept either exact candidate because their stored state does
not encode the original cancellation reason. Every other refinance or commitment state,
over-cap or duplicate inventory, missing or wrong commitment identity, wrong commitment
refinance, count/version inconsistency, checked underflow, candidate mismatch, or
processed cross-domain/other-refinance ID reverts `RefinanceReplayConflict`. Exact cancel
replay has zero dependency calls, writes, transfers, counters, and logs. It remains exact
after partial and final refunds and never uses `current stateVersion - 1` alone.

## Result and transition evidence preimages

The first implementation must use the following exact result commitments. Hashes
of frozen structs use the frozen field order and types.

```text
funding_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_FUNDING_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  commitment_id,
  funder,
  amount,
  commitment_nonce,
  accepted_funding_after,
  escrowed_units_after,
  commitment_count_after,
  refinance_state_after,
  refinance_state_version_after
))

IPayoffQuoteEngineV2.PayoffComponentV2[] exact_quote_components =
  exact components returned by quote(quote_id)
require exact_quote_components.length == 5
bytes32 recomputed_component_beneficiary_hash = keccak256(abi.encode(
  "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1",
  exact_quote_components
))
require recomputed_component_beneficiary_hash == consumed_quote.componentBeneficiaryHash
require recomputed_component_beneficiary_hash == accepted_record.componentBeneficiaryHash
bytes32 consumed_quote_component_beneficiary_hash = recomputed_component_beneficiary_hash

component_payout_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_COMPONENT_PAYOUT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  quote_id,
  consumed_quote_component_beneficiary_hash,
  old_net_payoff,
  refinance_fee,
  borrower_proceeds,
  funding_amount
))

execution_block = uint64(block.number)

ordered_tranche_ids = old_position_manager.trancheIds()
ordered_tranches[i] = old_position_manager.tranche(ordered_tranche_ids[i])
ordered_tranche_ids_hash = keccak256(abi.encode(ordered_tranche_ids))
ordered_tranches_hash = keccak256(abi.encode(ordered_tranches))

old_tranche_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_TRANCHE_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_tranche_ids_hash,
  ordered_tranches_hash
))

ordered_position_ids = old_position_manager.positionIds()
ordered_positions[i] = old_position_manager.position(ordered_position_ids[i])
ordered_position_ids_hash = keccak256(abi.encode(ordered_position_ids))
ordered_positions_hash = keccak256(abi.encode(ordered_positions))

old_position_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_POSITION_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_position_ids_hash,
  ordered_positions_hash
))

owners_at_execution[i] =
  old_position_manager.positionOwnerAt(ordered_position_ids[i], execution_block)
voting_power_at_execution[i] =
  old_position_manager.positionVotingPowerAt(ordered_position_ids[i], execution_block)
claims_at_execution[i] =
  old_position_manager.positionClaimAt(ordered_position_ids[i], execution_block)
total_voting_power_at_execution =
  old_position_manager.totalVotingPowerAt(execution_block)
require ordered_tranches[i].trancheId == ordered_tranche_ids[i] for every i
require ordered_positions[i].positionId == ordered_position_ids[i] for every i
require owners_at_execution[i] == ordered_positions[i].owner for every i
require voting_power_at_execution[i] == ordered_positions[i].votingPower for every i
require claims_at_execution[i] == ordered_positions[i].claim for every i
require checked_sum(voting_power_at_execution) == total_voting_power_at_execution
owners_at_execution_hash = keccak256(abi.encode(owners_at_execution))
voting_power_at_execution_hash = keccak256(abi.encode(voting_power_at_execution))
claims_at_execution_hash = keccak256(abi.encode(claims_at_execution))

old_rights_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_RIGHTS_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_position_ids_hash,
  owners_at_execution_hash,
  voting_power_at_execution_hash,
  claims_at_execution_hash,
  total_voting_power_at_execution
))

address[4] payout_recipients = [
  old_lender,
  payoff_fee_recipient,
  refinance_fee_recipient,
  borrower
]

uint256[4] payout_amounts = [
  old_lender_payoff_amount,
  payoff_fee_amount,
  refinance_fee,
  borrower_proceeds
]

old_lender_payoff_amount = quote.principal + quote.accruedInterest
payoff_fee_amount = quote.fees + quote.penalties - quote.credits
old_lender_payoff_amount + payoff_fee_amount = quote.netPayoff

payout_leg_delta_hash[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_PAYOUT_LEG_DELTA_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  settlement_token,
  uint8(i),
  payout_recipients[i],
  payout_amounts[i],
  leg_recipient_balance_before[i],
  leg_recipient_balance_after[i],
  leg_coordinator_balance_before[i],
  leg_coordinator_balance_after[i]
))
bytes32[4] payout_leg_delta_hashes = [
  payout_leg_delta_hash[0],
  payout_leg_delta_hash[1],
  payout_leg_delta_hash[2],
  payout_leg_delta_hash[3]
]

address[] unique_recipient_addresses = distinct payout_recipients sorted by increasing uint160
uint256[] unique_recipient_expected_amounts
uint256[] unique_recipient_balance_before
uint256[] unique_recipient_balance_after
uint256 unique_recipient_count = unique_recipient_addresses.length
require 1 <= unique_recipient_count <= 4
require unique_recipient_expected_amounts.length == unique_recipient_count
require unique_recipient_balance_before.length == unique_recipient_count
require unique_recipient_balance_after.length == unique_recipient_count
unique_recipient_expected_amounts[j] = checked sum of payout_amounts for that address
unique_recipient_balance_before[j] = balance before payout leg 0
unique_recipient_balance_after[j] = balance after payout leg 3
coordinator_outflow = coordinator_balance_before_all - coordinator_balance_after_all

recipient_balance_delta_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_RECIPIENT_BALANCE_DELTA_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  settlement_token,
  keccak256(abi.encode(payout_leg_delta_hashes)),
  keccak256(abi.encode(unique_recipient_addresses)),
  keccak256(abi.encode(unique_recipient_expected_amounts)),
  keccak256(abi.encode(unique_recipient_balance_before)),
  keccak256(abi.encode(unique_recipient_balance_after)),
  attributed_escrow_before,
  attributed_escrow_after,
  coordinator_balance_before_all,
  coordinator_balance_after_all,
  coordinator_outflow,
  funding_amount
))

old_debt_after_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_DEBT_AFTER_V1",
  old_loan_id,
  CLOSED,
  TERMINAL,
  unchanged_terms_version,
  prior_debt_state_version + 1,
  prior_state_nonce + 1,
  unchanged_commencement_time,
  unchanged_maturity_time,
  unchanged_schedule_hash,
  uint256(0), // outstanding principal
  uint256(0), // accrued interest
  uint256(0), // capitalized interest
  uint256(0), // accrued fees
  uint256(0), // accrued penalties
  uint256(0), // recoverable costs
  uint256(0), // unapplied credit
  uint256(0), // covered loss exposure
  uint256(0), // realized loss
  uint256(0), // written off
  uint256(0), // recovered after writeoff
  refinance_id,
  bytes32(0)  // active restructure ID
))

uint256[] zero_effective_claims = new uint256[](ordered_position_ids.length)
uint256[] zero_effective_voting_power = new uint256[](ordered_position_ids.length)
require zero_effective_claims.length == ordered_position_ids.length
require zero_effective_voting_power.length == ordered_position_ids.length
require each zero-array index i corresponds to ordered_position_ids[i]
require zero_effective_claims[i] == 0 for every ordered position index i
require zero_effective_voting_power[i] == 0 for every ordered position index i

effective_old_position_rights_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EFFECTIVE_OLD_POSITION_RIGHTS_V1",
  old_loan_id,
  old_position_manager,
  ordered_position_ids,
  zero_effective_claims,
  zero_effective_voting_power,
  old_debt_after_hash,
  true // LoanRegistry.isTerminal(old_loan_id) after payoff
))

old_debt_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_DEBT_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  quote_id,
  debt_state_version_before,
  debt_state_version_after,
  old_debt_after_hash,
  old_tranche_execution_snapshot_hash,
  old_position_execution_snapshot_hash,
  old_rights_execution_snapshot_hash,
  effective_old_position_rights_hash,
  true, // LoanRegistry.isTerminal(old_loan_id) after payoff
  old_net_payoff
))

Phase9Types.DebtState replacement_debt = canonical resolver-returned replacementDebt
Phase9Types.Tranche[] replacement_tranches = canonical resolver-returned replacementTranches
Phase9Types.Position[] replacement_positions = canonical resolver-returned replacementPositions
bytes32 replacement_debt_hash = keccak256(abi.encode(replacement_debt))
bytes32 replacement_tranches_hash = keccak256(abi.encode(replacement_tranches))
bytes32 replacement_positions_hash = keccak256(abi.encode(replacement_positions))

new_activation_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_NEW_ACTIVATION_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  new_loan_id,
  new_position_manager,
  refinance_policy_hash,
  replacement_debt_hash,
  replacement_tranches_hash,
  replacement_positions_hash,
  new_principal
))

require prior_lien_versions[i] < type(uint64).max for every i
next_lien_versions[i] = prior_lien_versions[i] + 1

pending_lien_views[i] = Lien(
  ordered_collateral_ids[i],
  unchanged_collateral_manager[i],
  unchanged_vault[i],
  unchanged_asset_id[i],
  unchanged_quantity[i],
  unchanged_borrower[i],
  old_loan_id,
  prior_lien_versions[i],
  HANDOFF_PENDING,
  refinance_id,
  new_loan_id
)

pending_handoff_views[i] = LienHandoffResult(
  ordered_handoff_ids[i],
  refinance_id,
  ordered_collateral_ids[i],
  old_loan_id,
  new_loan_id,
  prior_lien_versions[i],
  next_lien_versions[i],
  EXECUTING,
  bytes32(0)
)

pending_lien_observation_hash[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_PENDING_OBSERVATION_V1",
  chainid,
  lien_registry,
  refinance_id,
  uint32(i),
  ordered_collateral_ids[i],
  ordered_handoff_ids[i],
  keccak256(abi.encode(pending_lien_views[i])),
  keccak256(abi.encode(pending_handoff_views[i]))
))
pending_lien_observation_hashes[i] = pending_lien_observation_hash[i]

lien_handoff_evidence_hash[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_HANDOFF_RESULT_V1",
  chainid,
  lien_registry,
  ordered_handoff_ids[i],
  refinance_id,
  ordered_collateral_ids[i],
  old_loan_id,
  new_loan_id,
  prior_lien_versions[i],
  next_lien_versions[i],
  ACTIVE_NEW
))
ordered_handoff_evidence_hashes[i] = lien_handoff_evidence_hash[i]

active_lien_views[i] = Lien(
  ordered_collateral_ids[i],
  unchanged_collateral_manager[i],
  unchanged_vault[i],
  unchanged_asset_id[i],
  unchanged_quantity[i],
  unchanged_borrower[i],
  new_loan_id,
  next_lien_versions[i],
  ACTIVE,
  bytes32(0),
  bytes32(0)
)

active_handoff_views[i] = LienHandoffResult(
  ordered_handoff_ids[i],
  refinance_id,
  ordered_collateral_ids[i],
  old_loan_id,
  new_loan_id,
  prior_lien_versions[i],
  next_lien_versions[i],
  ACTIVE_NEW,
  lien_handoff_evidence_hash[i]
)

active_lien_observation_hash[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_ACTIVE_OBSERVATION_V1",
  chainid,
  lien_registry,
  refinance_id,
  uint32(i),
  ordered_collateral_ids[i],
  ordered_handoff_ids[i],
  keccak256(abi.encode(active_lien_views[i])),
  keccak256(abi.encode(active_handoff_views[i]))
))
active_lien_observation_hashes[i] = active_lien_observation_hash[i]

lien_handoff_vector_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_HANDOFF_VECTOR_V1",
  chainid,
  lien_registry,
  refinance_id,
  keccak256(abi.encode(ordered_collateral_ids)),
  keccak256(abi.encode(ordered_handoff_ids)),
  keccak256(abi.encode(pending_lien_observation_hashes)),
  keccak256(abi.encode(ordered_handoff_evidence_hashes)),
  keccak256(abi.encode(active_lien_observation_hashes))
))

funding_escrowed_state_version = stored stateVersion before provisional EXECUTING
completed_state_version = funding_escrowed_state_version + 1
execution_attempt = uint32(1)
require block.timestamp <= type(uint64).max
uint64 executed_at = uint64(block.timestamp)

execution_event_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EXECUTION_EVENT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  quote_id,
  execute_operation_id,
  execution_attempt,
  executed_at
))

terminal_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_TERMINAL_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  execution_event_id,
  component_payout_hash,
  recipient_balance_delta_hash,
  old_debt_result_hash,
  new_activation_result_hash,
  lien_handoff_vector_hash,
  completed_state_version,
  old_loan_refinance_lock_after,
  executed_at
))

execution_transition_evidence_hash = terminal_result_hash

require refinance_id != bytes32(0)
require stored_refinance.refinanceId == refinance_id
require stored_refinance.state == COMPLETED
require stored_refinance.executionAttempts == uint32(1)
require supplied_operation_id != bytes32(0)
require processedOperationIds[supplied_operation_id]
require stored_terminal_result.refinanceId == refinance_id
require stored_terminal_result.state == COMPLETED
require stored_terminal_result.executionEventId != bytes32(0)
require stored_terminal_result.resultHash != bytes32(0)
require stored_terminal_result.resultHash == stored_refinance.terminalEvidenceHash

replayed_execution_event_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EXECUTION_EVENT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  stored_refinance.quoteId,
  supplied_operation_id,
  uint32(1),
  stored_terminal_result.recordedAt
))
require replayed_execution_event_id != bytes32(0)
require replayed_execution_event_id == stored_terminal_result.executionEventId

refund_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REFUND_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  commitment_id,
  refund_operation_id,
  funder,
  amount,
  accepted_funding_after,
  escrowed_units_after,
  refinance_state_after,
  refinance_state_version_after,
  refunded_at
))

cancellation_result_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_CANCELLATION_RESULT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  cancel_operation_id,
  cancellation_reason,
  quote_id,
  quote_disposition_after,
  quote_disposition_source_id,
  old_loan_refinance_lock_before,
  old_loan_refinance_lock_after,
  refinance_state_before,
  refinance_state_version_before,
  refinance_state_after,
  refinance_state_version_after,
  accepted_funding,
  escrowed_units,
  recorded_at
))

terminal_refund_commitment_fact[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_TERMINAL_REFUND_COMMITMENT_V1",
  commitment_id,
  refinance_id,
  position_id,
  tranche_id,
  funder,
  amount,
  commitment_nonce,
  commitment_digest,
  immutable_funding_result_hash,
  REFUNDED
))

final_refund_completion_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_FINAL_REFUND_COMPLETION_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  refunded_state_version,
  keccak256(abi.encode(ordered_commitment_ids)),
  keccak256(abi.encode(ordered_terminal_refund_commitment_facts)),
  uint256(0), // accepted funding after
  uint256(0), // escrowed units after
  REFUNDED,
  old_loan_refinance_lock_after,
  refunded_at
))

transition_evidence_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_STATE_TRANSITION_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  previous_state,
  next_state,
  state_version,
  operation_id,
  action_result_hash
))
```

`execution_block` is fixed before the first external execution effect and requires
`block.number <= type(uint64).max`. The three old-manager snapshot hashes are computed
from the exact bounded ordered arrays above before that effect, recomputed after payoff,
and recomputed once more before terminal persistence, always using that same block.
Every recomputation must be byte-equal. These hashes prove only public observations
available through `trancheIds/tranche`, `positionIds/position`,
`positionOwnerAt`, `positionVotingPowerAt`, `positionClaimAt`, and
`totalVotingPowerAt`; they do not assert that private checkpoint arrays were enumerated.

`consumed_quote_component_beneficiary_hash` is read directly from the exact stored
consumed quote and equals its frozen `componentBeneficiaryHash`; no separately supplied
or newly derived opaque payoff-component hash exists. The three replacement values are
the exact active canonical refinance-policy resolver returns, typed respectively as
`Phase9Types.DebtState`, `Phase9Types.Tranche[]`, and `Phase9Types.Position[]` and encoded
in their frozen field order. The debt hash binds the resolver template with
`activeRefinanceId == 0`; the coordinator separately validates the activation copy that
injects only the derived refinance ID.

After operation/readiness validation and canonical re-resolution, but before the first
external execution effect, execution requires `block.timestamp <= type(uint64).max` and
captures `executed_at = uint64(block.timestamp)` exactly once. That one value is used in
`execution_event_id`, `terminal_result_hash`, terminal `recordedAt`, and every stored or
emitted execution-result fact. The frozen execution and transition events have no
timestamp field; they bind the same value transitively through `terminal_result_hash`.

Every payout recipient is validated nonzero, unequal to the coordinator, and unequal
to the settlement-token address before quote consumption or balance change, including
zero-amount legs. A recipient is not rejected merely for having code, equaling another
canonical recipient, or equaling another system-contract address; all four addresses
still come only from the canonical quote, accepted record, and constructor-bound fee
configuration. Beyond the settlement-token self-recipient rejection, this freeze adds
no code-size/system-contract classification. A positive leg makes one transfer
and requires both immediate recipient inflow and immediate coordinator outflow equal to
its amount. A zero leg makes no token call and requires both immediate deltas to be
zero. All four leg hashes remain present.

`unique_recipient_addresses` is deduplicated and sorted by strictly increasing
unsigned `uint160`, not by role occurrence. Its three parallel vectors have identical
length and index meaning. Each final recipient delta equals the checked sum of all legs
naming that address. The four leg amounts checked-sum to the positive `funding_amount`;
attributed escrow changes from exactly that amount to zero; and
`coordinator_outflow == funding_amount`. Pre-existing unsolicited surplus is preserved
by the raw coordinator before/after proof and is excluded from attributed escrow.

The lien vector has `1..16` members, and every count/order/identity/tuple check and
version addition is completed before the first `beginHandoff`; a prior
`type(uint64).max` value rejects execution without effect. The observable order is
begin-all, verify-all-pending, complete-all, then verify-all-active, each in the same
strictly increasing unsigned-`bytes32` collateral order. Every
`LienHandoffPending` log precedes the first `LienHandoffCompleted` log. From the first
begin through the last active observation, every external call targets only the
canonical lien registry. Pending and active view tuples must equal the exact frozen
field-order values above. The old senior identity remains enforceable in every pending
tuple; the pending target/successor is not enforceable until completion. Each indexed completion input is
`(ordered_handoff_ids[i], lien_handoff_evidence_hash[i])`; its returned result and the
later stored `handoff` view both equal `active_handoff_views[i]`. The registry's begin,
complete, lien, and handoff methods make no external call. Any mismatch or failure
rolls back the complete vector.

Provisional `EXECUTING` consumes neither a version nor an execution attempt and emits
no transition. First execution requires `executionAttempts == 0` and a
`funding_escrowed_state_version < type(uint64).max`. Success stores attempt `1` and
`completed_state_version == funding_escrowed_state_version + 1`. It then emits the
frozen `RefinanceExecuted(refinance_id, execution_event_id, terminal_result_hash)` log
followed by exactly one additive
`RefinanceStateTransitioned(refinance_id, FUNDING_ESCROWED, COMPLETED,
completed_state_version, execute_operation_id, terminal_result_hash)` log. For this
one transition, the event evidence is directly `terminal_result_hash`, as represented
by `execution_transition_evidence_hash`; it is not the generic transition wrapper.
Revert restores attempts and version, and provisional `EXECUTING` cannot qualify for
terminal replay. Before every first-execution current-state or old-lock read, exact replay
requires the record key and its nonzero stored refinance identity to match; stored
`COMPLETED` and attempt `1`; a nonzero processed supplied operation ID; terminal refinance
identity and `COMPLETED` state; a nonzero terminal event ID; and matching nonzero terminal
result/evidence. It reconstructs a nonzero `replayed_execution_event_id` from the exact
domain, chain, coordinator, refinance ID, stored `quoteId`, supplied ID, attempt one, and
terminal `recordedAt`, then matches the stored event ID. It makes no quote or dependency
call, returns the stored result, and performs no write, transfer, counter change, or log.
It does not recompute `execute_operation_id`; every tuple mismatch, changed ID, or
unprocessed ID reverts `RefinanceReplayConflict`.

For `BORROWER_CANCELLED`, `quote_disposition_after == INVALIDATED`; for `EXPIRED`,
it is `EXPIRED`. The latter is exact because every accepted record binds
`refinance.expiresAt == quote.validUntil`; boundary vectors prove both transition at
the same second. In both cases
`quote_disposition_source_id == cancel_operation_id`.
Quote invalidation occurs before refinance persistence and both effects roll back
together.

For funding and refund evidence, an operation delta remains the observed balance change
caused by that operation and is not the coordinator's global balance. Execution instead
uses the exact positive `coordinator_outflow` and four immediate leg deltas above.
`attributed_escrow_*` is scoped to the refinance. Unsolicited surplus is excluded from
every liability, readiness, payout, refund, and terminal-result field.

`RefinanceTerminalResult` is exact:

| Refinance state | `executionEventId` | `resultHash` | `recordedAt` | Stored terminal evidence |
|---|---|---|---|---|
| known `ACCEPTED`, `FUNDING_ESCROWED`, or `REFUNDABLE` | zero | zero | zero | zero |
| `CANCELLED` | zero | `cancellation_result_hash` with reason 1 | exact cancellation time | same cancellation hash |
| `EXPIRED` | zero | `cancellation_result_hash` with reason 2 | exact expiry-persistence time | same expiry hash |
| `REFUNDED` | zero | `final_refund_completion_hash` | exact last-refund time | same completion hash |
| `COMPLETED` | `execution_event_id` | `terminal_result_hash` | exact execution time | same execution terminal hash |

For the request transition `action_result_hash` is its derived request operation ID.
For funding it is `funding_result_hash`; for borrower cancellation or expiry it is
`cancellation_result_hash`; for an intermediate or last refund it is that commitment's
`refund_result_hash`. Those transitions use the generic wrapper above. Successful
execution instead places `terminal_result_hash` directly in the one durable transition
event's `evidenceHash`, and never emits a provisional transition. The last
refund separately stores `final_refund_completion_hash` as terminal evidence. The
additive transition event therefore retains the individual refund timestamp/result,
while the terminal aggregate is deterministically reconstructible from bounded stored
commitments plus the stored terminal `recordedAt == refunded_at ==` last-refund
transition time. `fundingResultHash` remains the immutable funding proof and is never
repurposed. `REFUNDABLE` remains nonterminal even though its transition has
cancellation evidence. Exact terminal-result replay must reconstruct and match the
same aggregate before returning it. Cross-language and event-order tests prove exactly
one refund transition/result per ordered stored commitment, no missing, duplicate, or
unmatched refund event, and exact last-refund aggregate reconstruction.

## Canonical first-slice vector inputs

The golden-vector generator must publish the full ABI-typed JSON input and output.
At minimum its canonical success vector uses:

| Fact | Required value |
|---|---|
| Chain ID | `31337` |
| Settlement decimals | `6` |
| Wire asset | exact `asset:phase9:p9unit` mapped directly to `0x61737365743a7068617365393a7039756e697400000000000000000000000000` |
| Caller refinance ID / quote ID / request digest | zero ID / zero ID / empty bytes |
| Old payoff components | principal/interest route `95_000000` plus fee/penalty route `5_000000` |
| Old net payoff | `100_000000` |
| Refinance fee | `2_000000` |
| Borrower proceeds | `18_000000` |
| Funding amount | `120_000000` |
| New principal | `120_000000` |
| Commitment A / position A | `90_000000` |
| Commitment B / position B | `30_000000` |
| Collateral vector | two nonzero IDs in strictly increasing raw `bytes32` order |
| First accepted state/version | `ACCEPTED`, `1` |
| State after commitment A | `FUNDING_ESCROWED` with accepted funding `90_000000` |
| State after commitment B | `FUNDING_ESCROWED` with accepted funding `120_000000` |
| Successful execution state/version/attempt | one durable `FUNDING_ESCROWED -> COMPLETED` increment, attempt `1`, no provisional transition |
| Execution evidence inputs | consumed quote's stored five-component hash; typed resolver debt/tranche/position hashes; one `uint64(block.timestamp)` |
| Attributed escrow after execution | `0` |
| Recipient ordering and outflow | four ordered leg hashes; unique addresses in increasing `uint160`; exact `120_000000` coordinator outflow |
| Lien handoff order | begin both, verify both pending, complete both, verify both active-new |
| Old debt after execution | `CLOSED/TERMINAL`; all economic/loss/credit values zero; debt version and state nonce each incremented once |
| Old execution observations | exact pre/payoff/post hashes from frozen public views at one `execution_block`; effective claims/votes zero; no private-series claim |

All addresses, IDs, timestamps, versions, policy values, debt, tranches,
positions, quote components, and collateral facts must be fixed explicitly in
the generated vector source, not taken from wall-clock time or a deployment that
was not recorded in the matching deployment manifest.

Required companion vectors include partial cancellation/refund, full
cancellation/refund, exact replay, changed replay, expiry at the half-open
boundary, cancellation reasons 0/1/2, cancellation/expiry/final-refund terminal-result
mutations, nonzero caller refinance/quote IDs, nonempty request digest, every
single-field preimage mutation, manager byte lengths
`0/19/21/32`, zero/substituted 20-byte manager addresses, reordered collateral,
over-cap `17/33/9/33` collateral/commitment/tranche/position vectors, reordered
commitments/positions, stale quote/debt/policy, dormant-clone reuse after every
terminal branch, malicious raw `ACTIVE` old position use against every joined-state
consumer, donation before each value operation, and injected failure at every request
and execution step.

Execution companions additionally cover every equality partition of the four canonical
recipient roles (including all-distinct and all-equal), a canonical contract recipient,
zero recipient, coordinator recipient, settlement-token recipient, another canonical
system-contract recipient, zero and positive leg combinations, changed
immediate leg deltas, changed unique-address order/aggregate/final balances, donation
surplus, and coordinator outflow mismatch. Zero/coordinator/settlement-token recipients
fail before any effect; another canonical contract recipient is governed by the same
exact-delta checks and does not create caller-selected authority.

Evidence-input companions mutate every field and order of the exact five stored quote
components, their recomputed `UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1` hash, the
consumed quote and accepted-record copies, each typed resolver replacement value and
its ABI hash, `block.timestamp == type(uint64).max`, an unrepresentable timestamp, and
any attempted resampling or disagreement among execution ID, terminal hash, terminal
storage, and event-bound result.

Snapshot companions mutate `execution_block`, every ordered ID, every frozen tranche
and position field, each owner/voting/claim observation, total voting power, every inner
array hash, and every outer field; they also force pre/payoff/post recomputation
mismatch. Lien companions inject failure at every index of begin-all,
verify-all-pending, complete-all, and verify-all-active; mutate each exact tuple and
phase vector; reorder IDs; use `type(uint64).max` prior version; and prove every pending
log precedes every completion log. State/event companions prove provisional
`EXECUTING` has no version, attempt, terminal replay, or event; success increments once,
sets attempt one, emits frozen execution then one durable completion transition, and
exact replay changes nothing.

The same bundle also includes factory replay after later successful creations without
current-nonce reconstruction; changed request and creation-resolver reuse; an alternate
creation ID for the same loan; global factory nonce start, advance, exhaustion, and
rollback; direct implementation initialization; account-before-manager authentication;
failure before and after each clone/initialization/registry step; exact
`agreementVersionHash(0) == 0`; every required configuration hash changed to zero;
direct-mapped settlement asset versus hashed/substituted asset IDs; wrong local-token
runtime; raw-ID duplicate/decreasing order with independent tranche-priority changes;
exact and changed tranche/position replay; same-block checkpoint coalescing; and
`block.number > type(uint64).max`. ABI negatives prove that no no-argument constructor,
OpenZeppelin deployment error, new selector, event, error, tuple field, base, or storage
field appears.

## Cross-language acceptance

For each preimage above, the accepted evidence bundle records:

- domain, ABI type list, normalized value list, encoded bytes, and final hash;
- Solidity contract or harness output;
- independently implemented Go, TypeScript, and Python output;
- compiler/tool versions and source hashes;
- positive vector IDs and negative mutation IDs; and
- the mapped `P9R-ID-*`, `P9R-FUND-*`, `P9R-EXEC-*`, `P9R-EXIT-*`,
  `P9R-DON-*`, and `P9R-EVT-*` rows.

An output is not accepted when any language copies a precomputed digest instead
of encoding the typed input independently, when generated code is stale, or when
the evidence was produced from a different source or deployment head. This
document fixes inputs and algorithms only; no placeholder digest is a golden
value.
