# ADR 0021: Phase 9 Atomic Refinance Authority and Activation

Status: accepted for synthetic local specification and compatibility activation

Date: 2026-07-26

## Context

ADR 0019 defines the Phase 9 refinance outcome, and `UNI-ABI-009` freezes the
external interfaces and storage declarations for `Phase9LoanFactory`,
`Phase9LoanAccount`, `CollateralCustodyV2`, `LienRegistry`,
`RefinanceCoordinator`, and `PositionManagerV2`. ADR 0020 activates the payoff
quote engine, including its constructor-bound refinance-coordinator authority.
Those decisions do not authorize the remaining stubs to invent caller authority,
policy resolution, collateral enumeration, replacement-loan facts, funding
semantics, refund behavior, replay identities, clone creation, or deployment
evidence.

The frozen coordinator exposes exactly five mutating selectors:

```text
requestRefinance(RefinanceRecord)
recordFundingCommitment(FundingCommitment)
executeRefinance(bytes32,bytes32)
cancelRefinance(bytes32,bytes32)
refundCommitment(bytes32,bytes32)
```

It has no separate offer, acceptance, rejection, or expiry selector. The frozen
record and commitment tuples also contain fields that are derived state, not
caller authority. The implementation therefore remains blocked until this
decision fixes a coherent reachable state machine and exact canonical sources.

This ADR is a boundary-only decision. It authorizes documentation, exact one-event/
two-error additive ABI review, reference models, deployment-evidence tooling,
method-level activation tooling, and later synthetic-local implementation review.
It does not activate a successful Solidity business path. `UNI-REFI-001` and
`UNI-REFI-002` remain incomplete until the implementation, evidence, independent
reviews, and bundled checkpoint all pass.

## Decision

### 1. Scope and authority hierarchy

This decision is subordinate to ADR 0019, the constitutional specifications, and
the historical `UNI-ABI-009` freeze. It refines the first atomic-refinance slice
where the frozen ABI is otherwise underspecified. If a statement in a subordinate
Phase 9 architecture document conflicts with this ADR, this ADR controls and the
subordinate document must be corrected before implementation activation.

The slice is available only when all of the following are true:

- `block.chainid == 31337`;
- the settlement token is the exact dedicated `Phase9LocalSyntheticToken`
  runtime accepted by ADR 0020;
- every loan, party, position, token balance, collateral record, lien, policy,
  signature-equivalent caller action, and deployment key is synthetic and local;
- the old and replacement loans are protocol-version-9 accounts created by the
  exact approved Phase 9 factory;
- every payoff is same-chain and every debt/lien/activation/proceeds effect is
  contained in one EVM transaction; and
- no Phase 8 bridge, message, wrapped token, satellite loan, collateral,
  cancellation, recovery, or release authority is reachable.

No database row, service, event payload, object, journal, mock response, operator,
or emergency account may supply or override a contract-authoritative value.

### 2. Frozen selector interpretation and reachable state

The five frozen coordinator mutators remain the complete first-slice selector set.
This ADR does not add an offer, acceptance, reject, or expire selector.

`REQUESTED`, `QUOTED`, and `OFFERED` remain canonical schema values for retained
off-chain proposal, quote-assembly, and offer evidence. They are not persistent
on-chain states in this selector-constrained slice and they do not transfer value,
reserve a lien, consume a quote, create debt, or authorize a lender commitment.

`requestRefinance` is the borrower's direct on-chain acceptance of the exact
preassembled proposal. A first successful call stores `ACCEPTED` with
`stateVersion == 1`. The reachable on-chain graph is:

```text
NONE -> ACCEPTED
ACCEPTED --first successful funding commitment--> FUNDING_ESCROWED
FUNDING_ESCROWED --additional partial funding--> FUNDING_ESCROWED
FUNDING_ESCROWED -> EXECUTING -> COMPLETED

ACCEPTED --borrower cancellation, no funding--> CANCELLED
ACCEPTED --expiry, no funding--> EXPIRED
FUNDING_ESCROWED --borrower cancellation or expiry before execution--> REFUNDABLE
REFUNDABLE --all commitments refunded--> REFUNDED
```

`EXECUTING` is a transaction-local reentrancy state. It may be written and emitted
inside the transaction, but a failed transaction cannot persist it. `REJECTED` is
an off-chain offer outcome in this slice. `DISPUTED` is reserved for a future
retained-contradiction decision and has no callable transition here. An
implementation must not invent either state to conceal an ordinary validation
failure.

The existing `RefinanceRequested` event retains its frozen signature. In this
slice it means that the exact borrower-accepted record was created, not that an
unaccepted value-bearing request exists.

### 3. Additive transition evidence and typed unknown errors

This ADR explicitly authorizes one additive event and exactly two additive errors,
subject to the historical ABI
remaining pinned and the compatibility checker recording the addition rather than
rewriting the freeze:

```solidity
event RefinanceStateTransitioned(
    bytes32 indexed refinanceId,
    Phase9Types.RefinanceState indexed previousState,
    Phase9Types.RefinanceState indexed nextState,
    uint64 stateVersion,
    bytes32 operationId,
    bytes32 evidenceHash
);

error UnknownFundingCommitment(bytes32 commitmentId);
error UnknownLienHandoff(bytes32 handoffId);
```

`RefinanceStateTransitioned` and `UnknownFundingCommitment` are additive items on
`IRefinanceCoordinator`/`RefinanceCoordinator`. `UnknownLienHandoff` is an additive
item on `ILienRegistry`/`LienRegistry`, which owns the `handoff(bytes32)` view.

No other event or error and no selector, tuple field, storage field, base contract,
slot, type, or field order is authorized to change by this decision. Each successful
persistent state change emits exactly one transition event. An inert exact replay
emits no second event. Reverted transitions emit no durable event.

For the request transition, `operationId` is the deterministic request-operation
ID defined below because the frozen request selector has no operation-ID argument.
For funding, it is the commitment ID. For execute, cancel, and refund, it is the
validated supplied operation ID. `evidenceHash` is an exact domain-separated
commitment to the transition-specific facts; it is never an opaque caller value.

### 4. Wire normalization and derived-field rejection

Caller-supplied derived state cannot select truth.

The Protobuf-to-EVM boundary is exact:

- every non-address `Identifier` and every `LoanId` is `0x` followed by exactly
  64 lowercase hexadecimal characters; a required-zero identifier is the exact
  all-zero spelling;
- an address-bearing `PartyId` is `evm:31337:0x` followed by exactly 40 lowercase
  hexadecimal characters;
- `new_position_manager` is raw 20-byte address data, not text;
- every other hash-bearing `bytes` field is exactly 32 bytes and nonzero where the
  proposal requires a commitment; input `request_digest` is the sole zero-length
  exception;
