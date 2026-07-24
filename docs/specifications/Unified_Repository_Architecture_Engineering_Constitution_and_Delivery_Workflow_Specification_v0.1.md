# Unified Repository Architecture, Engineering Constitution, and Delivery Workflow Specification v0.1

**Status:** Foundational Draft  
**Classification:** Binding Engineering Specification  
**Version:** 0.1  
**Applies to:** All Unified source code, smart contracts, services, applications, infrastructure, schemas, tests, releases, human contributors, AI agents, vendors, and deployment environments.

---

## 1. Purpose

This specification converts Unified's constitutional, domain, protocol, accounting, security, data, and deployment architecture into an enforceable engineering system.

It defines:

- Repository topology.
- Technology boundaries.
- Package and service ownership.
- Contract and schema governance.
- Development workflow.
- Testing hierarchy.
- Continuous integration and delivery gates.
- Security and release controls.
- Multi-agent collaboration rules.
- Architecture-conformance automation.
- Documentation and decision records.
- Environment and deployment promotion.
- Incident, rollback, and recovery procedures.

This document governs how Unified is built. It does not replace the economic or protocol specifications. Implementations must conform to all higher-order specifications.

---

## 2. Governing Sources

The repository and engineering system SHALL conform to:

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

When implementations conflict with these sources, the implementation is defective.

---

## 3. Engineering Constitution

### 3.1 Specification before implementation

No material financial capability SHALL be implemented without:

- A named domain owner.
- A documented state model.
- An interface or schema contract.
- Threat analysis.
- Invariant mapping.
- Accounting treatment where value is affected.
- Recovery behavior.
- Test obligations.

### 3.2 One canonical owner

Every mutable domain concept SHALL have one canonical owner.

Examples:

- Loan agreements: protocol kernel.
- Posted journals: accounting ledger.
- Provider settlement evidence: payment orchestration and provider adapter boundary.
- Identity documents: restricted identity vault.
- UFT canonical supply: UFT token contract.
- Wrapped UFT issuance: canonical bridge hub plus verified satellite adapters.

Other modules may project or cache canonical data but may not redefine it.

### 3.3 No hidden financial state

Financial rights, liabilities, custody, fees, reserves, rewards, and losses SHALL be represented by explicit state and auditable events.

No material balance may exist only in:

- Frontend state.
- Cache state.
- Analytics output.
- Log text.
- Manual spreadsheet.
- Unversioned provider metadata.

### 3.4 Active-agreement immutability

Code changes, deployments, registry updates, and configuration changes SHALL NOT silently change active loan economics.

Active agreements SHALL bind to exact:

- Contract implementation versions.
- Policy versions.
- Schema versions.
- Fee versions.
- Oracle policies.
- Settlement policies.
- Accounting rules.

### 3.5 Separation of intent and authority

No component may both invent and authorize a high-risk financial action.

Examples:

- Transaction builders cannot sign.
- Signers cannot construct arbitrary intent.
- Payment adapters cannot directly reduce debt.
- Indexers cannot release collateral.
- UI applications cannot finalize settlements.
- Governance proposal authors cannot bypass quorum and timelock.

### 3.6 Immutable evidence

Production evidence SHALL be append-only or cryptographically protected, including:

- Contract events.
- Posted journals.
- Provider callbacks.
- Governance actions.
- Release attestations.
- Privileged access logs.
- Incident records.

Corrections SHALL be represented by linked reversal, compensation, or superseding records.

### 3.7 Safe failure

Every module SHALL define behavior for:

- Dependency timeout.
- Duplicate request.
- Partial execution.
- Stale data.
- Conflicting evidence.
- Reordered events.
- Provider outage.
- Chain reorganization.
- Recovery retry.

Unknown state must fail closed for value movement while preserving repayment and recovery rights where safe.

### 3.8 Reproducibility

Every production artifact SHALL be reproducible from:

- Reviewed source revision.
- Locked dependencies.
- Declared toolchain.
- Versioned build configuration.
- Signed provenance.

### 3.9 No direct production mutation

Production databases, ledgers, contract storage, and queues SHALL NOT be modified manually except through an approved, audited emergency procedure.

### 3.10 Security is a release property

Passing functional tests is insufficient. A release is valid only when applicable security, invariant, migration, reconciliation, and operational gates pass.

---

## 4. Technology Constitution

### 4.1 Smart contracts

Primary language: **Solidity**.

Required toolchain:

- Foundry for build, testing, fuzzing, invariants, scripts, and deployment verification.
- Slither or equivalent static analysis.
- Symbolic or formal tools selected per critical contract.
- OpenZeppelin-compatible standards where appropriate, without inheriting unsafe authority by default.

Smart-contract production code SHALL NOT depend on unreviewed remote imports.

### 4.2 Financial and domain services

Primary language: **Go**.

Go services SHALL be used for:

- Origination.
- Servicing.
- Accounting.
- Payments.
- Reconciliation.
- Underwriting coordination.
- Cross-chain coordination.
- Indexing.
- Risk services.
- Governance operations.
- UFT off-chain economics.

Backend financial logic SHALL NOT be implemented in TypeScript or Node.js.

### 4.3 Experience applications

Primary language: **TypeScript**.

Frameworks may include:

- React.
- Next.js.
- React Native where mobile is introduced.

Frontend code SHALL NOT become the source of financial truth.

### 4.4 Machine learning and quantitative research

Primary language: **Python** for model research, simulations, and offline analytics.

Production underwriting decisions SHALL be served behind versioned interfaces and signed decision attestations. Research notebooks SHALL NOT directly operate production credit decisions.

### 4.5 Interface contracts

Primary interface formats:

- Protobuf for internal service APIs and domain events.
- OpenAPI generated from canonical gateway definitions for public HTTP APIs.
- Solidity ABI and typed contract bindings for chain interactions.
- JSON Schema only where external integration demands it.

A schema must have one source definition and generated derivatives.

### 4.6 Data stores

Default operational database: PostgreSQL.

Additional systems may include:

- Durable event broker.
- Redis for non-canonical cache and coordination.
- Object storage for encrypted evidence.
- Search engine for marketplace discovery.
- Analytical warehouse for reporting and risk analysis.

No cache SHALL be treated as canonical financial storage.

### 4.7 Infrastructure

Infrastructure SHALL be managed as code.

Preferred tools:

- Terraform or OpenTofu.
- Kubernetes for service orchestration where justified.
- Helm or equivalent package management.
- GitOps-based deployment reconciliation.
- HSM or managed key custody for production signing.

### 4.8 Toolchain pinning

Tool versions SHALL be pinned through repository-controlled configuration.

Updates require:

- Compatibility review.
- Security review.
- Reproducibility verification.
- CI validation.

---

## 5. Monorepo Architecture

The canonical repository SHALL use the following top-level structure:

```text
unified/
├── README.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CODEOWNERS
├── LICENSES/
├── .github/
├── .mise.toml
├── go.work
├── pnpm-workspace.yaml
├── turbo.json
├── buf.yaml
├── Makefile
│
├── constitution/
├── docs/
├── adr/
├── rfcs/
│
├── protocol/
├── services/
├── apps/
├── packages/
├── schemas/
├── models/
├── infrastructure/
├── deployments/
├── operations/
├── security/
├── simulations/
├── tests/
├── scripts/
└── tools/
```

The repository SHALL be treated as one coordinated product with separately owned components.

---

## 6. Documentation Structure

### 6.1 Constitution directory

```text
constitution/
├── UNIFIED_CONSTITUTION.md
├── ENGINEERING_CONSTITUTION.md
├── PROTOCOL_INVARIANTS.md
└── CHANGE_CONTROL.md
```

Constitutional files require the highest review class.

### 6.2 Architecture documents

```text
docs/architecture/
├── domain-model/
├── loan-model/
├── accounting/
├── tokenomics/
├── threat-model/
├── formal-verification/
├── smart-contract-api/
├── data-and-events/
├── system-topology/
└── repository-engineering/
```

### 6.3 Architecture Decision Records

Every material decision SHALL use an ADR.

ADR states:

```text
PROPOSED
ACCEPTED
SUPERSEDED
DEPRECATED
REJECTED
```

Each ADR SHALL include:

- Context.
- Decision.
- Alternatives.
- Consequences.
- Security impact.
- Migration impact.
- Active-agreement impact.
- Rollback strategy.

### 6.4 Requests for Comments

Cross-domain changes SHALL begin as RFCs.

An RFC is required for:

- New protocol module.
- New financial product.
- New event family.
- New chain or bridge.
- New payment provider.
- New identity or underwriting provider.
- New governance authority.
- Material schema change.
- New production technology.
- Service extraction.

---

## 7. Smart-Contract Repository Structure

```text
protocol/
├── foundry.toml
├── remappings.txt
├── src/
│   ├── kernel/
│   ├── tenders/
│   ├── offers/
│   ├── loans/
│   ├── funding/
│   ├── positions/
│   ├── collateral/
│   ├── interest/
│   ├── schedules/
│   ├── payments/
│   ├── liquidation/
│   ├── refinancing/
│   ├── insurance/
│   ├── identity/
│   ├── underwriting/
│   ├── crosschain/
│   ├── uft/
│   ├── governance/
│   ├── treasury/
│   ├── registries/
│   ├── adapters/
│   ├── libraries/
│   ├── interfaces/
│   ├── types/
│   └── errors/
├── test/
│   ├── unit/
│   ├── integration/
│   ├── invariant/
│   ├── fork/
│   ├── adversarial/
│   └── regression/
├── script/
├── deployments/
├── formal/
└── audit/
```

### 7.1 Contract package rule

Each contract package SHALL contain:

- Interfaces.
- Types.
- Errors.
- Events.
- Implementation.
- Unit tests.
- Invariant tests where applicable.
- Deployment or initialization script.
- NatSpec documentation.
- Threat-model references.
- Formal-property references.

### 7.2 Upgrade boundary

Upgradeable contracts SHALL be exceptional, not default.

Every upgradeable contract SHALL document:

- Why immutability is insufficient.
- Upgrade authority.
- Timelock.
- Storage-layout policy.
- Active-agreement compatibility.
- Emergency behavior.
- Rollback limitations.

### 7.3 Contract size and responsibility

A contract SHALL have one bounded responsibility.

A contract that combines custody, governance, accounting, and arbitrary upgrade authority is prohibited.

### 7.4 Contract dependency rule

Protocol packages may depend only on approved lower-level packages.

Illustrative dependency direction:

```text
types/errors/interfaces
        ↓
libraries
        ↓
registries and policy interfaces
        ↓
policy implementations
        ↓
loan and custody modules
        ↓
coordinators and factories
```

Circular dependencies are prohibited.

---

## 8. Go Service Template

Every production Go service SHALL follow:

```text
services/<service-name>/
├── README.md
├── go.mod
├── cmd/
│   ├── server/
│   ├── worker/
│   └── migrate/
├── internal/
│   ├── api/
│   ├── application/
│   ├── domain/
│   ├── policy/
│   ├── ports/
│   ├── store/
│   ├── eventbus/
│   ├── consumer/
│   ├── workflow/
│   ├── reconciliation/
│   ├── observability/
│   └── config/
├── proto/<domain>/v1/
├── migrations/
├── testdata/
├── tests/
│   ├── integration/
│   ├── contract/
│   └── adversarial/
└── deploy/
```

### 8.1 Layer rules

- `domain` may not import infrastructure.
- `application` coordinates use cases and domain rules.
- `ports` defines dependency interfaces.
- `store`, `eventbus`, and provider clients implement ports.
- `api` validates transport input but does not contain domain policy.
- `consumer` processes events idempotently.
- `workflow` owns durable multi-step orchestration.

### 8.2 Database ownership

Each service or bounded module owns its schema and migrations.

A service SHALL NOT query another service's private tables.

Cross-service reads SHALL use:

- Public API.
- Published event.
- Approved replicated read model.

### 8.3 Migration naming

```text
migrations/
├── 001_create_accounts.up.sql
├── 001_create_accounts.down.sql
├── 002_add_status_index.up.sql
└── 002_add_status_index.down.sql
```

Production migrations SHALL be:

- Forward compatible.
- Backward compatible during rollout.
- Reversible where technically safe.
- Tested against representative data.
- Accompanied by reconciliation checks.

---

## 9. Application Repository Structure

```text
apps/
├── web/
├── operations-console/
├── governance/
├── developer-portal/
└── mobile/
```

Each app SHALL separate:

```text
src/
├── app/
├── features/
├── entities/
├── shared/
├── generated/
├── security/
└── telemetry/
```

### 9.1 Frontend financial restrictions

Frontend applications SHALL NOT:

- Calculate canonical debt independently.
- Declare payment finality.
- Infer collateral release authority.
- Create unsigned economic terms.
- Store private signing keys.
- hide risk disclosures.

Displayed financial data SHALL identify:

- Source.
- Observation time.
- Finality.
- Currency and precision.
- Whether it is derived.

### 9.2 Wallet transaction safety

Every signing flow SHALL display:

- Contract.
- Chain.
- Function.
- Asset movement.
- Fees.
- Approval scope.
- Expiration.
- Reversibility.
- Human-readable consequences.

---

## 10. Shared Packages

```text
packages/
├── domain-identifiers/
├── money/
├── fixed-point/
├── contract-bindings/
├── api-client/
├── event-client/
├── auth-client/
├── observability/
├── cryptography/
├── validation/
├── feature-flags/
├── design-system/
└── test-fixtures/
```

Shared packages SHALL contain reusable primitives, not hidden domain services.

### 10.1 Prohibited package patterns

- Database access hidden in generic utility packages.
- Cross-domain business logic in shared libraries.
- Direct environment-variable reads throughout domain code.
- Untyped event payloads.
- Floating-point money calculations.
- Generic administrative bypass helpers.

---

## 11. Schema Repository

```text
schemas/
├── proto/
│   ├── common/v1/
│   ├── marketplace/v1/
│   ├── loan/v1/
│   ├── funding/v1/
│   ├── collateral/v1/
│   ├── payment/v1/
│   ├── accounting/v1/
│   ├── identity/v1/
│   ├── underwriting/v1/
│   ├── uft/v1/
│   ├── governance/v1/
│   └── crosschain/v1/
├── openapi/
├── json-schema/
├── solidity-abi/
└── compatibility/
```

### 11.1 Compatibility rules

Breaking changes require a new major schema version.

Within a version:

- Field numbers cannot be reused.
- Removed fields remain reserved.
- Enum meanings cannot change.
- Financial units cannot change.
- Optionality cannot become mandatory without migration.
- Default behavior cannot alter active agreements.

### 11.2 Schema gates

CI SHALL run:

- Formatting.
- Linting.
- Breaking-change detection.
- Generated-code drift checks.
- Example payload validation.
- Privacy-field classification checks.

---

## 12. Money and Precision Rules

### 12.1 No floating point

Financial calculations SHALL use:

- Integer smallest units.
- Fixed-point decimal libraries.
- Explicit rounding modes.

### 12.2 Unit metadata

Every amount SHALL identify:

- Asset.
- Chain or jurisdiction where relevant.
- Decimal precision.
- Rounding mode.
- Valuation timestamp where converted.

### 12.3 Deterministic calculations

The same input and policy version SHALL produce the same result across:

- Contracts.
- Go services.
- Simulations.
- User interfaces.

Cross-language golden test vectors SHALL be maintained.

---

## 13. Event Engineering Rules

Every event producer SHALL implement:

- Transactional outbox.
- Deterministic event ID.
- Aggregate version.
- Correlation and causation IDs.
- Schema version.
- Privacy classification.
- Authority classification.

Every event consumer SHALL implement:

- Durable inbox.
- Duplicate detection.
- Version check.
- Retry policy.
- Dead-letter handling.
- Replay support.
- Idempotent effects.

Events SHALL be immutable.

---

## 14. API Engineering Rules

### 14.1 Commands

State-changing commands SHALL include:

- Command ID.
- Idempotency key.
- Actor identity.
- Expected aggregate version.
- Expiration where appropriate.
- Signature where appropriate.

### 14.2 Queries

Queries SHALL identify whether the response is:

- Canonical.
- Derived.
- Provisional.
- Final.
- Stale.

### 14.3 Errors

Errors SHALL be typed and stable.

A financial error response SHALL distinguish:

- Authorization failure.
- Validation failure.
- Policy rejection.
- Concurrency conflict.
- Dependency unavailability.
- Finality pending.
- Reconciliation hold.
- Security hold.

---

## 15. Testing Constitution

### 15.1 Test hierarchy

Unified SHALL maintain:

1. Unit tests.
2. Domain-property tests.
3. Contract tests.
4. Integration tests.
5. Stateful invariant tests.
6. End-to-end workflow tests.
7. Fork and chain simulation tests.
8. Provider sandbox tests.
9. Adversarial tests.
10. Economic simulations.
11. Disaster-recovery tests.
12. Production verification tests.

### 15.2 Coverage rule

Line coverage is informational, not sufficient.

Critical modules SHALL have explicit coverage of:

- State transitions.
- Authorization.
- Invariants.
- Failure recovery.
- Duplicate execution.
- Time boundaries.
- Precision and rounding.
- Upgrade and migration behavior.

### 15.3 Golden scenarios

Canonical end-to-end scenarios SHALL include:

- Single-lender collateralized loan.
- Syndicated tranche loan.
- NFT-backed loan.
- Variable-rate amortizing loan.
- Unsecured verified loan.
- Card repayment with chargeback.
- Fiat disbursement and reconciliation.
- Cross-chain collateral loan.
- Partial liquidation.
- Full liquidation and borrower surplus.
- Refinancing.
- Secondary-market lender transfer.
- UFT staking and slashing.
- Governance proposal and timelock.
- Wrapped UFT issue and redemption.

### 15.4 Regression tests

Every production incident and confirmed vulnerability SHALL produce a permanent regression test where technically possible.

---

## 16. Smart-Contract Verification Gates

A contract change affecting value movement SHALL pass:

- Compilation with pinned compiler.
- Unit tests.
- Fuzz tests.
- Stateful invariant tests.
- Static analysis.
- Gas-delta review.
- Storage-layout comparison where upgradeable.
- ABI compatibility check.
- Access-control analysis.
- Event compatibility check.
- Formal-property mapping.
- Deployment-script simulation.

Critical contracts also require:

- Independent review.
- Symbolic or formal verification where selected.
- Mainnet-fork or production-state rehearsal.
- External audit before unrestricted deployment.

---

## 17. Continuous Integration Pipeline

The CI pipeline SHALL contain separate jobs for:

```text
Detect Changes
Repository Conformance
Documentation and ADRs
Schema Lint and Compatibility
Solidity Build and Test
Solidity Invariants
Solidity Static Analysis
Go Format and Vet
Go Unit Tests
Go Integration Tests
TypeScript Lint
TypeScript Typecheck
TypeScript Tests
Python Model Tests
Infrastructure Validation
Container Build
Dependency and License Scan
Secret Scan
SBOM Generation
Artifact Provenance
End-to-End Tests
Economic Simulations
Release Readiness
```

### 17.1 Required branch protection

Protected branches SHALL require:

- Passing required CI.
- Required code-owner reviews.
- Resolved review threads.
- Signed commits or verified authorship where configured.
- No unresolved critical security findings.
- No architecture-conformance violations.

### 17.2 Merge queue

Changes to the main integration branch SHALL use a merge queue or equivalent serialization to ensure the tested revision equals the merged revision.

---

## 18. Architecture-Conformance Automation

CI SHALL enforce:

- No forbidden cross-domain imports.
- No service access to another service's private migrations.
- No TypeScript backend service logic in financial domains.
- No direct production database scripts outside approved operations paths.
- No floating-point financial types.
- No unversioned event schemas.
- No contract interface drift without compatibility review.
- No generated-code modifications without regenerated source.
- No secret material committed.
- No unrestricted administrative withdrawal method.
- No post-genesis UFT mint path.
- No non-idempotent external callback handler.

Architecture tests SHALL fail the build, not merely warn.

---

## 19. Dependency Governance

### 19.1 Dependency admission

A new dependency requires review of:

- Maintenance status.
- License.
- Known vulnerabilities.
- Transitive dependencies.
- Upgrade behavior.
- Reproducibility.
- Security criticality.
- Replacement strategy.

### 19.2 Lockfiles

All ecosystems SHALL use committed lockfiles where supported.

### 19.3 Update policy

Automated dependency updates may open changes but SHALL NOT bypass review.

High-risk dependency updates require:

- Changelog review.
- Differential testing.
- Security assessment.
- Rollback plan.

---

## 20. Source-Code Ownership

`CODEOWNERS` SHALL map every critical path to accountable owners.

Minimum ownership classes:

- Protocol kernel.
- UFT and governance.
- Custody and collateral.
- Accounting.
- Payments.
- Identity and privacy.
- Underwriting.
- Cross-chain.
- Infrastructure and signing.
- Frontend signing experience.
- Security and formal verification.

No person or agent should be the sole approver for all critical domains.

---

## 21. Branching Model

Canonical long-lived branches:

```text
main
integration/<release-or-phase>
release/<version>
hotfix/<incident>
```

Short-lived work branches:

```text
feature/<domain>/<change>
fix/<domain>/<change>
agent/<agent-name>/<task>
research/<topic>
```

### 21.1 Main branch

`main` SHALL represent releasable, verified source.

### 21.2 Integration branches

Complex parallel work SHALL integrate into a dedicated integration branch before merging to `main`.

### 21.3 No direct pushes

Direct pushes to protected branches are prohibited except under a documented break-glass process.

---

## 22. Pull Request Contract

Every pull request SHALL state:

- Problem.
- Scope.
- Domain owner.
- Architecture documents affected.
- Security impact.
- Accounting impact.
- Data and privacy impact.
- Migration impact.
- Active-agreement impact.
- Tests added.
- Rollback plan.
- Deployment plan.

High-risk changes SHALL include an invariant matrix.

---

## 23. Multi-Agent Engineering Workflow

Unified may use multiple AI agents and human engineers simultaneously.

### 23.1 Agent charter

Every agent SHALL receive:

- Named task.
- Owned directories.
- Read-only reference directories.
- Prohibited directories.
- Required outputs.
- Required tests.
- Integration contract.
- Stop conditions.

### 23.2 No overlapping write ownership

Two agents SHALL NOT concurrently own the same source file or migration unless explicitly coordinated.

### 23.3 Agent branches

Each agent works on an isolated branch:

```text
agent/<agent>/<workstream>
```

### 23.4 Agent completion report

Every agent SHALL produce:

- Commit identifiers.
- Files changed.
- Tests run.
- Results.
- Known limitations.
- Assumptions.
- Architecture deviations.
- Security findings.
- Integration instructions.

### 23.5 Agent authority restrictions

Agents SHALL NOT:

- Push directly to protected branches.
- Modify constitutional files without explicit assignment.
- Change economic parameters silently.
- weaken tests to obtain green CI.
- suppress security findings.
- introduce new dependencies without disclosure.
- alter generated files without source changes.
- deploy to production.

### 23.6 Independent audits

For critical milestones, independent agents SHALL audit the same integrated revision separately. Audit reports must identify the exact commit reviewed.

---

## 24. Integration Discipline

Integration SHALL occur in dependency order.

Illustrative sequence:

```text
Schemas and interfaces
→ Shared generated bindings
→ Protocol kernel
→ Domain services
→ Indexers and ledger adapters
→ Experience applications
→ Infrastructure
→ Integrated verification
```

Every merge into an integration branch SHALL be followed by scoped verification.

The completed branch SHALL then run the full repository gate.

---

## 25. Release Versioning

Unified uses semantic versioning with explicit protocol and application dimensions.

Examples:

```text
Protocol: 1.0.0
Services bundle: 1.4.2
Web application: 1.8.0
Schema family: loan.v1
Deployment release: unified-2026.09.0
```

