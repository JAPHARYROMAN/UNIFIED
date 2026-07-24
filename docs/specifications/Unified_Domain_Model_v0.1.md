# Unified Domain Model

**Document:** Unified Domain Model  
**Version:** 0.1 — Foundational Draft  
**Status:** Architecture baseline for review  
**Authority:** Subordinate to the Unified Constitution v0.1  
**Applies to:** Smart contracts, backend services, data stores, indexers, applications, analytics, governance, UFT, integrations, and testing

---

## 1. Purpose

This document defines the canonical business and protocol entities of Unified, the relationships among them, their ownership boundaries, lifecycle responsibilities, event contracts, privacy classifications, and on-chain/off-chain representations.

Its purpose is to ensure that every implementation team uses the same language and does not create competing definitions for concepts such as a user, tender, offer, loan, payment, collateral position, lender position, governance lock, settlement, or default.

The Domain Model does not prescribe all implementation details. It establishes the semantic contract that implementations must preserve.

---

## 2. Governing Principles

The model follows these constitutional rules:

1. Every financial obligation and asset position has one canonical source of truth.
2. Active loan economics cannot be changed retroactively.
3. Complex products use coordinated state machines.
4. External settlement is represented as provisional until finality is established.
5. Sensitive personal and credit data remains off-chain or cryptographically protected.
6. UFT cannot be counted twice for the same economic or governance purpose.
7. Every policy, model, adapter, and agreement is explicitly versioned.
8. Every material state transition emits an auditable event.
9. Cached and indexed data never overrides canonical protocol state.
10. Rights over assets arise only from explicit ownership, authorization, or contractual rules.

---

# Part I — Universal Modeling Language

## 3. Entity Categories

Unified entities are grouped into ten domains:

1. **Party and Identity** — users, organizations, accounts, credentials, profiles, and delegates.
2. **Marketplace and Negotiation** — tenders, offers, counteroffers, conversations, and commitments.
3. **Credit and Underwriting** — applications, attestations, models, decisions, limits, guarantees, and reputation.
4. **Loan and Policy** — universal loans, policy sets, amendments, schedules, and obligations.
5. **Funding and Positions** — funding rounds, commitments, syndicates, tranches, and lender positions.
6. **Collateral, Risk, and Recovery** — collateral, valuations, margin calls, liquidations, defaults, recoveries, and insurance.
7. **Payments and Settlement** — payment instructions, transfers, allocations, fiat/card settlement, reconciliation, and disputes.
8. **UFT and Protocol Economics** — token balances, vesting, staking, rewards, fee routing, burns, liquidity, and reserves.
9. **Governance and Administration** — proposals, votes, timelocks, roles, policy approvals, and emergency actions.
10. **Cross-Chain and Infrastructure** — chain registrations, messages, bridge escrows, wrapped assets, adapters, and indexed projections.

## 4. Canonical Identifier Rules

Every canonical entity shall have:

- A globally unique identifier.
- An entity type.
- A schema version.
- A creation timestamp or block reference.
- A canonical authority.
- A lifecycle status.
- A deterministic event history.

Recommended identifier pattern:

```text
<domain-prefix>_<network-or-tenant>_<128-bit-or-256-bit-id>
```

Examples:

```text
usr_eip155-1_01J...
loan_eip155-1_0x8af...
pay_global_01J...
prop_eip155-1_42
```

On-chain entities may use `bytes32`, contract addresses, token IDs, or deterministic hashes. Off-chain systems must preserve the on-chain identifier rather than inventing an unrelated replacement.

## 5. Authority Classes

Each entity declares one canonical authority:

| Authority | Meaning |
|---|---|
| `ONCHAIN_HOME` | Canonical state is held by a smart contract on the loan or protocol home chain. |
| `ONCHAIN_SATELLITE` | Canonical local custody or execution state is held on a satellite chain, while global state is coordinated elsewhere. |
| `SIGNED_OFFCHAIN` | Canonical content is an immutable signed payload, later consumed on-chain or by an authorized service. |
| `REGULATED_PROVIDER` | Canonical external settlement or identity fact is held by an approved provider and represented through attestations. |
| `UNIFIED_LEDGER` | Canonical state is held in Unified's controlled double-entry ledger because no public-chain representation is practical. |
| `USER_CONTROLLED` | Canonical content is held and signed by the user, with only references or commitments stored by Unified. |
| `DERIVED` | The entity is a projection calculated from canonical sources and cannot independently change rights. |

## 6. Privacy Classes

| Class | Meaning |
|---|---|
| `PUBLIC` | Safe and intended for public disclosure. |
| `PSEUDONYMOUS_PUBLIC` | Publicly visible but associated with wallet or pseudonymous identifiers. |
| `CONFIDENTIAL` | Available only to authorized parties and services. |
| `RESTRICTED_IDENTITY` | Personal identity data subject to strict access and retention rules. |
| `RESTRICTED_FINANCIAL` | Bank, card, income, credit, or transaction data requiring strict controls. |
| `SECRET` | Cryptographic secrets, recovery material, or credentials that Unified should normally never possess. |
| `ZERO_KNOWLEDGE_ONLY` | Raw fact is not stored; only a proof or commitment is accepted. |

---

# Part II — Party and Identity Domain

## 7. Party

A `Party` is any natural person, legal entity, decentralized organization, protocol pool, or system actor capable of holding rights or obligations.

### Core fields

```text
party_id
party_type: PERSON | ORGANIZATION | DAO | POOL | PROTOCOL | PROVIDER
status: ACTIVE | RESTRICTED | SUSPENDED | CLOSED
primary_account_id
jurisdiction_claims[]
created_at
schema_version
```

### Relationships

- A Party owns one or more Accounts.
- A Party may hold multiple Profiles.
- A Party may possess multiple Identity Credentials.
- A Party may act as borrower, lender, guarantor, liquidator, liquidity provider, governance participant, service provider, or delegate.

### Canonical authority

`UNIFIED_LEDGER` for the party record; ownership is proven through account authorization and identity attestations.

### Privacy

`CONFIDENTIAL`; pseudonymous identifiers may be public.

### Invariants

- A Party record does not itself custody assets.
- A Party cannot be merged or split without preserving historical obligations.
- Restricting a Party cannot erase its repayment rights or existing obligations.

## 8. Account

An `Account` is an authorization and ownership endpoint used by a Party.

### Account types

```text
EOA_WALLET
SMART_ACCOUNT
MULTISIG
CUSTODIAL_WALLET
BANK_ACCOUNT_REFERENCE
CARD_PAYMENT_PROFILE
INTERNAL_SETTLEMENT_ACCOUNT
DAO_TREASURY
PROTOCOL_VAULT
```

