# Phase 9 Resolution, Protection, and Recovery

Status: implementation boundary for synthetic local engineering

## Scope

Phase 9 implements one integrated local product across five work packages:

- deterministic payoff quoting;
- atomic refinancing and senior-lien handoff;
- protected-consent restructuring;
- funded synthetic coverage, premiums, claim adjudication, and payout; and
- guarantee, loss, write-off, subrogation, and later-recovery allocation.

The environment uses the local EVM home domain, disposable PostgreSQL, the durable event
broker, object storage, and synthetic parties, assets, keys, balances, and evidence.
Every economic amount is a nonzero integer in one registered synthetic denomination.

The word `insurance` in this milestone describes a test state machine over synthetic
funds. It is not a real insurance product, guarantee, reserve claim, solvency statement,
legal promise, or deployment authorization.

## Product topology

```text
                               canonical local EVM

  old lender ──┐
               │    ┌───────────────────────┐
  new funders ─┼───►│ RefinanceCoordinator │
               │    └───────┬───────────────┘
  borrower ────┘            │
                   ┌─────────┼───────────┐
                   ▼         ▼           ▼
             PayoffQuote  LienRegistry  Phase9LoanAccount
                Engine       │                 ▲
                   │         ▼                 │
                   │  CollateralCustodyV2  Phase9LoanFactory
                   │
                   ▼
          RestructuringController
                   │
             PositionManagerV2
                   │
                   ▼
  funder ─────► InsuranceReserveVault ◄──── premium
                   │
                   ▼
            InsuranceManager
                   │
          threshold adjudication
                   │
                   ▼
              RecoveryManager ◄──── guarantor / actual later receipt
                   │
        loss, write-off, subrogation
                   │
                   ▼
       Foundation ledger + reconciliation

                  durable local projection

     PostgreSQL ◄── event broker ──► object evidence
          │                              │
          └──────── release assembler ──┘
```

No service or provider owns EVM authority. Services project canonical transitions,
verify typed local signatures and token receipts, create balanced accounting intent,
and retain evidence. A database row cannot create a payoff, lien, consent, reserve
asset, claim, write-off, or recovery.

Existing Phase 3 through Phase 8 clones cannot satisfy this boundary and are not
upgraded or reinterpreted. Phase 9 adds `IMPLEMENTATION_VERSION = 9` loan, position,
custody, lien, and resolution components. Existing loans retain their original
implementation and history. Phase 8 bridge, wrapped-token, message-recovery, satellite,
and collateral-release contracts are unreachable from every Phase 9 component.

## Dedicated local settlement fixture

Phase 9 deploys `Phase9LocalSyntheticToken`; it does not reuse
`Phase8LocalSyntheticToken`, `WrappedUFT`, `UnifiedToken`, a bridge asset, treasury
custody, or any provider-controlled asset. The exact constructor and external ABI are:

```solidity
interface IPhase9LocalSyntheticToken {
    error InvalidLocalChain(uint256 chainId);
    error InvalidFixtureAllocator();
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    function FIXED_SUPPLY_UNITS() external view returns (uint256);
    function name() external view returns (string memory);       // exact value below
    function symbol() external view returns (string memory);     // exact value below
    function decimals() external view returns (uint8);           // 6
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
```

The implementation constructor signature is exactly
`constructor(address fixtureAllocator)`.
Its name is exact ASCII `Unified Phase 9 Local Synthetic Unit`, symbol is exact ASCII
`P9UNIT`, decimals are `6`, and fixed supply is `1,000,000,000` display units
(`1_000_000_000_000_000` base units). The constructor reverts unless
`block.chainid == 31337` and `fixtureAllocator != address(0)`, then mints the entire
fixed supply once to that allocator. There is no post-construction mint, burn, fee,
rebase, callback, permit, pause, deny-list, role, upgrade, rescue, bridge, faucet, or
administrator transfer surface. OpenZeppelin Contracts `5.6.1` ERC-20 revert semantics
are authoritative; exact sender and recipient balance deltas are required.

The name and symbol are neutral fixture labels only. They confer no currency
denomination, USD or other fiat peg, redemption, backing, exchange rate, market value,
payment claim, legal tender status, or provider obligation.

The local deployment registers this address as the only Phase 9 settlement token and
binds every loan, escrow, reserve, claim, guarantee, and recovery policy to it. Phase 8
registries, routes, vaults, hubs, wrapped-token contracts, and workers never receive its
asset ID or an allowance. The release bundle commits its address, deployment
transaction, creation/runtime bytecode hashes, ABI hash, storage-layout hash, asset ID,
fixed supply, initial allocation, and all terminal balances. Reset removes its local
deployment/broadcast evidence and restores the disposable chain; it never calls a burn
or privileged cleanup function because none exists.

Every active payoff path independently requires `block.chainid == 31337` and
`settlementToken.codehash ==
keccak256(type(Phase9LocalSyntheticToken).runtimeCode)` under the pinned Solidity,
optimizer, EVM, and OpenZeppelin settings. Interface compatibility, token metadata, or a
successful ERC-20 call is not sufficient. Under Foundry `1.7.1`, Solidity `0.8.36`,
optimizer runs `200`, EVM Prague, and OpenZeppelin Contracts `5.6.1`, the exact deployed
runtime code hash is
`0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5`. The token
constructor's own chain check and the consumer's exact-runtime check are independent
local-only controls.

## Canonical local scenario

All displayed values are synthetic six-decimal base units:

```text
old principal                         90
old accrued interest                   5
old fees                               3
old penalties                          3
old unapplied credit                    1
old payoff                           100
old lender principal + interest       95
old net fee + penalty recipient         5

new senior funding                    90
new junior funding                    30
total funding                        120
refinance fee                          2
borrower proceeds                     18

post-refinance accrued interest         5
restructured debt                    125

collateral recovery                   60
actual guarantee payment              10
eligible uncovered loss               55
coverage deductible                    5
coverage percentage                  40%
coverage policy limit                 20
funded coverage payment               20
residual write-off                    35
later mocked legal-recovery receipt    5

reserve capitalization                60
funded premium                         4
reserve stress haircut           10,000 bps
modeled loss at target confidence     40
pre-claim reserve coverage ratio    1.60
post-claim reserve coverage ratio   1.10
```

The successful restructure capitalizes the five units, extends maturity, and replaces
the schedule without changing total debt. The senior position votes yes, the junior
position votes no, eligible participation is 100%, approval is exactly 75%, and the
borrower separately consents.

A required failure scenario reverts immediately before lien completion. Old debt and
lien remain unchanged, the new loan remains inactive, all 120 units remain escrowed in
`FUNDING_ESCROWED`, and the borrower receives zero. Retrying the same immutable
execution succeeds; refunds become callable only after borrower cancellation or expiry
persists `REFUNDABLE`.

## Components

### Phase9LoanFactory and Phase9LoanAccount

`Phase9LoanFactory` creates a non-upgradeable version-9 account and position manager
with a new loan ID, registers the account in the existing `LoanRegistry`, and binds the
approved quote, refinance, amendment, protection, and recovery policies. It cannot
replace or mutate an existing Phase 3 through Phase 8 registration.