- `Money.units` matches `^(0|[1-9][0-9]*)$`, parses without truncation to
  `0 <= units <= type(uint256).max`, and every refinance money value has
  `asset_id.value == "asset:phase9:p9unit"`;
- that asset string maps by exact equality, not string hashing, to the resolver-bound
  value
  `0x61737365743a7068617365393a7039756e697400000000000000000000000000`;
- every timestamp has nonnegative integral seconds representable as `uint64` and
  `nanos == 0`; and
- `refinance_policy` has `policy_id == "phase9-refinance"`,
  `version == "v1"`, and an exact 32-byte nonzero `content_hash` equal to the
  policy-resolver key.

Alternate prefixes, uppercase hex, shortened or padded identifiers, signed/decimal/
exponent money, leading zeroes, a hashed asset string, fractional timestamps, policy
aliases, and lossy numeric conversions are rejected before an on-chain call.

`requestRefinance` accepts a calldata record only when:

```text
refinanceId == 0x00..00
quoteId == 0x00..00
state == NONE
stateVersion == 0
acceptedFunding == 0
executionAttempts == 0
terminalEvidenceHash == 0x00..00
```

The Protobuf `request_digest` is canonical empty bytes. It does not carry an expected
refinance ID. The caller supplies proposal facts, `newLoanId`, and the corroborative
predicted manager. `newLoanNonce` must equal the same nonzero, high-bit-clear,
less-than-`NONCE_MASK` `refinanceNonce`; it is not a separately stored counter. The
coordinator derives the quote ID, refinance ID, request operation ID, and every stored
state/result fact.

`recordFundingCommitment` accepts a calldata commitment only when:

```text
state == NONE
fundingResultHash == 0x00..00
```

The coordinator reconstructs and stores the canonical identities, state, version,
accepted funding, attempt count, funding result, and terminal evidence. A caller
cannot preselect a quote/refinance identity or pre-mark a request accepted, funded,
refundable, completed, disputed, or terminal. Nonzero or alternate derived fields
revert before any nonce, storage, allowance, token, debt, lien, position, or event
effect.

### 5. Caller authority

Caller authority is exact and method-specific:

- `requestRefinance`: `msg.sender` must equal the nonzero borrower in the proposal,
  the old account configuration, the replacement creation policy, every collateral
  record, and every lien. The call itself is borrower acceptance; no delegated or
  signature-based acceptance exists in this slice.
- `recordFundingCommitment`: `msg.sender` must equal the commitment's nonzero
  `funder`. The funder transfers only its own exact committed amount.
- `executeRefinance`: permissionless after all canonical facts are immutable and
  full funding exists. The caller cannot choose a token, recipient, amount, debt
  tuple, position, collateral ID, lien target, operation route, or calldata target.
- `cancelRefinance`: before expiry, only the canonical borrower may cancel. At or
  after the half-open expiry boundary, any caller may persist expiry/refundability
  because doing so selects no recipient or economic amount.
- `refundCommitment`: permissionless once the refinance is `REFUNDABLE`; payment
  always goes to the stored commitment funder for the stored amount.

The emergency controller may stop creation of new requests or commitments. It may
not change an accepted record, consume a quote, move a lien, alter debt, redirect a
recipient, sweep tokens, block a valid cancellation/expiry transition, or block an
already-valid refund.

The two compile-time private capability IDs are exact:

```text
CAPABILITY_PHASE9_REFINANCE_REQUEST =
  keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST")
CAPABILITY_PHASE9_REFINANCE_FUNDING =
  keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING")
```

After the local old-loan lock is acquired and before any resolver/bootstrap/quote
effect, request acceptance calls `emergencyState` with the request capability and
reverts the complete transaction when active. Funding first classifies an existing
commitment ID: exact replay returns inert and changed reuse conflicts without an
emergency lookup. Only a first new commitment checks the funding capability before
allowance, transfer, or storage effects. Execute, cancel, expiry, and refund do not
consult either capability. The constants add no public getter or selector.

### 6. Canonical loan, quote, and replacement sources

The coordinator revalidates the complete canonical graph at acceptance, each
funding effect, first execution, cancellation/expiry, and refund as applicable:

```text
LoanRegistry.loanAccount(loanId)
  == Phase9LoanFactory.loanAccount(loanId)
  == account used by the transition

LoanRegistry.protocolVersionOf(loanId) == 9
Phase9LoanFactory.positionManager(loanId)
  == account.configuration().positionManager
```

The old account is either absent or the exact registered factory clone. Within the
borrower-authenticated request transaction, the coordinator invokes the unique
bootstrap creation exception when it is absent; that exception initializes it directly
`ACTIVE/CURRENT`. Before quote issuance, the same transaction registers or validates
the bootstrap positions, custody records, and liens under exact coordinator-only
authorities. Existing exact records are accepted as inert replay; any mismatch reverts.

The replacement account must not exist when the external request begins. Its
`newLoanId`, loan-creation policy, predicted account, and predicted position manager
are independently derivable without a quote or refinance ID. It is created inside the
successful request transaction only after those two IDs are derived and is initialized
exactly once as dormant `CREATED/NONE` with zero debt. Both accounts bind the same
registry, exact token and asset, approved factory, payoff engine, coordinator, custody,
and lien registry. Their borrowers must match the proposal.

The existing `_nextRefinanceNonce[oldLoanId]` `uint64` is also the single-active-
refinance lock without a new slot or getter:

```text
ACTIVE_MASK = uint64(1) << 63
NONCE_MASK  = ACTIVE_MASK - 1

raw == 0:
  unlocked, next nonce = 1

(raw & ACTIVE_MASK) == 0 and raw != 0:
  unlocked, next nonce = raw

(raw & ACTIVE_MASK) != 0:
  locked, active nonce = raw & NONCE_MASK
```

Acceptance rejects a caller nonce with its high bit set, requires an unlocked raw
value and `request.refinanceNonce == (raw == 0 ? 1 : raw)`, rejects
`refinanceNonce >= NONCE_MASK`, and stores `ACTIVE_MASK | refinanceNonce` before any
resolver, token, registry, factory, quote engine, provider, or other effect-capable
dependency interaction. Every later nonterminal mutator re-derives the old loan and proves that
the raw value equals `ACTIVE_MASK | record.refinanceNonce`. `REFUNDABLE` retains the
lock. After all other terminal effects, `COMPLETED`, `CANCELLED`, `EXPIRED`, and final
`REFUNDED` release to `record.refinanceNonce + 1`. `NONCE_MASK` is the permanent
unlocked exhaustion sentinel and is never activated. No addition wraps and no other
request can issue or share a quote while the flag is active. Exact terminal replay is
recognized before lock-owner validation so release does not break idempotent replay.

The exact acyclic `requestRefinance` sequence is:

1. perform only pure calldata normalization, derived-zero checks, local-chain syntax,
   nonzero old-loan-key validation, and exact `newLoanNonce == refinanceNonce` checks;