### Core fields

```text
account_id
party_id
account_type
network_id or provider_id
public_identifier or tokenized_reference
authorization_policy_id
status
valid_from
valid_until
```

### Invariants

- Raw private keys and full card credentials are never domain fields.
- Bank and card accounts are represented by provider tokens or references.
- Account ownership changes require a versioned authorization event.
- A smart account may define multiple signers, guardians, or session keys.

## 9. Authorization Policy

Defines who may act for an Account or Party.

### Supported modes

- Single signature.
- Multisignature threshold.
- Role-based organization approval.
- Session key with bounded permissions.
- Delegated transaction authority.
- Social or guardian recovery.
- Regulated custodian authorization.

### Invariants

- Authorization policies cannot retroactively validate past unauthorized actions.
- Session keys must define expiry, spending limits, and callable functions.
- Recovery cannot transfer active obligations without preserving liability.

## 10. Identity Credential

A signed or zero-knowledge assertion about a Party.

### Examples

- KYC verified.
- Legal entity verified.
- Age threshold satisfied.
- Permitted jurisdiction.
- Accredited or professional investor status.
- Unique-human credential.
- Income band.
- Business registration.
- Sanctions screening result.

### Core fields

```text
credential_id
subject_commitment
credential_type
issuer_id
claims_hash
assurance_level
issued_at
expires_at
revocation_reference
privacy_mode
signature_or_proof
```

### Authority

`REGULATED_PROVIDER`, `SIGNED_OFFCHAIN`, or `ZERO_KNOWLEDGE_ONLY`.

### Invariants

- Personally identifiable source data must not be placed on a public chain.
- Contracts consume only the minimum required claim.
- Expired or revoked credentials cannot authorize new actions.
- Revocation must not invalidate already completed transactions unless the agreement expressly provides otherwise.

## 11. Borrower Profile

A derived and user-controlled presentation of borrowing history, preferences, and eligibility.

### Fields

```text
party_id
public_alias
supported_identity_modes
preferred_assets
preferred_term_range
public_reputation_summary
verified_credentials_summary
active_exposure_summary
profile_metadata_uri
```

### Authority

Mixed: user-controlled metadata plus derived protocol facts.

### Invariants

- Public claims must identify whether they are user-asserted or verified.
- Reputation values must link to their calculation policy version.

## 12. Lender Profile

Represents lending preferences and public history.

### Fields

```text
party_id
preferred_assets
preferred_credit_classes
preferred_collateral
minimum_yield
term_preferences
available_commitment_range
public_portfolio_summary
verified_credentials_summary
```

The profile is not a legally binding commitment to lend.

## 13. Delegate

A Party authorized to perform bounded actions for another Party.

Examples include loan servicers, portfolio managers, corporate officers, recovery agents, and governance delegates.

### Invariants

- Delegation must identify scope, duration, revocation, and spending authority.
- A delegate cannot grant itself broader authority.
- Revocation affects future actions, not already-finalized actions.

---

# Part III — Marketplace and Negotiation Domain

## 14. Loan Tender

A `LoanTender` is a borrower-originated request for financing. It is not itself a loan or promise to borrow.

### Core fields

```text
tender_id
borrower_party_id
borrower_account_id
requested_principal_asset_or_currency
requested_amount or range
purpose_classification
requested_duration or range
preferred_interest_constraints
repayment_preferences
proposed_collateral_set_id
identity_policy_requirement
credit_policy_preference
funding_policy_preference
settlement_preferences
transferability_preferences
metadata_hash
disclosure_package_id
publication_scope
open_at
expires_at
status
version
```

### States

```text
DRAFT → PUBLISHED → NEGOTIATING → COMMITTED → FULFILLED
                    ↘ EXPIRED
                    ↘ CANCELLED
```

### Authority

Signed by the borrower; optionally anchored on-chain.

### Events

```text
TenderDrafted
TenderPublished
TenderAmended
TenderCancelled
TenderExpired
TenderCommitted
TenderFulfilled
```

### Invariants

- A tender cannot be fulfilled more than once unless it explicitly permits multiple independent facilities.
- Material amendments create a new version and invalidate incompatible offers.
- Publishing a tender does not transfer assets.

## 15. Disclosure Package

A versioned bundle of information supplied to prospective lenders.

May include:

- Purpose and use of funds.
- Financial statements.
- Collateral descriptions.
- Identity attestations.
- Credit credentials.
- Cash-flow evidence.
- Risk disclosures.
- Legal documents.

### Privacy

Usually `CONFIDENTIAL` or `RESTRICTED_FINANCIAL`.

### Invariants

- Access is auditable.
- Every offer records the disclosure-package version used.
- Later edits cannot silently alter the information relied upon by a signed offer.

## 16. Conversation

An encrypted communication channel associated with a tender, offer, loan, dispute, or support process.

### Core fields

```text
conversation_id
context_type
context_id
participants[]
encryption_scheme
key_references
retention_policy
status
```

Messages are not binding loan terms unless converted into a structured signed agreement.

## 17. Offer

A structured proposal by one or more funding parties.

### Core fields

```text
offer_id
tender_id
offeror_party_ids[]
borrower_party_id
principal_terms
funding_terms
interest_policy_config
repayment_policy_config
collateral_policy_config
settlement_policy_config
liquidation_policy_config
transfer_policy_config
refinancing_policy_config
insurance_policy_config
required_credentials[]
disclosure_package_version
valid_from
expires_at
nonce
chain_domain
protocol_version
offer_hash
signatures[]
status
```

### States

```text
DRAFT → SIGNED → SUBMITTED → ACCEPTED → CONSUMED
                     ↘ COUNTERED
                     ↘ WITHDRAWN
                     ↘ EXPIRED
                     ↘ REJECTED
```

### Invariants

- An accepted offer is consumed exactly once.
- Signatures are bound to chain, protocol, borrower, tender, nonce, and terms hash.
- An offer cannot be edited after signing; changes create a new version.

## 18. Counteroffer

A new Offer linked to a prior Offer through `supersedes_offer_id` and `negotiation_thread_id`.

A counteroffer does not mutate the original offer.

## 19. Reservation or Commitment Letter

An optional signed promise to reserve funding or proceed to closing subject to conditions.

It defines:

- Reserved amount.
- Expiration.
- Conditions precedent.
- Commitment fee.
- Refundability.
- Exclusivity.

It is distinct from a funded loan.

---

# Part IV — Credit and Underwriting Domain

## 20. Credit Application

A request by a borrower for a credit decision.

