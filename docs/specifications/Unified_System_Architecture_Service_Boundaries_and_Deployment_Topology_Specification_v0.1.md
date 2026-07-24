# Unified System Architecture, Service Boundaries, and Deployment Topology Specification v0.1

**Status:** Foundational Architecture Specification  
**Version:** 0.1  
**Applies to:** Unified Protocol, UFT, lending, collateral, payments, accounting, governance, identity, underwriting, bridges, marketplaces, social communication, analytics, operations, and all production environments.

---

## 1. Purpose

This specification defines the complete runtime architecture of Unified.

It converts the Unified Constitution, Domain Model, Universal Loan Model, Financial Accounting Specification, UFT Tokenomics, Threat Model, Formal Verification Specification, Smart Contract Interface Specification, and On-Chain/Off-Chain Data Architecture into deployable service boundaries and infrastructure topology.

It defines:

- The system context and trust boundaries.
- The trusted protocol kernel.
- Application service ownership.
- Modular-monolith and service-extraction strategy.
- Network and security zones.
- Blockchain, payment, bridge, identity, and underwriting integration boundaries.
- Databases, event infrastructure, caches, object storage, and search systems.
- Key management, signing, and privileged execution.
- Availability, scaling, observability, backup, and disaster-recovery requirements.
- Regional and multi-environment deployment patterns.
- Operational ownership and service-level objectives.
- Launch-blocking architectural conditions.

The architecture MUST preserve the constitutional properties of user-asset control, immutable active agreements, one canonical authority, explicit finality, funded economic claims, privacy by construction, and auditable recovery.

---

## 2. Normative language

The terms **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative.

A runtime component is conformant only when it satisfies the requirements applicable to its domain, authority class, data classification, security tier, recovery tier, and operational criticality.

---

## 3. Governing hierarchy

Runtime implementations MUST obey the following order of authority:

1. Unified Constitution.
2. Unified Protocol Invariants and Formal Verification Specification.
3. Universal Loan Model and State Machines.
4. Unified Financial Accounting Specification.
5. UFT Tokenomics and Economic Security Specification.
6. Unified Threat Model and Adversarial Security Specification.
7. Unified Domain Model.
8. Unified Smart Contract Interface and Protocol API Specification.
9. Unified On-Chain/Off-Chain Data Architecture and Event Contract Specification.
10. This specification.
11. Service-level implementation documentation.

A lower-level deployment decision MUST NOT weaken a higher-order rule.

---

# Part I — Architectural Doctrine

## 4. Core architectural principles

### A1 — Small trusted kernel

The trusted protocol kernel MUST contain only the minimum logic required to establish canonical loan identity, agreement integrity, policy binding, asset custody, debt state, lender rights, settlement authorization, UFT supply, and governance execution.

### A2 — Modular domains

Application capabilities MUST be organized around domain ownership rather than technical layers alone.

### A3 — Replaceable integrations

Oracles, bridges, banks, card processors, KYC providers, model providers, exchange routes, custodians, and notification providers MUST be isolated behind versioned adapters.

### A4 — One canonical authority

Every material fact MUST have one declared canonical authority. Services may project or reconcile authority but MUST NOT manufacture it.

### A5 — Explicit finality

Observed, pending, provisional, confirmed, final, reversed, disputed, and failed states MUST remain distinguishable end to end.

### A6 — Zero trust

No network location, service identity, employee device, cloud account, or workload identity is trusted merely because it is internal.

### A7 — Least privilege

Every service, human, key, role, and workload MUST receive only the minimum permissions required.

### A8 — Failure containment

A failure in one adapter, region, chain, provider, or projection MUST not automatically compromise unrelated assets or domains.

### A9 — Idempotent coordination

Every externally retried or asynchronously delivered operation MUST be idempotent.

### A10 — Event-driven evidence

Material state changes MUST emit durable evidence sufficient for indexing, accounting, reconciliation, monitoring, and recovery.

### A11 — Rebuildable projections

Read models, caches, indexes, and analytics stores MUST be rebuildable from canonical events and snapshots.

### A12 — Operational transparency

Privileged actions, degraded states, unresolved reconciliation differences, and safety-mode activation MUST be observable and auditable.

### A13 — Secure-by-default deployment

Production environments MUST deny public access, cross-service access, and administrative access unless explicitly allowed.

### A14 — Progressive decomposition

Unified MAY begin with a modular monolith for selected off-chain domains, but internal boundaries MUST match the eventual service boundaries defined here.

### A15 — No premature distributed transactions

Cross-domain workflows MUST use explicit orchestration, durable events, compensation, and reconciliation rather than hidden distributed database transactions.

---

## 5. Architecture objectives

Unified shall optimize for:

- Correctness before throughput.
- Solvency before incentives.
- Recoverability before convenience.
- Explicit authority before data duplication.
- Isolation before unrestricted composability.
- Determinism before opaque automation.
- Privacy before data accumulation.
- Operational simplicity within each domain.
- Independent scalability where justified.
- Continuous verification of constitutional invariants.

---

## 6. Architecture anti-goals

Unified MUST NOT become:

- A single application database pretending to be the financial source of truth.
- A network of microservices with unclear ownership.
- A bridge-dependent protocol without canonical recovery.
- A payment platform that treats provider callbacks as final without reconciliation.
- A governance system with unrestricted production administration.
- A data lake containing unnecessary raw identity and financial information.
- A collection of independently designed loan products with incompatible accounting.
- A frontend-driven protocol where displayed state can override canonical state.
- A deployment where one compromised cloud role controls contracts, treasury, databases, and customer data.

---

# Part II — System Context

## 7. Top-level system context

```text
Users, Wallets, Institutions, Operators
                  │
                  ▼
       Edge Security and Access Plane
                  │
                  ▼
        Unified Experience Applications
                  │
                  ▼
       API and Command Control Plane
                  │
   ┌──────────────┼────────────────┐
   ▼              ▼                ▼
Marketplace   Financial Core   Trust Services
and Social    and Servicing    Identity/Credit
   │              │                │
   └──────────────┼────────────────┘
                  ▼
       Event, Workflow, and Ledger Plane
                  │
      ┌───────────┼──────────────┐
      ▼           ▼              ▼
Home Chain   Satellite Chains  External Providers
Contracts    and Bridges       Banks/Cards/KYC
      │           │              │
      └───────────┼──────────────┘
                  ▼
       Reconciliation and Risk Plane
                  │
                  ▼
        Governance and Operations Plane
```

---

## 8. External actors

