# ADR 0018: Phase 8 Cross-Chain and Wrapped UFT Boundary

Status: accepted for synthetic local engineering

Date: 2026-07-25

## Context

Phase 7C proves a bounded mature external-settlement path on one local EVM domain. It
does not choose a production home chain, authorize a bridge provider, create wrapped
UFT, or permit a satellite contract to affect a canonical loan.

Phase 8 must implement all five master-plan work packages:

1. canonical cross-chain coordination;
2. satellite loan components;
3. replaceable messaging adapters;
4. a fully backed UFT bridge; and
5. timeout, failure, and compromised-route recovery.

Cross-chain execution cannot be atomic across independent domains. A source lock, remote
mint, borrower disbursement, repayment burn, home release, or collateral release can be
final on one domain while another step is delayed. The boundary must therefore identify
one canonical home, separate message transport from message authority, delay economic
recognition until the applicable finality proof exists, and make every retry and recovery
path idempotent.

ADR 0006 continues to defer production home and satellite chains, bridge and messaging
providers, RPC topology, custody, signing, and deployment regions. The current Phase 7C
Ed25519 observer is also an explicit local/test trust root rather than EVM consensus or a
production light client. Phase 8 may reuse reviewed canonical RLP and Merkle-Patricia
verification code, but it may not reinterpret Phase 7C settlement evidence as
cross-chain authority.

The existing `unified.v1.CrossChainMessage` is a minimal foundation message. It does not
bind source and destination contracts, aggregate identity, schema and adapter versions,
finality policy, execution, acknowledgement, or recovery. Its raw action payload cannot
become an arbitrary-call authority. Phase 8 therefore requires additive authoritative
messages rather than a breaking or semantic reinterpretation of that type.

## Decision

### 1. Bounded environment

Phase 8 is synthetic and local-only. The reproducible environment contains two isolated
EVM domains:

- local home domain with chain ID `31337`; and
- local satellite domain with chain ID `31338`.

Each domain has distinct contract addresses, observer keys, finality policy, chain
configuration hash, projection, and RPC endpoint. These identifiers are non-production
fixtures and must not be promoted or described as a production chain selection.

All UFT, wUFT, collateral, loans, parties, adapters, keys, balances, and accounting
records are synthetic. No public testnet, mainnet, real provider, production credential,
or real fund is authorized.

### 2. Complete first product

The complete bounded product is one principal-only cross-chain loan:

```text
home lender locks canonical UFT
  -> finalized home message
  -> satellite mints exact backed wUFT into disbursement escrow
  -> satellite locks one synthetic fungible collateral asset
  -> satellite releases the disbursement to the canonical borrower
  -> finalized acknowledgement activates one canonical home loan
  -> borrower burns wUFT for partial or full repayment
  -> home atomically reduces debt and releases exact UFT backing to the lender
  -> full repayment authorizes satellite collateral release
  -> finalized release acknowledgement and reconciliation close the loan
```

The product has one borrower, one lender, one home chain, one satellite chain, one UFT
and wUFT pair, one synthetic collateral asset, zero interest, zero fees and penalties,
one-to-one units, and no repayment excess. A repayment burn greater than canonical debt
fails before the burn is accepted for the loan path.

Implementation may land as Phase 8A boundary/schema/policy, Phase 8B
message/finality/recovery, Phase 8C satellite loan, Phase 8D wUFT/exposure, Phase 8E
durable services/SQL/accounting/topology, and Phase 8F simulation/security/exit changes.
`UNI-REVIEW-011` cannot close until the combined revision implements and verifies the
complete flow and all five Phase 8 work packages.

### 3. Canonical home and immutable policy

Every cross-chain loan and bridge route has exactly one canonical home domain. The home
loan owns agreement terms, principal, lender rights, lifecycle, repayment allocation,
and final closure. Satellite contracts own only the local custody or execution facts
assigned to them.

A new loan and factory version must bind a reviewed cross-chain policy at origination.
The immutable policy binds:

- home and satellite domain and configuration hashes;
- home coordinator, bridge hub, satellite component, wUFT, collateral vault, and token
  addresses;
- permitted action types;
- source and destination finality policies;
- adapter-set and adapter-version policy;
- message timeout and recovery rules;
- UFT per-route and aggregate exposure limits;
- collateral identity and amount;
- disbursement and settlement asset identity and units; and
- exact one-to-one conversion and zero-fee assumptions.

Existing loans and policy sets from Phases 2 through 7C cannot be retrofitted into this
path. Deprecating a policy for new origination cannot silently replace the policy bound
to an active Phase 8 loan.

