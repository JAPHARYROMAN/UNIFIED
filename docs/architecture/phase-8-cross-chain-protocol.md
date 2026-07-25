# Phase 8 Cross-Chain Protocol and Wrapped UFT

Status: implementation boundary for synthetic local engineering

## Scope and safety posture

Phase 8 delivers one reproducible, two-chain product slice:

- one canonical EVM home chain and one EVM satellite chain;
- one home-authoritative loan whose collateral, disbursement, and repayment settlement
  occur on the satellite;
- one canonical UFT escrow route with fully backed wrapped UFT on the satellite;
- two interchangeable synthetic transport providers;
- deterministic finality, replay, timeout, tombstone, compensation, accounting, and
  reconciliation paths; and
- clean-start and one-command reset tests using synthetic accounts and tokens only.

The milestone remains local-only. Its chain observer, signer set, providers, assets,
parties, and balances are test fixtures. Nothing in this boundary approves public RPC,
real bridge providers, production credentials, real funds, public testnet, or mainnet.

The implementation is staged as 8A through 8F. No later stage may weaken a boundary
accepted in an earlier stage merely to make the end-to-end demonstration pass.

## Canonical authority

Every cross-chain aggregate has exactly one home domain. For the first slice:

```text
protocol ID                         fixed synthetic deployment ID
home chain                         local EVM chain ID 31337
satellite chain                    local EVM chain ID 31338
loan economic authority            home CrossChainLoanAccount
canonical UFT and backing          home UFTBridgeHub
satellite collateral custody       satellite SatelliteCollateralVault
satellite disbursement/burn        satellite SatelliteSettlementVault
wrapped UFT supply                 satellite WrappedUFT
message execution                  destination CrossChainCoordinator
transport                          either synthetic provider A or B
```

The home loan account alone owns principal, terms, lender rights, immutable policy
bindings, canonical lifecycle, and debt. A satellite component may custody an exact
asset or execute an exact home-authorized transfer. It cannot change a loan amount,
rate, schedule, lender, borrower, policy, debt, or terminal state.

The home bridge hub alone owns route backing, exposure, and redemption obligations.
Wrapped UFT is a bounded representation of escrowed canonical UFT. It is not canonical
UFT, cannot vote, cannot be accepted as loan collateral in this slice, and exposes no
general mint, rescue, or arbitrary withdrawal surface.

Off-chain coordination is a durable projection and delivery mechanism. PostgreSQL,
Redpanda, object storage, a provider, relayer, indexer, or ledger worker cannot create
loan rights, consume a message, mint wrapped UFT, release escrow, or release collateral
without the corresponding canonical contract transition.

## Registries and immutable route policy

Phase 8 introduces append-only, versioned registries:

- `ChainRegistry`: chain ID, coordinator, finality verifier, genesis/configuration
  commitment, activation block, status, and version;
- `RouteRegistry`: source/destination contracts, allowed action family, verifier policy,
  provider set, finality policy, limits, activation block, status, and version;
- `FinalitySignerRegistry`: signer-set hash, threshold, signer addresses, validity
  interval, and status; and
- `MessageRegistry`: outbound nonce, inbound nonce, immutable envelope, terminal result,
  tombstone, and recovery reference.

An active message pins the exact chain, route, signer, adapter, and finality-policy
versions accepted when it was created. Deprecation prevents new messages but preserves
verification and exit paths for already-created messages. Emergency pause blocks new
exposure and ordinary execution on the affected route. It does not erase history,
convert a pending action to success, or permit an administrator to withdraw escrow.

Registry upgrades are additive. An old entry is never edited into a different trust
model. A replacement route receives a new version and must pass the same registration,
delay, limit, and acceptance checks.

## Message identity and lanes

The canonical lane is:

```text
lane_id = keccak256(abi.encode(
  "UNIFIED_XCHAIN_LANE_V1",
  protocol_id,
  source_chain_id,
  source_component,
  destination_chain_id,
  destination_component,
  aggregate_id,
  action_family
))
```

Each lane has a monotonically increasing `uint64` outbound nonce and strict inbound
execution order. Actions that do not share an ordering dependency use separate lanes.
The first slice never skips a nonce and never reuses a nonce after failure or recovery.

