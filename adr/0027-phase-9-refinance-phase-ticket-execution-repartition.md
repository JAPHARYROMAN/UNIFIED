# ADR 0027: Phase 9 Refinance Phase-Ticket Execution Repartition

Status: unproven/non-accepted eight-library topology candidate; semantic security gates frozen; size closure pending remeasurement

Date: 2026-07-27

Owner: Protocol Architecture Authority

Work items: prerequisite control for `UNI-REFI-001` and `UNI-REFI-002`

## Context

ADR 0025 remains the authority for refinance execution order, state transitions,
evidence preimages, rollback, and terminal-event semantics. ADR 0026 attempted to place
those unchanged semantics in two execution libraries. The compiling prototype proved
that topology undeployable: prepare measured 27,544 runtime bytes and finalize measured
38,885 runtime bytes against the 22,118-byte execution-module budget.

Read-only compiler experiments then evaluated coordinator-sequenced phase partitions.
Every experiment used Solidity 0.8.36, Prague EVM, optimizer enabled at 200 runs, and
`viaIR: false`. Repository Solidity was not modified by the measurements.

| Experiment | Material runtime measurements | Result |
| --- | --- | --- |
| ADR 0026 two-phase prototype | prepare 27,544; finalize 38,885 | rejected |
| Four execution modules with duplicated final checks | prevalidation 21,921; payoff 17,630; lien plus revalidation 35,181; combined final effects 19,015 | rejected |
| Four modules with secure combined activation and settlement | combined final module 27,364 | rejected |
| One reusable three-entry execution validator | guard 1,325; validator 31,035; payoff 18,396; lien 8,165; finalize 19,058 | rejected |
| Dynamic post-validation context | two-entry validator 24,309; either standalone phase validator 24,177 | rejected |
| Exact 14-word typed phase-ticket return | validator 22,424; guard-hash-carry optimization 22,190 | rejected; the latter remained 72 bytes over budget |
| Two-word proof over the same 14-word ticket preimage | post validator 21,829; lien 11,281; finalize 19,102 | rejected as size closure; exact current-context receipt and independently authoritative lien/finalize checks require remeasurement |

The last measured candidate returned only a 64-byte proof after each post-effect
validation. The exact fresh current-context receipt and the independently authoritative
consumer-owned lien/finalization checks were absent from the measured candidate, so its
289-byte validator margin does not establish a normative size closure. No accepted
eight-library closure exists. A successor candidate may split the two phase validators
or repartition differently, but it must retain the 64-byte proof, unchanged payload/plan
bytes, and all semantic requirements below.

The fully sequenced in-memory topology variant also removed legacy execution from the
lifecycle library. It measured the stripped lifecycle at 19,273 runtime / 19,325
initcode bytes and the six-call coordinator wrapper at 8,126 runtime / 8,557 initcode
bytes. The UTF-8 measurement source is bound by SHA-256
`088bc586a7c34e9cf96f3df714e10c1d31ba2d4b060254ed5beb0171e860f0b3`.
The source has 249,694 characters. That digest identifies an in-memory measurement
input, not a repository artifact or an
accepted deployment bytecode hash.

ADR 0027 makes ADR 0026's topology historical but does not accept a replacement library
count, linked-call inventory, creation order, nonce sequence, or coordinator prediction.
The eight-library/12-call/15-CREATE values below bind only the non-accepted measured
candidate. ADR 0025 semantics and all protocol ABI, constructor, storage, event, error,
and evidence authorities remain unchanged.

## Decision

The semantic gates in sections 2 through 7 are mandatory inputs to the next topology
measurement. The topology in sections 1, 8, and 9 is a non-accepted candidate record and
MUST NOT be implemented, deployed, relabeled as activation-grade, or treated as proof
that the mandatory gates fit within budget.

### 1. Unproven eight-library same-source candidate

The unproven in-memory candidate contained these eight source-scope, storage-free
libraries:

1. `Phase9RefinanceValidationModule`;
2. `Phase9RefinanceRequestModule`;
3. `Phase9RefinanceLifecycleModule`;
4. `Phase9RefinanceExecutionPrePayoffModule`;
5. `Phase9RefinanceExecutionPayoffModule`;
6. `Phase9RefinanceExecutionPostValidationModule`;
7. `Phase9RefinanceExecutionLienModule`; and
8. `Phase9RefinanceExecutionFinalizeModule`.

The lifecycle-only split remains a useful measured boundary. The six-stage execution
ownership and order that a successor must preserve semantically are:

1. `prepareExecution`: exact storage-only replay first; otherwise effect-free bounded
   validation and `ValidationPayloadV1` production;
2. `executePayoff`: rehash payload and guard, recheck every guard fact, write provisional
   `EXECUTING`, consume the quote, perform payout legs zero and one, record payoff, and
   produce the unchanged 68-word plan and payoff receipt;
