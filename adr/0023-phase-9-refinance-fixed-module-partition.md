# ADR 0023: Phase 9 Refinance Fixed-Module Partition

Status: accepted for synthetic-local candidate architecture; implementation activation pending

Date: 2026-07-26

Owner: Protocol Architecture Authority

Work item: `UNI-ADR-018`

## Context

ADR 0021 fixes the complete atomic-refinance authority and activation boundary. ADR
0022 fixes the factory, account, position, custody, and lien bootstrap semantics. The
first D1 coordinator implementation has exposed a hard deployment blocker: with the
frozen Solidity `0.8.36`, Prague EVM, optimizer enabled at 200 runs, and non-via-IR
settings, the partially implemented `RefinanceCoordinator` runtime is 24,559 bytes.
That leaves 17 bytes below the EIP-170 limit of 24,576 bytes before the required D1
security corrections and before the four D2-D4 lifecycle mutators are implemented.

The first two-library candidate then moved the corrected D1 request path into one
request module whose optimized runtime measured 31,501 bytes, 6,925 bytes over
EIP-170. The flat three-library candidate accepted below currently measures 22,275
bytes for validation, 24,052 bytes for request, 528 bytes for lifecycle, and 5,336
bytes for the coordinator under the pinned settings. Those measurements justify the
candidate partition only; they do not activate an implementation checkpoint.

Changing to via IR would change the frozen compiler settings and every affected
artifact. Appending the required behavior to the coordinator is not viable. A proxy,
facet router, mutable module registry, or caller-selected delegate target would add a
new authority and violate the Phase 9 ABI, storage, constructor, and threat-model
boundaries. A narrowly fixed compiler-linked library partition can reduce the
coordinator runtime without adding any runtime-selected authority, but the current
tooling and deployment evidence do not yet attest linked libraries.

This ADR accepts only that candidate partition and its additional gates for synthetic-
local implementation. It does not activate any method, satisfy a Phase 9
implementation checkpoint, approve a deployment, or weaken ADR 0021 or ADR 0022. Any
conflict must be resolved before implementation activation.

## Decision

### 1. Exact same-source-file partition

The existing
`protocol/src/resolution/RefinanceCoordinator.sol` source file will contain exactly
these three source-scope libraries in addition to the protocol-facing contract:

1. `Phase9RefinanceValidationModule`
2. `Phase9RefinanceRequestModule`
3. `Phase9RefinanceLifecycleModule`

No additional production Solidity source file is authorized. All three modules are
`library` declarations in that same source file. Only their exact public library
functions are compiler-linked. Internal functions inline into the module that owns
them, not into `RefinanceCoordinator`. There is no fourth linked library.

`RefinanceCoordinator` remains the sole protocol-facing contract and the sole owner
of all persistent refinance storage and settlement-token custody. It retains:

- the exact frozen constructor signature, argument order, assignments, and storage
  declarations;
- every exact external protocol ABI selector as a fixed wrapper;
- all frozen read views; and
- all protocol events, errors, caller authority, and state-machine behavior already
  authorized by ADR 0021 and ADR 0022.

The `requestRefinance` wrapper performs exactly this fixed orchestration with the same
calldata request and no caller-supplied module value or plan:

1. `Phase9RefinanceRequestModule.begin(layout, request)` performs pure wire and caller
   validation, proves the next nonce, and stores only the active old-loan lock;
2. `Phase9RefinanceValidationModule.preflight(context, request)` performs all bounded
   pre-effect dependency reads and returns one opaque bounded `bytes` plan; and
3. `Phase9RefinanceRequestModule.complete(layout, request, plan)` revalidates the plan
   binding, performs bootstrap, quote, and replacement creation in the ADR 0021 order,
   performs every required post-effect validation, stores the accepted record and
   request operation marker, and emits the request evidence.

The four lifecycle wrappers each obtain the slot-zero layout pointer and call their
one corresponding `Phase9RefinanceLifecycleModule` entry. The coordinator therefore
contains exactly seven compiler-generated fixed-library call sites: two to the request
module, one to the validation module, and four to the lifecycle module. It declares no
new state variable, base contract, constructor input, protocol selector, fallback,
receive function, module address, or mutable link target.

