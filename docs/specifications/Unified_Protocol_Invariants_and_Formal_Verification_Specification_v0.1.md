# Unified Protocol Invariants and Formal Verification Specification

**Version:** 0.1  
**Status:** Foundational architecture specification  
**System:** Unified Protocol and Unified Coin (UFT)  

---

## 1. Purpose

This specification converts Unified's constitutional rules, domain definitions, loan state machines, accounting principles, UFT economic controls, and adversarial threat model into testable formal properties.

Its purpose is to ensure that every material safety claim can be represented as one or more of the following:

- a mathematical invariant;
- a state-transition precondition or postcondition;
- an executable smart-contract assertion;
- a stateful fuzzing property;
- a symbolic-execution objective;
- a model-checking property;
- a differential test;
- an accounting reconciliation equation;
- a deployment or launch gate.

No critical security property may exist only as narrative documentation.

---

## 2. Governing hierarchy

This specification is subordinate to and must remain consistent with:

1. `Unified_Constitution_v0.1.md`;
2. `Unified_Domain_Model_v0.1.md`;
3. `Universal_Loan_Model_and_State_Machines_v0.1.md`;
4. `Unified_Financial_Accounting_Specification_v0.1.md`;
5. `UFT_Tokenomics_and_Economic_Security_Specification_v0.1.md`;
6. `Unified_Threat_Model_and_Adversarial_Security_Specification_v0.1.md`.

Where two subordinate rules conflict, the more restrictive safety interpretation applies until the conflict is resolved through an Architecture Decision Record.

---

# Part I — Formal Verification Doctrine

## 3. Verification objectives

Unified verification protects six fundamental properties:

### 3.1 Safety

Nothing forbidden can occur.

Examples:

- UFT supply cannot exceed its cap;
- collateral cannot be released while secured debt remains;
- an accepted offer cannot be consumed twice;
- a provisional payment cannot extinguish final debt;
- governance cannot rewrite active loan economics.

### 3.2 Liveness

Required progress remains possible under defined assumptions.

Examples:

- a borrower can repay an active loan;
- a fully repaid borrower can recover releasable collateral;
- a lender can claim recoveries after an objectively valid default;
- a queued governance action eventually becomes executable or expires;
- a failed cross-chain operation reaches recovery or terminal failure.

### 3.3 Conservation

Assets, liabilities, claims, shares, and token supplies reconcile.

### 3.4 Authorization

Only permitted actors and modules can perform each transition.

### 3.5 Determinism

The same canonical inputs produce the same economic result.

### 3.6 Recoverability

External and partial failures enter bounded, observable states from which safe recovery is defined.

---

## 4. Verification principles

### 4.1 Properties before implementations

Critical invariants must be written before the production implementation that is expected to satisfy them.

### 4.2 Small trusted computing base

The protocol kernel, canonical registries, asset custody, loan accounting, UFT supply logic, and authority checks form the most sensitive trusted computing base. They receive the highest verification priority.

### 4.3 Assume arbitrary call order

Tests must not assume users call functions in the intended interface order. Adversarial sequences, repeated calls, partial calls, callbacks, reentrancy, stale messages, and delayed finality must be explored.

### 4.4 Verify composition

A policy module may be locally correct but unsafe when combined with another module. Unified must verify both individual modules and supported policy compositions.

### 4.5 Verify failure paths

Reverts, timeouts, bridge delays, oracle failures, payment reversals, auctions without bidders, and provider outages are first-class verification scenarios.

### 4.6 Prove bounded authority

Administrative and governance powers must be formally constrained, not merely governed by operational policy.

### 4.7 Distinguish assumptions from proofs

Every property must document its environmental assumptions. A proof under an invalid oracle or bridge assumption is not an unconditional proof.

---

# Part II — Formal Model

## 5. System state

The abstract Unified state is represented as:

```text
Σ = {
  Accounts,
  Assets,
  Tenders,
  Offers,
  UnderwritingDecisions,
  Loans,
  Obligations,
  FundingCommitments,
  LenderPositions,
  CollateralPositions,
  Payments,
  Settlements,
  LedgerEntries,
  UFTState,
  GovernanceState,
  BridgeState,
  OracleState,
  InsuranceState,
  TreasuryState,
  Roles,
  Nonces,
  Time
}
```

A protocol operation is a transition:

```text
T(actor, input, Σpre) → (Σpost, events, result)
```

A valid transition must satisfy:

```text
Authorization(actor, input, Σpre)
∧ Preconditions(input, Σpre)
∧ Invariants(Σpre)
∧ Postconditions(input, Σpre, Σpost)
∧ Invariants(Σpost)
```

---

## 6. Property classes

Each property receives a stable identifier and one of these classes:

| Prefix | Property class |
|---|---|
| `INV-SUP` | UFT supply and representation |
| `INV-AUTH` | authorization and roles |
| `INV-LOAN` | loan agreement and lifecycle |
| `INV-FUND` | funding, syndication, and positions |
| `INV-COL` | collateral and custody |
| `INV-INT` | interest and debt accounting |
| `INV-PAY` | payment and settlement |
| `INV-ACC` | financial ledger and conservation |
| `INV-LIQ` | liquidation and recovery |
| `INV-REFI` | refinancing and restructuring |
| `INV-ORC` | oracle validity |
| `INV-GOV` | governance and emergency authority |
| `INV-STK` | staking, rewards, and slashing |
| `INV-BRG` | cross-chain messaging and backing |
| `INV-ID` | identity, credentials, and privacy |
| `INV-UW` | underwriting and exposure |
| `INV-INS` | insurance and reserves |
| `LIVE-*` | liveness properties |
| `REC-*` | recovery properties |

Every production contract and service must declare which property identifiers it implements or depends on.

---

# Part III — Global Conservation Invariants

## 7. Asset conservation

### INV-ACC-001 — Global accounted asset conservation

For every asset `a` and accounting boundary `b`:

```text
OpeningBalance(a,b)
+ Inflows(a,b)
- Outflows(a,b)
+ Revaluations(a,b)
= ClosingBalance(a,b)
```

Unexplained differences must remain in an explicit reconciliation or suspense account and cannot be recognized as revenue.

### INV-ACC-002 — Balanced journal entries

For every posted journal entry `j` and denomination `d`:

```text
Σ Debits(j,d) = Σ Credits(j,d)
```

### INV-ACC-003 — Immutable posted history

A posted journal entry cannot be edited or deleted. Correction requires:

```text
OriginalEntry + ReversalEntry + ReplacementEntry
```

with explicit references.

### INV-ACC-004 — Idempotent event posting

For each canonical source event identifier `e`:

```text
Count(PostedJournalEntries where sourceEventId = e and postingType = PRIMARY) ≤ 1
```

### INV-ACC-005 — Control-to-custody reconciliation

For each on-chain vault or regulated custody account:

```text
LedgerControlledBalance(asset, custodian)
= ObservableCustodyBalance(asset, custodian)
± ExplicitPendingSettlement(asset, custodian)
```

### INV-ACC-006 — No hidden negative reserve

A reserve cannot be represented as funded when its available asset balance is below zero or below its disclosed restricted liability.

### INV-ACC-007 — Suspense isolation

Funds in suspense cannot be distributed, burned, counted as treasury surplus, or used to satisfy solvency ratios until resolved.

---

# Part IV — UFT Supply, Allocation, and Representation

## 8. Canonical UFT supply

Let:

- `G` = genesis-minted UFT;
- `B(t)` = cumulative canonical UFT permanently burned by time `t`;
- `S(t)` = canonical total supply at time `t`.

### INV-SUP-001 — Fixed cap

```text
∀t: S(t) ≤ G = 1,000,000,000 UFT
```

### INV-SUP-002 — Supply equation

```text
S(t) = G - B(t)
```

### INV-SUP-003 — No post-genesis mint path

After genesis initialization, no externally reachable transition may increase canonical total supply.

### INV-SUP-004 — Burn irreversibility

A canonical burn permanently decreases total supply and cannot later be restored through minting, accounting, or bridge release.