3. `validatePreLien`: reread every pre-lien fact and return a two-word proof;
4. `executeLienBarrier`: perform begin-all, verify-all-pending, complete-all, and
   verify-all-active without returning to the coordinator during those loops;
5. `validatePreFinalize`: reread every pre-finalization fact and return a fresh proof;
6. `finalizeExecution`: activate replacement, prove the activation postcondition,
   perform payout legs two and three, prove conservation, consume inventory, prove the
   final snapshot, write the terminal result, and emit the frozen events in order.

No module links or delegates again. All module targets are compiler-fixed. No caller,
constructor, registry, policy, storage item, or governance action supplies a module
address.

### 2. Effect-free validation and the provisional guard

Pre-payoff and post-effect validation SHALL be compiler- and opcode-proven free of
`SSTORE`, `TSTORE`, `LOG0` through `LOG4`, `CALL`, `CREATE`, `CREATE2`,
`SELFDESTRUCT`, and nested `DELEGATECALL` after metadata is stripped. Their external
dependency reads SHALL compile only to bounded `STATICCALL` operations against the
fixed canonical dependencies.

`prepareExecution` first performs a storage-only replay discrimination. Exact replay
returns the stored terminal result plus empty `contextBytes`, zero `contextHash`, and
zero non-replay ticket material; the coordinator returns immediately and skips all five
remaining execution stages. A first-execution result must instead have the canonical
nonempty context and a canonical zero replay result.

`prepareExecution` writes no `EXECUTING` state. Before `executePayoff` writes it, payoff
uses bounded `STATICCALL` to reread the canonical current quote and five components,
requires `storedStateVersion < type(uint64).max`, recomputes
`operationId = keccak256(abi.encode("UNIFIED_REFINANCE_EXECUTE_OPERATION_V1",
block.chainid, address(this), refinanceId, quoteId, currentQuote.debtStateVersion))`,
and requires exact supplied-operation equality. It rechecks the current
`FUNDING_ESCROWED` record, version, attempt, evidence, full accepted/attributed escrow,
active old-loan lock, expiry, unprocessed operation, and issued quote immediately before
it writes provisional `EXECUTING`. It writes that guard before the first external effect.

Any same-refinance callback after that point observes `EXECUTING`; that fact alone is
not sufficient to close a callback into another refinance or coordinator mutator. A
revert at any later module,
dependency, token, lien stage, persistence step, or event step rolls the entire
top-level transaction back to the exact prior `FUNDING_ESCROWED` state.

### 3. `ValidationPayloadV1`

The pre-payoff module alone produces `ValidationPayloadV1`. It is internal memory,
never protocol calldata, never storage, never exposed by a protocol view, and never a durable
capability. Its nested ABI members are:

- `RefinanceRecord` (27 static words);
- `RefinancePolicyFacts`: six static header words, `bytes32[] collateralIds`,
  `DebtState` (21 words), `Tranche[]` (five words per item), and `Position[]` (six
  words per item);
- `ExecutionGraph` (four words);
- `PayoffQuoteV2` (20 words);
- `PayoffComponentV2[]`, whose five items each contain three static words and one
  dynamic obligation-code string;
- the three-word initial snapshot;
- the 42-word fixed payout workspace;
- the 21-word old-debt-before value;
- the 44-word old-debt-evidence workspace;
- inventory hash, commitment count, execution block, and execution time.

For collateral count `c`, replacement-tranche count `t`, replacement-position count
`p`, component count `n`, and component code byte lengths `codeLen[i]`, the exact
top-level ABI word count is:

```text
168 + (33 + c + 5*t + 6*p) + (1 + 6*n + sum(ceil(codeLen[i] / 32)))
```

At `c=16`, `t=8`, `p=32`, `n=5`, and the fixed codes `PRINCIPAL`,
`ACCRUED_INTEREST`, `FEE`, `PENALTY`, and `FEE_PENALTY_CREDIT`, the result is exactly
485 words / 15,520 bytes. The root offset is `0x20`; the nested struct head is 167
words / `0x14e0`; and the policy offset is stored at struct word 27 with the constant
value `0x14e0`. The other offsets are count-derived, not universal constants:

```text
componentsOffset = 0x14e0 + 0x20 * (33 + c + 5*t + 6*p)
policy.collateralIdsOffset = 0x3c0
policy.replacementTranchesOffset = 0x3c0 + 0x20 * (1 + c)
policy.replacementPositionsOffset = policy.replacementTranchesOffset + 0x20 * (1 + 5*t)
componentElementOffset[i] = 0x20*n + 0x20 * sum(j=0..i-1)(5 + ceil(codeLen[j]/32))
component[i].obligationCodeOffset = 0x80
```