`Phase9RefinanceRequestModule.begin` may mutate coordinator slot 9 only for the
old-loan lock. `Phase9RefinanceRequestModule.complete` may mutate slot 10 only for the
accepted refinance record and slot 15 only for the request operation marker.
Bootstrap, factory, quote, custody, and lien effects remain external calls made in the
coordinator execution context after the lock is active.

`Phase9RefinanceValidationModule.preflight` is `view`, receives no storage pointer,
and owns all pre-effect resolver, policy, bootstrap-vector, asset, absence, and
canonical-source checks that can be completed before bootstrap or quote effects. It
may receive only the exact memory context constructed by the coordinator wrapper and
the request. Before its first dependency call, preflight rejects
`context.coordinator != address(this)` with `InvalidRefinance()`. It declares no event,
makes no effect-capable external call, transfers no value, and cannot write coordinator
or module storage. Quote, installed-old-graph, and replacement postconditions that do
not exist during preflight remain in
`Phase9RefinanceRequestModule.complete`.

The preflight plan is an internal memory transport, not protocol authority. Its exact
candidate schema is versioned and bounded to 22,272 encoded bytes. It commits to its
domain, chain ID, coordinator,
request hash, active-lock encoding, dependency addresses, policy/configuration hashes,
and the complete capped collateral, bootstrap, and replacement vectors. The wrapper
accepts no external plan and enforces the exact maximum-length rule before forwarding
it. `complete` recomputes every plan/request/context/lock binding before the first
effect.

`Phase9RefinanceLifecycleModule` owns the complete implementations of:

- `recordFundingCommitment(FundingCommitment)`;
- `executeRefinance(bytes32,bytes32)`;
- `cancelRefinance(bytes32,bytes32)`; and
- `refundCommitment(bytes32,bytes32)`.

It also owns lifecycle-only and lifecycle-shared validation, replay/result/evidence,
payout, lien-handoff, replacement-activation, and lifecycle-event helpers. It may use
only frozen coordinator slots 9 through 15 according to the ADR 0021 state machine:
lock ownership and release in slot 9; refinance state, counters, and hashes in slot 10;
commitment order in slot 11; commitment records and statuses in slot 12; attributed
escrow in slot 13; terminal results in slot 14; and processed operation identities in
slot 15.

No library owns persistent storage. No library may declare a state variable or
use a library-local, diamond, EIP-7201, hashed, or otherwise unstructured storage
namespace. Only the request and lifecycle modules receive the coordinator storage
pointer supplied by their wrappers. The validation module is storage-blind.

### 2. Fixed compiler-linked delegatecall exception

The only proposed delegatecall exception is the seven Solidity compiler-generated
calls from the coordinator wrappers to the three library addresses embedded in the
coordinator bytecode at compile/link time. The addresses are fixed before deployment,
are independently deployed and hash-verified, have no setter, and cannot be selected
from calldata, policy, governance state, a registry, storage, or another contract.

This exception is not authority for a proxy, facet or diamond, fallback router,
upgrade beacon, plugin, arbitrary implementation, mutable module registry, late link,
post-deployment rebinding, caller-supplied target, low-level delegatecall, assembly
delegatecall, or delegatecall to a policy, provider, adapter, token, resolver, bridge,
or other third-party code. The coordinator and all three modules must contain no
`delegatecall` opcode except the exact seven compiler-generated fixed-library call
sites in the coordinator. No module may contain a compiler link reference or delegate
again. No target may be replaceable at the same address in the accepted local
deployment.

Delegate execution must preserve coordinator semantics: `address(this)` is the
coordinator, the original external caller remains `msg.sender`, events are emitted by
the coordinator address, external calls originate from the coordinator, and all value
and state remain subject to one transaction-wide rollback. The modules may neither
hold coordinator funds nor become an alternative protocol entry point.

The fixed coordinator-to-library dispatch is an internal code-partition mechanism,
not a resolver, token, registry, provider, policy, or other effect-capable dependency
interaction. `begin` performs no external dependency call before storing the old-loan
lock. After `begin` returns, preflight and every later dependency interaction execute
with that lock active. A revert from preflight or complete rolls the lock back with the
complete transaction.

