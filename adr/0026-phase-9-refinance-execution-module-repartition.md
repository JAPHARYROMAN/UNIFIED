# ADR 0026: Phase 9 Refinance Execution-Module Repartition

Status: rejected for topology by ADR 0027; retained as historical repartition evidence

Date: 2026-07-27

Owner: Protocol Architecture Authority

ADR 0027 rejects this ADR's five-library, eight-call, two-execution-module,
twelve-CREATE, nonce-12 coordinator topology, records a separate unproven candidate,
and leaves replacement topology selection pending. The 68-word `ExecutionPlanV1`, the
compiler boundary, and the ADR 0025 execution semantics recorded here remain inputs to
the next measurement and are not historicalized.

Historical-scope rule: every topology imperative, future-tense requirement,
implementation instruction, acceptance condition, and migration consequence in
sections 1 through 9 records only the rejected ADR 0026 candidate. None is operative,
none authorizes implementation or deployment, and none may satisfy an activation gate.
Only the unchanged plan format, compiler boundary, measurements, and ADR 0025 semantic
cross-references remain inputs to a successor ADR.

Work items: prerequisite control for `UNI-REFI-001` and `UNI-REFI-002`

## Context

ADR 0023 accepted a three-library, seven-call candidate before the complete bounded
execution and exit paths were compiled. The first maximum-path lifecycle prototype was
then compiled with the frozen Solidity `0.8.36`, Prague EVM, optimizer enabled at 200
runs, and non-via-IR settings. It measured:

| Artifact or isolated closure | Runtime bytes | Initcode bytes | EIP-170 result |
| --- | ---: | ---: | --- |
| complete lifecycle prototype | 40,375 | 40,427 | 15,799 bytes over |
| funding, cancellation, and refund | 19,273 | 19,325 | 5,303 bytes under |
| execution only | 26,547 | 26,599 | 1,971 bytes over |
| funding only | 13,053 | 13,105 | 11,523 bytes under |
| cancellation and refund only | 6,924 | 6,976 | 17,652 bytes under |

The measurement source diff is bound by SHA-256
`f408d159a8fbf8cbde9197e71456cf817d2c101f23e64c5abb10d7abdf4abc76`.
The in-memory isolation measurements changed no repository file: selected public
entries and their coordinator wrappers were replaced with fail-closed bodies or
removed only in compiler input, allowing ordinary Solidity dead-code elimination to
measure each reachable closure under the frozen settings.

A fourth execution library alone does not pass EIP-170. Separating exit behavior does
not shrink that execution closure. Moving execution into the coordinator is projected
at 31 to 32 KiB runtime, and reducing the original lifecycle module in place would
require removal of 15,799 bytes, or 39.1 percent, while retaining semantics. Those
alternatives do not provide an acceptable implementation boundary.

This ADR historically proposed replacing only the module-count, linked-call, and
deployment-order controls that the measurement invalidated. It preserved the protocol ABI, constructor, storage,
compiler, authority, state machine, evidence preimages, transaction atomicity, and
activation closure fixed by ADRs 0021 through 0025.

## Historical decision record — non-operative

### 1. Historical exact five-library same-source partition — non-operative

The rejected candidate would have contained exactly these five source-scope libraries:

1. `Phase9RefinanceValidationModule`;
2. `Phase9RefinanceRequestModule`;
3. `Phase9RefinanceLifecycleModule`;
4. `Phase9RefinanceExecutionPrepareModule`; and
5. `Phase9RefinanceExecutionFinalizeModule`.

The validation and request ownership fixed by ADR 0023 does not change. The lifecycle
module owns exactly funding, cancellation, expiry, and refund behavior. The execution
prepare and finalize modules jointly own first execution and exact terminal replay.

All five libraries remain in the coordinator source file. They have empty storage
layouts, no fallback or receive function, no nested compiler link, and no
`DELEGATECALL` opcode. Only the coordinator may contain compiler-generated fixed-library
delegatecalls. No library address is supplied through calldata, storage, a registry,
policy, governance action, constructor argument, or post-deployment setter.

### 2. Historical exact coordinator call inventory — non-operative

The coordinator contains exactly eight compiler-generated fixed-library call sites:

| Module | Entry | Call sites |
| --- | --- | ---: |
| `Phase9RefinanceValidationModule` | `preflight` | 1 |
| `Phase9RefinanceRequestModule` | `begin`, `complete` | 2 |
| `Phase9RefinanceLifecycleModule` | funding, cancel, refund | 3 |
| `Phase9RefinanceExecutionPrepareModule` | `prepareExecution` | 1 |
| `Phase9RefinanceExecutionFinalizeModule` | `finalizeExecution` | 1 |

The external `executeRefinance(bytes32,bytes32)` selector remains unchanged. Its wrapper
performs exactly the two fixed calls below and makes no dependency call or other effect
between them. No external caller can invoke the second call through the coordinator or
supply the internal plan.

### 3. Historical prepare call, replay, and first-phase effects — non-operative

`prepareExecution(layout, refinanceId, operationId)` classifies exact terminal replay
before any first-execution state, quote, policy, account, registry, token, or other
dependency read. Exact replay returns the complete stored terminal result, an explicit
replay discriminator, and empty plan bytes. The coordinator returns that result without
calling finalization. Replay remains storage-only, dependency-free, write-free,
transfer-free, counter-free, and log-free.

When replay misses, prepare performs the complete pre-effect validation required by
ADRs 0021 and 0025, writes provisional unversioned `EXECUTING` before the first external
effect, captures the one execution block and execution time, validates the consumed
quote and canonical policy/account/manager/asset bindings, captures the initial public
snapshots and payout baselines, consumes the quote, executes payout legs zero and one,
records the old-loan payoff, and proves the post-payoff snapshot. It then returns an
explicit non-replay discriminator, an empty replay result, the exact opaque execution
plan bytes, and `planHash = keccak256(executionPlanBytes)`. The plan is produced only
in coordinator execution context.

The plan is an internal memory transport, not protocol input, persistent state,
authority, or a new ABI surface. Prepare emits no terminal event and writes no terminal
result.

### 4. Historical transport decision for exact static `ExecutionPlanV1`

The execution transport is not a dynamic validation plan. `ExecutionPlanV1` is an
all-static ABI tuple of exactly 68 words and exactly 2,176 bytes. Its domain word is
`keccak256("UNIFIED_REFINANCE_EXECUTION_PLAN_V1")`. It contains no dynamic bytes,
string, array, tuple offset, pointer, or variable-length tail. The exact word groups
are:

| Word range | Count | Exact fields |
| --- | ---: | --- |
| 0..7 | 8 | domain, chain ID, coordinator, refinance ID, operation ID, `execution_block`, `executed_at`, and `planSuffixHash` |
| 8..20 | 13 | stored state version, refinance nonce, quote ID, consumed pre-payoff debt-state version, typed consumed-quote hash, refinance-policy hash, old loan ID, new loan ID, old account, old position manager, new account, new position manager, and settlement token |
| 21..29 | 9 | collateral count/hash, replacement-tranche count/hash, replacement-position count/hash, commitment count/hash, and distinct-recipient count |
| 30..59 | 30 | `address[4]` payout recipients, `uint256[4]` payout amounts, `address[4]` sorted unique recipients, `uint256[4]` unique expected amounts, `uint256[4]` unique starting balances, and the first two legs' `uint256[2]` recipient-before, recipient-after, coordinator-before, coordinator-after, and `bytes32[2]` leg hashes |
| 60..67 | 8 | initial tranche, position, and rights snapshot hashes; replacement-debt hash; component-payout hash; old-debt-state hash; old-debt-result hash; and coordinator balance before all payout legs |

The exact formulas are:

```text
planBytes = abi.encode(executionPlanV1)
require(planBytes.length == 2176)
planSuffixHash = keccak256(raw 1920-byte planBytes suffix from byte 256 through byte 2175)
planHash = keccak256(planBytes)
replacementDebtHash = keccak256(abi.encode(replacementDebt))
fundedCommitmentInventoryHash = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_FUNDED_COMMITMENT_INVENTORY_V1"),
  block.chainid,
  address(this),
  refinanceId,
  orderedCommitmentIds,
  orderedFundingCommitmentRecords
))
```