The non-recursive instruction preimage and message identifier are:

```text
message_preimage = abi.encode(
  "UNIFIED_XCHAIN_MESSAGE_V1",
  schema_version,
  protocol_id,
  source_chain_id,
  source_coordinator,
  source_component,
  destination_chain_id,
  destination_coordinator,
  destination_component,
  lane_id,
  source_nonce,
  aggregate_id,
  action_type,
  payload_hash,
  created_at,
  expires_at,
  route_policy_hash,
  adapter_set_policy_hash,
  source_finality_policy_hash,
  destination_finality_policy_hash,
  correlation_id,
  causation_message_id,
  superseded_message_id
)

message_id = keccak256(message_preimage)
```

`message_id` is carried in the stored envelope but is never included in its own
preimage. The exact ordered preimage above is shared by Solidity, Protobuf, Go,
TypeScript, Python, and SQL. `payload_hash` commits to the typed ABI encoding, including
its schema version. The message does not contain caller-selected executable calldata.
Destination dispatch is an explicit `action_type` switch to a registered component.

Provider identity, provider attempt, fee, delivery time, retry count, and transport
receipt are intentionally excluded from `message_id`. Provider A and provider B must
carry the same immutable envelope and source proof. Failover changes only delivery
attempt evidence; it cannot change the logical instruction.

For each lane and nonce:

- an unseen exact message may proceed;
- an exact retry returns the stored result and cannot repeat the external call;
- the same lane and nonce with changed content is rejected;
- a future nonce waits without executing; and
- a stale nonce without the exact stored digest is rejected.

The coordinator consumes the message and calls the target in one non-reentrant
transaction. A target revert leaves the message retryable without a partial economic
effect. A successful target call and its result commitment become terminal atomically.

## Message state machines