### INV-SUP-005 — Allocation reconciliation

At genesis:

```text
Σ GenesisAllocationVaultBalances = G
```

### INV-SUP-006 — Vesting conservation

For each vesting allocation `v`:

```text
Released(v,t) + Locked(v,t) + RevokedAndReturned(v,t) = InitialAllocation(v)
```

### INV-SUP-007 — Release bound

```text
Released(v,t) ≤ VestedAmount(v,t)
```

### INV-SUP-008 — No double representation

One underlying UFT unit cannot simultaneously be counted as two independent economic units across liquid UFT, sUFT backing, governance locks, collateral custody, and bridge backing.

Compatible derivative rights may exist only when their shared backing and priority are explicit.

---

## 9. Cross-chain UFT backing

For each satellite chain `c`:

- `Wc` = outstanding wrapped UFT on chain `c`;
- `Ec` = canonical UFT restricted in escrow for chain `c`;
- `Pc` = verified pending mint less pending burn finalization.

### INV-SUP-009 — Per-chain backing

```text
Wc ≤ Ec + Pc
```

### INV-SUP-010 — Global backing

```text
Σc Wc ≤ Σc Ec + Σc Pc
```

### INV-SUP-011 — Backing exclusivity

Canonical UFT committed as bridge backing cannot simultaneously be withdrawn, staked as free safety capital, used as free collateral, or counted as treasury liquidity.

### INV-SUP-012 — Satellite burn reconciliation

A satellite permanent burn must either:

1. cause an equivalent canonical burn; or
2. reduce the canonical escrow obligation by the same amount under the approved bridge accounting policy.

### INV-SUP-013 — Bridge exposure bounds

Outstanding UFT exposure must remain within the active per-bridge and aggregate governance-approved limits.

---

# Part V — Authorization and Authority Bounds

## 10. Role safety

### INV-AUTH-001 — Deny by default

An operation without an explicit authorization path must fail.

### INV-AUTH-002 — Least authority

No role may perform an operation outside its registered permission set and scope.

### INV-AUTH-003 — Role separation

The following powers must not be held by one ordinary operational key:

- proposing a sensitive upgrade;
- approving it;
- executing it;
- changing oracle sources;
- moving treasury funds;
- editing accounting reconciliation outcomes.

### INV-AUTH-004 — No hidden superuser

No contract may contain an undocumented route that transfers user assets, creates UFT, alters active loan economics, or bypasses governance controls.

### INV-AUTH-005 — Signature binding

Every signed instruction must bind at least:

```text
Signer
Action type
Canonical contract or service domain
Chain or settlement domain
Relevant entity identifier
Economic terms hash
Nonce
Expiry
```

### INV-AUTH-006 — Nonce uniqueness

A consumed nonce cannot authorize another state-changing operation within the same authorization domain.

### INV-AUTH-007 — Expiry enforcement

Expired signatures, offers, credentials, quotes, and provider authorizations cannot be consumed.

### INV-AUTH-008 — Delegation scope

A delegate cannot exceed the amount, duration, entity scope, asset scope, or action scope granted by the principal.

### INV-AUTH-009 — Revocation effectiveness

Once a delegation or credential is validly revoked, subsequent operations relying solely on it must fail, subject only to explicitly defined finality rules for operations already irreversibly settled.

---

# Part VI — Loan Agreement Invariants

## 11. Agreement formation

### INV-LOAN-001 — Unique canonical loan identity

Every activated loan has one unique canonical loan identifier and one canonical home authority.

### INV-LOAN-002 — One offer, one consumption

```text
Count(Loans activated from Offer o) ≤ 1
```

unless the offer explicitly represents a multi-draw facility with bounded draw rights.

### INV-LOAN-003 — Agreement hash integrity

The activated agreement hash must equal the hash approved by all required parties and consumed by the activation transition.

### INV-LOAN-004 — Immutable activation snapshot

After activation, the following cannot change except through an agreed amendment mechanism:

- borrower identity commitment;
- lender or lender-position rights;
- principal obligation;
- denomination;
- interest policy version;
- repayment schedule version;
- collateral policy version;
- liquidation policy version;
- settlement policy version;
- payment waterfall;
- maturity and grace rules;
- fee policy applicable to the loan;
- governing home authority.

### INV-LOAN-005 — Policy-version existence

Every referenced policy version must be registered, active for origination at acceptance time, and code-hash verified.

### INV-LOAN-006 — No retroactive upgrade

A protocol upgrade cannot cause an active loan to execute against a different economic policy version unless the original agreement explicitly authorizes that migration and all required parties consent.

### INV-LOAN-007 — Activation completeness

A loan cannot become `ACTIVE` unless every applicable readiness predicate is satisfied:

```text
AgreementValid
∧ RequiredSignaturesValid
∧ UnderwritingSatisfied
∧ FundingSatisfied
∧ CollateralSatisfied
∧ GuaranteeOrInsuranceSatisfied
∧ RequiredFeesFunded
∧ RequiredSettlementFinalityReached
∧ CrossChainReadinessSatisfied
```

### INV-LOAN-008 — Terminal state finality

A terminal loan state cannot transition back to an active servicing state.

### INV-LOAN-009 — No duplicate obligation

The same activation event cannot create duplicate principal obligations.

### INV-LOAN-010 — Borrower repayment right

For every active or delinquent loan that is not finally extinguished, a valid repayment route must remain available except during a narrowly bounded technical condition that cannot safely accept payment.

### INV-LOAN-011 — Closure completeness

A loan can reach final closure only after all required obligations, collateral dispositions, lender distributions, refunds, and unresolved settlement states are accounted for.

---

## 12. Loan state-transition properties

### INV-LOAN-012 — Valid transition graph

A loan dimension may move only along an edge defined in the approved state machine.

### INV-LOAN-013 — State compatibility

Forbidden state combinations must be unreachable. Examples:

```text
Servicing = REPAID ∧ Collateral = LOCKED without release obligation
Servicing = ACTIVE ∧ Origination ≠ ACTIVATED
Settlement = FINAL ∧ Payment = REVERSED without correction state
Loan = CLOSED ∧ UnresolvedSeniorClaim > 0
```

### INV-LOAN-014 — Transition atomicity

For atomic transitions, either all required state changes and asset movements succeed or none succeed.

### INV-LOAN-015 — Transition evidence

Every material state transition emits or persists a uniquely identifiable transition record containing pre-state, post-state, actor, timestamp, cause, and economic effects.

---

# Part VII — Funding, Syndication, and Lender Positions

## 13. Funding conservation

Let:

- `C` = accepted funded commitments;
- `D` = principal disbursed;
- `R` = returned unused commitments;
- `F` = authorized origination deductions.

### INV-FUND-001 — Funding conservation

```text
C = D + R + F
```

subject to explicit settlement-pending balances.

### INV-FUND-002 — No activation below minimum

A funding-round loan cannot activate unless the minimum funding condition is met.

### INV-FUND-003 — No overfunding

Accepted commitments cannot exceed the maximum funding limit unless the agreement explicitly defines oversubscription allocation and refund rules.

### INV-FUND-004 — Position-right conservation

For each loan and economic class:

```text
Σ OutstandingPositionRights ≤ OutstandingLoanRights
```

### INV-FUND-005 — Principal-share conservation

For pro-rata positions:

```text
Σ PositionPrincipalShare = 100%
```

For tranche structures, aggregate contractual claims must equal the issued funding and authorized economic enhancements.

### INV-FUND-006 — Distribution conservation

For each borrower payment distribution:

```text
AmountAllocatedToPositions
+ ProtocolAuthorizedDeductions
+ BorrowerRefund
+ SettlementSuspense
= FinalizedPaymentAmount
```

### INV-FUND-007 — Waterfall priority

A junior claim cannot receive a distribution that violates the active seniority waterfall.

### INV-FUND-008 — Transfer continuity

A lender-position transfer changes the owner of future rights but does not duplicate or destroy the underlying loan obligation.

### INV-FUND-009 — Transfer eligibility

