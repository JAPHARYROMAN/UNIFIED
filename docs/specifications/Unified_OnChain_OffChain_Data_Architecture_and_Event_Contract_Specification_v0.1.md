# Unified On-Chain/Off-Chain Data Architecture and Event Contract Specification v0.1

**Status:** Foundational Architecture Specification

**Version:** 0.1

**Applies to:** Unified Protocol, UFT, lending, collateral, payments, accounting, governance, identity, underwriting, bridges, marketplaces, indexers, analytics, operations, and all derived applications.

---

## 1. Purpose

This specification defines how Unified stores, signs, transports, indexes, reconciles, protects, retains, restores, and exposes data across on-chain and off-chain systems.

It converts the Unified Constitution, Domain Model, Universal Loan Model, Financial Accounting Specification, UFT Tokenomics, Threat Model, Formal Invariants, and Smart Contract Interface Specification into a concrete data architecture.

The architecture shall preserve five non-negotiable properties:
- Every financially material fact has one declared canonical authority.
- Derived databases may project canonical facts but may not replace or contradict them.
- Every command and event is idempotent, versioned, attributable, and auditable.
- Sensitive identity, credit, banking, and communication data is private by default.
- Reorganizations, provider reversals, bridge delays, and partial failures are represented explicitly rather than hidden.

---

## 2. Normative language

The terms **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative requirements.

A component is conformant only when it satisfies the requirements applicable to its authority class, privacy class, event class, and recovery tier.

---

## 3. Governing data principles

### D1 — Canonical authority

Every entity and financial fact MUST have exactly one canonical authority at a given time.

### D2 — Projection non-authority

Search indexes, caches, dashboards, analytics stores, and read models MUST NOT originate contractual or financial rights.

### D3 — Append-only history

Canonical event history and posted accounting history MUST be append-only; corrections occur through compensating records.

### D4 — Explicit finality

Initiated, observed, provisional, confirmed, finalized, reversed, disputed, and failed states MUST remain distinguishable.

### D5 — Domain ownership

Only the owning aggregate or authority may mutate its canonical state.

### D6 — Privacy by construction

Sensitive data MUST be minimized, encrypted, access-controlled, purpose-bound, and retained only as long as required.

### D7 — Verifiable provenance

Every material record MUST identify its source, actor, time, schema version, and integrity proof where applicable.

### D8 — Replay safety

Commands, callbacks, and cross-chain messages MUST be idempotent and replay-protected.

### D9 — Reconciliation

Off-chain representations of on-chain or provider-controlled facts MUST be continuously reconciled.

### D10 — Recoverability

Every durable state change MUST have a documented restoration and disaster-recovery path.

### D11 — No secret canonical finance

Financial rights and obligations MUST NOT depend solely on mutable application databases or hidden administrator records.

### D12 — Version permanence

Active agreements MUST remain bound to the exact schema and policy versions accepted at activation.

---

## 4. Authority classes

| Authority class | Canonical owner | Typical data | Mutation method | Required reconciliation |
|---|---|---|---|---|
| ONCHAIN_HOME | Canonical home-chain contracts | Loan terms, debt state, collateral rights, UFT supply, governance execution | Validated transactions | Indexer and ledger reconciliation |
| ONCHAIN_SATELLITE | Approved satellite-chain contracts | Remote collateral custody, wrapped assets, local settlement components | Validated satellite transactions | Home-chain and bridge reconciliation |
| SIGNED_OFFCHAIN | Cryptographically signed payload | Offers, consent, attestations, quotes, delegated commands | New signed version or revocation | Signature, nonce, expiry, and consumption checks |
| REGULATED_PROVIDER | Approved bank, card, KYC, custody, or payment provider | Fiat settlement, chargebacks, identity evidence, provider custody | Authenticated provider action | Provider statements and settlement reconciliation |
| UNIFIED_LEDGER | Unified double-entry ledger | Accounting journals, receivables, liabilities, reserves, suspense | Balanced posted journal | Chain, provider, vault, and bank reconciliation |
| USER_CONTROLLED | User wallet or client-side encrypted store | Keys, recovery secrets, private drafts, local preferences | User-authorized action | Optional integrity verification |
| DERIVED | Read-model or analytics pipeline | Search documents, dashboards, scores, portfolio views | Deterministic projection | Rebuild from canonical sources |
| GOVERNANCE_CONTROLLED | Governor, timelock, and constitutional process | Future protocol parameters and approved versions | Proposal and delayed execution | Execution-event reconciliation |

No record may move from one authority class to another without an explicit authority-transfer event and migration procedure.

---

## 5. System context and data planes

```text
Users and Wallets
        │
        ▼
API Gateway / Command Gateway
        │
        ├────────► Identity and Underwriting Plane
        ├────────► Marketplace and Social Plane
        ├────────► Payment and Provider Plane
        ├────────► Accounting Plane
        └────────► Protocol Transaction Plane
                         │
                         ▼
              Home and Satellite Chains
                         │
                         ▼
              Chain Indexing and Finality
                         │
                         ▼
       Canonical Event Bus and Projection Pipelines
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
 Operational DB     Search Index     Analytics Warehouse
        │                │                │
        └────────────────┴────────────────┘
                         │
                         ▼
                 Read APIs and Interfaces
```

Unified operates six distinct data planes:
- **Transaction plane:** blockchain transactions and provider settlement actions.
- **Command plane:** authenticated requests that may cause state transitions.
- **Event plane:** immutable notifications that a transition occurred or was observed.
- **Accounting plane:** balanced journals and reconciliation controls.
- **Projection plane:** query-optimized read models and indexes.
- **Control plane:** configuration, schemas, keys, roles, observability, and incident controls.

---

## 6. Canonical entity storage matrix

