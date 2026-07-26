# Phase 9 Refinance Deployment Evidence

Status: normative evidence boundary; no accepted deployment exists

Date: 2026-07-26

## Purpose and relationship to payoff evidence

This document defines the deployment evidence required before the ADRs 0021 and 0022
refinance method bundle can be activated. It does not authorize a deployment or
claim that a candidate, verifier, manifest, or accepted evidence file exists.

The nested payoff pair-deployer evidence remains valid for the already accepted
payoff-only checkpoint. It is historical evidence and is not rewritten. A later
refinance activation uses a fresh, larger deployment with top-level sequential
`CREATE` transactions plus one declared role-initialization transaction because the
complete constructor-bound graph includes the lien registry, payoff engine, refinance
coordinator reciprocal authority, and a factory that must register loans.

The deployment remains disposable synthetic-local evidence only and local-only
by design. It provides no business-logic activation and has no production,
public-network, live-fund, external-provider, or mainnet authority.

## Required deployment form

The candidate must be broadcast from one fresh local account whose starting nonce and
complete transaction sequence are recorded before broadcast. `RoleManager` binds that
account as the synthetic `GOVERNANCE_EXECUTOR_ROLE` holder and binds a distinct
predeclared synthetic local address as administrator. Every top-level dependency is
first deployed by that broadcaster through an ordinary top-level contract-creation
transaction. Exactly one declared initialization call follows the address-sensitive
creates. The sequence must satisfy all of the following:

- chain ID is exactly `31337`;
- the RPC is credential-free literal loopback HTTP with an explicit port;
- every manifest transaction has the same fresh sender, the next consecutive nonce,
  and zero value; every creation has exact reviewed creation bytecode and exact
  constructor arguments;
- the manifest enumerates every transaction in exact ordinal order, including every
  top-level dependency's artifact, source, compiler profile, creation/runtime hashes,
  predicted address, constructor ABI types, and constructor values;
- the payoff quote engine is the entry immediately before the refinance
  coordinator;
- before any broadcast, the coordinator address is predicted from the exact
  broadcaster nonce at its manifest ordinal;
- the lien registry and payoff engine constructors receive that predicted
  coordinator address;
- the coordinator constructor receives the actual immediately preceding engine
  and every exact already-created dependency;
- immediately after all address-sensitive creates, the final manifest transaction is
  the exact zero-value call from the broadcaster to `RoleManager.grantRole` with
  `(LOAN_FACTORY_ROLE, phase9Factory, type(uint64).max)` and exact predeclared calldata
  hash;
- that initialization succeeds before any loan registration, bootstrap, quote,
  refinance, or other business action;
- every other reciprocal binding or factory implementation address is predicted
  and verified in the same manifest before broadcast; and
- there is no top-level pair deployer, `CREATE2`, proxy, setter, rebinding,
  mutable implementation selector, late open-authorization window, arbitrary call,
  undeclared role grant, role-admin change, or post-hoc administrative repair
  transaction. The one reviewed initialization call is mandatory configuration, not
  repair authority.

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

For every bootstrap or replacement creation trace, evidence records the factory nonce,
creation ID, both domain-separated salts, implementation addresses/runtime hashes,
predicted and actual clone addresses, minimal-proxy creation/runtime hashes, and code at
both clones. The trace proves the atomic order: reserve the unique creation identity,
stored request, processed flag, predicted mappings, and incremented nonce; deploy both
clones; initialize the account; initialize the manager after authenticating the factory
and reciprocal fields through the account; register and verify protocol version 9 in
`LoanRegistry`; and emit the one creation event. Failure injection at every step proves
that no nonce reservation, clone, registry entry, mapping, or event survives a revert.

An exact old `creationId` replay is tested after later successful creations have advanced
the global nonce. It is classified from the stored request before the current nonce,
revalidates the active four-field creation-resolver tuple and canonical clone/registry
bindings, returns the stored pair, and produces no state-changing call, write, deployment,
initialization, registration, nonce movement, or event. Changed reuse fails with
`InvalidPhase9LoanConfiguration`; a distinct creation identity for an existing loan
fails with `Phase9LoanAlreadyExists(loanId)`. Clone, resolver, authority, nonce, prediction,
initialization, and registration failures expose no additional factory error.

The same execution evidence proves unsigned raw-`bytes32` ordering and exact inert replay
for tranche/position records, agreement-version-zero absence for a dormant account,
nonzero `LoanConfiguration` identifiers and policy/agreement commitments, and overwrite-
last same-block checkpoint coalescing. Asset evidence keeps the authority split exact:
the factory/account verify the ADR-bound synthetic-local token/runtime, while only the
coordinator calls the typed asset resolver and proves its active, decimals,
exact-balance-delta, runtime, and two-configuration equality.

## Pre-broadcast manifest

The reviewed manifest is immutable input to candidate creation. At minimum it
contains:

| Field | Required evidence |
|---|---|
| Manifest identity | schema version, artifact type, environment `local`, chain `31337`, source commit, dirty-state rejection, generated-at, and canonical manifest digest |
| Broadcaster and roles | nonzero address, proof it is a fresh disposable local key and the `RoleManager` governance executor, distinct nonzero synthetic local administrator, starting/final expected nonces, and no prior/pending transaction |
| RPC boundary | canonical literal loopback URL, no credentials/path/query/fragment/proxy, expected chain ID, and reset generation |
| Compiler boundary | Solidity/Foundry versions, optimizer settings, EVM version, remappings, artifact paths, compiler source-set hashes, and exact creation/runtime bytecode hashes |
| Ordered transactions | one row per top-level `CREATE` followed by exactly one `RoleManager.grantRole` row; exact ordinal, sender nonce, target/predicted address as applicable, artifact or selector, constructor/calldata ABI encoding, zero value, input hash, expected runtime hash for creates, and expected `RoleGranted` log for the grant |
| Reciprocal bindings | predicted coordinator in lien registry and engine; actual engine and all exact registries/factory/controllers/token/recipients in coordinator; exact account/manager implementation runtimes and locked implementation initializers; factory/account-first/manager/registry caller and initialization authority; custody/lien caller authority |
| Policy surfaces | exact code and behavior for `resolveLoanCreation`, `resolveBootstrap`, `resolveRefinancePolicy`, `resolveRefinanceAsset`, and `resolveCustodyAsset`, including active records, runtime hashes, exact-delta flags, and hard vector caps |
| Storage pins | historical storage manifest digest and exact reviewed slots/offsets/types to observe after broadcast |
| Scope | `contains_real_value=false`, mocks-only providers, synthetic identities/assets, no production key, no public network, and no live deployment authorization |

Absolute, traversal, alternate, symlinked, junction, or Windows-reparse artifact
and evidence paths are rejected. Every path is resolved and checked inside the
repository before it is read, written, or removed. JSON with duplicate keys,
unknown security-critical fields, noncanonical quantities, or numeric values that
can lose integer precision is rejected.

The ordered-transaction section, rather than prose or filesystem discovery, is the only
accepted sequence. Inserting, omitting, or reordering one transaction—or moving the
role initialization after any business action—invalidates the complete deployment.

## Stage A: broadcast candidate

The later deployment entrypoint may write only the canonical refinance candidate
path. A dry run or simulation can validate pre-broadcast pins but cannot write
accepted evidence. The candidate must contain:

- artifact type `PHASE9_REFINANCE_DEPLOYMENT_CANDIDATE`;
- `activation_accepted=false` and
  `post_broadcast_verification_required=true`;
- the exact pre-broadcast manifest digest and source commit;
- broadcaster, distinct administrator, starting/final nonce, chain ID, canonical
  dependency addresses, and the complete ordered expected transaction list, including
  the final role-initialization target, calldata, input hash, and expected log;
- all predicted and actual addresses available after broadcast;
- exact constructor-argument and configuration hashes;
- expected creation/runtime code hashes and historical ABI/storage manifest
  digests; and
- `contains_real_value=false` and `deployment_history_reverted=false`.

Script-side reads and writes that occur before Forge sends the transactions do
not prove deployment. The raw broadcast artifact and RPC receipts are required.
No loan, custody record, lien, quote, request, or funding action may occur while
the evidence is only a candidate.

## Stage B: post-broadcast verifier

Only a separate post-broadcast verifier may write
`activation_accepted=true`. It consumes the immutable manifest, candidate, raw
broadcast artifact, canonical RPC, compiler artifacts, historical compatibility
snapshots, and expected source head. It must independently prove:

1. `eth_chainId == 0x7a69` and the endpoint is the accepted loopback endpoint;
2. the broadcast contains exactly the manifest's ordered contract-creation
   transactions followed by exactly the one declared role-initialization call, with
   exactly their ordered receipts;
3. every transaction hash resolves through RPC to the exact sender, consecutive
   nonce, zero value, target/input, and applicable predicted CREATE address;
4. every receipt is successful and binds transaction, block number, canonical
   block hash, applicable contract address, exact expected logs, and gas fields without
   a missing receipt;
5. every creation input equals reviewed creation bytecode followed by the exact
   ABI-encoded constructor arguments;
6. every deployed address contains the exact reviewed runtime code at the
   receipt's canonical EIP-1898 block-hash reference;
7. the engine is immediately before the coordinator, both actual addresses match
   the pre-broadcast predictions, and no intervening sender nonce exists;
8. the lien registry and payoff engine authorize the exact coordinator, while
   the coordinator binds the exact loan registry, factory, engine, lien registry,
   asset registry, refinance policy registry, emergency controller, treasury fee
   recipient, and settlement token;
9. the final initialization receipt contains exactly
   `RoleGranted(LOAN_FACTORY_ROLE, phase9Factory, type(uint64).max, broadcaster)`;
   canonical EIP-1898 reads at its block hash prove the exact expiry and `hasRole`,
   source and transaction/log completeness prove no other role grant or role-admin
   change, and no business action precedes it;
10. factory/account/position-manager/custody implementations and every other
    constructor-bound dependency agree through storage and behavioral getters, and
    enforce the exact coordinator/factory caller graph and locked-implementation
    semantics in ADRs 0021 and 0022;
