# Unified Threat Model and Adversarial Security Specification

**Document:** Unified Threat Model and Adversarial Security Specification  
**Version:** 0.1 — Foundational Draft  
**Status:** Security architecture baseline for review, simulation, implementation, and independent audit  
**Applies to:** Unified protocol, UFT, smart contracts, applications, services, governance, identity, underwriting, payment rails, cross-chain infrastructure, treasury, operators, and external adapters  

---

## 1. Purpose

This specification defines the adversarial security model for Unified.

It identifies:

- Assets requiring protection.
- Trust boundaries.
- Threat actors.
- Attack surfaces.
- Abuse cases.
- Compound failure scenarios.
- Preventive controls.
- Detective controls.
- Recovery procedures.
- Residual risks.
- Security testing requirements.
- Production launch gates.

The goal is not to claim that Unified can eliminate all risk. The goal is to ensure that risks are explicit, bounded, observable, testable, recoverable where possible, and never hidden from users or governance.

This document covers attacks involving:

1. Protocol design.
2. Governance.
3. UFT monetary and economic systems.
4. Smart contracts.
5. Oracles and liquidation.
6. Bridges and cross-chain coordination.
7. Identity, privacy, and credentials.
8. Credit underwriting and automated models.
9. Fiat, card, and digital-asset payments.
10. Insiders and privileged operators.
11. Market and economic manipulation.
12. Infrastructure and operational failures.
13. Social, interface, and user-targeted attacks.
14. Accounting, reconciliation, and reporting.
15. Supply-chain and development-process compromise.

---

## 2. Governing Hierarchy

This specification is subordinate to:

1. `Unified_Constitution_v0.1.md`.
2. Ratified protocol invariants.
3. `Unified_Domain_Model_v0.1.md`.
4. `Universal_Loan_Model_and_State_Machines_v0.1.md`.
5. `Unified_Financial_Accounting_Specification_v0.1.md`.
6. `UFT_Tokenomics_and_Economic_Security_Specification_v0.1.md`.

Where this document conflicts with a higher-authority document, the higher-authority rule prevails and the conflict must be recorded and resolved through a versioned amendment.

---

# Part I — Security Doctrine

## 3. Security Objectives

Unified shall protect the following security properties.

### 3.1 Asset safety

No user, lender, borrower, staker, liquidity provider, treasury, insurer, or governance participant shall lose assets except through:

- A transaction they validly authorized.
- A contractual rule they accepted before activation.
- A disclosed market or counterparty loss.
- A valid liquidation, default, slashing, fee, or recovery process.
- A legally required action implemented through an authorized and transparent process where applicable.

### 3.2 Agreement integrity

Active loan terms, lender rights, repayment obligations, collateral rules, and policy versions must remain unchanged except through a valid amendment mechanism accepted at origination.

### 3.3 Accounting integrity

Every material financial event must be represented through balanced, immutable, idempotent accounting entries and reconciled against canonical settlement evidence.

### 3.4 Availability

Users must retain access to critical safety actions, including:

- Repayment.
- Collateral top-up.
- Valid withdrawal or redemption.
- Claim submission.
- Governance exit where applicable.
- Recovery procedures.

Emergency controls may restrict new risk creation but should not unnecessarily prevent risk reduction.

### 3.5 Privacy and confidentiality

Sensitive identity, communication, credit, bank, card, and authentication data must remain confidential and be disclosed only to authorized parties under defined policies.

### 3.6 Governance legitimacy

Governance outcomes must reflect valid voting power, valid proposal rules, transparent execution, and timelocked authority without duplicated, borrowed, bridged, or otherwise illegitimate voting influence.

### 3.7 Supply integrity

Canonical UFT supply must never exceed the genesis cap. Wrapped UFT must remain fully backed. Burned UFT must not re-enter circulation.

### 3.8 Settlement integrity

No payment, bridge transfer, card authorization, bank notification, or cross-chain message may be treated as final before its applicable finality policy is satisfied.

### 3.9 Model integrity

Automated underwriting, reputation, risk scoring, and liquidation models must operate under approved versions, authenticated inputs, monitored performance, and auditable decision records.

### 3.10 Recoverability

Failures must enter explicit recovery states. The system must avoid silent inconsistency, duplicated claims, hidden losses, or irreversible escalation where a bounded recovery process can be designed.

---

## 4. Security Principles

### 4.1 Assume compromise

Every external dependency, privileged key, operator, service, oracle, bridge, model, interface, and integration shall be treated as potentially compromised.

### 4.2 Least privilege

Every contract, service, key, role, adapter, and governance body receives only the minimum authority required.

### 4.3 Defense in depth

No critical control may depend on one unmonitored protection layer.

### 4.4 Fail closed for risk creation

Where validation is incomplete or contradictory, Unified should reject:

- New loan activation.
- New collateral valuation.
- New bridge issuance.
- New governance execution.
- New payment finalization.
- New token or position issuance.

### 4.5 Fail open only for risk reduction

Where technically safe, the system should preserve:

- Repayment.
- Collateral addition.
- Withdrawal after contractual entitlement.
- Position redemption.
- Emergency exit.

### 4.6 Explicit finality

Every external or asynchronous operation must define pending, provisional, final, failed, disputed, and recovery states where applicable.

### 4.7 Canonical authority

Mirrors, caches, interfaces, and indexes cannot override canonical state.

### 4.8 No hidden superuser

Unified shall not include undisclosed keys or roles capable of:

- Minting UFT.
- Seizing user assets.
- Rewriting active loans.
- Forging settlement.
- Bypassing governance.
- Changing accounting history.

### 4.9 Bounded blast radius

Assets, chains, collateral classes, payment providers, bridges, and product policies should be isolated so one failure does not automatically compromise the entire system.

### 4.10 Observable security

Every material security-relevant action must emit auditable evidence and be monitored.

---

# Part II — Scope, Assets, and Trust Boundaries

## 5. Protected Assets

### 5.1 User financial assets

- Loan principal.
- Borrower collateral.
- Lender receivables.
- Lender positions.
- Syndicate and tranche claims.
- Fiat deposits and withdrawals.
- Card-funded balances.
- Insurance benefits.
- Guarantee rights.
- Liquidation surplus.
- Refunds and overpayments.

### 5.2 UFT assets

- Canonical UFT supply.
- Genesis allocations.
- Vesting balances.
- Treasury UFT.
- Insurance reserve UFT.
- Staking reserve UFT.
- Staked UFT and sUFT.
- veUFT governance locks.
- Wrapped UFT.
- Bridge escrow backing.
- Burned supply records.
- Liquidity positions.

### 5.3 Protocol control assets

- Governance authority.
- Timelock authority.
- Emergency pause authority.
- Oracle configuration.
- Asset allowlists.
- Policy registries.
- Upgrade permissions.
- Treasury mandates.
- Bridge adapters.
- Payment adapters.
- Identity attesters.
- Credit-model approvals.

### 5.4 Information assets

- Identity documents.
- KYC and AML results.
- Credit reports.
- Income and cash-flow evidence.
- Bank-account details.
- Card-payment metadata.
- Private messages.
- Recovery secrets.
- API keys.
- Signing keys.
- Model parameters.
- Fraud signals.
- Security reports.
- Incident records.

### 5.5 Integrity assets

- Loan terms.
- Offer signatures.
- Policy versions.
- State transitions.
- Journal entries.
- Reconciliation records.
- Oracle observations.
- Governance votes.
- Cross-chain message nonces.
- Settlement references.
- Audit logs.

### 5.6 Availability assets

- Smart-contract execution.
- RPC and node access.
- Indexers.
- Payment services.
- Identity verification.
- Oracle feeds.
- Cross-chain relays.
- User interfaces.
- Emergency communications.
- Recovery tools.

---

## 6. Trust Boundaries

Unified operates across multiple trust domains.

### 6.1 User boundary

Includes:

- User wallets.
- Signing devices.
- Browsers.
- Mobile applications.
- Session keys.
- Account-recovery mechanisms.

The protocol cannot assume the user device is uncompromised.

### 6.2 Application boundary

Includes:

- Web frontend.
- Mobile frontend.
- Governance interface.
- Operations console.
- API gateway.

Interfaces are untrusted presentation layers and cannot define canonical financial state.

### 6.3 Service boundary

Includes:

- Marketplace services.
- Messaging services.
- Underwriting services.
- Payment orchestration.
- Indexers.
- Reconciliation services.
- Notification systems.
- Analytics systems.

Services may authorize workflows but may not silently override on-chain or ledger authority.

### 6.4 Smart-contract boundary

Includes:

- Loan contracts.
- Collateral vaults.
- Funding vaults.
- Position contracts.
- UFT contracts.
- Staking contracts.
- Governance contracts.
- Treasury contracts.
- Bridge escrows.

Smart-contract correctness is necessary but not sufficient for system safety.

### 6.5 External-provider boundary

Includes:

- Banks.
- Card processors.
- KYC providers.
- Credit bureaus.
- Oracles.
- Bridges.
- Messaging networks.
- Stablecoin issuers.
- Cloud providers.
- Market makers.

Each provider must be isolated through versioned adapters and exposure limits.

### 6.6 Governance boundary

Includes:

- UFT holders.
- Delegates.
- Risk council.
- Emergency council.
- Timelock executors.
- Treasury committees.

Governance is a threat actor as well as a control mechanism.

### 6.7 Development and deployment boundary

Includes:

- Source repositories.
- Package registries.
- CI/CD systems.
- Build runners.
- Artifact registries.
- Deployment keys.
- Infrastructure-as-code state.
- Audit reports.

A compromised build process can defeat otherwise secure source code.

---

# Part III — Threat Actors

## 7. External Threat Actors

### 7.1 Opportunistic attacker

Seeks exploitable defects, leaked keys, misconfigurations, or weak user accounts.

### 7.2 Professional financial attacker

Uses capital, automation, flash liquidity, market manipulation, and coordinated transactions to extract value.

### 7.3 Malicious borrower

Attempts to:

- Obtain principal without enforceable repayment.
- Inflate identity or credit quality.
- Reuse collateral.
- Manipulate valuations.
- Reverse payments.
- Evade liquidation.
- Exploit refinancing or restructuring.

### 7.4 Malicious lender

Attempts to:

- Misrepresent loan terms.
- Front-run offers.
- Claim excess repayment.
- Trigger wrongful liquidation.
- Transfer invalid positions.
- exploit borrower identity or communication.

### 7.5 Malicious liquidator