| Actor | Primary interactions | Trust posture |
|---|---|---|
| Borrower | Tender, offer acceptance, collateral, repayment, refinancing | Untrusted user; authenticated commands |
| Lender | Offers, commitments, positions, claims, governance | Untrusted user; authenticated commands |
| Liquidity provider | Pools, staking, gauges, claims | Untrusted user; protocol-enforced limits |
| Governance participant | Lock, delegate, propose, vote | Token-based authority; snapshot constrained |
| Institutional partner | Funding, custody, fiat settlement, reporting | Contracted but not implicitly trusted |
| KYC/identity provider | Identity attestations and revocations | Approved external authority; continuously verified |
| Credit-data provider | Financial and behavioral data | External evidence source; consent and provenance required |
| Underwriting model provider | Scores or decisions | Bounded adapter; no direct asset authority |
| Bank/payment provider | Fiat settlement | Regulated provider authority; provisional until reconciled |
| Card processor | Authorizations, captures, chargebacks | Reversible provider authority |
| Oracle provider | Prices and market observations | External evidence; aggregation and staleness checks |
| Bridge/messaging provider | Cross-chain messages | High-risk adapter; limited authority and exposure |
| Auditor | Evidence review and verification | Read-only access by default |
| Protocol operator | Runtime administration | Privileged but strongly segmented and audited |
| Emergency council | Temporary containment | Narrow, time-bound, non-confiscatory authority |

---

# Part III — Logical Architecture

## 9. Architectural planes

Unified is divided into the following logical planes.

### 9.1 Experience plane

- Public web application.
- Borrower application.
- Lender application.
- Institutional portal.
- Governance application.
- Operations console.
- Mobile applications.
- Developer portal and SDK documentation.

The experience plane MUST NOT possess direct database credentials, treasury keys, bridge keys, or unrestricted contract administration.

### 9.2 Edge and access plane

- CDN.
- DDoS protection.
- Web application firewall.
- Bot and abuse controls.
- API gateway.
- Rate limiting.
- Session and token validation.
- Device and risk signals.
- Regional routing.

### 9.3 Application-domain plane

- Accounts and authorization.
- Identity and credentials.
- Marketplace and tenders.
- Offers and negotiation.
- Underwriting and credit.
- Loan origination.
- Funding and syndication.
- Servicing and schedules.
- Collateral and liquidation coordination.
- Payments and settlement.
- Accounting.
- Refinancing and restructuring.
- Lender positions and secondary markets.
- UFT economics.
- Governance.
- Cross-chain coordination.
- Insurance and recovery.
- Social communication and notifications.

### 9.4 Protocol plane

- Home-chain contracts.
- Satellite-chain contracts.
- Policy modules.
- Custody vaults.
- UFT contracts.
- Governance and timelock contracts.
- Cross-chain adapters.
- Oracle routers.

### 9.5 Data and event plane

- Operational relational stores.
- Durable event bus.
- Transactional outboxes and inboxes.
- Append-only event archive.
- Accounting ledger.
- Search indexes.
- Analytics warehouse.
- Encrypted object storage.
- Cache layer.
- Reconciliation stores.

### 9.6 Trust and security plane

- Identity provider.
- Workload identity.
- Policy enforcement.
- Key-management services.
- Hardware security modules.
- Secrets management.
- Certificate authority.
- Security monitoring.
- Vulnerability and artifact scanning.

### 9.7 Operations and governance plane

- Deployment orchestration.
- Configuration management.
- Observability.
- Incident management.
- Feature and safety controls.
- Governance execution monitoring.
- Treasury operations.
- Reconciliation operations.
- Audit evidence collection.

---

# Part IV — Service Boundary Model

## 10. Service-boundary criteria

A domain SHOULD become an independently deployed service when one or more of the following are true:

- It owns a distinct canonical off-chain aggregate.
- It requires a distinct security or regulatory boundary.
- It needs independent scaling.
- It has a different availability or recovery objective.
- It integrates with high-risk external providers.
- It requires a specialized data store.
- It must deploy independently to contain risk.
- It has a separate operational team and clear API contract.

A domain SHOULD remain a module when separation would add distributed coordination without meaningful security, scale, or ownership benefit.

---

## 11. Initial modular-monolith strategy

Unified MAY begin selected off-chain capabilities as a modular monolith named the **Unified Core Application**, provided that:

- Every domain has a private internal package boundary.
- No domain accesses another domain’s tables directly.
- Cross-domain calls pass through declared application interfaces.
- Every domain owns its migrations.
- Events are emitted through an internal outbox from the beginning.
- Domain commands carry idempotency and expected-version data.
- Extraction tests verify that a module can be separated without semantic changes.
- Security-sensitive provider adapters remain isolated even during the modular-monolith phase.

Recommended modules inside the first Unified Core Application:

```text
accounts
marketplace
offers
loan-origination
loan-servicing
funding
positions
collateral-coordination
refinancing
notifications
reputation
```

The following SHOULD be independent from the beginning:

```text
blockchain-indexer
accounting-ledger
payment-orchestrator
identity-vault
underwriting-engine
cross-chain-coordinator
key-signing-service
reconciliation-service
security-monitoring
```

---

## 12. Canonical service catalogue

### 12.1 Edge Gateway

**Responsibilities**

- Terminate public TLS.
- Apply rate and abuse controls.
- Validate request size and schema.
- Route traffic to public APIs.
- Propagate correlation identifiers.
- Enforce regional and product availability.

**Must not**

- Hold financial keys.
- Finalize payments.
- alter loan states.
- query restricted identity databases directly.

**Data**

- Minimal operational logs.
- No sensitive payload retention by default.

---

### 12.2 Authentication and Account Service

**Owns**

- Application accounts.
- Wallet links.
- Session state.
- Delegated application permissions.
- Device and recovery metadata.

**Does not own**

- Blockchain keys.
- KYC source documents.
- Credit decisions.
- Loan economic terms.

**Interfaces**

- Authenticate wallet challenge.
- Issue and revoke session.
- Link or unlink approved account factor.
- Resolve actor authorization context.

---

### 12.3 Identity Credential Service

**Owns**

- Identity attestation metadata.
- Credential lifecycle.
- Revocation state.
- Verification-provider references.
- Consent and purpose records.

**Restricted subcomponent: Identity Vault**

The Identity Vault stores raw identity evidence only when legally and operationally required. It MUST be deployed in a restricted data zone with separate encryption keys and access policy.

**Must not**

- Expose raw identity data to general services.
- Directly authorize asset movement.
- Write sensitive identity data to public chains.

---

### 12.4 Marketplace Service

**Owns**

- Tender drafts and off-chain metadata.
- Tender publication workflow.
- Search visibility.
- Marketplace moderation state.
- Tender expiry and closure projections.

**Canonical dependencies**

- On-chain tender registry where applicable.
- Signed tender records.
- Identity and eligibility claims.

