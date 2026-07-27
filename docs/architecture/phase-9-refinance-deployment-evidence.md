# Phase 9 Refinance Deployment Evidence

Status: normative evidence boundary; no accepted deployment exists

Date: 2026-07-27

## Purpose and relationship to payoff evidence

This document defines the deployment evidence required before the ADRs 0021 and 0022
refinance method bundle can be activated. ADR 0023's candidate-only fixed-module
partition and ADR 0026's intermediate repartition are historical. ADR 0027 freezes
security-approved semantics, records a size-unproven successor candidate, and defines
mandatory measurement gates; no
future deployment topology is selected. This document
does not authorize a deployment or claim that a complete conforming candidate,
verifier, manifest, or accepted evidence file exists. ADR 0023 permits architecture and
tooling work only; none of its library, linking, or deployment evidence activates a
method or checkpoint by itself.

The nested payoff pair-deployer evidence remains valid for the already accepted
payoff-only checkpoint. It is historical evidence and is not rewritten. This revision
permits only a preliminary, non-activating topology checkpoint for the larger refinance
graph. ADR 0024 now selects explicit nonce preconditioning and freezes complete
topology verification before one distinct governance-executor factory-role grant. The
current topology harness remains preliminary because it deliberately stops before that
grant and emits only non-activating evidence. It also implements the superseded
ten-CREATE graph and therefore cannot become activation-grade evidence by adding a
role grant or changing an evidence label.

The accepted `P9-PAYOFF-001` checkpoint anchors that historical tool and evidence to its
reviewed Git blobs; the current foundation instead uses the linked-module gate and the
live ten-CREATE refinance verifier, and does not run the legacy payoff pin check.
That verifier remains historical control evidence until it is replaced; passing it is
not evidence for ADR 0027.

The deployment remains disposable synthetic-local evidence only and local-only
by design. It provides no business-logic activation and has no production,
public-network, live-fund, external-provider, or mainnet authority.

## ADR 0027 migration hold and size-unproven candidate graph

No accepted ADR-0027 deployment tool or artifact exists. Production Solidity, the
deployment script, plan schema, smoke harness, verifier fixtures, expected hashes, and
current candidate files deliberately remain unchanged in this specification-control
slice. The ten-CREATE evidence described in the historical sections below is retained
only to bind the measurement and reset history and cannot satisfy a `P9R-DEPLOY-*` row.

The non-accepted ADR 0027 measurement candidate would have generated exactly 15
consecutive zero-value top-level `CREATE` transactions at broadcaster nonces 1 through
15:

1. `LienRegistry`;
2. `CollateralCustodyV2`;
3. `Phase9LoanAccount` implementation;
4. `PositionManagerV2` implementation;
5. `Phase9LoanFactory`;
6. `Phase9RefinanceValidationModule`;
7. `Phase9RefinanceRequestModule`;
8. `Phase9RefinanceLifecycleModule`;
9. `Phase9RefinanceExecutionPrePayoffModule`;
10. `Phase9RefinanceExecutionPayoffModule`;
11. `Phase9RefinanceExecutionPostValidationModule`;
12. `Phase9RefinanceExecutionLienModule`;
13. `Phase9RefinanceExecutionFinalizeModule`;
14. `PayoffQuoteEngine`; and
15. the fully linked `RefinanceCoordinator`.

That non-accepted coordinator candidate has exactly 12 compiler-generated fixed-library
call sites across eight same-file, storage-free, non-linking modules. Its prediction uses RLP nonce
byte `0x0f`; from canonical broadcaster
`0x70997970c51812dc3a010c7d01b50e0d17dc79c8` it is
`0x381445710b5e73d34aF196c53A3D5cDa58EDBf7A` and would end at nonce 16 (`0x10`).
Those nonces and addresses are unproven-candidate measurement evidence only. The
mandatory exact fresh current-context receipt and independently authoritative lien/finalize
checks were absent from the measured modules, so neither the graph nor any execution-
module size is activation-grade. A successor ADR
must independently freeze and reproduce its library/call/CREATE order, nonce/address
predictions, all link replacements, exact ADR 0027 payload/proof semantics, execution-
module budget, EIP-170, and EIP-3860 evidence.