The suffix is exactly the contiguous ABI words 8 through 67 already present in
`planBytes`; it is not re-encoded and has no separate domain. In a memory implementation
its data begins 256 bytes after the first plan data byte and its length is exactly 1,920
bytes. The full `planHash` is domain-bound by word 0 and binds word 7's suffix hash.
This permits the coordinator to verify the exact length, fixed header, raw suffix hash,
and full hash with bounded memory hashing without decoding or re-encoding 68 words.

`fundedCommitmentInventoryHash` is an internal, transaction-local transport binding,
not a protocol event/result preimage. Finalization reconstructs the exact ordered ID
array and complete stored funding-commitment record array, validates every existing
identity/state/count rule, and requires this hash before the first finalization effect.
The plan's other typed quote, policy, vector, snapshot, component, replacement-debt,
and old-debt hashes use the normative ADR 0025 preimages. This ADR authorizes no change
to a protocol evidence preimage and no identity-only or ad hoc nested compression.

### 4.1 Historical machine-readable repartition manifest — non-operative topology

The following JSON object was normative only for the rejected ADR 0026 candidate. It is
retained byte-for-byte as historical evidence; its ownership, call-site, creation-order,
and budget entries are non-operative and cannot authorize implementation or deployment.
A successor may separately incorporate the unchanged `ExecutionPlanV1` fields.