Attempts to manipulate prices, trigger unnecessary liquidation, monopolize auctions, or capture excessive collateral.

### 7.6 Governance attacker

Attempts to acquire, borrow, duplicate, delegate, coerce, or corrupt voting power to alter protocol rules or transfer treasury value.

### 7.7 Oracle manipulator

Attempts to corrupt price observations, data sources, timestamps, aggregation, or fallback behavior.

### 7.8 Bridge attacker

Attempts to forge messages, duplicate releases, issue unbacked wrapped assets, compromise validators, or exploit finality assumptions.

### 7.9 Identity fraudster

Attempts to create synthetic identities, reuse credentials, steal verified accounts, or obtain multiple credit allocations.

### 7.10 Payment fraudster

Attempts to use stolen cards, reverse bank transfers, create chargebacks, exploit refunds, or falsify provider callbacks.

### 7.11 Market manipulator

Attempts to distort UFT, collateral, lender-position, or benchmark markets to profit from liquidations, governance, or accounting marks.

### 7.12 Extortionist or ransomware actor

Attempts to disrupt critical services, steal data, or threaten disclosure.

---

## 8. Internal and Privileged Threat Actors

### 8.1 Malicious administrator

Uses legitimate access for unauthorized configuration, data access, asset movement, or evidence suppression.

### 8.2 Compromised operator

An otherwise legitimate operator account is controlled by an attacker.

### 8.3 Malicious developer

Introduces backdoors, unsafe dependencies, hidden upgrade paths, or test omissions.

### 8.4 Malicious auditor or assessor

Conceals defects, leaks confidential findings, or approves insecure systems.

### 8.5 Treasury insider

Manipulates grants, market operations, transfers, counterparties, or reconciliation.

### 8.6 Model insider

Manipulates underwriting rules, model weights, training data, thresholds, or performance reporting.

### 8.7 Governance delegate cartel

Coordinates votes, private benefits, bribery, or censorship while appearing decentralized.

### 8.8 Provider insider

Compromises a bank, card processor, oracle, bridge, KYC provider, or market maker from within.

---

## 9. Non-Human and Environmental Threats

- Software defects.
- Configuration drift.
- Network partitions.
- Chain reorganizations.
- Consensus failures.
- Stablecoin depegs.
- Market crashes.
- Cloud outages.
- Data corruption.
- Model drift.
- Clock skew.
- Dependency abandonment.
- Regulatory intervention.
- Natural disasters.
- Hardware failure.
- Human error.

---

# Part IV — Risk Classification

## 10. Impact Levels

| Level | Definition |
|---|---|
| I1 — Negligible | Minor inconvenience; no material asset, privacy, or integrity loss |
| I2 — Limited | Bounded user or operational impact with straightforward recovery |
| I3 — Material | Significant user, financial, legal, or operational impact |
| I4 — Severe | Large losses, systemic disruption, major privacy breach, or governance compromise |
| I5 — Catastrophic | Protocol insolvency, canonical UFT failure, irreversible system-wide asset loss, or constitutional control failure |

## 11. Likelihood Levels

| Level | Definition |
|---|---|
| L1 — Rare | Requires exceptional conditions or multiple independent failures |
| L2 — Unlikely | Plausible but difficult or expensive |
| L3 — Possible | Credible under ordinary adversarial conditions |
| L4 — Likely | Expected to be attempted regularly |
| L5 — Almost certain | Continuous or highly automated attack pressure |

## 12. Risk Rating

Risk score:

```text
Risk Score = Impact × Likelihood
```

| Score | Rating |
|---:|---|
| 1–4 | Low |
| 5–9 | Moderate |
| 10–14 | High |
| 15–19 | Critical |
| 20–25 | Existential |

No production release may contain an untreated existential risk. Critical risks require explicit executive, security, risk-council, and governance acceptance with documented containment.

---

# Part V — Protocol-Level Threats

## 13. Universal Loan Integrity Threats

### T-PRO-001 — Active-loan term mutation

**Attack:** A governance action, upgrade, backend mutation, or storage collision changes active loan economics.

**Assets at risk:** Borrower obligations, lender rights, collateral, trust in protocol finality.

**Controls:**

- Immutable activation snapshots.
- Version-pinned policy references.
- No delegatecall to unbounded policy implementations.
- Timelocked upgrades.
- Storage-layout validation.
- Contract-level invariant tests.
- Independent comparison of pre- and post-upgrade loan hashes.

**Detection:**

- Continuous loan-term hash monitoring.
- Upgrade simulation against all active policy versions.
- Alert on unexpected state-root differences.

**Recovery:**

- Halt new activations.
- Preserve repayment and collateral-release paths.
- Revert upgrade if reversible.
- Deploy constitutionally compliant migration only with user-right preservation.

**Residual risk:** Critical if upgradeable storage controls active economics.

### T-PRO-002 — Duplicate loan activation

**Attack:** The same accepted offer, funding commitment, or settlement is used to activate more than one loan.

**Controls:**

- Globally unique offer identifiers.
- Nonces and consumed-offer registry.
- Idempotency keys.
- Canonical funding-commitment state.
- Atomic state update before external interaction.

**Required test:** Concurrent activation attempts across multiple RPC nodes and chains.

### T-PRO-003 — Principal disbursed without enforceable security

**Attack:** Principal is transferred before collateral, guarantee, insurance, identity, or cross-chain conditions become final.

**Controls:**

- Activation-readiness predicate.
- Atomic same-chain activation.
- Escrowed coordinated activation for asynchronous settlement.
- Compensation paths.
- Provider finality thresholds.

### T-PRO-004 — Collateral captured without principal delivery

**Attack:** Collateral becomes locked while funding fails or is redirected.

**Controls:**

- Atomic settlement where possible.
- Expiring conditional escrow.
- Borrower-triggered refund after timeout.
- Principal recipient binding in signed terms.
- No administrator discretion over refund eligibility.

### T-PRO-005 — Double collateral pledge

**Attack:** One asset or economic interest secures multiple incompatible senior obligations.

**Controls:**

- Canonical lien registry.
- Vault custody for digital assets.
- Unique asset identifiers for NFTs and tokenized assets.
- Attested lien searches for off-chain assets.
- Refinancing handoff protocol.

### T-PRO-006 — Duplicate lender claims

**Attack:** Position issuance, fractionalization, bridge representation, or accounting error creates claims exceeding funded rights.

**Controls:**

- Position-supply invariant.
- Burn-before-reissue.
- Canonical position registry.
- Tranche cap validation.
- Daily lender-claim reconciliation.

### T-PRO-007 — Unauthorized amendment

**Attack:** One party or operator alters schedule, rate, fees, collateral, or maturity without required consent.

**Controls:**

- Amendment-policy snapshot.
- Typed signatures from required parties.
- Position-holder voting rules where syndicated.
- Amendment nonce.
- Timed review period.

### T-PRO-008 — State-machine desynchronization

**Attack:** Origination, servicing, collateral, payment, funding, or cross-chain states diverge and allow contradictory actions.

**Controls:**

- Explicit state vector.
- Transition guards.
- Cross-domain invariant checker.
- Reconciliation jobs.
- Recovery states instead of silent correction.

### T-PRO-009 — Terminal-state reactivation

**Attack:** A repaid, settled, liquidated, or closed loan is returned to active state.

**Controls:**

- Irreversible terminal flags.
- Monotonic lifecycle counters.
- No generic administrator state setter.
- Fuzz tests over all transitions.

### T-PRO-010 — Repayment denial

**Attack:** Pause logic, frontend censorship, token routing, or malicious lender behavior prevents valid repayment and causes default.

**Controls:**

- Direct contract repayment path.
- Pause exemptions for risk-reducing actions.
- Multiple supported interfaces.
- Grace extension if protocol-caused outage is proven under predefined policy.

---

## 14. Funding and Syndication Threats

### T-FUN-001 — False commitment

A lender appears committed without locked, approved, or verifiably available funds.

**Controls:** funded escrow, allowance verification, expiring commitments, solvency checks, commitment bonds.

### T-FUN-002 — Last-block funding withdrawal

A large lender withdraws immediately before activation to manipulate the borrower or other lenders.

**Controls:** commitment lock period, withdrawal penalties, minimum funding stability window.

### T-FUN-003 — Tranche waterfall manipulation

Incorrect seniority or allocation redirects repayments or losses.

**Controls:** immutable waterfall hash, formal verification, accounting reconciliation, test vectors for every tranche scenario.

### T-FUN-004 — Syndicate voting capture

A lender accumulates positions solely to force restructuring, liquidation, or amendment beneficial to itself.

**Controls:** snapshot voting, conflict rules, supermajority for material changes, borrower protections, bounded lender discretion.

### T-FUN-005 — Fractionalization inflation

A position is fractionalized into claims exceeding the parent position.

**Controls:** escrow parent position, capped child supply, redemption burns, invariant monitoring.

---

## 15. Refinancing and Restructuring Threats

### T-REF-001 — Double senior lien

New funding activates before the old senior claim is extinguished.

**Controls:** atomic payoff-and-reassignment, escrow coordinator, old-loan payoff receipt, canonical lien registry.

### T-REF-002 — Payoff quote manipulation

A lender or service supplies an inflated, stale, or incomplete payoff amount.

**Controls:** contract-derived quote, timestamp, component breakdown, maximum validity period, dispute path.

### T-REF-003 — Refinance griefing

A party repeatedly initiates refinancing to freeze collateral or transfers.

**Controls:** proposal bond, expiry, attempt limits, automatic unlock, lender-position snapshot.

### T-REF-004 — Restructuring coercion

Borrowers or minority lenders are pressured into hidden or discriminatory amendments.

**Controls:** complete disclosure, independent review window, explicit signatures, position-holder quorum, immutable audit trail.

---

# Part VI — Smart-Contract Threats

## 16. Smart-Contract Attack Classes

### T-SC-001 — Reentrancy

**Vectors:** token callbacks, NFT receivers, vault withdrawals, liquidation payouts, bridge adapters.

**Controls:** checks-effects-interactions, reentrancy guards, pull payments, restricted token standards, state locking.

### T-SC-002 — Access-control failure

**Vectors:** missing modifiers, role-admin cycles, default admin exposure, stale roles, improper delegate authorization.

**Controls:** explicit role matrix, least privilege, multisig, role expiry, access-control tests, privileged-call monitoring.

### T-SC-003 — Integer precision and rounding exploitation

**Vectors:** interest accrual, tranche allocation, vault shares, exchange rates, token decimals, partial liquidation.