2. require the old-loan lock to be unlocked, match the high-bit-clear next nonce, and
   store its active encoding before any resolver, token, registry, factory, quote
   engine, provider, or other effect-capable dependency interaction, so concurrent/same-quote,
   reentrant, and exact-repeat requests fail before another quote can issue;
3. call the external resolvers and validate the borrower, proposal, policies,
   `newLoanId`, new-loan nonce, predicted account/manager, and replacement absence;
4. validate the exact active old account or, when absent, invoke the factory's unique
   resolver-bound bootstrap mode; then atomically register or validate its policy-bound
   bootstrap positions, custody, and liens; exact existing records are inert and
   changed records conflict;
5. invoke the constructor-bound payoff engine with the proposal's `expiresAt` as the
   quote `validUntil`, then match every returned component, beneficiary, route,
   version, amount, and exact `quote.validUntil == proposal.expiresAt` against the
   proposal economics;
6. derive the quote ID, refinance ID, and request operation ID from their acyclic
   preimages;
7. call the factory as the registered coordinator to create and initialize the exact
   dormant deterministic replacement clones, then verify their registration, code,
   configuration, manager, and zero debt; and
8. store the reconstructed `ACCEPTED` record at version one and emit the frozen request
   event plus the typed transition event.

ADR 0023's exact compiler-linked coordinator-to-library calls are an internal
code-partition mechanism for performing these steps, not a resolver or effect-capable
dependency interaction. Its fixed `RequestModule.begin` dispatch performs only step 1
and the step-2 lock write. No resolver, token, registry, factory, quote engine,
provider, or other callback-capable dependency is called before that write. The fixed
validation preflight and request completion dispatches occur only after the lock is
active, and any failure rolls back the dispatch, lock, and complete transaction.

Any revert rolls back the reserved nonce, bootstrap registration, quote issuance,
clones, registry entries, state, and events. A successful request is not idempotent:
an exact repeat carries the consumed old-loan refinance nonce and is rejected at step
2 before issuing another quote. Any unauthorized borrower or resolver failure after
lock acquisition reverts the lock write with the transaction. First execution consumes the quote with the exact old
debt-state version, derived refinance ID, and domain-separated source-event ID. ADR
0020 exact consume replay remains valid after successful payoff changes live debt.

### 7. Typed asset resolver

The frozen `_assetRegistry` address is the immutable local asset source. Its exact
internal-only surface is:

```solidity
interface IPhase9RefinanceAssetSource {
    function resolveRefinanceAsset(bytes32 settlementAssetId)
        external
        view
        returns (
            address settlementToken,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        );

    function resolveCustodyAsset(bytes32 assetId)
        external
        view
        returns (
            address token,
            uint8 decimals,
            bytes32 runtimeCodeHash,
            bool exactBalanceDelta,
            bool active
        );
}
```

The resolver address must contain code. The returned asset is accepted only when
`active` and `exactBalanceDelta` are true, `decimals == 6`, the token equals the
coordinator and both loan configurations, and `runtimeCodeHash` equals both the
deployed code hash and the exact committed Phase 9 local-token runtime hash. The
coordinator independently performs the code-hash and chain checks. A metadata,
interface, or resolver-only match is insufficient.

The asset source grants no transfer, allowance, mint, burn, rescue, freeze, or
recipient authority. Its tuple is fully revalidated on first execution.

`resolveCustodyAsset` is the distinct bootstrap-collateral path. It need not return the
settlement token or six decimals, but it must return a nonzero deployed synthetic-local
token with `active` and `exactBalanceDelta`, and its runtime hash must equal the
deployed code hash and bootstrap custody identity. It is revalidated before each first
custody transfer and exact existing-record replay.

### 8. Typed creation, bootstrap, and refinance-policy resolvers

The frozen `_policyRegistry` address is the immutable first-slice refinance-policy
source. Its exact internal-only surface uses the frozen Phase 9 tuple types:

```solidity
interface IPhase9RefinancePolicySource {
    function resolveLoanCreation(bytes32 policySetHash, bytes32 loanId)
        external
        view
        returns (
            Phase9Types.LoanConfiguration memory configuration,
            uint8 creationMode,
            bytes32 bootstrapId,
            bool active
        );

    function resolveBootstrap(bytes32 bootstrapId)
        external
        view
        returns (
            bytes32 policySetHash,
            bytes32 loanId,
            Phase9Types.DebtState memory initialDebt,
            Phase9Types.Tranche[] memory initialTranches,
            Phase9Types.Position[] memory initialPositions,
            Phase9Types.CustodyRecord[] memory custodyRecords,
            Phase9Types.Lien[] memory liens,
            bool active
        );

    function resolveRefinancePolicy(bytes32 refinancePolicyHash)
        external
        view
        returns (
            bytes32 boundOldPolicySetHash,
            bytes32 boundNewPolicySetHash,
            bytes32 proposedTermsHash,
            uint64 maximumValidity,
            uint32 maximumCommitments,
            bool active,
            bytes32[] memory collateralIds,
            Phase9Types.DebtState memory replacementDebt,
            Phase9Types.Tranche[] memory replacementTranches,
            Phase9Types.Position[] memory replacementPositions
        );
}
```

`creationMode` is closed: `1 == LOCAL_BOOTSTRAP` and
`2 == REFINANCE_REPLACEMENT`; zero and every other value are invalid. A bootstrap
creation has a nonzero reconstructed `bootstrapId`; a replacement creation has
`bootstrapId == 0`. Both returned configurations are complete immutable facts and
must match factory, registry, chain-31337 asset/token, borrower, loan ID, predicted
position manager, custody, lien registry, payoff engine, and coordinator. The factory
does not accept a caller-authored configuration that differs from this resolver.

`resolveBootstrap` is valid only for the one local bootstrap ID and returns the exact
active old debt, original tranche/position issuance records, and complete custody/lien
vectors. The debt is `ACTIVE/CURRENT`, has zero active refinance/restructure IDs, and
matches the quoteable old loan. The original position owner is exactly the proposal
and quote `oldLender`; the canonical beneficiary, tranche claims, position claims, and
aggregate claim-bearing debt match the old debt and payoff route, with no extra or
alternate beneficiary. Tranches are nonempty and at most 8; positions are nonempty and
at most 32; custody and lien arrays have identical IDs and nonzero equal lengths at
most 16. Every vector is strictly ordered and unique.

`maximumValidity` is nonzero and `1 <= maximumCommitments <= 32`. The refinance policy
has `1..16` collateral IDs, `1..8` replacement tranches, and `1..32` replacement
positions. These are hard protocol caps, not policy-increasable defaults. The resolver address,
policy hash, old and new policy-set hashes, proposed terms hash, collateral vector,
replacement debt, tranches, and positions are immutable for an accepted refinance.
The coordinator hashes each dynamic value independently and reconstructs:

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

