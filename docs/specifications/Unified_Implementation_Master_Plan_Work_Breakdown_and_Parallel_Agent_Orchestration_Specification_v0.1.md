# Unified Implementation Master Plan, Work Breakdown Structure, and Parallel Agent Orchestration Specification v0.1

**Status:** Foundational Draft  
**Classification:** Binding Delivery and Program-Control Specification  
**Version:** 0.1  
**Applies to:** All Unified implementation phases, workstreams, human contributors, AI agents, vendors, repositories, integration branches, environments, audits, test networks, launch rehearsals, and production-readiness decisions.

---

## 1. Purpose

This specification converts Unified's completed constitutional, domain, protocol, accounting, tokenomic, security, interface, data, deployment, and engineering foundations into an executable implementation program.

It defines:

- The complete delivery lifecycle.
- Program phases and dependency gates.
- Work breakdown structures.
- Parallel workstreams.
- Human and AI-agent responsibilities.
- Branch and integration choreography.
- Acceptance criteria.
- Test and verification milestones.
- Testnet progression.
- Audit sequencing.
- Economic and operational simulations.
- Production-readiness gates.
- Launch, rollback, and post-launch stabilization.

This document governs **how Unified moves from architecture to production**.

---

## 2. Governing Sources

All implementation work SHALL conform to:

1. Unified Constitution v0.1.
2. Unified Domain Model v0.1.
3. Universal Loan Model and State Machines v0.1.
4. Unified Financial Accounting Specification v0.1.
5. UFT Tokenomics and Economic Security Specification v0.1.
6. Unified Threat Model and Adversarial Security Specification v0.1.
7. Unified Protocol Invariants and Formal Verification Specification v0.1.
8. Unified Smart Contract Interface and Protocol API Specification v0.1.
9. Unified On-Chain/Off-Chain Data Architecture and Event Contract Specification v0.1.
10. Unified System Architecture, Service Boundaries, and Deployment Topology Specification v0.1.
11. Unified Repository Architecture, Engineering Constitution, and Delivery Workflow Specification v0.1.

When a task, implementation, test, deployment, or release conflicts with these sources, the implementation is defective unless the governing specification is formally amended.

---

## 3. Program Principles

### 3.1 Full-scope development without uncontrolled convergence

Unified SHALL implement its complete intended ecosystem, including:

- UFT.
- Single-lender and syndicated loans.
- Collateralized, partially collateralized, guaranteed, and unsecured lending.
- Fungible, NFT, mixed, digital, and off-chain collateral.
- Fixed, variable, hybrid, and benchmark-linked interest.
- Bullet, amortizing, installment, balloon, interest-only, and custom schedules.
- Automated underwriting.
- Private and zero-knowledge credentials.
- Fiat, card, crypto, and cross-chain settlement.
- Refinancing and restructuring.
- Algorithmic and auction liquidation.
- Secondary loan-position markets.
- Insurance and bad-debt protection.
- UFT staking, governance, liquidity, and bridge representations.

All major capabilities may advance simultaneously, but they SHALL converge through shared interfaces, schemas, invariants, accounting rules, and integration gates.

### 3.2 Architecture before local convenience

A local implementation shortcut SHALL NOT override:

- Domain ownership.
- Canonical authority.
- Active-loan immutability.
- Double-entry accounting.
- Payment finality.
- UFT supply integrity.
- Bridge backing.
- Governance boundaries.
- Privacy classifications.
- Security invariants.

### 3.3 Parallelism with controlled dependencies

Parallel work SHALL be organized as a directed dependency graph.

A downstream task may begin against an approved contract, schema, interface, fixture, simulator, or mock even when the upstream production implementation is incomplete.

A downstream task may not declare completion until it passes integration against the real upstream implementation.

### 3.4 Evidence-based completion

A work item is not complete because code exists.

Completion requires:

- Required artifacts.
- Passing tests.
- Invariant mappings.
- Security review.
- Documentation.
- Migration and rollback notes.
- Integration evidence.
- Acceptance sign-off.

### 3.5 Integration is continuous

Workstreams SHALL integrate at regular checkpoints. Large end-of-phase merges are prohibited for critical financial code.

### 3.6 No hidden manual systems

No production-critical workflow may depend on an undocumented spreadsheet, personal script, manual database edit, informal key exchange, or untracked operational procedure.

### 3.7 Safe launch over calendar launch

No planned date overrides launch-blocking security, accounting, solvency, legal, or operational failures.

---

## 4. Program Lifecycle

Unified implementation is divided into fifteen controlled phases.

```text
Phase 0   Program Mobilization and Baseline Freeze
Phase 1   Repository, Toolchain, Schemas, and Engineering Controls
Phase 2   Protocol Kernel and UFT Foundations
Phase 3   Core Loan Origination and Accounting Spine
Phase 4   Collateral, Oracle, Liquidation, and Servicing Engines
Phase 5   Syndication, Tranches, and Lender Positions
Phase 6   Identity, Reputation, Underwriting, and Unsecured Credit
Phase 7   Fiat, Card, Payment, and Reconciliation Infrastructure
Phase 8   Cross-Chain Protocol and Wrapped UFT
Phase 9   Refinancing, Restructuring, Insurance, and Recovery
Phase 10  Secondary Market, Governance, Staking, and Liquidity
Phase 11  Complete Experience Layer and Operations Console
Phase 12  Integrated Adversarial Verification and Economic Simulation
Phase 13  Testnet, Pilot, Audit, and Production Rehearsal
Phase 14  Controlled Mainnet Launch
Phase 15  Stabilization, Decentralization, and Expansion
```

The phases define integration maturity, not a prohibition against parallel development. Workstreams may begin early where their prerequisites are satisfied through stable interfaces or simulators.

---

## 5. Workstream Model

### WS-01 — Protocol Kernel

Owns:

- Loan factory.
- Loan registry.
- Policy registry.
- Universal loan account.
- Agreement snapshots.
- Access-control boundaries.
- Version binding.
- Protocol pause semantics.

### WS-02 — UFT and Token Economics

Owns:

- Canonical UFT token.
- Genesis allocation vaults.
- Vesting.
- Burner.
- Fee router.
- Staking vault.
- Governance lock.
- Reward distribution.
- UFT collateral adapter.
- Cross-chain UFT accounting interfaces.