Only at the maximum `c=16`, `t=8`, `p=32` are those last three derived values
`componentsOffset=0x3800`, `replacementTranchesOffset=0x5e0`, and
`replacementPositionsOffset=0xb00`. With the five fixed codes, every code occupies one
data word and the element offsets relative to the array tuple head after its length word
are exactly `0xa0`, `0x160`, `0x220`, `0x2e0`, and `0x3a0`; each element's string tail
begins at its tuple-relative offset `0x80`.

Every consumer SHALL require the count-derived exact length, these canonical offsets,
zero ABI padding, fixed component count/order/code, all caps, and the unchanged
`contextHash = keccak256(contextBytes)`. Short, long, offset-aliased, trailing,
noncanonically padded, or count-inconsistent bytes fail before effects. Decoding and
canonically re-encoding the complete payload must reproduce byte-identical
`contextBytes`. A semantically identical canonical construction is harmless because it
produces the identical raw bytes; only a byte-different semantic re-encoding fails.

### 4. Guard and pre-payoff ticket

`guardHash` is the hash of exactly 18 typed ABI words in this order:

```text
keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_EXECUTION_GUARD_V1"),
  block.chainid,
  address(this),
  refinanceId,
  operationId,
  oldLoanId,
  quoteId,
  uint8(FUNDING_ESCROWED),
  storedStateVersion,
  refinanceNonce,
  fundingAmount,
  acceptedFunding,
  escrowedUnits,
  activeLockWord,
  executionAttempts,
  terminalEvidenceHash,
  processedOperation,
  expiresAt
))
```

`prePayoffTicket` is exactly:

```text
keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PRE_PAYOFF_TICKET_V1"),
  guardHash,
  contextHash
))
```

The payoff module recomputes both hashes from unchanged bytes and current storage and
then independently rechecks every guard fact. A nonzero digest alone is never authority.

### 5. Execution plan and transcript

`ExecutionPlanV1` remains exactly ADR 0026's 68 static ABI words / 2,176 bytes,
including its header, raw 1,920-byte suffix hash, full plan hash, count/hash pairs,
zero tails, fixed payout arrays, snapshot hashes, inventory hash, and old-debt hashes.
ADR 0027 changes no plan word or protocol evidence preimage.

The transcript is exact and linear:

```text
contextHash -> prePayoffTicket -> planHash/payoffReceipt
            -> preLienProof.ticketHash -> lienHandoffVectorHash/lienResult
            -> preFinalizeProof.ticketHash -> terminal result
```

`payoffReceipt` is:

```text
keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PAYOFF_RECEIPT_V1"),
  block.chainid, address(this), refinanceId, operationId,
  contextHash, prePayoffTicket, planHash, oldDebtStateHash
))
```

`lienResult` is:

```text
keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_LIEN_RESULT_V1"),
  block.chainid, address(this), refinanceId, operationId,
  preLienProof.ticketHash, lienHandoffVectorHash
))
```

`lienHandoffVectorHash` is exactly the ADR 0025 canonical hash. Any implementation-local
identifier `lienVectorHash` SHALL be a byte-for-byte alias of that same word; it is not
a second hash, wrapper, or alternate preimage. This ADR uses
`lienHandoffVectorHash` exclusively below.

The coordinator retains identical `contextBytes` and `planBytes`, rehashes them before
every dispatch, and makes no call between a validator and its consumer.

### 6. Phase facts and two-word proof

`PhaseValidationProofV1` is exactly two static words / 64 bytes:

```text
{ bytes32 phaseFactsHash; bytes32 ticketHash; }
```

The four phase domains are constants, not caller input:

```text
PRE_LIEN_FACTS_DOMAIN = keccak256("UNIFIED_REFINANCE_PRE_LIEN_FACTS_V1")
PRE_LIEN_TICKET_DOMAIN = keccak256("UNIFIED_REFINANCE_PRE_LIEN_TICKET_V1")
PRE_FINALIZE_FACTS_DOMAIN = keccak256("UNIFIED_REFINANCE_PRE_FINALIZE_FACTS_V1")
PRE_FINALIZE_TICKET_DOMAIN = keccak256("UNIFIED_REFINANCE_PRE_FINALIZE_TICKET_V1")
```

Both facts hashes use eleven common non-action observations and one exact fresh current
execution-context observation. The exact common observation preimages are:

```text
o0 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_QUOTE_OBSERVATION_V1"),
  block.chainid, address(this), refinanceId, quoteId,
  keccak256(abi.encode(currentConsumedPayoffQuoteV2))
))

o1 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_COMPONENT_PAYOUT_OBSERVATION_V1"),
  componentPayoutHash
))

o2 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_SETTLEMENT_ASSET_OBSERVATION_V1"),
  settlementAssetId, settlementToken, settlementTokenDecimals,
  settlementToken.codehash, exactDeltaRequired, settlementAssetActive
))

o3 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_EXECUTION_GRAPH_OBSERVATION_V1"),
  keccak256(abi.encode(currentExecutionGraph))
))

o4 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_COMMITMENT_INVENTORY_OBSERVATION_V1"),
  commitmentCount, fundedCommitmentInventoryHash
))

o5 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_SNAPSHOT_OBSERVATION_V1"),
  executionBlock, oldTrancheExecutionSnapshotHash,
  oldPositionExecutionSnapshotHash, oldRightsExecutionSnapshotHash
))

o6 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_MIDPOINT_OBSERVATION_V1"),
  payoutRecipients, payoutAmounts, payoutLegDeltaHashes[0],
  payoutLegDeltaHashes[1], coordinatorBalanceAfterLegOne,
  uniqueRecipientAddresses, uniqueRecipientBalancesBefore,
  currentUniqueRecipientBalances
))

o7 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_OLD_DEBT_OBSERVATION_V1"),
  keccak256(abi.encode(currentTerminalOldDebtState)), oldDebtResultHash
))

o8 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_REPLACEMENT_ABSENCE_OBSERVATION_V1"),
  keccak256(abi.encode(currentNewDebtState)),
  keccak256(abi.encode(currentNewTrancheIds)),
  keccak256(abi.encode(currentNewPositionIds)),
  activationOperationId, processedActivationOperation
))

o9 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_REPLACEMENT_DEBT_OBSERVATION_V1"),
  replacementDebtHash
))

o10 = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_REPLACEMENT_COLLECTIONS_OBSERVATION_V1"),
  replacementTranchesHash, replacementPositionsHash
))
```

Array provenance is explicit: payout arrays and their initial balances are retained in
the unchanged payload/plan; quote components come from the fresh bounded quote-engine
`STATICCALL`; commitment IDs and complete records are freshly reconstructed from
storage; current recipient balances and new tranche/position ID arrays are fresh reads;
and replacement tranche/position arrays are fresh canonical resolver results required
byte-equal to the retained payload. `currentExecutionGraph` is the exact four-word
`ExecutionGraph`; the current quote is the complete typed 20-word `PayoffQuoteV2`; and
every other named hash uses its unchanged ADR 0025/reference-evidence preimage, not a
label-only digest.

The twelfth word in both phases is the hash of the following exact 20-word / 640-byte
freshly recomputed context receipt:

```text
phaseCurrentContextHash = keccak256(abi.encode(
  keccak256("UNIFIED_REFINANCE_PHASE_CURRENT_CONTEXT_V1"),
  block.chainid,
  address(this),
  refinanceId,
  operationId,
  uint8(EXECUTING),
  storedStateVersion,
  refinanceNonce,
  fundingAmount,
  acceptedFunding,
  escrowedUnits,
  activeLockWord,
  executionAttempts,
  terminalEvidenceHash,
  terminalResultHash,
  processedOperation,
  quoteId,
  contextHash,
  collateralIds.length,
  keccak256(abi.encode(collateralIds))
))

terminalResultHash = state.terminalResults[refinanceId].resultHash
require terminalResultHash == bytes32(0)
```

The validator requires current state `EXECUTING`; full funding equalities
`acceptedFunding == escrowedUnits == fundingAmount`; the unchanged active-lock word;
`executionAttempts == 0`; zero terminal evidence and the exact stored terminal-result
word `state.terminalResults[refinanceId].resultHash == bytes32(0)`; the supplied operation
unprocessed; the unchanged quote and context hash; and exact bounded collateral count,
order, and hash before producing this word.

The exhaustive facts-hash preimages are therefore:

```text
preLienPhaseFactsHash = keccak256(abi.encode(
  PRE_LIEN_FACTS_DOMAIN,
  o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10,
  phaseCurrentContextHash
))

preFinalizePhaseFactsHash = keccak256(abi.encode(
  PRE_FINALIZE_FACTS_DOMAIN,
  o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10,
  phaseCurrentContextHash
))
```

All 12 observations are recomputed from current canonical dependencies. Phase facts
explicitly exclude current/pending/active lien tuples, handoff IDs, lien versions,
handoff evidence, `lienHandoffVectorHash`, and `lienResult`; that action data belongs
only to the adjacent effect consumer's canonical registry reads. A plan digest may
supply comparison material only after the validator proves equality to each fresh
observation. Neither a facts hash nor a ticket hash is an action preimage or authority.

Although only two words are returned, `ticketHash` is the hash of this exact 14-word /
448-byte static preimage:

```text
abi.encode(
  hardCodedTicketDomain,
  block.chainid,
  address(this),
  refinanceId,
  operationId,
  contextHash,
  planHash,
  parentHash,
  executionBlock,
  executedAt,
  storedStateVersion,
  refinanceNonce,
  quoteId,
  phaseFactsHash
)
```