The replacement debt returned by the refinance policy is an activation template with
`activeRefinanceId == 0`. The zero prevents a circular policy/refinance identity. After
the coordinator derives the refinance ID, it copies the template and sets only
`activeRefinanceId = refinanceId` for the later activation call; every other field is
unchanged.

The returned policy is accepted only when `active` is true and every binding equals
the proposal, internally issued quote, old account, resolved replacement
configuration, factory, predicted position manager, asset resolver, and lien/custody
sources. A caller-provided policy hash is never trusted without reconstruction.

### 9. Ordered collateral vector

The policy resolver supplies the complete collateral-ID vector. The vector must have
`1..16` entries, remain within the accepted policy, be strictly increasing by raw
`bytes32`, contain no zero or duplicate ID, and be identical at acceptance and
execution.

For each ID, the coordinator reads the exact custody and lien records and requires:

- custody status `HELD`;
- matching nonzero asset ID, token or manager, vault, quantity, and borrower;
- lien status `ACTIVE`, no pending refinance or target, and the request's prior
  lien version;
- `seniorLoanId == oldLoanId`; and
- registry and custody addresses equal those bound by both loan accounts.

During the unique first request, a missing record is created only from the exact
bootstrap vector using the operation identities in Section 11. An already-present
exact record is inert replay. A present record with any changed field conflicts and
reverts the complete request. A later request never manufactures replacement
collateral facts.

Bootstrap custody is economically backed in that same request transaction. The
bootstrap resolver's returned `CustodyRecord.identityHash` is exactly:

```text
custody_identity_hash = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
  chainid,
  collateral_custody,
  asset_registry,
  bootstrap_custody_operation_id,
  collateral_id,
  asset_id,
  token,
  token_runtime_code_hash,
  token_decimals,
  true, // exactBalanceDelta
  borrower,
  quantity
))
```

The coordinator ignores any alternate operation proposal and recomputes the exact
nonzero `bootstrap_custody_operation_id` from Section 11 before calling custody.
`CollateralCustodyV2` first authenticates `msg.sender` as the coordinator resolved
from its immutable lien registry, requires that nonzero passed operation ID, calls
`resolveCustodyAsset(asset_id)` through its constructor-bound asset source, requires
token/runtime/active/exact-delta agreement, independently reads the deployed code
hash, and reconstructs this identity from the operation ID and record/resolver facts.
This is required to equal `CustodyRecord.identityHash` before transfer or first state
effects. This is
separate from Section 7's settlement resolver and permits a distinct synthetic
collateral token without treating it as the refinance settlement asset. The identity commits each collateral
ID to an active chain-31337 exact-balance synthetic token/runtime. For a missing record,
`recordCustody` uses the canonical borrower's pre-approved allowance to
`transferFrom` the exact quantity into `CollateralCustodyV2`. After all checks, it
marks the operation processed, stores `HELD`, and increases `totalCustody(assetId)`
with checked arithmetic before the external transfer; it then verifies exact borrower
and custody before/after balance deltas. Any transfer or delta failure rolls back those
effects. Only after that successful custody effect may the coordinator register the
lien. Fee, rebase, hook/callback, wrong code,
wrong asset/token, insufficient allowance/balance, delta mismatch, overflow, or
reentrancy reverts the quote, clones, and every bootstrap effect.

Exact same-operation/same-record replay verifies record identity, code/asset binding,
attributed holdings, aggregate `totalCustody`, and active lien without a second
transfer or event. Reuse of an operation ID with a changed record, or use of an
alternate operation ID for an existing collateral record, conflicts. Unattributed
direct surplus never substitutes for the record's exact custody. All bootstrap loops
are bounded by the 16-collateral cap and guarded before the first external token call.

The collateral-set hash is exactly the ADR 0019/data-layout ordered commitment over
each `(collateralId, assetId, quantity, vault, borrower, priorLienVersion)` tuple.
The coordinator does not accept a caller-provided array and does not infer a list by
enumerating unbounded registry storage.

Execution calls `beginHandoff` and `completeHandoff` for every collateral ID in the
same sorted order. A pending target is never an enforceable claim. No external token
transfer or callback is made while a lien is pending. Failure for any collateral
reverts every earlier handoff in the transaction.

### 10. Replacement debt, tranche, and position tuple

The policy resolver returns the complete replacement state. The coordinator requires:

- lifecycle `ACTIVE` and servicing state `CURRENT` for the activation input;
- nonzero terms and debt-state versions fixed by the policy, nonzero schedule,
  checked commencement and maturity, and template `activeRefinanceId == 0`; the
  coordinator sets the already-derived refinance ID only in the activation copy;
- outstanding principal equal to `newPrincipal`;
- zero accrued interest, capitalized interest, fees, penalties, recoverable costs,
  unapplied credit, covered loss, realized loss, write-off, later recovery, and
  active restructure ID at first activation;
- `1..8` strictly ordered tranches and `1..32` strictly ordered positions;
- unique nonzero tranche and position IDs;
- every position references one returned tranche, has state `ACTIVE`, has
  `owner == commitment.funder`, and has claim equal to that associated funded
  commitment;
- every funded commitment maps to exactly one returned position and no returned
  position lacks a funded commitment; and
- aggregate tranche original/outstanding claims, aggregate position claims,
  accepted funding, funding amount, and new principal are all equal.

For the first slice:

```text
newPrincipal == fundingAmount
fundingAmount == oldNetPayoff + refinanceFee + borrowerProceeds
```

Oversubscription, under-allocation, retained cash, capitalized interest at activation,
unfunded credit enhancement, cross-asset funding, and post-acceptance position
substitution are prohibited.

The additive Protobuf field `bytes new_position_manager = 24` is permitted only as
corroborative reconstruction input. It must contain exactly 20 bytes, decode to a
nonzero EVM address, and equal the predicted `newPositionManager` reconstructed from
the approved factory clone salt, resolved creation configuration, Solidity proposal,
and policy bindings. Length, nonzero, and equality checks occur before refinance-ID
reconstruction and before every state or economic effect. The field never overrides
or supplies on-chain authority. Zero-length and 19-, 21-, or 32-byte values, a 20-byte
zero address, and a substituted 20-byte address are mandatory negative cases.

### 11. Deterministic factory clones and local bootstrap

`Phase9LoanFactory` may create only deterministic, immutable minimal clones of the
constructor-bound account and position-manager implementations on chain `31337`.
The replacement loan identity is derived before any quote or refinance identity:

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
```

The clone salts are:

```text
loan_account_salt = keccak256(abi.encode(
  "UNIFIED_PHASE9_LOAN_ACCOUNT_CLONE_V1", loan_id
))