The durable cross-domain state machine is:

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
```

Failure and recovery branches are:

```text
SOURCE_FINALIZING | SENT | RELAYED -> EXPIRED
SENT | RELAYED | VERIFIED         -> REJECTED
SENT | RELAYED | VERIFIED         -> FAILED
FAILED                            -> SENT only for an exact, unexpired, classified retry
REJECTED | EXPIRED | FAILED       -> RECOVERY_PENDING
RECOVERY_PENDING                  -> DESTINATION_TOMBSTONED
DESTINATION_TOMBSTONED            -> SOURCE_COMPENSATED -> RECOVERED
any safety contradiction          -> DISPUTED
```

`SOURCE_FINAL` means the exact source event passed its pinned finality policy.
`SENT`, `RELAYED`, and provider delivery receipts are not destination acceptance.
`VERIFIED` is not execution. `EXECUTED` stores the destination effect and result hash.
`ACK_PENDING` is the durable wait for finalized destination evidence at home.
`ACKNOWLEDGED` is an observation of that terminal result, not another economic action.

Every state change is append-only, compare-and-set, and tied to the immutable message
digest. SQL state may lag chain state and must recover by replay. It may never lead it.
Retry classification is stored as evidence. A nonretryable, expired, rejected, or
recovery-selected failure cannot return to `SENT`.

## Synthetic local finality proof

Phase 8 reuses the Phase 7C authenticated EVM evidence boundary:

1. a pinned local Ed25519 observer signs a canonical source header;
2. the indexer derives the header hash, parent, height, timestamp, transaction root, and
   receipt root from RLP;
3. transaction and receipt Merkle-Patricia inclusion are verified at the same index;
4. the source contract, event signature, topics, data, transaction, log index, and
   message ID and payload hash are decoded from the included receipt;
5. the configured signed-head depth is reached; and
6. the complete proof receives threshold attestations from two of three local ECDSA
   finality signers.

The finality-certificate digest binds:

```text
"UNIFIED_SYNTHETIC_FINALITY_V1"
protocol ID
source chain and coordinator
source contract
message ID and source nonce
source block hash, height, and timestamp
transaction hash and index
receipt root and receipt-proof commitment
log index and source-event commitment
finality head hash and height
required depth
header-authority hash
finality-policy hash
signer-set hash and version
```

The destination `SyntheticFinalityVerifier` verifies the threshold, signer uniqueness,
validity interval, certificate domain, and exact route policy before the coordinator can
consume a message. A signer cannot substitute a different source contract, destination,
action, aggregate, payload, nonce, or proof commitment.

The Ed25519 observer and two-of-three ECDSA signer set are synthetic local trust roots.
They are not EVM consensus verification, a light client, a zero-knowledge proof, or a
production bridge-security claim. Production deployment is blocked until a separate ADR
selects an independently verifiable finality design and its compromise assumptions.

## Provider abstraction and failover

Providers implement only:

```text
Submit(immutable envelope, immutable finality certificate) -> attempt receipt
Observe(message ID) -> transport status
```

They cannot sign source authority, choose the destination call, change expiry, allocate
nonces, mark execution successful, or authorize recovery. Provider attempts are stored
under `(message_id, provider_id, attempt_number)` and are never the message primary key.

The local coordinator submits to provider A first. On a bounded retryable failure or
outage it submits the exact bytes to provider B. Both providers may deliver concurrently
or out of order. Destination replay protection makes duplicate delivery harmless.
Provider disagreement opens an operational exception but does not change chain state.

A compromised provider route is disabled for new attempts. Already-finalized source
value stays locked or burned until the same instruction executes through another
approved provider or the recovery protocol proves a destination tombstone. Failover
never means constructing a replacement economic message.

## Typed satellite loan actions

The first slice supports only these versioned actions:

| Direction | Action | Bounded effect |
|---|---|---|
| satellite to home | `SATELLITE_COLLATERAL_LOCKED_V1` | Prove exact exclusive collateral custody |
| home to satellite | `HOME_DISBURSEMENT_AUTHORIZED_V1` | Permit one exact backed-escrow borrower transfer |
| satellite to home | `SATELLITE_DISBURSEMENT_SETTLED_V1` | Prove exact borrower receipt |
| satellite to home | `SATELLITE_REPAYMENT_BURNED_V1` | Prove an exact loan-bound wUFT burn |
| home to satellite | `HOME_COLLATERAL_RELEASE_AUTHORIZED_V1` | Permit one exact release after zero home debt |
| satellite to home | `SATELLITE_COLLATERAL_RELEASED_V1` | Prove exact borrower release |

Every payload binds the loan ID, home loan account, home and satellite chain and
component identities, borrower, lender, exact registered asset, integer amount, action
sequence, loan state nonce, policy-set hash, and an action-specific evidence commitment.
Amounts use native integer token units. The first slice has no FX, fee, interest,
penalty, split waterfall, rounding, or caller-selected recipient.

### End-to-end loan flow

```text
1. Home CrossChainLoanAccount is created with immutable terms and satellite route.
2. Borrower locks exact collateral in SatelliteCollateralVault.
3. Final satellite lock proof reaches home; home records exclusive collateral.
4. Home emits one exact disbursement authorization.
5. The bridge mints exact backed wUFT into SatelliteSettlementVault, which transfers
   the authorized amount to the registry borrower and records one terminal
   disbursement result.
6. Final destination acknowledgement activates the home loan.
7. Borrower authorizes an exact loan-bound wUFT repayment burn; the satellite burns the
   units and emits the repayment-burn message in the same transaction.
8. Home consumes each finalized burn once and atomically reduces canonical debt while
   releasing the same canonical UFT units from backing to the registry lender.
9. Only after home debt is zero and the loan enters `CLOSING` does home authorize
   release.
10. SatelliteCollateralVault releases the exact collateral once to the registry
    borrower and acknowledges the result.