A position cannot transfer unless both the position state and transfer policy permit it and all required identity or jurisdiction conditions are satisfied.

### INV-FUND-010 — Accrual cut-off determinism

On transfer, accrued and future economic rights must be allocated according to one deterministic settlement timestamp or block reference.

### INV-FUND-011 — Encumbrance exclusivity

A lender position pledged as collateral cannot simultaneously be transferred as unencumbered property.

---

# Part VIII — Principal, Interest, Fees, and Debt

## 14. Debt accounting

For loan `l` at time `t`:

```text
GrossDebt(l,t) =
  OutstandingPrincipal(l,t)
+ AccruedInterest(l,t)
+ CapitalizedInterest(l,t)
+ AuthorizedFees(l,t)
+ AuthorizedPenalties(l,t)
+ RecoverableCosts(l,t)
- FinalizedCredits(l,t)
```

### INV-INT-001 — Non-negative components

No debt component may become negative except an explicit borrower-credit or refundable-overpayment account.

### INV-INT-002 — Principal bound

Outstanding principal cannot exceed legally activated principal plus authorized capitalized amounts less finalized principal payments.

### INV-INT-003 — Interest determinism

Given the same policy version, principal history, rate observations, timestamps, day-count convention, rounding policy, and payment history, accrued interest must be identical.

### INV-INT-004 — No interest before commencement

Interest cannot accrue before the contractually defined commencement condition.

### INV-INT-005 — No interest after extinguishment

Interest cannot accrue after the debt is finally extinguished, except explicitly authorized post-judgment or recovery costs.

### INV-INT-006 — Rate bounds

Variable and hybrid rates must remain within the active contractual floor and cap.

### INV-INT-007 — Stale benchmark behavior

A stale or invalid benchmark cannot silently produce a new rate. The policy must execute its predefined fallback, freeze, or safe-mode behavior.

### INV-INT-008 — Rounding conservation

Rounding cannot systematically create or destroy material value. Residual rounding amounts must be allocated through the disclosed residual policy.

### INV-INT-009 — Fee authorization

A fee can be charged only if authorized by the active loan agreement or protocol rule disclosed before the relevant action.

### INV-INT-010 — No fee-on-fee unless explicit

Fees and penalties cannot themselves accrue interest unless the agreement expressly permits it.

### INV-INT-011 — Payment waterfall determinism

Each finalized payment must be applied exactly once according to the immutable waterfall associated with the loan.

### INV-INT-012 — Overpayment protection

Any amount above all valid obligations becomes a refundable borrower credit and cannot be retained as hidden protocol revenue.

---

# Part IX — Payment and Settlement Finality

## 15. Payment lifecycle

### INV-PAY-001 — Initiation is not finality

A payment request, authorization, broadcast, provider callback, or mempool observation does not itself constitute final settlement.

### INV-PAY-002 — Finality predicate

Debt may receive a final reduction only when the settlement policy's finality predicate is true.

### INV-PAY-003 — One payment, one final allocation

```text
Count(FinalAllocations for Payment p) ≤ 1
```

### INV-PAY-004 — Callback authenticity

External settlement callbacks must be authenticated, bound to a provider and payment identifier, checked for expiry where applicable, and processed idempotently.

### INV-PAY-005 — Reversal restoration

A valid reversal or chargeback must restore the correct outstanding obligations and reverse the corresponding economic allocations, without duplicating debt.

### INV-PAY-006 — Provisional collateral restriction

Collateral cannot be finally released solely because a reversible payment is provisional.

### INV-PAY-007 — Settlement-asset conservation

For every conversion or routed settlement:

```text
InputAmount
= OutputAmount
+ ProviderFees
+ ProtocolFees
+ SlippageOrFXDifference
+ RefundOrResidual
```

### INV-PAY-008 — Currency consistency

Amounts in different denominations cannot be netted without an explicit conversion event, rate source, timestamp, and rounding rule.

### INV-PAY-009 — Duplicate provider event safety

Replaying an identical provider event cannot create another payment, debt reduction, refund, or ledger posting.

### INV-PAY-010 — Refund bound

A refund cannot exceed the amount economically received and not already refunded, allocated, charged back, or otherwise disposed.

### INV-PAY-011 — Reconciliation visibility

An unresolved mismatch between provider settlement and Unified accounting must remain visible in a reconciliation state and cannot be silently cleared.

---

# Part X — Collateral and Custody

## 16. Collateral invariants

For collateral position `c`:

### INV-COL-001 — Custody existence

A collateral position cannot become `LOCKED` unless the required asset is demonstrably controlled by the approved custody mechanism or validly perfected off-chain.

### INV-COL-002 — Ownership and lien separation

Locked borrower collateral is not protocol revenue or unrestricted treasury property.

### INV-COL-003 — One asset, bounded liens

The protocol cannot create collateral claims exceeding the quantity and priority rights actually controlled.

### INV-COL-004 — Release condition

Collateral can be released only when all secured obligations and applicable release conditions are satisfied or a valid substitution/refinancing transition completes.

### INV-COL-005 — Authorized recipient

Released collateral goes only to the entitled owner or an explicitly authorized destination.

### INV-COL-006 — No double release

A collateral unit cannot be released, claimed, or sold more than once.

### INV-COL-007 — Collateral-balance reconciliation

```text
VaultBalance(asset)
= Σ LockedCollateral(asset)
+ PendingAuthorizedDispositions(asset)
+ ExplicitResidual(asset)
```

### INV-COL-008 — Substitution atomicity

A collateral substitution cannot reduce protection below the required threshold between removal of old collateral and acceptance of new collateral.

### INV-COL-009 — UFT collateral isolation

UFT locked as collateral cannot simultaneously be counted as free staking capital, free governance voting power, or bridge backing.

### INV-COL-010 — NFT identity preservation

For NFT collateral, collection address, token identifier, quantity, chain, and custody provenance must match the agreed collateral record.

### INV-COL-011 — Off-chain collateral evidence

Off-chain collateral cannot be represented as perfected or enforceable without the required attestation, documentation, and status evidence defined by its policy.

### INV-COL-012 — Borrower surplus right

After liquidation costs and valid claims, residual collateral or proceeds belong to the contractually entitled party and cannot be retained without authority.

---

# Part XI — Oracle and Valuation Properties

## 17. Oracle validity

### INV-ORC-001 — Approved source

Only governance-approved and policy-compatible oracle sources may authorize a risk-sensitive action.

### INV-ORC-002 — Freshness

An oracle observation older than its policy-specific maximum age is invalid for origination, margin calls, and liquidation.

### INV-ORC-003 — Positive normalized value

Accepted prices must be positive and normalized to the expected denomination and decimals.

### INV-ORC-004 — Deviation control

A price outside configured cross-source or temporal deviation bounds cannot directly authorize liquidation without the policy's fallback or confirmation process.

### INV-ORC-005 — Observation provenance

Every risk-sensitive valuation must record source, observation time, retrieval time, round or sequence, denomination, and normalized value.

### INV-ORC-006 — No user-selected arbitrary oracle

Borrowers, lenders, liquidators, or integrators cannot inject an unapproved price source into an active loan.

### INV-ORC-007 — Deterministic valuation

Given the same asset quantities, approved observations, haircuts, and policy version, the valuation result must be identical.

### INV-ORC-008 — Failure-safe action

Oracle failure must block new risk creation and unsafe liquidation while preserving safe repayment and collateral top-up routes where possible.

### INV-ORC-009 — Concentration inclusion

When the policy requires concentration adjustments, valuation must incorporate current aggregate exposure rather than only spot price.

### INV-ORC-010 — UFT reflexivity controls

UFT collateral valuation must enforce its isolated-market debt ceilings, liquidity conditions, and circuit breakers.

---

# Part XII — Liquidation, Default, and Recovery

## 18. Default properties

### INV-LIQ-001 — Objective default eligibility

A loan may enter default only when the active default policy's conditions are satisfied from canonical state.

### INV-LIQ-002 — No premature liquidation

Collateral cannot be liquidated before liquidation eligibility is established.