position_manager_salt = keccak256(abi.encode(
  "UNIFIED_PHASE9_POSITION_MANAGER_CLONE_V1", loan_id
))
```

Predicted and actual addresses must match before registration. Implementations and
clones must contain code. Initialization occurs exactly once in the same factory
transaction, and any initialization or registration failure reverts clone creation
and every mapping/nonce effect.

The loan creation ID is acyclic and covers bootstrap and replacement modes:

```text
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
```

No quote ID or refinance ID appears in `new_loan_id` or either clone salt.
`creation_id` is derived later and includes the frozen
`LoanCreationRequest.refinanceId` as `refinance_id_context`: zero for the
request-internal local-bootstrap call and the already-derived refinance ID for the
request-internal replacement call. This is acyclic because new loan/predicted clones,
then quote/refinance ID, then creation ID are derived in that order. The factory still
independently resolves every creation fact.

Because the coordinator has neither implementation address in storage and the frozen
factory exposes no prediction selector, its fresh internal `LoanCreationRequest`
supplies `creationId == 0`. The factory alone knows both constructor-bound
implementations, derives both predictions and the canonical nonzero creation ID, and
stores a memory-canonicalized request containing that ID. A direct exact factory replay
later supplies that complete stored canonical request. Fresh caller-authored nonzero
creation IDs are invalid; this convention does not add a selector or let the
coordinator choose an identity.

The factory-global loan nonce starts at one, advances once only on successful unique
creation, cannot wrap, and is bound to the creation record. There is no separate
replacement new-loan counter: the coordinator requires
`new_loan_nonce == refinance_nonce`, carries that low-63-bit per-old-loan value into
the stored refinance and replacement creation request, and advances it only through
the tagged refinance-lock rules in Section 6. Local bootstrap is the explicit
exception and uses `source_old_loan_id = 0`, `refinance_id_context = 0`, and
`new_loan_nonce = 0`; replacement creation uses the source old-loan ID, the derived
nonzero refinance-ID context, and the equal nonzero refinance/new-loan nonce. Exact
creation replay returns the stored account/manager; changed reuse conflicts.

The unique bootstrap identity and request-time operation identities are:

```text
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
  chainid, refinance_coordinator, bootstrap_id, old_loan_id,
  loan_account, keccak256(abi.encode(initial_debt))
))

bootstrap_tranche_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_TRANCHE_V1",
  chainid, refinance_coordinator, bootstrap_id, old_loan_id,
  position_manager, tranche_id
))

bootstrap_position_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_POSITION_V1",
  chainid, refinance_coordinator, bootstrap_id, old_loan_id,
  position_manager, position_id
))

bootstrap_custody_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
  chainid, refinance_coordinator, bootstrap_id, old_loan_id,
  collateral_custody, collateral_id
))

bootstrap_lien_operation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_BOOTSTRAP_LIEN_V1",
  chainid, refinance_coordinator, bootstrap_id, old_loan_id,
  lien_registry, collateral_id, lien_version
))
```

Only `bootstrap_custody_operation_id` is carried by a frozen selector and is therefore
contract-authoritative replay and identity input. The activation, tranche, position,
and lien operation IDs are deterministic reference/evidence correlation hashes only:
their frozen selectors carry no operation-ID argument, so an implementation must not
pretend to receive, invert, store as processed, authorize with, or reject by those
hashes. Account/manager/lien idempotency and conflicts instead use their initialized
flag and exact canonical tranche, position, collateral, and full-record identities.

Inside the canonical borrower's authenticated `requestRefinance` transaction, only
the registered coordinator may call `createLoan` for the one `LOCAL_BOOTSTRAP`
record. The factory derives the borrower and complete configuration solely from the
active creation/bootstrap resolver records; it never trusts coordinator-supplied
configuration, `tx.origin`, or a forwarded caller identity. This is the sole factory
initialization exception: the factory initializes the old account directly with the
exact `ACTIVE/CURRENT` bootstrap debt so it can be quoted. It initializes the old
position manager but does not register tranches/positions, custody, or liens.
`activateReplacementLoan` is prohibited for bootstrap because it would require a
nonexistent refinance ID and emit false replacement evidence.

Inside the first `requestRefinance`, the registered coordinator alone registers or
validates the exact bootstrap tranches/positions, custody, and initial liens before
quote issuance. Missing exact records are created; existing exact records are inert;
any mismatch reverts. Bootstrap cannot run off chain `31337`, cannot use a
production-looking token or party, cannot create a second bootstrap record, and cannot
be used after any non-bootstrap Phase 9 loan exists. It is test-fixture construction,
not origination, underwriting, disbursement, or live lending authority.

Every `REFINANCE_REPLACEMENT` account and manager is instead created inside the
accepted request transaction by the registered coordinator after the refinance ID is
derived. The factory initializes only a dormant `CREATED/NONE` account with every debt
amount, version/time/schedule field, and active operation ID zero. Creation transfers
no value and creates no lender position, enforceable claim, custody change, or senior
lien. The replacement activation template remains policy-bound for execution.

Authority is exact:

- both bootstrap and replacement modes of `Phase9LoanFactory.createLoan` are callable
  only by the registered coordinator inside the borrower-authenticated request;
  borrower/configuration authority comes only from the active resolver record and
  exact creation replay returns stored clones;
- `Phase9LoanAccount.initialize` is factory-only;
- `recordRefinancePayoff` and `activateReplacementLoan` are callable only by the
  account-configured refinance coordinator;
- `PositionManagerV2.initialize` is factory-only, while `registerTranche` and
  `issuePosition` are callable only by the coordinator in its account configuration;
- `CollateralCustodyV2.recordCustody` authorizes only the coordinator resolved from
  its immutable lien registry; and
- every `LienRegistry` mutator authorizes only its immutable
  `registeredRefinanceCoordinator`.

No fixture allocator, borrower after clone creation, factory operator, emergency
controller, database, script, or resolver may exercise those coordinator-only paths.

### 12. Funding, partial funding, and escrow

Funding commitments may arrive separately. Each commitment has nonzero amount, funder,
position ID, tranche ID, nonce, and exact digest. The identity remains the frozen
`UNIFIED_REFINANCE_FUNDING_COMMITMENT_V1` preimage. Its digest is:

```text
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

The coordinator accepts the first commitment only in `ACCEPTED` and later
commitments only in `FUNDING_ESCROWED`, always before `expiresAt`, while the
commitment count is below both the policy maximum and the hard cap of 32 and
`acceptedFunding + amount <= fundingAmount`. It performs `transferFrom` and requires
exact coordinator and funder balance deltas. Immediately before `transferFrom`, the
coordinator provisionally applies the `FUNDED` commitment, funding-result hash,
ordered commitment ID, accepted funding, escrowed units, processed-operation marker,
state, and version as checks-effects-interactions reentrancy protection. The
commitment is considered recorded only after `transferFrom` succeeds and both exact
balance deltas pass. Any token revert, false/malformed return, insufficient balance,
allowance failure, or delta mismatch reverts the complete transaction, including
every provisional write, allowance change, token balance, and event.