---

### 12.5 Offer and Negotiation Service

**Owns**

- Signed offers and counteroffers.
- Nonce and expiration tracking.
- Negotiation threads.
- Offer-consumption projection.
- Disclosure acknowledgements.

**Must preserve**

- Signature domain binding.
- One-time consumption.
- Version history.
- Private communication boundaries.

---

### 12.6 Messaging Service

**Owns**

- Encrypted message envelopes.
- Thread membership.
- Delivery and read state.
- Abuse and moderation evidence.

**Must not**

- Interpret free-text chat as a binding financial agreement.
- Store plaintext private messages unless expressly required and authorized.

---

### 12.7 Underwriting Orchestrator

**Owns**

- Credit application workflow.
- Data-source consent.
- Feature requests.
- Policy execution references.
- Model invocation records.
- Decision explanations.
- Human review workflow.

**Does not own**

- Raw identity data outside authorized views.
- Canonical loan activation.
- User funds.

**Isolation**

Model runtimes SHOULD execute in a separate compute boundary without unrestricted production database access.

---

### 12.8 Credit Decision Registry Service

**Owns**

- Signed credit decisions.
- Decision versioning.
- Exposure limits.
- Expiration and revocation.
- Model and policy provenance.

The registry MUST make historical decisions immutable and issue corrections as new versions.

---

### 12.9 Loan Origination Service

**Owns**

- Origination workflow coordination.
- Activation readiness checks.
- Command correlation.
- Compensation and timeout state.
- Contract transaction preparation.

**Canonical authority**

- Active loan terms and activation remain on-chain.

**Must not**

- Directly mark a loan active in an application database without canonical evidence.

---

### 12.10 Funding and Syndication Service

**Owns**

- Funding-round workflow.
- Commitment projections.
- Syndicate configuration.
- Tranche allocations.
- Funding deadline coordination.

**Canonical authority**

- Accepted commitments and lender rights must reconcile to protocol contracts and accounting.

---

### 12.11 Loan Servicing Service

**Owns**

- Servicing schedules and projections.
- Due-date monitoring.
- Delinquency workflow.
- Notices and cure windows.
- Repayment instructions.
- Restructuring readiness.

**Does not own**

- Final debt state independently of the canonical loan and accounting authorities.

---

### 12.12 Interest and Schedule Engine

**Owns**

- Deterministic interest calculations.
- Schedule generation.
- Accrual projections.
- Rate-index observations.
- Rounding records.

Every result MUST identify policy version, rate source, input timestamps, and calculation precision.

---

### 12.13 Collateral Coordination Service

**Owns**

- Collateral onboarding workflow.
- Custody verification coordination.
- Health projections.
- Margin-call workflow.
- Liquidation eligibility projections.

**Canonical authority**

- Actual custody and lien state remain with approved vaults or regulated custodians.

---

### 12.14 Oracle Aggregation Service

**Owns**

- Provider observation ingestion.
- Normalization.
- Source health.
- Deviation analysis.
- Staleness monitoring.
- Signed off-chain observations where required.

**Must not**

- Override on-chain oracle policy.
- produce a price from a single unapproved venue when policy requires aggregation.

---

### 12.15 Liquidation Coordinator

**Owns**

- Liquidation workflow orchestration.
- Auction coordination.
- Route simulation.
- Keeper interaction.
- Result reconciliation.

**Canonical authority**

- Eligibility, asset movement, and final distribution remain determined by the loan’s liquidation policy and protocol contracts.

---

### 12.16 Payment Orchestrator

**Owns**

- Payment intents.
- Provider routing.
- Payment state.
- Provider callbacks.
- Refund and reversal coordination.
- Idempotency and evidence.

**Must distinguish**

```text
REQUESTED
AUTHORIZED
PROVISIONAL
FINAL
REVERSED
DISPUTED
FAILED
```

**Security boundary**

Each payment-provider adapter MUST have separate credentials and bounded permissions.

---

### 12.17 Fiat Settlement Adapter Services

One adapter service SHOULD exist per provider or provider class.

Each adapter MUST:

- Authenticate provider callbacks.
- Store raw evidence before normalization.
- Enforce replay protection.
- map provider references to Unified payment IDs.
- expose reconciliation exports.
- avoid direct access to loan-state mutation APIs.

---

### 12.18 Card Settlement Adapter Services

Card adapters MUST additionally support:

- Authorization and capture separation.
- Chargebacks.
- Re-presentment.
- Provider reserves.
- fraud signals.
- settlement batches.

Card credentials MUST remain with a compliant card provider; Unified services MUST NOT store raw card secrets.

---

### 12.19 Accounting Ledger Service

**Owns**

- Chart of accounts.
- Journal intents.
- Posted journals.
- Reversals.
- Subledgers.
- Balance views.
- Period controls.
- Accounting evidence.

**Properties**

- Double-entry.
- Append-only posted history.
- Idempotent posting.
- Explicit provisional and final accounts.
- Independent reconciliation.

The ledger MUST be deployed as an independent high-integrity service from the beginning.

---

### 12.20 Reconciliation Service

**Owns**

- Reconciliation rules.
- Comparison runs.
- Differences.
- materiality classification.
- investigation workflow.
- resolution evidence.

It reconciles chains, providers, vaults, banks, cards, UFT supply, bridge backing, staking shares, lender positions, collateral, treasury, and accounting balances.

---

### 12.21 Position and Secondary Market Service

**Owns**

- Position listings.
- Buyer eligibility workflow.
- Transfer quotes.
- Settlement coordination.
- Accrued-interest allocation projections.

**Canonical authority**

- Position ownership and cash-flow rights remain on-chain or in the approved regulated ledger for the product.

---

### 12.22 Refinancing Coordinator

**Owns**

- Payoff quote workflow.
- New-funding coordination.
- Existing lien release.
- Collateral reassignment.
- New-loan activation coordination.
- Compensation and recovery.

It MUST prevent two active senior claims over the same collateral.

---

### 12.23 Insurance and Recovery Service

**Owns**

- Coverage records.
- Claim workflow.
- Loss-waterfall coordination.
- Guarantor commitments.
- Recovery cases.
- reserve utilization projections.

**Canonical authority**

- Asset movement remains with insurance contracts, treasury mandates, regulated providers, and the accounting ledger.

---

### 12.24 UFT Economic Service

**Owns**

- Supply projections.
- Vesting projections.
- Reward epochs.
- fee-routing projections.
- burn records.
- staking analytics.
- liquidity incentive coordination.
- bridge-exposure projections.

**Must not**

- Create a minting path.
- represent unfunded rewards as earned liabilities.

---

### 12.25 Governance Service

**Owns**