| Entity | Canonical authority | Core fields | Privacy class |
|---|---|---|---|
| Party | UNIFIED_LEDGER / SIGNED_OFFCHAIN | party_id, status, profile refs | PUBLIC / CONFIDENTIAL |
| WalletAccount | ONCHAIN_HOME / USER_CONTROLLED | address, chain, delegation | PSEUDONYMOUS_PUBLIC |
| IdentityCredential | SIGNED_OFFCHAIN / REGULATED_PROVIDER | issuer, claims hash, expiry, revocation | RESTRICTED_IDENTITY |
| Tender | SIGNED_OFFCHAIN with optional chain anchor | terms, visibility, expiry, metadata hash | PUBLIC or CONFIDENTIAL |
| Offer | SIGNED_OFFCHAIN | typed terms, nonce, expiry, signatures | CONFIDENTIAL until accepted |
| LoanAgreement | ONCHAIN_HOME | immutable snapshot and policy refs | PSEUDONYMOUS_PUBLIC |
| LoanState | ONCHAIN_HOME | state vector, balances, deadlines | PSEUDONYMOUS_PUBLIC |
| FundingCommitment | ONCHAIN_HOME or SIGNED_OFFCHAIN until funded | amount, lender, tranche, expiry | PSEUDONYMOUS_PUBLIC |
| LenderPosition | ONCHAIN_HOME | owner, share, seniority, encumbrance | PSEUDONYMOUS_PUBLIC |
| CollateralPosition | ONCHAIN_HOME / ONCHAIN_SATELLITE | asset, quantity, lien, custody | PSEUDONYMOUS_PUBLIC |
| FiatPayment | REGULATED_PROVIDER + UNIFIED_LEDGER | provider ref, statuses, amounts | RESTRICTED_FINANCIAL |
| CardPayment | REGULATED_PROVIDER + UNIFIED_LEDGER | authorization, capture, settlement, chargeback | RESTRICTED_FINANCIAL |
| CryptoPayment | ONCHAIN_HOME or ONCHAIN_SATELLITE | transaction, confirmations, allocation | PSEUDONYMOUS_PUBLIC |
| JournalEntry | UNIFIED_LEDGER | balanced lines, source refs, posting status | RESTRICTED_FINANCIAL |
| OracleObservation | ONCHAIN_HOME or APPROVED_PROVIDER | price, timestamp, source set, confidence | PUBLIC |
| Liquidation | ONCHAIN_HOME | eligibility, route, proceeds, waterfall | PUBLIC |
| CreditDecision | SIGNED_OFFCHAIN | policy, model, grade, exposure, expiry | RESTRICTED_FINANCIAL |
| Conversation | USER_CONTROLLED / encrypted application store | ciphertext, participants, message metadata | CONFIDENTIAL |
| UFTSupply | ONCHAIN_HOME | genesis, burns, total supply | PUBLIC |
| UFTStake | ONCHAIN_HOME | shares, cooldown, slash state | PUBLIC |
| GovernanceProposal | ONCHAIN_HOME | payload hash, votes, execution | PUBLIC |
| CrossChainMessage | ONCHAIN_HOME and ONCHAIN_SATELLITE | source, destination, nonce, payload hash, status | PUBLIC |
| AuditRecord | append-only operational store | actor, action, target, correlation, outcome | RESTRICTED_FINANCIAL |
| Projection | DERIVED | materialized query view | classification inherited from source |

---

## 7. Storage architecture

### 7.1 On-chain storage

- Only values required for enforcement, authorization, replay protection, settlement, auditability, or canonical rights SHOULD be stored directly on-chain.
- Large descriptions, raw identity data, chat content, model inputs, and provider documents MUST NOT be placed on public chains.
- Immutable activation snapshots SHOULD be represented through compact structs, hashes, and exact version references.
- Mappings MUST expose events sufficient to rebuild externally queryable history.
- Upgradeable storage layouts MUST use documented namespaces, reserved gaps, or equivalent collision-resistant patterns.
- No implementation may reuse a storage slot for a semantically different variable across upgrades.

### 7.2 Operational relational store

A strongly consistent relational database SHOULD store off-chain aggregates, command status, provider records, encrypted metadata references, and deterministic projections requiring transactions.

Recommended logical schemas:
- `identity`
- `marketplace`
- `loans`
- `funding`
- `collateral`
- `payments`
- `accounting`
- `uft`
- `governance`
- `crosschain`
- `notifications`
- `audit`
- `reconciliation`
- `operations`

Each table MUST contain, where applicable:
- stable primary identifier
- aggregate identifier
- aggregate version
- schema version
- created timestamp
- updated timestamp
- source authority
- source reference
- correlation identifier
- causation identifier
- privacy class
- retention class
- soft-deletion marker only where legally and semantically valid

### 7.3 Append-only event store

Unified SHOULD maintain an append-only event archive independent of mutable operational projections.

The archive MUST preserve:
- event envelope
- raw source payload
- normalized payload
- schema version
- source block or provider reference
- ingestion time
- finality status
- reorg or reversal linkage
- integrity checksum
- consumer offsets and replay metadata

### 7.4 Search indexes

Search indexes MAY contain tenders, public profiles, asset metadata, loan summaries, and governance records. Search indexes are always DERIVED and MUST be rebuildable.

Sensitive identity, financial, and communication fields MUST NOT be indexed unless explicitly approved, encrypted where supported, and access-filtered before query execution.

### 7.5 Analytics warehouse

The analytics warehouse MUST receive de-identified or pseudonymized data whenever individual identity is unnecessary.

Production transaction systems MUST NOT depend on the analytics warehouse for authorization, debt calculation, collateral release, or payment finality.

### 7.6 Object and document storage

Encrypted object storage MAY retain KYC artifacts, signed legal documents, bank evidence, underwriting files, audit exports, and encrypted attachments.

Objects MUST use content hashes, envelope encryption, malware scanning, retention tags, legal-hold flags, and access audit trails.

### 7.7 IPFS and decentralized content storage

IPFS MAY store public metadata, public governance documents, public tender descriptions, encrypted attachments, and content-addressed disclosures.

Unencrypted personally identifiable information, raw KYC documents, bank details, private messages, and secret material MUST NOT be published to public content-addressed networks.

---

## 8. Command contract

Every state-changing off-chain request MUST use the following logical envelope:

```json
{
  "command_id": "uuid",
  "command_type": "loan.payment.finalize",
  "schema_version": "1.0.0",
  "aggregate_type": "Loan",
  "aggregate_id": "loan_...",
  "expected_version": 17,
  "actor": {"type": "wallet", "id": "0x..."},
  "idempotency_key": "...",
  "correlation_id": "...",
  "causation_id": "...",
  "submitted_at": "RFC3339 timestamp",
  "expires_at": "RFC3339 timestamp",
  "payload": {},
  "signature": "optional domain-bound signature"
}
```

Command requirements:
- `command_id` MUST be globally unique.
- `idempotency_key` MUST identify equivalent retries within the owning domain.
- `expected_version` MUST enforce optimistic concurrency where aggregate ordering matters.
- Commands MUST be authenticated and authorized before enqueueing.
- Command acceptance MUST NOT be represented as economic finality.
- Expired commands MUST fail without causing partial state changes.
- Rejected commands MUST produce structured failure events or durable command results.
- Commands crossing trust boundaries MUST be signed or carried over mutually authenticated transport.
- Payloads MUST be validated against an immutable schema version.
- Consumers MUST persist the result before acknowledging delivery.

---

## 9. Event contract

### 9.1 Canonical event envelope

```json
{
  "event_id": "globally unique id",
  "event_type": "loan.payment.finalized",
  "schema_version": "1.0.0",
  "aggregate_type": "Payment",
  "aggregate_id": "payment_...",
  "aggregate_version": 9,
  "occurred_at": "source time",
  "observed_at": "ingestion time",
  "producer": "payment-router",
  "authority_class": "REGULATED_PROVIDER",
  "source": {
    "chain_id": null,
    "block_number": null,
    "transaction_hash": null,
    "provider_id": "provider",
    "provider_reference": "reference"
  },
  "finality": "FINAL",
  "correlation_id": "...",
  "causation_id": "...",
  "privacy_class": "RESTRICTED_FINANCIAL",
  "payload": {},
  "integrity": {"algorithm": "sha256", "digest": "..."}
}
```

### 9.2 Event naming

Event names SHOULD follow `<domain>.<aggregate>.<past-tense-action>` for off-chain events and stable Solidity event names on-chain.

Examples:
- `marketplace.tender.published`
- `marketplace.offer.accepted`
- `loan.agreement.activated`
- `loan.interest.accrued`
- `payment.settlement.finalized`
- `payment.settlement.reversed`
- `collateral.position.locked`
- `liquidation.execution.completed`
- `accounting.journal.posted`
- `uft.supply.burned`
- `governance.proposal.executed`
- `crosschain.message.finalized`

### 9.3 Event immutability

- Published events MUST NOT be edited in place.
- Corrections MUST use superseding, reversal, invalidation, or compensation events.
- Every superseding event MUST reference the affected event.
- Consumers MUST be able to rebuild effective state by replaying the complete ordered stream.
- Event payload schemas MUST remain available for the lifetime of retained events.

### 9.4 Event finality classes

| Finality | Meaning | May change debt? | May release collateral? |
|---|---|---:|---:|
| OBSERVED | Source signal detected but not validated | No | No |
| PENDING | Accepted for processing | No | No |
| PROVISIONAL | Conditionally accepted and potentially reversible | Only provisional ledger state | No |
| CONFIRMED | Sufficient confirmations but not final under domain policy | Policy-dependent | No unless agreement explicitly permits |
| FINAL | Meets authority-specific finality policy | Yes | Yes when all other conditions pass |
| REVERSED | Previously accepted state reversed by valid authority | Restores balances | May reinstate lien if contract permits |
| DISPUTED | Finality contested or provider dispute open | Frozen or suspense | No |
| FAILED | Operation failed without completion | No | No |

---

## 10. On-chain event standards

Every material smart-contract transition MUST emit an event containing enough information to identify the aggregate, actor, version, and resulting state without requiring storage tracing.

Required event families include:
### 10.1 Protocol

- `ProtocolVersionApproved`
- `ProtocolPauseChanged`
- `PolicyVersionRegistered`
- `AdapterStatusChanged`

### 10.2 Marketplace

- `TenderCreated`
- `TenderUpdated`
- `TenderCancelled`
- `OfferConsumed`
- `OfferNonceCancelled`

### 10.3 Loans

- `LoanCreated`
- `LoanActivated`
- `LoanStateChanged`
- `LoanAmended`
- `LoanClosed`

### 10.4 Funding

- `CommitmentCreated`
- `CommitmentAccepted`
- `CommitmentRefunded`
- `PositionIssued`
- `PositionTransferred`

### 10.5 Collateral

- `CollateralDeposited`
- `CollateralLocked`
- `CollateralReleased`
- `MarginCallIssued`
- `CollateralLiquidated`

### 10.6 Payments

- `PaymentRegistered`
- `PaymentFinalized`
- `PaymentAllocated`
- `PaymentReversed`

### 10.7 Liquidation

- `LiquidationStarted`
- `LiquidationBid`
- `LiquidationCompleted`
- `LiquidationCancelled`

### 10.8 UFT

- `GenesisMinted`
- `UFTBurned`
- `UFTStaked`
- `UFTWithdrawalRequested`
- `UFTWithdrawn`
- `UFTSlashed`

### 10.9 Governance

- `ProposalCreated`
- `VoteCast`
- `ProposalQueued`
- `ProposalExecuted`
- `EmergencyActionActivated`

### 10.10 Cross-chain

- `MessageSent`
- `MessageReceived`
- `MessageExecuted`
- `MessageFailed`
- `WrappedUFTMinted`
- `WrappedUFTBurned`

Indexed Solidity parameters MUST be selected for stable queryability, not merely convenience. Dynamic payloads SHOULD emit a hash and structured identifiers when full content is stored elsewhere.

---

## 11. Chain ingestion and reorganization handling

### 11.1 Chain observation stages

```text
SEEN_IN_MEMPOOL
→ INCLUDED
→ CONFIRMING
→ CONFIRMED
→ FINALIZED

At any pre-final stage:
REORGED_OUT or REPLACED
```