### 3. Slot-zero storage-layout mirror

The source will define one storage-only access struct with the exact name
`Phase9RefinanceStorageLayout`. A coordinator helper returns its storage pointer with
the equivalent of `assembly { layout.slot := 0 }`. The struct is an access type over
the coordinator's existing slots, not a second allocation, namespace, storage
declaration, or migration.

Every logical mirror field has offset zero. To make that slot mapping explicit and
physically invariant under Solidity struct packing, each 20-byte `address` or `IERC20`
logical field in slots 0 through 8 is immediately followed by its exact 12-byte
`uint96` padding member at offset 20 in the same slot. The declaration order, names,
types, slots, and offsets are frozen as follows:

| Slot | Logical mirror field at offset 0 | Required padding field at offset 20 |
| ---: | --- | --- |
| 0 | `address loanRegistry` | `uint96 loanRegistryPadding` |
| 1 | `address phase9LoanFactory` | `uint96 phase9LoanFactoryPadding` |
| 2 | `address payoffQuoteEngine` | `uint96 payoffQuoteEnginePadding` |
| 3 | `address lienRegistry` | `uint96 lienRegistryPadding` |
| 4 | `address assetRegistry` | `uint96 assetRegistryPadding` |
| 5 | `address policyRegistry` | `uint96 policyRegistryPadding` |
| 6 | `address emergencyController` | `uint96 emergencyControllerPadding` |
| 7 | `address treasuryFeeRecipient` | `uint96 treasuryFeeRecipientPadding` |
| 8 | `IERC20 settlementToken` | `uint96 settlementTokenPadding` |
| 9 | `mapping(bytes32 oldLoanId => uint64 nonce) nextRefinanceNonce` | none |
| 10 | `mapping(bytes32 refinanceId => Phase9Types.RefinanceRecord record) refinances` | none |
| 11 | `mapping(bytes32 refinanceId => bytes32[] commitmentIds_) commitmentIds` | none |
| 12 | `mapping(bytes32 commitmentId => Phase9Types.FundingCommitment commitment) commitments` | none |
| 13 | `mapping(bytes32 refinanceId => uint256 units) escrowedUnits` | none |
| 14 | `mapping(bytes32 refinanceId => Phase9Types.RefinanceTerminalResult result) terminalResults` | none |
| 15 | `mapping(bytes32 operationId => bool processed) processedOperationIds` | none |

All nine padding fields are access-struct declarations over bytes that are unused by
the coordinator's logical dependency values. They must remain zero for the complete
lifetime of the deployment and must never be read, written, exposed, hashed as a
protocol fact, used for authorization, or referenced by any module. They do not
authorize a new state field or storage use. A nonzero padding value is an invariant
failure and rejects the deployment or execution evidence under review.

A static compatibility check must prove all 16 logical mirror fields and all nine
padding fields: their exact names, types, declaration order, slots, and offsets. It
must prove that the logical fields equal
`protocol/storage-layout/phase9/RefinanceCoordinator.storage.json`, that every padding
field is `uint96` at offset 20 in its corresponding slot 0 through 8, and that no code
reads or writes a padding field. It must also prove that the coordinator's original
private declarations still occupy those exact logical slots, that the unused bytes
remain zero, that all three libraries have empty compiler storage layouts, that the
validation module accepts no storage pointer, and that only the request and lifecycle
modules use the slot-zero mirror. A mismatch is an activation failure, not a
regeneratable expected change.

### 4. Unified quote and refinance policy authority

The synthetic-local deployment MUST use one composite policy registry for both
internal resolver surfaces authorized by ADR 0020 and ADR 0021. The exact deployed
address is identical in:

- `Phase9LoanFactory._quotePolicyRegistry`;
- `Phase9LoanFactory._refinancePolicyRegistry`;
- `PayoffQuoteEngine._quotePolicyRegistry`; and
- `RefinanceCoordinator._policyRegistry`.

The one composite source implements both `resolvePayoffQuotePolicy(bytes32,address)`
and the three `IPhase9RefinancePolicySource` selectors. This equality is a deployment
and runtime invariant, not an inference from matching return data. It adds no getter,
storage field, constructor argument, selector, or mutable registry choice.