ADR 0024 continues to govern the exact candidate identity, explicit nonce precondition,
verification-before-grant order, one governance-executor factory-role grant, post-grant
evidence, and reset. References below to ten, twelve, or fifteen creations; three, five,
or eight modules; seven, eight, or twelve links; nonce-9, nonce-11, or nonce-14 engine;
nonce-10, nonce-12, or nonce-15 coordinator; or final nonce `0xb`, `0x0d`, or `0x10`
describe only superseded or non-accepted candidates and are not operative requirements.

## Historical ADR 0023 candidate topology record — non-operative

Every imperative in this section records the superseded ADR 0023 candidate verifier.
It is historical evidence only and is not an ADR 0027 deployment requirement.

The topology candidate must be broadcast from one dedicated disposable Anvil account
that has no imported or production-origin key, no real-value asset, and no authority
outside the reset-bounded local chain. Before broadcast, the harness records the raw
`eth_chainId` and `eth_getTransactionCount` requests and responses at both `latest` and
`pending`, proving the fresh account nonce is 0. It then records the exact successful
`anvil_setNonce` request that sets the account nonce to `0x1` and the immediate nonce
reads proving both views are `0x1`; both original reads must be `0x0`. This Anvil
mutation is a test precondition, not an
on-chain transaction, role assignment, or deployment authority.

Each of the ten topology artifacts is then deployed by that account through an ordinary
top-level contract-creation transaction. There are exactly ten transactions and no
following initialization or activation call. The sequence must satisfy all of the
following:

- chain ID is exactly `31337`;
- the RPC is credential-free literal loopback HTTP with an explicit port;
- every topology-plan transaction has the same fresh sender, the next consecutive nonce,
  and zero value; every creation has exact reviewed creation bytecode and exact
  constructor arguments;
- there are exactly ten top-level creations from the broadcaster EOA transaction nonce 1:
  lien registry at nonce 1, collateral custody at 2, account implementation at 3,
  position-manager implementation at 4, factory at 5, validation module at 6, request
  module at 7, lifecycle module at 8, payoff engine at 9, and fully linked coordinator
  at 10;
- the coordinator prediction is derived from nonce 10 with the single RLP nonce byte
  `0x0a`; the three module predictions use nonces 6, 7, and 8;
- the topology plan enumerates every transaction in exact ordinal order, including each
  topology artifact's source, compiler profile, creation/runtime hashes,
  predicted address, constructor ABI types, and constructor values;
- the payoff quote engine is the entry immediately before the refinance
  coordinator;
- before any broadcast, the coordinator address is predicted from the exact
  broadcaster nonce at its topology-plan ordinal;
- the lien registry and payoff engine constructors receive that predicted
  coordinator address;
- before the nonce-10 broadcast, the coordinator creation bytecode is dynamically
  linked to only the predicted validation, request, and lifecycle module addresses at
  the exact seven compiler-reported offsets; reproduced linked bytes equal the complete
  transaction input before constructor arguments;
- each module has no storage, nested link reference, or delegatecall opcode, and its
  compiler template runtime, Solidity deployment-address self-patch offset,
  address-patched deployed runtime, and address-dependent code hash are recorded;
- the linked coordinator has no unresolved placeholder and contains only the seven
  fixed compiler-generated call sites: request `begin`, validation `preflight`, request
  `complete`, and the four lifecycle entries;
- each module and the linked coordinator is at most 24,576 runtime bytes and each
  creation satisfies the active initcode limit under Solidity 0.8.36, Prague,
  optimizer 200, and non-via-IR settings;
- the coordinator constructor receives the actual immediately preceding engine
  and every exact already-created dependency;
- after the nonce-10 coordinator receipt, raw `eth_getTransactionCount` reads at
  `latest` and `pending` both return nonce `0xb`;
- every other reciprocal binding or factory implementation address is predicted
  and verified in the same topology plan before broadcast; and
- there is no top-level pair deployer, `CREATE2`, proxy, setter, rebinding,
  mutable implementation selector, late open-authorization window, arbitrary call,
  role grant, role-admin change, policy/setup/repair call, loan registration,
  bootstrap, quote, refinance, funding, or other business-action transaction.