**Controls:** fixed precision standards, direction-specific rounding, minimum units, dust accounting, property tests.

### T-SC-004 — Storage collision

**Vectors:** proxy upgrades, inherited layouts, unstructured storage misuse.

**Controls:** namespaced storage, compiler layout checks, upgrade simulation, immutable contracts for critical token supply.

### T-SC-005 — Uninitialized implementation or proxy

**Controls:** constructor disabling, atomic initialization, deployment verification, initialization-state monitoring.

### T-SC-006 — Signature replay

**Vectors:** reused offers, cross-chain replay, contract replay, expired permits, duplicated amendment signatures.

**Controls:** chain ID, verifying contract, nonce, deadline, domain separator, consumed-signature registry.

### T-SC-007 — Signature malleability or signer confusion

**Controls:** standard signature libraries, low-s enforcement, explicit signer and action binding, EIP-712 structured data.

### T-SC-008 — Malicious or non-standard token behavior

**Vectors:** fee-on-transfer, rebasing, callback, blacklisting, false return value, changing decimals.

**Controls:** asset allowlist, balance-delta accounting, adapter-specific handling, isolation, emergency delisting for new actions.

### T-SC-009 — Denial of service through unbounded loops

**Vectors:** syndicate distribution, position-holder enumeration, installment processing, liquidation baskets.

**Controls:** bounded batches, claim-based distribution, pagination, gas profiling, maximum collection sizes.

### T-SC-010 — Forced asset transfer

Assets sent directly to contracts distort balances or accounting.

**Controls:** internal accounting independent of raw balance, sweep rules that cannot seize attributable user funds, reconciliation.

### T-SC-011 — Front-running and transaction-order manipulation

**Vectors:** offer acceptance, liquidation, collateral top-up, auction bids, governance delegation, swaps.

**Controls:** commitment schemes, slippage limits, deadlines, private transaction routes where appropriate, batch auctions.

### T-SC-012 — Flash-loan-assisted manipulation

**Vectors:** governance power, oracle prices, liquidity depth, collateral ratio, staking rewards.

**Controls:** historical snapshots, TWAPs, minimum holding periods, multi-block observations, borrowed-capital resistance.

### T-SC-013 — Self-destruct or code replacement risk

**Controls:** prohibit unsafe implementation patterns, code-hash monitoring, immutable critical contracts.

### T-SC-014 — Unexpected ETH/native-token reception

**Controls:** explicit receive logic, refund rules, no balance-based entitlement assumptions.

### T-SC-015 — Upgrade bypass

**Attack:** privileged actor changes implementation outside governance or timelock.

**Controls:** timelock-owned proxy admin, immutable upgrade path, on-chain implementation allowlist, code-hash publication.

### T-SC-016 — Event/state mismatch

**Attack:** events imply a state change that did not occur, or state changes without required events.

**Controls:** event-state invariant tests, indexer cross-checking, no event-only accounting.

### T-SC-017 — Delegatecall policy escape

A policy module executes arbitrary code in the loan’s storage context.

**Controls:** avoid delegatecall for third-party policies, narrow interfaces, sandboxed external calls, immutable policy code hashes.

### T-SC-018 — ERC-4626 share inflation or donation attack

**Controls:** virtual shares/assets, minimum initial deposit, preview-function consistency tests, controlled staking-vault initialization.

### T-SC-019 — NFT callback and approval abuse

**Controls:** strict receiver logic, collection allowlist, approval revocation, safe-transfer validation, no arbitrary callback execution.

### T-SC-020 — Auction settlement manipulation

**Controls:** deterministic auction rules, escrowed bids, reserve price policy, anti-sniping rules, finality confirmation.

---

## 17. Smart-Contract Verification Requirements

Every critical contract must undergo:

- Unit testing.
- Integration testing.
- Property-based testing.
- Stateful fuzzing.
- Invariant testing.
- Static analysis.
- Symbolic execution where suitable.
- Storage-layout validation.
- Gas-bound analysis.
- Fork testing.
- Independent audit.
- Public bug bounty before unrestricted launch.

Critical invariants must run continuously against mainnet-fork and testnet deployments.

---

# Part VII — Governance Threats

## 18. Governance Capture

### T-GOV-001 — Token concentration capture

Large holders coordinate to control proposals.

**Controls:** delegation transparency, quorum tiers, supermajority for constitutional actions, timelocks, concentration dashboards, progressive decentralization.

### T-GOV-002 — Borrowed voting power

Tokens are borrowed temporarily to influence a vote.

**Controls:** veUFT locks, historical snapshots, minimum lock exceeding proposal lifecycle, no collateralized-UFT voting.

### T-GOV-003 — Cross-chain double voting

Canonical UFT and wrapped UFT represent the same underlying tokens but both vote.

**Controls:** canonical vote-escrow accounting, remote vote locks, bridge voting nonce, backing-state proof.

### T-GOV-004 — Delegation cartel

Delegates coordinate private benefit extraction.

**Controls:** public delegation records, conflict disclosures, delegate performance dashboards, revocable delegation, bribery monitoring.

### T-GOV-005 — Governance bribery

Third parties pay voters to direct treasury, liquidity, or risk decisions.

**Controls:** disclosure, proposal-bond rules, gauge caps, diversified committees, delayed execution, public benefit analysis.

### T-GOV-006 — Malicious proposal payload

Proposal description appears benign while calldata performs another action.

**Controls:** decoded calldata, human-readable execution simulation, independent payload review, code-hash verification.

### T-GOV-007 — Timelock bypass

An executor or upgrade path avoids required delay.

**Controls:** timelock as sole privileged owner, no parallel admin, automated authority graph analysis.

### T-GOV-008 — Emergency-council abuse

Emergency powers are used for censorship, asset seizure, or permanent rule changes.

**Controls:** narrow powers, automatic expiry, public reason codes, post-action ratification, no UFT mint or user-asset transfer authority.

### T-GOV-009 — Governance denial of service

Spam, quorum manipulation, or execution griefing prevents legitimate governance.

**Controls:** proposal thresholds, refundable bonds, rate limits, alternate executors, queue cleanup rules.

### T-GOV-010 — Treasury extraction

Governance approves grants or market operations benefiting insiders.

**Controls:** conflict declarations, staged disbursement, milestones, on-chain streaming, independent treasury reporting.

### T-GOV-011 — Voter suppression

Interfaces, RPC providers, or delegates prevent users from seeing or casting votes.

**Controls:** direct contract voting, multiple interfaces, public proposal data, extended voting after verified outages.

### T-GOV-012 — Constitutional downgrade

Governance attempts to weaken supply cap, user protections, or active-loan immutability.

**Controls:** constitutional proposal class, maximum quorum and delay, immutable token cap, technical impossibility for prohibited actions where feasible.

---

## 19. Governance Security Controls

- Proposal simulation before voting.
- Proposal hash and calldata publication.
- Human-readable diff of parameter changes.
- Independent risk assessment for risk proposals.
- Treasury impact statement.
- Active-loan compatibility report.
- Timelock monitoring.
- Execution dry run.
- Emergency cancellation only under bounded authority.
- Post-execution verification.

---

# Part VIII — UFT and Economic Security Threats

## 20. UFT Supply Threats

### T-UFT-001 — Unauthorized mint

**Impact:** Catastrophic.

**Controls:** no post-genesis mint function, immutable token contract, bytecode verification, no upgradeable supply logic.

### T-UFT-002 — Vesting bypass

**Controls:** immutable vesting schedules, beneficiary-only claims, no administrator early-release function, public unlock dashboard.

### T-UFT-003 — Burn-accounting mismatch

UFT is reported burned without reducing canonical supply.

**Controls:** burn transaction verification, total-supply reconciliation, canonical event indexing.

### T-UFT-004 — Wrapped UFT overissuance

**Controls:** escrow-backed mint cap, per-chain reconciliation, bridge exposure limits, circuit breaker.

### T-UFT-005 — Duplicate economic use

The same UFT is counted as voting power, collateral, staking capital, and bridge backing in incompatible ways.

**Controls:** custody-state exclusivity, derivative-token registry, collateral-voting neutralization, cross-domain reconciliation.

---

## 21. UFT Market Threats

### T-UFT-006 — Price manipulation

Attackers distort thin markets to borrow, liquidate, or vote under false economic conditions.

**Controls:** multi-venue TWAP, liquidity-depth requirements, price-deviation limits, isolated collateral market.

### T-UFT-007 — Reflexive liquidation cascade

Protocol stress reduces UFT price, causing UFT-backed liquidations and further price decline.

**Controls:** low LTV, debt ceiling, partial liquidation, auction route, insurance diversification, burn suspension, circuit breakers.

### T-UFT-008 — Liquidity mining mercenary attack

Capital enters only for rewards and exits abruptly, leaving unusable liquidity.

**Controls:** time-weighted incentives, vesting, protocol-owned liquidity, depth-based rewards, emission caps.

### T-UFT-009 — Treasury market manipulation

Treasury trades move UFT price or favor counterparties.

**Controls:** mandate limits, execution algorithms, independent benchmark, public trade reporting, counterparty diversification.

### T-UFT-010 — Buyback front-running

Attackers anticipate buyback transactions and extract value.

**Controls:** randomized execution windows, size limits, TWAP execution, competitive routing.

### T-UFT-011 — Governance-value circularity

UFT price determines governance influence while governance controls UFT demand and treasury resources.

**Controls:** constitutional limits, treasury diversification, disclosure, lock-based voting, independent risk council.

---

## 22. Staking and Insurance Threats

### T-UFT-012 — Unfunded reward promise

**Controls:** reward reserve accounting, on-chain funded-rate calculation, no guaranteed APY language.

### T-UFT-013 — Withdrawal race before slashing

Stakers exit after learning of a covered loss but before slashing.

**Controls:** cooldown, incident lookback, pending-withdrawal exposure, public rules.

### T-UFT-014 — Arbitrary slashing

Governance or operators slash stakers without a predefined covered event.

**Controls:** enumerated slashing conditions, evidence requirement, timelocked or adjudicated execution, maximum bounds.

### T-UFT-015 — Insurance reserve correlation failure

Reserve is mostly UFT and collapses during protocol stress.

**Controls:** stable-asset diversification targets, reserve coverage ratio, product-specific reserves.

### T-UFT-016 — Reserve double counting

The same assets are counted as treasury liquidity, insurance capital, and bridge backing.

**Controls:** segregated custody, accounting dimensions, reserve-purpose locks, independent reconciliation.

