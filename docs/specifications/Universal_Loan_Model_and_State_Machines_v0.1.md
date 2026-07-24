# Universal Loan Model and State Machine Specification

**Document:** Universal Loan Model and State Machine Specification  
**Version:** 0.1 — Foundational Draft  
**Status:** Architecture baseline for review and ratification  
**Authority:** Subordinate to the Unified Constitution and Unified Domain Model  
**Applies to:** All Unified lending products, smart contracts, services, adapters, user interfaces, indexers, accounting systems, governance actions, and integrations

---

## 1. Purpose

This specification defines the universal behavioral model for every loan originated, funded, serviced, transferred, refinanced, restructured, liquidated, recovered, or closed through Unified.

It converts the constitutional principles and canonical domain entities into executable rules by defining:

- The universal loan configuration.
- Independent but coordinated state machines.
- Authorized actors and permissions.
- Preconditions and postconditions for every transition.
- Financial and asset movements.
- Required accounting entries.
- Required domain and protocol events.
- Finality and reversibility rules.
- Failure, dispute, and recovery procedures.
- Product-specific policy extension points.
- Cross-domain invariants.

The specification is intentionally capable of expressing complex products without requiring a separate protocol for every combination of borrower identity, funding structure, collateral type, interest model, repayment schedule, settlement rail, transfer rule, or liquidation method.

---

## 2. Governing Documents

This specification must be interpreted in the following order:

1. Unified Constitution.
2. Ratified protocol invariants.
3. Unified Domain Model.
4. This specification.
5. Financial Accounting Specification.
6. Ratified architecture decision records.
7. Versioned contract and service interfaces.
8. Product configurations.

Where this document conflicts with a higher-authority document, the higher-authority rule prevails and the conflict must be recorded.

---

# Part I — Universal Loan Architecture

## 3. Definition of a Unified Loan

A `Loan` is a versioned financial agreement under which one or more funding parties provide economic value to one or more borrowers, creating one or more obligations governed by immutable accepted terms and explicitly versioned policies.

A loan may be:

- Single-lender or syndicated.
- Fully collateralized, partially collateralized, guaranteed, insured, or unsecured.
- Funded with cryptoassets, fiat, card-originated value, off-chain assets, or a hybrid combination.
- Denominated in one asset and settled in another where conversion rules are explicit.
- Fixed-rate, variable-rate, benchmark-linked, profit-sharing, revenue-linked, or hybrid.
- Bullet, amortizing, interest-only, balloon, seasonal, revenue-based, or custom-scheduled.
- Same-chain or cross-chain.
- Transferable, fractionally transferable, restricted, or non-transferable.
- Refinanced, restructured, accelerated, liquidated, recovered, written off, or settled.

A loan is not defined by a single smart contract implementation. It is defined by a canonical agreement plus a set of policy versions and authoritative state records.

## 4. Universal Loan Aggregate

The `Loan Aggregate` is the consistency boundary for contractual rights and obligations.

It owns or references:

```text
Loan
├── Agreement Snapshot
├── Borrower Parties
├── Funding Parties and Positions
├── Principal and Denomination
├── Policy Set
├── Obligations
├── Repayment Schedule
├── Collateral Positions and Liens
├── Guarantees and Insurance Coverage
├── Settlement Instructions
├── Accounting References
├── Amendments
├── Defaults and Remedies
├── Refinancing and Restructuring Records
├── Transfer Restrictions
└── Canonical State Vector
```

The Loan Aggregate does not directly own every external entity. For example, payment-provider records, blockchain bridge messages, identity credentials, and price observations remain canonical in their respective domains. The Loan Aggregate references them by immutable identifier and records only the contractual consequence.

## 5. Universal Loan Configuration

Every proposed loan shall be represented by a canonical `LoanConfiguration` before activation.

```text
LoanConfiguration
loan_id
schema_version
protocol_version
home_authority
home_network_id
borrower_party_ids[]
borrower_account_ids[]
principal_asset_id
principal_denomination_id
principal_amount
approved_draw_amount
currency_conversion_policy_id?
funding_policy_id
identity_policy_id
credit_policy_id
collateral_policy_id
interest_policy_id
repayment_policy_id
settlement_policy_id
liquidation_policy_id
transfer_policy_id
refinancing_policy_id
restructuring_policy_id
cross_chain_policy_id?
insurance_policy_id?
fee_policy_id
governance_scope_id
funding_deadline
activation_deadline
commencement_rule
final_maturity_rule
grace_period_rule
metadata_commitment
agreement_hash
created_at
```

### 5.1 Immutable activation snapshot

At activation, Unified creates an immutable `AgreementSnapshot` containing:

- Final parties and authorized accounts.
- Final principal, denomination, and disbursement amount.
- Final lender positions or funding commitments.
- Final collateral and guarantee requirements.
- Exact policy implementation identifiers and versions.
- Accepted fees and economic terms.
- Applicable dates and calculation conventions.
- Transfer, refinancing, restructuring, liquidation, and dispute rights.
- Signed disclosures and accepted risk statements.
- Canonical metadata and document commitments.

General governance cannot alter this snapshot after activation.

### 5.2 Configurable versus immutable data

After activation, the following are immutable unless the original agreement expressly permits a governed amendment:

- Principal originally advanced.
- Accepted interest formula.
- Repayment calculation method.
- Maturity calculation.
- Collateral rights.
- Lender seniority and repayment waterfall.
- Borrower rights to repay.
- Default triggers.
- Liquidation method.
- Transfer restrictions.
- Policy versions.

The following may change through normal operation:

- Outstanding principal.
- Accrued interest.
- Paid amounts.
- Collateral value.
- Health factor.
- Current lender-position owner where transfers are permitted.
- Current servicing state.
- Current settlement state.
- Current cross-chain execution state.
- Current default or recovery state.

---

## 6. Policy Composition

Each loan references approved policy modules. A policy may calculate values or authorize transitions, but may not exceed its defined authority.

### 6.1 Mandatory policy families

Every loan must specify:

1. `IdentityPolicy`
2. `CreditPolicy`
3. `FundingPolicy`
4. `InterestPolicy`
5. `RepaymentPolicy`
6. `SettlementPolicy`
7. `FeePolicy`
8. `TransferPolicy`
9. `RefinancingPolicy`
10. `RestructuringPolicy`

A loan with collateral must also specify:

11. `CollateralPolicy`
12. `LiquidationPolicy`

A cross-chain loan must specify:

13. `CrossChainPolicy`

A guaranteed or insured loan must specify:

14. `GuaranteePolicy` or `InsurancePolicy`

### 6.2 Policy interface principles

Every policy shall expose:

- Policy identifier.
- Semantic version.
- Implementation address or service reference.
- Activation status.
- Supported product classes.
- Required inputs.
- Deterministic outputs where financially material.
- Failure behavior.
- Upgrade and deprecation status.
- Applicable constitutional invariants.