<!-- phase9-refinance-repartition-manifest:start -->
```json
{
  "schema": "phase9-refinance-repartition-v1",
  "status": "historical-rejected-topology",
  "topology_selected": false,
  "normative_execution_sizes_accepted": false,
  "execution_plan_retained_by_adr0027": true,
  "execution_plan": {
    "name": "ExecutionPlanV1",
    "abi_words": 68,
    "abi_bytes": 2176,
    "domain": "UNIFIED_REFINANCE_EXECUTION_PLAN_V1",
    "suffix_word_start": 8,
    "suffix_word_count": 60,
    "suffix_bytes": 1920,
    "fields": [
      {"name": "domain", "abi_type": "bytes32", "word_start": 0, "word_count": 1},
      {"name": "chainId", "abi_type": "uint256", "word_start": 1, "word_count": 1},
      {"name": "coordinator", "abi_type": "address", "word_start": 2, "word_count": 1},
      {"name": "refinanceId", "abi_type": "bytes32", "word_start": 3, "word_count": 1},
      {"name": "operationId", "abi_type": "bytes32", "word_start": 4, "word_count": 1},
      {"name": "executionBlock", "abi_type": "uint64", "word_start": 5, "word_count": 1},
      {"name": "executedAt", "abi_type": "uint64", "word_start": 6, "word_count": 1},
      {"name": "planSuffixHash", "abi_type": "bytes32", "word_start": 7, "word_count": 1},
      {"name": "storedStateVersion", "abi_type": "uint64", "word_start": 8, "word_count": 1},
      {"name": "refinanceNonce", "abi_type": "uint64", "word_start": 9, "word_count": 1},
      {"name": "quoteId", "abi_type": "bytes32", "word_start": 10, "word_count": 1},
      {"name": "consumedDebtStateVersion", "abi_type": "uint64", "word_start": 11, "word_count": 1},
      {"name": "consumedQuoteHash", "abi_type": "bytes32", "word_start": 12, "word_count": 1},
      {"name": "refinancePolicyHash", "abi_type": "bytes32", "word_start": 13, "word_count": 1},
      {"name": "oldLoanId", "abi_type": "bytes32", "word_start": 14, "word_count": 1},
      {"name": "newLoanId", "abi_type": "bytes32", "word_start": 15, "word_count": 1},
      {"name": "oldAccount", "abi_type": "address", "word_start": 16, "word_count": 1},
      {"name": "oldPositionManager", "abi_type": "address", "word_start": 17, "word_count": 1},
      {"name": "newAccount", "abi_type": "address", "word_start": 18, "word_count": 1},
      {"name": "newPositionManager", "abi_type": "address", "word_start": 19, "word_count": 1},
      {"name": "settlementToken", "abi_type": "address", "word_start": 20, "word_count": 1},
      {"name": "collateralCount", "abi_type": "uint32", "word_start": 21, "word_count": 1},
      {"name": "collateralIdsHash", "abi_type": "bytes32", "word_start": 22, "word_count": 1},
      {"name": "replacementTrancheCount", "abi_type": "uint32", "word_start": 23, "word_count": 1},
      {"name": "replacementTranchesHash", "abi_type": "bytes32", "word_start": 24, "word_count": 1},
      {"name": "replacementPositionCount", "abi_type": "uint32", "word_start": 25, "word_count": 1},
      {"name": "replacementPositionsHash", "abi_type": "bytes32", "word_start": 26, "word_count": 1},
      {"name": "commitmentCount", "abi_type": "uint32", "word_start": 27, "word_count": 1},
      {"name": "fundedCommitmentInventoryHash", "abi_type": "bytes32", "word_start": 28, "word_count": 1},
      {"name": "distinctRecipientCount", "abi_type": "uint8", "word_start": 29, "word_count": 1},
      {"name": "payoutRecipients", "abi_type": "address[4]", "word_start": 30, "word_count": 4},
      {"name": "payoutAmounts", "abi_type": "uint256[4]", "word_start": 34, "word_count": 4},
      {"name": "uniqueRecipients", "abi_type": "address[4]", "word_start": 38, "word_count": 4},
      {"name": "uniqueExpected", "abi_type": "uint256[4]", "word_start": 42, "word_count": 4},
      {"name": "uniqueStartingBalances", "abi_type": "uint256[4]", "word_start": 46, "word_count": 4},
      {"name": "firstLegRecipientBefore", "abi_type": "uint256[2]", "word_start": 50, "word_count": 2},
      {"name": "firstLegRecipientAfter", "abi_type": "uint256[2]", "word_start": 52, "word_count": 2},
      {"name": "firstLegCoordinatorBefore", "abi_type": "uint256[2]", "word_start": 54, "word_count": 2},
      {"name": "firstLegCoordinatorAfter", "abi_type": "uint256[2]", "word_start": 56, "word_count": 2},
      {"name": "firstLegHashes", "abi_type": "bytes32[2]", "word_start": 58, "word_count": 2},
      {"name": "initialTrancheHash", "abi_type": "bytes32", "word_start": 60, "word_count": 1},
      {"name": "initialPositionHash", "abi_type": "bytes32", "word_start": 61, "word_count": 1},
      {"name": "initialRightsHash", "abi_type": "bytes32", "word_start": 62, "word_count": 1},
      {"name": "replacementDebtHash", "abi_type": "bytes32", "word_start": 63, "word_count": 1},
      {"name": "componentPayoutHash", "abi_type": "bytes32", "word_start": 64, "word_count": 1},
      {"name": "oldDebtStateHash", "abi_type": "bytes32", "word_start": 65, "word_count": 1},
      {"name": "oldDebtResultHash", "abi_type": "bytes32", "word_start": 66, "word_count": 1},
      {"name": "coordinatorBalanceBeforeAll", "abi_type": "uint256", "word_start": 67, "word_count": 1}
    ]
  },
  "caps": {
    "collateral_count": 16,
    "replacement_tranche_count": 8,
    "replacement_position_count": 32,
    "commitment_count": 32,
    "distinct_recipient_count": 4
  },
  "hashes": {
    "plan_suffix_hash": "keccak256(raw 1920-byte planBytes suffix at bytes 256..2175 / words 8..67)",
    "plan_bytes": "abi.encode(ExecutionPlanV1)",
    "plan_hash": "keccak256(planBytes)",
    "replacement_debt_hash": "keccak256(abi.encode(replacementDebt))",
    "funded_commitment_inventory_hash": "keccak256(abi.encode(keccak256(\"UNIFIED_REFINANCE_FUNDED_COMMITMENT_INVENTORY_V1\"), block.chainid, address(this), refinanceId, orderedCommitmentIds, orderedFundingCommitmentRecords))"
  },
  "zero_tail_rules": [
    "uniqueRecipients[i] == address(0) for i >= distinctRecipientCount",
    "uniqueExpected[i] == 0 for i >= distinctRecipientCount",
    "uniqueStartingBalances[i] == 0 for i >= distinctRecipientCount"
  ],
  "modules": [
    {"name": "Phase9RefinanceValidationModule", "ownership": "request-preflight", "entries": ["preflight"]},
    {"name": "Phase9RefinanceRequestModule", "ownership": "request-lock-and-completion", "entries": ["begin", "complete"]},
    {"name": "Phase9RefinanceLifecycleModule", "ownership": "funding-cancellation-refund", "entries": ["recordFundingCommitment", "cancelRefinance", "refundCommitment"]},
    {"name": "Phase9RefinanceExecutionPrepareModule", "ownership": "execution-replay-validation-midpoint", "entries": ["prepareExecution"]},
    {"name": "Phase9RefinanceExecutionFinalizeModule", "ownership": "execution-reresolution-lien-activation-terminal", "entries": ["finalizeExecution"]}
  ],
  "call_sites": [
    {"ordinal": 1, "wrapper": "requestRefinance", "module": "Phase9RefinanceRequestModule", "entry": "begin"},
    {"ordinal": 2, "wrapper": "requestRefinance", "module": "Phase9RefinanceValidationModule", "entry": "preflight"},
    {"ordinal": 3, "wrapper": "requestRefinance", "module": "Phase9RefinanceRequestModule", "entry": "complete"},
    {"ordinal": 4, "wrapper": "recordFundingCommitment", "module": "Phase9RefinanceLifecycleModule", "entry": "recordFundingCommitment"},
    {"ordinal": 5, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionPrepareModule", "entry": "prepareExecution"},
    {"ordinal": 6, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionFinalizeModule", "entry": "finalizeExecution"},
    {"ordinal": 7, "wrapper": "cancelRefinance", "module": "Phase9RefinanceLifecycleModule", "entry": "cancelRefinance"},
    {"ordinal": 8, "wrapper": "refundCommitment", "module": "Phase9RefinanceLifecycleModule", "entry": "refundCommitment"}
  ],
  "create_order": [
    {"nonce": 1, "artifact": "LienRegistry"},
    {"nonce": 2, "artifact": "CollateralCustodyV2"},
    {"nonce": 3, "artifact": "Phase9LoanAccount"},
    {"nonce": 4, "artifact": "PositionManagerV2"},
    {"nonce": 5, "artifact": "Phase9LoanFactory"},
    {"nonce": 6, "artifact": "Phase9RefinanceValidationModule"},
    {"nonce": 7, "artifact": "Phase9RefinanceRequestModule"},
    {"nonce": 8, "artifact": "Phase9RefinanceLifecycleModule"},
    {"nonce": 9, "artifact": "Phase9RefinanceExecutionPrepareModule"},
    {"nonce": 10, "artifact": "Phase9RefinanceExecutionFinalizeModule"},
    {"nonce": 11, "artifact": "PayoffQuoteEngine"},
    {"nonce": 12, "artifact": "RefinanceCoordinator"}
  ],
  "module_runtime_budget_bytes": 22118
}
```
<!-- phase9-refinance-repartition-manifest:end -->