For pre-lien, `hardCodedTicketDomain = PRE_LIEN_TICKET_DOMAIN` and
`parentHash = payoffReceipt`. For pre-finalize,
`hardCodedTicketDomain = PRE_FINALIZE_TICKET_DOMAIN` and `parentHash = lienResult`.
Lien and finalization reconstruct and hash all 14 words, require the exact constant
phase domain, require both proof words nonzero, and compare the proof byte-for-byte.
Proofs cannot cross a phase, refinance, operation, plan, payload, block/time capture,
state version, nonce, quote, parent result, chain, or coordinator.

### 7. Write set, callbacks, and authority

`validatePreLien`, `executeLienBarrier`, `validatePreFinalize`, and
`finalizeExecution` SHALL each independently reread and require the current record to
be `EXECUTING`, the unchanged active old-loan lock to name this refinance, accepted
funding and attributed escrow both to equal full funding, execution attempt zero,
terminal evidence zero, exact stored terminal-result `resultHash` zero, and the supplied
operation unprocessed. The
coordinator makes no call or effect between either validator return and its immediately
adjacent consumer dispatch.

As its first action before `beginHandoff`, the lien module rereads every strictly
ordered current lien, requires the complete expected old-active tuple and zero pending
IDs, proves the derived handoff absent through exact `UnknownLienHandoff` revert data,
and independently derives and checks collateral order/count/hash, record lien version,
next versions, handoff IDs, and evidence hashes. It alone owns all pending tuple/hash
material and all four lien loops; none of that action material is returned to or
authorized by the validator. It returns only the exact ADR 0025
`lienHandoffVectorHash` and the `lienResult` fixed in section 5.

Before its first activation effect, finalization independently rederives every handoff
ID, version, and evidence hash; rereads every current active-new lien and completed
handoff tuple; reconstructs the exact ADR 0025 pending and active observation arrays,
`lienHandoffVectorHash`, and `lienResult`; and requires byte equality to the lien output
and to the unchanged adjacent pre-lien ticket used by the section 5 result preimage. It
also reconstructs the exact ordered commitment ID and complete stored-record arrays and
derives activation inputs from retained unchanged bytes plus fresh canonical state.

The lien and finalization canonical reads are the sole action authority. Ticket headers
are historical adjacency commitments, not current authority; a facts hash is never an
effect or action preimage.

No effect-capable implementation is acceptable until a closed codehash, call-graph,
and write-set proof covers every fixed dependency invoked during payoff, lien,
activation, payout, commitment consumption, and terminal persistence. Every reachable
effect callee SHALL be proven unable to callback any coordinator mutator or any route
that can enter a same- or cross-refinance mutation path. A proof relying only on the
current refinance's `EXECUTING` state, operation replay checks, or active lock is
insufficient because it does not close another refinance or another mutator. The proof
SHALL also establish that no reachable callee can mutate any refinance's escrow, lock,
quote, lien, replacement, commitment, or terminal state. Any callable coordinator
mutation edge rejects the candidate. This is a hard acceptance prerequisite, not
documentation deferred until after implementation.

The payload, plan, receipts, and proofs are never accepted from external calldata,
persisted, exposed by a protocol view, or reusable in a later transaction. There is no
catch, fallback, rescue, sweep, arbitrary call, signature-authorized transport,
caller-selected target, nested link, or nested delegatecall. Only finalization writes
terminal storage and emits the execution event followed by the durable completion
transition event.

### 8. Size and topology gates

The measured prototype figures are:

| Artifact | Runtime | Initcode | Runtime margin to 22,118 | Acceptance |
| --- | ---: | ---: | ---: | --- |
| lifecycle, funding/cancel/refund only | 19,273 | 19,325 | 2,845 | measured stripped topology input; recompile with final source |
| execution pre-payoff | 21,921 | 21,973 | 197 | unaccepted prototype; normative remeasurement pending |
| execution payoff | 18,396 | 18,448 | 3,722 | unaccepted prototype; normative remeasurement pending |
| execution post-validation, two entries, two-word proof | 21,829 | 21,881 | 289 | unaccepted prototype; predates exact fresh current-context receipt |
| execution lien | 11,281 | 11,333 | 10,837 | unaccepted prototype; predates independent current-guard/lien checks |
| execution finalize | 19,102 | 19,154 | 3,016 | unaccepted prototype; predates independent current-guard/inventory checks |
| coordinator, final six-call wrapper | 8,126 | 8,557 | 13,992 | measured topology wrapper; recompile with final modules |

No execution-module size in this table is accepted for the normative semantics in this
ADR. Every implementation artifact SHALL be recompiled together after all current
guard, adjacency, consumer-owned lien, and callback-closure controls are present and independently meet the
22,118-byte execution-module budget, EIP-170, and EIP-3860 without weakening a check,
bound, hash, or compiler setting. Until that evidence exists, topology implementation
and activation remain closed.