### 11.2 Reorganization rules

- Indexer records MUST include chain ID, block number, block hash, transaction hash, log index, and contract address.
- The unique source key MUST include chain ID, transaction hash, and log index.
- Events MUST NOT be treated as final until the configured finality policy is satisfied.
- If a block is removed, every derived event from that block MUST be marked orphaned and compensating projection updates MUST run.
- Accounting entries dependent on pre-final chain events MUST remain pending or provisional.
- Finalized accounting MUST not be silently deleted after an exceptional deep reorganization; it requires an incident, reversal, and explicit governance or recovery process.
- Consumers MUST tolerate duplicate delivery and out-of-order observation across forks.
- Reprocessing a previously orphaned event in the canonical chain MUST remain idempotent.

### 11.3 Finality policy registry

Finality requirements MUST be configurable by chain, asset, action type, value tier, bridge route, and current risk state.

High-value collateral release, bridge minting, and treasury transfers SHOULD require stronger finality than read-only marketplace projection.

---

## 12. Provider callbacks and external event ingestion

- Every provider callback MUST be authenticated through signed payloads, mTLS, verified API credentials, or a stronger approved method.
- Callback payloads MUST be stored in raw immutable form before normalization.
- Provider event identifiers MUST be unique within the provider namespace.
- Duplicate callbacks MUST return the prior result without repeating economic effects.
- Provider event order MUST not be assumed unless the provider contract guarantees it.
- Conflicting provider statuses MUST enter reconciliation or dispute state.
- Provider timestamps MUST not replace Unified ingestion timestamps.
- All provider state changes MUST link to the matching payment, settlement, identity, or custody aggregate.
- Unknown callbacks MUST be quarantined rather than discarded.
- Credential rotation and provider-key compromise procedures MUST be documented.

---

## 13. Event bus and delivery semantics

Unified SHALL assume at-least-once delivery. Exactly-once economic effects are achieved through idempotent consumers, unique constraints, transactional outboxes, inbox tables, and deterministic posting keys.

### 13.1 Transactional outbox

- Aggregate mutation and outbox insertion MUST occur in the same database transaction.
- Outbox records MUST include aggregate version and event schema version.
- Publishers MUST retry until acknowledged by the broker.
- Outbox cleanup MUST occur only after durable publication evidence.
- Publishing the same outbox record multiple times MUST be safe.

### 13.2 Consumer inbox

- Each consumer MUST persist processed event identifiers.
- The business effect and inbox acknowledgement SHOULD commit atomically.
- Poison events MUST enter a dead-letter workflow with alerting and controlled replay.
- Consumer offsets are operational metadata and MUST NOT be the only deduplication mechanism.
- Replay MUST support a bounded time range, aggregate range, schema version, and dry-run mode.

### 13.3 Partitioning and ordering

Events requiring aggregate order MUST use a partition key derived from the canonical aggregate ID. Global ordering is not assumed.

Cross-aggregate workflows MUST use sagas, process managers, or explicit coordinator aggregates rather than relying on broker order.

---

## 14. Schema governance

### 14.1 Versioning

Schemas MUST use semantic versioning:
- PATCH for backward-compatible clarification or optional metadata
- MINOR for backward-compatible additive fields
- MAJOR for incompatible meaning, removed fields, changed types, or changed invariants

### 14.2 Compatibility rules

- Existing field meaning MUST NOT change within a major version.
- Required fields MUST NOT be added in a backward-compatible revision.
- Enumerations SHOULD support unknown future values.
- Consumers MUST ignore unknown optional fields unless security policy requires rejection.
- Amounts MUST include asset identity and units.
- Timestamps MUST specify timezone and precision.
- Identifiers MUST not be recycled.
- Hashes MUST declare algorithm and canonical serialization.
- All active-loan schema versions MUST remain readable for the agreement lifetime plus retention period.

### 14.3 Schema registry

A central registry MUST publish schemas, owners, compatibility mode, privacy class, retention class, and deprecation status.

No production producer may publish an unregistered financially material event schema.

---

## 15. Identifiers and correlation

| Identifier | Purpose |
|---|---|
| party_id | Global participant identity independent of wallet |
| account_id | Wallet, bank, card, custody, or ledger account |
| tender_id | Loan request aggregate |
| offer_id | Signed lender or borrower offer |
| loan_id | Canonical loan agreement |
| position_id | Lender economic position |
| collateral_position_id | Specific collateral lien or custody record |
| payment_id | User payment intent or receipt |
| settlement_id | Authority-specific settlement |
| journal_entry_id | Posted accounting journal |
| message_id | Cross-chain message |
| proposal_id | Governance proposal |
| command_id | Requested state-changing action |
| event_id | Published fact |
| correlation_id | End-to-end business workflow |
| causation_id | Immediate preceding command or event |

Public identifiers MUST not encode sensitive identity data or predictable secrets.

---

## 16. Privacy and data classification

| Class | Treatment | Examples |
|---|---|---|
| PUBLIC | Intended for unrestricted publication | Governance proposals, public protocol parameters |
| PSEUDONYMOUS_PUBLIC | Public but associated primarily with addresses | Loan IDs, positions, collateral events |
| CONFIDENTIAL | Limited to authorized parties | Negotiation messages, private tender details |
| RESTRICTED_IDENTITY | Identity and KYC information | Documents, legal name, address, biometric artifacts |
| RESTRICTED_FINANCIAL | Sensitive financial information | Bank records, credit data, accounting details |
| SECRET | Cryptographic or privileged operational material | Private keys, API secrets, recovery material |
| ZERO_KNOWLEDGE_ONLY | Only proof result should be exposed | Eligibility and identity predicates |

### 16.1 Data minimization

- Collect only fields necessary for a declared purpose.
- Separate identity from transaction data using stable internal references.
- Prefer claims, attestations, and zero-knowledge proofs over raw documents.
- Do not copy provider documents into multiple services.
- Do not place sensitive content in logs, metrics, traces, URLs, event keys, or error messages.
- Derived risk and reputation data MUST retain provenance and explanation metadata.
- Anonymization claims MUST be validated against re-identification risk.