### Fields

```text
application_id
borrower_party_id
tender_id or requested_product
requested_exposure
requested_duration
data_consents[]
credential_references[]
submitted_data_hash
submitted_at
status
```

### States

```text
DRAFT → SUBMITTED → DATA_PENDING → ASSESSING → DECIDED
                                      ↘ MANUAL_REVIEW
                                      ↘ WITHDRAWN
```

## 21. Credit Data Consent

A revocable permission to obtain or process a specified data category.

### Invariants

- Consent identifies purpose, provider, fields, retention, and expiry.
- Revocation prevents future collection but does not erase immutable evidence required for an active agreement.

## 22. Underwriting Policy

A versioned decision framework defining eligibility, pricing, exposure, and review requirements.

### Fields

```text
policy_id
policy_version
applicable_products
required_features_or_credentials
rule_set_hash
model_ids[]
manual_review_rules
adverse_action_codes[]
valid_from
valid_until
status
```

## 23. Credit Model

A registered statistical, machine-learning, rules-based, or cryptographic model.

### Fields

```text
model_id
model_version
model_type
owner_or_attester
training_data_summary
feature_schema_version
validation_report_hash
performance_thresholds
bias_and_fairness_report_hash
explanation_method
approved_uses
prohibited_uses
deployed_at
retired_at
```

The model artifact may remain private, but its identity, version, approval, and output meaning must be auditable.

## 24. Credit Decision

A signed outcome of underwriting.

### Fields

```text
decision_id
application_id
borrower_commitment
policy_id and version
model_ids and versions
decision: APPROVE | DECLINE | REFER | CONDITIONAL
risk_grade
maximum_exposure
maximum_duration
pricing_band
required_collateral
required_guarantee
conditions[]
reason_codes[]
issued_at
expires_at
attester_signature
```

### Invariants

- A decision applies only to the identified subject, scope, and validity period.
- A decline or adverse change has explainable reason codes.
- A credit decision authorizes a product configuration; it does not transfer funds.

## 25. Credit Facility

A reusable approved limit from which one or more loans or drawdowns may be created.

### Fields

```text
facility_id
borrower_party_id
approved_limit
currency_or_asset
available_limit
utilized_limit
expiry
revolving_flag
credit_policy_id
covenants[]
status
```

### Invariants

- `available_limit + utilized_limit + reserved_limit = approved_limit`, adjusted only by authorized changes.
- Drawdowns cannot exceed available limit.

## 26. Guarantee

A third-party promise to absorb defined losses or repay defined obligations.

### Types

- Personal guarantee.
- Corporate guarantee.
- On-chain staked guarantee.
- Insurance-backed guarantee.
- Community or delegated-credit guarantee.

### Fields

```text
guarantee_id
guarantor_party_id
beneficiary_scope
covered_obligation
coverage_limit
coverage_percentage
trigger_conditions
recovery_rights
security_or_stake_reference
expiry
status
```

## 27. Reputation Record

An immutable event used to calculate reputation.

Examples:

- Loan repaid on time.
- Installment late.
- Default.
- Successful guarantee.
- Fraud determination.
- Governance participation.

A `ReputationScore` is derived from records under a named policy version.

---

# Part V — Universal Loan and Policy Domain

## 28. Universal Loan

A `Loan` is the canonical financial agreement and obligation container.

### Core fields

```text
loan_id
home_chain_id
loan_account_or_contract
borrower_party_ids[]
borrower_account_ids[]
originating_tender_id
accepted_offer_id
credit_decision_ids[]
principal_definition
policy_set_id
funding_structure_id
collateral_set_id
settlement_configuration_id
insurance_configuration_id
origination_timestamp
commencement_timestamp
maturity_timestamp
contractual_currency
accounting_precision
status_domains
metadata_hash
protocol_version
```

### Independent state domains

```text
origination_state
servicing_state
collateral_state
settlement_state
cross_chain_state
position_state
dispute_state
```

### Canonical authority

Normally `ONCHAIN_HOME`. Hybrid fiat loans may use a split authority with the contractual obligation on-chain and external money movement attested through `REGULATED_PROVIDER` plus `UNIFIED_LEDGER`.

### Invariants

- A loan has one canonical home authority.
- Active economic terms reference immutable policy versions and configuration hashes.
- The obligation cannot be duplicated through a bridge, refinance, or secondary transfer.
- Borrower and lender rights are represented separately from application views.

## 29. Loan Policy Set

An immutable manifest of policy implementations and configuration hashes selected for a loan.

```text
policy_set_id
identity_policy_ref
credit_policy_ref
funding_policy_ref
collateral_policy_ref
interest_policy_ref
repayment_policy_ref
settlement_policy_ref
liquidation_policy_ref
transfer_policy_ref
refinancing_policy_ref
cross_chain_policy_ref
insurance_policy_ref
amendment_policy_ref
dispute_policy_ref
```

### Invariants

- Every reference includes implementation identity and version.
- Governance may deprecate a policy for new loans without changing active loans.
- Policies cannot invoke unapproved arbitrary code.

## 30. Principal Definition

Defines what the borrower receives and owes.

### Modes

- On-chain token amount.
- Native-chain asset.
- Fiat currency amount.
- Basket or indexed amount.
- Credit line with drawdowns.

### Fields

```text
asset_or_currency_id
committed_amount
disbursed_amount
cancelled_amount
capitalized_amount
accounting_unit
conversion_policy
```

## 31. Obligation Component

A separately accounted amount owed under a loan.

### Types

```text
PRINCIPAL
ACCRUED_INTEREST
CAPITALIZED_INTEREST
CURRENT_FEE
LATE_FEE
RECOVERABLE_COST
PENALTY
TAX
INSURANCE_PREMIUM
OTHER_DISCLOSED
```

Each component has:

```text
component_id
calculation_policy
accrued_amount
paid_amount
waived_amount
written_off_amount
outstanding_amount
priority
```

## 32. Interest Policy

Defines interest accrual.

### Modes

- Fixed.
- Variable benchmark plus spread.
- Utilization-based.
- Hybrid.
- Revenue-based.
- Zero interest with fees.

### Required fields

```text
day_count_convention
compounding_rule
rate_source
rate_floor
rate_cap
spread
reset_frequency
stale_rate_behavior
rounding_rule
accrual_start
non_business_day_rule
```

## 33. Repayment Schedule

Defines contractual payment events.

### Fields

```text
schedule_id
loan_id
schedule_type
installments[]
payment_waterfall_id
prepayment_policy_id
holiday_policy_id
final_maturity
version
```

### Schedule types