The topology candidate stops after nonce 10. It cannot grant the factory role, enable a
successful protocol flow, set `activation_accepted=true`, satisfy a `P9R-DEPLOY-*` row,
or create a `P9-REFI-001` checkpoint. ADR 0024 selects this explicit nonce-preconditioned
form for later activation-grade evidence and binds the final role order, but the
candidate checkpoint does not implement or evidence its positive grant.

## Historical ADR 0024 activation-grade extension — non-operative topology

The identity separation, authority grant, verification-before-grant, and reset controls
remain operative through ADR 0027. The ten-CREATE topology referenced in this section
is historical and must not be read as an imperative for a new candidate.

Activation-grade evidence must preserve the candidate sequence above and add no
transaction until its independent topology verification passes. The prerequisite
`RoleManager` is deployed separately with pairwise-distinct setup administrator and
governance executor identities. Its constructor grants only `DEFAULT_ADMIN_ROLE` to
the setup administrator and `GOVERNANCE_EXECUTOR_ROLE` to the governance executor.
The candidate broadcaster and fixture allocator are distinct from both identities and
receive no role.

The selected order is exact:

1. record the prerequisite RoleManager constructor transaction and its two constructor
   `RoleGranted` logs; no later prerequisite role or role-admin transaction is allowed;
2. observe the roleless candidate broadcaster at `latest == pending == 0x0`, apply one
   evidenced `anvil_setNonce(..., 0x1)`, and observe both views at `0x1`;
3. broadcast and independently verify the exact ten zero-value `CREATE` transactions at
   candidate nonces 1 through 10, ending at `latest == pending == 0xb`;
4. prove the nonce-5 factory has zero role expiry and no `LOAN_FACTORY_ROLE`, the
   candidate broadcaster has no administrative or governance role, and
   `roleAdmin(LOAN_FACTORY_ROLE) == GOVERNANCE_EXECUTOR_ROLE`;
5. only then allow the dedicated governance executor, observed fresh at nonce `0x0`,
   to send one zero-value transaction to the RoleManager calling
   `grantRole(LOAN_FACTORY_ROLE, phase9LoanFactory, type(uint64).max)`; and
6. at the canonical receipt block, prove the exact single event, maximum expiry,
   positive role membership, unchanged role admin, governance nonce `0x1`, no role for
   the candidate broadcaster, and no second or intervening transaction.

That grant is the last activation-topology transaction. No policy mutation, setup,
repair, bootstrap, quote, refinance, funding, execution, cancellation, refund, or other
business action is part of this evidence. The positive role evidence remains
insufficient to activate any method or checkpoint until the bundled D1-D4 gate passes.

The factory-internal deterministic minimal clones governed by ADRs 0021 and 0022 are a
separate per-loan mechanism. Their `CREATE2`-style salts do not authorize
top-level `CREATE2` or weaken this sequence.

## Per-loan clone and initialization evidence

The reviewed factory implements the standard OpenZeppelin Contracts 5.6.1 EIP-1167
creation/runtime bytes and deterministic prediction through a private helper. A literal
library dependency may not add `FailedDeployment`, `InsufficientBalance`, or another
error to the frozen factory ABI. The top-level account and position-manager
implementation instances contain the exact reviewed runtime and have their existing
`initialized` storage member set by declaration initialization; direct initialization of
either implementation fails, while a fresh minimal clone begins with zero storage.

For every bootstrap or replacement creation trace, evidence records the fresh zero input,
factory-derived canonical nonzero creation ID, factory nonce, both domain-separated salts, implementation addresses/runtime hashes,
predicted and actual clone addresses, minimal-proxy creation/runtime hashes, and code at
both clones. The trace proves the atomic order: reserve the unique creation identity,
stored request, processed flag, predicted mappings, and incremented nonce; deploy both
clones; initialize the account; initialize the manager after authenticating the factory
and reciprocal fields through the account; register and verify protocol version 9 in
`LoanRegistry`; and emit the one creation event. Failure injection at every step proves
that no nonce reservation, clone, registry entry, mapping, or event survives a revert.

