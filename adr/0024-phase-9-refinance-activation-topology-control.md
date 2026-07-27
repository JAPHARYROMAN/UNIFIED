# ADR 0024: Phase 9 Refinance Activation-Topology Control

Status: accepted for synthetic-local activation-topology specification; implementation activation pending

Date: 2026-07-27

Owner: Protocol Architecture Authority

Work item: `UNI-ADR-019`

Qualification: ADR 0026 supersedes only this ADR's exact ten-CREATE graph, three module
addresses, nonce-9 payoff engine, nonce-10 coordinator, seven link offsets, and final
candidate nonce `0xb`. The identity separation, explicit nonce precondition,
verification-before-grant order, sole governance-executor grant, post-grant evidence,
activation closure, and bounded reset requirements below remain authoritative. The
historical ten-CREATE text is retained as evidence of the candidate that was measured,
not as the future deployment target.

## Context

ADR 0021 requires a nonce-ordered refinance deployment followed by one exact
`LOAN_FACTORY_ROLE` grant. ADR 0023 revised the linked candidate to ten top-level
`CREATE` transactions at broadcaster nonces 1 through 10, but deliberately left the
activation-grade nonce origin and final role order unresolved. The preliminary harness
therefore observes a fresh candidate broadcaster at nonce zero, applies one evidenced
`anvil_setNonce` precondition to set it to one, deploys the ten-contract graph, proves
that the factory role remains absent, and resets without granting a role or invoking a
business method.

The unresolved alternatives are:

1. deploy `RoleManager` from the candidate broadcaster at nonce zero and then deploy
   the ten-contract graph at nonces 1 through 10; or
2. preserve the separately prepared `RoleManager`, keep the candidate broadcaster
   roleless, and promote the already evidenced nonce precondition to the exact
   synthetic-local activation-topology rule.

The first alternative couples the address-sensitive graph broadcaster to authority
bootstrap, changes the reviewed prerequisite boundary, and requires a new preparation
and deployment mechanism. The second retains four distinct responsibilities: setup
administrator, governance executor, candidate broadcaster, and fixture allocator. Its
nonstandard RPC mutation is safe only because the boundary is literal-loopback Anvil,
chain `31337`, disposable, zero-real-value, and reset-bounded, and because raw before
and after RPC evidence makes the mutation explicit.

This ADR resolves only that synthetic-local topology decision and the future role-grant
order. It does not execute the grant, activate D1-D4, complete `UNI-REFI-001` or
`UNI-REFI-002`, create or update `P9-REFI-001`, approve a deployment, or authorize a
public network or production environment.

## Decision

### 1. Explicit nonce preconditioning is selected

The activation-grade synthetic-local topology uses explicit nonce preconditioning.
The candidate broadcaster does not deploy `RoleManager`, does not receive
`DEFAULT_ADMIN_ROLE` or `GOVERNANCE_EXECUTOR_ROLE`, and does not send the later role
grant. A nonce-zero `RoleManager` deployment by that candidate broadcaster is rejected.
This decision supersedes only ADR 0021 Section 18's statement that the refinance graph
broadcaster is also the governance executor. ADR 0021's exact single maximum-expiry
factory-role grant and every other authority and evidence rule remain binding.

The selection is limited to a newly started Anvil process at the exact credential-free
literal endpoint `http://127.0.0.1:18545` with decoded chain ID `31337`. It is not a
portable EVM deployment rule. A public RPC, fork, reused process, non-loopback endpoint,
production-origin key, real-value asset, or external provider is invalid.

The candidate broadcaster must be a dedicated disposable account distinct from the
setup administrator, governance executor, and fixture allocator. All four identities
are nonzero and pairwise distinct. The only accepted identities are the freshly spawned
Foundry-default Anvil accounts already pinned by the local harness:

| Responsibility | Account | Address |
|---|---:|---|
| setup administrator/broadcaster | 0 | `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266` |
| candidate broadcaster | 1 | `0x70997970c51812dc3a010c7d01b50e0d17dc79c8` |
| governance executor | 2 | `0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc` |
| fixture allocator | 3 | `0x90f79bf6eb2c4f870365e785982e1f101e93b906` |

They are unlocked ephemeral development identities, not caller-supplied private-key,
mnemonic, keystore, hardware-wallet, or KMS inputs. Raw `eth_getTransactionCount` reads
for the candidate at `latest` and `pending` must both be `0x0` before preparation.
Exactly one successful
`anvil_setNonce(candidateBroadcaster, 0x1)` call is permitted; immediate `latest` and
`pending` reads must both be `0x1`. No transaction may use candidate nonce zero, and no
other nonce mutation is permitted.

### 2. Prerequisite authority remains separate

Before candidate nonce preparation, the setup broadcaster deploys the prerequisite
`RoleManager(setupAdministrator, governanceExecutor)`. The constructor is the only
authority initialization in the prerequisite phase. It grants exactly
`DEFAULT_ADMIN_ROLE` to the setup administrator and
`GOVERNANCE_EXECUTOR_ROLE` to the governance executor, both with
`type(uint64).max` expiry.

The constructor arguments are nonzero and distinct. The constructor's two exact
`RoleGranted` logs are recorded. No `grantRole`, `revokeRole`, or `setRoleAdmin`
transaction follows during prerequisite preparation. The default admin does not deploy
the address-sensitive refinance graph, and the governance executor sends no transaction
before the final grant described below. The governance executor must therefore have
raw `latest` and `pending` nonce `0x0` immediately before that grant.

The setup broadcaster may deploy only the declared local loan, policy, asset,
emergency, and settlement-token prerequisites after `RoleManager`. Those prerequisite
transactions do not alter the candidate broadcaster's nonce or the governance
executor's nonce and grant no refinance-factory authority.