A policy used by an active loan cannot be silently replaced. New implementations apply only to future loans unless the active agreement contains an explicit opt-in migration mechanism.

---

# Part II — Canonical State Vector

## 7. Multi-Dimensional State Model

A loan shall not be represented by one oversized status. It shall have a coordinated state vector:

```text
LoanStateVector
├── MarketplaceState
├── UnderwritingState
├── FundingState
├── OriginationState
├── ServicingState
├── CollateralState
├── PaymentState
├── SettlementState
├── DefaultState
├── LiquidationState
├── RefinanceState
├── RestructureState
├── TransferState
├── CrossChainState
└── ClosureState
```

Each state domain has one canonical authority and one valid transition graph.

## 8. Transition Record

Every material transition must produce a `StateTransitionRecord`:

```text
transition_id
loan_id
state_domain
from_state
to_state
trigger_type
triggering_actor_id
authorization_reference
policy_id
policy_version
precondition_evidence[]
asset_movements[]
accounting_entry_ids[]
external_reference_ids[]
event_ids[]
initiated_at
finalized_at?
finality_status
reversal_reference?
failure_code?
```

No implementation may update a material state without producing an auditable transition record or equivalent on-chain event history.

---

# Part III — Marketplace and Agreement Formation

## 9. Marketplace State Machine

```text
DRAFT
  ↓ publish
OPEN
  ├──→ PAUSED
  ├──→ NEGOTIATING
  ├──→ COMMITMENT_PENDING
  ├──→ CANCELLED
  ├──→ EXPIRED
  └──→ FULFILLED
```

### 9.1 States

| State | Meaning |
|---|---|
| `DRAFT` | Borrower-controlled tender not yet available for offers. |
| `OPEN` | Tender is discoverable and may receive offers. |
| `PAUSED` | Tender remains valid but new offers are temporarily disabled. |
| `NEGOTIATING` | At least one active offer or counteroffer exists. |
| `COMMITMENT_PENDING` | A selected offer is awaiting required signatures, underwriting, or funding commitment. |
| `FULFILLED` | Tender resulted in a funded or activated loan. |
| `CANCELLED` | Borrower or authorized policy cancelled the tender before binding acceptance. |
| `EXPIRED` | Tender passed its published expiry without fulfillment. |

### 9.2 Publish tender

**Actor:** Borrower or authorized delegate.  
**Preconditions:** Valid borrower account; required disclosures; supported requested asset; tender fields complete; publication fee satisfied if applicable.  
**Effects:** Tender becomes discoverable; metadata commitment anchored where required.  
**Events:** `TenderPublished`.  
**Reversible:** Yes, through pause or cancellation until a binding offer is accepted.

### 9.3 Select offer

**Actor:** Borrower or authorized delegate.  
**Preconditions:** Tender open; offer valid, unexpired, and unconsumed; required borrower identity and disclosure conditions satisfied.  
**Effects:** Tender moves to `COMMITMENT_PENDING`; offer becomes reserved; competing offers may remain open or be suspended according to policy.  
**Events:** `OfferSelected`, `TenderCommitmentPending`.  
**Reversible:** According to offer terms before binding acceptance.

### 9.4 Fulfill tender

A tender becomes `FULFILLED` only after the associated funding or loan activation reaches the configured finality threshold. Merely signing an offer does not fulfill a tender.

---

## 10. Offer State Machine

```text
DRAFT
  ↓ sign
SIGNED
  ↓ submit
ACTIVE
  ├──→ COUNTERED
  ├──→ RESERVED
  ├──→ CANCELLED
  ├──→ EXPIRED
  ├──→ REJECTED
  └──→ CONSUMED
```

### 10.1 Binding representation

Messages and chat statements are non-binding unless explicitly converted into a structured signed offer or amendment object.

Every offer must define:

- Offer identifier.
- Tender or borrower scope.
- Lender or syndicate originator.
- Principal commitment.
- Interest and repayment terms.
- Required collateral and guarantees.
- Offer expiry.
- Nonce or replay-protection field.
- Chain and protocol domain.
- Policy versions or policy-selection constraints.
- Signature or authorization proof.

### 10.2 Consume offer

An offer becomes `CONSUMED` exactly once when it forms part of an activated or irrevocably funded agreement.

**Critical invariant:** No offer nonce or signed commitment may be consumed twice, including across chains, contract versions, or refinancing workflows.

---

# Part IV — Credit and Underwriting

## 11. Underwriting State Machine

```text
NOT_REQUIRED

or

REQUESTED
  ↓
DATA_PENDING
  ↓
IN_REVIEW
  ├──→ MORE_INFORMATION_REQUIRED
  ├──→ APPROVED
  ├──→ APPROVED_WITH_CONDITIONS
  ├──→ DECLINED
  ├──→ EXPIRED
  └──→ WITHDRAWN
```

### 11.1 Underwriting request

**Actor:** Borrower, lender, marketplace coordinator, or automated origination policy.  
**Preconditions:** Valid tender or proposed agreement; borrower consent to required data access; model and policy versions approved.  
**Effects:** Creates a `CreditApplication`; records consent scope and purpose.  
**Events:** `UnderwritingRequested`.

### 11.2 Decision requirements

A credit decision shall identify:

- Decision identifier.
- Underwriting policy and version.
- Model version if automated.
- Validity period.
- Approved amount and term limits.
- Required collateral, guarantee, pricing, or reserve conditions.
- Explanation code set.
- Appeal or review path where applicable.

Raw sensitive inputs remain protected. The contractual system consumes only the required decision or proof.

### 11.3 Conditional approval

A conditional approval may require:

- Additional collateral.
- Guarantor execution.
- Insurance premium funding.
- Identity credential.
- Debt repayment.
- Revenue-account connection.
- Reduced principal.
- Modified maturity.

The loan cannot activate until all conditions are independently verified.

---

# Part V — Funding and Syndication

## 12. Funding State Machine

```text
NOT_OPEN
  ↓
OPEN
  ├──→ PARTIALLY_COMMITTED
  ├──→ FULLY_COMMITTED
  ├──→ OVERCOMMITTED
  ├──→ FAILED
  ├──→ CANCELLED
  └──→ EXPIRED

FULLY_COMMITTED
  ↓
ESCROW_PENDING
  ↓
ESCROWED
  ↓
DISBURSEMENT_READY
  ↓
DISBURSED
```

### 12.1 Funding structures

The funding policy may authorize:

- One lender.
- Multiple pro-rata lenders.
- Senior and junior tranches.
- Open funding round.
- Lead-arranged syndicate.
- Pooled liquidity source.
- Hybrid on-chain and off-chain funding.

### 12.2 Funding commitment

A `FundingCommitment` is distinct from a final disbursement.

It must specify:

```text
commitment_id
loan_or_tender_id
lender_party_id
funding_account_id
committed_amount
asset_id
tranche_id?
priority_class
commitment_expiry
funding_conditions
signature_or_onchain_lock
status
```