### WS-03 — Marketplace and Negotiation

Owns:

- Tenders.
- Offers.
- Counteroffers.
- Signatures and nonces.
- Search projections.
- Encrypted conversations.
- Disclosures.
- Tender and offer lifecycle.

### WS-04 — Funding, Syndication, and Positions

Owns:

- Funding commitments.
- Single-lender settlement.
- Syndicate vaults.
- Tranches.
- Repayment waterfalls.
- Lender-position issuance.
- Splits, merges, transfers, pledges, and redemption.

### WS-05 — Interest and Loan Servicing

Owns:

- Fixed and variable interest.
- Benchmark adapters.
- Repayment schedules.
- Installment generation.
- Delinquency.
- Grace periods.
- Penalties.
- Cure.
- Acceleration.
- Closure coordination.

### WS-06 — Collateral, Oracle, and Liquidation

Owns:

- Fungible collateral.
- NFT and ERC-1155 collateral.
- Mixed bundles.
- UFT collateral controls.
- Valuation.
- Health factors.
- Margin calls.
- Partial and full liquidation.
- Auctions.
- Borrower surplus.

### WS-07 — Identity, Privacy, and Reputation

Owns:

- Wallet accounts.
- Identity attestations.
- KYC provider integration.
- Privacy classifications.
- Consent.
- Revocation.
- Zero-knowledge eligibility credentials.
- Reputation events and scores.

### WS-08 — Underwriting and Credit Risk

Owns:

- Credit application workflow.
- Feature registry.
- Decision policies.
- Model registry.
- Risk grades.
- Exposure limits.
- Fraud rules.
- Manual review.
- Explanations.
- Model monitoring.

### WS-09 — Payments and Settlement

Owns:

- Crypto payments.
- Bank settlement.
- Card settlement.
- Payment evidence.
- Provisional and final status.
- Refunds.
- Chargebacks.
- Currency conversion.
- Provider adapters.

### WS-10 — Financial Accounting and Reconciliation

Owns:

- Chart of accounts.
- Journal engine.
- Loan subledger.
- UFT supply controls.
- Collateral-control accounts.
- Suspense.
- Provider reconciliation.
- Chain reconciliation.
- Reserve reporting.
- Financial close.

### WS-11 — Cross-Chain

Owns:

- Canonical-home-chain coordination.
- Messaging adapters.
- Satellite loan components.
- Remote collateral vaults.
- Finality rules.
- Replay prevention.
- Timeout and recovery.
- UFT bridge escrow.
- Wrapped-UFT issuance.

### WS-12 — Refinancing, Restructuring, Insurance, and Recovery

Owns:

- Payoff quotes.
- Atomic refinancing.
- Restructuring proposals.
- Loan amendments.
- Guarantees.
- Insurance claims.
- Bad-debt waterfalls.
- Recoveries.
- Write-offs.

### WS-13 — Governance, Treasury, and Operations

Owns:

- Governor.
- Timelock.
- Risk council.
- Emergency council.
- Treasury mandates.
- Proposal lifecycle.
- Role management.
- Operational control plane.

### WS-14 — Experience Applications

Owns:

- Public marketplace.
- Borrower application.
- Lender application.
- Portfolio experience.
- Governance application.
- Operations console.
- Mobile interfaces.
- Transaction-intent explanations.

### WS-15 — Data, Events, Indexing, and Analytics

Owns:

- Event envelopes.
- Command schemas.
- Outbox and inbox libraries.
- Chain indexers.
- Provider-event ingestion.
- Search projections.
- Analytics warehouse.
- Read-model rebuilds.

### WS-16 — Platform, Infrastructure, and Reliability

Owns:

- Environments.
- Infrastructure as code.
- Network zones.
- Databases.
- Queues.
- HSM and key management.
- Secrets.
- Observability.
- Backups.
- Disaster recovery.
- Release infrastructure.

### WS-17 — Security, Formal Verification, and Adversarial Testing

Owns:

- Threat-model traceability.
- Invariant harnesses.
- Fuzzing.
- Symbolic analysis.
- Penetration testing.
- Red-team campaigns.
- Audit preparation.
- Security findings.
- Launch-blocking security gates.

### WS-18 — Economic Modeling and Risk Simulation

Owns:

- UFT unlock simulations.
- Staking-reward runway.
- Governance concentration.
- Collateral stress.
- Default correlation.
- Bridge loss.
- Payment reversal loss.
- Treasury and insurance solvency.
- Market-liquidity scenarios.

### WS-19 — Compliance, Legal, and Policy Operations

Owns:

- Jurisdiction analysis.
- Product classifications.
- KYC/AML policies.
- Consumer disclosures.
- Data-protection requirements.
- Token-distribution constraints.
- Payment-provider obligations.
- Governance and corporate interfaces.

This workstream informs architecture and launch gates but does not silently rewrite technical specifications.

---

## 6. Dependency Graph

The high-level dependency graph is:

```text
Constitution and Specifications
        │
        ▼
Repository + Schemas + CI Controls
        │
        ├──────────────► Security Harness
        ├──────────────► Infrastructure Baseline
        └──────────────► Service/Contract Templates
        │
        ▼
Protocol Kernel + UFT + Accounting Spine
        │
        ├────────► Marketplace and Offers
        ├────────► Funding and Syndication
        ├────────► Servicing and Schedules
        ├────────► Collateral and Liquidation
        ├────────► Identity and Underwriting
        ├────────► Payments and Settlement
        └────────► Data and Indexing
        │
        ▼
Cross-Domain Coordination
        │
        ├────────► Cross-Chain
        ├────────► Refinancing
        ├────────► Insurance and Recovery
        ├────────► Secondary Markets
        └────────► Governance and Staking
        │
        ▼
Experience Applications
        │
        ▼
Integrated Verification
        │
        ▼
Testnet + Audit + Rehearsal
        │
        ▼
Controlled Mainnet Launch
```

### 6.1 Critical dependency rules