- Bullet.
- Equal principal.
- Annuity.
- Interest-only.
- Balloon.
- Seasonal.
- Revenue-based.
- Custom irregular.

## 34. Installment

```text
installment_id
schedule_id
due_date
principal_due
interest_due
fees_due
total_due
paid_amount
status
grace_end
```

States:

```text
SCHEDULED → DUE → PARTIALLY_PAID → PAID
                 ↘ OVERDUE
                 ↘ WAIVED
                 ↘ RESTRUCTURED
```

## 35. Payment Waterfall

An immutable ordered allocation rule.

Example:

```text
1. Recoverable external settlement costs
2. Penalties and late fees
3. Overdue interest
4. Current interest
5. Principal
6. Insurance or reserve contribution
7. Refundable excess
```

The exact waterfall must be visible before loan activation.

## 36. Loan Amendment

A signed change allowed by the original Amendment Policy.

### Types

- Maturity extension.
- Rate modification.
- Payment holiday.
- Schedule restructuring.
- Covenant waiver.
- Collateral substitution.
- Party substitution where permitted.

### Fields

```text
amendment_id
loan_id
proposed_changes_hash
required_approvals
received_approvals
voting_class_results
proposed_at
effective_at
status
```

### Invariants

- An amendment cannot bypass required parties or classes.
- Historical terms remain auditable.
- An amendment is not effective before all conditions are satisfied.

---

# Part VI — Funding and Lender Position Domain

## 37. Funding Structure

Defines how principal is supplied.

### Modes

- Single lender.
- Closed syndicate.
- Open funding round.
- Pooled lending.
- Tranche-based structured loan.
- Hybrid on-chain/off-chain funding.

## 38. Funding Round

```text
funding_round_id
tender_or_loan_id
target_amount
minimum_close_amount
maximum_amount
open_at
close_at
allocation_rule
oversubscription_rule
refund_rule
status
```

States:

```text
SCHEDULED → OPEN → SOFT_COMMITTED → FUNDED → CLOSED
                    ↘ FAILED
                    ↘ CANCELLED
```

## 39. Funding Commitment

A lender's reserved or deposited contribution.

```text
commitment_id
funding_round_id
lender_party_id
funding_account_id
amount
asset
tranche_id
commitment_type
funded_amount
refundable_amount
status
signature_or_transaction
```

### Invariants

- The same funds cannot back two simultaneous irrevocable commitments.
- Refund rights are determined by the funding policy.

## 40. Syndicate

A group of lenders sharing an obligation under defined coordination rules.

```text
syndicate_id
loan_id
members[]
agent_or_coordinator
voting_policy
repayment_distribution_policy
recovery_policy
transfer_policy
```

## 41. Tranche

A priority class within a loan.

```text
tranche_id
loan_id
name
seniority_rank
target_size
funded_size
interest_entitlement
loss_absorption_rule
repayment_priority
voting_class
transfer_constraints
```

### Invariants

- Tranche waterfalls are deterministic.
- Seniority cannot change after activation except through an authorized amendment.
- Losses cannot skip a class contrary to the contractual waterfall.

## 42. Lender Position

A canonical economic claim to loan cash flows and recoveries.

```text
position_id
loan_id
owner_party_id
owner_account_id
tranche_id
principal_share
income_share
recovery_share
voting_rights
transfer_policy_id
acquired_at
cost_basis_reference
status
```

### Representation

May be a non-transferable ledger position, ERC-721 position token, ERC-1155 fractional position, or fungible tranche token.

### Invariants

- Aggregate position shares equal the loan's issued lender rights.
- Transfer changes ownership, not total debt.
- A seller cannot receive cash flows after final settlement of a transfer unless accrued entitlements were reserved.

## 43. Position Listing

A secondary-market offer to sell or transfer a Lender Position.

```text
listing_id
position_id
seller
quantity_or_fraction
price_terms
settlement_asset
buyer_eligibility_policy
expires_at
status
```

## 44. Position Transfer

An atomic or escrowed change of position ownership.

It records:

- Seller.
- Buyer.
- Consideration.
- Accrued-interest cut-off.
- Compliance checks.
- Settlement finality.
- New beneficiary rights.

---

# Part VII — Collateral, Risk, Default, and Recovery Domain

## 45. Collateral Set

A collection of assets securing one or more obligations.

```text
collateral_set_id
loan_id
assets[]
priority_and_cross_collateralization_rules
valuation_policy_id
custody_policy_id
release_policy_id
status
```

## 46. Collateral Position

A specific pledged asset or asset quantity.

### Supported asset classes

- Native tokens.
- ERC-20 or equivalent fungible assets.
- ERC-721 NFTs.
- ERC-1155 assets.
- LP positions.
- Tokenized real-world assets.
- Off-chain collateral represented by custodian attestation.
- UFT and sUFT under approved policies.

### Fields

```text
collateral_position_id
collateral_set_id
owner_party_id
asset_id
quantity_or_token_ids
custody_location
lien_rank
valuation_adapter_id
initial_value
current_value
haircut
eligible_value
status
```

### States

```text
PROPOSED → PENDING_TRANSFER → LOCKED → RELEASE_PENDING → RELEASED
                                  ↘ MARGIN_CALL
                                  ↘ LIQUIDATING → LIQUIDATED
                                  ↘ CLAIMED
```

### Invariants

- Locked collateral cannot be withdrawn outside its release or liquidation policy.
- A single asset cannot support conflicting first-priority claims unless cross-collateralization is explicit.
- Collateralized UFT does not retain independent voting rights.

## 47. Valuation Observation

An immutable record of asset valuation used for a material decision.

```text
observation_id
asset_id
price
quote_currency
source_ids[]
observed_at
valid_until
liquidity_measure
confidence_or_deviation
normalized_decimals
policy_id
```

## 48. Loan Health Snapshot

A derived but auditable assessment.

```text
health_snapshot_id
loan_id
outstanding_debt
eligible_collateral_value
health_factor
thresholds
valuation_observation_ids[]
calculated_at
policy_version
```

## 49. Margin Call

A formal requirement to cure collateral deficiency.

```text
margin_call_id
loan_id
trigger_snapshot_id
required_cure_amount
permitted_actions
issued_at
cure_deadline
status
```

## 50. Default Event

A determination that a contractual default condition has occurred.

### Types

- Payment default.
- Maturity default.
- Collateral default.
- Covenant default.
- Fraud or representation default.
- Cross-chain settlement failure.
- Insolvency event where contractually recognized.

### Fields

```text
default_id
loan_id
default_type
trigger_policy_id
evidence_references[]
triggered_at
cure_deadline
declared_by
dispute_window
status
```