The unproven synthetic-local candidate graph would have used exactly 15 consecutive
top-level `CREATE`s. Its libraries occupied nonces 6 through 13, the payoff engine
nonce 14, and the coordinator nonce 15. For candidate
`0x70997970c51812dc3a010c7d01b50e0d17dc79c8`, the coordinator is exactly
`0x381445710b5e73d34aF196c53A3D5cDa58EDBf7A`; the candidate would end at nonce 16.
These values are measurement evidence only. The replacement topology, CREATE order,
coordinator address, and final nonce are pending a successor ADR backed by reproducible
normative compilation.

### 9. Machine-readable unproven-candidate and semantic-gate manifest

<!-- phase9-refinance-phase-ticket-manifest:start -->
```json
{
  "schema": "phase9-refinance-phase-ticket-repartition-v1",
  "status": "unproven-non-accepted-topology-candidate",
  "topology_selected": false,
  "compiler": {"solc": "0.8.36", "evm": "prague", "optimizer": true, "runs": 200, "via_ir": false},
  "runtime_budget": 22118,
  "validation_payload": {
    "name": "ValidationPayloadV1",
    "word_formula": "168 + (33+c+5*t+6*p) + (1+6*n+sum(ceil(codeLen[i]/32)))",
    "caps": {"c": 16, "t": 8, "p": 32, "n": 5},
    "fixed_codes": ["PRINCIPAL", "ACCRUED_INTEREST", "FEE", "PENALTY", "FEE_PENALTY_CREDIT"],
    "maximum_words": 485,
    "maximum_bytes": 15520,
    "root_offset": "0x20",
    "struct_head_words": 167,
    "struct_head_bytes": "0x14e0",
    "policy_offset_word": 27,
    "policy_offset": "0x14e0",
    "components_offset_word": 52,
    "components_offset_formula": "0x14e0 + 0x20*(33+c+5*t+6*p)",
    "policy_nested_offset_formulas": {"collateral": "0x3c0", "tranches": "0x3c0+0x20*(1+c)", "positions": "tranches+0x20*(1+5*t)"},
    "component_element_offset_formula": "0x20*n + 0x20*sum(j=0..i-1)(5+ceil(codeLen[j]/32))",
    "component_string_offset": "0x80",
    "fixed_code_element_offsets": ["0xa0", "0x160", "0x220", "0x2e0", "0x3a0"],
    "maximum_offsets": {"components": "0x3800", "collateral": "0x3c0", "tranches": "0x5e0", "positions": "0xb00"},
    "canonical_exact_length_offsets_padding_required": true,
    "canonical_reencode_must_equal_raw_bytes": true
  },
  "guard": {
    "domain": "UNIFIED_REFINANCE_EXECUTION_GUARD_V1",
    "preimage_words": 18,
    "fields": ["domain", "block.chainid", "address(this)", "refinanceId", "operationId", "oldLoanId", "quoteId", "FUNDING_ESCROWED", "storedStateVersion", "refinanceNonce", "fundingAmount", "acceptedFunding", "escrowedUnits", "activeLockWord", "executionAttempts", "terminalEvidenceHash", "processedOperation", "expiresAt"]
  },
  "pre_payoff_ticket": {"domain": "UNIFIED_REFINANCE_PRE_PAYOFF_TICKET_V1", "preimage_words": 3, "fields": ["domain", "guardHash", "contextHash"]},
  "replay_discriminator": {"storage_only": true, "returns_stored_terminal_result": true, "returns_empty_context": true, "skips_remaining_execution_calls": 5},
  "payoff_pre_effect": {"bounded_staticcall_quote_reread": true, "operation_id_domain": "UNIFIED_REFINANCE_EXECUTE_OPERATION_V1", "operation_id_uses_current_quote_debt_state_version": true, "stored_state_version_must_be_below_uint64_max": true},
  "execution_plan": {"semantic_authority": "ADR-0025", "transport_origin": "ADR-0026", "abi_words": 68, "abi_bytes": 2176, "unchanged": true},
  "proof": {
    "name": "PhaseValidationProofV1",
    "abi_words": 2,
    "abi_bytes": 64,
    "fields": ["phaseFactsHash", "ticketHash"],
    "ticket_preimage_words": 14,
    "ticket_preimage_bytes": 448,
    "ticket_preimage_fields": ["ticketDomain", "block.chainid", "address(this)", "refinanceId", "operationId", "contextHash", "planHash", "parentHash", "executionBlock", "executedAt", "storedStateVersion", "refinanceNonce", "quoteId", "phaseFactsHash"],
    "domains": {
      "pre_lien_facts": "UNIFIED_REFINANCE_PRE_LIEN_FACTS_V1",
      "pre_lien_ticket": "UNIFIED_REFINANCE_PRE_LIEN_TICKET_V1",
      "pre_finalize_facts": "UNIFIED_REFINANCE_PRE_FINALIZE_FACTS_V1",
      "pre_finalize_ticket": "UNIFIED_REFINANCE_PRE_FINALIZE_TICKET_V1"
    },
    "common_non_action_observations": 11,
    "fresh_context_observation": "phaseCurrentContextHash",
    "fresh_context_preimage_words": 20,
    "fresh_context_preimage_bytes": 640,
    "fresh_context_preimage_fields": ["domain", "block.chainid", "address(this)", "refinanceId", "operationId", "EXECUTING", "storedStateVersion", "refinanceNonce", "fundingAmount", "acceptedFunding", "escrowedUnits", "activeLockWord", "executionAttempts", "terminalEvidenceHash", "terminalResultHash", "processedOperation", "quoteId", "contextHash", "collateralCount", "collateralIdsHash"],
    "terminal_result_hash_source": "state.terminalResults[refinanceId].resultHash",
    "terminal_result_hash_required_zero": true,
    "phase_facts_exclude_lien_action_data": true,
    "facts_or_ticket_is_action_authority": false
  },
  "transcript": {
    "payoff_receipt_domain": "UNIFIED_REFINANCE_PAYOFF_RECEIPT_V1",
    "lien_result_domain": "UNIFIED_REFINANCE_LIEN_RESULT_V1",
    "unchanged_context_rehash_before_every_dispatch": true,
    "validator_consumer_adjacency_no_call_or_effect": true,
    "lien_action_authority": "executeLienBarrier canonical registry reads",
    "finalize_action_authority": "finalizeExecution canonical registry and commitment reads"
  },
  "current_guard_reread_entries": ["validatePreLien", "executeLienBarrier", "validatePreFinalize", "finalizeExecution"],
  "normative_execution_sizes_accepted": false,
  "normative_execution_remeasurement": "pending",
  "unproven_candidate_modules": [
    {"name": "Phase9RefinanceValidationModule", "entries": ["preflight"], "ownership": "request-preflight"},
    {"name": "Phase9RefinanceRequestModule", "entries": ["begin", "complete"], "ownership": "request-lock-completion"},
    {"name": "Phase9RefinanceLifecycleModule", "entries": ["recordFundingCommitment", "cancelRefinance", "refundCommitment"], "ownership": "funding-cancellation-refund", "measured_prototype_runtime": 19273, "measured_prototype_initcode": 19325},
    {"name": "Phase9RefinanceExecutionPrePayoffModule", "entries": ["prepareExecution"], "ownership": "replay-effect-free-prepayoff-validation", "measured_prototype_runtime": 21921, "measured_prototype_initcode": 21973, "accepted_size": false},
    {"name": "Phase9RefinanceExecutionPayoffModule", "entries": ["executePayoff"], "ownership": "guard-quote-payout-0-1-old-payoff-plan", "measured_prototype_runtime": 18396, "measured_prototype_initcode": 18448, "accepted_size": false},
    {"name": "Phase9RefinanceExecutionPostValidationModule", "entries": ["validatePreLien", "validatePreFinalize"], "ownership": "effect-free-current-phase-proof", "measured_prototype_runtime": 21829, "measured_prototype_initcode": 21881, "accepted_size": false},
    {"name": "Phase9RefinanceExecutionLienModule", "entries": ["executeLienBarrier"], "ownership": "uninterrupted-four-stage-lien-barrier", "measured_prototype_runtime": 11281, "measured_prototype_initcode": 11333, "accepted_size": false},
    {"name": "Phase9RefinanceExecutionFinalizeModule", "entries": ["finalizeExecution"], "ownership": "activation-payout-2-3-consumption-terminal", "measured_prototype_runtime": 19102, "measured_prototype_initcode": 19154, "accepted_size": false}
  ],
  "unproven_candidate_call_sites": [
    {"ordinal": 1, "wrapper": "requestRefinance", "module": "Phase9RefinanceRequestModule", "entry": "begin"},
    {"ordinal": 2, "wrapper": "requestRefinance", "module": "Phase9RefinanceValidationModule", "entry": "preflight"},
    {"ordinal": 3, "wrapper": "requestRefinance", "module": "Phase9RefinanceRequestModule", "entry": "complete"},
    {"ordinal": 4, "wrapper": "recordFundingCommitment", "module": "Phase9RefinanceLifecycleModule", "entry": "recordFundingCommitment"},
    {"ordinal": 5, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionPrePayoffModule", "entry": "prepareExecution"},
    {"ordinal": 6, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionPayoffModule", "entry": "executePayoff"},
    {"ordinal": 7, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionPostValidationModule", "entry": "validatePreLien"},
    {"ordinal": 8, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionLienModule", "entry": "executeLienBarrier"},
    {"ordinal": 9, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionPostValidationModule", "entry": "validatePreFinalize"},
    {"ordinal": 10, "wrapper": "executeRefinance", "module": "Phase9RefinanceExecutionFinalizeModule", "entry": "finalizeExecution"},
    {"ordinal": 11, "wrapper": "cancelRefinance", "module": "Phase9RefinanceLifecycleModule", "entry": "cancelRefinance"},
    {"ordinal": 12, "wrapper": "refundCommitment", "module": "Phase9RefinanceLifecycleModule", "entry": "refundCommitment"}
  ],
  "unproven_candidate_create_order": [
    {"nonce": 1, "artifact": "LienRegistry"},
    {"nonce": 2, "artifact": "CollateralCustodyV2"},
    {"nonce": 3, "artifact": "Phase9LoanAccount"},
    {"nonce": 4, "artifact": "PositionManagerV2"},
    {"nonce": 5, "artifact": "Phase9LoanFactory"},
    {"nonce": 6, "artifact": "Phase9RefinanceValidationModule"},
    {"nonce": 7, "artifact": "Phase9RefinanceRequestModule"},
    {"nonce": 8, "artifact": "Phase9RefinanceLifecycleModule"},
    {"nonce": 9, "artifact": "Phase9RefinanceExecutionPrePayoffModule"},
    {"nonce": 10, "artifact": "Phase9RefinanceExecutionPayoffModule"},
    {"nonce": 11, "artifact": "Phase9RefinanceExecutionPostValidationModule"},
    {"nonce": 12, "artifact": "Phase9RefinanceExecutionLienModule"},
    {"nonce": 13, "artifact": "Phase9RefinanceExecutionFinalizeModule"},
    {"nonce": 14, "artifact": "PayoffQuoteEngine"},
    {"nonce": 15, "artifact": "RefinanceCoordinator", "address": "0x381445710b5e73d34aF196c53A3D5cDa58EDBf7A"}
  ],
  "unproven_candidate_final_nonce": 16,
  "unproven_candidate_coordinator": {"address": "0x381445710b5e73d34aF196c53A3D5cDa58EDBf7A", "measured_prototype_runtime": 8126, "measured_prototype_initcode": 8557, "accepted_size": false},
  "replacement_topology": "pending reproducible normative measurement/repartition and successor ADR",
  "measurement_source_character_length": 249694,
  "measurement_source_sha256": "088bc586a7c34e9cf96f3df714e10c1d31ba2d4b060254ed5beb0171e860f0b3",
  "measurement_source_scope": "in-memory stripped-lifecycle/six-call-topology prototype; not normative production semantics or accepted artifact"
}
```
<!-- phase9-refinance-phase-ticket-manifest:end -->