1. No financial service may finalize balances before the accounting contract is stable.
2. No payment adapter may release collateral directly.
3. No cross-chain module may activate a loan without canonical-home-chain rules.
4. No lender position may exist before funding conservation rules are implemented.
5. No UFT bridge may launch before canonical supply and backing invariants pass.
6. No automated underwriting may originate loans before policy versioning, explanation, consent, and exposure controls exist.
7. No secondary market may trade positions before ownership and accrued-interest rules are deterministic.
8. No governance upgrade path may deploy before storage-layout, timelock, and active-loan immutability tests pass.
9. No user interface may present provisional settlement as final.
10. No production deployment may proceed without reconciliation and recovery paths.

---

## 7. Phase 0 — Program Mobilization and Baseline Freeze

### 7.1 Objectives

- Establish program authority.
- Freeze the v0.1 architecture baseline.
- Create the implementation backlog.
- Assign workstream ownership.
- Establish decision and escalation mechanisms.
- Define evidence and reporting standards.

### 7.2 Work packages

#### WP-0.1 — Specification registry

Deliverables:

- Canonical specification index.
- Version and amendment policy.
- Traceability identifiers.
- Specification dependency map.

#### WP-0.2 — Program governance

Deliverables:

- Program steering group.
- Protocol architecture council.
- Security authority.
- Economic risk authority.
- Release authority.
- Incident authority.

#### WP-0.3 — Workstream charters

Each charter SHALL define:

- Scope.
- Owned directories.
- Canonical entities.
- Interfaces produced.
- Interfaces consumed.
- Invariants.
- Threats.
- Acceptance criteria.
- Named owner.

#### WP-0.4 — Integrated backlog

The backlog SHALL use stable identifiers:

```text
UNI-<WORKSTREAM>-<NUMBER>
```

Examples:

```text
UNI-KERNEL-001
UNI-UFT-014
UNI-LEDGER-032
UNI-BRIDGE-008
```

#### WP-0.5 — Risk and assumption registers

Every material assumption must identify:

- Owner.
- Evidence.
- Expiry date.
- Downstream impact.
- Validation plan.

### 7.3 Exit criteria

- All twelve governing documents are indexed.
- Every workstream has an accountable owner.
- All existential and critical risks have owners.
- The dependency graph is approved.
- No unresolved contradiction exists between foundational documents.
- The architecture baseline is tagged.

---

## 8. Phase 1 — Repository, Toolchain, Schemas, and Engineering Controls

### 8.1 Objectives

- Create the monorepo.
- Install canonical toolchains.
- Establish schemas and code generation.
- Enforce architecture boundaries.
- Create CI/CD foundations.
- Produce service and contract templates.

### 8.2 Work packages

#### WP-1.1 — Monorepo bootstrap

Required top-level directories:

```text
constitution/
docs/
adr/
rfcs/
protocol/
services/
apps/
packages/
schemas/
models/
infrastructure/
deployments/
operations/
security/
simulations/
tests/
scripts/
tools/
```

#### WP-1.2 — Toolchain lock

Required:

- Solidity and Foundry versions.
- Go toolchain.
- Node and package-manager versions.
- Python environment.
- Protobuf and schema tooling.
- Infrastructure tools.
- Static analyzers.
- Secret scanners.
- Container builders.

#### WP-1.3 — Shared schemas

Initial schemas:

- Universal identifiers.
- Command envelope.
- Event envelope.
- Money and asset types.
- Loan terms.
- Policy references.
- Payment evidence.
- Ledger posting intent.
- Cross-chain messages.
- Governance actions.

#### WP-1.4 — Templates

Templates SHALL exist for:

- Solidity contract package.
- Go financial service.
- TypeScript application.
- Python model package.
- Protobuf API.
- Database migration.
- Workflow orchestrator.
- Provider adapter.
- Threat mapping.
- Invariant mapping.
- ADR and RFC.

#### WP-1.5 — CI gates

Required pipelines:

- Repository conformance.
- Schema compatibility.
- Solidity.
- Go.
- TypeScript.
- Python.
- Infrastructure.
- Dependencies and licenses.
- Secrets.
- SBOM.
- Container security.
- Integration smoke tests.

#### WP-1.6 — Local developer environment

Required:

- Reproducible local stack.
- Local EVM chains.
- PostgreSQL.
- Event broker.
- Object storage.
- Mock providers.
- Seed data.
- One-command reset.

### 8.3 Exit criteria

- Clean bootstrap from a new machine succeeds.
- All templates compile.
- CI rejects forbidden dependencies and directory violations.
- Schemas generate code in all required languages.
- Local environment runs end to end.
- Artifact provenance and SBOM generation work.

---

## 9. Phase 2 — Protocol Kernel and UFT Foundations

### 9.1 Objectives

- Implement the smallest trusted contract kernel.
- Establish UFT fixed supply and allocation controls.
- Implement policy and version registries.
- Establish governance roles without enabling unrestricted governance.

### 9.2 Work packages

#### WP-2.1 — Protocol configuration

- Protocol identity.
- Chain configuration.
- Role definitions.
- Pause domains.
- Version registry.

#### WP-2.2 — Loan registry and factory

- Canonical loan IDs.
- Agreement hashes.
- Implementation versions.
- Deployment records.
- Terminal-state protections.

#### WP-2.3 — Policy registry

- Policy IDs.
- Semantic versions.
- Interface support.
- Activation dates.
- Deprecation.
- Future-loan applicability.

#### WP-2.4 — UFT token

- Fixed `1,000,000,000 UFT` genesis supply.
- No post-genesis mint path.
- Permit support.
- Burn support.
- Supply events.

#### WP-2.5 — Allocation and vesting vaults

- Community allocation.
- Treasury.
- Staking reserve.
- Insurance reserve.
- Contributors.
- Investors.
- Public distribution.
- Liquidity allocation.
- Advisors and partners.

#### WP-2.6 — UFT burner and fee-router skeleton

- Funded fee receipt.
- Bounded revenue splits.
- Burn accounting.
- Emergency suspension rules.

#### WP-2.7 — Kernel formal verification

Minimum proofs and invariants:

- UFT supply cap.
- Allocation conservation.
- No hidden mint authority.
- Loan-ID uniqueness.
- Policy-version immutability.
- Role separation.
- Pause restrictions.

### 9.3 Exit criteria