11. all recorded addresses are nonzero where required, contain code where
    required, and have no production-looking identity or provider binding;
12. the historical ABI/storage freeze and exact additive allowlist of one transition
    event plus two typed unknown-ID errors match the exact deployed source; and
13. the accepted evidence schema and canonical evidence digest validate before
    the accepted file is written.

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

At minimum it observes:

- payoff engine slots `0..3` and their loan registry, quote-policy registry plus
  maximum validity packing, factory, and coordinator bindings;
- refinance coordinator top-level slots `0..15`, including dependency slots
  `0..8` and the empty initial mapping roots for refinance nonces, records,
  commitment vectors, commitments, attributed escrow, terminal results, and
  processed operations;
- lien registry slots `0..2`, including the exact coordinator binding and empty
  initial lien/handoff mappings;
- custody, factory, account implementation, and position-manager implementation
  constructor/configuration fields required by their historical layouts, including
  locked implementation initializers without an added constructor ABI item;
- runtime code and exact code hashes for all resolver mocks, registries,
  controllers, implementations, token, custody, lien registry, factory, engine,
  and coordinator;
- the `RoleManager` constructor's distinct administrator/governance-executor bindings,
  `roleExpiry(LOAN_FACTORY_ROLE, phase9Factory) == type(uint64).max`,
  `hasRole(LOAN_FACTORY_ROLE, phase9Factory) == true`, exact expected constructor/grant
  logs, and no additional grant or role-admin-change transaction/log;
- creation/bootstrap/refinance/asset resolver selectors return their exact typed
  tuples, mode values, active flags, vector caps, dormant replacement template, and
  bootstrap facts; malformed, oversized, or substituted tuples fail closed; and
- initial zero application state: no loan, clone, custody record, lien, quote,
  refinance, commitment, escrow liability, terminal result, or processed
  operation.

The later bootstrap creates fixture state only after accepted deployment evidence
exists and is evidenced separately under `P9R-BOOT-*`.

## Rejection, reset, and residue

An intervening or undeclared broadcaster transaction, wrong nonce, wrong prediction,
wrong code, constructor mismatch, mismatched/failed/missing/late role initialization,
wrong role expiry/member/sender/calldata/log, any additional role grant or role-admin
change, post-hoc repair, failed or missing receipt, unexpected log, replacement block,
non-loopback RPC, dry run, source mismatch, stale artifact, or production-looking input
rejects the complete activation.

On rejection the verifier removes only the canonical not-yet-accepted output and
may write a canonical rejection receipt with:

```text
activation_accepted = false
bounded_local_reset_required = true
deployment_history_reverted = false
```

It does not claim that an on-chain transaction was reverted after confirmation.
Accepted and rejected refinance evidence cannot coexist for one reset generation.
A later run cannot accept evidence until the one-command bounded local reset
disposes of the canonical local chain state and canonical refinance evidence
directory.

Unsolicited token surplus at any deployed address is not a protocol liability,
does not make candidate evidence acceptable, and creates no rescue authority.
Donation residue is removed only with the disposable local reset.

## Acceptance mapping

| Acceptance row | Required artifact/result |
|---|---|
| `P9R-DEPLOY-001` | Fresh synthetic governance-executor broadcaster, distinct synthetic administrator, chain 31337, exact complete nonce-ordered CREATEs then one factory-role initialization, engine immediately before coordinator |
| `P9R-DEPLOY-002` | Independent CREATE prediction, reciprocal constructor binding, and exact factory-role call/receipt/log/EIP-1898 state evidence |
| `P9R-DEPLOY-003` | Candidate, complete broadcast, RPC transaction/receipt/log, code, constructor, role, slot, behavior, schema, and accepted-digest verification |
| `P9R-DEPLOY-004` | Negative evidence for wrong chain/key/order/nonce/prediction/code/constructor/RPC/provider/top-level CREATE2 or undeclared/mismatched/failed/late/post-hoc role action plus bounded reset |
| `P9R-BOOT-005` | Per-loan factory nonce and replay classification, exact salts/predictions/runtime, account-before-manager initialization/authentication, registry/event order, frozen errors, raw-ID ordering, zero-version/policy rules, and same-block checkpoint coalescing with rollback at every step |
| `P9R-DON-004` | One-command bounded-local-reset command/script, reset-generation manifest, before/after chain identity, observed removal of donated surplus, and proof that no production disposal/recovery authority exists |
| `P9R-FZ-001` | Exact source, compiler, ABI, storage, one-event/two-error additive allowlist, and method-level checkpoint binding |
| `P9R-LOCAL-001` | Synthetic-local dependency/provider/credential boundary scan |
| `P9R-LOCAL-002` | Clean bootstrap, accepted deployment, flow, restart/replay, and reset evidence from the same reset generation |
| `P9R-LOCAL-003` | Explicit proof that the evidence cannot be reused as public-chain or production authorization |

No deployment checkpoint may pass until independent architecture and security
review approve the accepted evidence and exact source head, and the bundled
`UNI-REFI-001`/`UNI-REFI-002` method activation gate passes. This document alone
does not change either backlog row from `TODO`.