### 16.2 Encryption

- Data in transit MUST use current approved authenticated encryption.
- Restricted and secret data at rest MUST use envelope encryption.
- Encryption keys MUST be separated by environment and sensitivity class.
- High-risk keys MUST be held in HSM or managed key systems with auditable access.
- Key rotation MUST not make retained records unreadable.
- Encrypted messaging SHOULD use per-conversation or per-recipient keys and forward-secrecy where feasible.
- Backups MUST preserve encryption and key-recovery procedures.

### 16.3 Access control

- Access MUST be deny-by-default and purpose-bound.
- Application authorization MUST evaluate user, role, tenant or jurisdiction, purpose, and resource sensitivity.
- Privileged access MUST be time-bound, approved, and fully audited.
- Support personnel MUST not receive unrestricted identity and financial access.
- Break-glass access MUST trigger alerts and post-use review.
- Data exports MUST be watermarked or otherwise attributable when feasible.

---

## 17. Data retention, deletion, and legal hold

Retention policies MUST distinguish contractual, accounting, regulatory, security, operational, and user-generated records.

| Retention class | Examples | Minimum behavior |
|---|---|---|
| PERMANENT_PROTOCOL | On-chain history, UFT supply, governance execution | Preserve indefinitely |
| LONG_FINANCIAL | Loan agreements, journals, settlements, liquidations | Retain for statutory and contractual period |
| IDENTITY_REGULATED | KYC evidence and attestations | Retain only as legally required; revoke access at expiry |
| SECURITY_AUDIT | Privileged actions, incident records, key events | Retain through security and legal horizon |
| OPERATIONAL | Queues, traces, temporary reconciliation artifacts | Short bounded retention |
| USER_CONTENT | Messages, drafts, attachments | User and legal policy dependent |
| DERIVED_ANALYTICS | Aggregated or pseudonymized metrics | Retain according to analytical purpose |

On-chain data cannot be deleted. Unified MUST therefore avoid placing erasable personal information on-chain.

Deletion of off-chain records MUST preserve required tombstones, audit proofs, accounting history, and referential integrity without preserving unnecessary sensitive content.

Legal holds MUST suspend deletion for scoped records and MUST be auditable.

---

## 18. Read models and projections

| Projection | Purpose |
|---|---|
| MarketplaceProjection | Searchable tenders, offers, visibility, expiry |
| LoanPortfolioProjection | Borrower and lender positions, balances, deadlines |
| CollateralHealthProjection | Valuation, thresholds, health factor, margin status |
| PaymentStatusProjection | Initiation through finality and reversal |
| AccountingBalanceProjection | Account balances and reconciliation status |
| UFTSupplyProjection | Supply, burns, vesting, staking, bridge backing |
| GovernanceProjection | Proposal lifecycle, voting, execution |
| CrossChainProjection | Message lifecycle and remote component state |
| RiskExposureProjection | Borrower, asset, bridge, provider, and protocol exposure |
| NotificationProjection | User-relevant state changes and delivery status |

Projection requirements:
- Every projection MUST record its source-event offset and build version.
- Projection updates MUST be idempotent.
- Projection state MUST be rebuildable from retained canonical events.
- Projection lag MUST be observable.
- Interfaces MUST disclose when data is pending, provisional, stale, or derived.
- High-risk actions MUST query canonical state or perform a fresh preflight check rather than trust a stale projection.
- Rebuilds MUST support shadow validation before replacing production views.

---

## 19. Accounting integration

The accounting ledger is canonical for posted journals, but it receives authorization evidence from chains, providers, and contractual policy engines.

### 19.1 Posting contract

A journal-posting request MUST include:
- journal intent ID
- source authority and reference
- business event type
- effective date
- posting date
- asset and units
- balanced debit and credit lines
- loan, payment, settlement, and position references
- idempotency key
- policy version
- supporting evidence hash
- approval metadata where required

### 19.2 Posting rules

- Journal entries MUST balance before posting.
- Posted entries MUST be immutable.
- Reversals MUST link to original entries.
- The same economic event MUST not post twice.
- Provisional and final balances MUST use distinct accounts or status dimensions.
- User collateral MUST remain segregated from protocol assets.
- Suspense balances MUST have owners, aging, and resolution deadlines.
- Provider reversals MUST restore the affected debt and allocation state consistently.
- Cross-chain accounting MUST not recognize destination assets before the applicable finality threshold.

---

## 20. Reconciliation architecture

Unified MUST operate continuous, scheduled, and incident-triggered reconciliation.

| Reconciliation | Comparison |
|---|---|
| CHAIN_TO_LEDGER | Contract balances and events against journal balances |
| CHAIN_TO_PROJECTION | Canonical contract state against operational read models |
| PROVIDER_TO_LEDGER | Bank, card, KYC, custody, and payment statements against Unified records |
| VAULT_TO_LIABILITY | Controlled asset balances against user and lender claims |
| UFT_SUPPLY | Genesis less burns against total supply and allocation vaults |
| BRIDGE_BACKING | Wrapped UFT and remote assets against canonical escrow |
| LOAN_TO_POSITION | Loan obligations against lender positions and tranche rights |
| COLLATERAL_TO_CUSTODY | Recorded liens against actual controlled collateral |
| STAKING_BACKING | sUFT shares against staking vault assets |
| TREASURY_RESERVE | Restricted reserve mandates against actual assets |

Every reconciliation result MUST produce:
- scope and as-of time
- source snapshots
- expected value
- observed value
- difference
- materiality class
- owner
- resolution deadline
- linked incident where applicable
- final disposition

Unexplained differences MUST NOT be silently written off or transferred to revenue.

---

## 21. Cross-chain data architecture

### 21.1 Canonical-home rule

Each loan, UFT supply record, governance process, and lender-position registry MUST have exactly one canonical home authority.

Satellite components may custody assets or execute bounded local actions, but may not independently redefine canonical economics.

### 21.2 Cross-chain message record