### T-UFT-017 — Socialized-loss abuse

Governance repeatedly uses stakers or reserves to subsidize reckless products.

**Controls:** product risk premiums, exposure caps, loss attribution, governance disclosure, post-loss parameter tightening.

---

# Part IX — Oracle and Liquidation Threats

## 23. Oracle Threats

### T-ORC-001 — Spot-price manipulation

**Controls:** TWAP, medianized sources, minimum liquidity, maximum deviation.

### T-ORC-002 — Stale price

**Controls:** heartbeat limits, timestamp validation, fail-closed new borrowing, predefined fallback.

### T-ORC-003 — Oracle source compromise

**Controls:** multiple independent providers, source quorum, adapter isolation, emergency disable.

### T-ORC-004 — Decimal or denomination error

**Controls:** normalized fixed-point format, unit metadata, test vectors, sanity bounds.

### T-ORC-005 — Wrong asset mapping

**Controls:** immutable asset/feed pair identifiers, deployment review, runtime symbol-independent checks.

### T-ORC-006 — Stablecoin depeg blindness

**Controls:** direct market-price feeds, depeg thresholds, collateral haircut, settlement-asset monitoring.

### T-ORC-007 — NFT floor manipulation

**Controls:** volume filters, wash-trade detection, appraisal attestations, conservative haircuts, auction liquidation.

### T-ORC-008 — Benchmark-rate manipulation

**Controls:** approved benchmark sources, delayed updates, cap/floor, fallback rate, governance review.

### T-ORC-009 — Time-source manipulation

**Controls:** chain timestamp bounds, monotonic service clocks, provider timestamp verification.

### T-ORC-010 — Fallback oracle abuse

Fallback source is easier to manipulate and deliberately triggered.

**Controls:** independent fallback quality, activation thresholds, reduced risk limits during fallback mode.

---

## 24. Liquidation Threats

### T-LIQ-001 — Wrongful liquidation

Loan is liquidated using invalid price, debt, threshold, or state.

**Controls:** reproducible eligibility calculation, challenge delay where appropriate, oracle quorum, event record.

### T-LIQ-002 — Liquidation underpayment

Liquidator receives excess collateral or repays insufficient debt.

**Controls:** deterministic quote, minimum output, balance-delta verification, settlement atomicity.

### T-LIQ-003 — Liquidation monopoly

One party captures all profitable liquidations and manipulates access.

**Controls:** open execution, batch auctions, keeper diversity, anti-censorship monitoring.

### T-LIQ-004 — Auction collusion

Bidders coordinate to acquire collateral below fair value.

**Controls:** reserve prices, competitive windows, bidder bonds, external market comparison.

### T-LIQ-005 — Partial-liquidation loop

Repeated small liquidations extract excessive bonuses.

**Controls:** target health factor, aggregate bonus cap, minimum liquidation size, cooldown.

### T-LIQ-006 — Collateral sale failure

Illiquid collateral cannot be sold and debt remains unresolved.

**Controls:** alternate routes, lender claim, auction extension, insurance and bad-debt process.

### T-LIQ-007 — Borrower front-run top-up censorship

Liquidators or block builders prevent collateral top-up.

**Controls:** grace windows, private transaction options, pre-signed top-up automation, oracle delay.

### T-LIQ-008 — Liquidation proceeds misallocation

Proceeds are distributed incorrectly among senior, junior, insurance, and borrower surplus.

**Controls:** immutable waterfall, accounting verification, claim-based distribution, independent reconciliation.

---

# Part X — Bridge and Cross-Chain Threats

## 25. Cross-Chain Security Model

Every loan has one canonical home authority. Satellite systems may custody assets or execute limited actions but cannot independently redefine loan economics.

## 26. Bridge Threats

### T-BRG-001 — Forged cross-chain message

**Controls:** authenticated message proof, validator quorum, source contract allowlist, domain separation.

### T-BRG-002 — Message replay

**Controls:** nonce, message ID, consumed-message registry, source/destination binding.

### T-BRG-003 — Message reordering

**Controls:** sequence numbers, dependency checks, explicit out-of-order queue.

### T-BRG-004 — Double release

Canonical assets are released more than once for one burn or lock.

**Controls:** one-time claim state, burn proof, escrow accounting, finality confirmation.

### T-BRG-005 — Unbacked wrapped asset issuance

**Controls:** backing cap, escrow proof, supply reconciliation, mint pause.

### T-BRG-006 — Validator or relayer compromise

**Controls:** provider diversification, threshold signatures, rate limits, per-bridge exposure caps, delayed large withdrawals.

### T-BRG-007 — Source-chain reorganization

A message is accepted before source finality and later disappears.

**Controls:** chain-specific finality thresholds, reorg monitoring, delayed high-value settlement.

### T-BRG-008 — Destination-chain reorganization

**Controls:** destination confirmation before canonical state finalization, compensation state.

### T-BRG-009 — Bridge censorship

Messages are withheld, freezing collateral, repayment, or redemption.

**Controls:** alternate relayers, user-submitted proofs, timeout recovery, emergency manual proof under transparent rules.

### T-BRG-010 — Adapter upgrade compromise

**Controls:** version pinning for active loans, timelocked upgrades, per-adapter isolation, migration only through explicit process.

### T-BRG-011 — Chain-ID or domain confusion

**Controls:** full chain-domain binding, canonical registry, no symbol-only routing.

### T-BRG-012 — Cross-chain double collateral

An asset locked on one chain is represented as free or reusable elsewhere.

**Controls:** canonical lien state, escrow proof, wrapped-asset restrictions, cross-chain reconciliation.

### T-BRG-013 — Cross-chain repayment duplication

One repayment message reduces debt more than once.

**Controls:** payment ID, message nonce, idempotent ledger posting, canonical home-chain allocation.

### T-BRG-014 — Cross-chain governance duplication

Covered under T-GOV-003 with bridge-lock verification.

### T-BRG-015 — Satellite contract takeover

**Controls:** minimal satellite authority, per-chain pause, capped custody, immutable home-chain economics.

---

## 27. Cross-Chain Recovery States

Cross-chain operations must support:

```text
NOT_INITIATED
SOURCE_PENDING
SOURCE_FINAL
MESSAGE_PENDING
DESTINATION_PENDING
FINAL
FAILED
DISPUTED
RECOVERY_PENDING
RECOVERED
```

No operator may convert `MESSAGE_PENDING` directly into `FINAL` without cryptographic or constitutionally approved evidence.

---

# Part XI — Identity, Privacy, and Credential Threats

## 28. Identity Threats

### T-ID-001 — Identity theft

Attacker controls a verified account or credential.

**Controls:** wallet binding, strong authentication, device alerts, credential revocation, recovery policy.

### T-ID-002 — Synthetic identity

Fabricated identity passes verification and obtains credit.

**Controls:** provider diversification, liveness checks, document validation, fraud analytics, exposure ramping.

### T-ID-003 — Duplicate identity and Sybil credit

One person creates many identities or wallets to exceed credit limits.

**Controls:** uniqueness credentials, privacy-preserving deduplication, provider correlation, aggregate exposure registry.

### T-ID-004 — Credential replay

Credential is reused by another wallet or on another chain.

**Controls:** subject binding, chain/domain binding, nonce, expiry, revocation registry.

### T-ID-005 — Expired or revoked credential acceptance

**Controls:** validity checks at decision and activation, revocation-cache freshness requirements.

### T-ID-006 — Malicious attester

Attester issues false eligibility or identity credentials.

**Controls:** attester bonds, audits, multi-attestation policy, exposure caps, revocation, slashing where defined.

### T-ID-007 — Privacy leakage on public chain

Personal data is embedded in transaction calldata, metadata, IPFS, or events.

**Controls:** schema restrictions, client-side validation, encrypted references, privacy review, data minimization.

### T-ID-008 — Zero-knowledge proof linkage

Proof design allows repeated actions to be linked or identity inferred.

**Controls:** domain-specific nullifiers, minimal disclosures, cryptographic review, metadata protection.

### T-ID-009 — Nullifier reuse or collision

**Controls:** circuit constraints, domain separation, uniqueness tests, audited libraries.

### T-ID-010 — Recovery-channel takeover

Account recovery transfers control to an attacker.

**Controls:** delay, multi-factor recovery, social recovery thresholds, cancellation alerts, limited recovery authority.

### T-ID-011 — Insider identity-data access

**Controls:** least privilege, just-in-time access, encryption, immutable audit logs, access anomaly monitoring.

### T-ID-012 — Credential censorship

Provider refuses or delays legitimate users.

**Controls:** multiple approved providers, portable credentials, appeal path, transparent eligibility policy.

---

## 29. Communication and Social Threats

### T-ID-013 — Encrypted-chat key compromise

**Controls:** forward secrecy, device verification, key rotation, no server-held plaintext.

### T-ID-014 — Phishing through lender-borrower chat

**Controls:** link warnings, verified system-message format, no secret requests, report/block tools.

### T-ID-015 — Metadata deanonymization

Timing, graph, IP, or transaction metadata reveals identities.

**Controls:** privacy-preserving relays where practical, metadata minimization, delayed batching, clear residual-risk disclosure.

### T-ID-016 — Harassment, coercion, and extortion

**Controls:** reporting, moderation, evidence preservation, blocking, emergency support, no off-platform payment pressure.

---

# Part XII — Underwriting and Automated Decision Threats

## 30. Data Threats

### T-UW-001 — Input-data falsification

Borrower submits fake income, transactions, assets, or employment.

**Controls:** source attestations, cross-validation, anomaly detection, random verification, fraud penalties.

### T-UW-002 — Data poisoning

Attackers manipulate training or feedback data to change model behavior.

**Controls:** provenance, signed datasets, quarantine, robust statistics, adversarial testing.

### T-UW-003 — Consent bypass

Data is accessed or reused beyond user consent.

**Controls:** scoped consent records, purpose binding, expiry, revocation, access audit.

### T-UW-004 — Stale data

Old information produces unsafe credit decisions.

**Controls:** freshness requirements, re-verification, decision expiry.

### T-UW-005 — Data-source compromise

**Controls:** multiple sources, source quality scoring, anomaly alerts, exposure reduction.

---

## 31. Model Threats

### T-UW-006 — Model evasion

Borrowers shape behavior to appear low risk without real capacity.

**Controls:** adversarial testing, behavioral diversity, manual review triggers, gradual credit limits.

### T-UW-007 — Model extraction