During request validation, the validation module calls `resolvePayoffQuotePolicy` on
the coordinator-bound policy registry for the exact old loan and account. It bounded-
decodes the flat seven-word result, revalidates every ADR 0020 field, requires quote-
policy `maximumValidity == refinance-policy maximumValidity`, and independently
reconstructs the exact `UNIFIED_PAYOFF_POLICY_V1` hash using that shared registry.
Successful quote issuance independently proves that the payoff engine's constructor-
bound maximum validity equals the same value. The deployment verifier proves the four
registry bindings and the engine constructor maximum from canonical storage/input
evidence. Separate quote/refinance registry addresses or validity values are invalid
for this slice.

This convention closes a fact otherwise unavailable through the frozen coordinator
ABI: the payoff policy hash preimage contains the quote-policy registry, maximum
validity, and fee/penalty beneficiary. Treating an opaque nonzero engine-returned hash
as self-authenticating is not sufficient.

High-level Solidity calls cannot establish a strict malicious-returndata byte bound,
because they copy or decode returndata before a later length check. The validation
module therefore has exactly one inline-assembly exception: one private view helper
named `_boundedStaticcall` containing one `assembly ("memory-safe")` block. That block
may issue only `STATICCALL`, read `RETURNDATASIZE`, reject a
selector-and-outcome-specific oversize result before copying, allocate ordinary
memory, and copy only in-cap successful or failed returndata with `RETURNDATACOPY`.
Copied dependency failure data is used only for local classification and is never
bubbled. The block may use only the memory and arithmetic operations needed for that
sequence. It may not execute or contain `CALL`, `CALLCODE`, `DELEGATECALL`, `SLOAD`,
`SSTORE`, `CREATE`, `CREATE2`, `SELFDESTRUCT`, or a log opcode; inspect or modify
storage; forward value; choose a target or selector from caller-controlled protocol
calldata; or return an uncapped byte array.

The sole dependency failure that may prove a semantic fact is the lien-absence check.
For `ILienRegistry.lien(collateralId)`, `_boundedStaticcall` uses an exact 36-byte
failure-data cap. Absence is accepted only when `!ok`, the returndata length is exactly
36, and the returndata is byte-for-byte equal to
`abi.encodeWithSelector(ILienRegistry.UnknownLien.selector, collateralId)`. Any
successful response rejects absence; a complete lien record is validated on the
separate existing-collateral read path. An empty, short, long, alternate-selector,
alternate-collateral, malformed, or otherwise different failure is not absence. Every
other failed dependency call, and every lien failure not matching that exact tuple,
is normalized to `InvalidRefinance()` after bounded inspection. No dependency revert
bytes are bubbled.

Every resolver has an exact maximum encoded return length derived from the ADR caps.
The validation module decodes only after `_boundedStaticcall` returns an in-bound
result. The coordinator wrapper catches any validation-module revert, including an
ABI-decoding panic, and normalizes it to `InvalidRefinance()`. It does not catch the
request-module completion call, so the exact factory, account, and manager errors that
ADR 0022 requires remain observable.

### 5. ABI, constructor, and storage compatibility

The fully linked coordinator must preserve the accepted historical coordinator ABI,
including every tuple shape, selector, return type, mutability, event, error, and the
only additive items separately authorized by ADR 0021. Library entry points belong to
separate library artifacts and must not appear in the protocol coordinator interface
or be accepted as new protocol authority.

The coordinator constructor remains exactly the frozen nine-argument constructor. The
three library addresses are link references in creation bytecode, not constructor
arguments or storage fields. Constructor ABI and behavior, linearized bases, storage
layout, and frozen read behavior must remain structurally identical. The linked
coordinator runtime must have no unresolved placeholder and must embed only the three
attested module addresses at the compiler-reported seven call-site link offsets. No
module artifact may contain a link reference.

### 6. Compiler, linking, hash, and size gates

Every candidate must use the already pinned toolchain exactly:

- Solidity `0.8.36+commit.8a079791.Emscripten.clang`;
- OpenZeppelin Contracts `5.6.1`;
- Prague EVM;
- optimizer enabled with 200 runs; and
- `viaIR: false`.