The four payout entries are always populated in canonical leg order, including
zero-amount legs. The unique-recipient arrays use increasing unsigned-`uint160` order.
Every index at or above the distinct-recipient count in each parallel unique-recipient
array must be zero. Counts are bounded exactly at 16 collateral IDs, 8 replacement
tranches, 32 replacement positions, 32 funding commitments, and 4 distinct payout
recipients. Finalization re-resolves the complete vectors and requires their counts and
typed hashes to match the plan before the uninterrupted lien barrier.

For first execution, the coordinator requires exactly 2,176 plan bytes, the exact
domain, chain, coordinator, refinance ID, and operation ID header, the returned
`planHash`, the raw suffix hash, current stored `EXECUTING`, the unchanged active old-loan
lock, full attributed escrow equal to accepted funding, execution attempt zero,
terminal evidence zero, and an unprocessed matching operation ID. It forwards the
identical byte string and hash to finalization. It does not decode a dynamic tail,
rewrite a word, catch a prepare/finalize revert, or perform an external call between
the two modules.

The plan is never accepted from protocol calldata, persisted for a later transaction,
returned from the external protocol method, exposed by a view, or treated as evidence
merely because its digest is nonzero. Empty, short, long, offset-bearing, reordered,
nonzero-tail, count/hash-inconsistent, or header/suffix/plan-hash-inconsistent bytes fail
before finalization effects.