Attackers infer model rules and optimize fraudulent applications.

**Controls:** rate limits, output minimization, rotating secondary checks, anomaly monitoring.

### T-UW-008 — Model inversion

Sensitive training information is reconstructed.

**Controls:** privacy-preserving training, access control, output restriction, testing.

### T-UW-009 — Biased or discriminatory decisions

**Controls:** fairness testing, protected-attribute governance, explainability, appeals, human oversight where required.

### T-UW-010 — Model drift

Performance deteriorates as markets or users change.

**Controls:** continuous monitoring, champion/challenger models, automatic exposure reduction, retraining governance.

### T-UW-011 — Unauthorized model version

Service uses an unapproved or altered model.

**Controls:** signed model artifacts, model registry, code hash, decision-attestation version.

### T-UW-012 — Feature leakage

Future or prohibited data creates unrealistic performance.

**Controls:** data lineage, temporal validation, independent model review.

### T-UW-013 — Feedback-loop amplification

Model decisions change user behavior and reinforce bias or risk concentration.

**Controls:** portfolio monitoring, exploration limits, segment caps, causal analysis.

### T-UW-014 — Correlated model failure

Many products depend on one model and fail simultaneously.

**Controls:** product isolation, independent model families, portfolio stress tests, manual fallback.

### T-UW-015 — Explainability fraud

Displayed explanation does not reflect actual model inputs or policy.

**Controls:** generated explanation tied to signed decision record, audit comparison, no generic placeholder explanations.

---

## 32. Underwriting Decision Controls

Every automated decision must record:

- Decision ID.
- Subject commitment.
- Policy ID and version.
- Model ID and version.
- Input-source references.
- Data freshness.
- Risk grade.
- Maximum exposure.
- Duration limits.
- Conditions.
- Decision expiry.
- Explanation record.
- Attester signature.

No credit decision may remain valid after its expiry or material revocation.

---

# Part XIII — Payment and Settlement Threats

## 33. General Payment Threats

### T-PAY-001 — Duplicate payment posting

**Controls:** payment ID, idempotency key, provider reference uniqueness, ledger constraints.

### T-PAY-002 — Payment misallocation

Funds are applied to the wrong loan, installment, lender, or currency.

**Controls:** explicit allocation reference, validation, suspense on ambiguity, user confirmation.

### T-PAY-003 — False finality

Provisional payment is treated as final.

**Controls:** settlement-state enforcement, provider-specific finality rules, ledger posting gates.

### T-PAY-004 — Refund duplication

**Controls:** refund state machine, original-payment balance, one-time provider reference.

### T-PAY-005 — Currency-conversion manipulation

**Controls:** quoted rate lock, source record, maximum slippage, fee disclosure, reconciliation.

### T-PAY-006 — Overpayment theft

Excess is retained or redirected.

**Controls:** borrower overpayment liability account, automatic refund/credit policy, public statement.

### T-PAY-007 — Suspense-account concealment

Unresolved funds are moved to revenue or ignored.

**Controls:** suspense aging, independent review, no automatic revenue reclassification.

---

## 34. Fiat and Bank Threats

### T-PAY-008 — Forged provider callback

**Controls:** signed webhooks, mutual TLS, nonce, source allowlist, callback replay protection.

### T-PAY-009 — Bank-transfer reversal

**Controls:** provisional state, settlement delay, reversal accounting, provider reserve.

### T-PAY-010 — Wrong beneficiary account

**Controls:** beneficiary verification, checksum, dual confirmation for changes, cooling period.

### T-PAY-011 — Reconciliation mismatch

**Controls:** daily bank reconciliation, settlement-file signatures, exception queue.

### T-PAY-012 — Provider insolvency

**Controls:** concentration limits, segregated accounts, prefunding limits, diversification, rapid withdrawal.

### T-PAY-013 — Sanctions or compliance freeze

**Controls:** disclosure, product-specific contingency, alternate provider where lawful, no false promise of instant access.

### T-PAY-014 — Fiat ledger creation without cash

**Controls:** cash-backed issuance only after final settlement, independent balance proof, daily attestation.

---

## 35. Card Threats

### T-PAY-015 — Stolen-card funding

**Controls:** processor fraud checks, 3-D Secure where available, velocity limits, delayed finality.

### T-PAY-016 — Chargeback after collateral release

**Controls:** reserve period, delayed release for card-funded repayment, insurance or provider guarantee.

### T-PAY-017 — Friendly fraud

**Controls:** evidence retention, transaction confirmation, device and identity binding, dispute process.

### T-PAY-018 — Refund-to-different-instrument fraud

**Controls:** refund to original instrument unless approved exception with enhanced review.

### T-PAY-019 — Card-data breach

**Controls:** tokenization, no storage of raw card data, provider-hosted fields, strict scope isolation.

### T-PAY-020 — Merchant descriptor deception

**Controls:** clear descriptors, pre-transaction disclosure, support contact, dispute monitoring.

---

## 36. Digital-Asset Payment Threats

### T-PAY-021 — Wrong-chain payment

**Controls:** chain-bound address display, network checks, recovery policy disclosure.

### T-PAY-022 — Wrong-token payment

**Controls:** asset allowlist, token-address verification, no symbol-only matching.

### T-PAY-023 — Chain reorganization

**Controls:** confirmation thresholds, finality policy, reversal accounting.

### T-PAY-024 — Stablecoin blacklist or freeze

**Controls:** issuer-risk disclosure, asset diversification, freeze-event recovery procedure.

### T-PAY-025 — Fee-on-transfer underpayment

**Controls:** balance-delta accounting, unsupported-token rejection or adapter.

---

# Part XIV — Accounting and Reporting Threats

## 37. Accounting Integrity Threats

### T-ACC-001 — Unbalanced journal entry

**Controls:** database constraint, posting service validation, no direct ledger writes.

### T-ACC-002 — Journal alteration

**Controls:** append-only ledger, cryptographic hash chain, restricted reversal process.

### T-ACC-003 — Duplicate journal posting

**Controls:** source-event uniqueness, idempotency key, event-consumption registry.

### T-ACC-004 — Missing journal posting

**Controls:** event-to-ledger reconciliation, unposted-event alerts, close controls.

### T-ACC-005 — Wrong denomination

**Controls:** asset ID and precision dimensions, no implicit currency conversion.

### T-ACC-006 — Hidden bad debt

**Controls:** delinquency aging, reserve policy, public loss reporting, independent review.

### T-ACC-007 — Reserve overstatement

**Controls:** segregated custody proof, purpose restriction, asset valuation, reconciliation.

### T-ACC-008 — Revenue inflation

User principal, collateral, or provisional settlement is treated as revenue.

**Controls:** chart-of-accounts restrictions, accounting-policy tests, independent audit.

### T-ACC-009 — Lender-position mismatch

**Controls:** position supply to ledger reconciliation, loan-level entitlement report.

### T-ACC-010 — UFT supply mismatch

**Controls:** total-supply, vesting, bridge, burn, staking, and treasury reconciliation.

### T-ACC-011 — Cross-chain suspense concealment

**Controls:** aging, public material exposure report, mandatory recovery status.

### T-ACC-012 — Selective reporting

Losses, incidents, or liabilities are omitted from public dashboards.

**Controls:** report definitions, signed snapshots, independent verification, governance sanctions.

---

# Part XV — Insider and Privileged-Access Threats

## 38. Privileged-Key Threats

### T-INS-001 — Key theft

**Controls:** hardware security modules, multisig, geographic separation, rotation, transaction policies.

### T-INS-002 — Single-person control

**Controls:** separation of duties, threshold authorization, dual control.

### T-INS-003 — Dormant privileged account

**Controls:** automatic expiry, periodic recertification, zero-standing privilege.

### T-INS-004 — Privilege escalation

**Controls:** role graph validation, least privilege, alerting, just-in-time access.

### T-INS-005 — Emergency-key misuse

**Controls:** narrow function scope, time-bound activation, public event, mandatory review.

### T-INS-006 — Treasury transfer fraud

**Controls:** allowlists, amount tiers, timelock, dual approval, beneficiary cooling period.

### T-INS-007 — Oracle configuration sabotage

**Controls:** risk-proposal class, staged activation, price sanity checks, rollback.

### T-INS-008 — Payment routing change

**Controls:** beneficiary verification, dual control, user-visible notice, delayed activation.

### T-INS-009 — Audit-log deletion

**Controls:** append-only remote logs, multiple retention domains, hash anchoring.

### T-INS-010 — Data exfiltration

**Controls:** encryption, DLP, monitored exports, field-level access, watermarking.

---

## 39. Separation of Duties

No one actor should be able to complete all steps of:

- Proposing, approving, and executing a treasury transfer.
- Changing an oracle and activating a loan under the new price.
- Adding a payment provider and finalizing its settlement.
- Approving a model and issuing a high-value credit decision.
- Deploying code and changing the production proxy.
- Creating and resolving a reconciliation exception.
- Declaring and paying an insurance claim.

---

# Part XVI — Infrastructure and Operational Threats

## 40. Availability Threats

### T-OPS-001 — RPC outage or censorship

**Controls:** multiple providers, self-hosted nodes, user-configurable RPC, health routing.

### T-OPS-002 — Cloud-region outage

**Controls:** multi-zone deployment, tested failover, state replication, infrastructure-as-code.

### T-OPS-003 — Database corruption

**Controls:** point-in-time recovery, immutable ledger backups, checksums, restore tests.

### T-OPS-004 — Queue loss or duplication

**Controls:** durable queues, idempotent consumers, dead-letter queues, replay tools.

### T-OPS-005 — Clock drift

**Controls:** synchronized clocks, monotonic timestamps, tolerance checks.

### T-OPS-006 — Certificate expiry

**Controls:** automated renewal, expiry alerting, emergency replacement.

### T-OPS-007 — Secret expiration or rotation failure

**Controls:** secret inventory, staged rotation, dual-validity windows, rollback.

### T-OPS-008 — Capacity exhaustion

**Controls:** rate limits, autoscaling, priority for repayment and safety actions, load testing.

### T-OPS-009 — Distributed denial of service

**Controls:** edge protection, request shaping, circuit breakers, degraded read-only modes.

### T-OPS-010 — Indexer lag

**Controls:** lag indicators, direct-chain reads for critical actions, no stale-state signing.

### T-OPS-011 — Monitoring blind spot

**Controls:** independent monitors, synthetic transactions, alert-path testing.

### T-OPS-012 — Backup compromise