A release manifest SHALL record exact versions of:

- Contracts.
- Policies.
- Services.
- Schemas.
- Apps.
- Infrastructure.
- Database migrations.
- Model versions.
- Provider adapters.

---

## 26. Environment Strategy

Required environments:

```text
local
unit-test
integration
security-test
simulation
testnet
staging
pre-production
production
recovery
```

Production credentials and keys SHALL never be used outside production-controlled environments.

Test environments SHALL use synthetic or anonymized data unless explicitly approved.

---

## 27. Deployment Promotion

A release SHALL be promoted through:

```text
Reviewed source
→ CI artifacts
→ Integration environment
→ Security environment
→ Testnet/provider sandbox
→ Staging
→ Pre-production rehearsal
→ Production canary
→ Progressive rollout
→ Post-deployment verification
```

Artifacts SHALL be promoted, not rebuilt independently at each stage.

---

## 28. Database Deployment Rules

Schema changes SHALL use expand-and-contract migration.

Sequence:

```text
Add compatible structure
→ Deploy dual-compatible code
→ Backfill
→ Reconcile
→ Switch reads/writes
→ Observe
→ Remove old structure in later release
```

Destructive migrations SHALL NOT be combined with first-use application changes.

---

## 29. Contract Deployment Rules

Every contract deployment SHALL include:

- Deterministic source revision.
- Compiler and optimization settings.
- Constructor or initializer arguments.
- Deployment address prediction where applicable.
- Bytecode verification.
- Ownership and role verification.
- Timelock verification.
- Registry registration.
- Event emission checks.
- Invariant smoke tests.
- Explorer verification.
- Release manifest update.

No production contract may remain with a temporary deployer as unintended administrator.

---

## 30. Configuration Governance

Configuration SHALL be classified:

```text
PUBLIC_NON_SENSITIVE
INTERNAL
RESTRICTED
SECRET
CONSTITUTIONAL_PARAMETER
```

Financial and risk parameters SHALL be versioned and auditable.

Changing a risk parameter SHALL identify whether it applies to:

- New loans only.
- Unactivated loans.
- Existing loans under an agreed dynamic policy.
- Operational routing only.

---

## 31. Secrets and Key Management

Secrets SHALL be stored in approved secret managers.

Production signing keys SHALL be HSM-backed or use equivalent protected custody.

Required controls:

- Key purpose separation.
- Least privilege.
- Rotation.
- Dual control for critical keys.
- Access logging.
- Recovery procedures.
- Revocation drills.

Secrets SHALL NOT appear in:

- Source code.
- CI logs.
- Test fixtures.
- Container images.
- Crash reports.
- Analytics events.

---

## 32. Observability Engineering

Every service SHALL provide:

- Structured logs.
- Metrics.
- Distributed traces.
- Health and readiness endpoints.
- Dependency status.
- Business-event counters.
- Security-event signals.

Financial telemetry SHALL include:

- Pending settlements.
- Reconciliation differences.
- Ledger posting failures.
- Duplicate command detections.
- Workflow timeouts.
- Oracle divergence.
- Bridge exposure.
- Collateral-health distributions.
- UFT supply and backing checks.

Sensitive data SHALL be redacted before telemetry export.

---

## 33. Security Review Classes

### Class A — Routine

Examples:

- Documentation.
- Non-financial UI styling.
- Internal development tooling.

### Class B — Domain

Examples:

- Marketplace behavior.
- Notifications.
- Search projections.

### Class C — Financial

Examples:

- Servicing.
- Interest.
- Payment allocation.
- Accounting.

### Class D — Custody and authority

Examples:

- Collateral vaults.
- UFT supply.
- Governance.
- Signing.
- Bridges.
- Treasury.

Class D requires the strongest review, verification, and deployment controls.

---

## 34. Release Gates

A production release SHALL NOT proceed with:

- Failing required tests.
- Unresolved critical or high security findings without approved exception.
- Unbalanced accounting scenarios.
- Unverified contract bytecode.
- Schema compatibility failures.
- Unreconciled migration results.
- Missing rollback or recovery procedure.
- Unreviewed privileged-role changes.
- Missing SBOM or artifact provenance.
- Unknown bridge backing discrepancy.
- UFT supply mismatch.
- Failed backup restoration rehearsal where applicable.

---

## 35. Exception Process

Exceptions SHALL be:

- Explicit.
- Time-bounded.
- Owned.
- Risk-assessed.
- Approved at the correct authority level.
- Logged.
- Monitored.
- Scheduled for removal.

Constitutional protections cannot be waived through ordinary engineering exceptions.

---

## 36. Incident and Hotfix Workflow

A hotfix SHALL follow:

```text
Incident declaration
→ Reproduction or evidence capture
→ Containment decision
→ Minimal fix branch
→ Focused tests
→ Security review
→ Release approval
→ Controlled deployment
→ Verification
→ Full regression follow-up
```