No per-contract setting, via-IR exception, metadata variation, manual bytecode patch,
unreviewed linker, or compiler substitution is allowed. Reproducible evidence must pin
the standard JSON compiler input and output, source hashes, compiler settings hash,
unlinked coordinator creation and runtime bytecode, exact link references and byte
offsets, each module's creation bytecode and compiler template runtime before the
Solidity deploy-address self-patch, its predicted and actual deployment address, the
exact self-patch offset, its address-patched runtime and address-dependent runtime code
hash, the fully linked coordinator creation and runtime bytecode, constructor
arguments, final creation-transaction input, and deployed runtime code hash. A module
runtime template hash is not a deployed module code hash.

The checker must reproduce the link from the unlinked artifact and the three predicted
module addresses and byte-compare it with the broadcast input. It must reject a
missing, extra, overlapping, repeated-at-an-undeclared-offset, zero, swapped, or
incorrect link; an unresolved placeholder; a changed module or coordinator hash; and
any artifact produced under different settings.

Each deployed runtime, including each module and the linked coordinator, must be no
larger than the EIP-170 limit of 24,576 bytes. Each creation transaction must also
satisfy the active EIP-3860 initcode limit. The gate records exact byte counts and
rejects boundary waivers. The final coordinator must retain reviewed headroom for the
complete D1-D4 implementation; merely compiling one incomplete slice below EIP-170 is
not evidence of completion.

The checker also records the exact maximum preflight-plan byte length and the measured
gas for maximum-cap plan construction, return, coordinator forwarding, completion
decode, success, normalized dependency failure, and full rollback. The opaque plan
must not cause the coordinator, request module, validation module, or lifecycle module
to exceed EIP-170, the applicable initcode limit, the reviewed local block-gas budget,
or compiler stack limits under the pinned non-via-IR settings.

### 7. Revised ten-CREATE deployment order

The dedicated synthetic-local request deployer or broadcaster starts at contract
nonce 1 and performs exactly these top-level sequential `CREATE` operations:

1. nonce 1: `LienRegistry(predictedCoordinator)`;
2. nonce 2: `CollateralCustodyV2(assetRegistry, lienRegistry, emergencyController)`;
3. nonce 3: `Phase9LoanAccount` implementation;
4. nonce 4: `PositionManagerV2` implementation;
5. nonce 5: `Phase9LoanFactory(...)`;
6. nonce 6: `Phase9RefinanceValidationModule`;
7. nonce 7: `Phase9RefinanceRequestModule`;
8. nonce 8: `Phase9RefinanceLifecycleModule`;
9. nonce 9: `PayoffQuoteEngine(..., predictedCoordinator)`; and
10. nonce 10: the fully linked `RefinanceCoordinator(...)`.

The payoff engine remains immediately before the coordinator. The coordinator address
is predicted from nonce 10, encoded as the single RLP nonce byte `0x0a`:

```solidity
address predictedCoordinator = address(
    uint160(
        uint256(
            keccak256(
                abi.encodePacked(hex"d694", deployerOrBroadcaster, hex"0a")
            )
        )
    )
);
```

Before broadcast, coordinator creation bytecode is dynamically linked to the exact
predicted nonce-6, nonce-7, and nonce-8 module addresses using the compiler-reported
seven link-reference call sites and the attested linker, then byte-compared with the nonce-10 creation
input. An ordinary build-time-linked `new RefinanceCoordinator` is not deployment
evidence for this sequence, and the broadcaster does not patch runtime bytecode. The
lien registry and payoff engine constructor bindings use the nonce-10 coordinator
prediction. Evidence must prove every nonce, prediction, actual address, address-
patched module code hash, constructor argument, link offset, fully linked bytecode,
zero transaction value, successful receipt, and reciprocal authorization at the
accepted block hash.

After all ten creations, and outside the CREATE sequence, the same declared
governance broadcaster performs exactly one zero-value
`RoleManager.grantRole(LOAN_FACTORY_ROLE, phase9Factory,
type(uint64).max)` transaction. No other role, policy, setup, repair, or business action
may intervene. Per-loan factory clones remain the separately authorized deterministic
`CREATE2` operations and do not alter this top-level sequence.