### 4. Domain and message identity

EVM chain IDs use canonical unsigned base-10 strings in schemas so the interface does not
narrow Solidity's `uint256`. Contract addresses use canonical 20-byte EVM identity.

The authoritative message identifier is non-recursive. It is the Keccak-256 hash of one
exact ABI preimage, in this order:

```text
"UNIFIED_XCHAIN_MESSAGE_V1"
schema version
protocol ID
source chain, coordinator, and component
destination chain, coordinator, and component
lane ID
source route nonce
loan or asset aggregate ID
typed action
payload hash
creation time
expiry
route-policy hash
adapter-set policy hash
source finality-policy hash
destination finality-policy hash
correlation ID
causation message ID
superseded message ID
```

`message_id = keccak256(abi.encode(preimage))`; `message_id` is stored in the envelope
but is not part of its own preimage. ABI, Protobuf, SQL, and every language encoder use
the exact same ordered fields. Zero causation or superseded IDs mean that relationship
does not apply; they are still committed fields. The source nonce is unique and
monotonic for the source contract and route. Both message ID and
`(source domain, source contract, destination domain, destination contract, nonce)` are
consumed at most once. Exact replay returns the prior result. Reuse with changed content
fails without another state or economic effect.

### 5. Typed actions and satellite authority

The first action family is closed and typed:

- canonical UFT lock;
- wrapped UFT mint;
- wrapped UFT burn;
- canonical UFT release;
- collateral lock;
- disbursement escrow and release;
- remote repayment;
- collateral release;
- state acknowledgement; and
- recovery or cancellation acknowledgement.

No message contains an arbitrary target or grants generic `bytes` execution. Each action
has an exact decoder, state predicate, asset and amount rule, and recipient derivation.
Recipients come from the immutable bridge instruction or canonical loan and collateral
state, never from a relayer or recovery caller.

Satellite components cannot set principal, interest, lender rights, loan policy, home
recipients, or canonical lifecycle. A satellite state report is evidence for a home
transition; it is not itself home-chain economic authority.

### 6. Canonical message lifecycle

The canonical message lifecycle is:

```text
CREATED
  -> SOURCE_FINALIZING
  -> SOURCE_FINAL
  -> SENT
  -> RELAYED
  -> VERIFIED
  -> EXECUTED
  -> ACK_PENDING
  -> ACKNOWLEDGED

Failure branches:
SENT | RELAYED | VERIFIED -> FAILED
FAILED -> SENT only for an unexpired retryable transport or target failure using the
          exact same message
REJECTED | FAILED | EXPIRED
  -> RECOVERY_PENDING
  -> DESTINATION_TOMBSTONED
  -> SOURCE_COMPENSATED
  -> RECOVERED
any safety contradiction -> DISPUTED
```

A `FAILED` message may retry only when its classified failure is retryable, it has not
expired, and every byte remains identical. A rejected, expired, nonretryable, or
recovery-selected failed message proceeds to `RECOVERY_PENDING`; it is never rewritten
as a new ordinary delivery.

This lifecycle is the Phase 8 implementation mapping for the shorter Domain Model
states, the cross-chain loan workflow states, the Data Architecture states, and the
Threat Model recovery states. `SOURCE_FINAL` and `VERIFIED` are evidence states;
`EXECUTED` is the atomic destination consume-and-effect result. `ACK_PENDING` records
that the result still lacks finalized home observation; `ACKNOWLEDGED` requires a
finalized destination execution proof at the home domain. No adapter acknowledgement or
operator assertion may skip those states.

Where action ordering matters, a later nonce may be retained but cannot execute before
its declared predecessor. Independent messages do not acquire a global ordering merely
because they use the same adapter.

### 7. Finality and adapter separation

The local source and destination observers have distinct pinned Ed25519 keys. A distinct
two-of-three ECDSA signer set attests the complete observer-authenticated inclusion and
finality proof. Observer signature alone, finality-signer signature alone, and transport
provider receipt alone are each insufficient. Each finality-policy hash binds:

- chain ID and chain configuration hash;
- source or destination contract;
- confirmation depth;
- observer authority;
- ECDSA signer-set hash, threshold, and version;
- cross-chain policy; and
- the applicable message action family.

Source and destination events are accepted only from canonical signed headers with
verified transaction and receipt Merkle-Patricia inclusion and canonical receipt/log
decoding. Pre-finality reorganization removes the provisional fact. A finalized-header
violation enters `DISPUTED`, pauses new route activity, preserves all evidence, and
requires owned recovery; it cannot be silently rewritten.

