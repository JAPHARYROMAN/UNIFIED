# Phase 9 Data and Storage Layouts

Status: frozen implementation boundary for synthetic local engineering

## Scope and authority

This document freezes the Phase 9 storage, identity, schema, accounting, and release
layouts subordinate to ADR 0019 and the Phase 9 architecture. The complete product runs
only on the isolated local EVM home domain with chain ID `31337`. Every token, loan,
party, position, reserve, guarantee, claim, loss, receipt, signature, provider response,
and journal is synthetic test data.

Real value, real reserves, production insurance or guarantees, public networks, public
testnets, live providers, production endpoints, production keys, real identities, real
loans, real collateral, and legally operative recovery evidence are prohibited.
Mocked legal or off-chain evidence is descriptive only. It cannot create value without
an exact local synthetic token receipt.

Authority does not move between storage systems:

- `Phase9LocalSyntheticToken` is the sole Phase 9 local settlement-token fixture; its
  fixed supply and ERC-20 balances are authoritative for synthetic value movement;
- `Phase9LoanAccount` is authoritative for debt components, debt state version, terms
  version, servicing state, and loan closure;
- `PayoffQuoteEngine` is authoritative for immutable quote content and disposition
  derived from a canonical debt snapshot;
- `RefinanceCoordinator` is authoritative for the local funding escrow and atomic
  refinance result;
- `LienRegistry` is authoritative for the single enforceable senior lien;
- `PositionManagerV2` is authoritative for positions and historical position rights;
- `RestructuringController` is authoritative for proposals, consent, votes, and
  amendment execution evidence;
- `InsuranceReserveVault` token custody is authoritative for funded product-pool assets;
- `InsuranceManager` is authoritative for coverage, claim, adjudication, and payment
  state, but cannot invent reserve custody;
- `GuaranteeVault` and `RecoveryManager` are authoritative for synthetic guarantee,
  loss, receipt, entitlement, write-off, and recovery-allocation state;
- finalized authenticated EVM events are authoritative inputs to PostgreSQL projections
  and accounting;
- PostgreSQL owns durable coordination, transition history, journal links,
  reconciliation, and release evidence but cannot create an EVM effect;
- Redpanda and MinIO retain replayable delivery or evidence artifacts and never create
  debt, consent, a lien, reserve capacity, a claim, a loss, or a recovery; and
- application read models and solvency dashboards are derived and non-authoritative.

All monetary fields use canonical base-10 integer units in one explicit registered asset.
Every durable fact has a schema version, source authority, immutable content digest,
correlation and causation identifiers, source-event identity, and UTC timestamp.

## Phase 9 local settlement-token authority

The exact accepted token is `Phase9LocalSyntheticToken` deployed on chain ID `31337`.
It has name `Unified Phase 9 Local Synthetic Unit`, symbol `P9UNIT`, six decimals, and
fixed supply `1_000_000_000_000_000` base units, minted once by
`constructor(address fixtureAllocator)`. The constructor rejects another chain or the
zero allocator. There is no later mint, burn, fee, rebase, callback, permit, pause,
deny-list, role, upgrade, rescue, bridge, faucet, or administrator transfer path.

The token name and symbol are neutral fixture labels. They create no currency
denomination, fiat or USD peg, redemption, backing, exchange rate, market value,
payment claim, legal tender status, or provider obligation.

Its exact external selectors, events, and eight custom errors are frozen in the Phase 9
architecture: the two Phase 9 constructor errors plus the six OpenZeppelin `IERC20Errors`
errors. The implementation is OpenZeppelin Contracts `5.6.1` ERC-20 with only the
six-decimal override and fixed constructor mint. Its inherited storage is exactly:

```solidity
mapping(address account => uint256) private _balances;                         // slot 0
mapping(address account => mapping(address spender => uint256)) private _allowances; // slot 1
uint256 private _totalSupply;                                                   // slot 2
string private _name;                                                          // slot 3
string private _symbol;                                                        // slot 4
```

The derived contract declares no non-constant storage. Compiler storage-layout output
is still authoritative for encoding metadata and MUST match these five entries. Every
Phase 9 component constructor and active policy binds the exact token address and asset
ID. Under Foundry `1.7.1`, Solidity `0.8.36`, optimizer runs `200`, EVM Prague, and
OpenZeppelin Contracts `5.6.1`, its exact deployed runtime code hash is
`0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5`, equivalently
`keccak256(type(Phase9LocalSyntheticToken).runtimeCode)`. Every active payoff issue and
first consumption requires that exact `settlementToken.codehash` and
`block.chainid == 31337`; matching the ERC-20 interface or metadata is insufficient. The
token constructor independently rejects another chain. Phase 8 registries, routes, hubs,
wrapped-token components, workers, and manifests must contain neither; Phase 9 never
accepts `Phase8LocalSyntheticToken`, `WrappedUFT`, or `UnifiedToken` as a substitute.

## Frozen local numerical fixture

The release flow uses the following nonzero synthetic values:

```text
old principal                         90
old accrued interest                   5
old fees                               3
old penalties                          3
old credits                            1
gross old payoff                     101
net old payoff                       100
old lender recipient                   95
net fee and penalty recipient           5

new senior funding                    90
new junior funding                    30
total funding                        120
refinance fee                          2
borrower proceeds                     18

post-refinance accrued interest         5
restructured debt                    125

collateral recovery                   60
actual guarantee payment              10
funded coverage payment               20
residual write-off                    35
later mocked legal-recovery receipt    5

reserve capitalization                60
funded premium                         4
stress haircut basis points        10000
pre-claim eligible reserve assets      64
post-claim eligible reserve assets     44
modeled loss at target confidence     40
pre-claim reserve coverage ratio    1.60
post-claim reserve coverage ratio   1.10
```

The conservation equation is:

```text
120 funding
= 95 old-lender principal and interest
 + 5 bound protocol fee and penalty recipient
 + 2 refinance fee
 + 18 borrower proceeds
```

Credits are nonzero and reduce the old payoff. The architecture's shorthand `100`
payoff is the net executable amount. All executable quote, funding, ledger, and release
records distinguish `gross_payoff_units = 101` from `credit_units = 1` and
`net_payoff_units = 100`. The ordered component-beneficiary commitment binds principal
`90` and interest `5` to the old lender, fees `3` and penalties `3` to the protocol
recipient, and the one-unit credit against that same protocol component route. The
resulting recipient payments are `95` and `5`; aggregate net alone is insufficient
authority.

## Canonical identifiers

All Solidity identifiers below use `keccak256(abi.encode(...))`, never
`abi.encodePacked`. Text domain separators are exact ASCII strings. An ID is not part
of its own preimage. A zero identifier is invalid unless the field is explicitly
optional.

### Loan and quote identities

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

debt_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_PHASE9_DEBT_SNAPSHOT_V1",
  loan_id,
  loan_account,
  debt_state_version,
  principal,
  accrued_interest,
  capitalized_interest,
  fees,
  penalties,
  recoverable_costs,
  credits,
  settlement_asset_id,
  settlement_token,
  as_of
))

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

`capitalized_interest` and `recoverable_costs` remain explicit in the debt snapshot but
are zero in the first quote. A future policy cannot silently fold either into another
component. Supporting a nonzero value requires a new quote-policy version and updated
golden vectors.

ADR 0020 fixes the exact first-slice component vector. All five entries are retained,
including zero amounts, and are never sorted or aggregated:

```text
0 PRINCIPAL          principal          lender_beneficiary       "PRINCIPAL"
1 ACCRUED_INTEREST   accrued_interest   lender_beneficiary       "ACCRUED_INTEREST"
2 FEE                fees               fee_penalty_beneficiary  "FEE"
3 PENALTY            penalties          fee_penalty_beneficiary  "PENALTY"
4 CREDIT             credits            fee_penalty_beneficiary  "FEE_PENALTY_CREDIT"
```

The lender beneficiary is the nonzero owner of the loan's exactly one `ACTIVE` lender
position, whose claim equals principal plus accrued interest. The credit is allocated
only against fees and penalties, so `credits <= fees + penalties`; it is not cash or
recipient-selection authority.

```text
component_beneficiary_hash = keccak256(abi.encode(
  "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1",
  components
))

settlement_route_hash = keccak256(abi.encode(
  "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
  chainid,
  payoff_quote_engine,
  refinance_coordinator,
  loan_id,
  loan_account,
  settlement_asset_id,
  settlement_token,
  lender_beneficiary,
  fee_penalty_beneficiary,
  policy_hash
))
```

For this formula `payoff_quote_engine` is `address(this)`. Both commitments use
`abi.encode`, never `abi.encodePacked`. The component commitment encodes the complete
ordered `IPayoffQuoteEngineV2.PayoffComponentV2[]`, including its dynamic exact strings.
These commitments prevent an aggregate-valid quote from substituting a component,
credit allocation, recipient, asset, token, coordinator, account, or policy.

### Refinance and lien identities

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
  net_payoff,
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

funding_commitment_id = keccak256(abi.encode(
  "UNIFIED_REFINANCE_FUNDING_COMMITMENT_V1",
  refinance_id,
  position_id,
  tranche_id,
  funder,
  amount,
  commitment_nonce
))

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

The ordered collateral-set hash commits every collateral ID, asset ID, quantity, vault,
borrower, and prior lien version. Collateral entries are sorted by raw `bytes32`
collateral ID before hashing.

The external request supplies all-zero `refinance_id` and `quote_id` and empty
`request_digest`. After pure wire/derived/key checks, the coordinator acquires the
old-loan tagged nonce lock before calling external borrower/policy/new-loan/manager
resolvers. The borrower-authenticated transaction then bootstraps the old fixture if absent,
issues the quote internally, derives both IDs, creates the dormant replacement clones,
and stores the accepted record. `new_loan_id`, clone salts, bootstrap/creation IDs, and
predicted manager are quote/refinance-independent; replacement creation happens only
after derivation and no replacement may preexist.

`new_loan_nonce` is immutable, nonzero, stored in `resolution.refinance_requests`, and
bound by `RefinanceRequest.new_loan_nonce`. It is not a separate counter: it must equal
the low-63-bit per-old-loan `refinance_nonce` governed by the coordinator's tagged
single-active lock. Local bootstrap alone uses zero. The factory-global creation nonce
is independent. The new-loan preimage never includes `refinance_id`; `refinance_id`
may therefore bind the already-derived `new_loan_id` without a circular identity
dependency.

### Restructuring identities

```text
position_snapshot_id = keccak256(abi.encode(
  "UNIFIED_POSITION_RIGHT_SNAPSHOT_V1",
  chainid,
  position_manager,
  loan_id,
  terms_version,
  snapshot_block,
  position_root,
  eligible_weight,
  position_count,
  quorum_bps,
  approval_bps,
  policy_hash
))

restructure_id = keccak256(abi.encode(
  "UNIFIED_RESTRUCTURE_V1",
  chainid,
  restructuring_controller,
  loan_id,
  active_terms_version,
  debt_state_version,
  amendment_policy_hash,
  modification_mask,
  amended_terms_hash,
  amended_schedule_hash,
  disclosure_hash,
  accounting_delta_hash,
  position_snapshot_id,
  borrower,
  review_starts_at,
  voting_ends_at,
  execute_by,
  proposal_nonce
))

vote_id = keccak256(abi.encode(
  "UNIFIED_RESTRUCTURE_POSITION_VOTE_V1",
  restructure_id,
  position_id,
  snapshot_owner,
  snapshot_weight,
  support
))
```

Borrower consent uses the exact signature domain frozen in the Phase 9 architecture and
binds chain ID, controller, restructuring and loan IDs, active terms version, amended
terms, disclosure, accounting delta, consent nonce, and deadline.

### Protection and recovery identities