ADR 0022 fixes this bootstrap without changing the frozen ABI or storage. The factory
classifies an exact stored creation replay before the current global nonce, revalidates
the complete request, current active four-field creation-resolver tuple, stored clone
mappings/code, and canonical protocol-version-9 registry identity, and returns the
stored clones without another registration, nonce change, or event. It does
not pretend to compare a historical full-bootstrap payload that the frozen layout did not
store. A unique path reserves the
request, processed flag, predicted mappings, and incremented nonce under rollback,
deploys both reviewed deterministic minimal clones, initializes the account before the
manager, has the manager authenticate the factory through that account's reciprocal
configuration, then registers and verifies protocol version 9 and emits. The factory and
account validate the exact synthetic-local token/runtime;
the coordinator alone performs the typed asset-registry `active`, decimals,
exact-balance-delta, and runtime checks.

The account and manager implementation instances lock their own initializers through the
existing `initialized` declaration while fresh clone storage begins unset. Clone creation
uses the standard OpenZeppelin-5.6.1 EIP-1167 bytes and salt behavior through a private
helper that does not add library errors to the frozen factory ABI. Factory conflicts use
only `InvalidPhase9LoanConfiguration` or `Phase9LoanAlreadyExists(loanId)` according to
ADR 0022; account and position-manager failures likewise use only their frozen typed
errors.

`Phase9LoanAccount` is the versioned debt authority dedicated to Phase 9. It exposes:

- immutable loan, borrower, lender, settlement asset, policy, and collateral identity;
- principal, accrued interest, fees, penalties, credits, and state version;
- exact refinance payoff entrypoint callable only by the bound coordinator, which
  closes debt, calls the existing registry terminal transition from the registered
  account, and verifies the terminal postcondition atomically;
- one-time replacement-loan activation;
- bounded restructuring application;
- covered-loss exposure, realized-loss, and explicit write-off records as distinct
  states; and
- terminal closure that does not erase recovery history.

Every debt-changing action increments `debt_state_version`. The quote engine and every
resolution proposal bind that version.

Every `LoanConfiguration` identifier and policy/agreement commitment is nonzero. Only the
express bootstrap, dormant-replacement, activation-template, and operation sentinels may
be zero. Agreement version zero remains absent: dormant initialization never writes it,
while active bootstrap or replacement activation records the immutable agreement hash at
the applicable nonzero terms version.

### PayoffQuoteEngine

The engine reads the complete canonical debt snapshot and stores an immutable quote.
It never accepts caller-supplied components. Quote nonces are monotonic per loan.

```text
quote_id = keccak256(abi.encode(
  "UNIFIED_PAYOFF_QUOTE_V1",
  payoff_quote_engine,
  chainid,
  loan_id,
  loan_account,
  policy_hash,
  debt_state_version,
  principal,
  accrued_interest,
  fees,
  penalties,
  credits,
  component_beneficiary_hash,
  net_payoff,
  settlement_asset_id,
  settlement_token,
  settlement_route_hash,
  issued_at,
  valid_until,
  quote_nonce
))
```

At issuance `payoff_quote_engine` MUST equal `address(this)`; using the explicit field
name keeps the ADR, architecture, data layout, service codec, and golden vector in one
identical conceptual sequence.

The maximum validity window is immutable policy. Stored quote content cannot be
recalculated into a different identity.

The additive `IPayoffQuoteEngineV2` surface and event return the entire stored quote.
They preserve existing ABI meanings; the legacy total-and-expiry interface is not used
as Phase 9 execution authority.

The following first-slice ABI is exact. Solidity source uses these names, integer
widths, tuple field order, mutability markers, errors, and non-indexed/indexed event
fields without substitution:

```solidity
interface IPayoffQuoteEngineV2 {
    enum QuoteState { NONE, ISSUED, CONSUMED, EXPIRED, INVALIDATED }
    enum ComponentKind {
        NONE,
        PRINCIPAL,
        ACCRUED_INTEREST,
        CAPITALIZED_INTEREST,
        FEE,
        PENALTY,
        RECOVERABLE_COST,
        CREDIT
    }

    struct PayoffComponentV2 {
        ComponentKind kind;
        uint256 amount;
        address beneficiary;
        string obligationCode;
    }

    struct PayoffQuoteV2 {
        bytes32 quoteId;
        bytes32 loanId;
        address loanAccount;
        bytes32 policyHash;
        uint64 debtStateVersion;
        uint256 principal;
        uint256 accruedInterest;
        uint256 fees;
        uint256 penalties;
        uint256 credits;
        bytes32 componentBeneficiaryHash;
        uint256 grossPayoff;
        uint256 netPayoff;
        bytes32 settlementAssetId;
        address settlementToken;
        bytes32 settlementRouteHash;
        uint64 issuedAt;
        uint64 validUntil;
        uint64 quoteNonce;
        QuoteState state;
    }

    error InvalidQuoteInput();
    error UnknownQuote(bytes32 quoteId);
    error UnauthorizedQuoteCaller(address caller);
    error StaleDebtVersion(uint64 expectedVersion, uint64 actualVersion);
    error QuoteExpired(bytes32 quoteId, uint64 validUntil);
    error QuoteTerminal(bytes32 quoteId, QuoteState state);
    error QuoteReplayConflict(bytes32 quoteId);

    event PayoffQuoteIssued(
        bytes32 indexed quoteId,
        bytes32 indexed loanId,
        uint64 indexed debtStateVersion,
        bytes32 componentBeneficiaryHash,
        uint256 grossPayoff,
        uint256 credits,
        uint256 netPayoff,
        bytes32 settlementAssetId,
        address settlementToken,
        bytes32 settlementRouteHash,
        uint64 issuedAt,
        uint64 validUntil,
        uint64 quoteNonce
    );
    event PayoffQuoteDispositionRecorded(
        bytes32 indexed quoteId,
        bytes32 indexed refinanceId,
        QuoteState state,
        bytes32 sourceEventId,
        uint64 recordedAt
    );

    function issueQuote(bytes32 loanId, uint64 validUntil)
        external
        returns (bytes32 quoteId);
    function consumeQuote(
        bytes32 quoteId,
        bytes32 refinanceId,
        uint64 expectedDebtStateVersion,
        bytes32 sourceEventId
    ) external returns (PayoffQuoteV2 memory storedQuote);
    function invalidateQuote(bytes32 quoteId, bytes32 sourceEventId) external;
    function quote(bytes32 quoteId)
        external
        view
        returns (PayoffQuoteV2 memory storedQuote, PayoffComponentV2[] memory components);
}
```

`PayoffQuoteV2` is an external return tuple; the exact quote-ID preimage remains the
ordered list above. `grossPayoff` is derived and stored evidence, not an additional ID
field. `componentBeneficiaryHash` appears immediately after `credits` in that preimage
in every Solidity vector, service codec, model, and release artifact.

#### ADR 0020 payoff implementation activation

ADR 0020 is the normative activation decision for `UNI-PAYOFF-001`. It adds no external
engine selector and no engine storage. The constructor-bound refinance coordinator is
the only authorized caller of `issueQuote`, `consumeQuote`, and `invalidateQuote`; every
other caller receives `UnauthorizedQuoteCaller`.

Issuance requires a registered, nonterminal protocol-version-9 loan whose account binds
the approved factory, this engine, the same loan registry, and the constructor-bound
coordinator. The engine independently requires the registry-resolved account to equal
`IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId)`. The account's configured
position manager must independently equal
`IPhase9LoanFactory(_approvedPhase9Factory).positionManager(loanId)` and contain deployed
code. Its lifecycle is `ACTIVE` and its servicing state is `CURRENT`, `DELINQUENT`, or
`DEFAULTED`. Issuance and first consumption require chain ID `31337` and the exact
`keccak256(type(Phase9LocalSyntheticToken).runtimeCode)` settlement-token code hash; an
interface-compatible substitute is rejected. The first slice requires zero capitalized
interest and recoverable costs and enforces:

```text
gross payoff = principal + accrued interest + fees + penalties
credits <= fees + penalties
net payoff = gross payoff - credits
net payoff > 0
```

The account's bound position manager must expose exactly one `ACTIVE` lender position.
Its nonzero owner is the principal-and-interest beneficiary and its claim equals
principal plus accrued interest.

The exact internal policy-source dependency is:

```solidity
interface IPhase9PayoffQuotePolicySource {
    function resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (
            bytes32 policyHash,
            bytes32 boundPolicySetHash,
            address feePenaltyBeneficiary,
            bytes32 settlementAssetId,
            address settlementToken,
            uint64 maximumValidity,
            bool active
        );
}
```

The existing `_quotePolicyRegistry` address is the immutable source. The response must
be active and nonzero, bind the account's exact policy-set hash and settlement asset and
token, and return a maximum validity equal to the constructor-bound maximum. The surface
is not added to `IPayoffQuoteEngineV2` and creates no engine getter or storage.

The resolver's `policyHash` must be the exact deterministic value:

```solidity
keccak256(abi.encode(
    "UNIFIED_PAYOFF_POLICY_V1",
    block.chainid,
    address(this),
    _quotePolicyRegistry,
    loanId,
    loanAccount,
    boundPolicySetHash,
    feePenaltyBeneficiary,
    settlementAssetId,
    settlementToken,
    maximumValidity
))
```

The first successful quote freezes that complete policy binding for the local
`(loanId, loanAccount)`. On every successor issue, even after terminal disposition or
effective expiry, the engine reconstructs the prior binding from the latest stored
quote, fixed components, account configuration, constructor-bound registry and maximum,
and local domain. The newly resolved tuple must reconstruct the same stored
`quote.policyHash`; its fee beneficiary, asset, token, policy-set hash, and maximum must
also remain exact. A change fails before nonce advancement or quote writes. First
consumption performs the same reconstruction against the quote being consumed. This
uses existing quote/component storage and adds no selector or slot.

The engine stores exactly five components, including zero amounts, in this order:

```text
PRINCIPAL          lender beneficiary       "PRINCIPAL"
ACCRUED_INTEREST   lender beneficiary       "ACCRUED_INTEREST"
FEE                fee/penalty beneficiary  "FEE"
PENALTY            fee/penalty beneficiary  "PENALTY"
CREDIT             fee/penalty beneficiary  "FEE_PENALTY_CREDIT"
```

Their amounts are the corresponding canonical debt fields. Credit is applied only to
the fee-and-penalty route. The exact commitments are:

```solidity
componentBeneficiaryHash = keccak256(abi.encode(
    "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1",
    components
));

settlementRouteHash = keccak256(abi.encode(
    "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
    block.chainid,
    address(this),
    refinanceCoordinator,
    loanId,
    loanAccount,
    settlementAssetId,
    settlementToken,
    lenderBeneficiary,
    feePenaltyBeneficiary,
    policyHash
));
```

Quote nonce zero is reserved. The first successful quote per loan uses nonce one, and a
nonce advances only after successful issuance. At most one quote per loan is effectively
`ISSUED`: a second issue while the latest quote is unexpired and unterminated reverts
`InvalidQuoteInput`; there is no implicit supersession. A terminal or effectively
expired latest quote permits the next nonce. Exhaustion before another identity can be
formed reverts `QuoteReplayConflict(bytes32(0))`.

After exact quote-ID derivation and before any write or nonce advance, either
`quoteId == bytes32(0)` or `_quotes[quoteId].quoteId != bytes32(0)` reverts
`QuoteReplayConflict(quoteId)`. Existing quote content is never overwritten or returned
as an issuance replay.

Validity is `[issuedAt, validUntil)`. `validUntil` is the coordinator-selected sole time
input; `issuedAt` is the checked local block timestamp, and the coordinator cannot supply
a clock, duration, or alternate issuance time. The requested duration must be positive
and no greater than the immutable maximum, with the maximum boundary accepted. At
`block.timestamp >= validUntil`, `quote()` overlays `EXPIRED` without writing and
consumption reverts `QuoteExpired`. Coordinator invalidation at or after that boundary
persists `EXPIRED`; invalidation before it persists `INVALIDATED`.

Consumption fully re-resolves the registry, the approved factory's independent loan and
position-manager results, account configuration, complete debt state, version, one active
lender position, local chain and exact token runtime, deterministic policy tuple,
components, both commitments, and quote-ID preimage. The expected, stored, and live debt
versions must match. Exact replay of a consume or invalidate disposition is idempotent and
emits nothing twice. Reuse of the same terminal action with a changed refinance ID,
consume-expected debt version, or source-event ID reverts `QuoteReplayConflict`;
attempting another terminal action reverts `QuoteTerminal`. For invalidation,
`sourceEventId` must be nonzero; after authorization and quote existence validation, zero
reverts `InvalidQuoteInput` before terminal classification and produces no write or event.
An existing terminal disposition is classified before first-consumption live revalidation
so the exact successful consume remains replayable after its atomic payoff has
legitimately changed the old loan; no new or changed consume receives that bypass.

The immutable engine/coordinator constructor cycle executes in one transaction through
one dedicated local deployer using ordinary sequential `CREATE`. Before either creation,
the deployer predicts the coordinator at the immediately next creation nonce after the
engine, deploys the engine with that exact address, then—with no intervening creation or
callback—deploys the coordinator with the actual engine. In that transaction the deployer
requires the predicted and actual coordinator to match, requires code at both addresses,
and checks the reciprocal constructor arguments it supplied. It validates every required
nonzero/local constructor argument before creation, while the activated engine constructor
independently enforces its local dependencies. Any mismatch reverts the whole transaction.
No setter, proxy, rebinding, or `CREATE2` path is permitted. Post-transaction raw local
storage reads using the reviewed layout cross-check the recorded constructor arguments
before activation, but are evidence only and are never claimed to cause the deployment
transaction to revert.

For the canonical scenario, principal and accrued interest route 95 units to the old
lender while the separately bound fee and penalty beneficiary receives five units.
Those routes, the two-unit refinance fee, and the 18-unit borrower proceeds are fixed
before funding:

```text
120 funding = 95 old lender + 5 old fee/penalty + 2 refinance fee + 18 borrower
```

### CollateralCustodyV2 and LienRegistry

`CollateralCustodyV2` holds the synthetic collateral independently of either loan
account. Only `LienRegistry` may change the bound secured-loan identity, and only the
borrower can receive an authorized surplus or final release after the active lien and
all stored recovery rights are satisfied. Neither component calls or inherits a
Phase 3 through Phase 8 collateral vault.

For each collateral ID `LienRegistry` stores:

```text
collateral_id
collateral_manager
vault
asset_id
quantity
borrower
senior_loan_id
lien_version
status
pending_refinance_id
pending_target_loan_id
```

`pending_target_loan_id` is not an enforceable lien. Only `senior_loan_id` owns the
claim. A handoff is callable only by the registered coordinator and changes old owner
to new owner inside a successful refinance transaction. The borrower never receives
collateral during handoff.