### Invariants

- Default must be reproducible from contractual rules and evidence.
- A default declaration does not itself authorize arbitrary asset seizure.

## 51. Liquidation Case

Coordinates liquidation of collateral.

```text
liquidation_id
loan_id
collateral_positions[]
liquidation_policy_id
trigger_snapshot_id
route: DIRECT_SWAP | PARTIAL | DUTCH_AUCTION | ENGLISH_AUCTION | LENDER_CLAIM | NFT_AUCTION
minimum_proceeds
started_at
completed_at
status
```

## 52. Auction

```text
auction_id
liquidation_id
asset_lot
auction_type
reserve_or_start_price
price_curve_or_bid_rules
start_at
end_at
winning_bid
settlement_state
```

## 53. Recovery Case

Tracks post-default collection and proceeds.

```text
recovery_case_id
loan_id
responsible_agent
available_claims[]
recovered_amounts[]
costs[]
distribution_waterfall
status
```

## 54. Write-Off

An accounting recognition that an amount is unlikely to be recovered. It does not erase legal or contractual recovery rights unless explicitly released.

## 55. Insurance Policy

A defined protection arrangement covering specified loss events.

```text
insurance_policy_id
provider_or_pool
covered_product
coverage_limit
coverage_percentage
deductible
premium_policy
covered_events
exclusions
claim_process
capital_source
status
```

## 56. Insurance Claim

```text
claim_id
policy_id
loan_id
claimant
loss_event
claimed_amount
approved_amount
paid_amount
evidence[]
status
```

### Invariants

- No claim may be represented as guaranteed beyond funded or contractually committed capacity.
- Claim approval and payment are separate states.

---

# Part VIII — Payment, Settlement, and Accounting Domain

## 57. Payment Instruction

A request to move value toward an obligation or recipient.

```text
payment_instruction_id
payer_party_id
payer_account_id
payee_or_loan_id
asset_or_currency
amount
payment_method
allocation_intent
provider_or_chain
expires_at
status
```

## 58. Payment

A canonical record of attempted or completed value transfer.

### States

```text
CREATED → AUTHORIZED → PROCESSING → PROVISIONAL → FINAL
                               ↘ FAILED
                               ↘ REVERSED
                               ↘ DISPUTED
                               ↘ REFUNDED
```

### Fields

```text
payment_id
instruction_id
external_reference_or_tx_hash
gross_amount
fees
net_amount
asset_or_currency
initiated_at
provisional_at
finalized_at
reversal_deadline
status
```

### Invariants

- Authorization is not settlement.
- Provisional card or fiat payments cannot release collateral unless the settlement policy explicitly covers reversal risk.
- Duplicate provider callbacks must be idempotent.

## 59. Payment Allocation

Applies a final or policy-eligible payment to obligation components.

```text
allocation_id
payment_id
loan_id
waterfall_id
allocations[]
allocated_at
reversal_policy
```

## 60. Disbursement

A transfer of loan principal or drawdown to a borrower.

It records gross principal, fees deducted, net proceeds, provider costs, and finality.

## 61. Settlement

The final transfer of legal and economic value under a defined settlement policy.

### Settlement types

- Same-chain.
- Cross-chain.
- Bank.
- Card.
- Cash-equivalent provider.
- Atomic delivery-versus-payment.
- Escrowed hybrid.

## 62. Fiat Settlement

A regulated-provider transaction linked to Unified.

```text
fiat_settlement_id
provider_id
provider_reference
currency
gross_amount
fees
net_amount
source_account_token
destination_account_token
bank_status
unified_status
settlement_date
reversal_status
```

## 63. Card Settlement

Records authorization, capture, processor settlement, chargeback window, reserve, and finality.

Raw card data is never stored.

## 64. Reconciliation Record

Matches external provider or chain events to Unified ledger entries.

```text
reconciliation_id
source
statement_period
external_entry_reference
internal_entry_ids[]
matched_amount
difference
status
reviewed_by
```

## 65. Ledger Account

A double-entry accounting account.

### Classes

- Asset.
- Liability.
- Equity/reserve.
- Revenue.
- Expense.
- Contra account.
- Memorandum exposure account.

## 66. Journal Entry

```text
journal_entry_id
business_event_id
accounting_date
currency_or_asset
lines[]
status
created_at
reversal_of
```

### Invariants

- Total debits equal total credits for each accounting unit.
- Posted entries are immutable; corrections use reversing entries.
- On-chain and external settlement references are preserved.

## 67. Dispute

A formal challenge concerning payment, settlement, loan servicing, liquidation, identity, or governance execution.

A dispute does not automatically reverse final on-chain state unless the original policy provides a remedy.

---

# Part IX — Refinancing and Restructuring Domain

## 68. Payoff Quote

A time-limited statement of the amount required to settle a loan.

```text
payoff_quote_id
loan_id
principal
interest
fees
penalties
credits
net_payoff_amount
valid_until
settlement_instructions
```

## 69. Refinance Request

A proposal to replace or modify an existing obligation using new financing.

```text
refinance_request_id
existing_loan_id
new_tender_or_offer_id
requested_changes
collateral_transfer_plan
payoff_quote_id
status
```

## 70. Refinance Transaction

Coordinates settlement of the old loan and activation of the new loan.

### Invariants

- The old debt is settled or legally subordinated before the new senior claim becomes final.
- Collateral cannot become simultaneously subject to conflicting first liens.
- Partial failure enters a recoverable escrow state.

## 71. Restructuring Plan

An amendment package created in response to borrower distress or changed conditions.

It may include maturity extension, fee waiver, interest capitalization, payment holiday, collateral addition, or lender haircut.

---

# Part X — UFT and Protocol Economics Domain

## 72. UFT Token

The canonical fixed-cap Unified ecosystem token.

### Canonical properties

```text
name: Unified Coin
symbol: UFT
standard: fungible token
max_supply: configured at genesis
post_genesis_minting: prohibited
burning: permitted only from controlled balances
```

### Invariants

- Total canonical supply never exceeds genesis maximum.
- No governance or administrator may create a mint authority.
- UFT is not represented as price-stable or guaranteed to appreciate.

## 73. Token Allocation

A genesis allocation to a named purpose.

```text
allocation_id
category
allocated_amount
vault_id
vesting_policy_id
spending_policy_id
distributed_amount
remaining_amount
```

## 74. Vesting Schedule

```text
vesting_id
beneficiary
allocation_id
cliff
start
end
release_curve
revocation_policy
released_amount
```

## 75. UFT Stake Position