- All kernel contracts compile and pass tests.
- UFT supply invariants pass stateful fuzzing.
- Storage layouts are documented.
- Deployment scripts are reproducible.
- Independent internal security review is complete.
- No critical or existential finding remains unresolved.

---

## 10. Phase 3 — Core Loan Origination and Accounting Spine

### 10.1 Objectives

- Originate a same-chain, single-lender loan.
- Create authoritative accounting entries.
- Establish tender, offer, activation, repayment, and closure flows.

This phase does not define the final product boundary. It establishes the shared spine used by all advanced loan forms.

### 10.2 Work packages

#### WP-3.1 — Tender and offer contracts/services

- Tender publication.
- Offer signing.
- Counteroffers.
- Nonces.
- Expiration.
- Cancellation.
- One-time acceptance.

#### WP-3.2 — Universal loan account

- Immutable terms snapshot.
- Policy references.
- Borrower and lender identities.
- Principal obligation.
- Status vector.
- Repayment entry points.

#### WP-3.3 — Funding manager

- Single-lender commitment.
- Principal transfer.
- Fee deduction.
- Failure rollback.
- Activation evidence.

#### WP-3.4 — Accounting ledger service

- Chart of accounts.
- Journal engine.
- Balanced postings.
- Immutability.
- Reversals.
- Loan subledger.
- Idempotent posting.

#### WP-3.5 — Chain indexer and event projections

- Contract-event ingestion.
- Reorg handling.
- Finality states.
- Loan and tender projections.
- Replay and rebuild.

#### WP-3.6 — Core application APIs

- Authentication.
- Tender queries.
- Offer commands.
- Loan queries.
- Transaction preparation.
- Portfolio projections.

### 10.3 Canonical demonstration

The phase SHALL demonstrate:

```text
Borrower creates tender
→ Lender signs offer
→ Borrower accepts
→ Funding transfers
→ Loan activates
→ Accounting journals post
→ Borrower repays
→ Lender receives funds
→ Loan closes
→ Journals reconcile
```

### 10.4 Exit criteria

- Offer replay is impossible.
- Activation is atomic for same-chain assets.
- Every material action produces a canonical event.
- Every value movement produces balanced accounting.
- Repayment reduces debt only once.
- Terminal loans cannot reactivate.
- Indexer rebuild reproduces projections.

---

## 11. Phase 4 — Collateral, Oracle, Liquidation, and Servicing Engines

### 11.1 Objectives

- Support complex collateral and servicing behavior.
- Implement deterministic debt calculations.
- Add liquidation with reproducible economics.

### 11.2 Work packages

#### WP-4.1 — Collateral vaults

- ERC-20.
- Native asset.
- ERC-721.
- ERC-1155.
- Mixed collateral bundles.
- UFT collateral.

#### WP-4.2 — Oracle router

- Approved sources.
- Decimal normalization.
- Freshness.
- Deviation limits.
- Fallbacks.
- Source evidence.

#### WP-4.3 — Interest engine

- Fixed interest.
- Variable interest.
- Benchmark plus spread.
- Floors and caps.
- Accrual precision.

#### WP-4.4 — Schedule engine

- Bullet.
- Amortizing.
- Equal principal.
- Interest-only.
- Balloon.
- Custom installments.
- Payment holidays.

#### WP-4.5 — Servicing state machine

- Current.
- Grace.
- Delinquent.
- Cured.
- Accelerated.
- Defaulted.
- Repaid.

#### WP-4.6 — Liquidation engine

- Direct swap.
- Partial liquidation.
- Dutch auction.
- English auction.
- NFT auction.
- Lender claim.
- Borrower surplus.

### 11.3 Exit criteria

- Debt calculations are deterministic across contracts and services.
- Oracle failures enter safe mode.
- Collateral cannot release before final debt settlement.
- Every liquidation is reproducible.
- UFT collateral debt ceilings and concentration controls work.
- NFT auctions handle failed and expired auctions safely.
- Liquidation accounting reconciles.

---

## 12. Phase 5 — Syndication, Tranches, and Lender Positions

### 12.1 Objectives

- Enable multiple lenders.
- Create deterministic tranche waterfalls.
- Represent transferable economic claims.

### 12.2 Work packages

#### WP-5.1 — Funding rounds

- Target amount.
- Minimum funding.
- Maximum funding.
- Commitments.
- Funding deadline.
- Cancellation and refund.

#### WP-5.2 — Syndicate vault

- Pro-rata shares.
- Commitment settlement.
- Activation threshold.
- Principal disbursement.
- Repayment distribution.

#### WP-5.3 — Tranches

- Seniority.
- Coupon rules.
- First-loss and last-loss behavior.
- Voting rights.
- Recovery rights.

#### WP-5.4 — Position manager

- Issuance.
- Split.
- Merge.
- Transfer.
- Pledge.
- Freeze.
- Redemption.

#### WP-5.5 — Accounting

- Syndicate commitments.
- Tranche balances.
- Position transfers.
- Accrued-interest ownership.
- Loss allocation.

### 12.3 Exit criteria

- Aggregate lender rights never exceed funded obligations.
- Repayment waterfalls are deterministic.
- Position transfers do not duplicate rights.
- Accrued interest is assigned correctly at transfer.
- Refunds occur when funding thresholds fail.
- Tranche-loss simulations pass.

---

## 13. Phase 6 — Identity, Reputation, Underwriting, and Unsecured Credit

### 13.1 Objectives

- Add privacy-preserving identity.
- Build automated and manual underwriting.
- Support verified, pseudonymous, private, and anonymous credit models.

### 13.2 Work packages

#### WP-6.1 — Identity attestation registry

- Provider registration.
- Credential issuance.
- Expiration.
- Revocation.
- Subject commitments.

#### WP-6.2 — Restricted identity vault

- Encrypted storage.
- Purpose-based access.
- Consent.
- Retention.
- Audit.

#### WP-6.3 — Zero-knowledge credentials

- Uniqueness proof.
- Eligibility proof.
- Age and jurisdiction proof.
- Risk-class proof.
- Exposure-limit proof.

#### WP-6.4 — Reputation engine