### RefinanceCoordinator

The coordinator owns:

- immutable policy registration;
- refinance requests, direct borrower acceptance, and exact quote binding;
- retained off-chain request, quote, offer, and rejection evidence;
- exact funding escrow;
- cancellation/expiry/refund before execution;
- atomic payoff, lien handoff, replacement activation, and borrower proceeds; and
- terminal replay evidence.

The frozen five-selector first slice persists `ACCEPTED` on the successful
`requestRefinance` call; it does not persist `REQUESTED`, `QUOTED`, `OFFERED`,
`REJECTED`, or `DISPUTED`. The first accepted funding value enters
`FUNDING_ESCROWED`, and further partial funding remains there until exact full funding
makes execution eligible.

ADR 0025 fixes successful execution as one durable
`FUNDING_ESCROWED -> COMPLETED` version increment. `EXECUTING` is only a provisional,
unversioned, non-evented reentrancy guard; it cannot persist or satisfy terminal replay.
The same decision replaces private checkpoint-history claims with public one-block
execution observations, permits canonical external payout-role aliases under exact
leg/unique-address/coordinator conservation while rejecting zero, coordinator, and
settlement-token recipients, fixes one representable execution timestamp plus exact
stored-quote/resolver result bindings, revalidates the replacement's exact stored
factory creation through checked current `nextLoanNonce - 1` and mapped clones, and
requires the sorted begin-all,
verify-all-pending, complete-all, verify-all-active lien sequence. D3 remains closed.

The caller supplies zero refinance/quote IDs and zero derived state. After pure wire/
derived/key checks the coordinator's fixed request `begin` dispatch acquires the
old-loan tagged lock before any external resolver or other effect-capable dependency
interaction. The fixed validation `preflight` and request `complete` dispatches occur
only with that lock active; they are ADR 0023 code partitioning rather than new runtime
authority. Policy, borrower, and acyclic new-loan/predicted-manager validation then
occurs under rollback. The one borrower-authenticated request transaction has the registered coordinator create the
unique old bootstrap clone if absent, register/validate old positions/custody/liens,
issue the quote internally, derive quote/refinance IDs, create exact dormant
replacement clones, validate, and store `ACCEPTED`. No replacement preexists. Failure
rolls back bootstrap, quote, clones, nonce, state, and events; exact request repeat
fails the consumed old-loan refinance nonce before a new quote.

The existing `uint64` old-loan nonce uses bit 63 as an active lock and the low 63 bits
as the matching nonce/next value. It is acquired before resolver, token, registry,
factory, quote-engine, provider, or other effect-capable dependency interactions, held
through `ACCEPTED`, `FUNDING_ESCROWED`, and `REFUNDABLE`, and advanced/released only
after `COMPLETED`, `CANCELLED`, `EXPIRED`, or final `REFUNDED` effects. The all-low-bits
mask is exhausted; no request, reentry, or same quote can overlap the active owner.

The coordinator is non-upgradeable in the first slice. It has no general token rescue
or arbitrary target call. Exact balance-delta checks reject fee, rebase, or callback
behavior. Terminal exact replay returns stored results; changed reuse reverts.

Factory creation replay is distinct from request replay. The factory recognizes a stored
`creationId` before using the now-advanced factory nonce and returns only after the stored
request, live resolver facts, clones, mappings, and registry identity agree. The external
borrower request still rejects its consumed old-loan refinance nonce before issuing a
second quote.

Fresh coordinator creation supplies zero `creationId`: the frozen coordinator has no
implementation-address fields or factory prediction selector. The factory derives both
predictions and the canonical nonzero ID, stores only the canonicalized request, and
rejects a fresh caller-authored nonzero ID. Direct factory replay later supplies that
complete stored canonical request.

### PositionManagerV2

`PositionManagerV2` owns the replacement loan's senior and junior positions and exposes
historical position-level proofs:

```text
positionOwnerAt(position_id, block_number)
positionVotingPowerAt(position_id, block_number)
positionClaimAt(position_id, block_number)
totalVotingPowerAt(block_number)
```

It freezes eligible lender positions for one proposal:

```text
snapshot_id
loan_id
terms_version
snapshot_block
position_root
eligible_weight
position_count
quorum_basis_points
approval_basis_points
policy_hash
```

Each accepted position proof binds the position ID, owner, tranche, voting weight, and
snapshot root. One position can contribute its weight once. Transfers after the
snapshot do not move or duplicate proposal voting power.

Canonical tranche and position vectors are strictly increasing by unsigned raw
`bytes32` ID, not by service order or tranche priority. Exact existing tuples are inert;
changed reuse, zero/duplicate/decreasing IDs, authority failure, unknown tranche, or cap
failure uses `InvalidPositionOperation`. Checkpoints coalesce within one block by
overwriting the final same-block entry and otherwise append, so multi-position issuance
has one final total-voting-power checkpoint for its block without duplicating an exact
replay.

Raw positions, tranches, and checkpoints are immutable nominal issuance history, not
independently authoritative current receivables or votes. Every consumer resolves the
manager to loan ID, proves factory/registry account agreement, and joins current debt.
Registry terminal, account `CLOSED/TERMINAL`, or zero claim-bearing debt makes effective
claim and voting power zero even if stored issuance remains `ACTIVE`.
Payment/distribution, transfer, snapshot/vote/restructuring, quote, lien/collateral,
liquidation, recovery, protection, and authorization consumers apply that gate;
historical getters alone never authorize a current action.

### RestructuringController

The controller stores the full proposal and consumes:

- the immutable active amendment policy;
- exact current terms and debt version;
- an allowed modification mask and bounded values;
- disclosure and accounting-delta hashes;
- position snapshot;
- borrower EIP-712 consent;
- one vote per eligible position; and
- review, voting, and execution deadlines.

Execution calls the bound loan account with the exact approved amendment. The loan
increments terms and debt versions atomically. The controller cannot change borrower,
settlement asset, collateral recipient, lender-position identity, or an unlisted term.

### InsuranceReserveVault

The vault records exact custody by pool and asset. Deposits can be made only through
registered funding and premium paths. Claim payment is callable only by the bound
insurance manager for a stored approved claim and canonical beneficiary.

The vault exposes no:

- general withdrawal or rescue;
- treasury transfer;
- bridge backing;
- swap or cross-asset conversion;
- lending, staking, delegation, or liquidity provision;
- arbitrary approval or call; or
- administrator-selected claim recipient.

Pool assets remain physically segregated from protocol operating balances. A logical
reserve designation without custody is never counted.

The only first-product pool maps to `3210 Product-Specific Risk Reserve`. The
protocol-wide `3200 Insurance Reserve`, the UFT genesis allocation, bridge backing,
treasury, and other product pools are neither counted nor callable. The 100,000,000-UFT
allocation in tokenomics is not treated as funded or legally available capital.

### ReservePolicy

An immutable policy version binds:

- pool and settlement asset;
- token;
- stress haircut;
- target-confidence modeled-loss fixture;
- maximum coverage percentage;
- maximum single-policy limit;
- aggregate commitment limit;
- minimum governing reserve coverage ratio;
- minimum commitment coverage ratio;
- covered-event vocabulary;
- deductible bounds;
- premium requirements;
- claim adjudicator set;
- payout and recovery waterfall;
- activation delay; and
- expiry.

An effective loosening receives a new version and delayed activation. Immediate strict
reduction can block new coverage but cannot confiscate an existing approved claim.