```

The satellite settlement vault receives only the exact backed wUFT mint for the
authorized disbursement. It proves exact vault and borrower balance deltas and retains no
unexplained new balance. A satellite repayment cannot reduce home debt unless the exact
wUFT supply reduction is final and the same home transaction releases backing to the
canonical lender. The home loan rejects repayment above its allowed exact amount in this
first slice.

The home loan also preserves a direct canonical-UFT repayment path during satellite,
adapter, or verifier outage. Direct repayment transfers exact canonical UFT from the
payer to the registered lender and reduces home debt atomically under a unique payment
ID. It does not consume a satellite burn, release bridge backing, reduce wrapped
liability, or alter pending cross-chain messages. Zero debt enters the same `CLOSING`
collateral-release flow; `CLOSED` still requires finalized remote release evidence and
accounting reconciliation.

Collateral is reserved by `(satellite_chain_id, vault, asset, position_id)` for exactly
one home loan. Locking the same position for another obligation fails. A release message
cannot name a recipient; the vault derives the borrower from its immutable position.

## Wrapped UFT bridge

The first slice implements one home-to-satellite route:

- `UFTBridgeHub` and `BridgeExposurePolicy` on the home chain;
- `WrappedUFT` on the satellite chain;
- one immutable canonical UFT identity;
- one immutable satellite wrapped-token identity; and
- one registered route and route-policy hash.

### Lock and mint

```text
user approves exact canonical UFT
-> home hub locks exact amount in route escrow
-> home lock message reaches source finality
-> satellite verifies message and route
-> WrappedUFT mints exact amount to bound recipient
-> destination result is acknowledged on home
```

Lock precedes mint. The hub increments backing before the source event can exist.
`WrappedUFT` accepts issuance only from its coordinator for
`HOME_UFT_MINT_AUTHORIZED_V1`. It has no independent minter role or public issuance
method. Exact retries return the original mint result.

### Burn and release

```text
user burns exact wrapped UFT on satellite
-> satellite burn message reaches source finality
-> home verifies burn and route
-> hub releases exact canonical UFT to the bound recipient
-> home result is acknowledged on satellite
```

Burn precedes release. A failed, expired, or censored burn message leaves canonical
backing locked and the wrapped units already destroyed; it creates a visible redemption
liability until delivery or controlled recovery completes. A provider timeout alone
cannot release canonical UFT.

### Permanent burn

For `SATELLITE_UFT_PERMANENT_BURNED_V1`, the home hub burns the equivalent escrowed
canonical UFT instead of releasing it. The satellite final burn must be proven first.
The canonical burn reduces both escrow and the related redemption obligation. The
operation closes only when token supply, bridge backing, ledger control accounts, and
both message histories reconcile.

### Backing and exposure

For each satellite route `c`:

```text
Wc = outstanding WrappedUFT total supply on c
Ec = canonical UFT restricted in the home escrow for c
Pc = verified pending mint less verified pending burn finalization
```

The governing bounds are:

```text
Wc <= Ec + Pc
sum(Wc) <= sum(Ec) + sum(Pc)
```

The local first slice enforces the stricter operational condition `Wc <= Ec` because a
home lock always finalizes before mint. `Pc` remains explicit for reconciliation and
future route models; it cannot be caller-supplied.

Before accepting a new lock, the hub checks:

```text
route escrow after lock <= route absolute cap
route escrow after lock <= 5% of canonical circulating supply
chain exposure after lock <= chain cap
aggregate bridge escrow after lock <= aggregate absolute cap
aggregate bridge escrow after lock <= 15% of canonical circulating supply
adapter exposure after lock <= adapter cap
```

Here `canonical circulating supply` is the immutable
`circulating_supply_reference_units` recorded by the active exposure-policy version,
with its synthetic evidence hash; it is not calculated from caller input.

The percentage ceilings are launch maxima, not targets. Governance may set lower values.
Increasing exposure requires the configured delayed authority and a new policy version.
Lowering a cap blocks new exposure immediately but never blocks burn, redemption,
tombstone, or compensation paths needed to reduce exposure.

Escrowed canonical UFT cannot vote, count as free treasury liquidity, support collateral,
or count as safety-staking capital. Wrapped UFT has no voting or collateral adapter in
Phase 8.

## Accounting and reconciliation

Cross-chain messages are evidence, not complete accounting entries. Accounting posts only
from exact finalized contract effects and uses stable message, transaction, and log
identities as idempotency keys.

The Phase 8 chart extension reserves:

| Code | Purpose |
|---|---|
| `1410` | Canonical Assets Locked for Bridging |
| `1420` | Cross-Chain Settlement Receivable |
| `1430` | Satellite Asset Receivable |
| `2230` | Bridge Backing Liability |
| `5120` | Cross-Chain Messaging Expense |
| `5320` | Bridge Loss |
| `7150` | UFT Locked in Bridge Escrow Control |
| `7160` | Wrapped UFT Outstanding Control |
| `9150` | Pending Cross-Chain Settlement |
| `9180` | Ledger-to-Chain Reconciliation Difference |

Account names and normal balances are frozen in 8A before a migration uses these codes.
No fee, loss, reserve, receivable, or revenue is inferred from a message status.
`5320 Bridge Loss` may be used only under separately approved economic evidence.

At a canonical UFT lock:

```text
Debit  1410 Canonical Assets Locked for Bridging [canonical UFT]
Credit 2230 Bridge Backing Liability              [canonical UFT]