- Verifiable events.
- Score versions.
- Explanation.
- Fraud resistance.
- Sybil resistance.

#### WP-6.5 — Underwriting engine

- Feature registry.
- Policy rules.
- Model registry.
- Decision version.
- Exposure limits.
- Reason codes.
- Manual review.

#### WP-6.6 — Unsecured credit products

- Verified unsecured.
- Pseudonymous unsecured.
- Privately verified.
- Anonymous risk-pool-backed.
- Guarantor-backed.

### 13.3 Exit criteria

- Raw identity data never enters public contracts.
- Credentials can be revoked.
- Credit decisions are versioned and explainable.
- Exposure limits cannot be bypassed through multiple accounts.
- Synthetic-identity simulations are performed.
- Anonymous products disclose loss and enforceability limitations.
- Model bias, drift, and manipulation monitoring exists.

---

## 14. Phase 7 — Fiat, Card, Payment, and Reconciliation Infrastructure

### 14.1 Objectives

- Add external payment rails safely.
- Preserve provisional and final settlement distinctions.
- Build provider-independent orchestration.

### 14.2 Work packages

#### WP-7.1 — Payment router

- Payment intents.
- Provider routing.
- Idempotency.
- Status lifecycle.
- Evidence hashes.

#### WP-7.2 — Bank adapters

- Deposit.
- Withdrawal.
- Disbursement.
- Repayment.
- Reversal.
- Reconciliation.

#### WP-7.3 — Card adapters

- Authorization.
- Capture.
- Provisional credit.
- Processor settlement.
- Chargeback.
- Refund.

#### WP-7.4 — Currency conversion

- Quotes.
- Expiry.
- Slippage.
- Provider fees.
- Settlement asset.

#### WP-7.5 — Reconciliation service

- Provider statements.
- Ledger comparison.
- Exceptions.
- Suspense.
- Resolution workflow.

### 14.3 Exit criteria

- Provider callbacks are authenticated and idempotent.
- Provisional payments cannot release collateral.
- Chargebacks reinstate debt correctly.
- Provider outage recovery is tested.
- Unknown callbacks are quarantined.
- Daily reconciliation completes with owned exceptions.

---

## 15. Phase 8 — Cross-Chain Protocol and Wrapped UFT

### 15.1 Objectives

- Support multi-chain loans without fragmented authority.
- Implement fully backed wrapped UFT.
- Build timeout and recovery mechanisms.

### 15.2 Work packages

#### WP-8.1 — Canonical cross-chain coordinator

- Loan home-chain authority.
- Message registry.
- Nonces.
- Finality.
- Replay protection.

#### WP-8.2 — Satellite loan components

- Remote collateral.
- Remote disbursement.
- Remote repayment evidence.
- Authority restrictions.

#### WP-8.3 — Messaging adapters

- Provider abstraction.
- Source verification.
- Destination binding.
- Retry.
- Timeout.

#### WP-8.4 — UFT bridge hub

- Canonical escrow.
- Wrapped issuance.
- Wrapped burn.
- Canonical release.
- Exposure limits.
- Backing reconciliation.

#### WP-8.5 — Cross-chain recovery

- Message failure.
- Provider outage.
- Compromised route.
- Delayed finality.
- Source and destination compensation.

### 15.3 Exit criteria

- Every message executes at most once.
- Wrapped UFT never exceeds canonical backing.
- Satellite contracts cannot rewrite loan economics.
- Timeout recovery cannot unlock value twice.
- Bridge-exposure limits are enforced.
- Multi-provider failover and bridge-compromise simulations pass.

---

## 16. Phase 9 — Refinancing, Restructuring, Insurance, and Recovery

### 16.1 Objectives

- Support controlled loan modification and replacement.
- Capitalize and operate loss-protection mechanisms.
- Handle bad debt transparently.

### 16.2 Work packages

#### WP-9.1 — Payoff quote engine

- Principal.
- Accrued interest.
- Fees.
- Penalties.
- Expiry.

#### WP-9.2 — Refinance coordinator

- New funding.
- Old payoff.
- Old-lien release.
- Collateral reassignment.
- New activation.
- Borrower proceeds.

#### WP-9.3 — Restructuring controller

- Proposal.
- Consent.
- Voting.
- Policy constraints.
- New schedule.
- Accounting modification.

#### WP-9.4 — Insurance manager

- Coverage policies.
- Premiums.
- Claim validation.
- Reserve accounting.
- Payout waterfall.

#### WP-9.5 — Recovery manager

- Guarantors.
- Collateral recoveries.
- Legal or off-chain recoveries.
- Write-off.
- Recovery allocation.

### 16.3 Exit criteria

- Refinancing never creates duplicate senior liens.
- Failed refinancing returns to a safe state.
- Restructuring preserves required consent.
- Insurance claims cannot exceed coverage.
- Losses and recoveries are not double-counted.
- Reserve solvency metrics are available.

---

## 17. Phase 10 — Secondary Market, Governance, Staking, and Liquidity

### 17.1 Objectives

- Enable secondary liquidity.
- Activate bounded UFT governance.
- Launch funded staking and liquidity systems.

### 17.2 Work packages

#### WP-10.1 — Secondary position market

- Listings.
- Bids.
- Settlement.
- Transfer-policy checks.
- Accrued-interest treatment.
- Defaulted-position restrictions.

#### WP-10.2 — Governance lock and voting

- veUFT.
- Checkpoints.
- Delegation.
- Snapshot voting.
- Lock periods.

#### WP-10.3 — Governor and timelock

- Proposal classes.
- Thresholds.
- Quorum.
- Approval ratios.
- Delays.
- Execution.

#### WP-10.4 — UFT staking

- sUFT shares.
- Reward funding.
- Withdrawal queue.
- Slashing.
- Incident accounting.

#### WP-10.5 — Liquidity incentives

- Approved pools.
- Epoch budgets.
- Time-weighted contribution.
- Protocol-owned liquidity.
- Reward vesting.

### 17.3 Exit criteria

- One UFT cannot vote twice.
- Collateralized and bridged UFT do not create duplicate governance power.
- Governance cannot mint UFT or rewrite active loans.
- Staking rewards are fully funded.
- Secondary-market transfer preserves economic rights.
- Governance-capture and flash-governance simulations pass.

