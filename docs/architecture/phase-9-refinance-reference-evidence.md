# Phase 9 Refinance Reference Evidence

Status: normative preimage and vector-input boundary; implementation evidence pending

Date: 2026-07-26

## Purpose

This document fixes the independent evidence model required by ADR 0021 and the
`P9R-*` acceptance matrix. It does not claim that a Solidity implementation or a
golden-output bundle exists. The first accepted implementation checkpoint must
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
entry boundaries.

Pure normalization/derived-zero/local-key checks precede the local old-loan lock write.
The lock is acquired before the first external resolver call; policy, borrower,
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
`nonce >= NONCE_MASK`, then stores `ACTIVE_MASK | nonce` before any external call.
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
  bootstrap_id,
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

The factory loan nonce starts at one, advances only on successful creation, and
cannot wrap. The replacement new-loan nonce has the same start/advance/wrap rule.
The local-bootstrap tuple fixes `source_old_loan_id = 0`,
`refinance_id_context = 0`, and `new_loan_nonce = 0`; the replacement tuple uses
the source old-loan ID, the already-derived nonzero refinance-ID context, and its
nonzero new-loan nonce. Exact creation replay returns the stored account/manager;
changed reuse conflicts.

No new-loan, clone-salt, or bootstrap identity includes a quote/refinance ID.
`creation_id` is computed only after the quote/refinance ID and includes the frozen
`LoanCreationRequest.refinanceId` as `refinance_id_context`: zero for bootstrap and
the already-derived refinance ID for replacement. The dependency order is therefore
acyclic and two changed replacement contexts cannot share one creation identity.

Clone-address evidence also includes the standard minimal-proxy creation-code
hash, factory address, salt, predicted address, actual address, implementation
address, implementation runtime code hash, clone runtime code hash, and successful
single initialization. The top-level refinance deployment does not use these
salts and is not `CREATE2`.

The creation-policy reference model calls exact
`resolveLoanCreation(policySetHash, loanId)` and accepts only mode
`LOCAL_BOOTSTRAP=1` with nonzero matching bootstrap ID or
`REFINANCE_REPLACEMENT=2` with zero bootstrap ID. Bootstrap also calls exact
`resolveBootstrap(bootstrapId)`. The coordinator, not a forwarded borrower or
`tx.origin`, is the factory caller inside `requestRefinance`; the resolver supplies
the borrower and complete configuration. Bootstrap initializes the old account
directly `ACTIVE/CURRENT`, then the coordinator installs all old rights/security
before quote issuance. Each missing custody record first calls exact
`resolveCustodyAsset(assetId)` through the custody contract's constructor-bound asset
source, matches token/runtime/active/exact-delta to
the exact returned `CustodyRecord.identityHash`, and proves exact borrower-to-custody
`transferFrom` balance deltas,
then checked `totalCustody`, `HELD`, and only afterward the lien. Exact record replay
proves attributable custody/aggregate/lien state without another transfer. The
original position owner and sole canonical payoff
beneficiary equal `oldLender`; tranche/position claims, claim-bearing debt, and the
quote route match exactly, with no alternate beneficiary. Replacement initializes only `CREATED/NONE` zero debt and no
positions/custody/lien, bound to the one derived refinance.

## Operation identities

```text
request_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REQUEST_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id
))

execute_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EXECUTE_OPERATION_V1",
  chainid, refinance_coordinator, refinance_id, quote_id,
  debt_state_version
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

component_payout_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_COMPONENT_PAYOUT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  quote_id,
  payoff_component_hash,
  old_net_payoff,
  refinance_fee,
  borrower_proceeds,
  funding_amount
))

recipient_balance_delta_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_RECIPIENT_BALANCE_DELTA_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  settlement_token,
  old_lender,
  old_lender_delta,
  payoff_fee_recipient,
  payoff_fee_delta,
  refinance_fee_recipient,
  refinance_fee_delta,
  borrower,
  borrower_delta,
  attributed_escrow_before,
  attributed_escrow_after,
  coordinator_operation_delta
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

effective_old_position_rights_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EFFECTIVE_OLD_POSITION_RIGHTS_V1",
  old_loan_id,
  position_manager,
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
  unchanged_historical_tranches_hash,
  unchanged_historical_positions_hash,
  unchanged_historical_checkpoints_hash,
  effective_old_position_rights_hash,
  true, // LoanRegistry.isTerminal(old_loan_id) after payoff
  old_net_payoff
))

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

lien_handoff_evidence_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_HANDOFF_RESULT_V1",
  chainid,
  lien_registry,
  handoff_id,
  refinance_id,
  collateral_id,
  old_loan_id,
  new_loan_id,
  prior_lien_version,
  next_lien_version,
  final_lien_state
))

lien_handoff_vector_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_LIEN_HANDOFF_VECTOR_V1",
  refinance_id,
  ordered_handoff_ids,
  ordered_handoff_evidence_hashes
))

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

For `BORROWER_CANCELLED`, `quote_disposition_after == INVALIDATED`; for `EXPIRED`,
it is `EXPIRED`. The latter is exact because every accepted record binds
`refinance.expiresAt == quote.validUntil`; boundary vectors prove both transition at
the same second. In both cases
`quote_disposition_source_id == cancel_operation_id`.
Quote invalidation occurs before refinance persistence and both effects roll back
together.

`coordinator_operation_delta` is the observed balance delta caused by the current
operation and must equal the expected attributed inflow or outflow. It is not the
coordinator's global balance. `attributed_escrow_*` is scoped to the refinance.
Unsolicited surplus is excluded from every liability, readiness, payout, refund,
and terminal-result field.

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
`cancellation_result_hash`; for execution it is `terminal_result_hash`; for an
intermediate or last refund it is that commitment's `refund_result_hash`. The last
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
| Attributed escrow after execution | `0` |
| Old debt after execution | `CLOSED/TERMINAL`; all economic/loss/credit values zero; debt version and state nonce each incremented once |
| Old raw positions after execution | byte-identical historical issuance facts; effective claims/votes zero |

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