Emergency changes SHALL be merged back into all affected branches and documented in an incident report.

---

## 37. Rollback and Roll-Forward

Rollback is appropriate only when it preserves data and protocol consistency.

Where rollback is unsafe, Unified SHALL roll forward through:

- Compensating deployment.
- Migration correction.
- Workflow recovery.
- Event replay.
- Accounting reversal.

Smart-contract deployments may be irreversible. Their emergency response SHALL be defined before launch.

---

## 38. Data Recovery Engineering

Recovery tooling SHALL support:

- Database restore.
- Event replay.
- Projection rebuild.
- Indexer checkpoint reset.
- Provider evidence re-import.
- Ledger reconciliation.
- Cross-chain message recovery.
- Contract-state comparison.

Recovery code SHALL be tested and versioned like production code.

---

## 39. Performance Engineering

Performance testing SHALL include:

- API load.
- Event throughput.
- Indexer catch-up.
- Payment callback bursts.
- Liquidation spikes.
- Governance voting spikes.
- Market stress.
- Chain congestion.
- Database failover.
- Cross-region recovery.

Performance optimization SHALL NOT weaken invariants or finality controls.

---

## 40. Economic Simulation Repository

```text
simulations/
├── tokenomics/
├── collateral/
├── liquidation/
├── unsecured-credit/
├── syndication/
├── insurance/
├── governance/
├── bridge-risk/
├── payment-reversal/
└── treasury-runway/
```

Each simulation SHALL declare:

- Input assumptions.
- Model version.
- Random seed where applicable.
- Output metrics.
- Limitations.
- Decision supported.

Simulation output is evidence, not canonical financial state.

---

## 41. Security Repository

```text
security/
├── threat-model/
├── invariants/
├── audits/
├── findings/
├── bug-bounty/
├── incident-response/
├── key-management/
├── penetration-tests/
└── formal-verification/
```

Findings SHALL have:

- Identifier.
- Severity.
- Affected revision.
- Owner.
- Status.
- Remediation.
- Verification evidence.

---

## 42. Operational Repository

```text
operations/
├── runbooks/
├── playbooks/
├── reconciliations/
├── dashboards/
├── alerts/
├── provider-failover/
├── chain-failover/
├── emergency-controls/
├── disaster-recovery/
└── release-checklists/
```

Runbooks SHALL be executable, tested, and assigned to owners.

---

## 43. Required Automated Repository Checks

The repository SHALL include automated checks for:

1. CODEOWNERS coverage.
2. ADR presence for material architecture changes.
3. RFC approval for cross-domain changes.
4. Domain import rules.
5. Migration ownership.
6. Protobuf compatibility.
7. ABI compatibility.
8. Generated-code freshness.
9. Money-type safety.
10. Event-envelope compliance.
11. Idempotency support.
12. Secret scanning.
13. License policy.
14. Dependency vulnerabilities.
15. Container vulnerabilities.
16. Infrastructure policy.
17. Privileged-role changes.
18. UFT mint-path absence.
19. Upgrade storage layout.
20. Documentation linkage to invariants.

---

## 44. Definition of Ready

A work item is ready only when it has:

- Business objective.
- Domain owner.
- Acceptance criteria.
- Architecture references.
- Dependencies.
- Security classification.
- Test plan.
- Migration plan where applicable.
- Recovery expectations.

---

## 45. Definition of Done

A work item is done only when:

- Code is reviewed.
- Required tests pass.
- Architecture checks pass.
- Schemas and documentation are updated.
- Security findings are resolved or formally accepted.
- Migrations are validated.
- Observability is present.
- Runbooks are updated where needed.
- Release notes identify user and operator impact.
- Integration is verified on the intended revision.

---

## 46. Repository Bootstrap Sequence

The repository SHALL be bootstrapped in this order:

### Phase R0 — Governance and skeleton

- Create repository.
- Add constitutional documents.
- Add CODEOWNERS.
- Add contribution and security policies.
- Pin toolchains.
- Add branch protections.

### Phase R1 — Schemas and primitives

- Common identifiers.
- Money and fixed-point packages.
- Protobuf conventions.
- Event envelope.
- Command envelope.
- Error model.

### Phase R2 — Protocol interfaces

- Solidity interfaces.
- Shared types.
- Errors and events.
- Policy interfaces.
- Generated bindings.

### Phase R3 — Core infrastructure

- CI pipeline.
- Architecture tests.
- Local development stack.
- Event broker.
- PostgreSQL templates.
- Observability baseline.

### Phase R4 — Protocol kernel

- Registries.
- Offer signatures.
- Loan factory.
- Canonical loan state.
- Position and collateral boundaries.

### Phase R5 — Core services

- Accounts.
- Marketplace.
- Origination.
- Servicing.
- Indexing.
- Accounting.
- Reconciliation.

### Phase R6 — Advanced workstreams