- Proposal metadata.
- discussion.
- simulation.
- voting projections.
- timelock monitoring.
- execution evidence.

Canonical voting and execution remain with governance contracts.

---

### 12.26 Cross-Chain Coordinator

**Owns**

- Message lifecycle.
- adapter selection.
- source finality.
- proof collection.
- destination execution.
- acknowledgement.
- timeout and recovery coordination.

It MUST have no unilateral ability to create unbacked UFT or duplicate loan rights.

---

### 12.27 Blockchain Transaction Service

**Owns**

- Transaction construction.
- simulation.
- fee estimation.
- nonce coordination for service-controlled accounts.
- broadcast.
- replacement strategy.
- receipt tracking.

It MUST be separated from the signing service.

---

### 12.28 Signing Service

**Owns**

- Controlled signing operations.
- policy checks.
- transaction authorization evidence.
- key versioning.

**Deployment**

- HSM or equivalent hardware-backed boundary.
- No general internet access.
- No unrestricted database access.
- dual or threshold authorization for high-impact operations.

---

### 12.29 Blockchain Indexer

**Owns**

- Raw block and log ingestion.
- confirmation tracking.
- reorganization handling.
- decoded protocol events.
- chain checkpoints.

The indexer MUST retain block hash, transaction hash, log index, chain ID, contract address, finality, and decoder version.

---

### 12.30 Search Projection Service

**Owns**

- Tender search.
- portfolio search.
- governance search.
- public protocol exploration.

Search is derived and MUST disclose staleness and finality where material.

---

### 12.31 Notification Service

**Owns**

- Notification preferences.
- templates.
- delivery attempts.
- provider routing.
- user-visible alert history.

Financial state MUST NOT depend on notification delivery.

---

### 12.32 Analytics and Risk Warehouse

**Owns**

- Historical analytical datasets.
- risk aggregates.
- model monitoring.
- liquidity and exposure analysis.
- governance and treasury reporting.

It is strictly derived and MUST NOT be used as the sole authority for asset movement.

---

### 12.33 Operations Control Service

**Owns**

- Approved operational workflows.
- maintenance windows.
- incident controls.
- feature and safety flags.
- evidence collection.

It MUST NOT provide unrestricted direct database editing or arbitrary contract calls.

---

# Part V — Inter-Service Communication

## 13. Communication classes

### 13.1 Synchronous query

Used when:

- The caller requires an immediate read.
- The result is non-authoritative or derived.
- Failure can be safely retried.

### 13.2 Synchronous command

Used sparingly when:

- A domain command requires immediate acceptance or rejection.
- The receiving service owns the aggregate.
- Idempotency and expected-version checks are enforced.

Acceptance MUST NOT be confused with final economic completion.

### 13.3 Asynchronous domain event

Used to communicate completed domain facts.

### 13.4 Workflow event

Used for multi-step coordination with timeouts and compensation.

### 13.5 Canonical evidence event

Used for chain, provider, accounting, or governance authority updates.

---

## 14. Communication rules

- Every command MUST carry a command ID and idempotency key.
- Every event MUST carry an event ID, schema version, correlation ID, causation ID, authority class, and finality.
- Services MUST NOT share mutable database tables.
- Event consumers MUST assume at-least-once delivery.
- Consumers MUST use durable inbox deduplication.
- Producers MUST use transactional outboxes.
- Cross-domain workflows MUST define compensation and unresolved states.
- Events containing restricted data MUST use protected channels and field-level encryption.
- Public event topics MUST NOT contain restricted identity or financial data.

---

## 15. Workflow orchestration

Complex workflows SHOULD use durable orchestrators.

Required orchestrators include:

- Loan activation.
- Syndicated funding.
- Fiat disbursement.
- Card repayment finalization.
- Cross-chain collateral locking.
- Refinancing.
- Liquidation auction.
- Insurance claim.
- UFT bridge transfer.
- Governance execution monitoring.

Each orchestrator MUST record:

```text
workflow_id
workflow_type
aggregate_id
current_step
state
started_at
step_deadlines
completed_steps
pending_compensations
correlation_id
policy_version
last_error
recovery_owner
```

---

# Part VI — Runtime and Deployment Topology

## 16. Environment model

Unified MUST maintain isolated environments:

```text
local
development
integration
security-test
staging
testnet
pre-production
production
recovery
```

Production credentials, keys, personal data, payment-provider secrets, and treasury authority MUST NOT be copied into non-production environments.

Synthetic or irreversibly masked data SHOULD be used outside production.

---

## 17. Production regional topology

Recommended production pattern:

```text
Global Edge
   │
   ├── Region A — Active
   │     ├── Stateless application workloads
   │     ├── Domain databases
   │     ├── Event brokers
   │     ├── Cache and search
   │     └── Observability collectors
   │
   ├── Region B — Active or warm standby
   │     ├── Stateless application workloads
   │     ├── replicated data services
   │     ├── event recovery capacity
   │     └── independent provider connectivity
   │
   └── Recovery Region
         ├── immutable backups
         ├── restore infrastructure
         ├── emergency control plane
         └── isolated evidence archive
```

Stateful active-active operation MAY be used only where conflict resolution and canonical ownership are formally defined.

Financial command ownership SHOULD normally be single-writer per aggregate or partition.

---

## 18. Availability zones

Each primary production region SHOULD span at least three independent availability zones for:

- Application workloads.
- Event brokers.
- relational databases.
- caches where required.
- observability collectors.

Quorum-based systems MUST be configured so loss of one zone does not destroy quorum.

---

## 19. Network zones

### Zone 0 — Public edge

Contains:

- CDN.
- WAF.
- DDoS protection.
- public load balancers.

No databases or signing components are permitted.

### Zone 1 — Application ingress

Contains:

- API gateway.
- session validation.
- public API services.

Inbound access is allowed only from the public edge or approved private channels.

### Zone 2 — Application services

Contains:

- Domain services.
- workflow orchestrators.
- projections.

East-west traffic requires workload identity and policy authorization.

### Zone 3 — Data services

Contains:

- Relational databases.
- event brokers.
- caches.
- search.
- object-storage private endpoints.

No direct public access.

### Zone 4 — Restricted identity and payment data

Contains:

- Identity Vault.
- restricted financial records.
- provider callback evidence.
- reconciliation evidence.

Requires separate encryption keys, policies, and audit.

### Zone 5 — Signing and key custody

Contains:

- HSM-backed signing service.
- root key material.
- certificate authority components.

No public ingress and no general application access.

### Zone 6 — Operations and governance

Contains:

- deployment control.
- security administration.
- governance monitoring.
- treasury workflows.
- incident controls.

Human access requires strong identity, managed device, just-in-time authorization, and recording.