### 12.3 Minimum and maximum funding

The Funding Policy shall define:

- Target amount.
- Minimum viable amount.
- Maximum accepted amount.
- Overcommitment allocation rule.
- Partial-funding treatment.
- Refund procedure if activation fails.
- Commitment cancellation rights.

### 12.4 Syndicate position issuance

Lender positions may be issued only after corresponding value is escrowed or finally committed under an approved settlement policy.

**Invariant:** Aggregate lender principal claims must equal the principal economically supplied, adjusted only by disclosed fees or discounts.

### 12.5 Funding failure

If the minimum viable funding threshold is not reached by the deadline:

- The funding round becomes `FAILED` or `EXPIRED`.
- Escrowed funds become withdrawable or refundable.
- No borrower debt arises.
- No collateral may remain indefinitely locked.
- No lender position may retain a claim against the borrower.

---

# Part VI — Origination and Activation

## 13. Origination State Machine

```text
PROPOSED
  ↓
VALIDATING
  ↓
APPROVED
  ↓
ASSET_LOCK_PENDING
  ↓
READY_TO_ACTIVATE
  ↓
ACTIVATING
  ├──→ ACTIVE
  └──→ ACTIVATION_FAILED
```

### 13.1 Activation readiness

A loan may enter `READY_TO_ACTIVATE` only when all applicable conditions are satisfied:

- Final agreement signatures valid.
- Offer or commitments unexpired and unconsumed.
- Underwriting approved.
- Identity requirements satisfied.
- Funding escrowed or externally guaranteed.
- Collateral locked or verified.
- Guarantees and insurance active.
- Required fees funded.
- Cross-chain components ready.
- Fiat or card settlement state meets the agreed threshold.
- All policy versions approved.
- No emergency restriction blocks new activation.

### 13.2 Atomic activation

For same-chain digital-asset loans, activation should be atomic:

1. Validate agreement and policy references.
2. Consume offer and commitment nonces.
3. Lock collateral.
4. Finalize lender positions.
5. Transfer or release principal.
6. Route origination fees.
7. Initialize obligations and schedule.
8. Set commencement and maturity timestamps.
9. Move origination state to `ACTIVE`.
10. Emit activation and accounting events.

Either every mandatory action succeeds or none becomes final.

### 13.3 Coordinated non-atomic activation

Fiat, card, and cross-chain loans may require coordinated finality. In those cases:

- Assets may enter controlled escrow.
- The loan remains `ACTIVATING` until all required confirmations arrive.
- Borrower debt does not become active before the agreed disbursement threshold.
- Compensation and rollback procedures must be predefined.
- Timeouts must return funds or move the loan into a recoverable exception state.

### 13.4 Activation failure

`ACTIVATION_FAILED` must identify:

- Failed condition.
- Assets currently held.
- Refund or release path.
- Retry eligibility.
- Deadline for recovery.
- Responsible adapter or provider.

No failed activation may leave ambiguous debt, duplicate lender claims, or inaccessible collateral.

---

# Part VII — Servicing and Obligation Accounting

## 14. Servicing State Machine

```text
NOT_STARTED
  ↓ activate
CURRENT
  ├──→ GRACE
  ├──→ DELINQUENT
  ├──→ CURED
  ├──→ RESTRUCTURING
  ├──→ REFINANCING
  ├──→ ACCELERATED
  ├──→ DEFAULTED
  ├──→ REPAID
  └──→ SETTLED
```

`CURED` is a transition marker and normally returns to `CURRENT`.

### 14.1 Current

A loan is `CURRENT` when all currently due obligations have been satisfied or no amount is yet due.

### 14.2 Grace

A loan enters `GRACE` when a due date has passed but the contractual grace period has not expired.

The policy must define:

- Whether late fees accrue.
- Whether default interest applies.
- Whether borrower reputation is affected.
- Whether collateral may be liquidated during grace.
- Whether payments must settle or merely be initiated before grace expires.

### 14.3 Delinquent

A loan is `DELINQUENT` when a required obligation remains unpaid after its applicable due date and grace treatment, but the loan has not yet reached contractual default.

### 14.4 Accelerated

Acceleration makes some or all future obligations immediately due under a predefined contractual event.

Acceleration must be explicitly authorized by the accepted policy and cannot be created retroactively by governance or a servicer.

### 14.5 Repaid

A loan becomes `REPAID` only when:

- All principal is satisfied.
- All contractually due interest is satisfied.
- All enforceable fees and charges are satisfied.
- All payment reversals and provisional settlement risks required by policy are resolved.
- No unresolved lender allocation remains.

### 14.6 Settled

`SETTLED` may be used when obligations are discharged through negotiated settlement, insurance proceeds, collateral transfer, legal recovery, tokenized settlement, or another accepted non-standard method.

The settlement record must identify any amount forgiven, written off, recovered, or paid by third parties.

---

## 15. Obligation Model

A loan may contain multiple obligations:

```text
Principal Obligation
Interest Obligation
Origination Fee
Servicing Fee
Late Fee
Insurance Premium
Guarantee Fee
Cross-Chain Cost
Card or Bank Processing Cost
Legal Recovery Cost
Liquidation Cost
Penalty or Make-Whole Amount
```

Every obligation must specify:

- Amount or calculation formula.
- Denomination.
- Accrual period.
- Due date or trigger.
- Priority in the payment waterfall.
- Beneficiary.
- Waiver or modification authority.
- Tax or regulatory treatment where applicable.
- Accounting classification.

## 16. Interest Accrual

Interest policies may support:

- Fixed total interest.
- Simple annualized interest.
- Compound interest.
- Variable benchmark plus spread.
- Utilization-based rates.
- Revenue-linked rates.
- Profit participation.
- Hybrid fixed-variable periods.

Every calculation must define:

```text
rate source
day-count convention
compounding convention
rounding mode
minimum and maximum rate
rate reset frequency
stale-data behavior
negative-rate behavior
accrual start
accrual end
prepayment treatment
delinquency treatment
```

Financial calculations must be deterministic and reproducible from recorded inputs.

---

# Part VIII — Repayment Schedule and Payment Allocation

## 17. Repayment Schedule State Machine

Each installment or schedule item has its own state:

```text
SCHEDULED
  ↓
DUE
  ├──→ PARTIALLY_PAID
  ├──→ PAID
  ├──→ OVERDUE
  ├──→ WAIVED
  ├──→ DEFERRED
  └──→ REPLACED
```

### 17.1 Supported schedule types

- Bullet.
- Equal principal.
- Annuity or equal payment.
- Interest only.
- Balloon.
- Seasonal.
- Revenue share.
- Milestone based.
- Irregular custom schedule.
- Revolving credit minimum payment.

### 17.2 Payment waterfall

Every repayment policy must define a deterministic allocation order. A default order may be:

1. Recoverable external processing costs.
2. Enforcement and liquidation costs.
3. Penalty charges.
4. Overdue fees.
5. Overdue interest.
6. Current fees.
7. Current interest.
8. Principal.
9. Insurance or reserve contribution.
10. Excess return to payer.