An exact old canonical `creationId` replay is tested after later successful creations have advanced
the global nonce. It is classified from the stored request before the current nonce,
revalidates the active four-field creation-resolver tuple and canonical clone/registry
bindings, returns the stored pair, and produces no state-changing call, write, deployment,
initialization, registration, nonce movement, or event. Changed reuse fails with
`InvalidPhase9LoanConfiguration`; a fresh nonzero ID fails, while a zero-ID retry or other
distinct creation identity for an existing loan fails with
`Phase9LoanAlreadyExists(loanId)`. Clone, resolver, authority, nonce, prediction,
initialization, and registration failures expose no additional factory error.

The same execution evidence proves unsigned raw-`bytes32` ordering and exact inert replay
for tranche/position records, agreement-version-zero absence for a dormant account,
nonzero `LoanConfiguration` identifiers and policy/agreement commitments, and overwrite-
last same-block checkpoint coalescing. Asset evidence keeps the authority split exact:
the factory/account verify the ADR-bound synthetic-local token/runtime, while only the
coordinator calls the typed asset resolver and proves its active, decimals,
exact-balance-delta, runtime, and two-configuration equality.

## Candidate artifacts and expected implementation paths

The topology checkpoint reserves the following exact paths:

- broadcast script: `protocol/script/DeployPhase9RefinanceLocal.s.sol`;
- reset-bounded Anvil harness: `scripts/smoke-phase9-refinance-anvil.ps1`;
- independent verifier: `tools/verify_phase9_refinance_deployment.py`;
- verifier tests: `tools/tests/test_phase9_refinance_deployment.py`;
- schemas:
  `infrastructure/local/phase9-refinance-deployment-plan.schema.json`,
  `infrastructure/local/phase9-refinance-deployment-candidate.schema.json`, and
  `infrastructure/local/phase9-refinance-deployment-evidence.schema.json`; and
- canonical outputs:
  `protocol/deployments/local/phase9-refinance-deployment-plan.json`,
  `protocol/deployments/local/phase9-refinance-deployment-candidate.json`, and
  `protocol/deployments/local/phase9-refinance-deployment-evidence.json`, plus
  `protocol/broadcast/DeployPhase9RefinanceLocal.s.sol/31337/run-latest.json`.

These are normative candidate expectations only. This document does not claim that
any path exists, passes, is fresh, or contains approved evidence. Missing or
nonconforming files leave the topology checkpoint unproven.

## Pre-broadcast topology plan

The reviewed topology plan is the immutable pre-broadcast manifest. At minimum it
contains:

| Field | Required evidence |
|---|---|
| Plan identity | schema version, artifact type `PHASE9_REFINANCE_DEPLOYMENT_PLAN`, environment `local`, chain `31337`, source commit, dirty-state rejection, generated-at, and canonical plan digest |
| Broadcaster and nonce precondition | exact freshly spawned Foundry-default Anvil account 1 (`0x70997970c51812dc3a010c7d01b50e0d17dc79c8`), exact ordered default account-set digest, account index/profile and recorded unlocked/no-private-key-input harness provenance, observed raw before/preconditioned `latest` and `pending` nonce evidence for `0x0`/`0x1`, expected final nonce `0xb`, exact `anvil_setNonce` request and response, and no prior or pending transaction; the standalone verifier rejects every other broadcaster or account profile, while the profile and digest identify the fixture but do not independently prove signer origin |
| RPC boundary | harness-enforced canonical literal loopback URL, no credentials/path/query/fragment/proxy, expected chain ID, pinned Anvil client identity, block-zero reset identity, and pre-broadcast canonical block |
| Compiler boundary | harness-enforced Solidity/Foundry versions plus plan-bound optimizer settings, EVM version, remappings, artifact paths, compiler source-set hashes, all four same-source coordinator/module compiler artifacts, exact creation/runtime bytecode hashes, module runtime self-patch offsets, and runtime/initcode byte counts |
| Ordered transactions | exactly ten rows for top-level `CREATE` nonces 1 through 10 and no other broadcaster transaction; exact ordinal, sender nonce, predicted address, artifact, constructor ABI encoding, zero value, input hash, and expected runtime hash |
| Fixed links | predicted nonce-6/7/8 module addresses, exact seven creation/runtime link-reference offsets, unlinked hashes, fully linked coordinator hashes, no unresolved placeholder, and byte equality with the nonce-10 broadcast input |
| Reciprocal bindings | predicted coordinator in lien registry and engine; actual engine and all exact registries/factory/controllers/token/recipients in coordinator; exact account/manager implementation runtimes and locked implementation initializers |
| Prerequisite boundary | exact compiler-produced local runtimes for RoleManager, loan/policy/asset registries, emergency controller, and synthetic settlement token; policy records and resolver behavior remain outside this topology-only checkpoint |
| Storage pins | exact constructor and implementation-lock slots enumerated below; full historical layout and behavioral compatibility remain activation-grade gates |
| Scope | `topology_only=true`, `activation_accepted=false`, `role_grant_performed=false`, `contains_real_value=false`, mocks-only providers, synthetic identities/assets, no production key, no public network, and no live deployment authorization |