### InsuranceManager

The manager stores coverage and claim state. Coverage cannot activate until:

- exact premium funding is present;
- reserve custody and stress capacity are sufficient;
- the loan, beneficiary, asset, events, limits, deductible, percentage, policy, and
  expiry are exact; and
- active aggregate commitments remain within policy.

Claim submission is non-economic. Approval requires a canonical loss, policy eligibility
and two-of-three typed signatures. Payment uses the exact stored beneficiary and amount.
Payout replay returns the same result without a second transfer.

Claim submitter, adjudicators, reserve payment authority, and reconciler are distinct
fixture roles. The reserve payer cannot be an adjudicator for the same claim. General
governance, treasury, emergency, and accounting roles cannot approve a claim or select
its beneficiary. A legacy recipient argument is accepted only when it equals the stored
beneficiary.

The loss submitter, write-off approver, recovery-receipt recorder, accounting poster,
reconciler, and release assembler are also distinct fixture roles. A write-off approver
cannot record or allocate a recovery for that loss, and a recovery recorder cannot
approve its accounting or close its reconciliation difference. Phase 8 and Phase 9
roles, signer domains, database schemas, object prefixes, broker subjects, and release
evidence namespaces are disjoint.

### GuaranteeVault

The vault records synthetic capped commitments:

```text
guarantee_id
loan_id
loss_id
guarantor
asset_id
maximum_amount
covered_event_mask
priority
subrogation_policy_hash
valid_from
expires_at
committed_amount
paid_amount
state
```

The commitment is memorandum authority only. `paid_amount` increases solely from exact
token custody in the recovery vault.

### RecoveryManager

The manager owns one immutable loss identity and monotonic source totals:

```text
gross covered-loss exposure
collateral credited
guarantor credited
insurance credited
other recovery credited
forgiveness recognized
residual loss exposure
realized loss recognized
write-off recognized
lender uncovered right
product-pool subrogation right
guarantor subrogation right
later recovery allocated
borrower surplus
```

It accepts actual registered-token receipts from the collateral, guarantor, or mocked
off-chain receipt paths. Descriptive evidence is content-addressed and privacy-safe.
Evidence without a token receipt cannot increment a recovery total.

Expected loss, covered-loss exposure, approved claim payable, funded claim payment,
residual exposure, realized loss, and write-off are never aliases. Realized loss is
recognized only after contractual recovery sources are exhausted or an exact valid
write-off is approved. Write-off requires separate authority and cannot exceed residual
loss exposure. Later recovery remains valid after write-off and follows the stored
waterfall.

The first product's loss order is collateral, zero unsupported borrower reserve,
actual funded guarantee, junior first-loss allocation, loan-specific coverage from the
dedicated product pool, then residual lender loss. No protocol-wide insurance reserve
or safety module participates. Later receipts restore uncovered lenders with senior
priority, then replenish the product-pool subrogation right, then the guarantor
subrogation right, and finally pay canonical borrower surplus.

## State transitions

### Quote

```text
NONE -> ISSUED -> CONSUMED
               -> EXPIRED
               -> INVALIDATED
```

`CONSUMED`, `EXPIRED`, and `INVALIDATED` are terminal. A new debt version requires a new
quote nonce and ID.

### Refinance

The full schema vocabulary supports retained proposal evidence and later phases. ADR
0021 fixes this five-selector slice's reachable on-chain graph as:

```text
NONE -> ACCEPTED
ACCEPTED --first successful funding commitment--> FUNDING_ESCROWED
FUNDING_ESCROWED --additional partial funding--> FUNDING_ESCROWED
FUNDING_ESCROWED -> COMPLETED

ACCEPTED --borrower cancellation before expiry--> CANCELLED
ACCEPTED --permissionless expiry at/after deadline--> EXPIRED
FUNDING_ESCROWED --borrower cancellation or expiry--> REFUNDABLE
REFUNDABLE --all stored commitments refunded--> REFUNDED
```

`REQUESTED`, `QUOTED`, and `OFFERED` are off-chain evidence stages;
`REJECTED` is an off-chain outcome; `DISPUTED` is unreachable in this slice.

The local atomic execution may write `EXECUTING` only as a provisional reentrancy guard
within one transaction. It consumes no state version or execution attempt and emits no
transition. Success persists exactly one direct `FUNDING_ESCROWED -> COMPLETED`
increment/event using the terminal result hash. Durable projections may observe the
transaction result, never `EXECUTING` or a half-committed EVM state.

### Restructure

```text
NONE -> PROPOSED -> REVIEW -> VOTING -> APPROVED -> EXECUTING -> EFFECTIVE
                    \          \-> REJECTED | EXPIRED | WITHDRAWN
                     \-> REJECTED | EXPIRED | WITHDRAWN
```

### Coverage

```text
DRAFT -> PREMIUM_PENDING -> ACTIVE -> EXPIRED
                                  \-> EXHAUSTED
                                  \-> CANCELLED_FOR_NEW_LOSS_ONLY
```

Cancellation cannot erase an already covered event or approved claim.

### Claim

```text
NONE -> SUBMITTED -> UNDER_REVIEW
                      -> APPROVED -> PAYMENT_PENDING -> PAID
                      -> PARTIALLY_APPROVED -> PAYMENT_PENDING -> PAID
                      -> REJECTED | EXPIRED | DISPUTED
```

### Loss and recovery

```text
NONE
  -> OPEN
  -> RECOVERY_PENDING
  -> LOSS_FINALIZED
  -> WRITE_OFF_PENDING
  -> WRITTEN_OFF
  -> RECOVERY_OPEN
  -> RECOVERED | CLOSED_WITH_UNRECOVERED_LOSS
```

Later recovery can append to a written-off loss without rewriting the write-off.

## Closed modification vocabulary

The restructuring payload is typed and additive:

| Modification | Required bound |
| --- | --- |
| Maturity extension | maximum extension seconds |
| Rate reduction | new rate not above active rate |
| Payment holiday | maximum periods and exact schedule |
| Fee waiver | exact amount not above fee due |
| Penalty waiver | exact amount not above penalty due |
| Arrears capitalization | exact amount and new principal cap |
| Added collateral | exact registered collateral commitment |
| Partial forgiveness | exact amount, supermajority, loss and position allocation |

Each payload field participates in the proposal and accounting hashes. Unsupported
modification bits fail.

## Consent and signature domains

Borrower consent:

```text
keccak256(abi.encode(
  "UNIFIED_RESTRUCTURE_BORROWER_CONSENT_V1",
  chainid,
  restructuring_controller,
  restructure_id,
  loan_id,
  active_terms_version,
  amended_terms_hash,
  disclosure_hash,
  accounting_delta_hash,
  consent_nonce,
  valid_until
))
```

Claim approval:

```text
keccak256(abi.encode(
  "UNIFIED_CLAIM_ADJUDICATION_V1",
  chainid,
  insurance_manager,
  claim_id,
  coverage_id,
  loss_id,
  loss_state_version,
  requested_amount,
  adjudicated_amount,
  evidence_hash,
  policy_hash,
  adjudication_nonce,
  valid_until,
  adjudicator_set_hash
))
```

`approved_amount` is derived by the contract from the signed adjudicated amount and the
current canonical approval cap; it is never an unsigned substitute for adjudicator
judgment. A changed loss version invalidates the decision.