The actual order must be visible before loan acceptance.

### 17.3 Partial payments

A partial payment must:

- Be accepted or rejected according to policy.
- Allocate deterministically.
- Update all affected obligations.
- Update schedule state.
- Preserve an auditable residual balance.
- Not falsely mark the loan current if required minimums remain unpaid.

### 17.4 Early repayment

The agreement must define whether early repayment:

- Is always permitted.
- Requires a make-whole or prepayment fee.
- Reduces future interest.
- Reduces term.
- Reduces subsequent installments.
- Applies only to principal after current interest.

A borrower’s constitutional repayment right does not prohibit a clearly disclosed and lawful prepayment formula accepted at origination.

---

## 18. Payment State Machine

```text
CREATED
  ↓
AUTHORIZED
  ↓
SUBMITTED
  ├──→ PENDING
  ├──→ PROVISIONAL
  ├──→ FINAL
  ├──→ FAILED
  ├──→ CANCELLED
  ├──→ REVERSED
  └──→ DISPUTED
```

### 18.1 Payment instruction

A payment instruction identifies:

- Payer.
- Source account.
- Loan and obligation allocation intent.
- Asset and amount.
- Settlement rail.
- Maximum fees or slippage.
- Expiry.
- Authorization proof.

### 18.2 Finality

A payment affects final loan balances only at the settlement threshold defined by the loan’s Settlement Policy.

Examples:

- On-chain token transfer: required confirmations plus protocol acceptance.
- Card: processor settlement and expiry of required reversal reserve period.
- Bank: provider-confirmed final settlement and reconciliation.
- Cross-chain: canonical message execution and destination receipt.

### 18.3 Reversal

If a provisional payment is reversed:

- The provisional credit is removed.
- Any collateral release dependent on that credit must not have finalized unless backed by a reserve.
- Delinquency and interest may be recalculated according to policy.
- A reversal event and accounting reversal entries are required.

Posted accounting entries are reversed through compensating entries, never silently edited.

---

## 19. Settlement State Machine

```text
NOT_INITIATED
  ↓
INSTRUCTION_CREATED
  ↓
PROCESSING
  ├──→ PROVISIONAL
  ├──→ FINAL
  ├──→ FAILED
  ├──→ REVERSED
  ├──→ DISPUTED
  └──→ RECOVERY_PENDING
```

Settlement is separate from Payment because one payment may involve several settlement legs, currency conversions, chains, or providers.

---

# Part IX — Collateral and Risk

## 20. Collateral Position State Machine

```text
PROPOSED
  ↓
VALUATION_PENDING
  ↓
APPROVED
  ↓
DEPOSIT_PENDING
  ↓
LOCKED
  ├──→ HEALTHY
  ├──→ WARNING
  ├──→ MARGIN_CALL
  ├──→ TOP_UP_PENDING
  ├──→ PARTIAL_RELEASE_ELIGIBLE
  ├──→ LIQUIDATION_ELIGIBLE
  ├──→ LIQUIDATING
  ├──→ RELEASED
  └──→ CLAIMED
```

### 20.1 Collateral types

- Native digital assets.
- ERC-20 or equivalent fungible tokens.
- UFT.
- ERC-721 NFTs.
- ERC-1155 assets.
- Liquidity-provider positions.
- Tokenized real-world assets.
- Off-chain pledged assets through verified custodians.
- Mixed collateral bundles.

### 20.2 Locking collateral

Collateral is `LOCKED` only when custody or enforceable lien finality has been established.

A user interface must not describe collateral as locked merely because a deposit transaction was initiated.

### 20.3 Valuation

Every valuation must record:

- Asset identifier.
- Quantity.
- Price source or appraisal source.
- Price timestamp.
- Confidence or liquidity measure.
- Haircut.
- Risk-adjusted value.
- Policy version.

### 20.4 Dynamic collateralization

Dynamic requirements may use market price, volatility, liquidity, concentration, asset correlation, borrower reputation, and macro risk. However:

- The formula must be fixed by the active policy version.
- Governance cannot selectively change one active borrower’s formula.
- Reputation adjustments are bounded.
- Maintenance and liquidation thresholds must remain explicit.

### 20.5 Collateral release

Collateral may be released only when:

- The secured obligation is fully satisfied or validly transferred.
- Required payment finality is reached.
- No unresolved reversal risk remains unless covered.
- No competing lien exists.
- Cross-chain release proof is final.
- Release authorization matches the active agreement.

---

## 21. Margin Call State Machine

```text
NOT_REQUIRED
  ↓ threshold breach
ISSUED
  ├──→ ACKNOWLEDGED
  ├──→ CURED_BY_TOP_UP
  ├──→ CURED_BY_REPAYMENT
  ├──→ EXPIRED
  └──→ LIQUIDATION_ELIGIBLE
```

The margin-call policy defines:

- Trigger threshold.
- Cure period.
- Permitted cure methods.
- Notification channels.
- Whether partial liquidation may occur immediately.
- Whether severe market movement bypasses the cure period.

---

# Part X — Default, Liquidation, and Recovery

## 22. Default State Machine

```text
NO_DEFAULT
  ↓ potential event
DEFAULT_CANDIDATE
  ↓ verify
DEFAULT_CONFIRMED
  ├──→ CURED
  ├──→ RESTRUCTURING
  ├──→ LIQUIDATION
  ├──→ INSURANCE_CLAIM
  ├──→ RECOVERY
  └──→ SETTLED
```

### 22.1 Default events

A policy may recognize:

- Payment default.
- Collateral maintenance default.
- Covenant default.
- Fraud or misrepresentation.
- Insolvency or bankruptcy event.
- Unauthorized collateral transfer.
- Cross-default.
- Provider or custodian failure where allocated to the borrower.

Default must arise from predefined objective or attestable conditions.

### 22.2 Confirmation

A default candidate becomes confirmed only after:

- Required grace or cure period expires.
- Payment finality and reversal status are resolved.
- Oracle or valuation evidence is valid.
- Required notices are issued.
- Any dispute hold defined by policy is completed.

### 22.3 Cure

A default may be cured only if the accepted policy permits it. Cure must record:

- Amount paid or collateral added.
- Fees or penalties.
- Updated obligations.
- Reputation consequence.
- Whether the original maturity remains.

---

## 23. Liquidation State Machine

```text
NOT_ELIGIBLE
  ↓
ELIGIBLE
  ↓
INITIATED
  ├──→ PARTIAL_LIQUIDATION
  ├──→ AUCTION_ACTIVE
  ├──→ DIRECT_SALE
  ├──→ LENDER_CLAIM_PENDING
  ├──→ PAUSED
  ├──→ FAILED
  └──→ COMPLETED
```

### 23.1 Liquidation methods