```text
pool_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_PRODUCT_POOL_V1",
  chainid,
  insurance_reserve_vault,
  product_hash,
  settlement_asset_id
))

coverage_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_COVERAGE_V1",
  insurance_manager,
  pool_id,
  policy_version_id,
  reserve_policy_hash,
  loan_id,
  beneficiary,
  settlement_asset_id,
  covered_event_mask,
  deductible,
  coverage_bps,
  coverage_limit,
  premium,
  loss_priority,
  subrogation_priority,
  valid_from,
  expires_at,
  coverage_nonce
))

loss_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_LOSS_V1",
  recovery_manager,
  loan_id,
  debt_state_version,
  default_event_id,
  settlement_asset_id,
  gross_covered_loss_exposure,
  collateral_recovery,
  borrower_credits,
  position_snapshot_id,
  waterfall_policy_hash,
  loss_nonce
))

claim_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_CLAIM_V1",
  insurance_manager,
  coverage_id,
  loss_id,
  claimant,
  requested_amount,
  evidence_hash,
  claim_nonce
))

claim_decision_id = keccak256(abi.encode(
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

claim_payment_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_CLAIM_PAYMENT_V1",
  claim_id,
  decision_id,
  pool_id,
  beneficiary,
  amount,
  payment_nonce
))

guarantee_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_GUARANTEE_V1",
  guarantee_vault,
  loan_id,
  guarantor,
  settlement_asset_id,
  maximum_amount,
  covered_event_mask,
  priority,
  subrogation_policy_hash,
  valid_from,
  expires_at,
  guarantee_nonce
))

recovery_source_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_RECOVERY_SOURCE_V1",
  recovery_manager,
  loss_id,
  source_type,
  source_authority,
  source_reference,
  settlement_asset_id,
  amount,
  receipt_transaction_hash,
  receipt_log_index
))

writeoff_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_WRITEOFF_V1",
  recovery_manager,
  loss_id,
  debt_state_version,
  residual_loss_exposure,
  writeoff_amount,
  position_allocation_hash,
  recovery_assessment_hash,
  reason_code,
  approval_policy_hash,
  writeoff_nonce
))

recovery_allocation_id = keccak256(abi.encode(
  "UNIFIED_PHASE9_RECOVERY_ALLOCATION_V1",
  recovery_manager,
  loss_id,
  recovery_source_id,
  waterfall_policy_hash,
  allocation_sequence,
  allocation_hash
))
```

`pool_id` is policy-version-independent: one vault, product, and settlement asset retain
one pool identity across delayed policy upgrades. Each coverage instead binds the exact
`policy_version_id` and `reserve_policy_hash`; a policy change therefore produces a
different `coverage_id` and coverage digest without fragmenting pool custody.

Claim adjudication signatures use `claim_decision_id` as the exact
`UNIFIED_CLAIM_ADJUDICATION_V1` digest frozen in the Phase 9 architecture. A changed
`loss_state_version` invalidates the decision. The signed `adjudicated_amount` records
adjudicator judgment; `approved_amount` is derived by the contract as the lesser of
that signed amount and the current canonical approval cap. Signatures cannot select a
beneficiary, pool, settlement asset, loss, policy, or amount outside the stored claim
and decision.

## Version-9 Solidity layouts

Compiler and optimizer settings remain those pinned by the repository. All Phase 9
contracts are non-upgradeable. Per-instance configuration initialized once is immutable
for the lifetime of the instance even where clone-compatible storage is used. The field
inventories below are mandatory logical state, but they are not permission to infer an
untyped compiler layout. Except for the exact token and payoff engine declarations
frozen below, the mandatory pre-code freeze in the Phase 9 architecture must replace
each inventory with a compileable typed declaration before any state-changing business
logic is accepted. The compiler artifact then becomes the exact slot/offset/type
authority. Implementation must fail ABI/storage checks if a frozen field is reordered,
removed, retyped, or encoded differently.

Every implementation MUST capture compiler storage-layout artifacts and fail
ABI/storage checks on incompatible drift; a prose inventory or nonempty snapshot
directory is not evidence.

### Exact `PayoffQuoteEngine` storage declaration

The first-slice payoff engine uses the exact `IPayoffQuoteEngineV2` types frozen in the
architecture and the following declaration order. All members are private; no generated
public getter may add an unreviewed selector.

```solidity
struct QuoteDispositionV2 {
    IPayoffQuoteEngineV2.QuoteState state;
    bytes32 sourceEventId;
    bytes32 refinanceId;
    uint64 debtStateVersion;
    uint64 recordedAt;
}

ILoanRegistry private _loanRegistry;
address private _quotePolicyRegistry;
uint64 private _maximumQuoteValidity;
address private _approvedPhase9Factory;
address private _refinanceCoordinator;
mapping(bytes32 loanId => uint64 nonce) private _nextQuoteNonce;
mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffQuoteV2 quote_) private _quotes;
mapping(bytes32 quoteId => IPayoffQuoteEngineV2.PayoffComponentV2[] components)
    private _quoteComponents;
mapping(bytes32 quoteId => QuoteDispositionV2 disposition) private _quoteDispositions;
mapping(bytes32 loanId => bytes32 quoteId) private _latestQuoteId;
```

Configuration is constructor-set and never mutated. Quote tuples and component arrays
are inserted once; the tuple's stored state is `ISSUED`. Only the disposition mapping
changes once from `NONE` to one terminal state. The external `quote(bytes32)` getter
returns memory copies, overlays the effective disposition state on the returned tuple,
and never exposes Solidity-generated mapping getters.

ADR 0020 activates the existing `_quotePolicyRegistry` address as an immutable typed
policy source without changing this declaration. Its only required internal selector is:

```solidity
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
```

The return is accepted only when active, nonzero, and equal to the account-bound policy
set, asset, and token, and when `maximumValidity == _maximumQuoteValidity`. This selector
belongs to the local `IPhase9PayoffQuotePolicySource` implementation dependency. It adds
no external `PayoffQuoteEngine` selector or storage.

The returned policy hash must equal:

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

This binds the policy to the local domain, exact engine and source, account, policy set,
beneficiary, asset, token, and validity limit. After the first successful issuance, every
successor for the same `(loanId, loanAccount)` reconstructs this prior binding from the
latest quote, its fixed components, account configuration, and constructor-bound source
and maximum. It must reproduce the prior stored `quote.policyHash`, including after
terminal disposition or effective expiry. A changed binding fails before any write or
nonce advance. Consumption performs the same reconstruction against the consumed quote;
no additional storage field is permitted.

At issue and consume, `_loanRegistry.loanAccount(loanId)` must independently equal
`IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId)`. Both must equal the
stored quote account and that account's self-declared configuration. A mismatch is a
substitution failure, not a recoverable routing choice.

At both gates, the account's configured position manager must independently equal
`IPhase9LoanFactory(_approvedPhase9Factory).positionManager(loanId)` and contain deployed
code. The chain must be `31337`, and the configured settlement token's code hash must be
the exact pinned `Phase9LocalSyntheticToken` runtime hash above.

`_nextQuoteNonce[loanId] == 0` means uninitialized. The first successful issuance stores
quote nonce `1` and advances the next nonce to `2`; only a successful issuance advances
it. `_latestQuoteId` enforces one effective issued quote per loan. An unexpired quote with
no terminal disposition cannot be superseded. A terminal or effectively expired quote
permits a new successful nonce. Exhaustion at `type(uint64).max` reverts
`QuoteReplayConflict(bytes32(0))` before creating an identity.

After deriving `quoteId` and before any quote, component, latest-ID, or nonce write,
`quoteId == bytes32(0)` or `_quotes[quoteId].quoteId != bytes32(0)` reverts
`QuoteReplayConflict(quoteId)`. A collision never returns, mutates, or overwrites the
previous record.

Validity is `[issuedAt, validUntil)`, and the maximum duration is inclusive. `validUntil`
is the coordinator-selected sole time input; `issuedAt` is the checked block timestamp,
and no caller supplies a clock, duration, or alternate issuance time. When no terminal
disposition exists, `quote()` overlays `EXPIRED` at
`block.timestamp >= validUntil` without writing. Coordinator invalidation then persists
`EXPIRED`; before the boundary it persists `INVALIDATED`.

For refinance-issued quotes the coordinator supplies the policy-bound proposal
`expiresAt` as this sole `validUntil` input and accepts the request only when the returned
quote and stored refinance record retain exact equality. Quote and refinance expiry can
therefore never diverge.

The disposition fields are the replay identity. Exact terminal replay is idempotent and
does not write or emit twice. A changed replay of the same action is a
`QuoteReplayConflict`; an attempted different terminal action is `QuoteTerminal`.
Invalidation requires a nonzero `sourceEventId`; after caller authorization and quote
existence validation, zero reverts `InvalidQuoteInput()` before terminal classification
and without a disposition write or event. Successful consumption first re-resolves the
complete registry, factory account and position manager, account, debt, position, local
chain, exact token runtime, deterministic immutable policy, component, route, and
quote-ID facts and requires expected, stored, and live debt versions to match.

The local engine/coordinator constructor cycle does not add a setter or deployment slot.
In one transaction, a dedicated deployer predicts the coordinator address at the
immediately next sequential `CREATE` after the engine, deploys the engine with that
prediction, and then performs that exact coordinator creation with no intervening
creation or callback. It supplies the actual engine to the coordinator. In-transaction
address, code, and constructor-argument checks validate every required nonzero/local
dependency, and the activated engine constructor independently enforces its local
dependencies. Any mismatch makes the whole transaction revert. Post-transaction
raw-storage reads use the reviewed layout to cross-check both private bindings before
activation; those reads are evidence only and are never claimed to cause the transaction
to revert. `CREATE2`, a mutable setter, a proxy, late registration, or rebinding is
prohibited.

### `Phase9LoanFactory`

ADR 0022 fixes the implementation semantics of the already-frozen factory layout. The
factory-global `_nextLoanNonce` starts at one. A unique creation reserves the current
nonce and creation identity under transaction rollback, rejects exhaustion before an
addition can wrap, and advances exactly once only when clone deployment, both
initializations, registry registration, mapping writes, and the creation event all
succeed.

Creation replay is classified by the supplied `creationId` and the stored
`_processedCreationIds`/`_creationRequests` entry before consulting the current global
nonce or attempting a clone or registry effect. The exact stored request and the current
active four-field creation-resolver tuple must still match. The full historical bootstrap
payload is not compared because the frozen layout stores no initial-payload hash and live
debt may legitimately change. An exact replay verifies the stored protocol-version-9
registry identity and returns the stored account and manager without recomputing
`creationId` from the now-advanced nonce, writing, emitting, or calling
`LoanRegistry.registerLoan`; changed reuse reverts
`InvalidPhase9LoanConfiguration`. A new creation identity for an already existing loan
reverts `Phase9LoanAlreadyExists(loanId)`. Every other factory validation, authority,
resolver, mode, nonce, prediction, implementation, deployment, initialization, or
registration inconsistency uses `InvalidPhase9LoanConfiguration`; no clone-library error
is added to the ABI.

The two implementation instances have exact reviewed runtime code and disable their own
initializers by setting the frozen `initialized` storage member to `true` through its
declaration initializer. Fresh minimal-clone storage remains zero. The factory uses a
private OpenZeppelin-5.6.1-byte-compatible EIP-1167 deterministic-clone helper so the
standard salt, prediction, creation code, and runtime remain reproducible without
importing additional OpenZeppelin errors into the frozen factory ABI. It deploys and
checks both predicted clones only after reserving the exact request, processed flag,
predicted account/manager mappings, and incremented nonce. It initializes the loan
account first, then initializes the manager. Manager initialization authenticates the
factory through the already-written account configuration and verifies the reciprocal
loan ID, manager, and settlement-token bindings. Only then may the factory register and
verify protocol version 9 in `LoanRegistry` and emit. Every failure reverts the
reservation and all earlier effects.

The factory and account validate the exact ADR-bound synthetic-local asset identifier,
deployed settlement-token address, and reviewed `Phase9LocalSyntheticToken` runtime. They
do not call or impersonate the coordinator's typed asset resolver and do not repurpose a
policy-registry field as an asset source. The coordinator remains solely responsible for
the asset registry's `active`, decimals, exact-balance-delta, and runtime-hash tuple and
for equality with both loan configurations.

### `Phase9LoanAccount`

```text
configuration:
  factory
  loan_registry
  settlement_token
  settlement_asset_id
  borrower
  position_manager
  collateral_custody
  lien_registry
  payoff_quote_engine
  refinance_coordinator
  restructuring_controller
  insurance_manager
  recovery_manager
  loan_id
  agreement_hash
  policy_set_hash
  amendment_policy_hash
  protection_policy_hash
  recovery_policy_hash
  protocol_version = 9

mutable, in this order:
  lifecycle
  servicing_state
  terms_version
  debt_state_version
  state_nonce
  commencement_time
  maturity_time
  schedule_hash
  outstanding_principal
  accrued_interest
  capitalized_interest
  accrued_fees
  accrued_penalties
  recoverable_costs
  unapplied_credit
  covered_loss_exposure
  realized_loss
  written_off_amount
  recovered_after_writeoff
  active_refinance_id
  active_restructure_id
  agreement_version_hashes
  processed_operation_ids
  initialized
```

Debt-changing operations increment `debt_state_version`. Terms-changing operations
increment `terms_version`. A write-off does not delete historical debt, agreement, loss,
position, or recovery-right records. Terminal closure cannot return to active servicing.

Every identifier or commitment in `LoanConfiguration` is nonzero: settlement asset,
loan, agreement, policy set, amendment policy, protection policy, and recovery policy.
The borrower is nonzero, and every configured contract dependency is nonzero and contains
code.
Only the mode- and state-specific zero sentinels expressly enumerated by ADR 0021 and ADR
0022 are accepted; there is no implicit optional zero policy hash. In particular, dormant
replacement initialization retains `CREATED/NONE`, zero debt, versions, times, schedule,
and active operation IDs, while an active bootstrap has the exact nonzero version and
schedule required by its resolver.