### 8. Verifier and implementation-checkpoint changes

The Phase 9 compatibility and checkpoint tools must learn linked-library evidence
before this architecture can be accepted. They must:

- recognize the four compiler artifacts/definitions from the one source path without
  permitting an undeclared source, definition, or artifact;
- retain the existing coordinator ABI and storage snapshots as authoritative;
- prove the 16 logical mirror fields and nine explicit padding fields through AST
  packing analysis or an exact compile-only probe, prove every padding field remains
  zero and unused, prove all three libraries are storage-free, and prove the validation
  module has no storage-pointer parameter;
- forbid inline assembly and raw `sload`/`sstore` in all modules except the exact
  AST-pinned validation `_boundedStaticcall` memory-safe block authorized in Section 4;
  the only other assembly exception is the AST-pinned coordinator helper assignment
  `layout.slot := 0`;
- inventory public library entry points from the AST and compiler method identifiers
  separately, because storage-pointer entries are absent from the ordinary library
  ABI, and reject their appearance in the protocol interface;
- parse and freeze the exact seven coordinator link-reference call sites, offsets,
  unlinked bytecode hashes, three module hashes, fully linked hashes, opaque-plan cap,
  maximum-cap gas measurements, and exact deployed byte counts;
- reject all delegatecall opcodes other than the exact compiler-attributed seven
  coordinator call sites and reject every link reference and delegatecall opcode in
  every module;
- replace the seven-CREATE request harness and nonce-7 prediction with the exact
  ten-CREATE sequence and nonce-10 (`0x0a`) prediction;
- verify all three link targets, final coordinator bytecode, constructor bindings, role
  grant, and block-hash-pinned deployed code; and
- make generated-artifact freshness, ABI compatibility, structural storage
  compatibility, method activation, deployment evidence, and the complete `P9R-*`
  traceability map pass against one reviewed commit.

An implementation checkpoint may not be marked `PASS`, a backlog row may not become
`DONE`, and generated checkpoint artifacts may not be accepted merely because the
tooling ignores or strips link references. The verifier changes and the protocol
changes require independent architecture, security, and tooling review.

### 9. Direct-call, hostile-host, reentrancy, and rollback obligations

Tests must call every public module entry point directly through its deployed library
address. Direct calls to the mutating request and lifecycle entries must revert under
the Solidity library call guard. A direct call to the view validation entry may return
or revert, but must not read coordinator storage, consume a coordinator lock or
operation ID, alter a commitment or terminal result, emit a coordinator transition,
transfer coordinator funds, call a coordinator-bound dependency, or create an
alternative successful protocol path. A direct-call result must not depend on storage
crafted at the library address.

Tests must also prove that compiler-linked delegate execution preserves the original
caller and coordinator address, and that authorization against the canonical
dependencies cannot be satisfied by calling a module directly or through an attacker-
controlled delegatecall host. The Solidity direct-call guard does not and cannot
prevent an arbitrary hostile contract from delegatecalling public library bytecode
against the hostile contract's own storage and mock dependencies. The required safety
property is that such reuse cannot read or mutate coordinator storage, move
coordinator funds, satisfy coordinator-address checks at the canonical factory,
custody, lien, or quote dependencies, or emit an event from the coordinator address.
An event or storage write at the hostile host is not protocol state or a protocol
event. Module bytecode must not treat its deployment address, balance, or library-local
storage as coordinator authority.

Tests must prove the exact seven-call coordinator orchestration, that `begin` receives
the external request unchanged, that no resolver or effect-capable dependency is
called before its lock write, that preflight receives only coordinator-constructed
context, and that `complete` receives only the same request and the immediately
returned bounded plan. No protocol calldata may select a module, library entry,
storage pointer, plan, link target, or downstream calldata target.