### INV-LIQ-003 — Liquidation reproducibility

Every liquidation must be reproducible from:

```text
Loan state
Debt amount
Collateral quantity
Oracle observations
Risk thresholds
Liquidation route
Fees and bonuses
Execution timestamps
Proceeds
Distribution waterfall
```

### INV-LIQ-004 — Sale bound

A partial liquidation cannot sell more collateral than permitted by the active restoration or close-out policy.

### INV-LIQ-005 — Proceeds conservation

```text
GrossLiquidationProceeds
= ExecutionCosts
+ LiquidationIncentive
+ SecuredClaimsPaid
+ JuniorClaimsPaid
+ ReserveRecoveries
+ BorrowerSurplus
+ ExplicitResidual
```

### INV-LIQ-006 — Priority preservation

Liquidation distributions must respect lien and tranche priority.

### INV-LIQ-007 — No double recovery

A creditor cannot receive more than its valid outstanding claim across collateral, guarantor, insurance, direct repayment, and later recovery.

### INV-LIQ-008 — Claim reduction

Every recovery payment reduces the corresponding outstanding claim before another recovery route can pay it.

### INV-LIQ-009 — Auction settlement finality

Auction ownership and proceeds distribution cannot finalize until the auction payment reaches the required settlement finality.

### INV-LIQ-010 — Lender-claim limit

A direct collateral claim transfers only the rights authorized by the loan policy and does not create an additional cash claim for the same satisfied amount.

### INV-LIQ-011 — Bad-debt visibility

Unrecovered debt after all applicable recovery sources is explicitly recorded as residual bad debt and cannot be concealed through suspense or valuation manipulation.

### INV-LIQ-012 — Cure priority

Where the agreement grants a cure right, a valid cure completed before the final cure deadline must prevent incompatible liquidation execution.

---

# Part XIII — Refinancing and Restructuring

## 19. Refinancing invariants

### INV-REFI-001 — Payoff quote consistency

A refinancing payoff quote must derive from canonical debt state, include an expiry, and identify all amounts required to close the old loan.

### INV-REFI-002 — No double senior lien

At no point may two loans hold independent senior claims over the same collateral beyond a bounded atomic or escrowed transition explicitly designed for lien transfer.

### INV-REFI-003 — Old-loan payoff priority

New refinancing funds must satisfy the old loan's payoff and release conditions before unrestricted additional proceeds reach the borrower.

### INV-REFI-004 — Collateral handoff conservation

Collateral released from the old loan and assigned to the new loan cannot become temporarily withdrawable by an unauthorized party.

### INV-REFI-005 — Failure compensation

If refinancing fails after funds or collateral enter an intermediate state, the recovery path must restore the prior valid position or complete a safe payoff.

### INV-REFI-006 — Amendment consent

A restructuring cannot modify protected economic terms without the approvals required by the active amendment policy.

### INV-REFI-007 — Position-holder voting weights

Restructuring votes must use the position-right snapshot and voting rules bound to the loan, preventing duplicate or post-snapshot vote reuse.

### INV-REFI-008 — No debt disappearance

A restructuring may alter timing or form but cannot erase debt except through an explicit authorized concession, settlement, insurance payment, write-off, or forgiveness entry.

---

# Part XIV — Governance and Emergency Powers

## 20. Governance invariants

### INV-GOV-001 — Checkpointed voting power

Proposal voting power must be determined at the configured historical snapshot.

### INV-GOV-002 — No duplicate UFT voting

One underlying UFT cannot create voting power on more than one governance domain for the same proposal.

### INV-GOV-003 — Proposal threshold

A proposal cannot enter active governance without satisfying its class-specific proposal threshold.

### INV-GOV-004 — Quorum and approval

A proposal cannot succeed unless it satisfies its class-specific quorum and approval threshold.

### INV-GOV-005 — Timelocked execution

A successful proposal cannot execute before its required timelock expires.

### INV-GOV-006 — Expired proposal safety

An expired or cancelled proposal cannot execute.

### INV-GOV-007 — Execution payload integrity

The executed calls must match the successfully voted and queued payload hash.

### INV-GOV-008 — Constitutional prohibition

No governance proposal can:

- mint canonical UFT beyond the cap;
- confiscate a specific user's assets;
- rewrite active loan economics outside agreed amendment rules;
- redirect an individual lender's valid repayments;
- create unbacked wrapped UFT;
- bypass vesting restrictions;
- edit posted accounting history.

### INV-GOV-009 — Scope-limited emergency action

Emergency actions may disable new risk creation or compromised paths but cannot exercise prohibited constitutional powers.

### INV-GOV-010 — Emergency expiry

Temporary emergency actions must expire or require ratification within their constitutional maximum duration.

### INV-GOV-011 — Repayment preservation

Emergency mode must preserve repayment and safe debt-reduction operations wherever technically possible.

### INV-GOV-012 — Upgrade storage safety

An upgrade cannot corrupt storage layout, identifiers, balances, loan policy references, or authority assignments.

### INV-GOV-013 — Upgrade compatibility

New implementation behavior must preserve all invariants applicable to existing state.

### INV-GOV-014 — Treasury mandate bound

Treasury transfers must remain within the approved proposal, destination, asset, amount, timing, and mandate.

---

# Part XV — Staking, Rewards, and Slashing

## 21. Staking-vault properties

Let:

- `A` = accounted staking-vault assets;
- `Q` = outstanding sUFT shares;
- `PPS` = assets per share under the active accounting rule.

### INV-STK-001 — Share backing

```text
A ≥ AssetsClaimableByOutstandingShares
```

subject to explicitly socialized and disclosed slashing losses.

### INV-STK-002 — Share conservation

Shares can be minted only in exchange for accepted assets or authorized capital contributions and burned only through redemption, cancellation, or loss processing.

### INV-STK-003 — Reward funding

A reward cannot be accrued or paid beyond assets already funded or legally receivable under a recognized policy.

### INV-STK-004 — No unfunded guaranteed APY

The system cannot represent projected rewards as guaranteed unless fully funded and contractually reserved.

### INV-STK-005 — Slashing authority

Slashing can occur only for a covered event, through the approved decision process, within the per-event and rolling-period limits.

### INV-STK-006 — Slash conservation

Slashed assets must be allocated to authorized loss coverage, recovery, reserve, or redistribution accounts and cannot disappear.

### INV-STK-007 — Withdrawal queue order

Withdrawal claims must follow the active queue, priority, cooldown, and loss-allocation policy.

### INV-STK-008 — No withdrawal front-running of known loss

Once a covered loss is formally recognized under the policy, withdrawal processing cannot allow later-ranked stakers to avoid their defined share of that loss through ordering manipulation.

### INV-STK-009 — Collateralized sUFT accounting

If sUFT is accepted as collateral, the protocol must apply the approved haircut and cannot count the same underlying UFT simultaneously as unrestricted insurance capital.

### INV-STK-010 — Governance-lock uniqueness

veUFT voting power must correspond to eligible locked UFT or approved staking shares and cannot exceed the lock's eligible economic backing.

---

# Part XVI — Identity, Credentials, and Underwriting

## 22. Credential properties

### INV-ID-001 — Credential issuer validity

A credential is usable only when issued by an approved issuer under an accepted schema.

### INV-ID-002 — Credential subject binding

A credential or zero-knowledge proof must bind to the account or subject commitment authorized for the operation.

### INV-ID-003 — Validity window

Expired, revoked, or not-yet-valid credentials cannot satisfy an origination requirement.

### INV-ID-004 — Minimal disclosure

Public protocol state must not reveal restricted identity attributes when the policy requires a commitment, attestation, or zero-knowledge proof instead.

### INV-ID-005 — Uniqueness semantics

A uniqueness credential prevents duplicate participation only within its explicitly defined scope and epoch; the system must not claim broader uniqueness than proved.

### INV-ID-006 — Consent binding

Use of restricted external data requires a valid consent or other authorized legal basis represented in the operational system.

### INV-ID-007 — Revocation propagation