Agreement version zero is permanently the absent sentinel:
`agreementVersionHash(0) == bytes32(0)`. Dormant initialization does not write a version
zero mapping entry. Active bootstrap initialization records the immutable configuration
agreement hash at its nonzero initial terms version; replacement activation does the same
at its nonzero policy-bound terms version and rejects an already occupied version.

Initialization authenticates before classifying initialized or configuration state: a
wrong caller uses `UnauthorizedPhase9LoanCaller(caller)`, while an authenticated repeat
or invalid configuration/debt shape uses `InvalidPhase9LoanOperation`. Reuse of a
processed nonzero operation ID uses `Phase9LoanOperationReplay(operationId)`. A
coordinator replay that has already been classified upstream does not call the account a
second time. After validation, the account sets its initializer flag before any possible
interaction, with transaction rollback preserving a clean failure.

### `PayoffQuoteEngine`

```text
configuration:
  loan_registry
  quote_policy_registry
  maximum_quote_validity
  approved_phase9_factory
  refinance_coordinator

mutable:
  loan_id -> next_quote_nonce
  quote_id -> immutable Quote
  quote_id -> terminal QuoteDisposition
  loan_id -> latest_quote_id
```

`Quote` stores the complete preimage fields. A disposition stores only `state`,
`source_event_id`, `refinance_id`, `debt_state_version`, and `recorded_at`. Content is
never recalculated or overwritten.

### `CollateralCustodyV2` and `LienRegistry`

`CollateralCustodyV2` stores:

```text
configuration:
  asset_registry
  lien_registry
  emergency_controller

mutable:
  collateral_id -> immutable custody identity and current quantity/status
  asset_id -> total exact custody
  processed custody operation IDs
```

For local bootstrap, `recordCustody` is coordinator-only through the immutable lien
registry and is a value-bearing operation. It first authenticates `msg.sender` as the
coordinator resolved from that registry, rejects a zero custody operation ID, calls the
constructor-bound asset source's exact `resolveCustodyAsset(bytes32)` tuple for the
exact-balance chain-31337 synthetic collateral token/runtime, and reconstructs the
bootstrap-bound custody identity from the passed operation ID and canonical facts.
After all checks, it marks the operation processed, records `HELD`, and increases
checked `total exact custody` before calling `transferFrom`; it then verifies exact
borrower and custody balance deltas. Any transfer or delta failure rolls back those
effects. Only afterward may the coordinator register the lien. Exact
same-operation/same-record replay validates record plus attributable
holdings/aggregate without a second transfer; changed-record reuse of that operation
ID or an alternate operation ID for existing collateral conflicts. Allowance, balance,
token, code, fee/rebase/callback, delta, overflow, or reentrancy failure reverts the
complete request.

`LienRegistry` stores:

```text
collateral_id -> Lien {
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
}
handoff_id -> immutable handoff result
```

`pending_target_loan_id` is not an enforceable claim. `senior_loan_id` remains the only
senior owner until the atomic handoff completes. No method releases collateral to the
borrower during handoff.

### `RefinanceCoordinator`

```text
configuration:
  loan_registry
  phase9_loan_factory
  payoff_quote_engine
  lien_registry
  asset_registry
  policy_registry
  emergency_controller
  treasury_fee_recipient

mutable:
  old_loan_id -> next_refinance_nonce
  refinance_id -> RefinanceRecord
  refinance_id -> ordered funding commitment IDs
  commitment_id -> immutable commitment and funding result
  refinance_id -> escrowed units
  refinance_id -> terminal execution or refund result
  processed operation IDs
```

`RefinanceRecord` stores all ID preimage fields plus current monotonic state, state
version, exact accepted funding, execution-attempt count, and terminal evidence.
Execution has no arbitrary target, recipient, token, amount, or calldata.

`old_loan_id -> next_refinance_nonce` is tagged without changing its `uint64` storage:
bit 63 is `ACTIVE`, low 63 bits are the active or next nonce, raw zero means unlocked
next one, and unlocked `0x7fff_ffff_ffff_ffff` is exhausted. Acceptance requires a
high-bit-clear matching nonce below the mask and stores the active encoding before
external calls. `ACCEPTED`, `FUNDING_ESCROWED`, and `REFUNDABLE` retain it; exact
terminal paths verify ownership then store `nonce + 1` after all effects. Terminal
replay branches before lock validation.

ADR 0021 freezes the internal policy dependency to exactly
`resolveLoanCreation(bytes32 policySetHash,bytes32 loanId)` returning the full
`LoanConfiguration`, closed creation mode, bootstrap ID, and active flag;
`resolveBootstrap(bytes32 bootstrapId)` returning policy/loan IDs, exact initial
`DebtState`, tranche/position/custody/lien vectors, and active flag; and
`resolveRefinancePolicy(bytes32)` returning the exact refinance bindings and replacement
template. Hard caps are collateral `16`, commitments `32`, tranches `8`, and positions
`32`. The replacement template has zero `activeRefinanceId`; the coordinator injects
only the derived ID at activation.

Unknown refinance-scoped views revert `UnknownRefinance`; unknown commitments and
handoffs use the exact two additive typed errors, and unknown liens use the historical
`UnknownLien`. A known nonterminal `terminalResult` is the all-zero result. Boolean
membership/processed views may return false. The one transition event and two typed
errors are the complete additive ABI allowlist.

### `PositionManagerV2`

```text
configuration:
  loan_id
  loan_account
  settlement_token

mutable:
  tranche_id -> immutable tranche configuration and outstanding claim
  ordered tranche IDs
  position_id -> current position
  ordered position IDs
  position_id -> owner checkpoints
  position_id -> voting-power checkpoints
  position_id -> claim checkpoints
  total voting-power checkpoints
  snapshot_id -> immutable snapshot header
  snapshot_id + position_id -> consumed vote right
  initialized
```

Historical getters resolve the greatest checkpoint at or before the requested block.
Position transfer after the snapshot cannot move, duplicate, or erase the snapshotted
vote right.

Tranche IDs and position IDs are inserted in strictly increasing unsigned raw `bytes32`
order, equivalently `uint256(currentId) > uint256(previousId)`. Zero, duplicate, or
decreasing IDs are invalid; tranche `priority` is a separate semantic field and does not
silently redefine the vector ordering. An existing ID is classified before the
new-record order check: a byte-exact existing tranche or position is inert replay, while
changed reuse reverts `InvalidPositionOperation` without a second array entry, checkpoint,
or event. Initialization, tranche registration, and position issuance authenticate the
factory or coordinator through the immutable account configuration on every call and
verify the reciprocal account, manager, loan, and exact local-token runtime. The same
error covers activated-method authority, initialization, cap,
unknown-tranche, and tuple failures; it does not invent an unknown-tranche error or
misuse `UnknownPosition`.

Checkpoint writers require `block.number <= type(uint64).max`. When the final checkpoint
has the current block number they overwrite it; otherwise they append. Owner checkpoints
store the owner with zero value, while voting-power, claim, and total-voting-power
checkpoints store the value with zero owner. Issuing several positions in one transaction
therefore leaves one final total-voting-power checkpoint for that block, and exact issue
replay leaves every checkpoint byte-identical.

Tranches, positions, and checkpoints are nominal immutable issuance history rather
than independent live receivables. Every current consumer resolves manager to loan,
proves factory/registry account agreement, and joins current canonical debt. Registry
terminal, `CLOSED/TERMINAL`, or zero claim-bearing debt makes effective claim and vote
zero regardless of raw `ACTIVE` state or face claim; historical getters alone cannot
authorize payment, transfer, vote, restructure, quote, lien/collateral, liquidation,
recovery, protection, or another current action.

On successful refinance payoff, the registered old account writes the exact closed
debt, calls the existing `LoanRegistry.markTerminal(oldLoanId)` authority, verifies
`isTerminal(oldLoanId)`, and returns atomically. The coordinator independently verifies
the terminal flag and unchanged registry/factory/account identity. The old-debt result
and effective-rights hashes bind that terminal fact; any mark failure, false
postcondition, identity mismatch, or registry reentry rolls every payoff effect back.

### `RestructuringController`

```text
configuration:
  loan_registry
  amendment_policy_registry
  emergency_controller

mutable:
  loan_id -> next_proposal_nonce
  restructure_id -> immutable proposal and current state
  restructure_id -> borrower consent digest and signer
  restructure_id + position_id -> immutable vote
  restructure_id -> support, oppose, and cast weight
  restructure_id -> terminal execution result
```

The proposal stores the position snapshot root and block, eligible weight, quorum,
approval threshold, modification mask, every bounded modification value, hashes of the
new terms, schedule, disclosure, and accounting delta, and all deadlines.

### `InsuranceReserveVault`, `ReservePolicy`, and `InsuranceManager`

`InsuranceReserveVault` stores:

```text
configuration:
  asset_registry
  insurance_manager

mutable:
  pool_id + asset_id -> exact custody units
  funding_event_id -> immutable balance-delta result
  claim_payment_id -> immutable payment result
```

It has no general withdrawal, rescue, treasury transfer, swap, approval, arbitrary call,
bridge, staking, delegation, lending, or investment surface.

`ReservePolicy` versions store:

```text
pool_id
asset_id
token
stress_haircut_basis_points
modeled_loss_at_target_confidence
target_confidence_bps
maximum_coverage_bps
maximum_single_policy_units
aggregate_commitment_limit_units
minimum_reserve_ratio_ray
minimum_commitment_ratio_ray
covered_event_mask
minimum_deductible_units
maximum_deductible_units
premium_policy_hash
adjudicator_set_hash
payout_waterfall_hash
recovery_waterfall_hash
effective_at
expires_at
status
```

Every stored policy and activation path enforces
`0 <= stress_haircut_basis_points <= 10_000` and
`modeled_loss_at_target_confidence > 0`. A policy violating either condition cannot
become active or authorize coverage, a ratio, or a release artifact.

`InsuranceManager` stores:

```text
policy_hash -> immutable policy version
pool_id -> active policy hash
coverage_id -> immutable coverage and current state/totals
claim_id -> immutable claim and current state/totals
decision_id -> immutable signed loss version and adjudicated amount plus
               contract-derived approval cap and approved amount
claim_payment_id -> immutable payment result
adjudicator_set_hash -> immutable threshold set
processed signature and operation IDs
```

Only the product-specific pool is reachable. The protocol-wide insurance allocation,
operating treasury, bridge backing, collateral, and other product pools are not
accepted sources.

### `GuaranteeVault` and `RecoveryManager`

`GuaranteeVault` stores:

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
processed receipt IDs
```

A commitment is memorandum authority only. `paid_amount` increases only with an exact
registered-token receipt.

`RecoveryManager` stores:

```text
loss_id -> LossRecord {
  loan_id
  debt_state_version
  default_event_id
  settlement_asset_id
  gross_covered_loss_exposure
  collateral_credited
  guarantor_credited
  insurance_credited
  other_recovery_credited
  forgiveness_recognized
  residual_loss_exposure
  realized_loss_recognized
  writeoff_recognized
  lender_uncovered_right
  product_pool_subrogation_right
  guarantor_subrogation_right
  later_recovery_allocated
  borrower_surplus
  waterfall_policy_hash
  state
  state_version
}
recovery_source_id -> immutable receipt result
loss_id + entitlement_id -> current bounded entitlement
recovery_allocation_id -> immutable allocation result
writeoff_id -> immutable write-off result
processed source and operation IDs
```

Every credited source shares one `loss_id`. A source reference can affect one loss once.
Write-off cannot exceed residual exposure and does not erase later recovery rights.

### Mandatory typed-layout freeze for remaining components

Before any Phase 9 state-changing logic other than the exact local token constructor is
accepted, a dedicated interface/storage freeze PR MUST convert every remaining logical
inventory above into compileable Solidity declarations. Acceptance requires all of the
following in the same PR:

- exact interfaces, errors, events, tuple types, selector mutability, and event indexing
  under `protocol/src/interfaces/phase9/`;
- shared enum/struct declarations under `protocol/src/resolution/`,
  `protocol/src/protection/`, and `protocol/src/recovery/`, with no shadow tuple types;
- explicit mapping key/value, array element, enum, integer-width, timestamp, checkpoint,
  boolean, initializer, and immutable/configuration types for every stored member;
- compiler-produced artifacts at
  `protocol/storage-layout/phase9/<Contract>.storage.json` for every deployable Phase 9
  contract, including the token and every clone implementation;
- a deterministic checker that compares compiler/settings hash, inheritance order,
  slot, offset, encoding, type ID, byte width, and the recursive member/key/value/base
  graph, and rejects a missing, extra, reordered, or retyped member;
- reviewed ABI snapshots for every Phase 9 contract plus explicit compiled/snapshot
  mappings in `tools/check_abi.py`; a nonempty directory is insufficient;
- imports for every Phase 9 deployable in `ProtocolCompilation.sol`, formatter coverage
  for all Phase 9 source/interface/test/script directories, and contract-size coverage;
  and
- clean-checkout regeneration and protected CI execution of both ABI and storage-layout
  checks before Foundry business-logic tests.

All non-token state-changing stubs revert `Phase9ImplementationNotFrozen()` until this
gate passes. The freeze commits each ABI hash and storage-layout hash into the Phase 9
release schema. Any later change requires explicit additive compatibility review. A
boundary-only document checker cannot waive this pre-code dependency.

## Canonical Protobuf schema

Phase 9 adds exactly four source files:

```text
schemas/proto/unified/v1/refinance.proto
schemas/proto/unified/v1/restructuring.proto
schemas/proto/unified/v1/protection.proto
schemas/proto/unified/v1/recovery.proto
```

They import existing shared types. They do not rename, renumber, reinterpret, or reuse
an existing field or enum value. Generated Solidity, Go, TypeScript, and Python bindings
are deterministic derivatives. Existing `LoanObligationSnapshotEvidence` remains a
Phase 7B synthetic projection and is not payoff authority.

### `refinance.proto`

Frozen enums:

```text
PayoffComponentKind:
  UNSPECIFIED=0 PRINCIPAL=1 ACCRUED_INTEREST=2 CAPITALIZED_INTEREST=3
  FEE=4 PENALTY=5 RECOVERABLE_COST=6 CREDIT=7