Represents UFT deposited into a protocol-security staking vault.

```text
stake_position_id
owner
underlying_uft
sUFT_shares
entry_exchange_rate
cooldown_state
slash_exposure
reward_debt
status
```

### Invariants

- Shares are backed by accounted vault assets.
- Rewards cannot exceed funded resources.
- Slashing occurs only under a predefined policy and covered event.

## 76. Governance Lock

A lock of UFT or approved stake shares producing non-transferable voting power.

```text
governance_lock_id
owner
underlying_asset
locked_amount
start
end
voting_power_formula
veUFT_amount
delegate
status
```

### Invariants

- Governance power is checkpointed.
- The same underlying UFT cannot vote through multiple representations.
- Collateralized UFT cannot be independently governance-locked.

## 77. Reward Program

A finite, funded incentive campaign.

```text
reward_program_id
purpose
eligible_actions
reward_asset
funded_budget
committed_budget
distributed_budget
start_epoch
end_epoch
calculation_policy
vesting_policy
status
```

## 78. Reward Accrual

A derived entitlement under a Reward Program. It becomes payable only after validation and available funding checks.

## 79. Protocol Fee

A disclosed fee charged by Unified, distinct from third-party processing costs.

```text
fee_id
fee_type
business_event_id
payer
asset
amount
fee_policy_id
collected_at
```

## 80. Fee Distribution

Allocates net protocol revenue among treasury, insurance, staking, liquidity, and burning.

### Invariants

- Distribution percentages total 100%.
- User principal and collateral are not treated as fee revenue.
- Third-party costs are separated from net protocol revenue.

## 81. Burn Event

A permanent destruction of canonical UFT.

```text
burn_id
source
amount
reason
transaction_reference
burned_at
```

Burning wrapped UFT must result in corresponding canonical reconciliation.

## 82. Treasury

A governed collection of protocol-owned assets.

Treasury subaccounts must distinguish:

- Operating funds.
- Insurance reserves.
- Staking rewards.
- Liquidity allocations.
- Grants.
- Tax or legal reserves.
- Protocol-owned liquidity.

Restricted reserves cannot be spent as unrestricted treasury assets.

## 83. Reserve

A segregated pool designated for specific losses or obligations.

```text
reserve_id
reserve_type
funding_sources
covered_events
available_balance
committed_balance
minimum_capital_rule
withdrawal_policy
```

## 84. Liquidity Pool Registration

A protocol-approved market or pool used for exchange, liquidation, or incentives.

It records venue, asset pair, pool contract, oracle eligibility, depth requirements, risk tier, and incentive status.

## 85. Liquidity Position

A Party's interest in a registered pool. It is distinct from UFT staking and lender positions.

---

# Part XI — Governance and Administration Domain

## 86. Governance Proposal

A versioned request to change permitted protocol state.

```text
proposal_id
proposer
proposal_type
metadata_hash
actions[]
constitutional_class
required_quorum
required_threshold
review_period
voting_period
timelock_period
status
```

### States

```text
DRAFT → SUBMITTED → REVIEW → ACTIVE → SUCCEEDED → QUEUED → EXECUTED
                               ↘ DEFEATED
                               ↘ CANCELLED
                               ↘ EXPIRED
```

## 87. Vote

```text
vote_id
proposal_id
voter_or_delegate
snapshot_voting_power
choice
reason_hash
cast_at
```

### Invariants

- Voting power is measured at the proposal snapshot.
- One underlying UFT cannot produce duplicate voting power.

## 88. Timelock Operation

A queued governance action with an earliest execution time and immutable action hash.

## 89. Protocol Role

A bounded permission assigned to an account or governance body.

Examples:

- Governor.
- Timelock executor.
- Risk council.
- Emergency council.
- Oracle registrar.
- Adapter registrar.
- Treasury operator.
- Pauser.

### Invariants

- Roles follow least authority.
- Role changes emit events.
- No role may override constitutional user protections.

## 90. Emergency Action

A temporary bounded intervention responding to a verified threat.

Examples:

- Pause new originations.
- Disable a compromised oracle.
- Disable a bridge adapter.
- Stop a payment provider.
- Disable a liquidation route.

### Required fields

```text
emergency_action_id
trigger
authorized_body
affected_modules
scope
activated_at
expires_at
recovery_plan
status
```

### Invariants

- Emergency action is time-bounded.
- Repayment and safe withdrawal paths remain available where technically possible.
- Emergency powers cannot mint UFT or seize arbitrary user assets.

## 91. Policy Registration

Approves a specific implementation and version for future use.

```text
registration_id
policy_type
implementation_address_or_artifact
version
security_review_hash
approved_from
deprecated_from
status
```

## 92. Adapter Registration

Registers an oracle, bridge, payment, identity, custody, or model provider under defined limits.

---

# Part XII — Cross-Chain Domain

## 93. Chain Registry Entry

Defines a supported chain.

```text
chain_id
chain_type
finality_policy
canonical_rpc_metadata
supported_assets
message_adapters
risk_tier
status
```

## 94. Cross-Chain Message

A uniquely identified instruction or attestation sent between chains.

```text
message_id
source_chain
destination_chain
source_sender
destination_receiver
nonce
loan_or_asset_context
payload_hash
sent_at
verified_at
executed_at
status
```

### States

```text
CREATED → SENT → OBSERVED → VERIFIED → EXECUTED
                    ↘ FAILED
                    ↘ EXPIRED
                    ↘ RECOVERY_PENDING
```

### Invariants

- Each message executes at most once.
- Source and destination domains are bound into the message.
- Message failure cannot duplicate assets or obligations.

## 95. Bridge Escrow

Holds canonical assets backing representations on satellite chains.

```text
bridge_escrow_id
canonical_asset
satellite_chain
locked_amount
minted_wrapped_supply
pending_outbound
pending_inbound
```

### Invariant

```text
minted_wrapped_supply <= canonical_backing_allocated
```

## 96. Wrapped Asset

A satellite representation of a canonical asset, including wUFT.

It identifies canonical chain, canonical contract, bridge adapter, and supply controller.

## 97. Satellite Loan Component

A local-chain component that may hold collateral, receive payment, or execute settlement for a loan whose canonical state is on another chain.

It cannot independently rewrite global loan terms.

---

# Part XIII — Infrastructure and Projection Domain

## 98. Protocol Event

The canonical immutable record of a material state transition.

Every event includes:

```text
event_id
entity_type
entity_id
event_type
schema_version
actor
source_authority
timestamp_or_block
transaction_or_provider_reference
payload_hash
```

## 99. Indexed Projection