---

## 18. Phase 11 — Complete Experience Layer and Operations Console

### 18.1 Objectives

- Deliver coherent user experiences across all capabilities.
- Make risk and finality visible.
- Provide secure operational control.

### 18.2 Applications

#### Borrower experience

- Identity and consent.
- Tender creation.
- Offer comparison.
- Collateral selection.
- Underwriting disclosures.
- Payment schedules.
- Repayment.
- Refinancing.
- Restructuring.
- Recovery and dispute workflows.

#### Lender experience

- Tender discovery.
- Risk information.
- Offer creation.
- Syndicate participation.
- Tranche selection.
- Position portfolio.
- Secondary trading.
- Governance.

#### Governance experience

- Proposal creation.
- Risk reports.
- Voting.
- Timelock status.
- Execution evidence.

#### Operations console

- Reconciliation exceptions.
- Payment states.
- Bridge states.
- Oracle states.
- Incident controls.
- Treasury mandates.
- Privileged-action evidence.

### 18.3 Exit criteria

- Every signing screen explains asset movement and obligation.
- Provisional and final states are visually distinct.
- Users can inspect policy versions and transaction evidence.
- Restricted data is role-controlled.
- Operations actions require step-up authentication and audit.
- Accessibility and localization baselines pass.

---

## 19. Phase 12 — Integrated Adversarial Verification and Economic Simulation

### 19.1 Objectives

- Validate the complete system under hostile and stressed conditions.
- Prove cross-domain invariants.
- Identify hidden feedback loops.

### 19.2 Required campaigns

#### Contract campaigns

- Stateful loan lifecycle fuzzing.
- Offer replay.
- Position overissuance.
- Collateral double release.
- UFT mint and burn integrity.
- Governance bypass.
- Bridge replay.
- Refinancing double lien.

#### Service campaigns

- Duplicate commands.
- Duplicate events.
- Reordered events.
- Database failover.
- Queue replay.
- Provider callback forgery.
- Reconciliation mismatch.

#### Economic campaigns

- UFT decline of 30%, 50%, 80%, and 95%.
- Liquidity collapse.
- Collateral liquidation cascade.
- Correlated unsecured defaults.
- Syndicate first-loss exhaustion.
- Insurance-reserve impairment.
- Treasury depletion.
- Governance concentration.

#### Compound campaigns

- Oracle manipulation plus UFT reflexivity.
- Bridge compromise plus UFT-backed loans.
- Identity fraud plus unsecured credit.
- Card chargeback after apparent repayment.
- Insider treasury theft plus accounting concealment.
- Malicious upgrade plus governance capture.

### 19.3 Exit criteria

- All existential and critical scenarios have tested controls.
- Every launch-blocking invariant has executable coverage.
- Economic losses remain within approved tolerances.
- Recovery procedures complete successfully.
- No unresolved critical security finding remains.

---

## 20. Phase 13 — Testnet, Pilot, Audit, and Production Rehearsal

### 20.1 Environment sequence

```text
Local deterministic networks
→ Shared development networks
→ Internal testnet
→ Public testnet
→ Restricted economic pilot
→ Staging with production topology
→ Pre-production rehearsal
```

### 20.2 Testnet stages

#### Stage A — Protocol testnet

- Kernel.
- UFT.
- Same-chain loans.
- Collateral.
- Repayment.

#### Stage B — Advanced product testnet

- Syndication.
- NFT collateral.
- Variable rates.
- Installments.
- Refinancing.

#### Stage C — External integration testnet

- Fiat sandbox.
- Card sandbox.
- Identity providers.
- Underwriting models.
- Cross-chain adapters.

#### Stage D — Adversarial public testnet

- Bug bounty.
- Economic attacks.
- Governance simulation.
- Bridge failure drills.

### 20.3 Audit sequence

1. Architecture and specification audit.
2. Kernel and UFT contract audit.
3. Loan and collateral audit.
4. Governance and bridge audit.
5. Payment and accounting audit.
6. Identity and privacy assessment.
7. Infrastructure penetration test.
8. Integrated re-audit of changes.

### 20.4 Production rehearsal

The rehearsal SHALL include:

- Genesis UFT distribution simulation.
- Contract deployment.
- Role transfer.
- Treasury initialization.
- Oracle and provider setup.
- Indexer bootstrap.
- Ledger opening balances.
- Loan origination.
- Repayment.
- Liquidation.
- Cross-chain recovery.
- Incident pause.
- Rollback or compensation.
- Disaster recovery.

### 20.5 Exit criteria

- Audit findings are resolved or formally accepted below critical severity.
- Bug bounty is active.
- Production artifacts are signed and reproducible.
- Restore procedures are tested.
- Privileged roles are transferred to production governance structures.
- Legal and compliance launch gates are approved.
- Production-readiness review passes.

---

## 21. Phase 14 — Controlled Mainnet Launch

### 21.1 Launch strategy

Mainnet activation SHALL be progressive.

#### Launch ring 0 — Technical activation

- Contracts deployed.
- No public originations.
- Read-only verification.
- Supply, role, and backing reconciliation.

#### Launch ring 1 — Internal and trusted participants

- Very low limits.
- Selected assets.
- Same-chain collateralized loans.
- Manual oversight.

#### Launch ring 2 — Restricted public beta

- Increased users.
- Limited syndication.
- Selected identity and payment providers.
- Strict exposure caps.

#### Launch ring 3 — Advanced capabilities

- NFT collateral.
- Variable rates.
- Cross-chain.
- Fiat and card.
- Refinancing.
- Secondary positions.

#### Launch ring 4 — Broad ecosystem

- Wider assets.
- Higher limits.
- Expanded jurisdictions.
- Broader governance participation.

### 21.2 Launch controls

- Asset-specific debt ceilings.
- User exposure limits.
- Bridge limits.
- Payment limits.
- UFT collateral limits.
- Insurance capacity.
- Manual review thresholds.
- Monitoring escalation.

### 21.3 Launch stop conditions

Launch progression stops when:

- Accounting does not reconcile.
- Wrapped UFT backing differs.
- Oracle divergence exceeds tolerance.
- Payment finality is uncertain.
- Critical provider is unstable.
- Security incident is unresolved.
- Insurance coverage falls below threshold.
- Governance or signing authority is uncertain.