Funding dependency reads use bounded `staticcall`, so resolver and emergency
callbacks inherit static execution. A callback may enter a coordinator wrapper and
run validation, but an otherwise-valid state-changing path halts at its first write;
no callback can complete a durable state change. The only token whose balance,
allowance, or `transferFrom` may be called is the exact chain-31337 settlement token
whose address and runtime code hash are frozen by the coordinator and asset record.
An asset record that substitutes a callback-capable token is rejected before any
`balanceOf`, `allowance`, or `transferFrom` call is made to that substitute. This
proof exercises the combined address-and-runtime identity check; it does not claim
to isolate the runtime-code-hash branch from the address-equality branch.

The first successful funding commitment changes the refinance to
`FUNDING_ESCROWED`; additional partial funding remains `FUNDING_ESCROWED`. Custody
of any accepted value therefore always has an explicit escrow state. Partial funding
never activates debt, creates a lien, consumes a quote, or pays a recipient. Exact
full funding leaves the refinance `FUNDING_ESCROWED` and makes execution eligible.
A failed or duplicate transfer creates no commitment, escrow state, or
accepted-funding increase. Funding after full funding or expiry is rejected.

### 13. Cancellation, expiry, and refunds

Expiry is the half-open boundary `block.timestamp >= expiresAt`. Acceptance and funding
require `block.timestamp < expiresAt`; execution also requires the strict pre-expiry
side. The accepted proposal duration must be nonzero and no greater than the policy
maximum. The coordinator supplies the same timestamp to internal quote issuance and
stores a refinance only when `RefinanceRecord.expiresAt == quote.validUntil` exactly;
there is no independent or earlier refinance deadline.

The closed internal cancellation reason uses exact `uint8` values:

```text
NONE = 0                 // always invalid for cancel/expiry
BORROWER_CANCELLED = 1
EXPIRED = 2
```

Before any funding, borrower cancellation stores `CANCELLED`; permissionless expiry
stores `EXPIRED`. Each is terminal and stores the exact cancellation/expiry result in
`terminalResult` and `terminalEvidenceHash`, and releases the owned old-loan lock. If
any funding has been accepted, borrower cancellation before
execution or permissionless expiry stores `REFUNDABLE`. A failed execution transaction
does not itself make funding refundable; it restores the valid pre-execution state so
the same immutable execution can be retried while unexpired or cancelled/expired into
refundability.

Before persisting any cancellation/expiry transition, the coordinator calls the
already-activated payoff engine's `invalidateQuote(quoteId, cancelOperationId)`.
Before expiry the engine persists `INVALIDATED`; at/after the shared refinance/quote
boundary it persists `EXPIRED`.
The cancellation result binds the exact quote disposition and source ID. Any quote
failure reverts the entire cancellation/refundability transition. An exact cancel
replay is detected before the external call and is inert; changed reuse conflicts.
This terminalizes the live quote immediately so a later valid old-loan request is not
blocked until the former expiry.

Each `FUNDED` commitment is refunded separately to its stored funder. A successful
refund requires exact coordinator and funder balance deltas, changes that commitment
to `REFUNDED`, and subtracts exactly its amount from accepted funding and escrowed
units. `REFUNDABLE` is nonterminal: `terminalResult` remains the canonical zero result
and `terminalEvidenceHash` remains zero. The refinance remains `REFUNDABLE` until all
funded commitments are refunded, then becomes terminal `REFUNDED` with zero attributed
escrow, releases the owned old-loan lock, and stores the exact final refund-completion hash in both terminal evidence and
the terminal result. That aggregate is reconstructed from the bounded ordered
commitment IDs and each stored immutable commitment identity, digest, funder, amount,
funding-result hash, and `REFUNDED` state plus zero accepted funding/escrow; it does not
assume an unpersisted refund-result vector. It also binds the stored terminal
`recordedAt`, which equals the last-refund transition time. Individual refund-result/
time evidence remains in its transition event, and `fundingResultHash` is never repurposed. Exact
refund replay has no second transfer or event; changed reuse conflicts. A consumed
commitment or completed refinance cannot refund.

A dormant replacement clone created for a request is bound by the factory creation
record to exactly that derived refinance ID. `activateReplacementLoan` is reachable
only from that coordinator while the same refinance is transaction-locally
`EXECUTING`. `CANCELLED`, `EXPIRED`, `REFUNDABLE`, and `REFUNDED` therefore make the
clone permanently unactivatable; it cannot be recycled into another refinance.

### 14. Atomic execution order

First execution requires `FUNDING_ESCROWED`, exact full funding, an unexpired accepted
record, the unconsumed exact quote, unchanged old debt, unchanged policy/asset/collateral
facts, an inactive exact replacement account whose factory creation record binds this
refinance ID, and the complete funded position tuple.
It performs, in order:

1. validate the operation ID and enter the transaction-local reentrancy state;
2. re-resolve and verify every canonical source;
3. consume the exact payoff quote;
4. transfer principal and accrued interest to the quote-bound old lender and the
   credit-netted fee/penalty amount to the quote-bound fee recipient;
5. call `recordRefinancePayoff` on the old account; after writing the exact closed
   terminal debt state, that registered account calls the existing
   `LoanRegistry.markTerminal(oldLoanId)` path, verifies the registry is terminal,
   and returns only if both canonical states agree;
6. hand off every senior lien in sorted collateral order without releasing custody;
7. register tranches and positions and activate the replacement debt exactly once;
8. transfer the disclosed refinance fee to the constructor-bound treasury fee
   recipient;
9. transfer borrower proceeds only to the canonical borrower;
10. consume every funded commitment and clear the refinance's accepted funding and
    escrowed units;
11. store terminal execution/result evidence and `COMPLETED`, and release the owned
    old-loan lock; and
12. prove exact recipient and coordinator operation balance deltas.

No arbitrary target, token, recipient, amount, allowance recipient, calldata, payable
ETH, hook, callback, or operator-selected fallback exists. Any revert restores quote,
funding, debt, positions, lien, recipients, operations, and coordinator attribution.

The old debt after payoff is exact:

```text
lifecycle = CLOSED
servicingState = TERMINAL
outstandingPrincipal = 0
accruedInterest = 0
capitalizedInterest = 0
accruedFees = 0
accruedPenalties = 0
recoverableCosts = 0
unappliedCredit = 0
coveredLossExposure = 0
realizedLoss = 0
writtenOffAmount = 0
recoveredAfterWriteoff = 0
activeRefinanceId = derived refinanceId
activeRestructureId = 0
debtStateVersion = prior debtStateVersion + 1
stateNonce = prior stateNonce + 1
```