- Direct lender claim.
- Automated exchange route.
- Partial liquidation.
- Dutch auction.
- English auction.
- Sealed-bid auction.
- NFT auction.
- Off-chain custodian sale.
- Recovery-agent sale.

### 23.2 Liquidation waterfall

The policy must define distribution order, such as:

1. Direct execution costs.
2. Liquidation incentive.
3. Senior secured principal.
4. Senior interest and fees.
5. Junior secured claims.
6. Insurance or guarantor reimbursement.
7. Protocol charges.
8. Surplus return to borrower.

No liquidator, lender, administrator, or treasury may retain borrower surplus unless the agreement explicitly and lawfully provides otherwise.

### 23.3 Reproducibility

Every liquidation must be reproducible from:

- Triggering obligation state.
- Collateral quantity.
- Recorded price or appraisal.
- Thresholds.
- Auction or route rules.
- Fees.
- Proceeds.
- Distribution entries.

---

## 24. Recovery State Machine

```text
NOT_REQUIRED
  ↓
OPEN
  ├──→ NEGOTIATING
  ├──→ LEGAL_ENFORCEMENT
  ├──→ GUARANTOR_COLLECTION
  ├──→ INSURANCE_COLLECTION
  ├──→ PARTIALLY_RECOVERED
  ├──→ FULLY_RECOVERED
  ├──→ WRITTEN_OFF
  └──→ CLOSED
```

Recovery is especially relevant to unsecured, guaranteed, fiat-settled, and off-chain-collateral loans.

### 24.1 Bad debt

Bad debt must be recognized explicitly when outstanding obligations exceed expected recoveries.

It may not be hidden by:

- Inflated collateral valuations.
- Unfunded insurance claims.
- Circular UFT valuations.
- Treasury receivables without authority.
- Unrecorded lender losses.

### 24.2 Loss waterfall

A loan’s loss waterfall may include:

1. Loan collateral.
2. Borrower reserve or security deposit.
3. Guarantor obligation.
4. Junior tranche.
5. Loan-specific insurance.
6. Product reserve.
7. Protocol safety module.
8. Senior lenders.
9. Governance-approved socialized loss, only if constitutionally allowed and explicitly funded.

---

# Part XI — Refinancing and Restructuring

## 25. Refinancing State Machine

```text
NOT_REQUESTED
  ↓
REQUESTED
  ↓
QUOTE_PENDING
  ↓
OFFERED
  ├──→ ACCEPTED
  ├──→ REJECTED
  ├──→ EXPIRED
  └──→ CANCELLED

ACCEPTED
  ↓
FUNDING_PENDING
  ↓
PAYOFF_PENDING
  ↓
COLLATERAL_TRANSFER_PENDING
  ↓
COMPLETED
```

### 25.1 Refinance requirements

A refinancing transaction must establish:

- Exact payoff amount and expiry.
- Accrued interest treatment.
- Existing lender payment.
- New lender commitment.
- Collateral lien priority.
- Transfer or replacement of guarantees.
- Release of old lender positions.
- Creation of new loan or amendment.
- Fees and borrower proceeds.

### 25.2 No double senior claim

At no point may two lenders hold an undisclosed first-priority claim over the same collateral.

For atomic digital-asset refinancing:

1. New funds enter escrow.
2. Old obligation is repaid.
3. Old lien is released.
4. Collateral is assigned to the new loan.
5. New loan activates.
6. Remaining proceeds are paid to borrower.

If any mandatory step fails, the refinance must revert or enter a predefined recoverable state without creating duplicate claims.

---

## 26. Restructuring State Machine

```text
NOT_REQUESTED
  ↓
REQUESTED
  ↓
NEGOTIATING
  ↓
VOTING_OR_APPROVAL
  ├──→ APPROVED
  ├──→ REJECTED
  ├──→ EXPIRED
  └──→ WITHDRAWN

APPROVED
  ↓
EXECUTING
  ↓
EFFECTIVE
```

A restructuring changes the existing agreement rather than replacing it with a new loan.

Possible modifications:

- Extended maturity.
- Reduced rate.
- Capitalized arrears.
- Payment holiday.
- Added collateral.
- Partial forgiveness.
- Tranche conversion.
- Revised repayment schedule.

Only the amendment mechanism accepted at origination may authorize restructuring. General protocol governance cannot impose it on an individual loan.

---

# Part XII — Lender Positions and Secondary Market

## 27. Position State Machine

```text
PENDING_ISSUANCE
  ↓
ACTIVE
  ├──→ LISTED
  ├──→ TRANSFER_PENDING
  ├──→ TRANSFERRED
  ├──→ PLEDGED
  ├──→ FROZEN
  ├──→ REDEEMED
  └──→ EXTINGUISHED
```

### 27.1 Position rights

A lender position may carry rights to:

- Principal repayment.
- Interest.
- Fees.
- Recovery proceeds.
- Amendment votes.
- Enforcement votes.
- Information rights.
- Transfer rights.

These rights must be encoded in the position metadata and funding policy.

### 27.2 Transfer validation

Before transfer:

- Seller ownership must be verified.
- Position must be transferable.
- Buyer eligibility must satisfy identity and jurisdiction policy.
- Accrued-interest allocation must be calculated.
- Existing pledge or freeze must be checked.
- Payment settlement must reach required finality.

Future cash flows redirect only after the transfer becomes final.

### 27.3 Fractionalization

Fractionalization may occur only if aggregate fractions equal the original economic claim and do not create additional rights.

---

# Part XIII — Cross-Chain Coordination

## 28. Cross-Chain State Machine

```text
LOCAL_ONLY

or

PREPARING
  ↓
SOURCE_LOCK_PENDING
  ↓
SOURCE_LOCKED
  ↓
MESSAGE_SENT
  ↓
MESSAGE_VERIFIED
  ↓
DESTINATION_EXECUTION_PENDING
  ├──→ DESTINATION_EXECUTED
  ├──→ FAILED
  ├──→ EXPIRED
  └──→ RECOVERY_PENDING
```

### 28.1 Canonical home authority

Every cross-chain loan has exactly one canonical home authority for:

- Agreement terms.
- Global obligation accounting.
- Position registry.
- Final servicing state.
- Governance scope.

Satellite chains may own local collateral custody or settlement execution, but they cannot independently rewrite global loan economics.

### 28.2 Message requirements

Every cross-chain message must contain:

- Message identifier.
- Loan identifier.
- Source chain.
- Destination chain.
- Source nonce.
- Message type.
- Payload hash.
- Expiry.
- Adapter version.
- Verification proof.

Every message must be consumed at most once.

### 28.3 Failure recovery

Cross-chain policies must define:

- Timeout.
- Retry authority.
- Alternative adapter procedure.
- Refund or unlock procedure.
- Manual recovery authority.
- Proof standard.
- Compensation rules.

Bridge failure must not silently create duplicate principal, collateral, UFT, or lender positions.

---

# Part XIV — Fiat and Card Settlement

## 29. Fiat Settlement Rules