Signatures use low-`s` ECDSA, canonical signer ordering, unique signers, explicit
threshold, nonce, deadline, chain, contract, and policy. The local keys are fixtures,
not production identity or legal consent.

## Exact equations

### Payoff

```text
gross due = principal + interest + fees + penalties
net payoff = gross due - credits
0 <= credits <= fees + penalties <= gross due
```

### Refinance

```text
funding escrow
= old net payoff
 + borrower proceeds
 + explicitly disclosed refinance fee

terminal attributed escrow(refinance ID) = 0
unsolicited coordinator token surplus is excluded from liabilities and readiness
old outstanding debt = 0
new activated principal = committed new principal
enforceable senior lien count(collateral ID) = 1
```

### Voting

```text
quorum reached
<=> voted weight * 10_000 >= eligible weight * quorum bps

approved
<=> support weight * 10_000 >= cast weight * approval bps
```

Every division uses cross-multiplication. No fractional vote rounding creates weight.

### Protection

```text
eligible risk-adjusted assets
= sum(floor(actual custody * immutable stress haircut bps / 10_000))

unclaimed commitments
= sum(policy remaining limits excluding approved unpaid amounts)

encumbered capacity = unclaimed commitments + approved unpaid claims
available underwriting capacity
= max(eligible risk-adjusted assets - encumbered capacity, 0)

unencumbered payout liquidity
= actual settlement custody - all approved unpaid claims

claim-specific payment liquidity for claim C
= actual settlement custody - approved unpaid claims for every claim other than C

reserve coverage ratio
= eligible risk-adjusted assets / modeled covered loss at target confidence

commitment coverage ratio
= eligible risk-adjusted assets / max(encumbered capacity, 1)
```

Every stress haircut is an integer in `[0, 10_000]` and modeled covered loss is strictly
positive. The canonical fixture therefore uses `64 * 10_000 / 10_000 = 64` eligible
units before its 20-unit claim payment.

Approval converts an unclaimed commitment to an approved payable in one transition, so
the same amount is not present in both terms.

For admission, a new or incremental commitment must be no greater than the
pre-activation available underwriting capacity. After activation, encumbered capacity
must not exceed eligible risk-adjusted assets and both policy ratio floors must hold.
Later impairment blocks increases but cannot delete or subordinate an existing payable.

### Claim

```text
eligible uncovered loss
= max(
     gross covered-loss exposure
     - collateral
     - guarantor paid
     - insurance already paid
     - other credited recovery,
     0
   )

coverage-formula amount
= max(eligible uncovered loss - deductible, 0)
  * coverage bps / 10_000

approval cap
= min(
     requested amount,
     coverage-formula amount,
     unclaimed policy limit,
     unclaimed policy commitment,
     claim-specific payment liquidity,
     beneficiary covered unresolved entitlement
   )

approved amount = min(adjudicated amount, approval cap)
payable amount = approved amount - paid amount
payment permitted <=> claim-specific payment liquidity >= payable amount
payment amount = payable amount when permitted; otherwise zero
```

The beneficiary entitlement is committed by the loss-position snapshot and waterfall.
The first local product makes no partial claim transfer. Insufficient liquidity leaves
the full amount in `PAYMENT_PENDING`; one nonce-bound exact payment consumes the
decision. Rounding is down and any explicit residual remains visible.

### Loss and later recovery

```text
residual loss exposure
= gross covered-loss exposure
 - all unique credited recovery sources
 - explicit forgiveness already recognized

realized loss is recognized only after recovery exhaustion or valid write-off
write-off <= residual loss exposure

later receipt
= lender uncovered allocation
 + product-pool subrogation allocation
 + guarantor subrogation allocation
 + borrower surplus
```

## Durable projection

The local `resolution-coordinator` service is split into:

```text
quote/
refinance/
restructure/
protection/
claim/
guarantee/
recovery/
accounting/
reconciliation/
store/
cmd/server/
cmd/local-worker/
```

Each package consumes typed canonical events and produces monotonic compare-and-set
records. Restart rehydrates incomplete work from PostgreSQL and object evidence. The
service does not hold a private key that can change loan, lien, reserve, or claim state.

The foundation ledger gains corresponding `resolutionaccounting` and
`resolutionreconciliation` packages. Accounting accepts only canonical terminal
evidence and registered identities. It cannot originate claim or recovery rights.

## Database authority

Migrations `000013` through `000015` define owner-only tables and reviewed functions.
Runtime roles receive `EXECUTE` only on the exact transitions they project.

Required negative tests prove runtime identities cannot:

- forge a quote or mark it consumed;
- complete a refinance or move a lien;
- insert consent, votes, approval, or effective amendment;
- increase reserve custody or stress value;
- approve or pay a claim;
- record a guarantee payment without receipt;
- write off more than remaining loss;
- create or allocate a recovery receipt; or
- insert, edit, or delete journal history.

## Accounting composition

The implementation must freeze the exact journal templates before use. Minimum batches:

1. refinance funding escrow control;
2. exact old payoff and old lender settlement;
3. old effective-claim extinguishment through terminal debt and new claim activation;
4. borrower residual proceeds;
5. refinance fee, if nonzero;
6. restructuring waiver/capitalization/forgiveness;
7. premium receipt and reserve restriction;
8. coverage memorandum commitment;
9. guarantor memorandum commitment and actual payment;
10. approved claim payable;
11. claim settlement and insurer subrogation;
12. realized loss and write-off;
13. later recovery receipt;
14. lender, insurer, guarantor, and borrower-surplus allocation; and
15. reconciliation differences.

Every batch is denomination-balanced and evidence-linked. Control-account equality is
tested separately from financial double-entry equality.

Phase 9 adds `2370 Accrued Lender Interest Claims`, `2380 Refinance Funding Escrow
Liability`, `2390 Refinance Refund Payable`, and `3210 Product-Specific Risk Reserve`.
The implemented `2320 Funding Commitment Liabilities` meaning is preserved. The
protocol-wide `3200 Insurance Reserve` is neither posted nor inferred from the UFT
genesis allocation.

## Reconciliation dimensions

Each snapshot reports:

- old and new debt components and versions;
- quote and refinance status;
- funding escrow and terminal recipients;
- lien owner and collateral vault custody;
- active terms and amendment version;
- eligible, cast, support, and oppose weight;
- reserve gross custody, stress value, commitments, payables, and capacity;
- coverage remaining and claim states;
- loss component totals;
- guarantee paid and subrogation right;
- insurance paid and subrogation right;
- write-off and later receipts;
- recovery allocations and borrower surplus;
- journal and control-account totals; and
- open difference owner, age, deadline, and evidence.

Differences are never netted across unrelated loans, losses, pools, assets, parties, or
accounting roles.

## Release evidence and reset

The complete Phase 9 implementation will have one independent authoritative local
manifest after `UNI-LOCAL-003` and the implementation/exit gates pass:

```text
protocol/deployments/local/phase9-release-evidence.json
```

That future manifest will not extend, import, or satisfy the Phase 8 manifest. It will
be schema validated and bind `environment = "local"`, `contains_real_value = false`, the
checked-out `source_commit`, a clean source tree at assembly, chain `31337`, exact
contract addresses and code hashes, policy and role hashes, canonical events, migration
and privilege checks, balanced journal identities, object and broker evidence,
PostgreSQL checkpoints, reconciliation closure, restart/replay results, and reset
scope. Its required live sections will cover the successful flow and every named
negative, concurrency, and injected-failure scenario.