Absolute, traversal, alternate, symlinked, junction, or Windows-reparse artifact
and evidence paths are rejected. Every path is resolved and checked inside the
repository before it is read, written, or removed. JSON with duplicate keys,
unknown security-critical fields, noncanonical quantities, or numeric values that
can lose integer precision is rejected.

The ordered-transaction section, rather than prose or filesystem discovery, is the only
candidate sequence. Inserting, omitting, or reordering one transaction, or adding a
role, policy, setup, repair, or business-action transaction, invalidates the topology
candidate.

## Stage A: broadcast candidate

The smoke harness alone writes the plan and raw nonce transcript. The Forge script may
write only the canonical candidate path and only after a real `--broadcast`; a dry run
or simulation writes neither candidate nor evidence. The candidate must contain:

- artifact type `PHASE9_REFINANCE_DEPLOYMENT_CANDIDATE`;
- `topology_only=true`, `activation_accepted=false`,
  `role_grant_performed=false`, and
  `post_broadcast_verification_required=true`;
- the exact pre-broadcast plan digest and source commit;
- broadcaster, raw nonce-preconditioning evidence, starting/final nonce, chain ID, and
  canonical dependency addresses, all bound to the plan's complete ten-row expected
  transaction list by its exact digest;
- all predicted and actual addresses available after broadcast;
- exact configuration hash, predicted/actual address pairs, and observed runtime hashes,
  with constructor inputs, complete creation/runtime hashes, and source/artifact identities
  bound indirectly through the immutable plan digest; and
- `contains_real_value=false` and `deployment_history_reverted=false`.

Script-side reads and writes that occur before Forge sends the transactions do
not prove deployment. The raw broadcast artifact and RPC receipts are required.
No loan, custody record, lien, quote, request, or funding action may occur while
the evidence is only a candidate.

## Stage B: post-broadcast verifier

Only the separately named post-broadcast verifier may write the canonical topology
evidence path with artifact type `PHASE9_REFINANCE_TOPOLOGY_EVIDENCE`. Its output
retains `topology_only=true`, `activation_accepted=false`,
`role_grant_performed=false`, and `contains_real_value=false`; it sets
`topology_verified=true` only after every check passes and cannot write an accepted
deployment or checkpoint. It consumes the immutable plan, candidate, raw broadcast
artifact, canonical RPC, compiler artifacts, and expected source head. It must
independently prove:

1. `eth_accounts` is the exact ordered Foundry-default Anvil account set, account 1 is
   the plan broadcaster; its digest/profile identifies the expected fixture but does not
   independently prove signer origin, so the harness-owned process and recorded invocation
   supply the separate no-caller-private-key-input provenance,
   `eth_chainId == 0x7a69`, and the endpoint is the accepted loopback endpoint;
2. raw precondition evidence proves the dedicated account was at nonce `0x0`, the exact
   `anvil_setNonce` call set it to `0x1`, and immediate `latest` and `pending` reads
   both returned `0x1` before broadcast;
3. the broadcast contains exactly the plan's ten ordered contract-creation
   transactions with exactly their ordered receipts and no other broadcaster
   transaction;
4. every transaction hash resolves through RPC to the exact sender, consecutive
   nonce, zero value, target/input, and applicable predicted CREATE address;