### 5. Historical finalize call and rollback boundary — non-operative

`finalizeExecution(layout, refinanceId, operationId, executionPlanBytes, planHash)`
repeats the coordinator's exact length, header, plan hash, suffix hash, guard, lock,
escrow, attempt, evidence, operation, count, fixed-tail, and ordering checks. It then
re-resolves and re-hashes the canonical quote, policy, accounts, managers, asset,
collateral, replacement, commitment, payout, public snapshot, and old-debt facts before
the first finalization effect. In particular, finalization recomputes the three
after-payoff snapshot hashes at the captured execution block and requires each to equal
its corresponding initial snapshot hash before entering the lien barrier. After those
checks, it performs the remaining order fixed by ADR 0025 without returning to the
coordinator during the lien barrier:

1. begin every lien handoff;
2. verify every old lien is pending;
3. complete every lien handoff;
4. verify every successor lien is active;
5. register replacement tranches and positions and activate the replacement account;
6. execute payout legs two and three;
7. prove leg-local, alias-aware recipient, and coordinator conservation;
8. consume the bounded commitment inventory and clear attributed escrow;
9. recompute the final old-manager snapshots at the same execution block and require
   each to equal its corresponding initial snapshot hash; and
10. write the one terminal result and emit the frozen execution event followed by the
    one durable `FUNDING_ESCROWED -> COMPLETED` transition event.

Prepare and finalize execute in one top-level coordinator transaction. A coordinator
plan-length/header/hash/state rejection, any single-word or tail mutation, finalization
validation failure, downstream failure, out-of-gas condition, or terminal persistence
failure reverts the provisional guard, quote
consumption, payouts, payoff, liens, replacement activation, escrow changes, storage,
and logs from both calls. There is no recoverable partial phase and no durable plan.

### 6. Historical size and compiler gates — non-operative topology

The compiler boundary remains Solidity `0.8.36+commit.8a079791.Emscripten.clang`,
OpenZeppelin Contracts `5.6.1`, Prague EVM, optimizer enabled at 200 runs, and
`viaIR: false`.

Each rejected-candidate execution module had a hard planning budget of 22,118 runtime
bytes, ten percent below the 24,576-byte EIP-170 limit. Meeting EIP-170 while exceeding
22,118 bytes would not have satisfied that prototype gate. Every module and the
coordinator was also required to pass the active 49,152-byte EIP-3860 initcode limit.
The measured lifecycle closure was the initial 19,273-runtime-byte planning bound;
implementation growth was to be measured, not assumed.

The rejected first repartition prototype was required to report exact runtime, initcode,
linked creation and runtime offsets, compiler-generated delegatecall count, and maximum-
vector gas for all five modules and the coordinator. Exceeding either execution-module
budget required another architecture decision; evidence hashes, bounds, checks, and
compiler settings could not be weakened to recover size.

### 7. Historical exact twelve-CREATE synthetic-local topology — non-operative

The rejected ADR-0026 candidate graph would have used exactly twelve consecutive
zero-value top-level `CREATE` transactions from the nonce-preconditioned broadcaster:

1. nonce 1: `LienRegistry`;
2. nonce 2: `CollateralCustodyV2`;
3. nonce 3: `Phase9LoanAccount` implementation;
4. nonce 4: `PositionManagerV2` implementation;
5. nonce 5: `Phase9LoanFactory`;
6. nonce 6: `Phase9RefinanceValidationModule`;
7. nonce 7: `Phase9RefinanceRequestModule`;
8. nonce 8: `Phase9RefinanceLifecycleModule`;
9. nonce 9: `Phase9RefinanceExecutionPrepareModule`;
10. nonce 10: `Phase9RefinanceExecutionFinalizeModule`;
11. nonce 11: `PayoffQuoteEngine`; and
12. nonce 12: the fully linked `RefinanceCoordinator`.