Two independently configured mock messaging adapters are available. They transport the
same immutable envelope and proof but are not source-finality authority. A retry through
another approved adapter retains the message ID and digest. Adapter compromise cannot
forge a source event, change a recipient or amount, lower finality, or bypass destination
verification. If every adapter is unavailable, a valid user-submitted proof remains
acceptable under the same policy.

### 8. Timeout and recovery

Timeout alone is never evidence that destination execution did not occur.

- Before source finality, an operation may expire without an economic effect.
- After source value is locked but before destination execution, refund or unlock
  requires finalized destination non-execution or a finalized compensating
  cancellation.
- If wUFT was minted only into the satellite disbursement escrow, cancellation first
  burns that exact escrowed amount, acknowledges the burn at home, returns canonical
  UFT to the lender, and releases collateral.
- After borrower disbursement, the loan cannot be cancelled into a lender refund.
  Activation must complete or enter an owned recovery state.
- After a satellite repayment burn, canonical backing remains locked until the home
  repayment/release succeeds. Timeout cannot both remint wUFT and release UFT.
- A recovered operation is permanently tombstoned. Reauthorization uses a new message
  ID and nonce and binds the superseded operation.

Compromised-route handling pauses new messages and mints, reduces no debt, seizes no
asset, and preserves direct home repayment, proof submission, reconciliation, and
recovery.

### 9. Fully backed wUFT

Canonical `UnifiedToken` remains fixed supply and receives no bridge mint role or new
mint function. The home bridge hub holds existing UFT in a route-specific restricted
escrow. The satellite wUFT is a distinct token whose only issuance authority is the
typed satellite bridge component under an exact finalized home-lock message.

The bounded implementation uses the stricter backing rule:

```text
wrapped UFT outstanding on satellite
<= finalized canonical UFT restricted for that satellite
```

Pending, relayed, or merely verified locks do not count as mintable backing. Backing is
partitioned by satellite and cannot simultaneously be withdrawn, staked, used as free
collateral, counted as treasury liquidity, or counted as voting power.

The local exposure policy freezes `circulating_supply_reference_units` and its evidence
hash when the policy version activates. The reference is derived from the synthetic
canonical UFT supply and registered non-circulating fixture balances, cannot exceed
`UnifiedToken.totalSupply()`, and cannot be supplied by a bridge caller. A new delayed
policy version is required to change it. New locks enforce the strictest absolute,
per-chain, per-adapter, per-route `5%`, and aggregate `15%` cap against that frozen
reference. This proves the percentage mechanism but does not ratify a production
circulating-supply definition.

A satellite burn is final before home release. Home release consumes one exact burn
message and derives the canonical recipient and amount from that message. A replay,
changed recipient, changed amount, alternate chain, alternate wrapped token, or second
release fails.

wUFT is not a governance, staking, collateral-eligible, reserve, or treasury asset in
this slice.

### 10. Cross-chain loan activation

The new home loan begins in an explicit activating workflow without recognized active
debt. The borrower and lender authorize one immutable agreement and cross-chain policy.
The lender's canonical UFT, the remote collateral, the satellite wUFT disbursement
escrow, and every message are bound to that agreement.

Debt becomes active only after:

- the lender's exact canonical UFT is finally restricted as backing;
- the exact wUFT amount is minted on the satellite;
- the required collateral is finally locked under one canonical lien;
- the disbursement escrow releases wUFT to the canonical borrower;
- the destination execution reaches configured finality; and
- the home account consumes that acknowledgement once.

Failure before borrower disbursement follows the exact compensating burn, UFT return,
and collateral-release path. Failure after borrower disbursement cannot erase the
borrower's debt or refund the lender from the same backing.

### 11. Repayment and collateral release

Remote repayment starts with an exact satellite wUFT burn bound to loan ID, payment ID,
amount, home loan, home bridge, and canonical lender. After finality, one home transaction
must:

- consume the burn message;
- prove the loan and bridge policy;
- release the exact canonical UFT backing to the registry lender;
- reduce canonical principal by the same amount;
- record the payment once; and
- emit the complete result for acknowledgement and accounting.

Any failure rolls back the entire home transaction. Partial repayment is allowed.
Repayment above outstanding principal and any excess/refund path are unavailable.

Safe direct home UFT repayment remains available during adapter or satellite outage.
Such a repayment does not release backing for still-outstanding wUFT.

After canonical zero debt, the home emits one typed collateral-release instruction. The
satellite derives the collateral and borrower from immutable custody state and releases
once. The home loan remains `CLOSING` until the finalized release acknowledgement and
accounting reconciliation arrive; only then may it become `CLOSED`.