5. every receipt is present, ordered, successful, and binds transaction, block number,
   canonical block hash, and applicable contract address; role grant/revoke/admin logs
   are forbidden, while exhaustive event and gas accounting remain activation-grade;
6. every creation input equals reviewed creation bytecode followed by the exact
   ABI-encoded constructor arguments;
7. every deployed address contains the exact reviewed runtime code at the
   receipt's canonical EIP-1898 block-hash reference;
8. the validation, request, and lifecycle modules occupy nonces 6, 7, and 8; their
   deployed runtimes equal the address-self-patched compiler templates; each is
   storage-free and contains no nested link or delegatecall; and all module and
   coordinator runtime/initcode sizes pass the pinned limits;
9. the engine is nonce 9 immediately before the nonce-10 coordinator, all four actual
   addresses match the pre-broadcast predictions, and no intervening sender nonce
   exists;
10. the verifier reproduces the exact seven executable-code replacements from the
    unlinked coordinator artifact and predicted module addresses, proves no other or
    unresolved link exists, and separately byte-compares the compiler-linked creation/
    runtime bytes—including library-bound compiler metadata—and the nonce-10 input;
11. the lien registry and payoff engine bind the exact coordinator, while
   the coordinator binds the exact loan registry, factory, engine, lien registry,
   asset registry, refinance policy registry, emergency controller, treasury fee
   recipient, and settlement token;
12. post-broadcast `latest` and `pending` nonce reads both return `0xb`, and the candidate,
    broadcast, and RPC evidence contain no role grant, role-admin change, policy/setup/
    repair call, or business action;
13. factory/account/position-manager/custody implementations and every other
    constructor-bound dependency agree through the enumerated storage observations,
    including locked implementation initializers;
14. all recorded addresses are nonzero where required, exact code exists where required,
    and the harness uses only its pinned synthetic identities; and
15. the candidate topology evidence schema validates before the non-activating topology
    file is written.

Behavioral resolver tuples, complete caller-graph execution, exhaustive event/gas
accounting, the historical ABI/storage freeze, additive ABI allowlists, and the final
canonical evidence digest remain mandatory activation-grade work. This preliminary
topology verifier neither claims nor satisfies them.

The token observation is bound to its receipt block hash. Each dependency and
storage observation is bound to that contract's receipt block hash or a later
single canonical block hash recorded by the verifier. Same-height replacement
blocks, moving `latest` reads, or mixed-block observations cannot authorize the
checkpoint.

## Required storage and behavioral observations

Raw storage is corroborative evidence, not an alternate configuration source.
The verifier records exact slot words, decodes them using the historical layout,
and checks matching public or purpose-built read behavior where the frozen surface
allows it.

For this preliminary topology checkpoint it observes:

- payoff engine slots `0..3` and their loan registry, quote-policy registry plus
  maximum validity packing, factory, and coordinator bindings;
- refinance coordinator dependency slots `0..8`;
- lien registry slot `0`, containing the exact coordinator binding;
- custody, factory, account implementation, and position-manager implementation
  constructor/configuration fields required by their historical layouts, including
  locked implementation initializers without an added constructor ABI item;
- runtime code and exact code hashes for every configured prerequisite, implementation,
  custody, lien registry, factory, engine, module, and coordinator;
- the pre-existing `RoleManager` as untrusted local context: before broadcast for the
  predicted nonce-5 factory and after broadcast for the actual factory,
  `roleExpiry(LOAN_FACTORY_ROLE, factory) == 0` and `hasRole(...) == false`; no grant or
  role-admin transaction/log occurs; ADR 0024 requires a separate activation-grade
  artifact to prove the later verification-before-governance-grant sequence;
- no role, policy, setup, repair, bootstrap, quote, refinance, or other business-action
  transaction is present in the candidate broadcaster's exact ten-transaction history.

Coordinator mapping-root observations, lien mapping-root observations, resolver tuples,
full initial application state, and behavioral getter/caller tests are deferred to the
later activation-grade evidence described by the acceptance matrix.

No bootstrap or protocol flow may run from this topology checkpoint. Fixture state may
be created only after ADR 0024-conforming activation-grade deployment evidence passes,
and is evidenced separately under `P9R-BOOT-*`.