Every message MUST include:
- message ID
- source chain
- destination chain
- source contract
- destination contract
- nonce
- loan or aggregate ID
- action type
- payload hash
- adapter ID and version
- sent block and time
- required finality
- received proof
- execution status
- retry count
- timeout
- recovery status

### 21.3 Message states

```text
CREATED
→ SOURCE_FINALIZING
→ SENT
→ RELAYED
→ VERIFIED
→ EXECUTED
→ ACKNOWLEDGED

Failure branches: REJECTED, EXPIRED, FAILED, RECOVERY_PENDING, RECOVERED
```

### 21.4 Cross-chain invariants

- One message ID executes at most once.
- Payload, source, destination, nonce, and aggregate binding are immutable.
- Wrapped UFT issuance cannot exceed canonical escrow backing.
- A remote collateral claim cannot be active for two canonical loans unless explicitly fractionalized and fully accounted.
- Retry cannot duplicate economic effects.
- Timeout cannot silently unlock source assets while destination execution may still occur.
- Recovery actions MUST reconcile both chains and accounting before closure.

---

## 22. Identity, credentials, and underwriting data

### 22.1 Credential model

Unified SHOULD store verifiable claims and revocation status rather than raw identity documents wherever possible.

A credential record MUST identify:
- credential ID
- subject commitment
- issuer
- credential type
- claims hash
- issue time
- expiry time
- revocation registry
- jurisdiction and purpose restrictions
- proof type
- verification status

### 22.2 Underwriting record

Every automated or manual credit decision MUST preserve:
- application ID
- subject
- requested product and exposure
- input-data references
- consent basis
- policy version
- model version
- feature version
- decision
- risk grade
- approved limit
- expiry
- reason codes
- human-review status
- attester signature

Raw model inputs MUST remain access-restricted. Public-chain contracts SHOULD receive only the minimum signed decision or zero-knowledge proof required for enforcement.

### 22.3 Explainability and correction

- Users MUST be able to request the material factors behind automated decisions, subject to fraud and security constraints.
- Data corrections MUST produce a new decision version rather than editing history.
- Revoked or expired credit decisions MUST fail new-loan activation.
- Active loans remain governed by their accepted agreement unless a valid contractual process requires re-evaluation.

---

## 23. Messaging and social data

- Message bodies SHOULD be end-to-end encrypted where product constraints permit.
- Server-side indexes MUST not contain plaintext private messages unless the privacy model explicitly permits it.
- Metadata collection MUST be minimized.
- Attachments MUST be encrypted, scanned, and content-addressed.
- Accepted financial terms MUST be represented in structured signed offers; chat text alone is not the canonical agreement.
- Reporting and moderation workflows MUST preserve evidence without broadly exposing private content.
- Deleted user messages may remain subject to legal hold or abuse-investigation policy, which MUST be disclosed.

---

## 24. Caching and consistency

Unified SHALL use consistency levels appropriate to risk:

| Operation | Minimum consistency |
|---|---|
| Browse public tenders | Eventual consistency |
| View portfolio | Bounded staleness with visible timestamp |
| Submit offer | Strong aggregate concurrency control |
| Accept offer | Canonical chain preflight and signature validation |
| Release collateral | Canonical state and final payment verification |
| Cast governance vote | Canonical voting snapshot |
| Transfer lender position | Canonical ownership and encumbrance check |
| Finalize provider payment | Authenticated provider state plus idempotent ledger posting |
| Issue wrapped UFT | Canonical escrow and message finality |
| Treasury transfer | Canonical governance and timelock execution |

Caches MUST include expiry, source version, and invalidation strategy. Security-critical authorization MUST NOT rely solely on cache state.

---

## 25. Audit logging

Audit records MUST capture security-relevant and financially material actions, including reads of restricted data where feasible.

Required fields:
- audit ID
- actor identity and authentication context
- action
- target resource
- before and after references where permissible
- decision and authorization rule
- source IP or device context where lawful
- correlation ID
- time
- result
- privilege level
- reason or ticket for elevated access
- integrity checksum

Audit logs MUST be tamper-evident, separately protected, and unavailable for arbitrary modification by ordinary application administrators.

---

## 26. Observability and data-quality controls

- chain indexing lag by chain and contract
- event-bus publish and consume lag
- projection rebuild lag
- dead-letter queue depth
- duplicate event rate
- reorg frequency and depth
- provider callback failure rate
- payment finalization latency
- reconciliation differences and aging
- bridge backing ratio
- UFT supply reconciliation
- loan-to-position reconciliation
- collateral custody mismatch
- schema validation failures
- unauthorized data-access attempts
- backup success and restore-test age
- key-rotation status
- data-retention job status

Data-quality rules MUST detect missing identifiers, invalid amounts, unsupported assets, duplicate source records, impossible state regressions, stale finality, orphaned references, and aggregate-version gaps.

---

## 27. Backup, disaster recovery, and continuity

### 27.1 Backup classes

- Operational database snapshots and point-in-time recovery logs.
- Append-only event archive replicas.
- Encrypted object-store replication.
- Schema registry and migration history.
- Configuration and infrastructure definitions.
- Key metadata and documented key-recovery procedures.
- Accounting exports and reconciliation evidence.
- Indexer checkpoints and replay manifests.

### 27.2 Recovery objectives

Every system MUST declare an RPO and RTO based on its criticality. Financial ledgers, identity evidence, and canonical event archives require the strictest objectives.

### 27.3 Restore testing

- Backups are not considered valid until restoration is tested.
- Restore tests MUST include checksum validation and reconciliation against canonical chains or providers.
- Disaster recovery MUST support rebuilding projections from canonical events.
- Recovery environments MUST preserve privacy and access controls.
- Key recovery MUST be tested without exposing production secrets.
- An annual full-region failure exercise and more frequent component exercises are required before unrestricted launch.

---

## 28. Data migration and backfill