**Controls:** encrypted backups, separate credentials, immutable retention, restore drills.

---

## 41. Configuration Threats

### T-OPS-013 — Wrong network deployment

**Controls:** chain-ID checks, deployment manifest, address verification, environment locks.

### T-OPS-014 — Unsafe default parameter

**Controls:** schema bounds, reviewed baseline registry, staged rollout.

### T-OPS-015 — Configuration drift

**Controls:** declarative configuration, continuous diff, signed releases.

### T-OPS-016 — Feature-flag abuse

**Controls:** limited scope, audit log, expiry, no financial-rule override.

### T-OPS-017 — Production debug endpoint

**Controls:** build-time exclusion, scanning, network policy, authentication.

---

# Part XVII — Software Supply-Chain Threats

## 42. Source and Dependency Threats

### T-SUP-001 — Malicious dependency

**Controls:** lockfiles, allowlists, source review, software bill of materials, dependency scanning.

### T-SUP-002 — Dependency takeover

**Controls:** package pinning, namespace protection, vendoring critical libraries, provenance verification.

### T-SUP-003 — Typosquatting

**Controls:** automated package-name policy, review of new dependencies.

### T-SUP-004 — Compromised compiler or build tool

**Controls:** reproducible builds, trusted toolchain hashes, independent build verification.

### T-SUP-005 — CI/CD compromise

**Controls:** isolated runners, short-lived credentials, protected environments, signed artifacts.

### T-SUP-006 — Source-repository compromise

**Controls:** hardware-backed maintainer authentication, branch protection, signed commits, mandatory review.

### T-SUP-007 — Malicious release artifact

**Controls:** artifact signatures, provenance attestations, bytecode/source match.

### T-SUP-008 — Secret committed to repository

**Controls:** secret scanning, pre-commit hooks, immediate revocation process.

### T-SUP-009 — Test bypass

**Controls:** protected required checks, no administrator bypass without public incident record.

### T-SUP-010 — Audit-scope mismatch

Deployed bytecode differs from audited code.

**Controls:** audited commit hash, reproducible build, deployment verification, public manifest.

---

# Part XVIII — Interface, Wallet, and User Threats

## 43. Interface Threats

### T-UI-001 — Malicious frontend deployment

**Controls:** signed releases, content-security policy, subresource integrity, decentralized fallback interface.

### T-UI-002 — DNS or domain hijack

**Controls:** registry lock, DNSSEC where supported, certificate monitoring, alternate verified domains.

### T-UI-003 — Transaction simulation deception

**Controls:** independent transaction decoder, exact asset-flow preview, contract-address display.

### T-UI-004 — Address poisoning

**Controls:** address book, checksum, full-address confirmation, warning for first-time destination.

### T-UI-005 — Approval phishing

**Controls:** limited allowances, permit deadlines, approval dashboard, revoke tools.

### T-UI-006 — Session hijack

**Controls:** short sessions, device binding, reauthentication for sensitive actions.

### T-UI-007 — Clipboard malware

**Controls:** destination confirmation, QR and address-book options, warning on clipboard changes.

### T-UI-008 — Homograph token or contract

**Controls:** address-based asset registry, verified metadata, no symbol-only selection.

### T-UI-009 — Hidden fee or risk disclosure

**Controls:** standardized confirmation screen, machine-readable terms, no preselected consent.

### T-UI-010 — Accessibility failure causing financial error

**Controls:** accessibility testing, plain-language summaries, review step, keyboard and screen-reader support.

---

## 44. Wallet and Key Threats

### T-WAL-001 — Seed phrase theft

**Controls:** education, hardware wallets, no seed collection, phishing warnings.

### T-WAL-002 — Malicious wallet extension

**Controls:** transaction simulation, supported-wallet guidance, direct hardware confirmation.

### T-WAL-003 — Session-key overreach

**Controls:** scoped permissions, value limits, expiry, revocation.

### T-WAL-004 — Lost key

**Controls:** optional social recovery, delegated repayment, clear irrecoverability disclosure.

### T-WAL-005 — Multisig signer collusion

**Controls:** diverse signers, threshold design, spending limits, timelock.

---

# Part XIX — Market and Economic Attacks

## 45. Credit-Market Threats

### T-ECO-001 — Adverse selection

High-risk borrowers dominate a product while pricing assumes average risk.

**Controls:** underwriting, risk-based pricing, exposure caps, portfolio monitoring.

### T-ECO-002 — Moral hazard

Borrower behavior becomes riskier after funding.

**Controls:** covenants, monitoring, staged disbursement, collateral or guarantee structure.

### T-ECO-003 — Correlated default wave

Many borrowers fail under the same macroeconomic shock.

**Controls:** diversification limits, stress testing, capital reserves, product throttles.

### T-ECO-004 — Lender run

Lenders or liquidity providers simultaneously withdraw or sell positions.

**Controls:** maturity matching, no false liquidity promise, withdrawal queues, protocol-owned liquidity.

### T-ECO-005 — Interest-rate mismatch

Variable funding costs rise faster than loan revenue.

**Controls:** matched rate policy, caps/floors, repricing rules, stress tests.

### T-ECO-006 — Currency mismatch

Borrower income and debt are in different currencies.

**Controls:** disclosure, hedging, lower limits, FX stress.

### T-ECO-007 — Collateral concentration

Many loans rely on one asset or issuer.

**Controls:** debt ceilings, concentration limits, diversified collateral policy.

### T-ECO-008 — Stablecoin depeg cascade

Principal, collateral, reserve, and settlement assets fail simultaneously.

**Controls:** issuer diversification, depeg triggers, isolated markets, reserve assets.

### T-ECO-009 — Secondary-market price manipulation

Thin loan-position markets are manipulated to misstate value or trigger covenants.

**Controls:** no sole reliance on spot position prices, valuation models, liquidity filters.

### T-ECO-010 — Wash trading

Users fabricate volume, reputation, liquidity rewards, or price history.

**Controls:** related-party analysis, time-weighted economic contribution, fee-aware detection.

### T-ECO-011 — Self-lending reputation farming

Borrower and lender controlled by one actor create artificial repayment history.

**Controls:** graph analysis, economic-cost thresholds, related-wallet detection, reputation weighting.

### T-ECO-012 — Insurance arbitrage

Users take excessive risk because losses are socialized.

**Controls:** deductibles, product premiums, exclusions, exposure caps, claims review.

### T-ECO-013 — Governance-funded subsidy extraction

Actors create products primarily to receive incentives or rescue funds.

**Controls:** measurable outcomes, capped programs, sunset dates, independent review.

---

# Part XX — Compound Attack Scenarios

## 46. Compound Scenario A — UFT Oracle and Liquidation Spiral

1. Attacker accumulates leveraged short exposure to UFT.
2. Attacker manipulates thin UFT markets.
3. Oracle reports depressed price.
4. UFT-backed loans become liquidatable.
5. Liquidations sell additional UFT.
6. Insurance reserve loses value because it is UFT-heavy.
7. Governance participants panic or become economically captured.

**Required defenses:** multi-venue oracle, low UFT LTV, debt ceiling, partial liquidation, reserve diversification, market circuit breaker, burn suspension.

## 47. Compound Scenario B — Bridge Compromise and Duplicate Claims

1. Bridge validators are compromised.
2. Unbacked wUFT is minted.
3. wUFT is used as loan collateral.
4. Loans activate on satellite chain.
5. Attacker bridges or sells proceeds.
6. Canonical escrow lacks backing.
7. Lenders hold claims against nonexistent economic value.

**Required defenses:** bridge exposure cap, backing proof, collateral haircut, delayed high-value activation, satellite pause, canonical reconciliation.

## 48. Compound Scenario C — Identity Fraud and Unsecured Credit Farming

1. Synthetic identities pass one KYC provider.
2. Multiple wallets obtain uniqueness credentials.
3. Automated model approves low initial limits.
4. Accounts create artificial repayment history.
5. Limits increase.
6. Borrowers draw simultaneously and disappear.

**Required defenses:** provider diversity, privacy-preserving deduplication, graph analysis, slow limit growth, correlated draw monitoring, reserve pricing.

## 49. Compound Scenario D — Payment Reversal and Collateral Release

1. Borrower repays by card.
2. Processor reports authorization.
3. System incorrectly marks repayment final.
4. Collateral is released.
5. Borrower files chargeback.
6. Loan debt is reinstated but collateral is gone.

**Required defenses:** provisional settlement state, chargeback reserve, delayed collateral release, provider guarantee.

## 50. Compound Scenario E — Governance and Upgrade Capture

1. Attacker accumulates veUFT through purchased and delegated tokens.
2. Proposal installs malicious implementation.
3. Interface presents benign description.
4. Timelock monitoring fails.
5. Upgrade redirects fees or collateral.

**Required defenses:** decoded payload, constitutional limits, independent simulation, timelock alerting, immutable user-asset restrictions.

## 51. Compound Scenario F — Insider and Accounting Concealment

1. Treasury operator transfers reserve assets to a related counterparty.
2. Reconciliation operator marks difference as temporary suspense.
3. Reporting service excludes aged suspense.
4. Governance sees overstated reserve coverage.
5. Loss emerges during a default event.

**Required defenses:** separation of duties, immutable logs, suspense aging, external custody proof, independent reporting.

## 52. Compound Scenario G — Oracle Outage and Governance Delay

1. Primary oracle fails.
2. Fallback becomes stale.
3. Governance cannot update quickly enough.
4. Borrowing and liquidation are both unsafe.
5. Attackers exploit inconsistent interfaces.

**Required defenses:** predefined fallback states, automatic risk reduction, emergency council limited to disabling new risk, repayment and top-up preserved.

## 53. Compound Scenario H — Supply-Chain Backdoor

1. Dependency maintainer account is compromised.
2. Malicious package version enters build.
3. CI signs release.
4. Frontend changes transaction recipient.
5. Source repository appears unchanged.

**Required defenses:** pinned dependencies, SBOM, reproducible builds, artifact provenance, independent frontend verification.

---

# Part XXI — Security Controls by Architectural Layer

## 54. On-Chain Controls

- Immutable active-loan snapshots.
- Role-based access control.
- Timelocks.
- Pausable new-risk functions.
- Nonces and replay protection.
- Reentrancy protection.
- Balance-delta accounting.
- Supply caps.
- Position-supply caps.
- Collateral custody isolation.
- Explicit terminal states.
- Event completeness.
- Upgrade authorization graph.

## 55. Off-Chain Service Controls