PayoffQuoteState:
  UNSPECIFIED=0 ISSUED=1 CONSUMED=2 EXPIRED=3 INVALIDATED=4

RefinanceState:
  UNSPECIFIED=0 REQUESTED=1 QUOTED=2 OFFERED=3 ACCEPTED=4
  FUNDING_ESCROWED=5 EXECUTING=6 COMPLETED=7 REJECTED=8 EXPIRED=9
  CANCELLED=10 REFUNDABLE=11 REFUNDED=12 DISPUTED=13

FundingCommitmentState:
  UNSPECIFIED=0 OFFERED=1 ACCEPTED=2 FUNDED=3 REFUNDABLE=4
  REFUNDED=5 CONSUMED=6

LienHandoffState:
  UNSPECIFIED=0 ACTIVE_OLD=1 EXECUTING=2 ACTIVE_NEW=3 REVERTED=4
  DISPUTED=5
```

The enums retain the complete cross-system vocabulary. Under ADR 0021 the frozen
five-selector on-chain refinance slice first persists `ACCEPTED`; request/quote/offer
and rejection are off-chain evidence stages/outcomes. Its first successful funded
commitment enters `FUNDING_ESCROWED`, additional partial funding stays there, and exact
full funding is required for execution.

Frozen messages and field tags:

```text
CanonicalDebtSnapshot {
  LoanId loan_id=1
  Identifier loan_account_id=2
  Money principal=3
  Money accrued_interest=4
  Money capitalized_interest=5
  Money fees=6
  Money penalties=7
  Money recoverable_costs=8
  Money credits=9
  uint64 debt_state_version=10
  Timestamp as_of=11
  bytes policy_set_hash=12
  bytes snapshot_hash=13
}

PayoffComponent {
  PayoffComponentKind kind=1
  Money amount=2
  PartyId beneficiary_id=3
  string obligation_code=4
}

PayoffQuote {
  Identifier quote_id=1
  LoanId loan_id=2
  CanonicalDebtSnapshot debt=3
  repeated PayoffComponent components=4
  Money gross_payoff=5
  Money credits=6
  Money net_payoff=7
  bytes component_beneficiary_hash=8
  bytes settlement_route_hash=9
  Timestamp issued_at=10
  Timestamp valid_until=11
  uint64 quote_nonce=12
  PolicyReference quote_policy=13
  bytes quote_digest=14
  PayoffQuoteState state=15
}

RefinanceRequest {
  Identifier refinance_id=1
  LoanId old_loan_id=2
  LoanId new_loan_id=3
  PartyId borrower_id=4
  PartyId old_lender_id=5
  Identifier quote_id=6
  Money old_net_payoff=7
  Money new_principal=8
  Money funding_amount=9
  Money refinance_fee=10
  Money borrower_proceeds=11
  bytes component_beneficiary_hash=12
  repeated Identifier collateral_ids=13
  bytes collateral_set_hash=14
  uint64 lien_version=15
  bytes proposed_terms_hash=16
  bytes new_policy_set_hash=17
  Timestamp expires_at=18
  uint64 refinance_nonce=19
  PolicyReference refinance_policy=20
  bytes request_digest=21
  RefinanceState state=22
  uint64 new_loan_nonce=23
  bytes new_position_manager=24
}

`new_position_manager=24` is the additive ADR 0021 corroboration field. It must be
exactly 20 bytes, decode to a nonzero EVM address, and equal the manager
resolved from the approved factory and account/policy bindings before refinance-ID
reconstruction. It never overrides on-chain authority; lengths `0`, `19`, `21`, and
`32`, a zero 20-byte address, and a substituted 20-byte address are rejected.

For this request, non-address `Identifier` and `LoanId` values are exactly `0x` plus
64 lowercase hex digits; address-bearing `PartyId` values are exactly
`evm:31337:0x` plus 40 lowercase hex digits. Money units use unsigned canonical
decimal, every asset is exact `asset:phase9:p9unit` mapped directly to
`0x61737365743a7068617365393a7039756e697400000000000000000000000000`,
timestamps have `nanos=0`, and the refinance policy reference is exact
`phase9-refinance`/`v1` with a 32-byte content hash. Other hash-bearing bytes are
exactly 32 bytes/nonzero where required; input request digest is exactly empty. No
string hash supplies the asset.

RefinanceFundingCommitment {
  Identifier commitment_id=1
  Identifier refinance_id=2
  Identifier position_id=3
  Identifier tranche_id=4
  PartyId funder_id=5
  Money amount=6
  uint64 commitment_nonce=7
  bytes commitment_digest=8
  FundingCommitmentState state=9
}

CollateralLienHandoff {
  Identifier handoff_id=1
  Identifier refinance_id=2
  Identifier collateral_id=3
  LoanId old_loan_id=4
  LoanId new_loan_id=5
  uint64 prior_lien_version=6
  uint64 next_lien_version=7
  LienHandoffState state=8
  bytes evidence_hash=9
}

RefinanceExecutionEvidence {
  Identifier refinance_id=1
  Identifier quote_id=2
  Identifier execution_event_id=3
  LoanId old_loan_id=4
  LoanId new_loan_id=5
  Money funding_amount=6
  Money old_net_payoff=7
  Money refinance_fee=8
  Money borrower_proceeds=9
  repeated CollateralLienHandoff lien_handoffs=10
  bytes old_debt_result_hash=11
  bytes new_activation_result_hash=12
  bytes recipient_balance_delta_hash=13
  bytes component_payout_hash=14
  bytes journal_batch_hash=15
  Timestamp executed_at=16
}

RefinanceRefundEvidence {
  Identifier refinance_id=1
  Identifier commitment_id=2
  Identifier refund_id=3
  PartyId funder_id=4
  Money amount=5
  bytes balance_delta_hash=6
  Timestamp refunded_at=7
}
```

The frozen `PayoffQuote` wire tags intentionally omit deployment authority. Every
quote codec MUST resolve `payoff_quote_engine`, `chainid`, the canonical
`settlement_asset_id` bytes and matching `AssetId.value`, and `settlement_token`
from an immutable authoritative tuple held only by the codec closure. The public
`TrustedPayoffQuoteContext` is solely an opaque singleton identity token created in
that same closure: it stores and exposes no engine, chain, asset, token, capability,
snapshot, mint function, or registry field. No public constructor or arbitrary-value
factory may exist. That token is service wiring, not command, event, API, or
per-request data; callers MUST NOT construct, substitute, or override it. The codec
MUST require strict singleton identity before returning its closure-held tuple and
MUST never resolve authority from object attributes, private-name lookups, symbols,
getters, prototypes, or caller values. A deployment or registry change requires a
new internally authenticated codec closure; it cannot be expressed through request
data.

The Python token MUST be an empty, immutable tuple-backed identity with empty slots
and blocked normal construction and subclassing; `object.__setattr__` cannot add
authority or replace its class, `object.__new__` is unsafe for the type, and any
lower-level tuple forgery fails the identity check. The TypeScript token MUST be a
frozen, property-free, null-prototype object; assignment, prototype tampering,
property copying, and forged null-prototype objects cannot alter or satisfy its
identity. Capability, snapshot, class, getter, and mint-based implementations are
non-conforming.

Before hashing, the codec MUST verify that every wire `Money.asset_id` matches the
trusted asset, that the loan account and quote policy come from the canonical debt
snapshot and quote respectively, and that the payoff equation, exact integer
encoding, timestamp precision, and fixed-width values are canonical. The exact
`UNIFIED_PAYOFF_QUOTE_V1` digest MUST match both `quote_digest` and `quote_id`.
Python and TypeScript implementations share the same committed golden vector;
neither implementation may accept caller-provided engine, chain, asset, or token
substitutions. Test code may expose only the fixed no-argument canonical golden
context. The golden fixture is not an alternate-value factory and MUST NOT become a
production registry-adapter API. Low-level preimage resolution and encoding remain
module-private so a request caller cannot bypass trusted-context validation.

### `restructuring.proto`

Frozen enums:

```text
RestructuringState:
  UNSPECIFIED=0 PROPOSED=1 REVIEW=2 VOTING=3 APPROVED=4 EXECUTING=5
  EFFECTIVE=6 REJECTED=7 EXPIRED=8 WITHDRAWN=9 DISPUTED=10

RestructuringVoteChoice:
  UNSPECIFIED=0 SUPPORT=1 OPPOSE=2 ABSTAIN=3
```

Frozen messages and field tags:

```text
PositionRightSnapshot {
  Identifier snapshot_id=1
  LoanId loan_id=2
  uint64 terms_version=3
  uint64 snapshot_block=4
  bytes position_root=5
  string eligible_weight=6
  uint32 position_count=7
  uint32 quorum_basis_points=8
  uint32 approval_basis_points=9
  bytes policy_hash=10
}

PositionRight {
  Identifier snapshot_id=1
  Identifier position_id=2
  Identifier tranche_id=3
  PartyId owner_id=4
  Money claim=5
  string voting_weight=6
  bytes proof_hash=7
}

RestructuringProposal {
  Identifier restructure_id=1
  LoanId loan_id=2
  PartyId proposer_id=3
  uint64 active_terms_version=4
  uint64 debt_state_version=5
  PolicyReference amendment_policy=6
  uint64 modification_mask=7
  bytes amended_terms_hash=8
  bytes amended_schedule_hash=9
  bytes disclosure_hash=10
  bytes accounting_delta_hash=11
  PositionRightSnapshot position_snapshot=12
  PartyId borrower_id=13
  Timestamp review_starts_at=14
  Timestamp voting_ends_at=15
  Timestamp execute_by=16
  uint64 proposal_nonce=17
  bytes proposal_digest=18
  RestructuringState state=19
}

RestructuringVote {
  Identifier vote_id=1
  Identifier restructure_id=2
  PositionRight position_right=3
  RestructuringVoteChoice choice=4
  bytes authorization_hash=5
  Timestamp recorded_at=6
}

BorrowerRestructuringConsent {
  Identifier consent_id=1
  Identifier restructure_id=2
  LoanId loan_id=3
  PartyId borrower_id=4
  uint64 active_terms_version=5
  bytes amended_terms_hash=6
  bytes disclosure_hash=7
  bytes accounting_delta_hash=8
  uint64 consent_nonce=9
  Timestamp valid_until=10
  bytes signature=11
  bytes consent_digest=12
}

LoanAmendment {
  Identifier amendment_id=1
  Identifier restructure_id=2
  LoanId loan_id=3
  uint64 prior_terms_version=4
  uint64 next_terms_version=5
  uint64 prior_debt_state_version=6
  uint64 next_debt_state_version=7
  bytes prior_agreement_hash=8
  bytes amended_terms_hash=9
  bytes amended_schedule_hash=10
  bytes accounting_delta_hash=11
  Money capitalized_interest=12
  Money waived_fees=13
  Money waived_penalties=14
  Money forgiven_amount=15
  bytes amendment_digest=16
}