- Migrations MUST be versioned, repeatable, and reversible where technically possible.
- Financial backfills MUST run through controlled posting or projection pipelines, not direct ad hoc updates.
- Every migration MUST define source, target, mapping, validation, reconciliation, rollback, and ownership.
- Backfills MUST preserve original event time and record backfill time separately.
- Active loans MUST retain original agreement and schema interpretation.
- Large migrations SHOULD use dual-write, shadow-read, or compare-mode before cutover.
- Destructive migrations require backups, approval, and dry-run evidence.

---

## 29. Data security threat controls

| Threat | Required controls |
|---|---|
| SQL injection | Parameterized queries, schema validation, least privilege, WAF telemetry |
| Mass assignment | Explicit command DTOs and allowlists |
| IDOR and authorization bypass | Resource-level policy enforcement |
| Sensitive logging | Structured redaction and log schemas |
| Data exfiltration | Egress controls, DLP, anomaly detection, export approval |
| Ransomware | Immutable backups, segmented credentials, restore testing |
| Insider manipulation | Append-only audit, separation of duties, four-eyes approval |
| Event forgery | Producer authentication, signatures, broker ACLs, schema registry |
| Replay | Unique IDs, inbox deduplication, nonces, expiry |
| Projection poisoning | Source validation, provenance, deterministic rebuild |
| Chain reorg misuse | Finality gating and orphan handling |
| Provider spoofing | Signed callbacks, mTLS, allowlisted endpoints |
| Bridge message forgery | Source and destination binding, proof verification |
| Model-input poisoning | Data provenance, feature validation, model monitoring |
| Backup theft | Encryption, separate key custody, access auditing |

---

## 30. Service ownership boundaries

| Service | Owns | Explicitly does not own |
|---|---|---|
| Identity Service | Credentials, consent, verification references | Cannot activate loans or post debt |
| Marketplace Service | Tenders, offers, discovery, negotiation metadata | Cannot mutate canonical active loan terms |
| Underwriting Service | Credit applications, decisions, model provenance | Cannot disburse funds |
| Loan Service | Off-chain loan orchestration and projections | Cannot override home-chain canonical state |
| Payment Orchestrator | Payment intents and provider workflows | Cannot finalize without authenticated evidence |
| Accounting Service | Journals, balances, reconciliation | Cannot alter contract state directly |
| Collateral Monitor | Valuation and health projections | Cannot seize collateral outside approved execution |
| Cross-Chain Coordinator | Messages and remote workflow state | Cannot redefine loan economics |
| UFT Service | Supply and staking projections | Cannot mint canonical UFT |
| Governance Service | Proposal and vote projections | Cannot bypass on-chain governor and timelock |
| Notification Service | User communications | Cannot originate financial facts |
| Analytics Service | Aggregated and derived insight | Cannot authorize transactions |

---

## 31. Reference relational model

The following tables are logical references, not a mandate for one physical database.

### `core.parties`

- `party_id PK`
- `party_type`
- `status`
- `created_at`
- `privacy_class`

### `core.accounts`

- `account_id PK`
- `party_id FK`
- `account_type`
- `authority_class`
- `external_ref`
- `status`

### `marketplace.tenders`

- `tender_id PK`
- `borrower_party_id`
- `current_version`
- `status`
- `expires_at`
- `metadata_hash`

### `marketplace.tender_versions`

- `tender_id`
- `version`
- `terms_json`
- `schema_version`
- `created_at`
- `signature_ref`

### `marketplace.offers`

- `offer_id PK`
- `tender_id`
- `maker_party_id`
- `nonce`
- `terms_hash`
- `expires_at`
- `status`

### `loans.loans`

- `loan_id PK`
- `home_chain_id`
- `contract_address`
- `agreement_hash`
- `protocol_version`
- `created_at`

### `loans.state_projection`

- `loan_id PK`
- `origination_state`
- `servicing_state`
- `collateral_state`
- `payment_state`
- `version`
- `as_of_event_id`

### `funding.commitments`

- `commitment_id PK`
- `loan_id`
- `lender_party_id`
- `amount`
- `asset_id`
- `tranche_id`
- `status`

### `funding.positions`

- `position_id PK`
- `loan_id`
- `owner_account_id`
- `share_units`
- `seniority`
- `encumbrance_status`

### `collateral.positions`

- `collateral_position_id PK`
- `loan_id`
- `asset_id`
- `quantity`
- `custody_authority`
- `lien_status`

### `payments.payments`

- `payment_id PK`
- `loan_id`
- `payer_account_id`
- `asset_id`
- `amount`
- `payment_method`
- `status`

### `payments.settlements`

- `settlement_id PK`
- `payment_id`
- `provider_id`
- `provider_reference`
- `finality`
- `settled_amount`

### `accounting.journals`

- `journal_entry_id PK`
- `source_event_id`
- `posting_status`
- `effective_at`
- `posted_at`
- `reversal_of`

### `accounting.lines`

- `journal_entry_id`
- `line_number`
- `account_code`
- `debit`
- `credit`
- `asset_id`
- `dimensions_json`

### `crosschain.messages`

- `message_id PK`
- `source_chain`
- `destination_chain`
- `nonce`
- `payload_hash`
- `status`

### `audit.records`

- `audit_id PK`
- `actor_id`
- `action`
- `resource_type`
- `resource_id`
- `occurred_at`
- `integrity_hash`

### `events.archive`

- `event_id PK`
- `event_type`
- `schema_version`
- `aggregate_id`
- `aggregate_version`
- `payload`
- `source_ref`
- `finality`

### `operations.outbox`

- `outbox_id PK`
- `event_id`
- `payload`
- `published_at`
- `attempt_count`

### `operations.inbox`

- `consumer_name`
- `event_id`
- `processed_at`
- `result_hash`

---

## 32. Event-to-projection examples