---

## 22. Phase 15 — Stabilization, Decentralization, and Expansion

### 22.1 Stabilization

- Production defect reduction.
- Capacity tuning.
- Cost optimization.
- Incident review.
- Reconciliation automation.
- User-support improvement.

### 22.2 Progressive decentralization

- Wider UFT distribution.
- Governance delegation.
- Risk-council elections.
- Treasury transparency.
- Additional oracle and bridge providers.
- Independent infrastructure operators.

### 22.3 Expansion

- Additional chains.
- Additional fiat rails.
- New collateral classes.
- New credit products.
- New jurisdictions.
- Institutional participation.
- Protocol integrations.

Expansion SHALL preserve active-loan immutability and use versioned policies.

---

## 23. Parallel Agent Orchestration Model

### 23.1 Agent classes

Unified may use multiple AI agents and human teams in parallel.

Recommended agent roles:

```text
Architecture Agent
Protocol Agent
Formal Verification Agent
Go Services Agent
Accounting Agent
Payments Agent
Identity and Underwriting Agent
Cross-Chain Agent
Frontend Agent
Infrastructure Agent
Security Audit Agent
Economic Simulation Agent
Integration Agent
Documentation and Traceability Agent
```

### 23.2 Agent task contract

Every agent instruction SHALL contain:

```text
Task identifier
Objective
Owned directories
Read-only directories
Forbidden directories
Governing specifications
Required interfaces
Required invariants
Required tests
Deliverables
Integration target
Stop conditions
Completion report format
```

### 23.3 Branch model

Agent branches SHALL use:

```text
agent/<agent-name>/<task-id>
```

Examples:

```text
agent/protocol/UNI-KERNEL-001
agent/accounting/UNI-LEDGER-004
agent/frontend/UNI-WEB-018
```

Agents SHALL NOT push directly to:

- `main`.
- `release/*`.
- Protected integration branches.

### 23.4 Directory ownership

An agent may modify only explicitly owned paths.

Cross-boundary changes require:

- An RFC or interface-change request.
- Approval from both domain owners.
- Schema compatibility checks.
- Integration-agent coordination.

### 23.5 Required agent completion report

Each report SHALL include:

```text
Task ID
Branch
Commit SHAs
Changed files
Implemented behavior
Tests executed
Test results
Invariant mappings
Threat mappings
Schema changes
Migration changes
Dependencies introduced
Known limitations
Integration instructions
Open questions
```

### 23.6 Agent stop conditions

An agent SHALL stop and report rather than invent behavior when:

- Governing specifications conflict.
- Required authority is undefined.
- A financial invariant would be weakened.
- A schema change is breaking and unapproved.
- A security control is missing.
- An upstream interface is ambiguous.
- A requested action crosses forbidden ownership.

### 23.7 Independent audit agents

Audit agents SHALL review entire defined scopes independently rather than sharing conclusions prematurely.

Audit reports SHALL identify:

- Finding.
- Severity.
- Evidence.
- Affected invariant.
- Exploit or failure path.
- Recommended remediation.
- Confidence.

### 23.8 Integration agent

The integration agent owns:

- Dependency-order merges.
- Conflict resolution coordination.
- Integrated test execution.
- Architecture conformance.
- Cross-workstream traceability.
- Integration verdicts.

The integration agent SHALL NOT silently rewrite domain behavior to make merges pass.

---

## 24. Integration Cadence

### 24.1 Daily integration

- Schema generation.
- Compilation.
- Unit tests.
- Architecture checks.
- Dependency checks.

### 24.2 Twice-weekly integration

- Cross-service contracts.
- Event compatibility.
- Database migration compatibility.
- Contract-service integration.

### 24.3 Phase integration

At every phase gate:

- Full monorepo build.
- Full test matrix.
- Invariant suite.
- Security scans.
- Economic regression simulations.
- Infrastructure validation.
- Documentation traceability.

### 24.4 Integration branch procedure

```text
Create integration/<phase>
→ Merge workstreams in dependency order
→ Resolve declared interface conflicts
→ Run domain verification
→ Run integrated verification
→ Produce phase verdict
→ Promote only after approval
```

---

## 25. Definition of Ready

A work item is ready only when:

- Objective is concrete.
- Owner is assigned.
- Dependencies are identified.
- Governing specifications are cited.
- Interface inputs and outputs are defined.
- Invariants are listed.
- Threats are mapped.
- Acceptance criteria are testable.
- Required fixtures or mocks exist.

---

## 26. Definition of Done

A work item is done only when:

- Code or artifact is complete.
- Tests pass.
- Invariants are exercised.
- Threat controls are implemented.
- Accounting treatment is included where applicable.
- Documentation is updated.
- Migrations are reversible or compensatable.
- Telemetry exists.
- Integration passes.
- No unresolved critical finding remains.
- Completion report is accepted.

---

## 27. Acceptance Evidence Matrix

Every major deliverable SHALL produce applicable evidence:

| Evidence | Contracts | Services | Apps | Infrastructure | Models |
|---|---:|---:|---:|---:|---:|
| Unit tests | Yes | Yes | Yes | Yes | Yes |
| Integration tests | Yes | Yes | Yes | Yes | Yes |
| Invariant tests | Yes | Yes | Limited | Yes | Yes |
| Threat mapping | Yes | Yes | Yes | Yes | Yes |
| Schema compatibility | Yes | Yes | Yes | Yes | Yes |
| Performance results | Yes | Yes | Yes | Yes | Yes |
| Recovery behavior | Yes | Yes | Limited | Yes | Yes |
| Documentation | Yes | Yes | Yes | Yes | Yes |
| Audit trail | Yes | Yes | Yes | Yes | Yes |

---

## 28. Program Metrics

### 28.1 Delivery metrics

- Work items accepted.
- Cycle time.
- Integration frequency.
- Reopened work.
- Cross-boundary change requests.

### 28.2 Quality metrics

- Test pass rate.
- Mutation score.
- Fuzz executions.
- Invariant coverage.
- Escaped defects.
- Reconciliation differences.

### 28.3 Security metrics