Revocation must affect future eligibility checks within the stated propagation bound.

---

## 23. Underwriting properties

### INV-UW-001 — Decision provenance

Every automated or attested credit decision records:

```text
Policy version
Model version where applicable
Feature or evidence references
Decision timestamp
Validity period
Exposure limit
Product eligibility
Issuer or decision service
```

### INV-UW-002 — Exposure bound

Activated unsecured and partially secured obligations cannot cause the borrower's recognized exposure to exceed the valid decision limit.

### INV-UW-003 — Decision expiry

An expired underwriting decision cannot authorize a new activation.

### INV-UW-004 — Product compatibility

The approved product, amount, duration, collateral class, and settlement mode must cover the activated loan configuration.

### INV-UW-005 — No hidden decision mutation

A model or policy update cannot retroactively alter an already issued decision without creating a new versioned decision.

### INV-UW-006 — Feature integrity

Critical features used for underwriting must be tied to authenticated sources, timestamps, and transformation versions.

### INV-UW-007 — Manual override traceability

A manual override requires authorized personnel, reason, scope, expiry where applicable, and immutable audit evidence.

### INV-UW-008 — Portfolio-limit conservation

Portfolio and segment exposure limits must include pending activations where their policy requires reservation of capacity.

### INV-UW-009 — Anonymous-credit risk disclosure

A truly anonymous unsecured product cannot be represented as possessing enforceable identity recovery when it does not.

---

# Part XVII — Insurance, Guarantees, and Reserves

## 24. Protection invariants

### INV-INS-001 — Funded-reserve truth

A disclosed funded reserve equals assets actually controlled and legally available for the stated mandate, net of senior restrictions.

### INV-INS-002 — Coverage bound

Coverage promises cannot exceed the policy limit and available capital under the disclosed loss waterfall.

### INV-INS-003 — No double claim

A loss amount paid by collateral, guarantor, insurance, reserve, or recovery cannot be claimed again.

### INV-INS-004 — Claim eligibility

A claim can be approved only when the covered event and policy conditions are satisfied.

### INV-INS-005 — Reserve segregation

Restricted insurance assets cannot be spent as unrestricted operating treasury funds.

### INV-INS-006 — Correlated UFT valuation

UFT-denominated reserve assets must be valued under stress-adjusted rules when measuring coverage for losses correlated with Unified or UFT.

### INV-INS-007 — Loss waterfall determinism

Given the same loss, positions, collateral recoveries, guarantees, and reserves, the allocation result must be identical.

### INV-INS-008 — Claim-payment conservation

```text
ApprovedClaim
= PaymentsToEligibleClaimants
+ AuthorizedCosts
+ UnpaidApprovedClaim
```

### INV-INS-009 — Subrogation accounting

Where payment creates recovery rights, those rights must be recorded and later recoveries allocated according to the policy.

---

# Part XVIII — Cross-Chain Messaging and Satellite State

## 25. Message invariants

### INV-BRG-001 — Canonical home authority

Every cross-chain loan has one authoritative home domain for its economic state.

### INV-BRG-002 — Message uniqueness

A verified message identifier or nonce can execute at most once on the destination domain.

### INV-BRG-003 — Source authentication

A destination action requires proof that the message originated from the approved source adapter and source contract.

### INV-BRG-004 — Domain binding

Messages must bind source chain, destination chain, source contract, destination contract, loan or asset identifier, action, nonce, and payload hash.

### INV-BRG-005 — Ordered action safety

Where order matters, out-of-order messages cannot produce an invalid state transition.

### INV-BRG-006 — Timeout safety

A timed-out operation enters a recovery state and cannot later execute as if still pending unless explicitly reauthorized.

### INV-BRG-007 — Retry idempotency

Retries cannot duplicate asset release, minting, repayment, collateral locking, or position issuance.

### INV-BRG-008 — Satellite authority limit

A satellite component cannot independently alter principal, interest, lender rights, or other canonical economics.

### INV-BRG-009 — Cross-chain collateral exclusivity

Collateral locked on a satellite chain cannot support another obligation unless the canonical policy explicitly allows and accounts for that reuse.

### INV-BRG-010 — Finality threshold

A cross-chain action cannot become canonical before the required source and messaging finality conditions are met.

### INV-BRG-011 — Failure visibility

Unresolved bridge and message states remain observable and reconciled; they cannot be silently marked successful.

### INV-BRG-012 — Recovery authorization

Manual recovery requires multi-party authorization, evidence, amount bounds, and replay-safe identifiers.

---

# Part XIX — Liveness Properties

## 26. Core liveness

Liveness properties are evaluated under explicit assumptions such as an operational base chain, available gas, non-compromised canonical contracts, and valid user authorization.

### LIVE-LOAN-001 — Repayment reachability

From every nonterminal debt state, a valid borrower or authorized payer can reach a debt-reducing transition.

### LIVE-COL-001 — Collateral release reachability

After all secured obligations are finally satisfied, the entitled party can eventually reach collateral release or a documented recovery path.

### LIVE-FUND-001 — Funding exit

If a funding round expires without activation, committed funds can eventually be returned according to policy.

### LIVE-PAY-001 — Payment resolution

Every accepted payment reaches one of:

```text
FINAL
REVERSED
REFUNDED
FAILED_TERMINAL
DISPUTED_WITH_EXPLICIT_OWNER
```

within its operational resolution framework.

### LIVE-BRG-001 — Cross-chain resolution

Every cross-chain operation eventually reaches executed, safely cancelled, refunded, or governed recovery status.

### LIVE-GOV-001 — Governance resolution

Every valid proposal eventually reaches defeated, cancelled, expired, executed, or permanently failed status.

### LIVE-STK-001 — Withdrawal resolution

A valid staking withdrawal request eventually becomes claimable, cancelled under policy, or explicitly loss-adjusted.

### LIVE-LIQ-001 — Default resolution

A defaulted loan eventually reaches recovery completion, settlement, write-off with recorded recovery rights, or another explicit terminal status.

### LIVE-REFI-001 — Refinance resolution

A refinancing attempt cannot remain indefinitely between old-loan payoff and new-loan activation without entering recovery.

### LIVE-OPS-001 — Emergency exit

Emergency mode has a defined path to normal operation, replacement of the compromised component, or orderly product shutdown.

---

# Part XX — Recovery Properties

## 27. Safe recovery

### REC-001 — No recovery overpayment

A recovery action cannot transfer more than the provable unresolved entitlement.

### REC-002 — Recovery idempotency

Repeating the same recovery instruction cannot duplicate its economic effect.

### REC-003 — Recovery auditability

Every manual or exceptional recovery records reason, authority, source evidence, affected entities, amount, destination, and related incident.

### REC-004 — Pre-state preservation

Before an exceptional migration or recovery, the canonical pre-state must be reproducibly snapshotted.

### REC-005 — State reconciliation

After recovery:

```text
OnchainState
↔ LedgerState
↔ ProviderState
↔ PositionClaims
↔ CustodyBalances
```

must reconcile or retain explicit differences.

### REC-006 — No constitutional bypass

Recovery authority cannot bypass the fixed UFT cap, seize unrelated user assets, rewrite active terms, or edit posted history.

### REC-007 — Compensating transition completeness

A compensating transition must reverse or neutralize all dependent effects of the failed transition, not only the visible top-level state.

### REC-008 — Recovery finality

Once recovery is finalized, stale original messages or callbacks cannot reapply the failed operation.

---

# Part XXI — Property-to-Threat Traceability

## 28. Threat coverage matrix