| Event | Projection | Effect |
|---|---|---|
| LoanActivated | LoanPortfolioProjection | Insert active loan, immutable terms hash, maturity, initial balances |
| PaymentFinalized | PaymentStatusProjection | Mark settlement final and eligible for allocation |
| PaymentAllocated | LoanPortfolioProjection | Reduce principal and interest according to waterfall |
| PaymentReversed | Payment and Loan projections | Restore affected balances and mark dispute or delinquency |
| CollateralLocked | CollateralHealthProjection | Add controlled collateral and compute health |
| OracleObservationAccepted | CollateralHealthProjection | Recompute valuation using approved observation |
| LiquidationCompleted | Loan and accounting projections | Apply proceeds, creditor distribution, and borrower surplus |
| PositionTransferred | PortfolioProjection | Move future lender rights to buyer |
| UFTBurned | UFTSupplyProjection | Reduce total supply and reconcile burner balance |
| MessageReorgedOut | CrossChainProjection | Mark source event orphaned and suspend dependent action |

---

## 33. Testing requirements

- Schema compatibility tests for every producer and consumer.
- Golden-event replay tests for every critical projection.
- Property tests for idempotency and aggregate ordering.
- Reorganization simulations across supported chains.
- Duplicate and out-of-order provider callback tests.
- Cross-chain timeout and retry tests.
- Accounting posting and reversal tests.
- Backup restoration and full projection rebuild tests.
- Privacy tests preventing restricted fields from entering logs, search, analytics, or public events.
- Authorization tests at row, aggregate, and field level.
- High-volume event replay and lag testing.
- Dead-letter recovery and poison-event handling.
- Data migration and rollback rehearsals.
- Reconciliation fault injection.
- Key-loss and key-rotation recovery tests.

---

## 34. Launch-blocking data failures

Unified MUST NOT enter unrestricted production if any known path allows:
- A derived database to release collateral or alter debt without canonical authorization.
- Duplicate commands, callbacks, messages, or events to create duplicate economic effects.
- Wrapped UFT or remote assets to exceed canonical backing.
- Posted accounting journals to be edited or deleted.
- Sensitive identity or financial data to be written publicly without explicit lawful purpose.
- Chain reorganizations to leave projections or accounting silently inconsistent.
- Provider reversals to fail to restore debt and accounting state.
- Reconciliation differences to be hidden, ignored, or booked as revenue without authority.
- Active-loan schema interpretation to change through an application deployment.
- Backups to exist without a verified restoration path.
- Cross-chain timeout recovery to unlock both source and destination value.
- One lender position, payment, collateral claim, or governance vote to be counted twice.
- Critical events to lack stable schema ownership or replay support.
- Privileged users to access or export restricted data without audit.

---

## 35. Implementation sequence

1. Create the canonical schema registry and identifier package.
2. Implement command and event envelope libraries.
3. Implement transactional outbox and consumer inbox patterns.
4. Build the chain-event archive with reorg-aware ingestion.
5. Build provider callback gateways with raw-payload retention and idempotency.
6. Implement the accounting posting contract and reconciliation framework.
7. Create core operational schemas and migrations.
8. Build deterministic loan, collateral, payment, UFT, governance, and cross-chain projections.
9. Implement privacy classification and field-level redaction controls.
10. Implement audit logging and privileged-access workflows.
11. Implement backup, restore, replay, and projection-rebuild tooling.
12. Run adversarial data, reorg, provider-reversal, and disaster-recovery exercises.

---

## 36. Required implementation artifacts

- `schemas/commands/` — versioned command schemas.
- `schemas/events/` — versioned event schemas.
- `schemas/provider/` — normalized provider callback schemas.
- `packages/identifiers/` — stable ID types and validation.
- `packages/event-envelope/` — serialization, hashing, and validation.
- `packages/idempotency/` — command, callback, and consumer deduplication.
- `services/chain-indexer/` — reorg-aware multi-chain ingestion.
- `services/event-archive/` — immutable event storage.
- `services/accounting/` — journal posting and reconciliation.
- `services/projection-builder/` — deterministic read models.
- `services/privacy-control/` — classification, redaction, retention, and access policy.
- `services/audit/` — tamper-evident audit records.
- `infrastructure/backups/` — backup and restore automation.
- `tests/replay/` — canonical event replay suites.
- `tests/reconciliation/` — source-to-ledger and source-to-projection tests.

---

## 37. Architecture decision records required

- ADR-DATA-001: Canonical authority model.
- ADR-DATA-002: Relational database and transaction boundaries.
- ADR-DATA-003: Event broker and delivery semantics.
- ADR-DATA-004: Event archive format and retention.
- ADR-DATA-005: Chain finality and reorganization policy.
- ADR-DATA-006: Provider callback authentication.
- ADR-DATA-007: Schema registry and compatibility mode.
- ADR-DATA-008: Identity and financial data encryption.
- ADR-DATA-009: Analytics de-identification.
- ADR-DATA-010: Backup and regional recovery architecture.
- ADR-DATA-011: Search indexing privacy model.
- ADR-DATA-012: Cross-chain message persistence and replay protection.
- ADR-DATA-013: Accounting integration and posting boundaries.
- ADR-DATA-014: Audit-log immutability.
- ADR-DATA-015: Data retention and deletion framework.

---

## 38. Acceptance criteria

This specification is accepted when:
- Every canonical domain entity has an authority class, privacy class, and storage owner.
- Every material command and event has a registered schema and owner.
- Every on-chain event can be ingested, finalized, orphaned, and replayed safely.
- Every provider callback can be authenticated, deduplicated, normalized, and reconciled.
- Every critical projection can be rebuilt from retained canonical events.
- Every accounting posting has an authoritative source reference and idempotency key.
- Every restricted field has encryption, access, retention, and audit policy.
- Every cross-chain workflow has timeout, retry, compensation, and recovery data.
- Backup restoration and full event replay are demonstrated in a clean environment.
- Launch-blocking data invariants pass automated tests and formal review.

---

## 39. Closing rule

Unified shall never confuse convenience with authority.

A cache may be fast, an index may be searchable, an analytics model may be insightful, and an application database may be operationally useful. None of them may create, destroy, transfer, or rewrite financial rights unless the Constitution and the owning canonical authority explicitly permit it.

This specification is subordinate to the Unified Constitution and must be implemented consistently with the Universal Loan Model, Financial Accounting Specification, UFT Tokenomics, Threat Model, Formal Invariants, and Smart Contract Interface Specification.