Fiat settlement requires a regulated provider or approved banking integration.

Canonical external facts include:

- Provider instruction accepted.
- Funds received.
- Funds cleared.
- Funds reversed.
- Funds returned.
- Beneficiary paid.

Unified records signed provider attestations and corresponding ledger entries.

### 29.1 Debt activation threshold

For fiat disbursement, the agreement must define whether debt activates when:

- Provider accepts instruction.
- Provider debits lender.
- Funds clear into escrow.
- Borrower bank receives funds.
- Settlement becomes irreversible under the applicable rail.

The selected threshold must be disclosed and enforced consistently.

## 30. Card Settlement Rules

Card authorization is not final settlement.

A card-funded or card-repaid amount may pass through:

```text
AUTHORIZED
→ CAPTURED
→ PROVISIONAL
→ SETTLED
→ CHARGEBACK_ELIGIBLE_EXPIRED
```

or:

```text
PROVISIONAL
→ DISPUTED
→ CHARGEBACK
→ REVERSED
```

Collateral release based on card repayment requires either:

- Final settlement under the active policy.
- A funded chargeback reserve.
- A provider guarantee.
- Another explicit risk-transfer mechanism.

---

# Part XV — Insurance and Guarantees

## 31. Guarantee State Machine

```text
PROPOSED
  ↓
ACCEPTED
  ↓
ACTIVE
  ├──→ CLAIM_PENDING
  ├──→ CLAIM_PAID
  ├──→ EXPIRED
  ├──→ RELEASED
  └──→ EXHAUSTED
```

A guarantee must define:

- Guarantor.
- Maximum amount.
- Covered obligations.
- Trigger conditions.
- Priority.
- Expiry.
- Collateral or reserve backing.
- Recovery rights against borrower.

## 32. Insurance Claim State Machine

```text
NOT_APPLICABLE

or

ELIGIBLE
  ↓
SUBMITTED
  ↓
UNDER_REVIEW
  ├──→ APPROVED
  ├──→ PARTIALLY_APPROVED
  ├──→ REJECTED
  ├──→ DISPUTED
  └──→ EXPIRED

APPROVED
  ↓
PAYMENT_PENDING
  ↓
PAID
```

No insurance amount may be recognized as a funded recovery until the relevant reserve or insurer payment is final.

---

# Part XVI — Closure and Archival

## 33. Closure State Machine

```text
OPEN
  ↓
CLOSURE_PENDING
  ↓
CLOSED
  ├──→ REOPENED_FOR_DISPUTE_ONLY
  └──→ ARCHIVED
```

### 33.1 Closure conditions

A loan may close when:

- Obligations are repaid, settled, written off, or otherwise discharged.
- Collateral is released, claimed, or fully liquidated.
- Lender positions are redeemed or extinguished.
- Payment and settlement disputes are resolved or separately provisioned.
- Accounting is balanced.
- Cross-chain components are finalized.
- Required records are preserved.

### 33.2 Terminal-state protection

Closure does not permit economic reactivation. A closed loan may be reopened only for dispute records, recoveries, corrections through compensating accounting entries, or legal administration. New debt requires a new loan or valid refinancing agreement.

---

# Part XVII — Authorization Matrix

## 34. Actor Classes

```text
BORROWER
LENDER
SYNDICATE_AGENT
GUARANTOR
INSURER
SERVICER
LIQUIDATOR
RECOVERY_AGENT
IDENTITY_ATTESTER
CREDIT_ATTESTER
PAYMENT_PROVIDER
BRIDGE_ADAPTER
ORACLE_PROVIDER
GOVERNANCE
RISK_COUNCIL
EMERGENCY_COUNCIL
PROTOCOL_AUTOMATION
COURT_OR_LEGAL_AUTHORITY
```

## 35. High-Level Authorization Matrix

| Action | Primary authorized actor | Additional requirements |
|---|---|---|
| Publish tender | Borrower/delegate | Identity and disclosure policy |
| Submit offer | Lender/delegate | Eligibility and signature |
| Accept offer | Borrower | Offer valid and conditions satisfied |
| Commit funding | Lender | Funding policy and asset authorization |
| Activate loan | Protocol coordinator | All activation invariants |
| Make repayment | Borrower or third party | Payment authorization |
| Allocate repayment | Protocol/servicer | Repayment waterfall |
| Add collateral | Borrower or approved third party | Collateral policy |
| Release collateral | Protocol | Debt and finality conditions |
| Declare default | Protocol, servicer, or lender | Objective policy trigger |
| Initiate liquidation | Authorized liquidator/protocol | Eligibility verified |
| Transfer lender position | Position owner | Transfer policy and buyer eligibility |
| Request refinance | Borrower or authorized lender | Refinance policy |
| Approve restructuring | Required loan parties | Contractual voting rule |
| Pause new originations | Emergency authority | Bounded emergency power |
| Change active loan economics | No general actor | Only valid loan-level amendment |

---

# Part XVIII — Financial and Accounting Effects

## 36. Mandatory Accounting Events

Every material financial transition must produce balanced accounting entries or references to canonical on-chain movements.

Required accounting event families include:

```text
FundingCommitted
FundingEscrowed
PrincipalDisbursed
BorrowerObligationRecognized
CollateralLocked
FeeRecognized
InterestAccrued
PaymentReceived
PaymentFinalized
PaymentAllocated
PaymentReversed
PrincipalReduced
CollateralReleased
DefaultRecognized
LiquidationProceedsReceived
RecoveryRecognized
InsuranceReceivableRecognized
InsuranceProceedsReceived
BadDebtRecognized
PositionTransferred
LoanClosed
```

## 37. Example activation entries

Conceptually:

```text
Lender funding escrow
Dr Funding Escrow Asset
Cr Lender Cash or Token Position

Principal disbursement
Dr Borrower Loan Receivable
Cr Funding Escrow Asset

Borrower obligation recognition
Dr Borrower Principal Obligation Control
Cr Lender Principal Claim Control

Collateral lock
Dr Restricted Collateral Control
Cr Borrower Available Collateral Control
```

The Financial Accounting Specification will define the exact chart of accounts, dimensions, currency translation, and journal rules.

---

# Part XIX — Event Contract

## 38. Required Domain Events

### Marketplace

```text
TenderCreated
TenderPublished
TenderPaused
TenderCancelled
TenderExpired
OfferSigned
OfferSubmitted
OfferCountered
OfferSelected
OfferConsumed
```

### Underwriting

```text
UnderwritingRequested
CreditDataConsentGranted
CreditDecisionIssued
CreditDecisionExpired
CreditConditionSatisfied
```

### Funding and origination

```text
FundingRoundOpened
FundingCommitted
FundingThresholdReached
FundingEscrowed
LoanValidationCompleted
CollateralLockConfirmed
LoanActivationStarted
LoanActivated
LoanActivationFailed
```

### Servicing and payments