The future pre-reset verifier will read only this manifest and live local resources.
The complete one-command reset will delete all Phase 9 contracts' generated manifests,
local token balances, database rows and schemas, object prefixes, broker streams,
cached fixture keys, and run artifacts within the reviewed workspace paths. The future
post-reset verifier will test absence directly and never attempt to read a deleted
manifest.

## Failure matrix

| Failure | Required result |
| --- | --- |
| Debt changes after quote | quote cannot execute |
| Competing refinance consumes quote | one completes; the other fails without value or lien effect |
| New funder commitment submitted twice | exact replay only; no second escrow |
| Token callback or transfer fee | entire transition reverts |
| Old payoff fails | no lien or new-loan change |
| Lien handoff fails | payoff and all other effects revert |
| New activation fails | payoff, lien, funding, and proceeds revert |
| Borrower proceeds fail | entire refinance reverts |
| Accepted funded refinance expires before execution | `REFUNDABLE`; each stored funder commitment has one exact refund |
| Position transfers after snapshot | vote right remains bound to snapshot owner/proof |
| Vote replays | no duplicate weight |
| Borrower signature changes field | proposal cannot execute |
| Reserve value falls below limit | new coverage blocked; existing claims remain visible |
| Claim exceeds eligibility or capacity | approval/payment capped or rejected |
| Adjudicator set substituted | claim cannot approve |
| Guarantee promised but not paid | loss unchanged |
| Same receipt submitted twice | exact replay; no second recovery |
| Write-off and later recovery race | serializable totals and append-only history |
| Database response lost | replay returns same terminal record and journals |
| Process restarts | incomplete projections rehydrate without a new economic effect |

## Invariant traceability

Phase 9 test and release-evidence matrices map every applicable invariant in these
families:

```text
INV-ACC-001 through INV-ACC-007
INV-AUTH-001 through INV-AUTH-009
INV-LOAN-001 through INV-LOAN-015
INV-FUND-001 through INV-FUND-011
INV-INT-001 through INV-INT-012
INV-COL-001 through INV-COL-012
INV-LIQ-005 through INV-LIQ-012
INV-REFI-001 through INV-REFI-008
INV-INS-001 through INV-INS-009
REC-001 through REC-008
LIVE-REFI-001
```

An invariant is never omitted merely because the local fixture does not exercise its
production variant. `INV-INT-007` has an explicit no-live-benchmark non-applicability
test; `INV-COL-009`, `INV-COL-010`, and `INV-COL-011` have explicit prohibited UFT,
NFT, and off-chain-collateral path tests. Equivalent non-applicability evidence names
the invariant, reason, enforcing prohibition, owner, and expiry.

## Work packages

### Mandatory pre-code ABI and storage freeze

The behavioral specification intentionally does not invent selectors for the remaining
large components in prose. Before any Phase 9 state-changing business logic is accepted,
the first implementation PR MUST contain only compileable interfaces, typed storage
declarations, deployment stubs, and compatibility tooling, and MUST pass independent
architecture and security review. Until that PR is merged, every Phase 9 implementation
backlog item other than schema/model and interface-freeze work remains blocked.

That freeze PR is complete only when all of the following are true:

1. `protocol/src/interfaces/phase9/` contains exact compileable interfaces for
   `IPhase9LoanFactory`, `IPhase9LoanAccount`, `IPayoffQuoteEngineV2`,
   `ICollateralCustodyV2`, `ILienRegistry`, `IRefinanceCoordinator`,
   `IPositionManagerV2`, `IRestructuringController`, `IInsuranceReserveVault`,
   `IReservePolicy`, `IInsuranceManager`, `IGuaranteeVault`, `IRecoveryManager`, and
   `IPhase9LocalSyntheticToken`. Every externally callable function, tuple field and
   order, integer width, mutability marker, custom error, and event field/indexing is
   present. The payoff interface above is copied exactly rather than re-derived.
2. `protocol/src/resolution/Phase9Types.sol`,
   `protocol/src/protection/Phase9ProtectionTypes.sol`, and
   `protocol/src/recovery/Phase9RecoveryTypes.sol` contain the exact enum and struct
   definitions used by those interfaces. No contract-local shadow struct may reproduce
   an interface tuple.
3. Each non-upgradeable contract has one typed storage declaration matching the logical
   inventory in `phase-9-data-layouts.md`. Mapping key/value types, array element types,
   enum widths, timestamps, counters, booleans, and initializer placement are explicit.
   Clone instances reserve no upgrade gap. Storage declarations may not use unstructured
   slots, delegatecall, or proxy namespaces.
4. The stub contracts compile with Solidity `0.8.36`, optimizer runs `200`, EVM Prague,
   OpenZeppelin Contracts `5.6.1`, and contain no successful state-changing business
   path except the exact token constructor. Other mutating stubs revert
   `Phase9ImplementationNotFrozen()`.
5. `ProtocolCompilation.sol` imports every Phase 9 contract, including
   `Phase9LocalSyntheticToken`. The command in scripts/check-foundation.ps1 formats
   `src/interfaces/phase9`, `src/resolution`, `src/protection`, `src/recovery`, the token,
   tests, and scripts. Contract-size checking sees every deployable Phase 9 runtime.
6. Reviewed ABI snapshots exist at `protocol/abi/phase9/<Contract>.abi.json` for every
   deployable contract and interface-bearing implementation. `tools/check_abi.py`
   contains explicit compiled/snapshot pairs for all of them; directory non-emptiness is
   not acceptance.
7. Deterministic compiler storage artifacts exist at
   `protocol/storage-layout/phase9/<Contract>.storage.json`. A dedicated checker compares
   contract name, compiler/settings hash, linearized bases, slot, offset, type ID,
   encoding, key/value/base/member graph, and byte width. Missing, additional, reordered,
   or retyped fields fail CI.
8. ABI and storage checkers run from `scripts/check-foundation.ps1` and the protected CI
   workflow. A clean checkout regenerates identical artifacts and fails on stale output.
   Golden vectors prove the exact quote preimage order, the non-circular loan/refinance
   identities, claim signature digest, coverage policy binding, and token metadata/supply.
9. The freeze review records the ABI hash and storage-layout hash for every component.
   Any later selector, event, error, tuple, or storage change requires an explicit
   additive compatibility review before business logic can merge.

This is a hard implementation dependency, not exit-review paperwork. Passing the
boundary-only `tools/check_phase9.py` mode without Phase 9 source files does not satisfy
it. The always-run checker detects any Phase 9 production source or
`ProtocolCompilation.sol` import, then immediately requires `UNI-SCHEMA-013` and
`UNI-ABI-009` to be `DONE` and runs the complete pre-code ABI/storage gate without
waiting for the rest of the implementation backlog. It also rejects any later
implementation row marked `DONE` while `UNI-ABI-009` is incomplete. Full implementation
mode adds the remaining schema, service, live, security, and release-evidence gates.

### Historical freeze and exact-source implementation checkpoints

The `UNI-ABI-009` merge is an immutable historical baseline, not a mutable pointer to the
latest Phase 9 source. Its ABI hashes, compiler storage-layout hashes, compiler settings,
source-set hash, manifest hash, independent review, merge commit, and tag remain
reproducible after implementation begins. The historical manifest, every ABI and storage
snapshot, and the freeze-review record are additionally pinned by a deterministic
aggregate over their repository paths and raw byte hashes, so semantically equivalent
rewrites still fail.

