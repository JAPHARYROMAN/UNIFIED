# ADR 0022: Phase 9 Factory, Account, and Position Bootstrap Semantics

Status: accepted for synthetic local specification and implementation review

Date: 2026-07-26

Owner: Protocol Architecture Authority

Work item: `UNI-ADR-017`

## Context

ADR 0021 fixes the atomic-refinance authority, identities, replay outcomes, clone
salts, local bootstrap, and method-level activation boundary. The historical
`UNI-ABI-009` artifacts separately freeze the external interfaces and storage of
`Phase9LoanFactory`, `Phase9LoanAccount`, and `PositionManagerV2`.

Those authorities leave nine implementation details that cannot safely be inferred
from the stubs: a replayed creation cannot recover its original factory-global nonce;
the frozen errors need an exact conflict mapping; tranche and position order need a
comparator; manager initialization needs a factory-authentication source; dormant
agreement version zero needs a defined result; configuration hashes need an exact zero
policy; the factory has no asset-resolver slot; implementation instances need an
initializer lock without a new constructor ABI item; and same-block checkpoints need
one canonical representation.

This decision resolves only those details. It is subordinate to ADR 0019, ADR 0021,
the constitutional specifications, and the historical ABI/storage freeze. ADR 0021
continues to control the complete refinance state machine, economic order, caller
authority, deployment sequence, and activation gate. A conflict with this decision
must be resolved before implementation review; it is not permission to add a selector,
tuple member, event, error, storage field, base contract, or mutable dependency.

## Decision

### 1. Synthetic-local and compatibility boundary

Every rule below applies only on disposable chain `31337`, only to the exact
`Phase9LocalSyntheticToken` runtime, and only to synthetic local identities and value.
It grants no public-network, production-key, external-provider, mainnet, or real-fund
authority.

The historical ABI and storage artifacts remain byte-for-byte authoritative. The only
additive ABI items remain the one coordinator transition event and two typed unknown
errors accepted by ADR 0021. A source-level implementation must preserve every
historical ABI error, including `Phase9ImplementationNotFrozen`, without making an
unopened mutator callable. No explicit constructor may be added to the currently
constructor-less account or position-manager ABI.

### 2. Factory nonce and creation replay

`_nextLoanNonce` starts at one. A fresh unique creation binds the current value into
the ADR 0021 `creation_id`, rejects `type(uint64).max`, and advances the value exactly
once. Any later failure reverts the nonce and every other factory, clone, registry, and
event effect.

`createLoan` classifies `_processedCreationIds[request.creationId]` before consulting
the current global nonce or testing fresh-loan absence. For a processed identity it:

1. compares the complete stored and supplied `LoanCreationRequest` values with
   `keccak256(abi.encode(...))`;
2. calls the exact active `resolveLoanCreation(policySetHash, loanId)` source again and
   requires its complete configuration, closed creation mode, and bootstrap ID to
   equal the stored request and its mode-specific derivation;
3. authenticates `msg.sender` as the coordinator in that resolved stored
   configuration;
4. verifies the stored nonzero account and manager mappings, their code, and the
   canonical protocol-version-9 `LoanRegistry` identity; and
5. returns the stored clones without a write, deployment, initialization,
   registration, nonce change, or event.

The factory never recomputes a processed `creationId` with the current
`_nextLoanNonce`. The original factory nonce is not separately recoverable from the
frozen storage after later creations. The successful first validation, stored request,
creation-ID commitment, and emitted `loanNonce` are its evidence. For bootstrap replay,
the four-field creation resolver tuple is revalidated; the historical full
`resolveBootstrap` payload is not byte-compared because no initial-payload hash is
stored and live debt may legitimately change after creation. Fresh bootstrap creation
still validates that complete payload before any effect, and the policy source remains
immutable by ADR 0021.

The exact factory error mapping is:

- a processed creation ID with a changed request or creation-resolver fact reverts
  `InvalidPhase9LoanConfiguration()`;
- a different creation identity that collides with an existing canonical loan reverts
  `Phase9LoanAlreadyExists(loanId)`; and
- invalid mode, nonce, authorization, resolver output, configuration, implementation,
  prediction, partial graph, or nonce exhaustion reverts
  `InvalidPhase9LoanConfiguration()`.

An exact replay must branch before `LoanRegistry.registerLoan`, whose append-only
duplicate behavior is not idempotent.

### 3. Deterministic clones, initializer locks, and effect order

Factory-internal account and manager clones use the exact ADR 0021 salts and standard
OpenZeppelin-compatible EIP-1167 minimal-proxy creation and runtime bytes. Prediction
includes the implementation, salt, factory deployer, and exact minimal-proxy creation
code hash. The factory validates both implementation addresses contain code before
deployment and verifies both actual clone addresses and code afterward.

A literal `Clones.cloneDeterministic` path is prohibited when it adds OpenZeppelin
`FailedDeployment` or `InsufficientBalance` errors to the frozen factory ABI. The
implementation instead uses private byte-for-byte-compatible EIP-1167 prediction and
`CREATE2` helpers and maps a deployment failure to
`InvalidPhase9LoanConfiguration()`. This changes no external behavior or ABI authority.

The account and manager implementation instances are initializer-locked with a
declaration initializer on the existing final storage flag:

```solidity
bool private _initialized = true;
```

Implementation creation therefore sets only implementation storage. A fresh minimal
clone retains zero storage and may initialize exactly once. An explicit no-argument
constructor is prohibited because it would create a new constructor ABI item.

After every pure, resolver, authorization, identity, absence, and prediction check, the
factory reserves the exact request, processed flag, predicted account/manager mappings,
and incremented nonce before clone deployment or initialization/registry effects. It
then:

1. deploys both clones and verifies their predictions and code;
2. initializes the account first;
3. initializes the manager second;
4. calls `LoanRegistry.registerLoan` once and verifies account, borrower, agreement
   hash, protocol version `9`, and nonterminal state; and
5. emits exactly one `Phase9LoanCreated` event.

Account-before-manager order is mandatory. Manager initialization reads the already
initialized account configuration and requires `configuration.factory == msg.sender`,
matching loan ID, `configuration.positionManager == address(this)`, matching settlement
token, and code at both the account and token addresses. This authenticates the factory
without adding manager storage or a selector. Any failure reverts every reservation,
clone, initialization, registration, nonce, and event effect.

### 4. Configuration, asset, debt, and agreement-version rules

Every `LoanConfiguration` is complete. `loanId`, `settlementAssetId`, `agreementHash`,
`policySetHash`, `amendmentPolicyHash`, `protectionPolicyHash`, and
`recoveryPolicyHash` are nonzero. The borrower is nonzero. Every configured contract
dependency is nonzero and contains code. None of the three policy hashes is optional in
this slice; unopened later methods remain frozen even though their immutable authority
is already bound.

The only settlement asset ID is the direct, non-hashed mapping of
`asset:phase9:p9unit`:

```text
0x61737365743a7068617365393a7039756e697400000000000000000000000000
```

The factory has no asset-source field and must not repurpose a policy registry or add
storage. The factory and account require that exact asset ID, chain `31337`, equality
with the active creation configuration, a deployed settlement token, and the exact
`settlementToken.codehash == keccak256(type(Phase9LocalSyntheticToken).runtimeCode)`
condition. The manager proves the token equals the account configuration and has that
same runtime. The coordinator remains the sole consumer of its frozen `_assetRegistry`
and independently validates the ADR 0021 `active`, `exactBalanceDelta`, six-decimal,
token-address, resolver-runtime-hash, and deployed-runtime-hash tuple. The Foundry-only
`keccak256("SYNTHETIC_PHASE9_ASSET")` value is not an asset identity.

Bootstrap account initialization accepts only the exact active resolver debt with
`ACTIVE/CURRENT`, nonzero `termsVersion`, and zero active refinance/restructure IDs. It
stores the complete debt and writes
`_agreementVersionHashes[initialDebt.termsVersion] = configuration.agreementHash`.

Replacement account initialization accepts only `CREATED/NONE` with every other debt
amount, version, nonce, time, schedule, and active-operation field zero. It does not
write `_agreementVersionHashes[0]`; `agreementVersionHash(0)` remains zero. Later
replacement activation requires a nonzero terms version, an empty mapping entry, and
writes the configuration agreement hash at that version.

Initialize authenticates before classifying initialized/configuration state: a wrong
caller always reverts `UnauthorizedPhase9LoanCaller(msg.sender)`, while an authenticated
second initialization or invalid configuration/debt shape reverts
`InvalidPhase9LoanOperation()`. After those checks, the account sets `_initialized`
before any possible interaction.

### 5. Ordered issuance, replay, and checkpoints

Every canonical tranche, position, collateral, custody, and lien sequence is strictly
increasing by unsigned raw `bytes32` identity, implemented as
`uint256(currentId) > uint256(previousId)`. Tranches order by `trancheId`; positions
order by `positionId`; tranche `priority` remains an independent record fact and is not
the ordering comparator. Zero, duplicate, or decreasing IDs are invalid.

`registerTranche` and `issuePosition` authenticate the caller on every call by reading
the immutable account configuration and requiring its coordinator, manager, loan ID,
and settlement token to match. They classify an existing ID before the new-record
ordering check. An exact full-record replay returns without a write, checkpoint,
aggregate change, array append, or event. Changed reuse, wrong authority, invalid
initialization, ordering, caps, fields, state, unknown tranche, allocation, or arithmetic
reverts `InvalidPositionOperation()`. `UnknownPosition` is not used for these activated
write conflicts.

Every checkpoint series has at most one entry per block. A writer rejects
`block.number > type(uint64).max`, overwrites the last entry when its block equals the
current block, and otherwise appends. Owner checkpoints set `owner` and keep `value`
zero. Voting-power, claim, and total-voting-power checkpoints set `value` and keep
`owner == address(0)`. Issuance creates one owner, voting-power, and claim checkpoint
for the new position; multiple same-block issuances coalesce the cumulative total-vote
checkpoint. Greatest-checkpoint-at-or-before lookup therefore has one canonical
block-level result.

### 6. Method activation remains closed

This decision does not expand ADR 0021's method allowlist. Every unopened mutator
retains the exact `Phase9ImplementationNotFrozen()` behavior. Read methods may support
the activated paths only within their frozen selectors and return types. The accepted
refinance checkpoint must prove historical ABI equality, structural storage equality,
method-level activation, exact clone bytecode, direct implementation locks, creation
replay, error selectors, raw ordering, zero policy, asset/runtime binding, and
same-block checkpoint coalescing against one reviewed commit.

## Consequences

- Factory creation is replay-safe without pretending the current global nonce is the
  historical nonce.
- Canonical clones initialize atomically, while directly callable implementation
  instances remain locked without ABI or storage drift.
- Dormant replacement debt cannot masquerade as agreement version zero, and future
  policy authority cannot be left unbound by zero configuration hashes.
- Asset identity, token implementation, ordering, and block-level checkpoint history
  are deterministic across Solidity and independent models.
- No real funds, production key, public network, external provider, bridge, mainnet
  deployment, or production approval is authorized.
- `UNI-REFI-001` and `UNI-REFI-002` remain incomplete until the complete ADR 0021 gate,
  all existing `P9R-*` rows, independent reviews, deployment evidence, and the bundled
  implementation checkpoint pass.