```text
InterestAccrued
InstallmentBecameDue
PaymentAuthorized
PaymentSubmitted
PaymentProvisional
PaymentFinalized
PaymentAllocated
PaymentReversed
LoanBecameDelinquent
LoanCured
LoanRepaid
```

### Risk and recovery

```text
CollateralValued
MarginCallIssued
CollateralToppedUp
DefaultCandidateCreated
LoanDefaultConfirmed
LiquidationInitiated
LiquidationCompleted
RecoveryOpened
RecoveryReceived
BadDebtRecognized
InsuranceClaimPaid
```

### Refinance, restructure, and positions

```text
RefinanceRequested
PayoffQuoteIssued
RefinanceCompleted
RestructureProposed
RestructureApproved
LenderPositionIssued
LenderPositionListed
LenderPositionTransferred
LenderPositionRedeemed
```

### Cross-chain and closure

```text
CrossChainMessageSent
CrossChainMessageVerified
CrossChainExecutionCompleted
CrossChainRecoveryOpened
LoanClosureStarted
LoanClosed
LoanArchived
```

Every event shall include schema version, canonical entity identifier, transition identifier, actor, timestamp or block reference, and sufficient correlation data.

---

# Part XX — Failure and Recovery Model

## 39. Failure Classes

```text
VALIDATION_FAILURE
AUTHORIZATION_FAILURE
INSUFFICIENT_FUNDS
INSUFFICIENT_COLLATERAL
ORACLE_FAILURE
PRICE_STALENESS
PAYMENT_PROVIDER_FAILURE
CARD_REVERSAL
BANK_REVERSAL
BRIDGE_FAILURE
MESSAGE_TIMEOUT
SMART_CONTRACT_REVERT
INDEXER_DIVERGENCE
ACCOUNTING_MISMATCH
DUPLICATE_MESSAGE
DUPLICATE_PAYMENT
MODEL_UNAVAILABLE
ATTESTATION_REVOKED
GOVERNANCE_CONFIGURATION_ERROR
EMERGENCY_PAUSE
```

## 40. Recovery principles

1. No failure may create duplicate debt or duplicate asset claims.
2. User funds in failed workflows must remain identifiable.
3. Retriable operations require idempotency keys or nonces.
4. Compensation must be recorded through explicit transitions and accounting entries.
5. Manual intervention must use bounded roles and auditable evidence.
6. A frontend retry must not duplicate a finalized backend or on-chain action.
7. Indexer disagreement cannot override canonical state.
8. Emergency pause must preserve repayment and safe withdrawal paths where technically possible.

## 41. Idempotency

The following operations require unique idempotency or replay-protection keys:

- Offer consumption.
- Funding commitment.
- Payment instruction.
- Provider callback.
- Cross-chain message.
- Position transfer.
- Collateral release.
- Liquidation settlement.
- Insurance payment.
- Refinance payoff.

---

# Part XXI — Product Composition Examples

## 42. Example A: Single-Lender Crypto Loan

```text
Borrower identity: Pseudonymous verified
Funding: One lender
Principal: USDC
Collateral: WETH
Interest: Fixed
Repayment: Bullet
Settlement: Same-chain
Liquidation: Health-factor partial liquidation
Transfer: Non-transferable
```

Relevant state domains:

- Marketplace.
- Underwriting optional.
- Funding.
- Origination.
- Servicing.
- Payment.
- Collateral.
- Liquidation.
- Closure.

## 43. Example B: Syndicated Business Loan

```text
Borrower: Verified company
Funding: Senior and junior tranches
Principal: Fiat-denominated
Collateral: Tokenized assets plus guarantee
Interest: Benchmark plus spread
Repayment: Monthly amortization
Settlement: Bank rails
Transfer: Eligible institutional buyers
Recovery: Guarantee, collateral, junior-first loss
```

This product uses nearly every major state domain but still relies on the same universal model.

## 44. Example C: NFT-Backed Cross-Chain Loan

```text
Home chain: Ethereum-compatible canonical chain
Collateral: NFT on satellite chain
Principal: Stablecoin on another chain
Interest: Fixed
Repayment: Bullet
Liquidation: NFT auction
Cross-chain: Verified message adapters
```

The home chain owns the agreement and debt. Satellite contracts own local custody and execution only.

## 45. Example D: Anonymous Unsecured Microcredit

```text
Identity: Zero-knowledge unique-user proof
Collateral: None
Funding: Diversified risk pool
Interest: Risk-based fixed rate
Repayment: Weekly installments
Risk protection: Reserve and reputation bond
Recovery: Future access restriction and reserve waterfall
```

The product must disclose that conventional legal recovery may be unavailable.

---

# Part XXII — Cross-State Invariants

## 46. Universal invariants

1. A loan cannot become active without a valid immutable agreement snapshot.
2. A loan cannot become active before the funding condition is satisfied.
3. A collateralized loan cannot become active before collateral lock finality.
4. Borrower debt cannot arise before the contractual disbursement threshold.
5. An offer or funding commitment cannot be consumed twice.
6. Aggregate lender positions cannot exceed funded economic rights.
7. Active policy versions cannot be silently replaced.
8. A payment cannot reduce final debt before required finality.
9. A reversed payment must restore affected obligations through explicit entries.
10. Collateral cannot be released while secured debt remains outstanding.
11. Liquidation cannot occur without a valid policy trigger.
12. Liquidation surplus belongs to the contractually entitled party, normally the borrower.
13. General governance cannot alter one active loan’s economics.
14. Refinancing cannot create duplicate senior collateral claims.
15. Position transfer cannot duplicate future cash-flow rights.
16. Cross-chain messages are consumed at most once.
17. Satellite state cannot override canonical home-loan economics.
18. External provider data cannot be treated as final beyond its actual finality status.
19. Rewards, insurance, and guarantees cannot exceed funded or legally enforceable capacity.
20. Closure requires accounting and asset-state reconciliation.
21. A closed loan cannot be economically reactivated.
22. Sensitive identity and credit data cannot be exposed through loan events.
23. Every financially material calculation must be reproducible.
24. Every material state transition must be attributable to an actor or deterministic policy.
25. Emergency controls cannot confiscate user assets or erase repayment rights.

---

# Part XXIII — Implementation Requirements

## 47. Smart-contract requirements

Smart-contract implementations shall include:

- Explicit state enums or equivalent typed state representations.
- Role and authorization checks.
- Nonce and replay protection.
- Reentrancy protection where value moves.
- Safe token-transfer handling.
- Asset allowlists and adapter validation.
- Versioned policy references.
- Event emission for every material transition.
- Emergency pause boundaries.
- Invariant and property tests.
- Migration restrictions for active loans.

## 48. Backend requirements

Services shall include:

- Idempotent commands.
- Transactional outbox or equivalent event reliability.
- Canonical-state reconciliation.
- Double-entry accounting integration.
- Signed provider-callback verification.
- Policy and model version capture.
- Privacy and access controls.
- Immutable audit history.
- Recovery queues for failed external operations.