The additions are checked and cannot wrap. Terms version, commencement time, maturity
time, schedule hash, agreement, policy, and configuration remain unchanged. Before
payoff the coordinator requires the old registry record to be nonterminal and to map
the old loan to the exact factory/account identity. After the debt write,
`recordRefinancePayoff` calls `LoanRegistry.markTerminal(oldLoanId)` from that
registered old account and requires `isTerminal(oldLoanId) == true`; the coordinator
then independently re-verifies the terminal flag and unchanged identity before
continuing. A preterminal registry record, mismatched account, unauthorized or failed
mark, false postcondition, or reentrant registry behavior reverts the transaction,
including the debt write, quote consumption, and preceding payouts.

Old tranche/position structs and their checkpoints are immutable historical issuance
facts, never live receivables by themselves. Payoff does not rewrite their face claim,
owner, voting power, or stored `ACTIVE` issuance state, does not set `EXHAUSTED`, and
does not add or repurpose an exhaustion selector. Their enforceable outstanding right
is derived from canonical account debt:

```text
claim_bearing_debt = outstandingPrincipal
                   + accruedInterest
                   + capitalizedInterest
                   + accruedFees
                   + accruedPenalties
                   + recoverableCosts

effectiveClaim(position_id) = 0 and effectiveVotingPower(position_id) = 0 when:
  LoanRegistry reports the loan terminal, or
  lifecycle == CLOSED, or
  servicingState == TERMINAL, or
  claim_bearing_debt == 0

otherwise, the bounded historical issuance share is interpreted only through the
current canonical debt and applicable active-loan policy
```

Successful payoff therefore has both `LoanRegistry.isTerminal(oldLoanId) == true`
and account `CLOSED/TERMINAL`; this registry fact is bound into the old-debt result and
effective-rights evidence rather than inferred from the account alone.

All additions are checked. Before any effective-right use, every consumer re-resolves
`positionManager.loanId -> factory.positionManager(loanId) == positionManager ->
LoanRegistry.loanAccount(loanId) == factory.loanAccount(loanId) ==
positionManager.loanAccount`, then joins the current canonical debt. A manager-only,
historical-block, or checkpoint-only lookup can never authorize a current action.

The joined-state gate applies to payment/distribution, position transfer,
snapshot/vote/restructuring, payoff quote, lien/collateral, liquidation, recovery,
protection, and every authorization consumer. Each must fail when the account is
terminal or has zero claim-bearing debt. Unopened transfer/voting and later-package
mutators retain their freeze stubs in this package. CI must prohibit activating any
consumer without malicious stale-`ACTIVE` post-payoff tests. No downstream consumer
may interpret `position()`, `positionClaimAt()`, tranche `outstandingClaim`, a vote
checkpoint, or any historical getter alone as outstanding debt, a current vote, or an
enforceable receivable. Conservation is evaluated over effective claims plus exact
canonical debt, never raw issuance face values.

### 15. Donation and residue semantics

An ERC-20 holder can transfer tokens directly to the coordinator without calling it.
Therefore global `settlementToken.balanceOf(coordinator) == 0` is not a valid safety
precondition or terminal invariant.

The coordinator recognizes liabilities only from successful recorded funding balance
deltas. For each refinance:

```text
recognized escrow liability == escrowedUnits(refinanceId)
```

Completion or full refund requires that refinance's recognized escrow liability to be
zero and requires the exact expected net coordinator balance delta for the operation.
An unsolicited surplus:

- creates no commitment, accepted funding, escrow liability, position, proceeds,
  refund right, revenue, journal, or execution authority;
- cannot satisfy a funding shortfall;
- cannot block acceptance, execution, cancellation, expiry, or refund;
- is excluded from refinance and ledger reconciliation; and
- can never be swept, rescued, assigned, refunded, or transferred by any Phase 9
  coordinator function.

The absence of a rescue path is deliberate. Forced or donated residue remains outside
the protocol's recognized economics and is disposed only by resetting the bounded local
chain.

### 16. Domain-separated operations and terminal evidence

Every operation ID is recomputed and matched before mutation:

```text
request_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REQUEST_OPERATION_V1",
  chainid, coordinator, refinance_id
))

execute_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_EXECUTE_OPERATION_V1",
  chainid, coordinator, refinance_id, quote_id, debt_state_version
))

cancel_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
  chainid, coordinator, refinance_id, state_version, expires_at,
  cancellation_reason
))

refund_operation_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_REFUND_OPERATION_V1",
  chainid, coordinator, refinance_id, commitment_id, amount, funder
))
```

`cancellationReason` is a closed internal enum for borrower cancellation or expiry;
it is not caller-selected calldata and uses the exact Section 13 values. Funding uses
its commitment ID as the operation identity. An operation ID cannot be reused across
action domains.

Replay behavior is method-specific:

| Mutator | Exact repeat | Changed reuse/conflict |
| --- | --- | --- |
| `requestRefinance` | Rejects on the already-consumed old-loan refinance nonce before issuing another quote | Rejects before quote, clone, or state effects |
| `recordFundingCommitment` | Returns inertly with no transfer, write, counter, result, or event | Same commitment ID with changed facts reverts `RefinanceReplayConflict` |
| `executeRefinance` | Returns the stored terminal result with no write, call, transfer, counter, or event | Changed reuse of its operation ID reverts `RefinanceReplayConflict` |
| `cancelRefinance` | Returns inertly with no second terminal/transition evidence | Changed reuse cannot alter reason, terminal facts, or refundability and conflicts |
| `refundCommitment` | Returns inertly with no second transfer, write, result, or event | Changed reuse cannot redirect funder/amount and conflicts |
| `Phase9LoanFactory.createLoan` | Returns the stored exact account and manager clones | Same creation identity with changed request/resolver facts conflicts |
| bootstrap custody/lien/position setup | Exact existing record/operation is inert | Any changed record under the same identity conflicts and reverts the request |

Only successful exact execution and factory creation replays return stored nonzero
results. Request replay is deliberately rejected, not treated as idempotent, because
issuing a second quote would create a distinct canonical quote nonce.
For funding, execute, cancel, and refund, exact replay recognition occurs before
current-state and old-loan-lock ownership checks so terminal lock release cannot turn a
valid retry into a false conflict. Changed reuse never receives that bypass.

Execution-event, component-payout, recipient-balance-delta, old-debt-result,
new-activation-result, lien-handoff-vector, funding-result, refund, terminal-result,
cancellation/expiry-result, final-refund-completion, and transition-evidence hashes use
distinct exact `UNIFIED_*_V1` domains documented in
`phase-9-refinance-reference-evidence.md`. `CANCELLED`, `EXPIRED`, `REFUNDED`, and
`COMPLETED` each store a canonical `terminalResult` and matching
`terminalEvidenceHash`; `REFUNDABLE` is nonterminal and stores neither. Opaque
caller-supplied evidence is prohibited.

View behavior is exact and does not materialize state:

- unknown `refinance`, `terminalResult`, `commitmentIds`, or `escrowedUnits`
  refinance IDs revert `UnknownRefinance`;