RestructuringExecutionEvidence {
  Identifier restructure_id=1
  Identifier execution_event_id=2
  LoanAmendment amendment=3
  string eligible_weight=4
  string cast_weight=5
  string support_weight=6
  string oppose_weight=7
  bytes borrower_consent_digest=8
  bytes position_snapshot_root=9
  bytes journal_batch_hash=10
  Timestamp executed_at=11
}
```

### `protection.proto`

Frozen enums:

```text
ReservePolicyState:
  UNSPECIFIED=0 SCHEDULED=1 ACTIVE=2 RESTRICTED=3 EXPIRED=4 DEPRECATED=5

CoverageState:
  UNSPECIFIED=0 DRAFT=1 PREMIUM_PENDING=2 ACTIVE=3 CLAIM_PENDING=4
  EXHAUSTED=5 EXPIRED=6 CANCELLED=7

PremiumState:
  UNSPECIFIED=0 DUE=1 FUNDED=2 APPLIED=3 REFUNDED=4

InsuranceClaimState:
  UNSPECIFIED=0 SUBMITTED=1 UNDER_REVIEW=2 APPROVED=3
  PARTIALLY_APPROVED=4 REJECTED=5 EXPIRED=6 DISPUTED=7
  PAYMENT_PENDING=8 PAID=9
```

Frozen messages and field tags:

`ReservePolicyVersion.stress_haircut_basis_points` is constrained to the inclusive
range `0..10_000`, and `modeled_loss_at_target_confidence` MUST be greater than zero.
These validation rules are part of the frozen wire semantics.

```text
ReservePolicyVersion {
  Identifier policy_version_id=1
  Identifier pool_id=2
  AssetId settlement_asset_id=3
  string token_address=4
  uint32 stress_haircut_basis_points=5
  Money modeled_loss_at_target_confidence=6
  uint32 target_confidence_basis_points=7
  uint32 maximum_coverage_basis_points=8
  Money maximum_single_policy=9
  Money aggregate_commitment_limit=10
  string minimum_reserve_ratio_ray=11
  string minimum_commitment_ratio_ray=12
  uint64 covered_event_mask=13
  Money minimum_deductible=14
  Money maximum_deductible=15
  bytes premium_policy_hash=16
  bytes adjudicator_set_hash=17
  bytes payout_waterfall_hash=18
  bytes recovery_waterfall_hash=19
  Timestamp effective_at=20
  Timestamp expires_at=21
  ReservePolicyState state=22
  bytes content_hash=23
}

ReserveBalanceSnapshot {
  Identifier snapshot_id=1
  Identifier pool_id=2
  AssetId asset_id=3
  Money gross_custody=4
  Money eligible_risk_adjusted_assets=5
  Money unclaimed_commitments=6
  Money approved_unpaid_claims=7
  Money available_payout_liquidity=8
  Money available_underwriting_capacity=9
  Identifier policy_version_id=10
  uint64 block_number=11
  bytes block_hash=12
  bytes custody_evidence_hash=13
  Timestamp observed_at=14
}

ReserveSolvencySnapshot {
  Identifier solvency_snapshot_id=1
  ReserveBalanceSnapshot balance=2
  Money modeled_loss_at_target_confidence=3
  string reserve_coverage_ratio_ray=4
  string commitment_coverage_ratio_ray=5
  string status=6
  bytes model_evidence_hash=7
}

LoanCoverage {
  Identifier coverage_id=1
  Identifier pool_id=2
  LoanId loan_id=3
  PartyId beneficiary_id=4
  AssetId settlement_asset_id=5
  uint64 covered_event_mask=6
  Money deductible=7
  uint32 coverage_basis_points=8
  Money coverage_limit=9
  Money remaining_limit=10
  Money premium=11
  uint32 loss_priority=12
  uint32 subrogation_priority=13
  Timestamp valid_from=14
  Timestamp expires_at=15
  uint64 coverage_nonce=16
  Identifier policy_version_id=17
  bytes coverage_digest=18
  CoverageState state=19
  bytes reserve_policy_hash=20
}

PremiumEvidence {
  Identifier premium_event_id=1
  Identifier coverage_id=2
  Identifier pool_id=3
  PartyId payer_id=4
  Money amount=5
  bytes transaction_hash=6
  uint32 log_index=7
  bytes balance_delta_hash=8
  Timestamp funded_at=9
  PremiumState state=10
}

InsuranceClaim {
  Identifier claim_id=1
  Identifier coverage_id=2
  Identifier loss_id=3
  PartyId claimant_id=4
  Money requested_amount=5
  Money eligible_uncovered_loss=6
  bytes evidence_hash=7
  uint64 claim_nonce=8
  Timestamp submitted_at=9
  InsuranceClaimState state=10
  bytes claim_digest=11
}

ClaimDecision {
  Identifier decision_id=1
  Identifier claim_id=2
  Money adjudicated_amount=3
  Money approval_cap=4
  Money beneficiary_covered_unresolved_entitlement=5
  Money approved_amount=6
  Money authorized_costs=7
  bytes beneficiary_entitlement_hash=8
  bytes evidence_hash=9
  uint64 adjudication_nonce=10
  Timestamp valid_until=11
  bytes adjudicator_set_hash=12
  repeated bytes signatures=13
  bytes decision_digest=14
  uint64 loss_state_version=15
}

ClaimPayment {
  Identifier claim_payment_id=1
  Identifier claim_id=2
  Identifier decision_id=3
  Identifier pool_id=4
  PartyId beneficiary_id=5
  Money amount=6
  Money unpaid_approved_amount=7
  bytes transaction_hash=8
  uint32 log_index=9
  bytes balance_delta_hash=10
  bytes subrogation_entitlement_hash=11
  Timestamp paid_at=12
  uint64 payment_nonce=13
}
```

`ClaimDecision.decision_digest` MUST equal the exact `claim_decision_id` digest. Its
`loss_state_version` and `adjudicated_amount` are signed fields; `approved_amount` is
the contract-derived result and is never substituted into the signed preimage.
`ClaimPayment.payment_nonce` is immutable and MUST equal the nonce bound by
`claim_payment_id`. `LoanCoverage.coverage_digest` commits the deterministic immutable
coverage fields, including both `policy_version_id` and `reserve_policy_hash`, and MUST
recompute to the same preimage represented by `coverage_id`.

The local claim fixture is exact:

```text
gross covered loss / debt                       125
less unique collateral recovery                  60
less actual funded guarantee                     10
eligible uncovered loss                          55
deductible                                        5
coverage percentage                             40%
coverage formula = floor((55 - 5) * 40%)         20
policy remaining limit                           20
unclaimed policy commitment                      20
stored beneficiary unresolved entitlement        25
authorized costs                                  0
approved and paid claim                          20
residual write-off                                35
```

The approval cap is the minimum of the request, coverage formula, policy remaining
limit, unclaimed commitment, payout liquidity excluding other approved unpaid claims,
and the stored beneficiary's covered unresolved entitlement. The contract derives
`approved_amount = min(adjudicated_amount, approval_cap)` at the signed
`loss_state_version`; neither the caller nor an adjudicator signature supplies
`approved_amount`. The entitlement hash binds beneficiary, position set, priority, loss
ID, amount, and snapshot evidence. This prevents payment above the beneficiary's
provable unresolved right even when aggregate loss and reserve capacity are larger.

After collateral and guarantee cash recoveries, the position loss exposure is `55`.
The contractual waterfall assigns the junior position's `30` first-loss amount before
the senior position's `25` covered unresolved amount. Junior allocation is not cash and
is not subtracted again from policy `eligible_uncovered_loss`. The exact `20` coverage
payment restores the stored senior beneficiary, leaving write-off allocation of junior
`30` followed by senior `5`. This ordering is committed in the claim entitlement,
position-loss allocation, write-off, and recovery-waterfall hashes.

`authorized_costs` remains in the additive schema for a future policy version but MUST
equal zero in the first local product. A nonzero value is rejected because this slice
has no authorized cost beneficiary or cost-payment route.

Pool-wide unencumbered liquidity and claim-specific payment liquidity are different:

```text
unencumbered payout liquidity
= custody - all approved unpaid claims

payment liquidity for claim C
= custody - approved unpaid claims for every claim other than C
```

The current claim's payable is excluded from the second subtraction because it is the
amount being settled. Thus custody `20` reserved entirely for claim C still permits C
to receive `20`; the same payable is not deducted twice. Approval and payment both
remain capped by the current claim's stored beneficiary entitlement.

The first local slice prohibits partial claim transfers. A decision's full payable is
its contract-derived `approved_amount` because `authorized_costs` is fixed at zero. The
decision is paid exactly once only when claim-specific payment liquidity is at least
that full payable. The successful transfer MUST satisfy
`ClaimPayment.amount = ClaimDecision.approved_amount` and
`ClaimPayment.unpaid_approved_amount = 0`. If full liquidity is unavailable, the claim
remains `PAYMENT_PENDING`, no token transfer or claim-payment journal is emitted, no
`ClaimPayment` row is created, and the bound payment nonce is not consumed. Exact replay
of a completed decision returns its one payment; changed nonce or payment content is an
idempotency conflict.

### `recovery.proto`

Frozen enums:

```text
GuaranteeState:
  UNSPECIFIED=0 PROPOSED=1 ACCEPTED=2 ACTIVE=3 CLAIM_PENDING=4
  PARTIALLY_PAID=5 PAID=6 EXPIRED=7 RELEASED=8 EXHAUSTED=9

RecoveryCaseState:
  UNSPECIFIED=0 OPEN=1 RECOVERY_PENDING=2 LOSS_FINALIZED=3
  WRITE_OFF_PENDING=4 WRITTEN_OFF=5 RECOVERY_OPEN=6 RECOVERED=7
  CLOSED_WITH_UNRECOVERED_LOSS=8 DISPUTED=9

RecoverySourceType:
  UNSPECIFIED=0 COLLATERAL=1 GUARANTOR=2 INSURANCE=3
  MOCKED_LEGAL_RECEIPT=4 OTHER_AUTHORIZED_RECEIPT=5

RecoverySourceState:
  UNSPECIFIED=0 OBSERVED=1 FINAL=2 ALLOCATED=3 REJECTED=4 DISPUTED=5

RecoveryEntitlementKind:
  UNSPECIFIED=0 LENDER_UNCOVERED=1 PRODUCT_POOL_SUBROGATION=2
  GUARANTOR_SUBROGATION=3 BORROWER_SURPLUS=4
```

Frozen messages and field tags:

```text
Guarantee {
  Identifier guarantee_id=1
  LoanId loan_id=2
  Identifier loss_id=3
  PartyId guarantor_id=4
  AssetId asset_id=5
  Money maximum_amount=6
  uint64 covered_event_mask=7
  uint32 priority=8
  bytes subrogation_policy_hash=9
  Timestamp valid_from=10
  Timestamp expires_at=11
  Money committed_amount=12
  Money paid_amount=13
  GuaranteeState state=14
  bytes guarantee_digest=15
}

RecoveryCase {
  Identifier recovery_case_id=1
  Identifier loss_id=2
  LoanId loan_id=3
  uint64 debt_state_version=4
  Identifier default_event_id=5
  AssetId settlement_asset_id=6
  Money gross_covered_loss_exposure=7
  Money collateral_credited=8
  Money guarantor_credited=9
  Money insurance_credited=10
  Money other_recovery_credited=11
  Money forgiveness_recognized=12
  Money residual_loss_exposure=13
  Money realized_loss_recognized=14
  Money writeoff_recognized=15
  bytes position_snapshot_root=16
  bytes waterfall_policy_hash=17
  RecoveryCaseState state=18
  uint64 state_version=19
}

RecoverySourceEvidence {
  Identifier recovery_source_id=1
  Identifier loss_id=2
  RecoverySourceType source_type=3
  PartyId source_party_id=4
  string source_reference=5
  Money amount=6
  bytes transaction_hash=7
  uint32 log_index=8
  bytes balance_delta_hash=9
  bytes descriptive_evidence_hash=10
  RecoverySourceState state=11
  Timestamp finalized_at=12
}

RecoveryEntitlement {
  Identifier entitlement_id=1
  Identifier loss_id=2
  RecoveryEntitlementKind kind=3
  PartyId beneficiary_id=4
  Money original_amount=5
  Money remaining_amount=6
  uint32 priority=7
  bytes policy_hash=8
}

RecoveryAllocation {
  Identifier allocation_id=1
  Identifier loss_id=2
  Identifier recovery_source_id=3
  Identifier entitlement_id=4
  PartyId beneficiary_id=5
  Money amount=6
  uint32 allocation_sequence=7
  Money receipt_residual=8
  bytes waterfall_policy_hash=9
  bytes allocation_digest=10
}