### Zone 7 — Recovery and evidence

Contains:

- immutable backups.
- audit archives.
- disaster-recovery tooling.
- offline recovery material.

Production services cannot freely modify this zone.

---

## 20. Service-mesh and workload identity

Production workloads SHOULD use cryptographic workload identities.

Requirements:

- Mutual TLS for service-to-service traffic.
- Short-lived certificates.
- Automated certificate rotation.
- Service-level authorization policies.
- Egress restrictions.
- Request identity propagation.
- Deny-by-default network policy.
- Traffic telemetry without exposing sensitive payloads.

A service mesh MAY be used, but architecture MUST not depend on mesh-specific proprietary behavior for correctness.

---

# Part VII — Blockchain Topology

## 21. Home-chain infrastructure

Unified MUST use multiple independent RPC and node providers for critical reads and writes.

Recommended components:

- Self-operated full nodes where economically and operationally viable.
- Independent managed RPC providers.
- Archival access for investigations and historical reconstruction.
- Dedicated transaction broadcast paths.
- health and divergence monitoring.

No single RPC provider may be the sole authority for transaction finality or protocol health.

---

## 22. Satellite-chain infrastructure

Each supported satellite chain requires:

- Dedicated chain configuration.
- Finality policy.
- RPC quorum.
- indexer deployment.
- bridge adapter deployment.
- exposure limit.
- recovery procedure.
- emergency disablement capability for new activity.

A satellite chain MUST NOT be enabled merely because a bridge supports it.

---

## 23. Transaction submission topology

```text
Domain Command
    │
    ▼
Transaction Builder
    │
    ▼
Simulation and Policy Check
    │
    ▼
Signing Authorization
    │
    ▼
HSM Signing Service
    │
    ▼
Independent Broadcast Endpoints
    │
    ▼
Receipt and Finality Tracking
```

The builder and signer MUST be separate trust boundaries.

---

## 24. Smart-contract deployment authority

Production contract deployment requires:

- Reproducible build artifacts.
- source and bytecode verification.
- formal property reports.
- independent audit approval.
- deployment simulation.
- multi-party authorization.
- exact constructor and initialization manifest.
- storage-layout checks for upgradeable components.
- post-deployment invariant checks.
- public deployment record.

---

# Part VIII — Data Infrastructure

## 25. Relational databases

Recommended ownership pattern:

- One logical database per bounded domain or service.
- Separate schemas MAY be used during the modular-monolith phase.
- No cross-domain writes.
- Foreign references across domains use identifiers, not database foreign keys.
- Every schema change is versioned and reversible where possible.
- Financial and identity databases receive stricter backup and access controls.

---

## 26. Accounting database

The accounting ledger requires:

- Strong transactional consistency.
- append-only posted journals.
- immutable audit metadata.
- deterministic posting references.
- period controls.
- high-integrity backups.
- independent read replicas.
- restricted administrative access.

No generic application administrator may edit posted journals.

---

## 27. Event infrastructure

The durable event platform MUST support:

- Partitioned ordered streams.
- replication across zones.
- durable retention.
- consumer groups.
- replay.
- schema validation.
- dead-letter quarantine.
- encryption in transit and at rest.

Financial events SHOULD partition by canonical aggregate identifier to preserve aggregate ordering.

---

## 28. Event archive

A separate append-only archive MUST retain canonical normalized events and raw source evidence where required.

The archive SHOULD use immutable or object-locked storage for critical evidence.

---

## 29. Cache layer

Caches MAY improve latency but:

- MUST NOT become canonical.
- MUST use bounded time-to-live.
- MUST support explicit invalidation.
- MUST not store unencrypted restricted data.
- MUST degrade safely when unavailable.

---

## 30. Search infrastructure

Search indexes MUST be treated as derived projections.

Search documents SHOULD include:

- Projection version.
- source aggregate version.
- finality.
- indexed time.
- stale indicator.
- privacy class.

---

## 31. Object storage

Encrypted object storage is used for:

- identity documents where required.
- provider evidence.
- signed documents.
- audit artifacts.
- model reports.
- reconciliation files.
- encrypted message attachments.

Every object MUST have classification, retention class, owner, integrity hash, encryption context, and access log.

---

## 32. Analytics warehouse

The analytics warehouse receives de-identified or minimized datasets.

It MUST NOT receive raw secrets, full KYC documents, card credentials, signing material, or unrestricted message content.

Analytical results used for underwriting or risk decisions MUST retain provenance and model version.

---

# Part IX — Key and Secret Architecture

## 33. Key classes

| Key class | Examples | Required custody |
|---|---|---|
| User keys | User wallets | User-controlled or approved smart account |
| Protocol deployment keys | Contract deployment | HSM, multisig or threshold control |
| Governance execution keys | Timelock administration | Contract-governed; no unilateral key |
| Treasury keys | Treasury movement | Multisig/threshold plus policy controls |
| Emergency keys | Temporary containment | Restricted, time-bound, multi-party |
| Service signing keys | Provider requests, attestations | HSM/KMS with workload authorization |
| Encryption keys | Databases, objects, fields | KMS/HSM with separated domains |
| Bridge keys | Adapter operations | Threshold or provider-specific secure custody |
| Certificate keys | Workload identity | Automated short-lived issuance |

---

## 34. Key-management requirements

- Keys MUST have named owners and purposes.
- Key use MUST be logged.
- High-impact key use MUST require policy authorization.
- Keys MUST rotate according to risk class.
- Root keys MUST remain offline or strongly isolated.
- No production private key may be stored in source code, CI variables without protection, developer laptops, or general databases.
- Recovery procedures MUST be tested.
- Compromise of one service credential MUST not expose unrelated domains.

---

## 35. Human privileged access

Human production access requires:

- Strong phishing-resistant authentication.
- Managed device posture.
- just-in-time access.
- approval for high-risk roles.
- short session duration.
- command and session recording where lawful.
- tamper-resistant audit logs.
- periodic access review.

Standing broad administrator access is prohibited.

---

# Part X — Scaling and Capacity

## 36. Scaling principles

- Stateless services scale horizontally.
- Stateful domains scale by ownership partition.
- Financial aggregates preserve single-writer semantics where required.
- Backpressure is preferred to silent data loss.
- Capacity limits must be explicit.
- Safety controls may reduce throughput during market stress.

---

## 37. Suggested partition keys

| Domain | Primary partition key |
|---|---|
| Loans | loan_id |
| Tenders | tender_id or market segment |
| Offers | tender_id |
| Payments | payment_id or provider account |
| Accounting | ledger partition and journal date |
| Cross-chain | source chain and message_id |
| Indexing | chain_id and block range |
| Notifications | user_id |
| UFT staking | account or epoch |
| Governance | proposal_id |