- Syndication.
- NFTs.
- Variable interest.
- Complex schedules.
- Underwriting.
- Fiat and cards.
- Cross-chain.
- Refinancing.
- Secondary market.
- UFT governance and staking.

### Phase R7 — Integrated verification

- End-to-end scenarios.
- Economic simulations.
- Formal verification.
- Penetration testing.
- Disaster recovery.
- External audit.

---

## 47. Initial Workstream Ownership Map

| Workstream | Primary directories |
|---|---|
| Protocol kernel | `protocol/src/kernel`, `protocol/src/loans`, `protocol/src/registries` |
| UFT | `protocol/src/uft`, `protocol/src/governance`, `services/uft-economics` |
| Lending marketplace | `services/marketplace`, `services/offers`, `apps/web` |
| Funding | `protocol/src/funding`, `services/funding-syndication` |
| Servicing | `protocol/src/interest`, `protocol/src/schedules`, `services/loan-servicing` |
| Collateral | `protocol/src/collateral`, `services/collateral-coordination` |
| Liquidation | `protocol/src/liquidation`, `services/liquidation-coordination` |
| Accounting | `services/accounting-ledger`, `services/reconciliation` |
| Payments | `protocol/src/payments`, `services/payment-orchestration`, provider adapters |
| Identity | `services/identity-credentials`, restricted infrastructure |
| Underwriting | `models/`, `services/underwriting`, `services/credit-decisions` |
| Cross-chain | `protocol/src/crosschain`, `services/crosschain-coordination` |
| Security | `security/`, `protocol/formal`, invariant tests |
| Infrastructure | `infrastructure/`, `deployments/`, `operations/` |

---

## 48. Launch-Blocking Engineering Failures

Unified SHALL NOT enter unrestricted production while any known repository or delivery path allows:

1. Direct pushes to protected production branches.
2. Production artifacts not traceable to reviewed source.
3. Unpinned critical toolchains or dependencies.
4. Financial calculations using floating point.
5. Services writing to another domain's private database.
6. Event consumers producing duplicate economic effects.
7. Payment adapters directly changing debt.
8. Frontends declaring financial finality.
9. Post-genesis UFT mint authority.
10. Unreviewed privileged-role changes.
11. Active-loan behavior changing through an unversioned deployment.
12. Contract upgrades without storage-layout verification.
13. Provider callbacks without authentication and idempotency.
14. Accounting journals that can be edited or deleted.
15. Production secrets in source, logs, or images.
16. Missing recovery and rollback procedures for critical releases.
17. Untested database or event restoration.
18. Schema breaking changes without versioning.
19. Critical code without accountable ownership.
20. Agents or humans bypassing required integration gates.

---

## 49. Acceptance Criteria for v0.1

This specification is accepted when:

- Repository topology is approved.
- Technology boundaries are approved.
- Ownership boundaries align with the system architecture.
- CI and release gates cover critical invariants.
- Agent workflow prevents overlapping uncontrolled changes.
- Contract, service, schema, data, and infrastructure templates are defined.
- Launch-blocking engineering conditions are agreed.
- Repository bootstrap can begin without redefining architecture.

---

## 50. Next Foundation

The next required artifact is:

# Unified Implementation Master Plan, Work Breakdown Structure, and Parallel Agent Orchestration Specification v0.1

It SHALL define:

- Complete implementation phases.
- Epics and work packages.
- Dependency graph.
- Critical path.
- Parallel workstreams.
- Human and AI-agent assignments.
- Deliverables and acceptance criteria.
- Integration checkpoints.
- Verification milestones.
- Environment milestones.
- Audit milestones.
- Testnet and production readiness gates.
- Version and release roadmap.

---

## Appendix A — Mandatory Repository Files

```text
README.md
CONTRIBUTING.md
SECURITY.md
CODE_OF_CONDUCT.md
CODEOWNERS
CHANGELOG.md
LICENSES/
constitution/ENGINEERING_CONSTITUTION.md
adr/README.md
rfcs/README.md
docs/architecture/README.md
operations/release-checklists/README.md
security/findings/README.md
```

---

## Appendix B — Mandatory Pull Request Labels

```text
architecture
protocol
accounting
security
breaking-schema
migration
governance
uft
cross-chain
payments
identity
underwriting
infrastructure
hotfix
release-blocker
```

---

## Appendix C — Mandatory Commit Metadata for Critical Changes

Critical commits or pull requests SHALL identify:

- Specification references.
- Threat identifiers.
- Invariant identifiers.
- Migration identifiers.
- Release target.
- Reviewer identities.

---

## Appendix D — Engineering Principle Summary

```text
Specifications govern code.
Canonical owners govern state.
Interfaces govern integration.
Invariants govern safety.
Accounting governs financial truth.
Evidence governs finality.
Automation governs conformance.
Independent review governs release.
Recovery planning governs resilience.
```

---

**End of Unified Repository Architecture, Engineering Constitution, and Delivery Workflow Specification v0.1**