## 49. Frontend requirements

The interface must show:

- Current canonical and provisional states separately.
- Assets and amounts that will move.
- Fees, rates, and schedule rules.
- Collateral and liquidation risk.
- Payment finality.
- Position transfer restrictions.
- Cross-chain dependencies.
- Automated decision explanations.
- Irreversible actions.

A frontend may not label a transaction complete before canonical finality.

## 50. Testing requirements

Every implementation must include:

- Unit tests.
- State-transition tests.
- Invalid-transition tests.
- Property-based tests.
- Smart-contract fuzz tests.
- Cross-state invariant tests.
- Accounting-balance tests.
- Duplicate-message tests.
- Payment-reversal tests.
- Oracle-staleness tests.
- Liquidation simulations.
- Refinancing atomicity tests.
- Cross-chain timeout and replay tests.
- Emergency-pause tests.

---

# Part XXIV — Ratification Checklist

## 51. Specification completeness questions

Before this specification is ratified, Unified must confirm:

1. Does every product use the same Loan Aggregate?
2. Are all policy families explicitly versioned?
3. Is the canonical authority of each state domain identified?
4. Are activation and disbursement thresholds unambiguous?
5. Are provisional and final settlement separated?
6. Are all payment allocations deterministic?
7. Are all collateral-release conditions explicit?
8. Are default and liquidation triggers reproducible?
9. Are refinancing lien priorities safe?
10. Are lender-position transfers non-duplicative?
11. Are cross-chain failure states recoverable?
12. Are fiat and card reversals represented correctly?
13. Are insurance and guarantee claims funded or enforceable?
14. Are all material transitions auditable?
15. Can emergency controls preserve repayment rights?

---

# Part XXV — Required Subordinate Specifications

## 52. Documents that must follow

This specification requires the following subordinate artifacts:

1. `UNIFIED_STATE_TRANSITION_CATALOG.md`
2. `Unified_Financial_Accounting_Specification_v0.1.md`
3. `POLICY_INTERFACE_SPEC.md`
4. `SMART_CONTRACT_INTERFACE_SPEC.md`
5. `ONCHAIN_OFFCHAIN_DATA_MODEL.md`
6. `CROSS_CHAIN_PROTOCOL_SPEC.md`
7. `PAYMENT_AND_SETTLEMENT_SPEC.md`
8. `COLLATERAL_AND_LIQUIDATION_SPEC.md`
9. `UNDERWRITING_AND_IDENTITY_SPEC.md`
10. `LENDER_POSITION_AND_SECONDARY_MARKET_SPEC.md`
11. `REFINANCING_AND_RESTRUCTURING_SPEC.md`
12. `INSURANCE_AND_LOSS_WATERFALL_SPEC.md`
13. `PROTOCOL_INVARIANT_TEST_PLAN.md`

---

# Appendix A — Canonical State Summary

```text
Marketplace: DRAFT | OPEN | PAUSED | NEGOTIATING | COMMITMENT_PENDING | FULFILLED | CANCELLED | EXPIRED
Underwriting: NOT_REQUIRED | REQUESTED | DATA_PENDING | IN_REVIEW | MORE_INFORMATION_REQUIRED | APPROVED | APPROVED_WITH_CONDITIONS | DECLINED | EXPIRED | WITHDRAWN
Funding: NOT_OPEN | OPEN | PARTIALLY_COMMITTED | FULLY_COMMITTED | OVERCOMMITTED | ESCROW_PENDING | ESCROWED | DISBURSEMENT_READY | DISBURSED | FAILED | CANCELLED | EXPIRED
Origination: PROPOSED | VALIDATING | APPROVED | ASSET_LOCK_PENDING | READY_TO_ACTIVATE | ACTIVATING | ACTIVE | ACTIVATION_FAILED
Servicing: NOT_STARTED | CURRENT | GRACE | DELINQUENT | CURED | RESTRUCTURING | REFINANCING | ACCELERATED | DEFAULTED | REPAID | SETTLED
Collateral: PROPOSED | VALUATION_PENDING | APPROVED | DEPOSIT_PENDING | LOCKED | HEALTHY | WARNING | MARGIN_CALL | TOP_UP_PENDING | PARTIAL_RELEASE_ELIGIBLE | LIQUIDATION_ELIGIBLE | LIQUIDATING | RELEASED | CLAIMED
Payment: CREATED | AUTHORIZED | SUBMITTED | PENDING | PROVISIONAL | FINAL | FAILED | CANCELLED | REVERSED | DISPUTED
Settlement: NOT_INITIATED | INSTRUCTION_CREATED | PROCESSING | PROVISIONAL | FINAL | FAILED | REVERSED | DISPUTED | RECOVERY_PENDING
Default: NO_DEFAULT | DEFAULT_CANDIDATE | DEFAULT_CONFIRMED | CURED | RESTRUCTURING | LIQUIDATION | INSURANCE_CLAIM | RECOVERY | SETTLED
Liquidation: NOT_ELIGIBLE | ELIGIBLE | INITIATED | PARTIAL_LIQUIDATION | AUCTION_ACTIVE | DIRECT_SALE | LENDER_CLAIM_PENDING | PAUSED | FAILED | COMPLETED
Refinance: NOT_REQUESTED | REQUESTED | QUOTE_PENDING | OFFERED | ACCEPTED | REJECTED | EXPIRED | CANCELLED | FUNDING_PENDING | PAYOFF_PENDING | COLLATERAL_TRANSFER_PENDING | COMPLETED
Restructure: NOT_REQUESTED | REQUESTED | NEGOTIATING | VOTING_OR_APPROVAL | APPROVED | REJECTED | EXPIRED | WITHDRAWN | EXECUTING | EFFECTIVE
Transfer: PENDING_ISSUANCE | ACTIVE | LISTED | TRANSFER_PENDING | TRANSFERRED | PLEDGED | FROZEN | REDEEMED | EXTINGUISHED
CrossChain: LOCAL_ONLY | PREPARING | SOURCE_LOCK_PENDING | SOURCE_LOCKED | MESSAGE_SENT | MESSAGE_VERIFIED | DESTINATION_EXECUTION_PENDING | DESTINATION_EXECUTED | FAILED | EXPIRED | RECOVERY_PENDING
Closure: OPEN | CLOSURE_PENDING | CLOSED | REOPENED_FOR_DISPUTE_ONLY | ARCHIVED
```

---

# Appendix B — Definition of Done

The Universal Loan Model is implementation-ready only when:

- Every state has one owner.
- Every transition has an actor and authorization rule.
- Every asset movement has an accounting consequence.
- Every external action has a finality rule.
- Every failure has a recovery path.
- Every policy reference is versioned.
- Every active agreement has an immutable snapshot.
- Every transition emits an auditable event.
- Every terminal state is protected from unauthorized reopening.
- Every constitutional invariant is represented in tests.

---

**End of Universal Loan Model and State Machine Specification v0.1**