---

## 38. Market-stress mode

Unified MUST support a controlled market-stress mode that can:

- Slow or disable new originations.
- tighten new-loan collateral requirements.
- disable a compromised asset or route for future use.
- reduce bridge exposure.
- pause incentive emissions.
- increase confirmation requirements.
- limit high-risk payment methods.

It MUST NOT:

- Prevent safe repayment.
- seize user assets.
- rewrite active loans.
- conceal insolvency.

---

# Part XI — Availability and Service Objectives

## 39. Criticality tiers

### Tier 0 — Constitutional financial core

- Smart contracts.
- accounting ledger.
- signing service.
- payment finalization.
- UFT supply and bridge backing.
- collateral custody.

### Tier 1 — Critical coordination

- Loan origination.
- servicing.
- transaction service.
- indexers.
- reconciliation.
- cross-chain coordinator.
- oracle aggregation.

### Tier 2 — User operations

- Marketplace.
- offers.
- portfolios.
- governance projections.
- notifications.

### Tier 3 — Analytical and auxiliary

- analytics.
- experimentation.
- non-critical reporting.

---

## 40. Baseline service objectives

Provisional objectives for architecture planning:

| Tier | Availability target | RPO | RTO |
|---|---:|---:|---:|
| Tier 0 | 99.99% where technically applicable | Near-zero to 1 minute | 15–30 minutes |
| Tier 1 | 99.95% | 5 minutes | 1 hour |
| Tier 2 | 99.9% | 15 minutes | 4 hours |
| Tier 3 | 99.5% | 24 hours | 24–48 hours |

These targets are provisional and MUST be validated against cost, regulation, provider dependencies, and launch jurisdiction.

On-chain contract availability is governed by the underlying network and contract safety controls rather than ordinary service uptime.

---

## 41. Graceful degradation

Examples:

- If search fails, direct loan access remains available.
- If notification delivery fails, financial state remains correct.
- If analytics fails, origination continues unless risk limits depend on unavailable required data.
- If one RPC fails, independent endpoints remain.
- If an oracle source fails, aggregation excludes it or enters safe mode.
- If a payment provider fails, new routing pauses while existing evidence remains reconcilable.
- If a bridge fails, new messages stop and recovery begins without affecting local repayment.

---

# Part XII — Observability and Control

## 42. Observability pillars

Unified requires:

- Metrics.
- structured logs.
- distributed traces.
- domain events.
- security events.
- audit events.
- reconciliation differences.
- user-visible status.

---

## 43. Required telemetry dimensions

Every material operation SHOULD include:

```text
service
version
environment
region
aggregate_type
aggregate_id
command_id
event_id
correlation_id
causation_id
actor_type
authority_class
finality
policy_version
chain_id
provider_id
result
latency
```

Sensitive values MUST be redacted or tokenized.

---

## 44. Financial health telemetry

Dashboards and alerts MUST cover:

- Loan activation mismatches.
- payment provisional-to-final aging.
- unsettled provider balances.
- ledger imbalance attempts.
- collateral health distribution.
- liquidation queue depth.
- UFT supply reconciliation.
- wrapped UFT backing.
- staking backing.
- insurance coverage ratios.
- treasury runway.
- bridge exposure.
- unresolved accounting differences.

---

## 45. Security telemetry

Required detections include:

- Privileged role changes.
- unusual signing requests.
- treasury destination changes.
- repeated failed authorization.
- unexpected contract bytecode.
- oracle divergence.
- bridge-message anomalies.
- callback signature failures.
- duplicate payment attempts.
- database export activity.
- secrets access anomalies.
- CI artifact mismatch.

---

## 46. User-visible status

Unified SHOULD expose public or authenticated status for:

- Chain confirmation state.
- payment state.
- provider delays.
- bridge delays.
- governance execution.
- maintenance and incidents.
- collateral health.
- reconciliation holds affecting the user.

User interfaces MUST distinguish delays from final failures.

---

# Part XIII — Deployment and Software Supply Chain

## 47. Build requirements

- Reproducible builds where practical.
- Locked dependencies.
- signed commits or equivalent protected provenance for releases.
- software bill of materials.
- vulnerability scanning.
- secret scanning.
- static analysis.
- container and infrastructure scanning.
- provenance attestations.
- immutable release artifacts.

---

## 48. Deployment pipeline

```text
Source Change
   ↓
Review and Policy Checks
   ↓
Unit, Integration, Invariant, and Security Tests
   ↓
Build and Artifact Signing
   ↓
Staging Deployment
   ↓
Migration and Rollback Validation
   ↓
Production Approval
   ↓
Progressive Deployment
   ↓
Post-Deployment Verification
```

Financially critical deployments require multi-party approval and exact artifact verification.

---

## 49. Progressive delivery

Unified SHOULD use:

- Canary deployment.
- traffic shadowing for non-sensitive requests.
- feature flags for off-chain capabilities.
- bounded rollout by region or user cohort.
- automatic rollback for defined health failures.

Feature flags MUST NOT alter immutable active-loan economics or bypass contract authorization.

---

## 50. Database migration rules

- Expand-and-contract migrations are preferred.
- Migrations MUST preserve old readers during rollout.
- Posted accounting history cannot be rewritten.
- Active agreement schema meaning cannot change silently.
- Every migration requires backup and tested rollback or forward-recovery plan.
- Large migrations require throttling and observability.

---

## 51. Contract upgrade deployment

Upgradeable components require:

- governance proposal.
- timelock.
- storage-layout verification.
- formal invariant rerun.
- audit review proportional to change.
- implementation allowlisting.
- post-upgrade checks.
- rollback or containment plan where technically possible.

Active loan terms remain bound to approved versions unless an authorized migration mechanism was accepted at activation.

---

# Part XIV — Backup, Recovery, and Continuity

## 52. Backup classes

### Class A — Financial and canonical off-chain data

- Accounting ledger.
- payment evidence.
- reconciliation records.
- identity credential state.
- workflow state.

Requires frequent backups, immutable copies, and tested point-in-time recovery.

### Class B — Rebuildable operational state

- Projections.
- search indexes.
- caches.

May be rebuilt from canonical events.

### Class C — Restricted evidence

- Identity documents.
- legal and provider evidence.

Requires encrypted, access-controlled, retention-aware backups.

### Class D — Configuration and infrastructure

- Infrastructure code.
- policies.
- deployment manifests.
- schema definitions.

Requires versioned and independently recoverable storage.

---

## 53. Recovery doctrine

Recovery MUST preserve:

- Canonical authority.
- journal immutability.
- idempotency history.
- event ordering within aggregates.
- privacy controls.
- key separation.
- reconciliation evidence.