### 3. Exact ten-CREATE graph remains unchanged

After the nonce precondition, the candidate broadcaster sends exactly ten sequential,
zero-value, top-level `CREATE` transactions at nonces 1 through 10 in ADR 0023 order:

1. `LienRegistry`;
2. `CollateralCustodyV2`;
3. `Phase9LoanAccount` implementation;
4. `PositionManagerV2` implementation;
5. `Phase9LoanFactory`;
6. `Phase9RefinanceValidationModule`;
7. `Phase9RefinanceRequestModule`;
8. `Phase9RefinanceLifecycleModule`;
9. `PayoffQuoteEngine`; and
10. the fully linked `RefinanceCoordinator`.

The predicted addresses, reciprocal constructor bindings, three link targets, seven
link offsets, creation inputs, runtime hashes, receipts, canonical receipt block hashes,
and final candidate nonce `0xb` remain governed by ADR 0023. No role, setup, repair,
policy, loan, quote, refinance, funding, or other business transaction may be mixed into
this ten-transaction sequence.

### 4. Verification precedes the only role grant

The topology verifier must first accept the complete ten-CREATE graph while proving:

- `roleAdmin(LOAN_FACTORY_ROLE) == GOVERNANCE_EXECUTOR_ROLE`;
- `roleExpiry(LOAN_FACTORY_ROLE, phase9LoanFactory) == 0`;
- `hasRole(LOAN_FACTORY_ROLE, phase9LoanFactory) == false`;
- the candidate broadcaster has neither default-admin nor governance-executor authority;
- no role or role-admin log exists after the `RoleManager` constructor logs; and
- the plan, candidate, RPC, bytecode, link, constructor, receipt, and block-hash evidence
  all bind one clean source commit and one reset generation.

A topology verification failure ends the attempt. It cannot be repaired in place; the
complete disposable chain must reset before retry.

### 5. Exact role-initialization order

Only after the verification in Section 4 may the dedicated governance executor send
one zero-value transaction at its nonce zero:

```solidity
RoleManager.grantRole(
    ProtocolRoles.LOAN_FACTORY_ROLE,
    phase9LoanFactory,
    type(uint64).max
);
```

The target is the prerequisite `RoleManager`, the sender is the constructor-bound
governance executor, and the account is the verified nonce-5 factory. The calldata,
transaction hash, sender, nonce `0x0`, zero value, successful receipt, canonical receipt
block hash, and exactly one
`RoleGranted(LOAN_FACTORY_ROLE, phase9LoanFactory, type(uint64).max,
governanceExecutor)` log are mandatory. Immediate raw governance nonce reads at
`latest` and `pending` must both be `0x1`.

At that exact receipt block, EIP-1898 reads must prove:

- `roleAdmin(LOAN_FACTORY_ROLE) == GOVERNANCE_EXECUTOR_ROLE`;
- `roleExpiry(LOAN_FACTORY_ROLE, phase9LoanFactory) == type(uint64).max`;
- `hasRole(LOAN_FACTORY_ROLE, phase9LoanFactory) == true`;
- neither the candidate broadcaster nor any undeclared account has that role; and
- no role-admin change, second grant, revocation, or other state-changing transaction
  occurred.

The grant is the last activation-topology transaction. No bootstrap, quote,
`requestRefinance`, funding, execution, cancellation, refund, policy mutation, or other
business call belongs to this control package.

### 6. Checkpoint and activation remain closed

`UNI-ADR-019` is a mandatory predecessor of both refinance implementation rows. Even
with conforming role evidence, `UNI-REFI-001` and `UNI-REFI-002` remain `TODO` and
`P9-REFI-001` remains absent until the complete bundled D1-D4 implementation,
acceptance matrix, deployment evidence, deterministic vectors, and exact-head
architecture, security, and tooling reviews pass.

The preliminary topology harness remains valid non-activating evidence because it
stops before Section 5. Activation-grade tooling may extend it only in a separately
reviewed change that preserves the exact order above and emits a distinct artifact. A
candidate topology artifact with `activation_accepted=false` or
`role_grant_performed=false` cannot satisfy an activation-grade row merely because this
ADR selected its nonce form.

### 7. Failure and reset

Wrong identity separation, chain, endpoint, initial nonce, nonce mutation, transaction
order, prediction, link, constructor, code, receipt, block hash, pre-grant role state,
grant sender, grant nonce, expiry, event, post-grant role state, extra transaction, or
production-looking input rejects the complete activation-topology attempt. Rejection
creates no accepted checkpoint and requires bounded reset to the exact genesis identity.

Reset evidence must prove candidate and governance nonces return to zero, every
prerequisite and graph address has empty code, the role grant and all logs disappear,
the exact genesis hash is restored, generated sensitive configuration is removed, and
the disposable Anvil process stops.

## Consequences

- Address prediction remains identical to the reviewed nonce-1-through-10 topology.
- The graph broadcaster remains roleless and cannot self-authorize the factory.
- The only positive factory-role transition is attributable to the separately bound
  governance executor after complete topology verification.
- The design deliberately depends on a visible Anvil-only RPC precondition and is not a
  production deployment pattern.
- No D1-D4 method, implementation checkpoint, real fund, production key, public network,
  external provider, or mainnet deployment is authorized.

## Verification

The always-run Phase 9 checker must bind this ADR, `UNI-ADR-019`, the exact selected
nonce form, identity separation, ten-CREATE order, verification-before-grant rule,
single governance grant, post-grant facts, non-activation boundary, and reset rule. Its
negative tests must reject a missing ADR, a nonce-zero candidate `RoleManager`, a grant
by the candidate broadcaster, a grant before topology verification, a changed expiry,
an extra role-admin action, or refinance completion before `UNI-ADR-019` is accepted.