A query-optimized representation derived from protocol events and signed off-chain records.

Examples:

- Tender search index.
- User portfolio view.
- Loan dashboard.
- Reputation summary.
- Governance analytics.

### Invariants

- Projection lag and source block are visible.
- A projection cannot settle funds or mutate canonical rights.
- Reorgs and source corrections are handled deterministically.

## 100. Adapter

A versioned boundary to an external system.

### Adapter types

- Oracle.
- Bridge.
- Payment.
- Card.
- Bank.
- Identity.
- Custody.
- Exchange.
- Underwriting model.
- Messaging.

### Required properties

- Version.
- Capabilities.
- Permissions.
- Risk limits.
- Timeout behavior.
- Idempotency rules.
- Failure and recovery procedure.
- Security-review reference.

## 101. Notification

A non-canonical user communication derived from events.

Failure to deliver a notification does not alter contractual deadlines unless the applicable policy explicitly makes delivery a condition.

## 102. Audit Record

An immutable record of privileged access, sensitive data access, administrative action, or reconciliation decision.

---

# Part XIV — Relationship Model

## 103. Core Relationship Graph

```text
Party
 ├── owns → Account
 ├── holds → IdentityCredential
 ├── maintains → BorrowerProfile / LenderProfile
 ├── creates → LoanTender
 ├── signs → Offer
 ├── submits → CreditApplication
 ├── receives → CreditDecision
 ├── commits through → FundingCommitment
 ├── owns → LenderPosition
 ├── pledges → CollateralPosition
 ├── initiates → Payment
 ├── owns → UFTStakePosition
 ├── owns → GovernanceLock
 └── votes on → GovernanceProposal

LoanTender
 ├── references → DisclosurePackage
 ├── receives → Offer
 └── may originate → Loan

Loan
 ├── uses → LoanPolicySet
 ├── contains → ObligationComponents
 ├── uses → RepaymentSchedule
 ├── funded by → FundingStructure
 ├── represented to lenders by → LenderPositions
 ├── secured by → CollateralSet
 ├── receives → Payments
 ├── may enter → DefaultEvent
 ├── may trigger → LiquidationCase
 ├── may produce → RecoveryCase
 ├── may be covered by → InsurancePolicy
 ├── may be replaced by → RefinanceTransaction
 └── emits → ProtocolEvents
```

## 104. Aggregate Boundaries

### Party Aggregate

Owns:

- Party.
- Account references.
- Authorization policies.
- Profiles.
- Delegations.

Does not own:

- Identity-provider source records.
- Loans.
- External settlement records.

### Tender Aggregate

Owns:

- Tender.
- Tender versions.
- Public metadata references.
- Offer associations.

Does not own accepted loan economics after origination.

### Loan Aggregate

Owns:

- Universal Loan.
- Policy-set reference.
- Obligation balances.
- Repayment schedule.
- Contractual state machines.
- Loan-level amendments.

References but does not necessarily custody:

- Collateral positions.
- Funding assets.
- External fiat settlements.
- Insurance reserves.

### Collateral Aggregate

Owns:

- Collateral set.
- Collateral positions.
- Custody and lien state.
- Release and liquidation eligibility.

### Funding Aggregate

Owns:

- Funding round.
- Commitments.
- Syndicate.
- Tranches.
- Issued lender positions.

### Payment Aggregate

Owns:

- Payment instruction.
- Payment lifecycle.
- Provider or chain references.
- Finality.
- Allocation references.

### UFT Economic Aggregate

Owns:

- Genesis supply.
- Allocation vaults.
- Stake shares.
- Governance locks.
- Fee routing.
- Burn records.
- Restricted reserves.

### Governance Aggregate

Owns:

- Proposal.
- Snapshot.
- Votes.
- Timelock operations.
- Execution result.

---

# Part XV — Canonical Data Placement

## 105. Must Be On-Chain or Cryptographically Canonical

- Active loan terms and policy references.
- Collateral custody and lien state for on-chain collateral.
- Lender-position ownership where tokenized.
- Principal disbursement and on-chain repayments.
- UFT supply, burns, staking shares, and governance locks.
- Governance proposals, votes, timelocks, and executions.
- Bridge escrow balances and wrapped supply.
- Policy and adapter registrations.
- Material protocol events.

## 106. Should Be Off-Chain but Signed or Anchored

- Tenders and offers before acceptance.
- Disclosure packages.
- Legal documents.
- Credit decisions and attestations.
- Appraisal reports.
- Underwriting outputs.
- Fiat and card provider confirmations.
- Governance discussion documents.

## 107. Must Remain Confidential or Restricted

- Legal names and identity documents.
- Bank-account details.
- Card credentials.
- Income and financial statements.
- Private messages.
- Raw credit-model features.
- Fraud-monitoring details.
- Recovery and support communications.

## 108. Derived Only

- Search indexes.
- Portfolio dashboards.
- Reputation scores.
- Health dashboards.
- APY projections.
- Market rankings.
- Analytics.

Derived data must expose the canonical source and calculation version.

---

# Part XVI — Domain-Wide Invariants

## 109. Ownership and Authorization

1. No entity may move value without valid authority or a pre-agreed contractual rule.
2. Ownership changes are evented and historically auditable.
3. Delegation is bounded by scope and time.
4. Service control does not create beneficial ownership.

## 110. Loan Integrity

5. An offer can be consumed at most once.
6. A loan has exactly one canonical home authority.
7. Active economic terms reference immutable versions.
8. A loan cannot become active unless its funding and required security conditions are satisfied.
9. A repaid or finally settled obligation cannot be reactivated.
10. Aggregate lender rights cannot exceed issued loan rights.

## 111. Accounting Integrity

11. Every posted journal entry balances.
12. Corrections use reversals rather than silent mutation.
13. Provisional settlement is not final settlement.
14. Payment allocation follows the disclosed waterfall.
15. No fee is deducted unless authorized by a visible policy.
16. Bad debt and reserves are explicitly recorded.

## 112. Collateral and Recovery Integrity

17. Locked collateral cannot be released while secured obligations remain, except through authorized substitution or refinance.
18. Liquidation is reproducible from policy and recorded observations.
19. A collateral asset cannot support conflicting senior claims without explicit cross-collateral rules.
20. Recovery proceeds follow the contractual loss waterfall.

## 113. UFT Integrity

21. Canonical UFT supply never exceeds the genesis maximum.
22. Rewards never exceed funded resources.
23. One underlying UFT cannot generate duplicate voting, bridge, collateral, or staking claims.
24. Restricted reserves remain segregated.
25. Wrapped UFT supply remains backed by canonical escrow.