WriteOffEvidence {
  Identifier writeoff_id=1
  Identifier loss_id=2
  LoanId loan_id=3
  uint64 debt_state_version=4
  Money residual_loss_exposure=5
  Money writeoff_amount=6
  bytes position_allocation_hash=7
  bytes recovery_assessment_hash=8
  string reason_code=9
  PolicyReference approval_policy=10
  uint64 writeoff_nonce=11
  bytes approval_evidence_hash=12
  Timestamp recognized_at=13
}

RecoveryReconciliationEvidence {
  Identifier reconciliation_id=1
  Identifier loss_id=2
  Money gross_loss=3
  Money unique_credited_sources=4
  Money residual_loss=5
  Money writeoff=6
  Money later_receipts=7
  Money allocated_to_entitlements=8
  Money borrower_surplus=9
  bytes entitlement_set_hash=10
  bytes journal_set_hash=11
  bytes evidence_hash=12
  Timestamp reconciled_at=13
}
```

## PostgreSQL migration ownership

Phase 9 adds exactly three append-only migrations and exactly 45 Phase9-owned tables:

| Migration | Owned tables |
| --- | ---: |
| `000013_resolution_core.sql` | 17 |
| `000014_protection_recovery.sql` | 21 |
| `000015_resolution_accounting.sql` | 7 |
| Total | 45 |

Functions, views, triggers, roles, indexes, inserted chart-account rows, and grants do
not count as Phase9-owned tables. No migration changes the meaning of an existing
column, enum, account code, journal, or source event.

### `000013_resolution_core.sql` — 17 tables

```text
 1. resolution.phase9_debt_snapshots
 2. resolution.payoff_quotes
 3. resolution.refinance_requests
 4. resolution.refinance_funding_commitments
 5. resolution.refinance_transitions
 6. resolution.refinance_executions
 7. resolution.refinance_refunds
 8. resolution.lien_handoffs
 9. resolution.restructuring_proposals
10. resolution.position_snapshots
11. resolution.position_snapshot_members
12. resolution.restructuring_votes
13. resolution.borrower_consents
14. resolution.restructuring_executions
15. resolution.amendment_versions
16. resolution.resolution_inbox
17. resolution.resolution_outbox
```

`phase9_debt_snapshots` stores the exact authenticated canonical debt projection that
authorized a quote. `payoff_quotes` stores the exact quote preimage, content digest,
current terminal disposition, disposition source event, and consuming refinance ID. A
quote has one terminal disposition and one refinance consumer at most. Disposition
history remains immutable inside the source event and the affected
`refinance_transitions` payload rather than creating an additional table.

`refinance_requests` stores current monotonic state under compare-and-set. Every state
change inserts `refinance_transitions` in the same transaction. Reverted transaction
hashes, deterministic pre-submission failures, compensation evidence, and lien
sub-transitions are immutable typed transition payloads; none can mark an execution
complete. Only an authenticated finalized coordinator event creates
`refinance_executions`.

`position_snapshots` stores one immutable header and root.
`position_snapshot_members` stores each exact position ID, owner, tranche, claim,
voting weight, and proof commitment. `amendment_versions` stores the append-only
effective agreement and schedule version after an authenticated execution.

`resolution_inbox` commits event consumption and its durable state effect in one
transaction. `resolution_outbox` is published at least once. Neither table is shared
with or aliases the Phase 8 cross-chain inbox or outbox.

Required uniqueness includes:

```text
(loan_id, quote_nonce)
one terminal disposition and one consuming refinance in payoff_quotes per quote_id
(old_loan_id, refinance_nonce)
(chain_id, phase9_loan_factory, old_loan_id, borrower_id, new_loan_nonce)
(refinance_id, position_id)
(refinance_id, commitment_id)
(collateral_id, prior_lien_version, next_lien_version)
one completed lien handoff per collateral and refinance
(restructure_id, position_id)
(restructure_id, borrower_id, consent_nonce)
source (chain_id, transaction_hash, log_index)
```

An active partial unique index permits one nonterminal refinance per old loan and one
nonterminal restructuring proposal per loan. Serializable execution locks the refinance,
quote, funding, and lien rows in canonical byte order.

### `000014_protection_recovery.sql` — 21 tables

```text
 1. protection.reserve_pools
 2. protection.reserve_asset_snapshots
 3. protection.modeled_loss_fixtures
 4. protection.coverage_policies
 5. protection.loan_coverages
 6. protection.premium_events
 7. protection.adjudicator_sets
 8. protection.claims
 9. protection.claim_decisions
10. protection.claim_payments
11. recovery.guarantees
12. recovery.guarantee_payments
13. recovery.loss_cases
14. recovery.loss_source_events
15. recovery.writeoffs
16. recovery.subrogation_rights
17. recovery.recovery_receipts
18. recovery.recovery_allocations
19. recovery.recovery_incidents
20. protection.protection_inbox
21. protection.protection_outbox
```

Reserve funding and premium rows require exact finalized vault balance deltas. Snapshot
rows are immutable observations and cannot alter custody, policy, coverage, claim, or
capacity. `coverage_policies` stores immutable delayed policy versions and
`modeled_loss_fixtures` stores the exact synthetic denominator, target confidence,
model version, and evidence hash. One delayed policy version is active for a pool and
asset at a time. Database checks enforce
`stress_haircut_basis_points BETWEEN 0 AND 10000` and
`modeled_loss_at_target_confidence > 0`; owner functions repeat both checks before
activation.

Approval atomically reduces unclaimed coverage commitment and creates approved unpaid
claim capacity, so the same amount cannot appear in both totals. Payment consumes one
decision and exact stored beneficiary once. It creates a final payment only for the
entire payable; otherwise it leaves `PAYMENT_PENDING` with zero transfer and zero
payment row. Direct table writes cannot approve or pay a claim.

Guarantee commitment and guarantee payment are different rows. Only a `FINAL` exact
token receipt in `guarantee_payments` or `recovery_receipts` can increment credited
loss or create a `subrogation_rights` row. Descriptive mock evidence without that
receipt is retained in a typed loss-source or incident record but has zero economic
amount.

Claim and recovery transition histories are retained as immutable typed source-event,
decision, payment, loss-source, receipt, allocation, write-off, or incident rows rather
than separate mutable transition tables.

`protection_inbox` commits claim, reserve, and recovery event consumption with its
durable effect. `protection_outbox` publishes at least once. They are disjoint from both
the Phase 8 cross-chain broker tables and the Phase 9 resolution broker tables.

Required uniqueness includes:

```text
(pool_id, policy_version)
(pool_id, asset_id, transaction_hash, log_index) for reserve funding
one active coverage nonce per loan and policy
(coverage_id, premium_event_id)
(loss_id, claim_nonce)
(claim_id, adjudication_nonce)
(claim_id, claim_payment_id)
one final claim payment per decision_id
(guarantee_id, guarantee_payment_id)
(loss_id, source_type, source_reference)
(transaction_hash, log_index, asset_id) for recovery proceeds
(recovery_receipt_id, allocation_sequence)
(loss_id, subrogation_right_id)
(loss_id, writeoff_nonce)
```

Loss, receipt, subrogation, allocation, and write-off rows serialize on the
`recovery.loss_cases` row. Exact replay returns prior IDs. Conflicting replay fails
without a new total or journal.

### `000015_resolution_accounting.sql` — 7 tables

```text
1. ledger.phase9_accounting_identities
2. ledger.phase9_journal_links
3. reconciliation.phase9_snapshots
4. reconciliation.phase9_differences
5. reconciliation.phase9_solvency_reports
6. reconciliation.phase9_release_commitments
7. reconciliation.phase9_runtime_checkpoints
```

`phase9_accounting_identities` binds one canonical economic transition to the complete
ordered journal-role set and batch digest. `phase9_journal_links` binds each required
role to one immutable posted journal. A batch is complete only when every required role
is linked and every linked journal is balanced, posted, content-matching, and
source-event exact.

Reconciliation snapshot finalization and difference insertion serialize on the
snapshot row. Finalized snapshots cannot acquire new sources or differences. Difference
resolution is append-only: a subsequent snapshot and, when still material, a subsequent
difference record reference the prior difference and its resolution evidence. The
original expected, observed, severity, owner, and deadline never change.

`phase9_solvency_reports` stores the exact reserve numerators, denominator, ratios,
policy, and source snapshot commitments. `phase9_runtime_checkpoints` makes restart
position, inbox/outbox heads, aggregate versions, and replay verification first-class
append-only evidence.

`phase9_release_commitments` stores the content hash and validation result for the
generated local release manifest. It cannot certify a snapshot while a critical
difference is open or a required journal, transaction, source projection, runtime
checkpoint, restart test, or reset assertion is missing.

## Append-only and least-privilege boundary

Migration `000013` creates:

```text
unified_phase9_owner NOLOGIN
unified_phase9_runtime NOLOGIN NOINHERIT
unified_phase9_observer NOLOGIN NOINHERIT
unified_phase9_consent_verifier NOLOGIN NOINHERIT
```

Migration `000014` creates:

```text
unified_phase9_reserve_observer NOLOGIN NOINHERIT
unified_phase9_claim_verifier NOLOGIN NOINHERIT
unified_phase9_recovery_observer NOLOGIN NOINHERIT
unified_phase9_writeoff_verifier NOLOGIN NOINHERIT
```

Migration `000015` creates:

```text
unified_phase9_accounting_runtime NOLOGIN NOINHERIT
unified_phase9_reconciler NOLOGIN NOINHERIT
unified_phase9_release_assembler NOLOGIN NOINHERIT
```

Owners receive no login. Runtime roles receive schema `USAGE`, narrowly required reads,
and `EXECUTE` on reviewed `SECURITY DEFINER` functions with fixed `search_path`. They
receive no direct insert, update, delete, truncate, trigger-disable, ownership, role
grant, or DDL rights on authoritative or ledger tables.

Append-only triggers reject update and delete on debt snapshots, refinance transitions,
refinance executions, refinance refunds, lien handoffs, position snapshot headers and
members, restructuring votes, borrower consents, restructuring executions, amendment
versions, both inbox/outbox histories, reserve asset snapshots, modeled-loss fixtures,
coverage policy versions, premium events, adjudicator sets, claim decisions, claim
payments, guarantee payments, loss source events, write-offs, subrogation rights,
recovery receipts, recovery allocations, recovery incidents, accounting identities,
journal links, reconciliation snapshots, reconciliation differences, solvency reports,
release commitments, and runtime checkpoints. These history and evidence rows are
immutable.

Only `resolution.payoff_quotes`, `resolution.refinance_requests`,
`resolution.refinance_funding_commitments`, `resolution.restructuring_proposals`,
`protection.reserve_pools`, `protection.loan_coverages`, `protection.claims`,
`recovery.guarantees`, and `recovery.loss_cases` are mutable current/version rows.
Owner functions compare-and-set their exact expected state and version and append the
applicable typed transition, source, inbox, or outbox evidence in the same transaction.
Runtime roles receive no direct DML on either current rows or immutable history.

## On-chain roles and separation of duties

Phase 9 adds narrowly scoped role constants without changing existing role meanings:

```text
REFINANCE_COORDINATOR_ROLE
RESTRUCTURE_EXECUTOR_ROLE
RESERVE_POLICY_REGISTRAR_ROLE
CLAIM_ADJUDICATOR_REGISTRAR_ROLE
CLAIM_PAYMENT_ROLE
RECOVERY_RECEIPT_ROLE
WRITEOFF_APPROVER_ROLE
```

The local deployment uses distinct fixture accounts. The same account cannot adjudicate
and pay the same claim. Treasury, general governance, emergency, accounting, provider,
reconciler, and release roles cannot adjudicate a claim, select its beneficiary, move a
lien, sign borrower consent, create a recovery receipt, or approve a write-off.

Emergency controls may stop new quotes, refinance offers, restructuring proposals,
coverage, or claim submissions. They cannot block safe repayment, an already-valid
funding refund, payment of an already-approved claim when funds exist, evidence
retention, reconciliation, or later recovery. They cannot rewrite debt, a vote, lien,
beneficiary, reserve balance, loss, entitlement, write-off, journal, or release evidence.

## Privacy and object evidence

Public contracts and topics contain only synthetic addresses, opaque identifiers,
integer units, policy hashes, and evidence commitments. They contain no names, email
addresses, phone numbers, account numbers, government identifiers, legal documents,
credit files, or free-form personal narratives.

MinIO retains synthetic:

- debt and quote golden fixtures;
- transaction receipts and log inclusion evidence;
- borrower-consent and claim-adjudication fixture signatures;
- position snapshot proofs;
- reserve custody and balance-delta evidence;
- mocked legal-recovery descriptors;
- journal batch manifests;
- reconciliation source bundles; and
- release and reset evidence.

PostgreSQL stores content hash, object version, byte size, media and schema type,
authority, retention class, and synthetic-data classification. An object URI or object
body is never execution authority. The mocked legal-recovery object cannot supply or
override amount, asset, payer, beneficiary, loss, or receipt identity.

## Accounting codes

Migration `000015` may add missing chart rows but cannot change an existing row. The
Phase 9 account vocabulary is:

```text
1220 Stablecoin Treasury Holdings
1310 Principal Receivable
1320 Accrued Interest Receivable
1330 Fee Receivable
1340 Penalty Receivable
1350 Recovery Receivable
1360 Insurance Recoverable
1370 Guarantor Recoverable
1550 Restricted Refinance Escrow Asset
1560 Restricted Recovery Transit Asset
1570 Segregated Product Reserve Asset