| Threat family | Primary properties |
|---|---|
| Active-loan mutation | INV-LOAN-004, 006; INV-GOV-008, 012, 013 |
| Unauthorized UFT minting | INV-SUP-001–004; INV-GOV-008 |
| Wrapped UFT overissuance | INV-SUP-009–013; INV-BRG-002–004 |
| Offer replay | INV-LOAN-002; INV-AUTH-005–007 |
| Payment replay | INV-PAY-003, 004, 009; INV-ACC-004 |
| Collateral theft | INV-COL-001–007; INV-AUTH-001–004 |
| Oracle manipulation | INV-ORC-001–010; INV-LIQ-001–004 |
| Liquidation cascade | INV-ORC-004, 009, 010; INV-LIQ-004–006 |
| Governance capture | INV-GOV-001–014 |
| Staking insolvency | INV-STK-001–010; INV-INS-001, 006 |
| Synthetic identity fraud | INV-ID-001–007; INV-UW-001–009 |
| Unsecured-credit overexposure | INV-UW-002, 008; INV-INS-001–007 |
| Chargeback after release | INV-PAY-002, 005, 006 |
| Accounting concealment | INV-ACC-001–007; REC-003–005 |
| Insider treasury theft | INV-AUTH-003–004; INV-GOV-014; INV-ACC-004–007 |
| Bridge replay | INV-BRG-002–007 |
| Refinancing double lien | INV-REFI-002–005; INV-COL-003 |
| Secondary-market overissuance | INV-FUND-004–011 |
| Upgrade corruption | INV-GOV-012–013; INV-LOAN-006 |

Every critical and existential threat in the threat model must have at least one preventive invariant, one detective control, one recovery property, and one launch test.

---

# Part XXII — Executable Verification Architecture

## 29. Verification layers

### 29.1 Layer A — Local unit properties

Tests for pure functions and isolated modules:

- interest calculations;
- payment waterfalls;
- collateral ratios;
- vesting schedules;
- quorum calculations;
- bridge message hashes;
- loan-state transition predicates;
- tranche distributions.

### 29.2 Layer B — Contract invariants

Persistent assertions evaluated across arbitrary stateful call sequences.

### 29.3 Layer C — Multi-contract integration invariants

Properties spanning factory, loan account, vault, registry, oracle, payment router, position manager, treasury, and governance.

### 29.4 Layer D — Service and ledger invariants

Properties spanning event ingestion, idempotency, accounting posting, reconciliation, identity, underwriting, and provider callbacks.

### 29.5 Layer E — Cross-domain simulations

Full workflows involving chains, payment providers, bridges, oracles, and operational recovery.

### 29.6 Layer F — Economic and adversarial simulation

Market crashes, liquidity withdrawal, correlated default, governance concentration, bank failure, bridge impairment, and UFT reflexivity.

---

## 30. Required contract assertions

Production contracts should include low-cost assertions or equivalent checks for critical local properties, including:

```text
newTotalSupply ≤ MAX_SUPPLY
consumedNonce[signer][nonce] changes false → true once
loan.state transition is permitted
postPaymentDebt ≤ prePaymentDebt unless valid reversal
releasedCollateral ≤ lockedCollateral - previouslyDisposedCollateral
issuedPositionRights ≤ authorizedLoanRights
wrappedSupply[chain] ≤ escrowBacking[chain] + verifiedPendingBacking
revenueSplitSum = 10,000 basis points
```

Assertions that are too expensive for production must remain in test harnesses and formal specifications.

---

## 31. Stateful fuzzing actor model

The minimum adversarial actor set is:

```text
Borrower
Lender
Multiple lenders
Liquidator
Position buyer
Position seller
Guarantor
Insurer
Governance proposer
Governance voter
Emergency council
Treasury operator
Oracle updater
Bridge relayer
Payment provider
Identity attester
Underwriting service
Arbitrary external account
Malicious token
Malicious callback contract
```

The fuzzer must vary:

- call order;
- timestamps and block advancement;
- prices and rate observations;
- partial funding;
- partial payments;
- repeated messages;
- failed token transfers;
- fee-on-transfer and rebasing behavior where tested as unsupported assets;
- reentrancy callbacks;
- role changes;
- pauses and upgrades;
- bridge delays;
- chargebacks;
- governance proposals;
- reserve depletion.

---

## 32. Stateful fuzz target families

### FZ-LOAN-001 — Arbitrary lifecycle sequencing

Randomly exercise tender, offer, funding, activation, payment, delinquency, refinance, liquidation, and closure transitions. Assert all loan invariants after every call.

### FZ-FUND-001 — Syndicate conservation

Randomly commit, cancel, accept, refund, transfer, split, and merge positions. Assert funding and position-right conservation.

### FZ-COL-001 — Collateral custody

Randomly deposit, substitute, top up, partially liquidate, claim, and release collateral. Assert no double disposition and exact vault reconciliation.

### FZ-PAY-001 — Payment finality

Randomly initiate, authorize, finalize, reverse, refund, duplicate, and dispute payments. Assert one final allocation and correct debt restoration.

### FZ-UFT-001 — Supply integrity

Exercise every UFT, vesting, staking, burn, treasury, collateral, and bridge path. Assert the fixed cap and representation equations.

### FZ-GOV-001 — Governance authority

Generate arbitrary proposals, role changes, timings, vote delegations, cancellations, and execution calls. Assert constitutional prohibitions and timelocks.

### FZ-BRG-001 — Message replay and ordering

Deliver cross-chain messages repeatedly, out of order, late, and after recovery. Assert idempotency and canonical authority.

### FZ-ORC-001 — Oracle stress

Vary prices, staleness, source disagreement, decimal formats, liquidity measures, and circuit breakers. Assert unsafe actions remain blocked.

### FZ-REFI-001 — Refinancing interruption

Force failures at each refinancing step and prove no double lien, trapped collateral, or duplicated debt.

### FZ-ACC-001 — Ledger posting

Replay, reorder, reverse, and reconcile source events. Assert balanced immutable entries and no duplicate economic posting.

---

# Part XXIII — Symbolic Execution and Model Checking

## 33. Symbolic execution priorities

The highest-priority symbolic targets are:

1. canonical UFT token and burner;
2. offer signature and nonce consumption;
3. loan activation;
4. repayment and debt reduction;
5. collateral release;
6. liquidation eligibility and distribution;
7. lender-position issuance and transfer;
8. governance execution and upgrade authority;
9. bridge escrow and wrapped issuance;
10. staking share mint, redemption, and slashing.

For each target, prove or exhaustively search for:

- unauthorized state changes;
- arithmetic overflow or underflow;
- violation of conservation equations;
- replay;
- reentrancy;
- terminal-state reversal;
- missing authorization;
- invariant-breaking external call behavior.

---

## 34. Model-checking domains

### 34.1 Loan lifecycle model

Model a bounded loan with:

- one borrower;
- up to three lenders;
- two collateral assets;
- partial payments;
- default;
- refinance;
- liquidation;
- position transfer.

Verify state reachability and forbidden-state impossibility.

### 34.2 Cross-chain model

Model home and satellite chains with:

- delayed messages;
- duplicate messages;
- reordering;
- finality rollback within assumptions;
- timeout and recovery.

Verify no duplicate mint, release, repayment, or collateral claim.

### 34.3 Payment model

Model authorization, provisional settlement, final settlement, reversal, refund, dispute, and collateral release. Prove reversible funds cannot permanently release collateral under the configured policy.

### 34.4 Governance model

Model proposal creation, delegation, snapshots, voting, timelock, cancellation, execution, and emergency intervention. Prove prohibited actions remain unreachable.

### 34.5 Accounting model

Model source events, primary entries, reversals, replacements, and reconciliation. Prove balanced posting and event idempotency.

---

# Part XXIV — Differential and Reference Testing

## 35. Reference implementations

Critical economic algorithms require an independent reference implementation separate from production contracts.

Required references include:

- fixed and variable interest accrual;
- amortization schedules;
- payment waterfalls;
- tranche waterfalls;
- collateral health and liquidation amount;
- UFT vesting and unlocks;
- staking share conversion;
- governance quorum and voting power;
- fee routing;
- bridge backing reconciliation.

### INV-VER-001 — Differential equivalence

For every generated valid input within supported ranges:

```text
ProductionImplementation(input)
= ReferenceImplementation(input)
```

subject to the same disclosed rounding convention.

### INV-VER-002 — Cross-language equivalence

Where the same rule is implemented in Solidity, backend services, indexers, and user interfaces, all implementations must match the canonical reference vectors.