Adversarial reentrancy tests must cover callbacks at every externally interacting
request and lifecycle stage, including token transfer and balance reads, resolver and
emergency checks, bootstrap, custody, lien, quote, factory, account, position-manager,
payout, handoff, and replacement activation. Cross-method reentry through each
coordinator wrapper, repeated commitment/refund attempts, and reentry from every
configured beneficiary must prove the exact ADR 0021 lock, operation-ID, state-version,
commitment-status, attributed-escrow, and checks-effects-interactions behavior. The
partition may not add a new reentrancy storage slot or weaken the rule that the request
old-loan lock is written before the first external effect.

Failure-injection tests must revert at every external call boundary and after every
material state transition. They must prove transaction-wide rollback across the
coordinator, all three modules' delegate execution, factory/clones, loan registry, custody,
lien registry, quote engine, token balances and allowances, account/position state,
events, locks, commitments, escrow, terminal results, operation IDs, and replacement
activation. A module boundary, caught error, or normalized dependency failure must
not preserve a partial effect.

### 10. D1 audit closure is a prerequisite

The fixed-module partition addresses code size only. Before even the D1 request method
can be activated, one reviewed implementation and its tests must close every current
D1 audit finding:

1. decode the exact flat refinance-policy and bootstrap resolver return tuples rather
   than decoding them as one dynamic struct;
2. require the replacement configuration's policy-set hash to equal the policy's
   accepted new policy-set hash;
3. bootstrap only an absent old loan and validate an already canonical replacement
   loan so it may later be refinanced again;
4. use principal plus accrued interest as the lender position claim while preserving
   fees, penalties, costs, and credits in their distinct payoff route;
5. require the old and replacement accounts to bind the same custody contract;
6. use the unified registry convention in section 4 to resolve and independently
   reconstruct the exact payoff policy hash, then validate the complete quote,
   including debt version, gross and credit decomposition, settlement route, all
   components, codes, beneficiaries, issuance facts, quote identity, and the
   recomputed component hash;
7. reject a terminal old loan and a non-absent replacement graph before any external
   bootstrap or quote effect;
8. preflight the complete ordered collateral vector before the first custody or lien
   call; and
9. normalize malformed, reverting, and inconsistent dependency responses to the exact
   authorized coordinator error behavior while retaining errors that ADR 0022
   explicitly requires from the factory, account, and manager.

Closure requires focused, golden, fuzz, invariant, adversarial, compatibility, size,
and deployment tests. Moving defective code into a module, passing compilation, or
recovering EIP-170 headroom does not close a finding.

## Consequences

- The coordinator can remain the single ABI, storage, authority, event, and fund-
  custody surface while the complete D1-D4 implementation is partitioned across three
  immutable, compiler-linked code modules.
- The source set does not gain a new production file, but the build, checkpoint, and
  deployment systems gain three deployed artifacts, seven explicit link-reference
  call sites, three top-level CREATE operations, and additional hash and opcode
  obligations.
- The design introduces delegatecall risk. Its safety depends on exact immutable link
  targets, an exact slot-zero mirror, storage-free modules, complete direct-call and
  reentrancy testing, and tooling that fails closed on any drift.
- A defect in the request or lifecycle module executes with coordinator storage and
  token authority and can corrupt any slot; a validation defect can return a false
  plan. Code ownership conventions are therefore insufficient without static and
  adversarial enforcement.
- The nonce-10 coordinator prediction becomes part of the reciprocal lien and payoff
  bindings; any transaction-order or linker change invalidates the complete evidence
  package and requires a bounded local reset.
- No real funds, production key, public network, external provider, bridge, mainnet
  deployment, or production approval is authorized.

## Architecture review and activation gate

The architecture review accepted the fixed-link exception only after independently
confirming the padded slot mirror and linked-call feasibility and adding the unified
policy authority, hostile-host scope, deployment-address self-patch, method-identifier,
assembly, and dynamic-linking gates above. This acceptance permits candidate code and
tooling work only.

The seven-CREATE harness remains historical candidate code, and the prior nine-CREATE
candidate model is superseded. The ten-CREATE sequence
is the required candidate deployment model but is not an approved deployment until
one reviewed commit proves every gate above. All unresolved D1 findings remain release
blockers, and no D1-D4 refinance method, deployment, backlog item, or implementation
checkpoint may be treated as activated before the implementation, independent
architecture/security/tooling reviews, and complete evidence package pass together.