A restored database MUST NOT be considered production-ready until reconciled against chains, providers, vaults, and the accounting ledger.

---

## 54. Disaster-recovery workflow

```text
Incident Declared
   ↓
Protect and Freeze Evidence
   ↓
Contain New Risk
   ↓
Select Recovery Point
   ↓
Restore Core Data and Services
   ↓
Replay Canonical Events
   ↓
Reconcile Chains, Providers, and Ledger
   ↓
Validate Invariants
   ↓
Resume in Restricted Mode
   ↓
Return to Normal Operation
```

---

## 55. Recovery testing

Unified MUST test:

- Database point-in-time recovery.
- event-bus replay.
- chain-index reconstruction.
- accounting restoration.
- provider-evidence restoration.
- cross-region failover.
- key-recovery procedures.
- identity-vault recovery.
- loss of one availability zone.
- loss of one cloud region.
- compromise of one provider credential.
- bridge-disablement and message recovery.

Backups do not count as valid until restore tests succeed.

---

# Part XV — Operational Ownership

## 56. Ownership model

Every service MUST have:

- Business owner.
- engineering owner.
- security owner.
- data owner.
- on-call rotation.
- service-level objectives.
- runbook.
- dependency map.
- recovery procedure.
- risk classification.

---

## 57. Separation of duties

At minimum, the following powers SHOULD be separated:

- Code approval and production deployment.
- transaction construction and signing.
- treasury proposal and execution approval.
- payment-provider administration and reconciliation.
- identity-data administration and underwriting.
- accounting posting and accounting review.
- bridge operations and bridge reconciliation.
- emergency action and post-incident review.

---

## 58. Runbook requirements

Each Tier 0 and Tier 1 service requires runbooks for:

- Service outage.
- dependency outage.
- data corruption.
- credential compromise.
- duplicate event.
- backlog growth.
- reconciliation mismatch.
- provider failure.
- degraded chain or RPC.
- security alert.
- rollback.
- regional failover.

---

# Part XVI — Reference Deployment Topology

## 59. Reference topology

```text
Internet and Mobile Networks
          │
          ▼
Global CDN / DDoS / WAF
          │
          ▼
Regional Public Load Balancers
          │
          ▼
API Gateway and Session Validation
          │
          ▼
Application Service Cluster
          │
 ┌────────┼─────────┬───────────────┐
 ▼        ▼         ▼               ▼
Core    Identity  Payments       Governance
Apps    Boundary  Boundary       and Ops
 │        │         │               │
 └────────┼─────────┼───────────────┘
          ▼
Private Event and Workflow Platform
          │
 ┌────────┼──────────────┬───────────┐
 ▼        ▼              ▼           ▼
Domain  Accounting    Indexers   Reconciliation
DBs     Ledger DB     and RPCs      Engine
 │        │              │           │
 └────────┼──────────────┼───────────┘
          ▼              ▼
Encrypted Object     Home/Satellite
and Event Archive       Chains
          │              │
          └──────┬───────┘
                 ▼
         HSM Signing Boundary
                 │
                 ▼
      Governance / Treasury / Providers
```

---

## 60. Provider connectivity

External provider traffic SHOULD use:

- Dedicated outbound egress.
- IP restrictions where supported.
- mutual TLS where supported.
- signed requests and callbacks.
- provider-specific credentials.
- rate and exposure limits.
- independent circuit breakers.
- health and reconciliation monitoring.

Provider credentials MUST NOT be shared across environments or providers.

---

# Part XVII — Extraction Roadmap

## 61. Stage 0 — Architecture simulation

Before implementation:

- Validate service ownership against all domain entities.
- map every event producer and consumer.
- map every canonical authority.
- simulate major workflows.
- identify all cross-domain transactions.
- validate recovery ownership.

---

## 62. Stage 1 — Modular core

Deploy:

- Unified Core Application with strict domain modules.
- Independent Accounting Ledger.
- Independent Blockchain Indexer.
- Independent Identity Vault.
- Independent Payment Orchestrator.
- Independent Signing Service.
- Durable event bus and outbox/inbox infrastructure.

---

## 63. Stage 2 — High-risk extraction

Extract or independently deploy:

- Underwriting.
- oracle aggregation.
- cross-chain coordination.
- liquidation coordination.
- reconciliation.
- UFT economics.
- governance monitoring.

---

## 64. Stage 3 — Scale-driven extraction

Extract where justified:

- Marketplace search.
- notifications.
- messaging.
- analytics.
- positions and secondary market.
- servicing schedules.

---

## 65. Stage 4 — Multi-region resilience

- Add secondary active or warm region.
- test aggregate ownership failover.
- deploy independent provider routes.
- validate regional recovery.
- introduce public status and incident automation.

---

# Part XVIII — Architecture Decision Records

## 66. Required ADRs

At minimum, Unified must create ADRs for:

1. Canonical home-chain selection.
2. Contract upgrade strategy.
3. UFT token immutability.
4. Cross-chain adapter model.
5. Loan account deployment model.
6. Modular monolith versus initial services.
7. Accounting ledger technology.
8. Event-bus technology.
9. Relational database strategy.
10. Identity Vault architecture.
11. Underwriting model runtime.
12. Payment-provider adapter isolation.
13. HSM and threshold-signing design.
14. Multi-region database strategy.
15. RPC and node-provider strategy.
16. Oracle aggregation design.
17. Search and analytics separation.
18. Backup and immutable evidence storage.
19. Observability and audit retention.
20. Incident and emergency-control execution.

---

# Part XIX — Architecture Invariants

## 67. Service and deployment invariants

1. No application projection may originate financial rights.
2. No service may mutate another domain’s canonical state through direct database access.
3. Every financial command is idempotent.
4. Every material event is versioned and attributable.
5. Every high-risk external provider is isolated behind a bounded adapter.
6. The accounting ledger is independently controlled and append-only after posting.
7. The transaction builder cannot sign transactions.
8. The signing service cannot independently invent transaction intent.
9. No public workload can access HSM key material.
10. No single cloud role controls code deployment, treasury, identity data, and accounting.
11. Active loan economics cannot be changed through application deployment.
12. UFT supply cannot be increased through runtime administration.
13. Wrapped UFT cannot exceed canonical backing.
14. Payment provisional state cannot be collapsed into final state by UI or cache.
15. Cross-chain messages cannot execute more than once.
16. Reorganized chain events cannot remain silently final in projections.
17. Restricted identity data is never published to public event topics.
18. Posted journals cannot be edited by database administrators.
19. Recovery cannot bypass canonical reconciliation.
20. Backups are not accepted until restoration is tested.
21. Loss of one availability zone cannot destroy all copies of Tier 0 off-chain state.
22. Failure of one RPC provider cannot determine protocol truth.
23. Failure of one provider adapter cannot expose credentials for another provider.
24. A cache outage cannot prevent valid debt or collateral reconciliation.
25. Emergency controls cannot prevent safe repayment where technically possible.
26. Market-stress mode cannot rewrite active agreements.
27. Every privileged action is attributable to a human or workload identity.
28. Every service has a declared owner and recovery procedure.
29. Every deployment artifact is traceable to reviewed source.
30. Every production contract deployment is reproducible and verified.