The rejected candidate prediction used RLP nonce byte `0x0c`. For the canonical
synthetic-local broadcaster `0x70997970c51812dc3a010c7d01b50e0d17dc79c8`, its predicted
coordinator was `0xca03dc4665a8c3603cb4fd5ce71af9649dc00d44`. That graph would
have left both latest and pending candidate nonces at 13 (`0x0d`), with the nonce-1 lien
registry and nonce-11 payoff engine bound to the predicted coordinator.

ADR 0024's identity separation, explicit nonce precondition, verification-before-grant,
single governance-executor role grant, post-grant evidence, and bounded reset controls
remain unchanged. The existing ten-CREATE scripts, schemas, artifacts, and observations
are historical candidate evidence only and are not ADR-0026 activation evidence.

### 8. Historical isolation and threat controls — non-operative topology

The repartition adds two fixed code identities and one bounded in-transaction transport.
The historical candidate acceptance plan required evidence for:

- direct calls to effect-capable library entries cannot mutate coordinator storage or
  custody and fail the compiler library execution-context guard;
- neither execution module has storage, a nested link, a delegatecall, a caller-selected
  target, arbitrary call, fallback, rescue, sweep, or self-destruct path;
- `address(this)` remains the coordinator and `msg.sender` remains the original external
  caller across both fixed delegatecalls;
- duplicate policy, snapshot, token, arithmetic, and evidence helpers cannot drift
  semantically between modules;
- every one of the 68 static plan words, every fixed-array tail, every count/hash pair,
  and every canonical order is independently mutation-tested;
- reentrancy during either phase observes provisional `EXECUTING` and cannot obtain a
  terminal result or enter another mutator;
- exact replay cannot reach finalization, and first execution cannot supply an empty
  plan or a replay result;
- only finalization writes terminal storage or emits terminal events; and
- maximum 32-commitment, 16-lien, 8-tranche, 32-position, and four-leg alias patterns
  fit the reviewed local block-gas limit with deterministic reset after failure.

### 9. Historical activation closure — no authority

The historical priority-zero plan required storage-only replay before dependencies, no
catch around either execution-module call, no external/caller-authored/persisted plan,
full rollback under injected failure at every boundary, and an uninterrupted four-stage
lien barrier. Its priority-one plan required mutation of every plan word, fixed-array
tail, count/hash pair, and ordering rule, plus exact conformance to every normative ADR
0025 preimage.

This ADR changes no interface, selector, tuple, event, error, constructor, storage
declaration, checkpoint, method-activation manifest, backlog status, security verdict,
deployment artifact, or production topology. It does not make the current oversized
prototype deployable and does not authorize updating an expected artifact hash.

`UNI-REFI-001`, `UNI-REFI-002`, every D1-D4 activation gate, and `P9-REFI-001` remain
closed. No implementation may begin under ADR 0026. A successor ADR must independently
select, measure, and freeze its linked-module, deployment, isolation, gas, and evidence
controls before implementation can be considered.

## Consequences

- The measured funding/cancel/refund closure remains together with 5,303 bytes of
  EIP-170 margin.
- Execution gains an atomic two-call partition without a proxy, facet router, mutable
  module registry, storage migration, or external ABI addition.
- The fixed link-target count increases from three to five, the compiler call-site
  count from seven to eight, and the top-level creation count from ten to twelve.
- In the rejected candidate, the payoff engine would have moved from nonce 9 to nonce
  11 and the coordinator from nonce 10 to nonce 12. Those predictions are historical
  and MUST NOT drive a production or synthetic-local migration.
- Existing ten-CREATE evidence remains useful as historical failure/repartition input
  but cannot satisfy an implementation or activation gate.

## Verification

This historical record is complete only when deterministic semantic tests pin its
status, measured sizes, source-diff digest, five library names, exact
ownership, two-call execution order, 68-word/2,176-byte static plan, returned suffix and
plan hashes, zero tails, plan bindings and caps, 22,118-byte budgets,
eight call sites, twelve-CREATE order, nonce/address predictions, rollback semantics,
isolation rules, and closed activation boundary. Production checks remain fail-closed;
only a successor ADR may define the topology and evidence required for a reviewed
implementation.