## 114. Governance Integrity

26. Governance cannot rewrite active loan economics.
27. Governance execution follows the required timelock.
28. Emergency powers are bounded and temporary.
29. Governance cannot seize a specific user's assets.
30. Every approved policy and adapter is versioned and auditable.

## 115. Privacy and Explainability

31. Sensitive identity and financial data is not published by default.
32. Automated decisions identify their policy and model versions.
33. Reputation scores identify their calculation policy.
34. Access to restricted data is logged.
35. Public interfaces distinguish verified facts from user assertions and projections.

---

# Part XVII — Required Event Families

## 116. Party and Identity Events

```text
PartyCreated
PartyStatusChanged
AccountLinked
AccountUnlinked
AuthorizationPolicyChanged
CredentialIssued
CredentialRevoked
CredentialExpired
DelegateAuthorized
DelegateRevoked
```

## 117. Marketplace Events

```text
TenderPublished
TenderAmended
TenderCancelled
TenderExpired
OfferSubmitted
OfferCountered
OfferWithdrawn
OfferAccepted
OfferConsumed
```

## 118. Credit Events

```text
CreditApplicationSubmitted
CreditDecisionIssued
CreditDecisionExpired
FacilityApproved
FacilityLimitChanged
GuaranteeCreated
GuaranteeCalled
ReputationEventRecorded
```

## 119. Loan Events

```text
LoanCreated
LoanActivated
LoanAmended
InterestAccrued
InstallmentDue
LoanDelinquent
LoanRestructuringStarted
LoanRefinancingStarted
LoanRepaid
LoanDefaulted
LoanClosed
```

## 120. Funding and Position Events

```text
FundingRoundOpened
FundingCommitted
FundingWithdrawn
FundingRoundClosed
TrancheFunded
LenderPositionIssued
LenderPositionListed
LenderPositionTransferred
LenderPositionRedeemed
```

## 121. Collateral and Recovery Events

```text
CollateralProposed
CollateralLocked
CollateralValued
MarginCallIssued
CollateralAdded
CollateralReleased
LiquidationStarted
LiquidationCompleted
RecoveryRecorded
InsuranceClaimSubmitted
InsuranceClaimPaid
```

## 122. Payment Events

```text
PaymentAuthorized
PaymentProcessing
PaymentProvisional
PaymentFinalized
PaymentAllocated
PaymentFailed
PaymentReversed
PaymentDisputed
PaymentRefunded
ReconciliationCompleted
```

## 123. UFT Events

```text
GenesisSupplyCreated
TokenAllocationCreated
TokensVested
UFTStaked
UFTUnstakeRequested
UFTUnstaked
StakeSlashed
GovernanceLockCreated
GovernanceDelegated
ProtocolFeeCollected
FeeRevenueDistributed
UFTBurned
RewardAccrued
RewardClaimed
```

## 124. Governance and Cross-Chain Events

```text
ProposalSubmitted
VoteCast
ProposalQueued
ProposalExecuted
EmergencyActionActivated
EmergencyActionExpired
PolicyRegistered
AdapterRegistered
CrossChainMessageSent
CrossChainMessageVerified
CrossChainMessageExecuted
WrappedAssetMinted
WrappedAssetBurned
BridgeBackingReconciled
```

---

# Part XVIII — Ownership Matrix

## 125. Module Ownership

| Module | Owns canonical state for | Must not own |
|---|---|---|
| Identity | Party references, credentials, consents, delegations | Raw wallet secrets, full card data |
| Marketplace | Tenders, offer discovery, negotiation metadata | Active loan balances |
| Underwriting | Applications, policy execution, decisions, explanations | Custody of loan funds |
| Loan Kernel | Loan terms, policy references, contractual states, balances | Raw identity or payment credentials |
| Funding | Commitments, syndicates, tranches, lender positions | Borrower identity documents |
| Collateral | Custody, lien, valuation references, release/liquidation state | General governance votes |
| Servicing | Schedules, accruals, delinquency, payment allocation | Payment-provider source truth |
| Payments | Instructions, provider/chain settlement, finality, reconciliation | Loan-policy mutation |
| Insurance | Coverage, reserves, claims, payouts | Undisclosed socialized losses |
| UFT | Supply, allocations, staking, locks, fees, burns | Active loan-term modification |
| Governance | Proposals, votes, timelocks, future policy approvals | Individual asset seizure |
| Cross-chain | Messages, escrow, wrapped supply, recovery | Independent duplicate loan truth |
| Indexer | Query projections | Canonical financial mutation |
| Frontend | User interaction and disclosures | Canonical rights or balances |

---

# Part XIX — Open Decisions for v0.2

The Domain Model intentionally leaves these matters for subsequent specifications:

1. Exact UFT maximum supply and allocations.
2. Exact legal structure of fiat-denominated obligations.
3. Supported home chain and satellite chains.
4. Position-token standards by loan type.
5. Legal enforceability model for verified unsecured loans.
6. Initial identity and payment providers.
7. Cross-chain messaging provider strategy.
8. Oracle construction and fallback hierarchy.
9. Accounting currency and reporting standards.
10. Detailed dispute-resolution and arbitration model.
11. Jurisdiction-specific eligibility rules.
12. Exact governance thresholds and constitutional amendment procedure.
13. Insurance capitalization and loss-socialization limits.
14. Data retention periods and privacy-jurisdiction mapping.
15. Treatment of taxes, withholding, and reporting obligations.

---

# Part XX — Acceptance Criteria

Unified Domain Model v0.1 is accepted when every workstream can answer all of the following for its entities:

```text
What is the entity called?
What does it mean?
Who owns or controls it?
What is its canonical authority?
What fields are required?
What privacy class applies?
What states can it enter?
Who may trigger each transition?
What events are emitted?
What other entities does it reference?
What assets or rights can it affect?
What invariants must always remain true?
What happens if an external provider fails?
How is historical truth preserved?
```

No production contract, service, database schema, or API may introduce a conflicting definition without a ratified version update or architecture decision record.

---

# Part XXI — Next Required Specification

The next foundational document is:

## Universal Loan Model and State Machine Specification v0.1

It must convert the entities defined here into precise executable behavior for:

- Origination.
- Funding.
- Activation.
- Accrual.
- Repayment.
- Delinquency.
- Collateral management.
- Liquidation.
- Refinancing.
- Restructuring.
- Secondary transfers.
- Cross-chain settlement.
- Fiat and card settlement.
- Closure.

It must include transition tables, preconditions, authorization rules, accounting effects, emitted events, timeout behavior, reversibility, and failure recovery.