Debit  7150 UFT Locked in Bridge Escrow Control [canonical UFT]
Credit 9150 Pending Cross-Chain Settlement      [canonical UFT]
```

At finalized wrapped issuance, memorandum control records the exact wrapped units:

```text
Debit  9150 Pending Cross-Chain Settlement [wUFT]
Credit 7160 Wrapped UFT Outstanding Control [wUFT]
```

At finalized wrapped burn the wUFT control journal reverses. At canonical release or
corresponding permanent burn, `2230` is debited and `1410` is credited, while the
canonical pending/escrow control journal reverses, for the exact canonical units. Every
journal balances within one asset identity. Issuance and redemption are supply-control
events, not revenue.

Satellite collateral and settlement balances use control/custody journals tied to the
exact finalized vault event. Loan receivable reduction occurs only from the finalized
`SATELLITE_REPAYMENT_BURNED_V1` effect and the same atomic home transaction that releases
exact backing to the canonical lender. Existing principal receivable and lender
claim/payable accounts remain authoritative; Phase 8 does not invent interest, FX, fee,
or reserve economics.

Continuous reconciliation compares:

- home hub token balance to the sum of route escrow obligations;
- route escrow to wrapped supply and pending finalized actions;
- canonical UFT supply to genesis issuance less canonical burns;
- satellite `WrappedUFT.totalSupply()` to issuance/burn events and ledger controls;
- home and satellite message state, nonces, results, acknowledgements, and tombstones;
- satellite custody token balances to exclusive collateral positions;
- settlement-vault disbursement deltas, wrapped burn/supply deltas, and home lender
  receipts; and
- finalized chain effects to immutable journals and read models.

Every difference has an ID, source values, amount, asset, evidence, detection time,
severity, owner, deadline, status, and resolution reference. A difference remains open
or incident-owned. It is never silently netted, hidden in suspense, or booked as revenue.

## Timeout, tombstone, and compensation

Expiry is a delivery control, not proof that a destination did nothing. After
`expires_at`, ordinary first execution of the original message is rejected and the
workflow enters `RECOVERY_PENDING`. No source asset unlocks and no debt, mint, payout,
or custody state changes because a clock elapsed.

Recovery uses the same message identity:

1. the authorized recovery controller emits a cancellation request referencing the
   original message, immutable digest, bounded amount, reason, and recovery nonce;
2. the destination coordinator returns the stored execution result if the message
   executed;
3. otherwise it atomically records a permanent tombstone for the original message;
4. the tombstone event reaches the destination's configured finality;
5. the source verifies the exact tombstone proof; and
6. only then may the source perform the predefined compensation and record `RECOVERED`.

An executed result prevents source compensation. A tombstone prevents later execution.
These facts are mutually exclusive in destination storage. A refund, escrow unlock,
collateral change, or balance restoration is therefore impossible on both branches.

Recovery authorization is two-of-three in the local environment and binds the original
message, amount, assets, source and destination state commitments, route versions,
expiry, reason, and recovery action. It can request cancellation or submit independently
verified destination evidence; it cannot declare non-execution without a finalized
destination tombstone.

If the destination is unavailable, the verifier threshold is suspected compromised, or
the two domains disagree, value stays frozen and the workflow enters `DISPUTED`. An
approved transport provider may continue relaying the same route-pinned message.
Replacing the route policy never reuses that message: only after a finalized destination
tombstone and source recovery may reauthorization create a new nonce and message ID that
binds the superseded message. There is no unilateral operator unlock, message deletion,
arbitrary recipient, or general rescue function.

A deep reorganization after a finalized action freezes the affected lane and exposure,
records the full orphan/replacement proof, opens an incident, and posts linked accounting
opposites only when the canonical economic effect is actually absent. It never
automatically mints, releases, refunds, reopens debt, or releases collateral.

## Local two-chain topology

The reproducible environment extends the foundation stack:

```text
Anvil home      chain 31337
Anvil satellite chain 31338
PostgreSQL      durable messages, proofs, attempts, reconciliation, ledger
Redpanda        transactional outbox delivery and replay
MinIO           immutable synthetic raw proof/evidence objects
mock provider A normal delivery with configurable delay/failure
mock provider B failover, duplicate, reorder, and outage simulation
local observers and 2-of-3 signers using test-only keys
```

Home and satellite have separate deployment manifests, RPC endpoints, observer keys,
coordinator addresses, and confirmation policies. The smoke path deploys from a clean
checkout, seeds only synthetic tokens, runs the loan and UFT flows, reconciles both
chains and the ledger, restarts workers to prove recovery, and resets all local state
with one command.

No container or fixture may contain a production endpoint, real credential, real account
number, real identity, public private key, or live asset identifier.

## Staged implementation

### 8A — Freeze authority and schemas

- ratify ADR-0018 for the local cross-chain trust, recovery, and wrapped-UFT model;
- freeze action enums, message digest, lane order, finality proof, state machines,
  account names, reconciliation equations, risk assumptions, and production deferrals;
- extend canonical Protobuf and regenerate Solidity, Go, TypeScript, and Python bindings;
- register `UNI-ADR-013`, `UNI-SCHEMA-012`, and `UNI-LOCAL-002`;
- register the named Phase 8 risks, assumptions, and frozen local circulating-supply
  evidence under `UNI-RISK-002`; and
- reject schema changes that alter an existing digest or action meaning.

### 8B — Coordinator and recovery kernel

- implement `CrossChainTypes`, `ChainRegistry`, `RouteRegistry`,
  `SyntheticFinalityVerifier`, `CrossChainCoordinator`, and
  `CrossChainRecoveryController`;
- implement lane nonces, exact replay, ordered dispatch, acknowledgements, expiry,
  tombstones, route pause, and append-only policy versions; and
- prove at-most-once execution and no timeout double effect with Foundry unit,
  adversarial, fuzz, and invariant tests.

### 8C — Satellite loan slice

- implement the immutable cross-chain loan policy, `CrossChainLoanFactory`,
  `CrossChainLoanAccount`, `SatelliteLoanComponent`, `SatelliteCollateralVault`, and
  `SatelliteSettlementVault`;
- implement only the six typed actions in this boundary; and
- demonstrate exclusive collateral, exact disbursement, exact repayment burn plus home
  lender release, one home debt reduction, and home-authorized collateral release.

### 8D — Wrapped UFT and exposure

- implement `UFTBridgeHub`, `BridgeExposurePolicy`, and `WrappedUFT`;
- implement lock/mint, burn/release, permanent burn, caps, pause, and exit-safe recovery;
- update privileged-surface controls only for the coordinator-restricted wrapped-token
  issuance primitive, without permitting mint in canonical UFT or other contracts; and
- prove backing and cap equations with stateful invariant tests.

### 8E — Durable services, data, and accounting

- add a cross-chain coordinator service with message, provider, recovery, store, and
  reconciliation packages;
- extend chain ingestion for both domains and exact finality/tombstone projections;
- add append-only migrations for messages, satellite loan accounting, and wrapped UFT;
- implement the `UNI-DATA-002` `NOLOGIN` owner, least-privilege runtime role, and
  reviewed callable transaction surface with no authoritative direct writes;
- add exact, idempotent accounting adapters and restart-rehydrated repositories; and
- prove runtime credentials cannot insert or mutate authoritative success records
  outside approved functions.

### 8F — Simulations and exit review

- run two Anvil chains, two providers, failure controls, topics, deployments, and smoke
  scripts in the local stack;
- add provider failover, duplicate, reorder, timeout race, route compromise, finality
  delay, signer compromise, deep-reorg, restart, and reconciliation simulations;
- run the full foundation, Phase 8, generated-code, ABI, architecture, secret, and
  filesystem checks; and
- complete internal security and exit reviews before Phase 8 is marked done.

## Required acceptance tests

The Phase 8 exit review requires evidence that:

- golden Solidity, Go, TypeScript, and Python encoders produce the same message and
  finality digests;
- wrong protocol, chain, coordinator, component, route, signer set, aggregate, action,
  payload, nonce, expiry, transaction, receipt, log, or finality head fails closed;
- one message executes at most once under concurrent duplicates, both providers, restart,
  and replay;
- changed content at the same lane and nonce fails and out-of-order dependent actions do
  not execute;
- a target revert is retryable without a partial consume or partial token movement;
- provider A outage fails over to provider B without changing message identity;
- expiry, cancellation, execution, acknowledgement, tombstone, and compensation races
  cannot create both destination effect and source unlock;
- satellite components cannot change home principal, terms, lender, borrower, policy,
  debt, or terminal state;
- collateral cannot support two loans and cannot release before a finalized exact home
  authorization;
- disbursement and repayment prove exact registered-token balance deltas and recipient;
- direct home repayment remains live during route outage, cannot release backing, and
  reaches the same evidence-gated collateral-release closure path;
- canonical UFT lock precedes wrapped mint and wrapped burn precedes canonical release;
- replay cannot double mint, burn, release, permanent-burn, repay, disburse, or release
  collateral;
- randomized sequences maintain `Wc <= Ec`, global backing, escrow-balance equality, and
  every absolute, chain, adapter, 5%, and 15% cap;
- cap reduction and route pause block new exposure but preserve redemptions and recovery;
- every bridge, loan, suspense, and compensation journal is independently balanced,
  immutable, idempotent, and traceable to finalized evidence;
- reconciliation catches injected supply, escrow, nonce, message, vault, journal, and
  read-model differences and leaves them visibly owned;
- a database outage never retries an already-finalized economic action;
- least-privilege database credentials cannot forge chain success or accounting;
- projections rebuild from retained events after restart and after a simulated reorg;
- the complete local product passes from a clean checkout and resets with one command;
  and
- tests use no real funds, providers, credentials, identities, or public networks.

These tests trace `INV-SUP-009` through `INV-SUP-013`, `INV-BRG-001` through
`INV-BRG-012`, and `T-BRG-001` through `T-BRG-015`.

## Explicit production deferrals

Phase 8 does not select or approve:

- a production home chain, satellite chain, bridge, relayer, messaging provider, RPC,
  header source, consensus verifier, light client, or finality threshold;
- public-network deployments, real UFT, real collateral, stablecoins, lender or borrower
  funds, treasury assets, HSM/KMS custody, production signing, or privileged operations;
- a live adapter upgrade mechanism, unilateral recovery, arbitrary manual balance
  correction, or administrator rescue;
- wrapped-UFT voting, governance delegation, collateral eligibility, staking, liquidity,
  exchange listing, or cross-chain governance;
- arbitrary chains, non-EVM domains, arbitrary assets, multiple live satellites,
  fractional collateral, multi-loan collateral reuse, cross-asset exposure, FX, fees,
  slippage, rounding, interest, penalties, or multi-lender waterfalls;
- funded reserves, insurance, loss guarantees, route solvency claims, or bridge-risk
  capitalization;
- production legal terms, licensing, tax, custody, sanctions, accounting, operational
  support, incident notification, or recovery-service conclusions; or
- production SLOs, capacity, geographic resilience, disaster recovery, monitoring,
  audit, formal verification, penetration testing, or external security review.

Each production item requires a separately ratified ADR, provider and chain due
diligence, threat-model update, economic stress testing, operational runbooks,
least-privilege IAM, independent audit, and an explicit deployment approval.