---

# Part XXV — Numeric Precision and Arithmetic

## 36. Arithmetic rules

### INV-NUM-001 — Explicit scale

Every fixed-point value declares its scale and denomination.

### INV-NUM-002 — Checked conversion

Decimal normalization cannot silently truncate beyond the permitted rounding policy.

### INV-NUM-003 — Bounded multiplication and division

Intermediate values must not overflow and division order must not create unacceptable precision loss.

### INV-NUM-004 — Rounding direction disclosure

Each calculation defines whether it rounds up, down, toward zero, or to nearest.

### INV-NUM-005 — User-protective bounds

Where asymmetrical rounding is necessary, it must not systematically overcharge borrowers or overpay claimants beyond funded amounts.

### INV-NUM-006 — Time precision

Interest and vesting calculations use one canonical time unit and define boundary behavior at exact deadlines.

### INV-NUM-007 — Basis-point sum

Every percentage allocation intended to distribute a whole amount must reconcile to its full denominator.

---

# Part XXVI — Supported and Unsupported Asset Behavior

## 37. Token compatibility properties

Unified asset policies must explicitly classify support for:

- standard ERC-20 tokens;
- tokens with transfer fees;
- rebasing tokens;
- tokens with hooks or callbacks;
- pausable or blacklistable tokens;
- upgradeable tokens;
- tokens with nonstandard return values;
- ERC-721 assets;
- ERC-1155 assets.

### INV-ASSET-001 — Actual-received accounting

For assets whose transfer behavior is supported, custody and funding accounting must use the amount actually received where required.

### INV-ASSET-002 — Unsupported behavior rejection

An asset with unsupported transfer or supply behavior cannot be accepted merely because it exposes a nominal interface.

### INV-ASSET-003 — Balance-change validation

Where token behavior is uncertain, expected asset movement must be validated through pre/post balances.

### INV-ASSET-004 — Callback safety

External token callbacks cannot reenter a state transition in a way that violates loan, collateral, payment, or supply invariants.

### INV-ASSET-005 — Asset delisting continuity

Delisting prevents new risk creation but does not invalidate valid repayment, redemption, or closure paths for existing positions.

---

# Part XXVII — Verification Evidence and Traceability

## 38. Property registry

The repository must contain a machine-readable property registry with at least:

```text
property_id
name
class
severity
statement
assumptions
governing_document
implementing_components
test_files
formal_models
monitoring_controls
recovery_runbook
status
owner
last_verified_commit
```

## 39. Requirement traceability

Every critical property must trace in both directions:

```text
Constitutional rule
↕
Domain invariant
↕
State-machine rule
↕
Threat or failure mode
↕
Formal property
↕
Implementation component
↕
Executable test or proof
↕
Runtime monitor
↕
Recovery procedure
```

A critical implementation without a mapped property is incomplete. A critical property without an executable test or proof is unverified.

---

# Part XXVIII — Runtime Invariant Monitoring

## 40. Production monitoring

Not all properties can be fully enforced within one transaction. Unified must continuously monitor:

- UFT supply and burns;
- wrapped supply versus escrow backing;
- staking assets versus shares;
- governance locks versus voting power;
- collateral vault balances versus recorded positions;
- lender positions versus loan rights;
- loan balances versus payment and accrual records;
- provider settlement versus ledger entries;
- reserve assets versus coverage claims;
- oracle staleness and divergence;
- bridge message states;
- suspense balances;
- emergency-action duration;
- treasury movements versus mandates.

### INV-MON-001 — Alert completeness

Every runtime-monitored critical invariant has an alert threshold, owner, escalation route, and response runbook.

### INV-MON-002 — Independent reconstruction

Critical balances must be reconstructable independently from canonical events and state, not solely from the primary application database.

### INV-MON-003 — Monitoring cannot mutate truth

Monitoring and analytics systems cannot directly alter canonical financial state.

---

# Part XXIX — Verification Severity and Launch Gates

## 41. Severity classes

| Class | Meaning | Launch consequence |
|---|---|---|
| Existential | Can destroy protocol-wide solvency, supply integrity, or constitutional control | Zero open failures permitted |
| Critical | Can cause major user loss, duplicate claims, governance compromise, or systemic insolvency | Zero open failures permitted |
| High | Can cause bounded material loss or prolonged inability to use funds | Must be fixed or explicitly launch-disabled |
| Medium | Limited loss, incorrect noncanonical data, or recoverable disruption | Risk acceptance required |
| Low | Minor defect without material safety impact | May enter backlog |

---

## 42. Launch-blocking properties

The following are always launch-blocking:

1. any violation of the UFT fixed cap;
2. any unbacked wrapped UFT path;
3. any duplicate payment or bridge execution path;
4. any path to release collateral before policy conditions;
5. any path to rewrite active loan economics without consent;
6. any lender-position overissuance;
7. any unbalanced or duplicate primary accounting posting;
8. any governance bypass of timelock or constitutional prohibition;
9. any refinancing double-lien path;
10. any reversible payment path that causes irreversible collateral release contrary to policy;
11. any unauthorized treasury or user-asset transfer;
12. any terminal loan reactivation;
13. any stale-oracle liquidation outside approved fallback rules;
14. any reward or reserve claim beyond funded resources;
15. any cross-chain replay that changes economic state twice.

---

## 43. Required evidence before public deployment

Before unrestricted production launch, Unified must have:

- complete property registry for all critical and existential invariants;
- passing unit and integration suites;
- passing stateful invariant tests over sustained campaigns;
- symbolic analysis of the highest-risk contracts;
- model-checking results for loan, payment, governance, and bridge state machines;
- differential test vectors for economic calculations;
- storage-layout and upgrade-compatibility verification;
- mainnet-fork or realistic network simulations;
- malicious-token tests;
- bridge delay, replay, and failure simulations;
- fiat and card reversal simulations;
- economic stress tests;
- at least two independent smart-contract security reviews for critical custody and supply components;
- remediation of all critical and existential findings;
- a live bug-bounty program before broad value-at-risk expansion;
- verified emergency and recovery drills;
- signed launch-readiness report mapping every launch gate to evidence.

---

# Part XXX — Verification Phases

## 44. Phase FV-0 — Specification integrity

Deliverables:

- property identifiers;
- formal statements;
- assumptions;
- traceability to governing documents;
- conflict review;
- launch severity.

Exit criterion: every constitutional financial rule maps to at least one property.

## 45. Phase FV-1 — Reference models

Deliverables:

- pure reference implementations;
- canonical test vectors;
- state-machine models;
- accounting equations.

Exit criterion: production teams can implement against stable expected behavior.

## 46. Phase FV-2 — Module proofs and fuzzing

Deliverables:

- local contract assertions;
- stateful fuzz harnesses;
- symbolic targets;
- role and authorization tests.

Exit criterion: no unresolved critical local invariant failures.

## 47. Phase FV-3 — Composition verification

Deliverables:

- multi-contract harnesses;
- policy-composition matrix;
- cross-module state tests;
- external-call adversarial tests.

Exit criterion: every launch-supported product composition passes its property set.

## 48. Phase FV-4 — Cross-domain verification

Deliverables:

- bridge simulations;
- provider-reversal tests;
- ledger reconciliation tests;
- identity and underwriting failure tests;
- operational recovery exercises.

Exit criterion: external failure cannot violate constitutional invariants.

## 49. Phase FV-5 — Independent review

Deliverables:

- external audits;
- formal review reports;
- red-team results;
- remediation evidence.

Exit criterion: no open existential or critical finding.

## 50. Phase FV-6 — Runtime assurance

Deliverables:

- monitors;
- alerting;
- independent state reconstruction;
- incident runbooks;
- recurring invariant checks.

Exit criterion: verified properties remain observable after deployment.

---

# Part XXXI — Initial Formal Verification Priority List

## 51. Priority P0 — Existential