### 12. Accounting and reconciliation

Submission or relay is not financial completion. Every posting consumes exact finalized
evidence and uses append-only, idempotent journal batches.

The bridge control sequence uses the existing chart of accounts:

```text
canonical lock:
  Debit  1410 Canonical Assets Locked for Bridging
  Credit 2230 Bridge Backing Liability
  Debit  7150 UFT Locked in Bridge Escrow Control
  Credit 9150 Pending Cross-Chain Settlement

wrapped mint:
  Debit  9150 Pending Cross-Chain Settlement
  Credit 7160 Wrapped UFT Outstanding Control

wrapped burn:
  Debit  7160 Wrapped UFT Outstanding Control
  Credit 9150 Pending Cross-Chain Settlement

canonical release:
  Debit  2230 Bridge Backing Liability
  Credit 1410 Canonical Assets Locked for Bridging
  Debit  9150 Pending Cross-Chain Settlement
  Credit 7150 UFT Locked in Bridge Escrow Control
```

Each journal balances within UFT. Pending mint, burn, release, timeout, and recovery
amounts remain visible and cannot become revenue. Loan activation recognizes principal
receivable and lender claim only after finalized disbursement. Remote repayment reduces
the exact historical principal and lender claim while the same atomic home transaction
releases backing to the lender. Remote collateral reuses the existing collateral-control
model with an explicit satellite domain and custody reference.

Reconciliation compares, per route and message:

- canonical escrow balance;
- wUFT total supply;
- pending mint and burn states;
- per-route and aggregate exposure;
- source, delivery, execution, and acknowledgement evidence;
- remote collateral custody;
- borrower disbursement;
- canonical loan debt and lender rights;
- UFT lender release;
- journal and control balances; and
- every recovery or dispute.

Every difference has an owner, materiality, age, deadline, and disposition. No service,
adapter, indexer, or operator can clear a difference by editing history.

### 13. Schemas and durable state

Protobuf remains the canonical interface source. Phase 8 adds authoritative, additive
messages for:

- domain and route configuration;
- cross-chain policy;
- immutable message envelope and digest context;
- source finality proof;
- adapter delivery attempt;
- destination verification and execution;
- acknowledgement;
- timeout, cancellation, recovery, and dispute;
- bridge lock, mint, burn, release, and backing snapshot;
- satellite collateral, disbursement, and repayment;
- canonical loan activation and repayment consequence; and
- accounting and reconciliation evidence.

The legacy `CrossChainMessage` remains compatible but is not sufficient accounting,
execution, or recovery authority.

PostgreSQL stores the current workflow under versioned compare-and-set, append-only
transition history, outbox and inbox records, consumed identities, bridge backing,
satellite custody, acknowledgements, incidents, recoveries, journals, and reconciliation.
Destination consume and typed effect are one transaction. Exact retry returns the prior
identities; partial prior writes or changed content fail closed.

Generated Solidity, Go, TypeScript, and Python bindings and every ABI are deterministic
derivatives.

### 14. Emergency and privileged authority

Bridge and satellite components use least authority. No operator can both invent and
authorize a message. Recovery authority is multi-party, evidence-bound, amount-bounded,
time-bounded, and replay-safe.

Emergency controls may:

- stop new route locks and mints;
- disable a compromised adapter for new delivery;
- lower future exposure;
- retain and reconcile disputed evidence; and
- direct a governed recovery procedure already authorized by policy.

They may not mint canonical UFT, create unbacked wUFT, seize arbitrary balances, redirect
repayment or collateral, mark an unverified message final, alter an active loan, edit a
posted journal, or block a safe direct home repayment.

### 15. Risks and assumptions

The Phase 8 risk register must include:

- `RISK-PHASE8-001`: forged or alternate-authority destination action;
- `RISK-PHASE8-002`: replay, domain confusion, nonce collision, or reordering;
- `RISK-PHASE8-003`: unbacked wUFT or duplicate canonical release;
- `RISK-PHASE8-004`: duplicate or incomplete loan activation, disbursement, or repayment;
- `RISK-PHASE8-005`: remote collateral reuse, trapping, or double release;
- `RISK-PHASE8-006`: timeout or recovery unlocks value on both domains;
- `RISK-PHASE8-007`: adapter compromise, reorganization, or finality substitution;
- `RISK-PHASE8-008`: exposure-cap or backing-reconciliation bypass;
- `RISK-PHASE8-009`: coordinator, projection, and ledger divergence; and
- `RISK-PHASE8-010`: satellite or recovery authority rewrites home economics.