## Rejection, reset, and residue

An intervening or undeclared broadcaster transaction, wrong before/preconditioned/after
nonce, missing or mismatched `anvil_setNonce` evidence, wrong prediction, wrong code,
constructor mismatch, any role grant or role-admin change, policy/setup/repair or
business-action call, failed or missing receipt, unexpected log, replacement block,
non-loopback RPC, dry run, source mismatch, stale artifact, production-looking key, or
real-value input rejects the complete topology candidate.

On rejection the verifier removes only the canonical not-yet-verified topology output,
emits diagnostics without creating a fourth evidence artifact, and requires the
one-command bounded local reset. It does not claim that an on-chain transaction was
reverted after confirmation. A later run cannot verify topology evidence until the reset
disposes of the canonical local chain state and canonical refinance evidence
directory.

Unsolicited token surplus at any deployed address is not a protocol liability,
does not make candidate evidence acceptable, and creates no rescue authority.
Donation residue is removed only with the disposable local reset.
Successful topology verification also requires immediate bounded reset and disposal;
verified evidence proves the completed observation, not an authority to retain or use
the deployed local graph.

## Acceptance mapping

The following rows remain activation-grade requirements. The topology candidate can
provide preliminary bytecode, address, nonce, and receipt observations, but cannot
satisfy any row until a separate artifact proves ADR 0024's selected nonce and role
order.

| Acceptance row | Later activation-grade artifact/result |
|---|---|
| `P9R-DEPLOY-001` | Reserved and unsatisfied until a successor ADR combines ADR 0024 nonce-preconditioning and identity/grant/reset controls with a reproducibly measured exact CREATE sequence; ADR 0027's 15-CREATE record is unproven-candidate evidence only |
| `P9R-DEPLOY-002` | Reserved and unsatisfied until the successor pins the exact module/coordinator nonces, link inventory, coordinator prediction, final nonce, reciprocal bindings, and grant evidence; ADR 0027's nonce-15/`0x3814...`/`0x10` values are not operative |
| `P9R-DEPLOY-003` | Complete successor activation candidate, broadcast, RPC transaction/receipt/log, module self-patches, unlinked/linked code, independently frozen link offsets and normative sizes, constructor, role, slot, behavior, exact ADR 0027 payload/proof semantics, and accepted-digest verification under ADR 0024 and the successor topology ADR |
| `P9R-DEPLOY-004` | Negative evidence for wrong chain/key/order/nonce/prediction/code/constructor/RPC/provider/top-level CREATE2 or undeclared/mismatched/failed/late/post-hoc role action plus bounded reset |
| `P9R-BOOT-005` | Reserved and unsatisfied until ADR 0024-conforming activation-grade deployment passes; then prove per-loan factory nonce/replay, salts/predictions/runtime, initialization/authentication, registry/event order, frozen errors, raw-ID ordering, zero-version/policy rules, and same-block checkpoint rollback |
| `P9R-DON-004` | One-command bounded-local-reset command/script, reset-generation manifest, before/after chain identity, observed removal of donated surplus, and proof that no production disposal/recovery authority exists |
| `P9R-FZ-001` | Exact source, compiler, ABI, storage, one-event/two-error additive allowlist, and method-level checkpoint binding |
| `P9R-LOCAL-001` | Synthetic-local dependency/provider/credential boundary scan |
| `P9R-LOCAL-002` | Reserved and unsatisfied until ADR 0024-conforming activation-grade evidence; then prove clean bootstrap, accepted deployment, flow, restart/replay, and reset evidence from the same reset generation |
| `P9R-LOCAL-003` | Explicit proof that the evidence cannot be reused as public-chain or production authorization |

No deployment checkpoint may pass until independent architecture and security
review approve the accepted evidence and exact source head, and the bundled
`UNI-REFI-001`/`UNI-REFI-002` method activation gate passes. The topology candidate
authorized here is preliminary input only and cannot satisfy any row above. ADR 0024
selects explicit nonce preconditioning and the final verification-before-grant sequence,
but this document alone does not execute that sequence or change either backlog row
from `TODO`.