2130 Lender Repayment Payable
2250 Unallocated Repayment Liability
2310 Lender Principal Claims
2370 Accrued Lender Interest Claims
2380 Refinance Funding Escrow Liability
2390 Refinance Refund Payable
2450 Insurance Claim Payable
2460 Guarantor Reimbursement Payable
2470 Recovery Allocation Payable

3210 Product-Specific Risk Reserve
3400 Retained Protocol Surplus or Deficit

4130 Refinancing Fee Revenue
4140 Restructuring Fee Revenue
4300 Insurance Premium Revenue

5300 Credit Loss Expense
5360 Insurance Claim Expense

6100 User Collateral at Contract Quantity
6130 Guarantee Commitment Control
6140 Insurance Coverage Control

8100 Original Principal by Loan
8110 Outstanding Principal by Loan
8120 Accrued Interest by Loan
8130 Paid Principal by Loan
8140 Paid Interest by Loan
8150 Fees and Penalties by Loan
8160 Written-Off Principal by Loan
8170 Recovered Principal by Loan

9180 Ledger-to-Chain Reconciliation Difference
```

`2320` retains its existing repository meaning, `Funding Commitment Liabilities`.
Phase 9 never reinterprets it as accrued lender interest. `2370` is the additive lender
interest-claim account. `2380` records exact funded refinance escrow before execution;
`2390` records only a terminally authorized lender refund. They do not replace or
reinterpret `2320`.

`1220` is protocol-owned treasury custody. Lender refinance escrow, pass-through
recovery, and product reserve custody are never general protocol treasury: `1550` is
the restricted refinance escrow asset, `1560` is the restricted recovery transit asset,
`1570` is the segregated product reserve asset, and `2470` is the recovery allocation
payable. `1570` is physically segregated and categorically distinct from `1220`; no
balance, wallet, vault, or journal row may alias the two. These additive accounts are
frozen by this layout and cannot be substituted with `1220`.

The protocol-wide insurance reserve account is not used. The first product posts only
to `3210 Product-Specific Risk Reserve`, backed by exact dedicated synthetic token
custody in `1570 Segregated Product Reserve Asset`. The UFT genesis allocation,
treasury, bridge backing, collateral, staking, liquidity, and any other product pool
cannot support these balances.

## Journal identities and required roles

Journal batch identity is:

```text
batch_id = "phase9:" + authority_type + ":" + authority_id
batch_idempotency_key = source_event_id + ":" + authority_digest
journal_id = batch_id + ":" + journal_role
journal_idempotency_key = source_event_id + ":" + journal_role
```

The ordered `journal_role` set is committed by `journal_batch_hash`. Caller-supplied
descriptions or journal references are never accounting authority.

Required batches are:

```text
refinance-funding:<refinance_id>
  FUNDING_ESCROW_CONTROL

refinance-execution:<refinance_id>
  FUNDING_ESCROW_CONSUMED
  OLD_PRINCIPAL_AND_INTEREST_PAYOFF
  OLD_FEE_AND_PENALTY_SETTLEMENT
  OLD_CLAIM_EXTINGUISHED
  NEW_LOAN_AND_POSITION_ACTIVATION
  LIEN_HANDOFF_CONTROL
  REFINANCE_FEE_SETTLEMENT
  BORROWER_PROCEEDS_CONTROL

refinance-refund:<refund_id>
  FUNDING_ESCROW_REFUND

restructure-execution:<restructure_id>
  INTEREST_CAPITALIZATION
  WAIVER_OR_FORGIVENESS
  POSITION_CLAIM_ADJUSTMENT
  SCHEDULE_AND_TERMS_CONTROL

reserve-funding:<funding_event_id>
  PRODUCT_RESERVE_CAPITALIZATION

premium:<premium_event_id>
  PREMIUM_RECEIPT
  PRODUCT_RESERVE_RESTRICTION

coverage:<coverage_id>
  COVERAGE_COMMITMENT_CONTROL

guarantee:<guarantee_id>
  GUARANTEE_COMMITMENT_CONTROL

guarantee-payment:<recovery_source_id>
  GUARANTOR_RECEIVABLE
  GUARANTOR_RECEIPT
  LENDER_PAYABLE_SETTLEMENT
  COVERED_DEBT_SATISFACTION
  GUARANTOR_SUBROGATION_CONTROL

claim-approval:<decision_id>
  CLAIM_PAYABLE_RECOGNITION

claim-payment:<claim_payment_id>
  CLAIM_PAYABLE_SETTLEMENT
  COVERED_DEBT_SATISFACTION
  PRODUCT_POOL_SUBROGATION_CONTROL

writeoff:<writeoff_id>
  REALIZED_LOSS_AND_WRITEOFF
  POSITION_LOSS_ALLOCATION
  WRITTEN_OFF_RIGHT_CONTROL

recovery:<recovery_source_id>
  RECOVERY_RECEIPT
  RECOVERY_ALLOCATION
  RECOVERED_PRINCIPAL_CONTROL

reconciliation:<difference_id>
  RECONCILIATION_DIFFERENCE_CONTROL
```

`OLD_CLAIM_EXTINGUISHED` means that joined canonical debt makes the effective current
claim zero. It does not mutate nominal tranche/position/checkpoint issuance facts or
set a stored position to `EXHAUSTED`.

Zero economic roles are omitted only when the frozen accounting delta explicitly marks
them inapplicable. A nonzero quote component, fee, waiver, forgiveness, payout, loss, or
allocation cannot be omitted.

### Frozen journal equations

Refinance funding receipt:

```text
Dr 1550 Restricted Refinance Escrow Asset        120
Cr 2380 Refinance Funding Escrow Liability       120
```

Old payoff:

```text
Dr 2310 Lender Principal Claims                   90
Dr 2370 Accrued Lender Interest Claims             5
Cr 1310 Principal Receivable                      90
Cr 1320 Accrued Interest Receivable                 5

Dr 1220 Stablecoin Treasury Holdings                5
Dr 2250 Unallocated Repayment Liability             1
Cr 1330 Fee Receivable                              3
Cr 1340 Penalty Receivable                          3
```

The second posting is balanced as debits `6` and credits `6`. The one-unit unapplied
credit is a borrower-controlled liability applied to the bound fee-and-penalty route;
it cannot be redirected or treated as cash. The quote's component-beneficiary hash and
the execution's component-payout hash bind `95` to the old lender and net `5` to the
protocol fee-and-penalty recipient.

New loan and fee:

```text
Dr 1310 Principal Receivable                      120
Cr 2310 Lender Principal Claims                   120
    senior position 90, junior position 30

Dr 1220 Stablecoin Treasury Holdings                2
Cr 4130 Refinancing Fee Revenue                     2

Dr 6100 User Collateral Control, new loan
Cr 6100 User Collateral Control, old loan
```

`FUNDING_ESCROW_CONSUMED` clears the exact funded liability:

```text
Dr 2380 Refinance Funding Escrow Liability       120
Cr 1550 Restricted Refinance Escrow Asset        120
```

The finalized contract event separately proves transfers of `95`, `5`, `2`, and `18`,
the quote-bound recipient routes, exact recipient balance deltas, zero terminal
attributed escrow for the refinance, and the exclusion of unsolicited coordinator token
surplus from liabilities and readiness.

Before execution, an authorized refund reclassifies and settles once:

```text
Dr 2380 Refinance Funding Escrow Liability       120
Cr 2390 Refinance Refund Payable                 120

Dr 2390 Refinance Refund Payable                 120
Cr 1550 Restricted Refinance Escrow Asset        120
```

Interest accrual and restructuring capitalization:

```text
interest accrual:
Dr 1320 Accrued Interest Receivable                 5
Cr 2370 Accrued Lender Interest Claims              5

capitalization:
Dr 1310 Principal Receivable                        5
Dr 2370 Accrued Lender Interest Claims              5
Cr 1320 Accrued Interest Receivable                 5
Cr 2310 Lender Principal Claims                     5
```

Reserve and premium:

```text
reserve capitalization:
Dr 1570 Segregated Product Reserve Asset            60
Cr 3210 Product-Specific Risk Reserve              60

premium receipt and restriction:
Dr 1570 Segregated Product Reserve Asset             4
Cr 4300 Insurance Premium Revenue                   4

Dr 3400 Retained Protocol Surplus or Deficit         4
Cr 3210 Product-Specific Risk Reserve               4
```

The reserve designation is separate from the premium receipt and cannot create assets
without the exact four-unit custody increase.

Claim approval and payment:

```text
claim approval:
Dr 3210 Product-Specific Risk Reserve              20
Cr 2450 Insurance Claim Payable                    20

claim payment:
Dr 2450 Insurance Claim Payable                    20
Cr 1570 Segregated Product Reserve Asset            20

covered debt satisfaction:
Dr 2310 Lender Principal Claims                    20
Cr 1310 Principal Receivable                       20
```

The claim-payment batch is emitted only for the full `20`. A liquidity result below
`20` emits neither a partial transfer nor any of these payment roles and leaves the
claim `PAYMENT_PENDING`.

Guarantee payment:

```text
Dr 1370 Guarantor Recoverable                      10
Cr 2130 Lender Repayment Payable                   10

Dr 1560 Restricted Recovery Transit Asset          10
Cr 1370 Guarantor Recoverable                      10

Dr 2130 Lender Repayment Payable                   10
Cr 1560 Restricted Recovery Transit Asset          10

Dr 2310 Lender Principal Claims                    10
Cr 1310 Principal Receivable                       10
```

Collateral recovery records:

```text
Dr 1560 Restricted Recovery Transit Asset          60
Cr 2130 Lender Repayment Payable                   60

Dr 2130 Lender Repayment Payable                   60
Cr 1560 Restricted Recovery Transit Asset          60

Dr 2310 Lender Principal Claims                    60
Cr 1310 Principal Receivable                       60
```

The collateral route requires an authenticated finalized registered-token receipt and
an exact transfer to the quote- and position-bound lender. It binds source transaction,
log index, asset, payer, beneficiary, receipt balance delta, payout balance delta, debt
version, and loss ID. The route is complete only when both transfers are final,
restricted transit and the lender payable are zero, the lender received exactly `60`,
and reconciliation matches the `60` debt-and-claim reduction. Descriptive collateral
evidence without these balance deltas has zero economic effect.

The local fixture freezes the user-funded pass-through write-off:

```text
Dr 2310 Lender Principal Claims                    35
Cr 1310 Principal Receivable                       35
    junior position allocation 30, then senior position allocation 5

Dr 8160 Written-Off Principal by Loan              35
Cr 8110 Outstanding Principal by Loan              35
```

The immutable position-allocation hash binds the junior `30` followed by the senior
`5`. The write-off reduces the corresponding claim and receivable together, but does
not forgive debt, erase the written-off-right control record, or extinguish guarantee,
product-pool, or other subrogation rights. The protocol-owned `5300 Credit Loss Expense`
template remains deferred; Phase 9 cannot apply it to this user-funded fixture.

Later recovery is receipt plus allocation, never automatic revenue:

```text
Dr 1560 Restricted Recovery Transit Asset            5
Cr 2470 Recovery Allocation Payable                  5

Dr 2470 Recovery Allocation Payable                  5
Cr 1560 Restricted Recovery Transit Asset            5

Dr 8170 Recovered Principal by Loan                  5
Cr 8160 Written-Off Principal by Loan                5
```

The allocation cannot silently substitute treasury holdings or recovery income when
Unified does not own the entitlement.

## Accounting and storage invariants

The database, Go accounting adapter, Solidity tests, and independent Python model enforce:

```text
gross payoff = principal + interest + fees + penalties
net payoff = gross payoff - credits
0 <= credits <= fees + penalties <= gross payoff

funding escrow = net payoff + refinance fee + borrower proceeds
terminal attributed escrow(refinance ID) = 0
unsolicited coordinator surplus is excluded from liabilities and readiness
old debt after completed refinance = CLOSED/TERMINAL with every debt/loss/credit amount 0
effective old position claim and voting power = 0 while nominal issuance history is unchanged
new activated principal = committed new principal
enforceable senior lien count per collateral = 1

restructured debt after capitalization
= debt before capitalization