- Strong service identity.
- Mutual TLS.
- Short-lived credentials.
- Idempotency.
- Input validation.
- Rate limiting.
- Least-privilege data access.
- Immutable audit logs.
- Secrets management.
- Queue durability.
- Disaster recovery.

## 56. Data Controls

- Encryption at rest and in transit.
- Field-level encryption for restricted data.
- Data classification.
- Consent enforcement.
- Retention limits.
- Secure deletion where legally and technically possible.
- Access logging.
- Backup protection.
- Privacy review.

## 57. Provider Controls

- Due diligence.
- Contractual service levels.
- Security requirements.
- Exposure limits.
- Adapter isolation.
- Health monitoring.
- Exit and migration plan.
- Incident-notification obligations.
- Independent reconciliation.

## 58. Human Controls

- Background checks where lawful and appropriate.
- Security training.
- Phishing-resistant authentication.
- Separation of duties.
- Mandatory leave for sensitive operations where appropriate.
- Access recertification.
- Conflict-of-interest disclosure.
- Whistleblower and incident-reporting mechanisms.

---

# Part XXII — Detection and Monitoring

## 59. Required Security Telemetry

Unified must monitor:

- Privileged contract calls.
- Governance proposals and queued executions.
- UFT total supply and burns.
- Bridge escrow and wrapped supply.
- Large treasury transfers.
- Oracle deviation and staleness.
- Liquidation rates and discounts.
- Loan activation failures.
- Duplicate or replayed messages.
- Payment reversals and chargebacks.
- Reconciliation differences.
- Suspense aging.
- Failed identity verification patterns.
- Credit-model drift.
- Unusual account graphs.
- API abuse.
- Login and key anomalies.
- CI/CD and deployment changes.
- Data exports.
- Backup failures.

## 60. Security Alerts

Alerts must be classified:

```text
SEV-0 — Existential protocol or supply threat
SEV-1 — Active material asset loss or governance compromise
SEV-2 — High-risk exploit attempt or significant service failure
SEV-3 — Contained security event requiring investigation
SEV-4 — Low-risk anomaly or policy violation
```

## 61. Alert Quality Requirements

- Every critical alert has a named owner.
- Every alert has a runbook.
- Alert delivery is tested.
- Suppression requires recorded approval.
- Repeated false positives require rule improvement, not permanent disabling without replacement.

---

# Part XXIII — Incident Response and Recovery

## 62. Incident Lifecycle

```text
DETECTED
→ TRIAGED
→ CONTAINED
→ INVESTIGATED
→ ERADICATED
→ RECOVERED
→ REVIEWED
→ CLOSED
```

## 63. Immediate Containment Priorities

1. Prevent additional asset loss.
2. Preserve repayment and risk-reducing actions.
3. Isolate compromised provider, chain, asset, or module.
4. Preserve evidence.
5. Inform authorized incident leadership.
6. Publish user communication when material.
7. Begin reconciliation.

## 64. Emergency Actions

Permitted emergency actions may include:

- Pausing new loan activation.
- Pausing a compromised asset or collateral type.
- Pausing new bridge messages.
- Pausing new provider settlement.
- Disabling an oracle or liquidation route.
- Revoking compromised roles.
- Rotating keys.
- Activating read-only or degraded mode.

Emergency authority must not permit unrestricted seizure, minting, or retroactive loan modification.

## 65. Evidence Preservation

Preserve:

- Contract events.
- Node data.
- Logs.
- Provider callbacks.
- Database snapshots.
- CI/CD records.
- Access records.
- Governance payloads.
- Communication records.
- Memory or host images where appropriate.

## 66. User Communication

Material incident notices should state:

- What happened.
- What is known and unknown.
- Which systems and assets are affected.
- Which actions users should take.
- Which functions remain safe.
- Whether repayment, withdrawal, or collateral actions are available.
- When the next update will be issued through established operational procedures.

No communication may falsely state that funds are safe before reconciliation confirms it.

## 67. Loss and Recovery Accounting

Every incident with financial impact must produce:

- Loss estimate.
- Asset and liability mapping.
- Affected-user list.
- Recovery sources.
- Insurance or reserve treatment.
- Journal entries.
- Public material-impact report.

## 68. Post-Incident Review

Every SEV-0, SEV-1, and material SEV-2 incident requires:

- Root-cause analysis.
- Timeline.
- Control-failure analysis.
- Economic impact.
- User impact.
- Corrective actions.
- Owners and deadlines.
- Independent review.
- Public summary unless prohibited by law or active security concerns.

---

# Part XXIV — Security Testing Program

## 69. Threat-Driven Testing

Every threat in this document must map to at least one of:

- Preventive control test.
- Detection test.
- Recovery test.
- Economic simulation.
- Manual procedure exercise.

## 70. Smart-Contract Test Classes

- Unit tests.
- Integration tests.
- Fuzz tests.
- Stateful invariant tests.
- Differential tests.
- Fork tests.
- Upgrade tests.
- Gas-bound tests.
- Malicious-token tests.
- Reentrancy tests.
- Signature replay tests.
- Oracle-failure tests.
- Bridge-message tests.

## 71. Economic Security Simulations

Required scenarios include:

- UFT decline of 30%, 50%, 80%, and 95%.
- Stablecoin depeg.
- 70% liquidity reduction.
- Mass UFT-backed liquidation.
- Syndicated-loan default wave.
- Unsecured-loan fraud cluster.
- Insurance reserve impairment.
- Bridge insolvency.
- Card chargeback spike.
- Bank-provider freeze.
- Governance concentration.
- Staking-withdrawal run.
- Treasury runway collapse.

## 72. Operational Exercises

At least periodically, Unified must run:

- Key-compromise drill.
- Oracle-failure drill.
- Bridge-pause drill.
- Payment-provider outage drill.
- Database-restore drill.
- Governance-malicious-proposal drill.
- Frontend-compromise drill.
- Incident-communications drill.
- Reconciliation-break drill.

## 73. Penetration Testing

Scope must include:

- Web and mobile applications.
- APIs.
- Operations console.
- Identity flows.
- Payment webhooks.
- Cloud configuration.
- CI/CD.
- Wallet and signing flows.
- Smart contracts.
- Cross-chain adapters.

## 74. Red-Team Program

Red-team exercises should target compound attack paths rather than isolated defects.

Example objectives:

- Obtain principal using synthetic identities.
- Trigger wrongful liquidation.
- Introduce a malicious governance payload.
- Create a duplicate cross-chain claim.
- Exfiltrate restricted financial data.
- Conceal a treasury loss through reconciliation.

## 75. Bug Bounty

The public bounty should prioritize:

- User-asset theft.
- UFT mint or backing failure.
- Governance takeover.
- Active-loan mutation.
- Collateral bypass.
- Duplicate claims.
- Payment finality bypass.
- Identity or privacy compromise.
- Critical denial of service.

Safe-harbor terms and responsible-disclosure procedures must be public.

---

# Part XXV — Security Invariants

## 76. Foundational Security Invariants

1. Canonical UFT supply never exceeds the genesis maximum.
2. No governance or privileged role can create a post-genesis mint authority.
3. Wrapped UFT supply never exceeds corresponding canonical backing.
4. One underlying UFT cannot create duplicate voting power.
5. One underlying asset cannot secure incompatible senior claims.
6. One offer cannot activate more than one loan.
7. One payment cannot reduce debt more than once.
8. One cross-chain message cannot execute more than once.
9. Aggregate lender positions cannot exceed funded economic rights.
10. Active loan economics cannot change outside the accepted amendment process.
11. A terminal loan cannot return to an active state.
12. Collateral cannot be released while secured debt remains unpaid unless the agreed substitution or refinancing process completes.
13. Principal cannot become finally disbursed without satisfaction of activation conditions.
14. Provisional settlement cannot be represented as final settlement.
15. A card authorization alone cannot trigger irreversible collateral release.
16. A stale or invalid oracle cannot authorize new borrowing or liquidation.
17. Governance cannot seize a specific user’s assets.
18. Emergency powers cannot mint UFT or rewrite active loans.
19. Posted journal entries cannot be edited or deleted.
20. Every posted journal entry balances.
21. User principal and collateral cannot be recognized as protocol revenue.
22. Suspense balances cannot be silently reclassified as revenue.
23. Rewards cannot exceed funded resources.
24. Insurance claims cannot exceed eligible loss and available policy limits.
25. Reserve assets cannot be counted simultaneously for incompatible mandates.
26. Privileged actions require authenticated, authorized, and auditable execution.
27. Every critical upgrade passes storage, invariant, and active-loan compatibility tests.
28. Every automated credit decision identifies its approved policy and model version.
29. Revoked or expired credentials cannot authorize new exposure.
30. Sensitive identity data is not written unencrypted to public immutable storage.
31. Repayment remains available during emergency controls wherever technically safe.
32. User-facing state cannot override canonical contract or ledger state.
33. Every liquidation is reproducible from recorded inputs and policy versions.
34. Every external callback is authenticated and idempotent.
35. Every material reconciliation difference enters an explicit exception state.
36. No single person controls proposal, approval, execution, and reconciliation of a material treasury transfer.
37. No production artifact is deployed without provenance and source-to-bytecode verification.
38. Security monitoring cannot be disabled silently.
39. Material incidents cannot be closed without reconciliation and corrective action.
40. A failed external operation cannot be silently treated as successful.

---

# Part XXVI — Risk Register Baseline

## 77. Initial Highest-Priority Risks

| ID | Risk | Initial rating | Required treatment before unrestricted launch |
|---|---|---:|---|
| R-001 | Active-loan mutation through upgrade | Existential | Immutable snapshots, upgrade simulation, independent audit |
| R-002 | Unauthorized UFT mint or wrapped overissuance | Existential | Immutable cap, backing proofs, continuous reconciliation |
| R-003 | Bridge compromise | Existential | Exposure caps, isolation, delayed high-value settlement, audits |
| R-004 | Payment finality error releasing collateral | Critical | Provisional states, provider guarantees, reversal testing |
| R-005 | Oracle manipulation and liquidation cascade | Critical | Multi-source oracle, debt ceilings, partial liquidation |
| R-006 | Governance capture | Critical | veUFT locks, tiers, timelocks, constitutional limits |
| R-007 | Synthetic identity unsecured-loan fraud | Critical | Deduplication, slow exposure growth, fraud graph monitoring |
| R-008 | Privileged-key compromise | Critical | HSM, multisig, least privilege, emergency revocation |
| R-009 | Accounting concealment or reserve overstatement | Critical | Immutable ledger, segregation, independent reconciliation |
| R-010 | Supply-chain compromise | Critical | Reproducible builds, provenance, dependency controls |
| R-011 | UFT reflexive collateral collapse | Critical | Low LTV, reserve diversification, isolation |
| R-012 | Syndicate claim inflation | High | Position-supply invariant and reconciliation |
| R-013 | Model drift or correlated underwriting failure | High | Monitoring, limits, challenger models |
| R-014 | Treasury insider fraud | High | Separation of duties, timelocks, custody proofs |
| R-015 | Frontend transaction substitution | High | signed releases, transaction decoder, fallback UI |