- an unknown commitment reverts
  `UnknownFundingCommitment(commitmentId)`;
- an unknown lien reverts the historical `UnknownLien(collateralId)`;
- an unknown handoff reverts `UnknownLienHandoff(handoffId)`;
- `terminalResult` for a known nonterminal refinance returns the canonical all-zero
  result; and
- membership and processed-operation views may return `false` for unknown keys where
  their frozen return type is boolean.

### 17. Method-level implementation activation

Historical ABI and storage artifacts remain immutable. Activation is method-level so
later Phase 9 packages cannot silently enable unrelated account or position behavior.
The refinance package may later activate only:

| Contract | Authorized methods |
| --- | --- |
| `Phase9LoanFactory` | `createLoan` |
| `Phase9LoanAccount` | `initialize`, `recordRefinancePayoff`, `activateReplacementLoan` |
| `CollateralCustodyV2` | `recordCustody` |
| `LienRegistry` | `registerLien`, `beginHandoff`, `completeHandoff` |
| `RefinanceCoordinator` | all five frozen mutators |
| `PositionManagerV2` | `initialize`, `registerTranche`, `issuePosition` |

Every other mutator retains the exact `Phase9ImplementationNotFrozen()` body until its
own later activation decision and checkpoint. Read methods may implement fail-closed
unknown-ID behavior required to support these activated methods without granting a
state-changing path.

The checkpoint must support historical method revisions, monotonic activated-signature
sets, and multiple required backlog IDs. The coordinator value path is one bundled gate:

```text
required backlog IDs = [UNI-REFI-001, UNI-REFI-002]
```

Neither row may become `DONE` and no coordinator implementation checkpoint may become
`PASS` until atomic execution, partial funding, cancellation, expiry, every refund exit,
replay, adversarial tests, deployment evidence, and independent architecture, security,
and tooling reviews all pass against the same reviewed commit.

### 18. Top-level CREATE and role-initialization deployment evidence

ADR 0020's nested pair-deployer mechanism remains valid evidence for the already
accepted payoff-only checkpoint. It is not the deployment mechanism for the activated
refinance package because constructor growth and the lien/coordinator binding require a
larger reviewed sequence.

The refinance candidate uses one fresh synthetic local broadcaster as the
`GOVERNANCE_EXECUTOR_ROLE` account and a distinct predeclared synthetic local
administrator in the `RoleManager` constructor. The complete nonce-ordered sequence is
all top-level sequential `CREATE` transactions first, followed by exactly one zero-value
initialization call from that broadcaster to
`RoleManager.grantRole(LOAN_FACTORY_ROLE, phase9Factory, type(uint64).max)`. The grant
occurs after every address-sensitive creation and before any loan registration,
bootstrap, quote, or other business action. No pair deployer, `CREATE2` top-level
dependency, setter, proxy, rebinding, late open authorization, undeclared role grant,
role-admin change, or post-hoc administrative repair exists. Before broadcast, the
evidence assembler fixes the broadcaster, distinct administrator, starting and final
nonce, complete transaction order, predicted addresses, compiler artifacts,
constructor arguments, grant calldata and hash, and code hashes. Components that must
authorize the coordinator are created with the coordinator address predicted from the
exact later broadcaster nonce. The quote engine is created immediately before the
coordinator; the coordinator receives the actual engine and every already-created exact
dependency.

Accepted evidence proves every transaction input, sender, nonce, zero value, successful
receipt, block hash, applicable CREATE address, runtime code, constructor argument,
relevant frozen storage slot, and reciprocal behavioral authorization through canonical
EIP-1898 block-hash reads. For the final initialization call it additionally proves the
exact target/calldata/hash, the exact `RoleGranted(LOAN_FACTORY_ROLE, phase9Factory,
type(uint64).max, broadcaster)` log, `roleExpiry == type(uint64).max`, `hasRole == true`,
and absence of any other role grant or role-admin change. An intervening or undeclared
transaction, wrong nonce, wrong prediction, wrong code, wrong constructor or grant fact,
failed/missing/late initialization, post-hoc repair, replacement block, non-loopback RPC,
dry run, or production-looking input rejects activation and requires bounded local
reset.

Top-level deployment uses sequential CREATE. The deterministic per-loan clones in
Section 11 remain factory-internal clone identities and do not authorize a top-level
CREATE2 deployment or mutable implementation selection.

## Verification

The later implementation review must prove every mandatory `P9R-*` row in
`docs/architecture/phase-9-refinance-acceptance.md`, including:

- exact authority, resolver, identity, state, funding, refund, execution, donation,
  replay, and deployment semantics in this ADR;
- deterministic cross-language reference vectors for every commitment and result hash;
- exact historical ABI/storage compatibility plus the exact additive allowlist of one
  transition event and two typed unknown-ID errors;
- method-level freeze enforcement for every unopened mutator;
- the canonical `120/100/2/18` success, `95/5` payoff route, `90/30` positions, and
  every injected failure boundary;
- no double lien, debt disappearance, trapped escrow, redirected recipient, duplicate
  position, duplicate refund, or donation-created liability;
- executable traceability for applicable refinance, authority, loan, funding,
  collateral, accounting, and liveness invariants; and
- local-only deployment, replay, restart evidence, and bounded reset.

## Consequences

- The five frozen coordinator selectors now have one coherent, reviewable first-slice
  interpretation.
- Borrower acceptance is a direct transaction and is not inferred from an off-chain row
  or a caller-supplied state enum.
- Partial funding is permitted without partial debt, lien, position, or proceeds effects.
- Funding cannot become stranded merely because execution is not yet possible.
- The replacement debt and positions are canonical typed policy facts, not arbitrary
  execution calldata.
- Multi-collateral handoff is executable because the complete bounded ordered vector has
  one canonical source.
- Direct token donations neither create liabilities nor disable valid protocol exits.
- Contract activation can proceed without unfreezing later restructuring, transfer,
  recovery, or custody operations.
- `UNI-REFI-001` and `UNI-REFI-002` form one value-safe implementation checkpoint even
  though they remain separate ownership/backlog rows.

## Explicitly not authorized

This decision does not authorize Solidity business logic merely because this ADR is
accepted. It does not authorize real funds, real UFT or stablecoins, public networks,
public testnets, production RPCs or keys, live borrowers, lenders, loans, positions,
collateral, identity, custody, title, liens, providers, off-chain settlement,
cross-chain refinancing, non-atomic handoff, production policy, discretionary debt
change, governance amendment, reserve use, insurance, guarantee, recovery, token rescue,
legal effect, accounting conclusion, or deployment.

Every live or production capability requires a separate ratified legal, architecture,
security, economic-risk, custody, operational, and release decision. Nothing in this ADR
weakens ADR 0019's production prohibitions or Phase 8's independent authority boundary.