1. UFT total-supply cap and no mint authority.
2. Canonical/wrapped UFT backing.
3. Governance constitutional limits.
4. Upgrade authority and storage integrity.
5. Collateral custody and release.
6. Payment finality before collateral release.
7. Loan activation and immutable agreement snapshot.
8. Duplicate offer, payment, and cross-chain replay prevention.
9. Lender-position rights conservation.
10. Treasury and user-asset authorization.

## 52. Priority P1 — Critical

1. Interest and repayment accounting.
2. Liquidation eligibility and proceeds waterfall.
3. Refinancing lien transfer.
4. Staking share backing and slashing.
5. Reserve and insurance claim limits.
6. Oracle freshness and deviation controls.
7. Syndicate and tranche distributions.
8. Provider callback authenticity and idempotency.
9. Ledger posting and reversal integrity.
10. Emergency-mode repayment availability.

## 53. Priority P2 — High

1. Position marketplace settlement.
2. NFT auction handling.
3. credential revocation propagation.
4. underwriting exposure reservations.
5. reward-distribution epochs.
6. cross-chain governance participation.
7. custom repayment schedules.
8. off-chain collateral attestations.

---

# Part XXXII — Initial Verification Matrix

## 54. Component matrix

| Component | Mandatory property groups | Primary verification methods |
|---|---|---|
| UnifiedToken | SUP, AUTH, GOV | unit, invariant fuzzing, symbolic execution |
| Genesis and vesting vaults | SUP, AUTH, ACC | differential tests, invariant fuzzing |
| Tender and Offer Manager | LOAN, AUTH | signatures, replay fuzzing, model checking |
| Loan Factory | LOAN, AUTH, GOV | integration invariants, symbolic execution |
| Loan Account | LOAN, INT, PAY | stateful fuzzing, model checking |
| Funding/Syndicate Vault | FUND, ACC | conservation fuzzing, differential waterfalls |
| Position Manager | FUND, AUTH | transfer-state fuzzing, rights reconciliation |
| Collateral Manager | COL, ORC, LIQ | custody invariants, malicious-token testing |
| Oracle Router | ORC, AUTH | stale/deviation fuzzing, source-failure simulation |
| Liquidation Engine | LIQ, COL, ACC | model checking, differential calculations |
| Payment Router | PAY, ACC | callback replay, reversal simulations |
| Refinance Coordinator | REFI, COL, PAY | failure injection, state-machine checking |
| Staking Vault | STK, SUP, ACC | share-accounting fuzzing, loss simulation |
| Governor/Timelock | GOV, AUTH | model checking, proposal-sequence fuzzing |
| Treasury/Fee Router | ACC, SUP, GOV | allocation conservation, mandate tests |
| Insurance Manager | INS, ACC | loss-waterfall differential testing |
| Bridge Hub | BRG, SUP, AUTH | replay/order simulation, symbolic execution |
| Identity Registry | ID, AUTH | revocation and binding tests |
| Underwriting Registry | UW, ID, AUTH | provenance, expiry, exposure tests |
| Ledger Service | ACC, PAY | property-based posting and reconciliation |
| Indexer | ACC, MON | deterministic reconstruction and reorg tests |

---

# Part XXXIII — Constitutional Invariant Summary

## 55. Non-negotiable protocol truths

Unified is considered formally unsafe if any supported execution path allows:

1. creation of canonical UFT above the genesis cap;
2. creation of wrapped UFT without backing;
3. duplicate exercise of one signature, offer, payment, message, or recovery instruction;
4. movement of user assets without authorization or a previously accepted contractual rule;
5. modification of active loan economics through an unrelated upgrade or governance action;
6. release or liquidation of collateral outside the active policy;
7. lender claims exceeding funded rights;
8. borrower debt reduction before required settlement finality;
9. disappearance of assets, liabilities, or losses outside balanced accounting;
10. governance execution outside proposal, vote, quorum, timelock, and constitutional limits;
11. reserve, reward, guarantee, or insurance promises beyond funded capacity;
12. refinancing that creates two unbounded senior claims over the same collateral;
13. cross-chain satellite state overriding canonical economics;
14. terminal financial states becoming active again;
15. an emergency authority minting, confiscating, concealing, or rewriting protected rights.

---

# Part XXXIV — Required Repository Artifacts

## 56. Verification repository structure

```text
verification/
├── properties/
│   ├── property-registry.yaml
│   ├── constitutional.yaml
│   ├── loan.yaml
│   ├── accounting.yaml
│   ├── uft.yaml
│   ├── governance.yaml
│   ├── collateral.yaml
│   ├── payment.yaml
│   └── crosschain.yaml
├── reference-models/
│   ├── interest/
│   ├── schedules/
│   ├── waterfalls/
│   ├── collateral/
│   ├── tokenomics/
│   └── governance/
├── fuzz/
│   ├── loan/
│   ├── funding/
│   ├── collateral/
│   ├── payment/
│   ├── uft/
│   ├── governance/
│   └── bridge/
├── formal/
│   ├── specifications/
│   ├── symbolic/
│   ├── model-checking/
│   └── proofs/
├── vectors/
│   ├── canonical/
│   ├── edge-cases/
│   └── regression/
├── runtime/
│   ├── monitors/
│   ├── alerts/
│   └── reconstruction/
└── reports/
    ├── coverage/
    ├── audits/
    ├── launch-gates/
    └── exceptions/
```

---

# Part XXXV — Definition of Done

## 57. Specification completion criteria

This specification reaches implementation-ready status when:

- every invariant has an owner and severity;
- every invariant maps to one or more components;
- every critical invariant has an executable test plan;
- every environmental assumption is explicit;
- all equations use canonical definitions and units;
- supported policy combinations are listed;
- runtime-only properties have monitors and runbooks;
- launch gates have evidence requirements;
- unresolved contradictions have ADRs and cannot silently pass into code.

## 58. Implementation completion criteria

A component is not complete merely because its code compiles or its unit tests pass. It is complete only when:

```text
Implementation exists
∧ Interfaces conform
∧ Required properties pass
∧ Threat mappings are covered
∧ Accounting effects reconcile
∧ Recovery behavior is tested
∧ Monitoring exists where required
∧ Documentation and evidence are current
```

---

# Conclusion

Unified's complexity must be governed by explicit, composable, and continuously verified truths.

The Constitution defines what the system must protect. The Domain Model defines what exists. The Universal Loan Model defines how it changes. The Accounting Specification defines how value is recorded. The UFT Specification defines the economic system. The Threat Model defines how those systems may be attacked. This specification defines how Unified proves, tests, monitors, and preserves their correctness.

The governing rule is:

> **No critical financial assumption is trusted merely because it was intended. It must be encoded as a property, exercised against adversarial state transitions, reconciled against canonical value, and enforced as a launch gate.**

---

## Appendix A — Minimum invariant dashboard

The production invariant dashboard must display at least:

```text
Canonical UFT supply / cap
Wrapped UFT / canonical escrow backing by bridge
sUFT claimable assets / staking-vault assets
veUFT voting power / eligible locked backing
Collateral recorded / vault custody by asset
Outstanding lender rights / outstanding loan rights
Finalized payments / allocated payments
Loan debt / accounting receivables
Reserve claims / funded reserve assets
Cross-chain messages pending, failed, recovered
Suspense balances by age
Emergency actions and expiry
Oracle age and source divergence
```

## Appendix B — Minimum regression corpus

Every fixed critical defect must add a permanent regression vector containing:

- original triggering state;
- adversarial action sequence;
- expected revert or safe outcome;
- property identifier;
- affected versions;
- remediation commit;
- test owner.

## Appendix C — Formal assumption register

Examples of assumptions that must be tracked rather than hidden:

- base-chain finality assumptions;
- cryptographic signature security;
- approved oracle honesty threshold;
- bridge verification assumptions;
- stablecoin and token contract behavior;
- payment-provider authenticity and legal settlement rules;
- custody-provider solvency and control evidence;
- KYC and credit-attester trust assumptions;
- governance participation assumptions;
- off-chain collateral enforceability assumptions.

When an assumption fails, the system must enter the predefined safe or recovery behavior; it must not continue as though the proof remained valid.