### 10. Activation remains closed

This ADR accepts only the corrected semantic measurement requirements and records the
unproven candidate. It changes no production
Solidity, ABI, deployment artifact, expected hash, backlog status, checkpoint, method
activation manifest, control hash, or security verdict. `UNI-REFI-001`,
`UNI-REFI-002`, D1 through D4, and `P9-REFI-001` remain closed until one reviewed
successor topology matches the semantic gates in this manifest, compiles all artifacts
together within every budget, updates tooling and evidence for its independently frozen
CREATE order, and passes the complete ADR 0025 failure-injection and semantic suite.

## Consequences

- ADR 0026's five-library/eight-call/twelve-CREATE graph is historical.
- The measured eight-library, 12-call, 15-CREATE candidate remains non-accepted because its
  sizes predate the exact fresh current-context receipt and independently authoritative
  lien/finalize checks.
- No replacement library/call/CREATE count is selected pending reproducible
  remeasurement or repartition.
- In this unproven candidate, validation is repeated at fresh phase boundaries without
  duplicating its non-action checks into effect modules.
- The 64-byte proof reduces transaction-local transport while preserving commitment to
  the typed 448-byte ticket. It does not establish deployability: the normative shared-
  validator size is unmeasured and must be recompiled with every corrected check.
- More linked identities and phase boundaries increase deployment evidence and
  mutation-test scope; they do not weaken atomicity because all calls remain one
  top-level coordinator transaction.

## Verification

Any successor topology acceptance SHALL pin the complete semantic manifest, payload
offsets and length equation,
18-word guard, pre-payoff ticket, unchanged execution plan, payoff receipt, both facts
domains, both ticket domains, 14-word ticket preimage, two-word proof, lien result,
unchanged-byte transcript, its independently measured exact library/call/CREATE order,
sizes, nonces, coordinator address, opcode isolation, dependency write set, callback
closure, cross-refinance closure, and rollback at every injected failure point.