The risk register must be maintained as a versioned operational artifact. Each risk must have an owner, treatment status, evidence, review date, and residual-risk decision.

---

# Part XXVII — Launch Security Gates

## 78. Mandatory Pre-Launch Gates

Unified shall not launch unrestricted production lending until all of the following are satisfied.

### 78.1 Architecture gates

- Constitution ratified.
- Domain model approved.
- State machines approved.
- Accounting specification approved.
- UFT tokenomics approved.
- Threat model approved.
- Protocol invariants encoded as tests.

### 78.2 Smart-contract gates

- Critical contracts complete.
- Full test suite passes.
- Invariant tests pass under extended fuzzing.
- At least two independent audits for highest-value contracts.
- All critical and high findings resolved or explicitly contained.
- Deployment bytecode matches audited source.
- Emergency controls tested.

### 78.3 Economic gates

- UFT price-stress tests pass.
- Bridge-loss stress passes within exposure limits.
- Insurance reserve meets launch target.
- Liquidity depth meets minimum threshold.
- Collateral debt ceilings configured.
- Unsecured lending begins under capped exposure.

### 78.4 Operational gates

- Incident response tested.
- Key management operational.
- Reconciliation operational.
- Backups restored successfully.
- Monitoring and alerting tested.
- Provider failover procedures documented.
- Security contacts and escalation paths active.

### 78.5 Privacy and identity gates

- Data protection assessment complete.
- Credential revocation works.
- Restricted data is encrypted.
- Access review complete.
- Privacy leakage testing complete.

### 78.6 Payment gates

- Callback authentication tested.
- Duplicate and reversal scenarios tested.
- Provisional/final states enforced.
- Provider settlement reconciles.
- Chargeback reserve rules configured.

### 78.7 Governance gates

- Proposal simulation available.
- Timelock is sole execution path.
- Emergency powers are bounded.
- Cross-chain vote duplication is prevented.
- Treasury transfer controls are tested.

---

# Part XXVIII — Required Security Artifacts

## 79. Artifacts to Produce

1. `PROTOCOL_INVARIANTS.md`
2. `SECURITY_REQUIREMENTS_TRACEABILITY_MATRIX.md`
3. `PRIVILEGED_ROLE_MATRIX.md`
4. `TRUST_BOUNDARY_DIAGRAMS.md`
5. `DATA_FLOW_DIAGRAMS.md`
6. `SMART_CONTRACT_ATTACK_SURFACE.md`
7. `ORACLE_SECURITY_POLICY.md`
8. `BRIDGE_SECURITY_POLICY.md`
9. `PAYMENT_FINALITY_POLICY.md`
10. `IDENTITY_AND_PRIVACY_SECURITY_POLICY.md`
11. `MODEL_RISK_MANAGEMENT_POLICY.md`
12. `KEY_MANAGEMENT_AND_SIGNING_POLICY.md`
13. `INCIDENT_RESPONSE_PLAN.md`
14. `DISASTER_RECOVERY_PLAN.md`
15. `SECURE_SOFTWARE_DEVELOPMENT_LIFECYCLE.md`
16. `AUDIT_AND_BUG_BOUNTY_POLICY.md`
17. `SECURITY_MONITORING_CATALOG.md`
18. `RISK_REGISTER.md`
19. `LAUNCH_SECURITY_GATE_REPORT.md`
20. `POST_LAUNCH_SECURITY_REVIEW_SCHEDULE.md`

---

# Part XXIX — Security Requirements Traceability

## 80. Traceability Rule

Every critical security requirement must map to:

- A governing constitutional rule.
- A domain entity or state transition.
- An implementation component.
- A test.
- A monitoring control.
- A recovery procedure.
- An accountable owner.

Example:

| Requirement | Component | Test | Monitor | Recovery |
|---|---|---|---|---|
| Offer cannot be consumed twice | OfferManager | Concurrent replay test | Duplicate nonce alert | Reject second activation |
| Wrapped UFT remains backed | Bridge escrow | Mint-cap invariant | Supply/backing monitor | Pause mint and bridge |
| Card payment not final before settlement | Payment router | Chargeback scenario | Provisional aging alert | Reverse allocation |
| Active loan terms immutable | Loan account | Upgrade differential test | Loan hash monitor | Rollback/migration |

No requirement is considered implemented merely because it appears in documentation.

---

# Part XXX — Residual Risk and Disclosure

## 81. Residual Risk Categories

Even after controls, Unified retains risk from:

- Smart-contract defects.
- Blockchain failures.
- Bridge compromise.
- Oracle failures.
- UFT volatility.
- Stablecoin depegs.
- Borrower default.
- Fraud.
- Governance capture.
- Regulatory action.
- Payment-provider insolvency.
- Model error.
- Privacy leakage.
- User-key compromise.
- Market illiquidity.

## 82. Disclosure Standard

Risk disclosures must be:

- Specific to the product.
- Written in plain language.
- Available before authorization.
- Consistent with machine-readable terms.
- Updated when material conditions change.

The protocol must not describe a product as insured, guaranteed, decentralized, private, final, or risk-free unless the underlying system actually satisfies the claim under disclosed conditions.

---

# Part XXXI — Amendment and Maintenance

## 83. Review Frequency

This threat model must be reviewed:

- Before every major protocol release.
- Before adding a new chain.
- Before adding a new bridge.
- Before adding a new payment or identity provider.
- Before activating a new collateral class.
- Before materially changing UFT economics.
- After every SEV-0 or SEV-1 incident.
- At least quarterly during active development.
- At least annually after stabilization.

## 84. Amendment Requirements

Every amendment must include:

- Threat or control changed.
- Reason.
- Affected components.
- New tests.
- New monitoring.
- Migration effect.
- Active-loan compatibility assessment.
- Residual-risk decision.

---

# Appendix A — STRIDE Mapping

| STRIDE category | Unified examples |
|---|---|
| Spoofing | Stolen wallet, forged attester, fake webhook, malicious relayer |
| Tampering | Loan mutation, journal alteration, oracle manipulation, model change |
| Repudiation | Disputed signature, denied payment, denied governance execution |
| Information disclosure | KYC leak, chat metadata, model inversion, log exposure |
| Denial of service | Repayment censorship, bridge halt, RPC outage, governance spam |
| Elevation of privilege | Admin takeover, role escalation, proxy-admin bypass |

---

# Appendix B — Threat-to-Workstream Ownership

| Threat family | Primary owner | Supporting owners |
|---|---|---|
| Protocol and smart contracts | Protocol Security | Lending, Collateral, Governance |
| UFT and economic security | Token Economics | Treasury, Risk, Protocol Security |
| Oracle and liquidation | Risk Engineering | Collateral, Market Operations |
| Bridge and cross-chain | Cross-Chain Security | Protocol Security, Operations |
| Identity and privacy | Identity Security | Legal/Compliance, Platform Security |
| Underwriting and models | Model Risk | Credit, Data, Security |
| Payments | Payment Security | Accounting, Operations, Compliance |
| Accounting | Financial Controls | Engineering, Treasury, Audit |
| Insider | Security Governance | Human Resources, Internal Audit |
| Infrastructure | Platform Security | SRE, Engineering |
| Supply chain | Product Security | Engineering Productivity, Release Management |
| User interface and wallet | Product Security | Frontend, Support, Communications |

---

# Appendix C — Minimum Security Metrics

Unified should publish or internally track:

- Critical vulnerabilities open.
- Mean time to contain incidents.
- Privileged accounts by role.
- Unreviewed governance payloads.
- Oracle deviation events.
- Bridge backing ratio.
- UFT supply reconciliation difference.
- Loan-position reconciliation difference.
- Payment reversal rate.
- Chargeback rate.
- Suspense aging.
- Identity fraud rate.
- Credit-model default by risk grade.
- Infrastructure recovery time.
- Backup restore success.
- Dependency vulnerabilities.
- Bug-bounty resolution time.
- Security-test coverage of critical invariants.

---

# Appendix D — Initial Security Decision Register

| Decision | Baseline |
|---|---|
| Active-loan terms | Immutable snapshot with version-pinned policies |
| UFT token contract | Immutable, fixed genesis supply, no minter |
| Governance | veUFT, snapshots, proposal tiers, timelock |
| Emergency authority | Narrow pause and isolation powers only |
| Collateralized UFT voting | Disabled |
| Wrapped UFT | Fully escrow-backed |
| Bridge exposure | Capped per bridge and globally |
| Oracle model | Multi-source, freshness and deviation checks |
| Card settlement | Provisional until finality policy completes |
| Ledger | Append-only double entry |
| Critical upgrades | Timelocked, audited, active-loan compatibility tested |
| Privileged operations | Multisig and separation of duties |
| Identity data | Restricted, encrypted, never public by default |
| Automated credit | Signed decision with policy and model version |
| Production artifacts | Signed and reproducibly built |

---

# Conclusion

Unified is intentionally designed as a complex financial ecosystem. Complexity increases capability, but it also multiplies the number of ways in which financial, technical, governance, privacy, operational, and human failures can combine.

This specification therefore treats security as a system property rather than a smart-contract feature. Unified is secure only when:

- Loan rules remain immutable and enforceable.
- UFT supply and backing remain correct.
- Governance remains bounded and legitimate.
- Oracles and liquidation remain reproducible.
- Cross-chain actions remain canonical and idempotent.
- Identity and credit systems resist fraud without sacrificing privacy.
- Payments respect real settlement finality.
- Accounting exposes rather than conceals losses.
- Privileged actors remain constrained.
- Infrastructure can fail without silently corrupting financial rights.
- Incidents can be detected, contained, reconciled, and learned from.

The companion **Unified Protocol Invariants and Formal Verification Specification v0.1** converts the constitutional, accounting, economic, and threat-model rules into executable invariants, formal properties, fuzz targets, model-checking requirements, and launch-blocking verification gates.