Each activated work package creates a later exact-source implementation checkpoint. The
checkpoint regenerates and reviews current source hashes and the complete source-set hash
plus the activated contract's complete ordered transitive repository-local Solidity
dependency-closure hash, while independently comparing ABI and compiler storage layout
with the historical freeze. Review evidence names both checkpoints and the dependency
closure. A current source hash never overwrites a historical hash, a dependency-only
change requires renewed review, and an implementation checkpoint cannot claim that its
business logic existed at the freeze commit.

The protected checker uses an explicit reviewed backlog-to-contract activation map. An
unopened contract or function must retain the exact
`Phase9ImplementationNotFrozen()` mutating body. A specifically activated implementation
may succeed only after its activation ADR and tooling row are complete. Selector, event,
error, tuple, base, field, slot, offset, type, compiler-setting, or storage-order drift
remains blocked pending a separate additive compatibility decision.

For the first activation, `UNI-ADR-015` accepts ADR 0020 and its checker mapping before
`UNI-PAYOFF-001` can complete. The implementation checkpoint must prove the frozen
external `IPayoffQuoteEngineV2` ABI and exact `PayoffQuoteEngine` storage layout remain
compatible while its new source hashes and independent architecture/security review are
recorded separately.

For atomic refinance, `UNI-ADR-016` accepts ADR 0021's boundary, `UNI-ADR-017`
accepts ADR 0022's factory/account/position bootstrap semantics, and `UNI-ADR-018`
accepts ADR 0023's synthetic-local three-library/seven-call/ten-CREATE candidate
architecture without activating an implementation or deployment. `UNI-ADR-019`
accepts ADR 0024's explicit Anvil nonce precondition and exact
verification-before-governance-grant order without executing that grant. `UNI-ADR-020`
accepts ADR 0025's computable execution observations, alias-aware payout conservation,
single durable completion transition, and four-phase lien handoff without opening D3
or changing any frozen interface. The later
implementation checkpoint is method-level: it may activate only the exact factory,
account, custody, lien, coordinator, and position-manager methods listed by ADRs 0021
and 0022, while the candidate must also pass ADR 0023's linked-module checker and
nonce-10 deployment-evidence gates plus ADR 0024's activation-topology controls,
retains the exact freeze stub for every other mutator, and requires
`UNI-ADR-020`, `UNI-REFI-001`, and `UNI-REFI-002` as one bundled gate. The exact additive ABI allowlist
contains only coordinator-owned `RefinanceStateTransitioned` and
`UnknownFundingCommitment(bytes32)`, plus lien-registry-owned
`UnknownLienHandoff(bytes32)`; no selector, other event/error, tuple, storage, base,
slot, offset, type, or order may drift. Both refinance backlog
rows remain incomplete until implementation, reference/deployment evidence, adversarial
tests, and independent reviews pass on one source head.

### 9A — Boundary, schemas, and models

- accept ADR 0019;
- define data layouts, identities, policies, equations, and accounts;
- add canonical Protobuf and deterministic four-language bindings;
- build independent Python and TypeScript models/goldens;
- register risks, assumptions, backlog, and Phase 8 residual records.

### 9B — Payoff and refinance

- implement debt account, quote engine, lien registry, replacement account, and
  coordinator;
- prove quote freshness and atomic refinance;
- implement funding cancellation, expiry, refund, exact replay, and collision tests.

### 9C — Restructuring and consent

- implement policy, snapshot registry, controller, typed signatures, votes, and exact
  amendment;
- prove one-position-one-vote, policy caps, borrower consent, quorum, and no debt
  disappearance.

### 9D — Funded protection

- implement reserve vault, reserve policy, coverage, premium, adjudicator set, claim,
  payout, guarantee, and solvency metrics;
- prove custody, segregation, stress haircuts, capacity, policy limits, eligibility,
  payment conservation, and no duplicate claim.

### 9E — Loss and recovery

- implement canonical loss, actual receipt verification, write-off, subrogation, later
  recovery, allocation, and borrower surplus;
- add migrations, services, accounting, reconciliation, evidence, restart, and
  least-privilege roles.

### 9F — Simulations, release, and review

- run stale quote, interruption, reentrancy, competing lien, consent replay, reserve
  impairment, duplicate claim, guarantee failure, write-off, and recovery simulations;
- run full foundation, schema, ABI, architecture, privilege, dependency, secret, local
  flow, release-evidence, reset, and post-reset gates;
- complete internal security review; and
- complete a separate Phase 9 engineering exit PR.

## Required acceptance tests

The Phase 9 exit must prove:

- the exact pre-code ABI/storage freeze passed before business logic, every Phase 9
  deployable is imported and formatted, and ABI/storage snapshots regenerate without
  drift under their dedicated checkers;
- `Phase9LocalSyntheticToken` has exact metadata, six decimals, fixed constructor-only
  supply, exact ERC-20 errors and balance deltas, no privileged surface, and no Phase 8
  registration, route, allowance, worker, or manifest reference;
- payoff components and net amount match canonical debt at one version;
- quote expiry and every state-changing debt event invalidate execution;
- funding, payoff, lien handoff, activation, fee, and borrower proceeds are atomic;
- old debt is zero and exactly one senior lien remains after refinance;
- every pre-execution terminal refinance returns funding once without moving collateral;
- restructuring uses the original amendment policy, complete disclosure, borrower
  consent, immutable position snapshot, quorum, approval, and exact schedule;
- duplicate, foreign, transferred, or post-snapshot positions cannot add weight;
- debt reduction has explicit concession, settlement, claim, write-off, or forgiveness
  accounting;
- reserve assets are actually held, segregated, stress-valued, and not counted in
  treasury, bridge, collateral, or another pool;
- commitments and approved payables never exceed disclosed capacity;
- claims cannot exceed eligible loss, deductible/percentage result, policy remaining,
  approval, or payout liquidity;
- claim payout uses the canonical beneficiary and creates exact subrogation;
- a guarantor promise does not reduce loss before actual receipt;
- collateral, guarantee, claim, write-off, and later recovery share one loss identity
  and cannot be double counted;
- later recovery allocates deterministically and reconciles to token custody and
  journals;
- stale writers, conflicting replay, response loss, restart, rollback, privilege, and
  append-only tests pass;
- executable or explicit non-applicability evidence covers the complete invariant
  traceability matrix above, and randomized sequences preserve every stateful invariant
  exercised by the product;
- a clean checkout runs the complete nonzero local flow and resets with one command;
  and
- no real reserve, guarantee, recovery, provider, asset, identity, public network,
  production credential, or real fund is involved.

## Production boundary

The implementation must reject non-loopback providers and any configuration marked as
containing real value. Local fixtures may use unlocked Anvil accounts and deterministic
test signers only. Evidence contains synthetic identifiers and content hashes only; raw
personal data, production identity attributes, payment credentials, legal records, and
external provider payloads are prohibited.

No claim in this document is an actuarial, legal, accounting, solvency, custody,
consumer-protection, or enforceability conclusion. The governing reserve coverage ratio
uses a deterministic synthetic modeled-loss-at-target-confidence fixture; the separate
commitment ratio uses only local commitments and payables. Neither is a regulatory,
actuarial, or commercial capital measure.

Phase 10 cannot treat this milestone as authority for governance, staking, liquidity,
secondary markets, reserve investment, or socialized loss.