---

# Part XX — Launch Gates

## 68. Architecture launch gates

Unified MUST NOT enter unrestricted production while any known path allows:

- A shared database table to bypass domain ownership.
- The frontend or API to declare financial finality without canonical evidence.
- A payment callback to release collateral without reconciliation policy.
- A service credential to access unrestricted signing authority.
- A single RPC or oracle source to determine critical state without required redundancy.
- A bridge adapter to mint unbacked UFT.
- A regional outage to permanently lose Tier 0 off-chain records.
- Accounting history to be altered through ordinary administration.
- Sensitive identity data to flow into public logs, traces, or event streams.
- Duplicate commands or events to create duplicate economic effects.
- Chain reorganizations to leave unreconciled final projections.
- Contract deployment without reproducible artifact verification.
- Production access without strong identity and audit.
- Backups without successful restore testing.
- An emergency operator to mint UFT, seize arbitrary assets, or rewrite active loans.
- A service without named ownership, on-call coverage, and recovery runbook.
- Critical provider failure without circuit breaker and reconciliation procedure.
- Cross-chain recovery to unlock value on both source and destination.
- Staging or development credentials to authorize production activity.
- A deployment to change the meaning of an active agreement schema.

---

# Part XXI — Implementation Deliverables

## 69. Required implementation artifacts

This specification requires the following artifacts before production implementation is considered architecture-complete:

```text
SYSTEM_CONTEXT.md
SERVICE_CATALOG.md
SERVICE_OWNERSHIP_MATRIX.md
TRUST_BOUNDARY_DIAGRAMS.md
NETWORK_ZONE_SPECIFICATION.md
DATASTORE_OWNERSHIP_MATRIX.md
EVENT_PRODUCER_CONSUMER_MATRIX.md
WORKFLOW_ORCHESTRATION_CATALOG.md
PROVIDER_ADAPTER_CATALOG.md
KEY_AND_SIGNING_ARCHITECTURE.md
DEPLOYMENT_ENVIRONMENT_MATRIX.md
MULTI_REGION_TOPOLOGY.md
SLO_AND_ERROR_BUDGET_SPEC.md
CAPACITY_MODEL.md
OBSERVABILITY_STANDARD.md
BACKUP_AND_RECOVERY_PLAN.md
DISASTER_RECOVERY_RUNBOOK.md
PRIVILEGED_ACCESS_MODEL.md
SOFTWARE_SUPPLY_CHAIN_POLICY.md
ARCHITECTURE_DECISION_RECORDS/
```

---

## 70. Immediate next architecture step

The next foundation should be the **Unified Repository Architecture, Engineering Constitution, and Delivery Workflow Specification v0.1**.

It should define:

- Monorepo layout.
- Language and framework boundaries.
- Smart-contract packages.
- Service templates.
- API and event schema packages.
- Database migration ownership.
- Test hierarchy.
- CI/CD gates.
- Branching and integration strategy.
- Agent and team ownership.
- Dependency rules.
- Code review requirements.
- release and deployment workflow.
- Architecture-conformance automation.

---

# Appendix A — Service ownership summary

| Service/domain | Canonical off-chain owner | Critical dependencies | Extraction priority |
|---|---|---|---|
| Accounts | Account Service | Identity, wallets | Medium |
| Identity | Identity Credential Service | Providers, HSM/KMS | Immediate isolation |
| Marketplace | Marketplace Service | Search, tenders | Later scale extraction |
| Offers | Offer Service | Signatures, marketplace | Core module initially |
| Underwriting | Underwriting Orchestrator | Identity, data providers, models | Immediate isolation |
| Origination | Loan Origination Service | Contracts, funding, collateral | Core module initially |
| Funding | Funding Service | Contracts, accounting | Core module initially |
| Servicing | Loan Servicing Service | Schedule engine, payments | Core module initially |
| Payments | Payment Orchestrator | Banks, cards, ledger | Immediate isolation |
| Accounting | Accounting Ledger Service | All financial domains | Immediate isolation |
| Collateral | Collateral Coordinator | Vaults, oracles | Core plus isolated oracle |
| Liquidation | Liquidation Coordinator | Oracles, auctions, contracts | High-risk extraction |
| Positions | Position Service | Contracts, accounting | Later extraction |
| Refinancing | Refinance Coordinator | Loans, funding, collateral | Core initially |
| Insurance | Insurance Service | Treasury, ledger, recovery | High-risk extraction |
| UFT | UFT Economic Service | Token, staking, treasury | High-risk extraction |
| Governance | Governance Service | Governor, timelock | Independent monitoring |
| Cross-chain | Cross-Chain Coordinator | Bridges, chains | Immediate isolation |
| Indexing | Blockchain Indexer | RPCs, event archive | Immediate isolation |
| Reconciliation | Reconciliation Service | Chains, providers, ledger | Immediate isolation |
| Notifications | Notification Service | User preferences, providers | Later extraction |
| Analytics | Analytics Platform | Event archive, warehouse | Derived and isolated |

---

# Appendix B — Minimum production clusters

A minimum serious production deployment SHOULD separate:

1. Public edge and API workloads.
2. General application domain workloads.
3. Payment-provider workloads.
4. Identity and underwriting workloads.
5. Accounting and reconciliation workloads.
6. Blockchain indexing and transaction workloads.
7. Cross-chain workloads.
8. Signing and key-management workloads.
9. Operations and governance workloads.
10. Observability and security workloads.

These may share an orchestration platform only when namespaces, network policies, workload identities, secrets, node pools, and administrative roles remain strongly separated.

---

# Appendix C — Architectural completion statement

This specification establishes the deployment-level architecture of Unified as a multi-domain financial protocol whose canonical financial state is distributed across immutable smart contracts, regulated provider evidence, signed off-chain agreements, and an append-only accounting ledger.

Unified is therefore not one application and not one blockchain contract suite. It is a coordinated system of independently bounded authorities connected through versioned commands, durable events, explicit finality, deterministic accounting, continuous reconciliation, and constrained governance.

Its runtime architecture must preserve those properties under normal operation, market stress, provider failure, regional failure, malicious behavior, software defects, and disaster recovery.