- Findings by severity.
- Mean remediation time.
- Privileged actions.
- Dependency vulnerabilities.
- Secret exposures.
- Bug-bounty reports.

### 28.4 Economic metrics

- UFT circulating supply.
- Vesting release.
- Staking coverage.
- Insurance coverage.
- Treasury runway.
- UFT collateral exposure.
- Bridge exposure.
- Loan losses.

### 28.5 Operational metrics

- Availability.
- Event lag.
- Chain-indexing lag.
- Payment settlement time.
- Reconciliation completion.
- Recovery time.
- Backup-restore success.

Metrics SHALL inform decisions but SHALL NOT be manipulated to conceal risk.

---

## 29. Change Control

### 29.1 Change classes

```text
Class A — Documentation clarification
Class B — Compatible implementation change
Class C — Interface or schema evolution
Class D — Economic or risk parameter change
Class E — Constitutional or active-agreement-impacting change
```

### 29.2 Approval

- Class A: Domain owner.
- Class B: Domain owner plus reviewer.
- Class C: Architecture council plus affected owners.
- Class D: Risk authority, economic authority, and governance path.
- Class E: Constitutional amendment process and highest review threshold.

### 29.3 No silent scope expansion

A new capability SHALL enter the program through:

- RFC.
- Domain mapping.
- Threat analysis.
- Invariant mapping.
- Accounting treatment.
- Dependency update.
- Acceptance criteria.

---

## 30. Release Readiness Review

The release authority SHALL review:

- Functional completion.
- Security findings.
- Formal verification.
- Accounting reconciliation.
- UFT supply and backing.
- Treasury and reserve solvency.
- Infrastructure readiness.
- Key and role custody.
- Legal and compliance readiness.
- User-support readiness.
- Incident and rollback readiness.

The verdict SHALL be one of:

```text
READY
READY WITH RESTRICTIONS
NOT READY
```

Restrictions must be enforceable through code, configuration, debt ceilings, allowlists, or operational controls.

---

## 31. Launch-Blocking Program Conditions

Unified SHALL NOT enter unrestricted production while any known path permits:

1. UFT supply above the genesis cap.
2. Unbacked wrapped UFT.
3. Duplicate loan, payment, position, or bridge execution.
4. Active-loan economic mutation.
5. Premature collateral release.
6. Unbalanced or editable accounting.
7. Unauthenticated provider settlement.
8. Governance or timelock bypass.
9. Refinancing double liens.
10. Lender-position overissuance.
11. Unfunded rewards or insurance promises.
12. Public leakage of restricted identity or financial data.
13. Unrecoverable production signing authority.
14. Untested disaster recovery.
15. Unresolved existential or critical security findings.
16. Unknown ownership of reconciliation differences.
17. Cross-chain recovery that can unlock value twice.
18. A frontend or derived database acting as financial authority.
19. Unreviewed production artifacts.
20. A compliance prohibition applicable to the planned launch scope.

---

## 32. Immediate Implementation Sequence

After approval of this plan, execution SHALL begin with the following sequence:

```text
1. Create the canonical Unified monorepo.
2. Import all foundational specifications.
3. Establish CODEOWNERS and directory boundaries.
4. Lock toolchains.
5. Create command, event, money, asset, and loan schemas.
6. Generate Solidity, Go, TypeScript, and Python bindings.
7. Create contract and service templates.
8. Build CI architecture gates.
9. Create local infrastructure and deterministic chains.
10. Implement UFT and protocol-kernel skeletons.
11. Implement accounting-ledger skeleton.
12. Implement chain indexer and event archive skeleton.
13. Establish invariant and threat traceability.
14. Open Phase 2 parallel agent branches.
15. Integrate through integration/phase-2.
```

---

## 33. First Parallel Agent Allocation

### Agent A — Repository and Toolchain

Owns:

- Root repository files.
- Toolchain locks.
- Build orchestration.
- CI skeleton.
- Architecture linting.

### Agent B — Shared Schemas

Owns:

- Protobuf schemas.
- Universal identifiers.
- Money and asset types.
- Command and event envelopes.
- Generated bindings.

### Agent C — Solidity Protocol Skeleton

Owns:

- Protocol package structure.
- Interfaces.
- Shared types.
- Errors.
- Events.
- Foundry configuration.

### Agent D — UFT Foundations

Owns:

- UFT token.
- Allocation vault interfaces.
- Vesting interfaces.
- Supply invariants.

### Agent E — Go Service Template

Owns:

- Canonical service layout.
- Domain/application/ports structure.
- Outbox and inbox interfaces.
- Observability baseline.

### Agent F — Accounting Ledger Skeleton

Owns:

- Ledger domain.
- Journal model.
- Account types.
- Posting invariants.
- Database migrations.

### Agent G — Infrastructure Baseline

Owns:

- Local development stack.
- PostgreSQL.
- Event broker.
- Object storage.
- Local EVM chains.
- Secrets placeholders.

### Agent H — Security and Verification Harness

Owns:

- Invariant IDs.
- Threat traceability.
- Static analysis.
- Fuzzing templates.
- CI security gates.

### Agent I — Integration and Audit

Owns:

- `integration/phase-1` and `integration/phase-2` coordination.
- Independent conformance review.
- Integration verdict.

---

## 34. Program Deliverables

The implementation program SHALL ultimately deliver:

- Production smart contracts.
- Financial and operational services.
- Experience applications.
- UFT token and economic modules.
- Governance and treasury controls.
- Identity and underwriting systems.
- Payment and cross-chain integrations.
- Accounting and reconciliation.
- Security and formal-verification evidence.
- Economic simulation reports.
- Deployment and recovery infrastructure.
- Operational runbooks.
- Audit reports.
- Testnet and launch evidence.
- Production-readiness verdict.

---

## 35. Final Program Rule

Unified SHALL be built as one coherent financial system, not as a collection of independently impressive components.

Every parallel workstream, agent, service, contract, model, and application must converge on:

- One constitutional framework.
- One domain language.
- One universal loan model.
- One accounting truth.
- One UFT supply model.
- One canonical authority for each fact.
- One traceable security model.
- One controlled release process.

**Complexity is accepted. Incoherence is not.**