Controlled findings remain `CONTROLLED_LOCAL_ONLY`; this milestone does not generalize
their controls to production.

The assumption register must include:

- `ASM-026`: every Phase 8 chain, provider, token, collateral, party, key, and balance is
  synthetic and local;
- `ASM-027`: each local observer key remains uncompromised and signs only finalized
  headers for its configured domain;
- `ASM-028`: Anvil verifies state-machine and reorganization mechanics but is not a
  production consensus or finality model;
- `ASM-029`: UFT and wUFT share denomination and precision and convert one-to-one with
  zero fee, slippage, or rounding;
- `ASM-030`: wUFT has no governance, staking, collateral, reserve, or treasury role; and
- `ASM-031`: accepted finalized headers do not reorganize beyond the explicit local
  finality assumption, while every pre-finality reorganization is handled and tested;
- `ASM-032`: each local two-of-three ECDSA finality/recovery signer set remains
  uncompromised and signs only the complete observer-authenticated proof for its pinned
  policy version; and
- `ASM-033`: the frozen local circulating-supply reference and evidence are synthetic
  fixtures used only to test the `5%` and `15%` cap mechanisms.

### 16. Verification and exit

Tests must cover:

- exact message replay and conflicting reuse;
- swapped domains or contracts, wrong nonce, aggregate, action, payload, policy, expiry,
  adapter set, and finality authority;
- duplicate, delayed, reordered, stale, and post-recovery delivery;
- canonical legacy and typed receipt proof, malformed trie and receipt data, proof limits,
  same-header enrichment, and pre-finality reorganization;
- adapter A outage, adapter B retry, both-adapter outage, user-submitted proof, and
  compromised-adapter fabrication;
- lock-before-mint, burn-before-release, partial and full round trips, cap boundaries,
  backing conservation, double mint, double burn, double release, and fee-token rejection;
- activation before collateral, mint, or disbursement finality;
- cancellation before disbursement and non-cancellation after disbursement;
- partial and full remote repayment, repayment conflict, direct home repayment during
  outage, and exact lender recipient;
- collateral double-use, wrong recipient, premature release, full release, replay, and
  closure acknowledgement;
- crash and restart at every cross-domain step;
- database stale writers, response loss, partial writes, exact replay, and concurrent
  message/recovery races;
- balanced accounting, suspense aging, backing, supply, custody, debt, payout, and
  recovery reconciliation; and
- delayed messages, duplicate messages, compromised relayer, satellite reorganization,
  emergency shutdown, backing impairment, and complete route-loss simulations.

Phase 8 exits only when every message executes at most once, wrapped UFT never exceeds
canonical backing, satellite contracts cannot rewrite loan economics, timeout recovery
cannot unlock value twice, exposure limits are enforced, and multi-provider failover and
bridge-compromise simulations pass. The two-chain environment must bootstrap and reset
from a clean checkout, generated bindings and ABIs must be fresh, all journals must
balance, and no critical or existential local-scope risk may remain unresolved.

## Consequences

- Cross-chain authority is proof of a typed finalized source action, not possession of a
  relayer key.
- Canonical UFT remains fixed supply; wUFT is a backed representation rather than another
  canonical mint.
- Loan debt begins only after actual finalized borrower disbursement.
- Remote repayment and canonical lender release share one home transaction.
- Timeout recovery favors safety and explicit suspense over an unsafe fast refund.
- The complete milestone is larger than a message bus or bridge demo and must be
  integrated before the Phase 8 exit review.

## Explicitly deferred

Phase 8 does not select or authorize:

- production home or satellite chains, RPC topology, consensus or light-client design,
  messaging or bridge vendors, custody, or deployment regions;
- real UFT, collateral, loans, provider accounts, production keys, or funds;
- public testnet or mainnet deployment;
- more than one satellite or wrapped asset;
- non-UFT settlement, FX, non-unit rates, fees, slippage, rounding, interest, penalties,
  excess repayment, or multi-lender waterfalls;
- wUFT governance, staking, collateral eligibility, liquidity, or remote voting;
- production manual recovery, insurance, reserve loss absorption, or bridge-insolvency
  capitalization;
- unrestricted arbitrary cross-chain calls; or
- production legal, tax, audit, HSM, incident, or operations approval.

Those deferrals cannot be used to omit synthetic/local wUFT value, satellite custody,
disbursement and repayment, accounting, adapter failover, or recovery from the Phase 8
engineering exit.