approved claim
= payments + authorized costs + unpaid approved claim

eligible risk-adjusted reserve assets
= floor(
    exact pool custody
    * stress_haircut_basis_points
    / 10_000
  )

0 <= stress_haircut_basis_points <= 10_000
modeled_loss_at_target_confidence > 0

reserve coverage ratio ray
= floor(
    eligible risk-adjusted reserve assets
    * 10^27
    / modeled_loss_at_target_confidence
  )

canonical pre-claim: floor(64 * 10_000 / 10_000) = 64; 64 / 40 = 1.60
canonical post-claim: floor(44 * 10_000 / 10_000) = 44; 44 / 40 = 1.10

encumbered capacity
= unclaimed commitments + approved unpaid claims

claim-specific payment liquidity
= exact pool custody - approved unpaid claims of claims other than the claim being paid

eligible uncovered loss before non-cash position allocation
= gross covered loss - unique collateral recovery - actual funded guarantee
  - prior funded insurance - other unique funded recovery

approval cap
= min(
    requested amount,
    coverage formula amount,
    remaining policy limit,
    unclaimed policy commitment,
    claim-specific payment liquidity,
    stored beneficiary covered unresolved entitlement
  )

residual loss
= gross loss
 - unique collateral recovery
 - unique guarantor payment
 - unique insurance payment
 - unique other recovery
 - explicit forgiveness

writeoff <= residual loss

later receipt
= lender uncovered allocation
 + product-pool subrogation allocation
 + guarantor subrogation allocation
 + borrower surplus
```

No source can reduce loss twice. An approved claim is not a paid claim. A guarantee
commitment is not a receipt. A write-off is not forgiveness. A later recovery is not a
debt payment, recovery income, reserve replenishment, and lender distribution
simultaneously.

Every journal balances by exact asset. Every journal role has one canonical source event.
Exact replay returns the original batch and posted times. Changed reuse is an
idempotency conflict. Corrections use linked opposites; posted history is never edited.

## Event and object layouts

Redpanda topics are:

```text
unified.resolution.quote-issued.v1
unified.resolution.refinance-transitioned.v1
unified.resolution.refinance-completed.v1
unified.resolution.refinance-refunded.v1
unified.resolution.restructure-proposed.v1
unified.resolution.restructure-voted.v1
unified.resolution.restructure-effective.v1
unified.protection.reserve-funded.v1
unified.protection.coverage-activated.v1
unified.protection.claim-decided.v1
unified.protection.claim-paid.v1
unified.recovery.source-finalized.v1
unified.recovery.writeoff-recognized.v1
unified.recovery.allocated.v1
unified.phase9.reconciliation-difference.v1
unified.phase9.release-bundle.v1
```

Every producer uses a transactional outbox and every consumer uses a durable inbox key
based on canonical event ID. Delivery is at least once and may reorder. Consumers use
aggregate version and canonical source ordering rather than broker order.

## Reconciliation layouts

Each Phase 9 run stores:

```text
run ID and run type
chain ID, finalized head number and hash
deployment and policy manifest hashes
old and new loan IDs, accounts, terms and debt versions
quote ID, nonce, components, gross, credit, net, state, and expiry
refinance ID, state, escrow, payoff, fee, proceeds, and terminal balance
collateral ID, vault balance, senior loan, lien version, and handoff result
position IDs, tranches, claims, snapshot block/root, and vote totals
restructure ID, consent digest, accounting delta, and amendment result
pool, reserve policy, custody, haircut, commitments, payables, and headroom
coverage, premium, claim, decision, payment, and remaining limit
loss components, guarantee, write-off, entitlements, later receipt, and allocations
journal batch identities, roles, balances, and content hashes
object evidence identities and content hashes
restart/replay result
started, finalized, and released times
owner and status
```

Every source row records expected and observed integer values, canonical authority,
source event, transaction/log identity, evidence hash, and observation time.

Every difference stores:

```text
difference ID
run ID
dimension and reason code
expected and observed values
asset, loan, quote, refinance, collateral, position, proposal, pool, coverage,
claim, loss, guarantee, write-off, recovery, and journal references as applicable
severity
detected time
owner
resolution deadline
status
resolution evidence or opposite-journal reference
```

Differences cannot net across unrelated assets, loans, positions, pools, coverages,
claims, losses, beneficiaries, entitlements, or journal roles. A critical debt, lien,
custody, reserve, claim, double-credit, write-off, or allocation difference blocks the
release bundle and pauses the affected new activity.

Required reconciliation equalities include:

```text
quote components and net == canonical debt snapshot at quote version
funding token receipts == accepted commitments == escrowed units
payoff + fee + proceeds == funded units
old debt == zero after completion
new debt and position claims == activated principal plus valid capitalization
one collateral custody position == one senior lien owner
position snapshot totals == vote eligibility and cast totals
eligible reserve assets == floor(reserve vault custody * haircut bps / 10_000)
reserve policy haircut bps is within 0..10_000 and modeled loss is greater than zero
coverage commitments + approved unpaid claims <= policy capacity
claim paid <= approved <= eligible and policy limits
final collateral receipt == lender payout == debt-and-claim reduction; transit/payable == 0
unique credited recovery sources == recovery-case credited totals
write-off <= residual loss
later receipt == sum allocations + explicit residual
journal role totals == canonical economic effects
```

## Release and reset bundle

The generated local artifact is:

```text
protocol/deployments/local/phase9-release-evidence.json
```

Its schema is:

```text
infrastructure/local/resolution/phase9-release-evidence.schema.json
```

The bundle records:

```text
artifact type and schema version
git commit and clean-checkout assertion
toolchain lock and generated-manifest hashes
chain ID 31337, finalized head, and synthetic-only marker
contract address, deployment transaction, bytecode, ABI, and storage-layout hashes
Phase9LocalSyntheticToken address, asset ID, metadata, fixed supply, allocator, initial
  allocation, terminal balances, deployment hash, ABI hash, and storage-layout hash
policy, adjudicator-set, and fixture signer hashes
four Protobuf source hashes and four-language generated binding hashes
migration hashes and exact owned-table counts 17, 21, 7, total 45
each of the 45 fully qualified table names, exact row count, and deterministic ordered
  content hash, plus the aggregate Phase 9 SQL state hash
old loan, quote, refinance, replacement loan, lien, and position identities
restructuring proposal, snapshot, consent, votes, and amendment identities
pool, reserve, premium, coverage, loss, claim, decision, and payment identities
guarantee, write-off, entitlement, later receipt, and allocation identities
all finalized transaction/log and exact token balance deltas
all journal batches, roles, IDs, and content hashes
10,000-bps canonical haircut, pre-claim ratio 1.60 from 64/40, and post-claim ratio
  1.10 from 44/40 with exact numerator and denominator
reconciliation run, sources, differences, resolutions, and zero-critical-open assertion
worker restart and exact replay results
security and exit review content hashes
no-real-value, no-live-provider, loopback-only, and test-key assertions
pre-reset validation result
```

For each table, the ordered content hash is computed over length-prefixed canonical row
encodings sorted by that table's frozen primary-key column order. The aggregate SQL
state hash commits the 45 table commitments sorted by UTF-8 fully qualified table name,
including each table name, row count, and ordered content hash. Release verification
recomputes the commitments from a clean replay and rejects a missing or extra table, a
missing or extra row, a row-count mismatch, a row-content mismatch, or a mismatched
aggregate hash.

Post-reset validation proves the generated manifest, Phase 9 cache, database rows,
topics, objects, synthetic keys, contract broadcast artifacts,
`Phase9LocalSyntheticToken` deployment record, asset registration, allowances, and
balances are absent or returned to the declared clean fixture state by resetting the
disposable local chain. Reset never calls a token burn, rescue, or administrator path
and never targets a path outside the repository's explicit local cache, deployment,
broadcast, or named container-volume roots.

## Storage acceptance properties

- the four additive proto files generate deterministic bindings in all four languages;
- the dedicated six-decimal `P9UNIT` fixture is deployed only on chain `31337`, has its
  exact fixed supply and constructor allocation, is absent from every Phase 8 route and
  manifest, and is fully committed by release/reset evidence;
- no non-token Phase 9 business logic is accepted before exact interfaces, typed storage
  declarations, ABI snapshots/checker mappings, compiler storage-layout snapshots and
  checker, `ProtocolCompilation.sol` imports, formatter scope, and clean-regeneration CI
  all pass;
- the historical `UNI-ABI-009` freeze keeps its original ABI, storage, compiler,
  source-set, manifest, review, merge, and tag evidence, with the manifest, every ABI and
  storage snapshot, and freeze review pinned as raw bytes, while each activated work
  package records a distinct current exact-source implementation checkpoint and ordered
  transitive repository-local Solidity dependency-closure hash;
- the protected checker applies a reviewed backlog-to-contract activation map, retains
  the exact freeze revert for unopened logic, and compares current ABI and storage with
  the historical freeze instead of overwriting that baseline;
- `UNI-ADR-015` and its activation-tooling review complete before `UNI-PAYOFF-001` may
  complete, and any ABI or storage drift remains blocked on a separate additive
  compatibility decision;
- one quote nonce and debt version produce one immutable quote and one terminal
  disposition;
- the first quote nonce is one, advances only on successful issuance, and at most one
  quote per loan is effectively `ISSUED`;
- the exact five-component payoff vector, component-beneficiary commitment, settlement
  route commitment, half-open validity window, full consume revalidation, and terminal
  replay semantics match ADR 0020;
- new-loan and refinance identifiers have acyclic preimages, and one immutable
  `new_loan_nonce` produces one new-loan identity in its bound scope;
- one accepted funding commitment creates one escrow effect or one refund, never both;
- a completed refinance consumes the exact quote once, clears its attributed escrow,
  and neither consumes nor is blocked by unsolicited coordinator token surplus;
- one collateral ID has exactly one enforceable senior loan before and after handoff;
- an injected failure before lien completion leaves old debt, old lien, funding, new
  activation, and borrower balance unchanged;
- one position contributes its snapshotted voting weight once;
- borrower consent cannot replay across proposal, loan, version, chain, controller,
  accounting delta, or deadline;
- reserve capacity derives only from actual dedicated synthetic custody under the
  product-specific policy;
- eligible reserve assets use integer floor division by `10_000`, haircut basis points
  are within `0..10_000`, modeled loss is strictly positive, and the canonical
  10,000-bps fixture proves pre-claim `64/40 = 1.60` and post-claim `44/40 = 1.10`;
- approved unpaid claims and unclaimed commitments never double-count capacity;
- claim payment uses the stored beneficiary, pays one decision exactly once for its
  full approved payable only when claim-specific liquidity is sufficient, records zero
  unpaid approved amount on success, and otherwise stays `PAYMENT_PENDING` with zero
  transfer;
- a guarantee commitment cannot reduce loss before exact receipt;
- collateral recovery reduces debt and lender claims only after the finalized restricted
  receipt and bound lender payout both equal the reduction, with zero transit and
  payable balances and matching reconciliation;
- collateral, guarantee, insurance, other recovery, forgiveness, write-off, and later
  recovery share one loss identity and cannot duplicate a source;
- write-off preserves history and bounded recovery entitlements;
- later recovery allocation is deterministic, idempotent, and amount-conserving;
- migration-owned table counts are exactly `17 + 21 + 7 = 45`;
- the release bundle commits the exact row count and deterministic ordered content hash
  of every one of the 45 tables plus the aggregate SQL state hash, and rejects any
  missing or extra table or row;
- runtime database roles cannot forge terminal, financial, consent, claim, receipt,
  write-off, allocation, journal, reconciliation, or release authority;
- every posted journal is balanced, immutable, evidence-bound, and exact-replay safe;
- projections rebuild from retained finalized events and content-addressed evidence;
- the release bundle fails with any critical difference or production-looking
  configuration; and
- one command resets only the bounded local synthetic state.

## Production deferrals and prohibitions

These layouts do not approve production reserve capital, insurance underwriting,
actuarial models, guarantors, claims operations, legal enforcement, collections,
subrogation, write-off policy, accounting conclusions, custody, payment providers,
oracle providers, reserve investment, cross-asset conversion, FX, public-chain
deployment, live refinancing, live collateral handoff, production IAM, HSM/KMS custody,
retention, disaster recovery, or regulatory reporting.

No field or function named `manual_override`, `force_quote`, `force_payoff`,
`force_handoff`, `force_vote`, `force_claim`, `force_payment`, `force_recovery`,
`force_writeoff`, `force_allocation`, `force_reconcile`, or equivalent is permitted.
Any future production design requires separate legal, risk, accounting, actuarial,
security, provider, custody, operational, and deployment approval and may not weaken
the identities, consent, custody, capacity, double-claim, append-only, or reconciliation
properties frozen here.
