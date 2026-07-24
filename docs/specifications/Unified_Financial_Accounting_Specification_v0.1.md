# Unified Financial Accounting Specification

**Document:** Unified Financial Accounting Specification  
**Version:** 0.1 — Foundational Draft  
**Status:** Architecture baseline for review and ratification  
**Authority:** Subordinate to the Unified Constitution, ratified protocol invariants, Unified Domain Model, and Universal Loan Model and State Machine Specification  
**Applies to:** Smart contracts, the Unified financial ledger, loan servicing, payments, collateral, syndication, UFT, treasury, insurance, governance, cross-chain operations, fiat and card integrations, indexers, analytics, audits, and financial reporting

---

## 1. Purpose

This specification defines the authoritative accounting model for Unified.

It establishes how Unified shall recognize, classify, record, allocate, reconcile, reverse, report, and audit every material financial event, including:

- Loan commitments and disbursements.
- Principal receivables and borrower obligations.
- Interest accrual and capitalization.
- Fees, penalties, discounts, rebates, and waivers.
- Installments, repayments, allocations, and prepayments.
- Single-lender, syndicated, and tranched funding.
- Fungible, NFT, mixed, UFT, and off-chain collateral.
- Defaults, liquidations, recoveries, write-offs, and insurance.
- Fiat, card, blockchain, and cross-chain settlement.
- UFT allocations, vesting, staking, rewards, fees, burns, and reserves.
- Treasury, protocol-owned liquidity, and governance-controlled funds.
- Foreign-exchange conversion, rounding, suspense, reconciliation, and disputes.

The objective is to ensure that every economic claim in Unified can be reconstructed from immutable evidence and balanced journal entries.

---

## 2. Governing Hierarchy

This specification must be interpreted in the following order:

1. Unified Constitution.
2. Ratified protocol invariants.
3. Unified Domain Model.
4. Universal Loan Model and State Machine Specification.
5. This Financial Accounting Specification.
6. Ratified architecture decision records.
7. Versioned contract and service interfaces.
8. Product configurations and operational procedures.

A lower-level system may not create an accounting treatment that changes a contractual right established by a higher-level document.

---

# Part I — Accounting Principles

## 3. Double-Entry Requirement

Every posted financial transaction must contain at least one debit and one credit.

For each journal entry:

```text
Σ Debits = Σ Credits
```

The ledger must reject unbalanced entries.

A blockchain transfer, bank callback, card authorization, cross-chain message, or application status change is not itself a complete accounting record. It becomes financially authoritative only when interpreted through the applicable policy and posted as a balanced journal entry.

## 4. Economic Substance Over Interface Presentation

Accounting follows economic substance and contractual rights rather than interface labels.

Examples:

- A card authorization is not settled repayment.
- A bridge message submitted is not a completed cross-chain transfer.
- An NFT floor-price increase is not realized protocol income.
- UFT placed in escrow is not burned.
- A lender-position transfer changes beneficial ownership but does not create new principal.
- A governance-approved reward budget is not an expense until earned or distributed according to policy.

## 5. Canonical Ledger

Unified shall maintain one canonical financial ledger for protocol-level and operational accounting.

The ledger records consequences derived from canonical authorities such as:

- Home-chain smart-contract events.
- Satellite-chain verified events.
- Signed off-chain agreements.
- Approved bank and payment-provider settlement records.
- Governance executions.
- Oracle observations used by a valid policy.
- Approved manual adjustments supported by controlled evidence.

Derived dashboards, indexers, data warehouses, and reports may mirror the ledger but may not alter it.

## 6. Immutable Posting

Posted journal entries cannot be edited or deleted.

Errors must be corrected through:

1. A linked reversal entry.
2. A replacement entry where necessary.
3. A documented reason code.
4. The actor and authority that approved the correction.
5. References to the original evidence and entry.

## 7. Idempotency

Every external financial event must have a stable idempotency key.

The same event must not create duplicate accounting entries, even if it is delivered repeatedly by:

- A blockchain indexer.
- A payment provider.
- A bank webhook.
- A card processor.
- A bridge relayer.
- A message queue.
- A recovery job.

## 8. Accrual Basis

Unified shall use accrual accounting for economically earned or incurred amounts where the applicable product requires it.

Interest, fees, rewards, insurance premiums, and penalties may accrue before cash settlement if the governing policy creates an enforceable obligation.

Accrued amounts must remain distinguishable from settled amounts.

## 9. Gross and Net Presentation

Unified must distinguish:

- Gross user payment.
- Third-party processing costs.
- Net protocol revenue.
- Lender proceeds.
- Borrower obligation reduction.
- Taxes or statutory deductions where applicable.

Third-party costs may not be misclassified as protocol revenue.

## 10. Asset and Denomination Separation

Every amount must identify:

- Accounting denomination.
- Settlement asset.
- Native precision.
- Valuation currency where applicable.
- Conversion rate and source when denomination differs from settlement asset.

A loan denominated in USD but settled with USDC, ETH, UFT, or fiat remains a USD-denominated obligation unless the agreement states otherwise.

---

# Part II — Ledger Architecture

## 11. Ledger Layers

Unified shall maintain the following logically separated ledgers:

### 11.1 Protocol ledger

Records contractual and protocol-level balances, including loans, collateral control, lender claims, protocol fees, UFT activity, insurance, and treasury.

### 11.2 Settlement subledger

Records movements through blockchain, fiat, card, and cross-chain rails, including provisional, pending, final, reversed, and disputed amounts.

### 11.3 Custody and control subledger

Records assets held or controlled for users without recognizing them as protocol-owned assets.

### 11.4 Off-chain operational ledger

Records regulated-provider balances, receivables, payables, expenses, and reconciliation differences.

### 11.5 Analytics ledger

Contains derived metrics only and has no authority to create financial rights.

## 12. Journal Entry Structure

Every journal entry shall contain:

```text
journal_entry_id
ledger_id
entry_type
status
business_date
posting_timestamp
source_authority
source_event_id
idempotency_key
loan_id?
party_id?
account_id?
asset_id
denomination_id
exchange_rate_id?
policy_id
policy_version
description
reversal_of_entry_id?
correction_reason_code?
approved_by?
lines[]
evidence_references[]
created_at
```

Each journal line shall contain:

```text
journal_line_id
account_code
debit_amount
credit_amount
asset_quantity?
valuation_amount?
position_id?
tranche_id?
lender_position_id?
collateral_position_id?
settlement_id?
metadata
```

## 13. Posting Statuses

```text
DRAFT
VALIDATED
POSTED
REVERSED
REJECTED
```

Only `POSTED` entries affect balances.

A `REVERSED` entry remains part of history and is offset by a separate reversal.

## 14. Balance Dimensions

Balances must be queryable by relevant dimensions, including:

- Legal or protocol entity.
- Network and chain.
- Asset.
- Denomination.
- User or party.
- Loan.
- Funding pool.
- Syndicate.
- Tranche.
- Lender position.
- Collateral position.
- Payment provider.
- Settlement rail.
- Treasury mandate.
- Insurance pool.
- Governance program.
- UFT allocation or reserve.

---

# Part III — Chart of Accounts

## 15. Account Classes

Unified shall use the following top-level account classes:

```text
1000 Assets
2000 Liabilities and User-Controlled Balances
3000 Protocol Equity, Reserves, and Net Assets
4000 Revenue
5000 Expenses and Losses
6000 Memorandum and Control Accounts
7000 UFT Supply and Token-Control Accounts
8000 Loan and Position Control Accounts
9000 Suspense, Clearing, and Reconciliation Accounts
```

The chart may be extended, but account meanings must remain versioned and unambiguous.

## 16. Core Asset Accounts — 1000 Series

```text
1100 Cash and Fiat at Banks
1110 Restricted Fiat Settlement Funds
1120 Card Processor Receivable
1130 Payment Provider Receivable
1140 Fiat in Transit

1200 Digital Assets Owned by Protocol
1210 UFT Treasury Holdings
1220 Stablecoin Treasury Holdings
1230 Native Asset Treasury Holdings
1240 Protocol-Owned Liquidity Assets
1250 Acquired Loan Positions

1300 Loan-Related Receivables
1310 Principal Receivable
1320 Accrued Interest Receivable
1330 Fee Receivable
1340 Penalty Receivable
1350 Recovery Receivable
1360 Insurance Recoverable
1370 Guarantor Recoverable

1400 Bridge and Cross-Chain Assets
1410 Canonical Assets Locked for Bridging
1420 Cross-Chain Settlement Receivable
1430 Satellite Asset Receivable

1500 Other Assets
1510 Prepaid Provider Costs
1520 Security Deposits
1530 Tax Recoverable
1540 Reconciliation Receivable
```

Protocol accounting must distinguish assets owned by Unified from assets merely held for users.

## 17. Liability and User-Controlled Accounts — 2000 Series

```text
2100 User Digital Asset Balances
2110 User Fiat Balances
2120 Borrower Disbursement Payable
2130 Lender Repayment Payable
2140 Liquidity Provider Payable
2150 Refund Payable
2160 Withdrawal Payable

2200 Custodial and Escrow Obligations
2210 Loan Collateral Held for Borrowers
2220 Collateral Payable to Lenders After Final Claim
2230 Bridge Backing Liability
2240 Auction Proceeds Payable
2250 Unallocated Repayment Liability

2300 Funding and Position Liabilities
2310 Lender Principal Claims
2320 Accrued Lender Interest Claims
2330 Syndicate Distribution Payable
2340 Senior Tranche Claims
2350 Junior Tranche Claims
2360 Position Sale Settlement Payable

2400 Protocol Program Obligations
2410 Earned Staking Rewards Payable
2420 Earned Liquidity Rewards Payable
2430 Vesting Distribution Payable
2440 Governance Grant Payable
2450 Insurance Claim Payable
2460 Guarantor Reimbursement Payable

2500 External Settlement Liabilities
2510 Card Chargeback Reserve
2520 Fiat Reversal Reserve
2530 Provider Fees Payable
2540 Taxes and Statutory Charges Payable
```

## 18. Protocol Equity and Reserve Accounts — 3000 Series

```text
3100 Protocol Treasury Net Assets
3200 Insurance Reserve
3210 Product-Specific Risk Reserve
3220 Cross-Chain Risk Reserve
3230 Card and Fiat Settlement Reserve
3240 Liquidation Shortfall Reserve

3300 UFT Ecosystem Reserves
3310 Community Incentive Reserve
3320 Staking Reward Reserve
3330 Liquidity Incentive Reserve
3340 Development Reserve
3350 Airdrop Reserve
3360 Insurance Bootstrap Reserve

3400 Retained Protocol Surplus or Deficit
3500 Governance-Restricted Funds
```

A reserve designation does not create assets. It classifies funded net assets subject to use restrictions.

## 19. Revenue Accounts — 4000 Series

```text
4100 Loan Origination Fee Revenue
4110 Loan Servicing Fee Revenue
4120 Syndication Fee Revenue
4130 Refinancing Fee Revenue
4140 Restructuring Fee Revenue

4200 Secondary Market Fee Revenue
4210 Exchange and Routing Fee Revenue
4220 Liquidation Administration Revenue
4230 Cross-Chain Coordination Revenue
4240 Fiat Orchestration Revenue
4250 Card Orchestration Revenue

4300 Insurance Premium Revenue
4310 Guarantee Fee Revenue
4320 Premium Feature Revenue
4330 Subscription Revenue

4400 Treasury Yield and Liquidity Revenue
4410 Protocol-Owned Liquidity Fees
4420 Investment Income
4430 Realized Asset Disposal Gain
```

Token price appreciation must not be recognized as operating revenue merely because the market value of treasury UFT increases.

## 20. Expense and Loss Accounts — 5000 Series

```text
5100 Payment Processing Expense
5110 Blockchain and Gas Expense
5120 Cross-Chain Messaging Expense
5130 Oracle and Data Expense
5140 Custody and Banking Expense

5200 Staking Reward Expense
5210 Liquidity Incentive Expense
5220 Community Reward Expense
5230 Governance Grant Expense

5300 Credit Loss Expense
5310 Liquidation Shortfall Loss
5320 Bridge Loss
5330 Card Chargeback Loss
5340 Fiat Settlement Loss
5350 Fraud Loss
5360 Insurance Claim Expense
5370 Guarantor Default Loss

5400 Operating Expense
5410 Audit and Security Expense
5420 Legal and Compliance Expense
5430 Development Expense
5440 Support and Operations Expense

5500 Realized Asset Disposal Loss
5510 Foreign-Exchange Loss
5520 Rounding and Dust Expense
```

## 21. Memorandum and Control Accounts — 6000 Series

These accounts track controlled or contingent quantities without recognizing protocol ownership.

```text
6100 User Collateral at Contract Quantity
6110 NFT Collateral Control
6120 Off-Chain Collateral Control
6130 Guarantee Commitment Control
6140 Insurance Coverage Control
6150 Unfunded Loan Commitment Control
6160 Approved Credit Limit Control
6170 Governance Voting Power Control
6180 UFT Locked for Governance Control
6190 UFT Staked Control
```

Memorandum accounts must never be used to conceal liabilities or losses.

## 22. UFT Supply and Token-Control Accounts — 7000 Series

```text
7100 Genesis UFT Supply Control
7110 UFT Circulating Supply Control
7120 UFT Burned Supply Control
7130 UFT Vested but Unclaimed Control
7140 UFT Unvested Allocation Control
7150 UFT Locked in Bridge Escrow Control
7160 Wrapped UFT Outstanding Control
7170 UFT Staking Vault Underlying Control
7180 sUFT Shares Outstanding Control
7190 veUFT Voting Power Outstanding Control
```

These are supply-control accounts and must reconcile to canonical token contracts.

## 23. Loan and Position Control Accounts — 8000 Series

```text
8100 Original Principal by Loan
8110 Outstanding Principal by Loan
8120 Accrued Interest by Loan
8130 Paid Principal by Loan
8140 Paid Interest by Loan
8150 Fees and Penalties by Loan
8160 Written-Off Principal by Loan
8170 Recovered Principal by Loan

8200 Lender Position Units Issued
8210 Lender Position Units Transferred
8220 Lender Position Units Redeemed
8230 Tranche Units Outstanding
8240 Fractional Position Units Outstanding
```

These control accounts must reconcile to the loan registry and position manager.

## 24. Suspense and Reconciliation Accounts — 9000 Series

```text
9100 Unidentified Digital Asset Receipt
9110 Unidentified Fiat Receipt
9120 Unallocated Loan Payment
9130 Pending Card Settlement
9140 Pending Bank Settlement
9150 Pending Cross-Chain Settlement
9160 Pending Blockchain Confirmation
9170 Provider Reconciliation Difference
9180 Ledger-to-Chain Reconciliation Difference
9190 Foreign-Exchange Clearing
9200 Rounding and Dust Clearing
9210 Disputed Payment Suspense
9220 Reversal Pending Investigation
```

Suspense accounts require aging, ownership, investigation status, and resolution deadlines.

---

# Part IV — Loan Accounting

## 25. Loan Commitment

An unfunded commitment does not create principal receivable or borrower debt.

It may be recorded in control accounts:

```text
Debit  6150 Unfunded Loan Commitment Control
Credit Commitment Authorization Control
```

The entry is reversed when the commitment expires, is cancelled, or is funded.

## 26. Loan Activation and Disbursement

### 26.1 Direct lender-to-borrower settlement

Where the protocol does not take ownership of principal, the protocol ledger records lender claims and borrower obligations as matched control and servicing records.

Conceptual entry:

```text
Debit  1310 Principal Receivable / Borrower Obligation Control
Credit 2310 Lender Principal Claims
```

Any borrower cash or token receipt is evidenced by settlement events but is not protocol revenue.

### 26.2 Principal temporarily routed through Unified

When Unified receives lender funds before disbursement:

```text
On receipt:
Debit  Settlement Asset Held
Credit Lender Funding Payable

On final disbursement:
Debit  Lender Funding Payable
Credit Settlement Asset Held

Contractual recognition:
Debit  Principal Receivable
Credit Lender Principal Claims
```

### 26.3 Origination fee deducted from proceeds

Example:

```text
Gross principal:       5,000 USDC
Origination fee:          25 USDC
Net borrower proceeds: 4,975 USDC
```

Accounting:

```text
Debit  Principal Receivable                 5,000
Credit Lender Principal Claims              5,000

Debit  Borrower Disbursement Payable        5,000
Credit Origination Fee Revenue                 25
Credit Settlement Asset / Borrower Payment  4,975
```

The agreement must state whether the borrower owes the gross or net amount.

## 27. Interest Accrual

Interest shall accrue according to the immutable interest policy and approved calculation convention.

At accrual:

```text
Debit  1320 Accrued Interest Receivable
Credit 2320 Accrued Lender Interest Claims
```

If Unified retains a servicing spread:

```text
Debit  Accrued Interest Receivable          Gross interest
Credit Accrued Lender Interest Claims       Lender share
Credit Servicing Fee Revenue                Protocol share
```

Interest must not accrue:

- Before the contractual commencement event.
- After the obligation has been fully discharged, except valid post-maturity amounts.
- On reversed principal that was never finally disbursed.
- Beyond caps established by the agreement or applicable policy.

## 28. Variable Interest

Each accrual period must store:

- Benchmark source.
- Observation time.
- Benchmark value.
- Spread.
- Floor and cap.
- Day-count convention.
- Principal basis.
- Accrual period.
- Rounding rule.
- Policy version.

Historical accruals cannot be recomputed using a later benchmark value.

## 29. Capitalized Interest

Interest may be added to principal only when the agreement expressly permits capitalization.

```text
Debit  Principal Receivable
Credit Accrued Interest Receivable
```

The capitalization event must not create duplicate lender income. It changes classification from interest due to principal outstanding.

## 30. Fees and Penalties

Fees must be classified by economic purpose.

Examples include:

- Origination.
- Servicing.
- Syndication.
- Late-payment penalty.
- Liquidation administration.
- Refinancing.
- Payment processing.

A fee is recognized only when:

- The agreement authorizes it.
- The triggering condition occurs.
- The amount is determinable.
- Applicable caps are respected.

## 31. Payment Allocation Waterfall

Every repayment must be allocated according to the loan’s immutable repayment policy.

A possible waterfall is:

```text
1. Recoverable third-party costs
2. Penalties
3. Overdue fees
4. Accrued interest
5. Current interest
6. Principal
7. Reserve contribution
8. Refundable excess
```

The exact order is product-specific and must be disclosed before activation.

## 32. Final Loan Repayment

When a final repayment is settled:

```text
Debit  Settlement Asset
Credit Principal Receivable                 Principal portion
Credit Accrued Interest Receivable          Interest portion
Credit Fee Receivable                       Fee portion
```

Distribution to the lender:

```text
Debit  Lender Principal Claims
Debit  Accrued Lender Interest Claims
Credit Lender Repayment Payable
```

When transferred:

```text
Debit  Lender Repayment Payable
Credit Settlement Asset
```

## 33. Partial Repayment

Partial repayments reduce only the components allocated by the repayment waterfall.

The ledger must preserve:

- Gross received amount.
- Final settled amount.
- Principal allocation.
- Interest allocation.
- Fee allocation.
- Penalty allocation.
- Unallocated or refundable excess.

## 34. Prepayment

Prepayment accounting depends on the policy:

- Outstanding principal reduction.
- Future interest reduction.
- Prepayment charge.
- Installment rescheduling.
- Loan-term reduction.

No unearned future interest may be recognized merely because the borrower prepays, unless the contract creates a valid make-whole obligation.

## 35. Overpayment

Amounts exceeding valid obligations must be posted to a user payable or suspense account.

```text
Debit  Settlement Asset
Credit Loan Receivables                     Valid amount
Credit Refund Payable or Unallocated Payment Excess
```

Unified may not retain overpayments as revenue without an explicit lawful basis.

---

# Part V — Syndication, Tranches, and Positions

## 36. Funding Commitment Accounting

Before activation, lender commitments remain contingent and are tracked in control accounts.

When final funding is received, the commitment converts into a lender position.

## 37. Syndicated Principal

For a pro-rata syndicate:

```text
Total principal: 10,000
Lender A: 5,000
Lender B: 3,000
Lender C: 2,000
```

Recognition:

```text
Debit  Principal Receivable               10,000
Credit Lender A Principal Claim            5,000
Credit Lender B Principal Claim            3,000
Credit Lender C Principal Claim            2,000
```

The sum of lender principal claims must equal the funded principal, adjusted only for expressly funded fees or retained interests.

## 38. Tranche Accounting

Tranches must be separated by:

- Principal amount.
- Seniority.
- Interest entitlement.
- Loss allocation.
- Recovery priority.
- Voting or amendment rights.

Example:

```text
Senior tranche principal: 8,000
Junior tranche principal: 2,000
```

Principal and income accounts must be segmented by tranche.

Losses must follow the contractual waterfall, for example:

```text
1. Collateral and recoveries
2. Guarantor support
3. Junior tranche
4. Product reserve
5. Senior tranche
```

## 39. Lender Position Transfer

A secondary-market sale changes ownership of the lender claim but does not alter borrower debt.

At settlement:

```text
Seller:
Debit  Position Sale Settlement Receivable
Credit Loan Position Asset or Claim Carrying Amount
Recognize gain or loss if applicable

Buyer:
Debit  Acquired Loan Position
Credit Settlement Asset or Payable
```

The protocol servicing ledger reassigns future distributions to the buyer only after settlement finality and transfer-policy approval.

## 40. Accrued Interest at Transfer

The transfer agreement must define whether accrued but unpaid interest belongs to:

- Seller.
- Buyer.
- Both through a specified allocation.

The transfer engine must prevent duplicate claims.

## 41. Fractionalization

Fractional lender-position units are control representations of one underlying claim.

```text
Σ Fractional units' economic rights
≤ Underlying lender position rights
```

Fractionalization cannot increase principal or interest owed by the borrower.

---

# Part VI — Collateral Accounting

## 42. Custodial Treatment

Collateral held for a loan remains a user-controlled asset subject to a contractual lien unless ownership transfers through valid liquidation or claim.

It must not be recorded as protocol-owned inventory.

Use:

- Custody liability accounts.
- Memorandum quantity accounts.
- Collateral-position records.

## 43. Collateral Deposit

For fungible collateral:

```text
Debit  Collateral Custody Control
Credit Borrower Collateral Control
```

Equivalent custody quantity records must reconcile to the vault contract.

For NFTs, the ledger records unique identifiers, collection, token ID, ownership source, vault, and lien status rather than a fungible quantity alone.

## 44. Collateral Valuation

Valuation changes affect risk metrics but do not ordinarily create realized revenue or expense.

The system records:

- Valuation amount.
- Oracle source.
- Observation time.
- Confidence or validity status.
- Haircut.
- Liquidation threshold.
- Health factor.

Valuation entries are analytical or memorandum records unless an accounting policy expressly requires remeasurement.

## 45. Collateral Release

After secured debt is discharged:

```text
Debit  Borrower Collateral Control
Credit Collateral Custody Control
```

The on-chain transfer and ledger release must reconcile.

## 46. Collateral Claim After Default

A lender claim does not become final merely because a loan is overdue. The applicable default and liquidation policy must complete.

At final transfer:

```text
Debit  Lender Principal and Interest Claims settled by collateral value
Credit Collateral Payable to Lender
```

Any excess collateral value remains payable to the borrower unless the agreement states an enforceable alternative.

## 47. Liquidation Sale

At liquidation sale settlement:

```text
Debit  Liquidation Proceeds Asset
Credit Collateral Disposal Clearing
```

Apply proceeds according to the contractual waterfall:

```text
Debit  Collateral Disposal Clearing
Credit Liquidation Costs Payable
Credit Accrued Interest Receivable
Credit Principal Receivable
Credit Fees or Penalties Receivable
Credit Borrower Surplus Payable
```

If proceeds are insufficient, the residual becomes an unsecured recovery receivable, insured loss, guaranteed amount, lender loss, or write-off according to policy.

## 48. NFT Liquidation

NFT liquidation accounting must separately record:

- Auction reserve price.
- Winning bid.
- Marketplace or auction fees.
- Royalties where applicable.
- Settlement asset.
- Failed auction status.
- Direct lender claim value if no sale occurs.

Unrealized appraisals are not sale proceeds.

---

# Part VII — Default, Loss, Recovery, and Insurance

## 49. Delinquency

Delinquency changes servicing classification but does not automatically create a loss.

The ledger must distinguish:

- Current.
- Past due.
- Non-performing.
- Defaulted.
- Accelerated.
- In liquidation.
- Written off.
- Recovered.

## 50. Default Recognition

On default, the ledger reclassifies balances but does not duplicate them.

```text
Debit  Defaulted Principal Receivable
Credit Performing Principal Receivable

Debit  Defaulted Interest Receivable
Credit Performing Interest Receivable
```

Interest accrual after default follows the contract and applicable policy.

## 51. Expected and Realized Loss

Where risk reporting requires expected-loss estimates, those estimates must be maintained separately from realized loss.

Realized loss occurs only when contractual recovery sources have been exhausted or a valid write-off is approved.

## 52. Write-Off

A write-off does not erase the historical debt or prevent later recovery unless the legal settlement releases the borrower.

```text
Debit  Credit Loss Expense
Credit Principal or Interest Receivable
```

Write-offs require:

- Policy authority.
- Reason code.
- Recovery assessment.
- Approval evidence.
- Loan and lender-position allocation.

## 53. Recovery After Write-Off

```text
Debit  Settlement Asset
Credit Recovery Income or Reinstated Receivable
```

Recovery proceeds are distributed under the original loss waterfall unless a later lawful settlement changes entitlements.

## 54. Insurance Premium

When earned:

```text
Debit  Premium Receivable or Settlement Asset
Credit Insurance Premium Revenue
```

The associated reserve allocation is separate:

```text
Debit  Retained Protocol Surplus
Credit Insurance Reserve
```

A reserve designation does not replace actual funding.

## 55. Insurance Claim

When a valid claim becomes payable:

```text
Debit  Insurance Claim Expense or Insurance Reserve
Credit Insurance Claim Payable
```

On settlement:

```text
Debit  Insurance Claim Payable
Credit Settlement Asset
```

Claim payments must identify whether they reduce borrower debt, reimburse lenders, acquire recovery rights, or create subrogation claims.

## 56. Guarantee Accounting

A guarantee commitment is contingent until triggered.

On trigger:

```text
Debit  Guarantor Recoverable
Credit Lender or Loan Settlement Payable
```

On guarantor payment:

```text
Debit  Settlement Asset
Credit Guarantor Recoverable
```

The guarantor may acquire a recovery claim against the borrower if the agreement provides it.

---

# Part VIII — Payment and Settlement Accounting

## 57. Payment Lifecycle

The accounting lifecycle is:

```text
INITIATED
→ AUTHORIZED
→ PROVISIONAL
→ FINAL
```

Alternative terminal paths include:

```text
FAILED
REVERSED
DISPUTED
REFUNDED
CHARGED_BACK
```

Debt is reduced finally only when the settlement policy reaches the state required for final allocation.

## 58. Blockchain Payment

Before required confirmation:

```text
Debit  Pending Blockchain Confirmation
Credit Unallocated Loan Payment
```

After finality:

```text
Debit  Settlement Asset
Credit Pending Blockchain Confirmation
```

Then allocate to loan components.

## 59. Fiat Bank Payment

On provider notification before final bank settlement:

```text
Debit  Pending Bank Settlement
Credit Unallocated Loan Payment
```

On final settlement:

```text
Debit  Cash or Fiat at Bank
Credit Pending Bank Settlement
```

Then allocate to the loan.

## 60. Card Payment

On card authorization:

- No final debt reduction.
- Record authorization metadata.

On capture or provisional processor acceptance:

```text
Debit  Pending Card Settlement
Credit Unallocated Loan Payment
```

On final processor settlement:

```text
Debit  Cash or Processor Receivable
Credit Pending Card Settlement
```

Processor fees:

```text
Debit  Card Processing Expense
Credit Cash or Processor Receivable
```

Only the net or gross treatment specified by the processor contract may be used.

## 61. Chargeback

If a final loan allocation is reversed by chargeback:

1. Reverse the previous repayment allocation.
2. Reinstate principal, interest, fees, or penalties in the same proportions.
3. Recognize chargeback fees.
4. Apply any reserve or insurance coverage.
5. Update servicing state according to policy.

Example:

```text
Debit  Reinstated Loan Receivable
Debit  Card Chargeback Loss or Reserve
Credit Cash or Processor Receivable
```

## 62. Refund

Refunds require a valid payable balance or reversal authority.

```text
Debit  Refund Payable
Credit Settlement Asset
```

Refunds must not reduce lender claims unless the underlying payment allocation is also reversed.

## 63. Cross-Chain Settlement

The accounting stages are:

```text
Source asset locked or burned
→ Cross-chain receivable or clearing
→ Message verified
→ Destination asset released or minted
→ Final settlement
```

At source lock:

```text
Debit  Canonical Assets Locked for Bridging
Credit User or Settlement Asset Balance
```

At verified destination issuance, bridge backing and wrapped supply control accounts must reconcile.

A failed or timed-out message remains in cross-chain suspense until recovered or compensated.

## 64. Currency Conversion

Every conversion must record:

- Source asset and amount.
- Destination asset and amount.
- Quoted rate.
- Executed rate.
- Price source.
- Spread.
- Provider fee.
- Slippage.
- Timestamp.
- Rounding.

Realized conversion differences are recognized separately from protocol service fees.

---

# Part IX — UFT Accounting

## 65. Genesis Supply

At genesis, the full maximum supply is minted to approved allocation vaults.

Supply-control records must show:

```text
Maximum supply
Genesis minted supply
Allocation by vault
Circulating supply
Locked supply
Vested supply
Unvested supply
Bridge-escrowed supply
Burned supply
```

The invariant is:

```text
Canonical UFT Total Supply
= Genesis Minted Supply − Permanent Burns
```

## 66. Token Allocation

Moving UFT between approved allocation vaults does not create expense by itself.

Expense or distribution recognition occurs when tokens are earned, granted, vested, claimed, or transferred for goods, services, incentives, or losses according to policy.

## 67. Vesting

Unvested allocations remain restricted.

At vesting eligibility:

```text
Debit  Relevant Reserve or Compensation/Grant Expense
Credit Vested Distribution Payable
```

On claim:

```text
Debit  Vested Distribution Payable
Credit UFT Treasury or Allocation Holdings
```

Supply does not increase because tokens were minted at genesis.

## 68. Protocol Fees Paid in UFT

On receipt:

```text
Debit  UFT Treasury Holdings or Fee Router Asset
Credit Applicable Fee Revenue
```

The subsequent revenue split is recorded separately.

## 69. UFT Burn

A burn permanently reduces canonical supply.

```text
Debit  UFT Burn Allocation / Protocol Net Assets
Credit UFT Treasury Holdings
```

Supply control:

```text
Debit  UFT Circulating or Treasury Supply Control
Credit UFT Burned Supply Control
```

Burned UFT cannot remain recorded as a treasury asset.

## 70. Buyback and Burn

On purchase:

```text
Debit  UFT Treasury Holdings
Credit Settlement Asset
```

On burn:

```text
Debit  Burn Allocation
Credit UFT Treasury Holdings
```

Trading fees, slippage, and execution costs are separate expenses.

## 71. UFT Staking

Depositing UFT into the staking vault transfers control but does not create protocol revenue.

The vault records underlying UFT and sUFT shares.

Invariant:

```text
Value attributable to outstanding sUFT
≤ Accounted assets of staking vault after recognized losses
```

## 72. Staking Rewards

Rewards may be funded from:

- Protocol revenue.
- Pre-minted reward reserves.
- Liquidation penalties.
- Slashed stake.
- Governance-approved treasury allocations.

At reward accrual:

```text
Debit  Staking Reward Expense or Reward Reserve
Credit Earned Staking Rewards Payable
```

On distribution or vault compounding:

```text
Debit  Earned Staking Rewards Payable
Credit UFT Holdings or Other Settlement Asset
```

Unfunded promised yield cannot be recognized as payable.

## 73. Slashing

Slashing reduces the staking vault’s assets under a defined covered event.

```text
Debit  Covered Loss Settlement or Insurance Recovery Use
Credit UFT Staking Vault Underlying
```

sUFT share claims adjust according to the staking-vault policy.

Slashed value must not be simultaneously recognized as protocol income and loss compensation unless the economic flows justify both entries.

## 74. Governance Locks

Locking UFT for veUFT voting power does not create expense, revenue, or new UFT supply.

The ledger records:

- UFT quantity locked.
- Lock duration.
- Voting power issued.
- Delegation.
- Unlock eligibility.

veUFT has no independent redemption value beyond its governing lock rules.

## 75. Wrapped UFT

For each satellite chain:

```text
Wrapped UFT Outstanding
≤ Canonical UFT Locked for That Chain
```

Wrapped issuance and redemption are supply-control events, not revenue.

Satellite burns must reconcile to canonical backing according to the bridge policy.

## 76. Liquidity Incentives

At earning:

```text
Debit  Liquidity Incentive Expense or Reserve
Credit Earned Liquidity Rewards Payable
```

On claim:

```text
Debit  Earned Liquidity Rewards Payable
Credit UFT or Other Reward Asset
```

Deposited liquidity principal remains owned by liquidity providers unless transferred under explicit terms.

---

# Part X — Treasury, Reserves, and Governance

## 77. Treasury Segmentation

Treasury assets must be segmented by mandate:

- General operations.
- Insurance.
- Staking rewards.
- Liquidity incentives.
- Community grants.
- Development.
- Cross-chain risk.
- Fiat and card settlement.
- Emergency response.

Governance approval does not permit funds restricted to one mandate to be silently used for another.

## 78. Revenue Allocation

When net protocol revenue is allocated:

```text
Debit  Retained Protocol Surplus
Credit Insurance Reserve
Credit Staking Reward Reserve
Credit Treasury General Reserve
Credit Liquidity Incentive Reserve
Credit Burn Allocation
```

Percentages must total 100% of the amount being allocated.

## 79. Governance Grants

On approval, a grant may remain a commitment until performance or vesting conditions are met.

At earning:

```text
Debit  Governance Grant Expense
Credit Governance Grant Payable
```

On settlement:

```text
Debit  Governance Grant Payable
Credit Settlement Asset or UFT Holdings
```

## 80. Protocol-Owned Liquidity

Treasury-provided pool assets remain protocol assets.

The ledger must track:

- Asset deposits.
- LP tokens or positions received.
- Fees earned.
- Impermanent-loss analytics.
- Withdrawals.
- Realized gains or losses.

Unrealized pool-value changes must not be mixed with operating fee revenue.

## 81. Emergency Expenditure

Emergency spending requires:

- Defined emergency authority.
- Purpose.
- Maximum amount.
- Recipient.
- Evidence.
- Expiration or review.
- Public post-event accounting.

Emergency authority cannot bypass double-entry recording.

---

# Part XI — Reconciliation

## 82. Required Reconciliations

Unified shall perform reconciliation between:

- Canonical ledger and home-chain contracts.
- Canonical ledger and satellite chains.
- Bridge escrow and wrapped supply.
- UFT token supply and UFT control accounts.
- Loan registry and loan receivable/control accounts.
- Lender positions and lender claim balances.
- Collateral vaults and collateral control accounts.
- Bank statements and fiat ledger balances.
- Card processor reports and card receivables.
- Payment providers and settlement subledgers.
- Treasury wallets and treasury accounts.
- Staking vault assets and sUFT shares.
- Governance locks and veUFT voting power.

## 83. Reconciliation Frequency

Frequency must reflect risk:

- On-chain critical balances: continuously or per finalized block/event batch.
- UFT and bridge supply: continuously.
- Bank and payment providers: at least daily where operations are active.
- Card processors: daily and by settlement batch.
- Treasury: daily, with governance-period reporting.
- Loan servicing: after every finalized financial event and at scheduled close.

## 84. Reconciliation Difference

Every difference must have:

```text
difference_id
source_system
ledger_balance
external_balance
amount
asset
detected_at
owner
status
reason_code
investigation_notes
resolution_entry_id?
resolved_at?
```

Differences may not be silently netted against unrelated balances.

## 85. Suspense Aging

Suspense balances must be aged and escalated.

Suggested classes:

```text
0–1 day
2–3 days
4–7 days
8–30 days
Over 30 days
```

Product-specific settlement periods may use different thresholds, but every suspense balance requires an accountable owner.

---

# Part XII — Foreign Exchange, Precision, and Rounding

## 86. Precision

The ledger must preserve native asset precision and a defined accounting precision.

No system may use floating-point arithmetic for financially material calculations.

Use integer or fixed-point arithmetic with explicit scale.

## 87. Rounding

Every policy must define:

- Calculation precision.
- Rounding direction.
- Rounding stage.
- Treatment of residual dust.
- Beneficiary of rounding differences.

Rounding must not systematically and undisclosedly favor the protocol.

## 88. Foreign-Exchange Recognition

Where obligation denomination differs from settlement asset:

- The obligation remains in its contractual denomination.
- Settlement is converted using the agreed rate policy.
- Realized gains or losses are identified separately.
- Provider spread and protocol fee are separately disclosed.

## 89. Dust

Residual amounts below transfer feasibility must be recorded in dust clearing.

Dust policies may:

- Accumulate until transferable.
- Be refunded in another asset.
- Be donated with user consent.
- Be transferred to treasury under a disclosed de minimis rule.

Dust cannot disappear from accounting.

---

# Part XIII — Period Close and Reporting

## 90. Financial Close

Each reporting period shall include:

1. Event ingestion completion.
2. Chain finality confirmation.
3. Provider settlement reconciliation.
4. Accrual posting.
5. Suspense review.
6. UFT and bridge supply reconciliation.
7. Loan and collateral reconciliation.
8. Reserve and insurance review.
9. Correction and reversal review.
10. Report generation and sign-off.

## 91. Core Reports

Unified should produce:

- Trial balance.
- General ledger.
- Journal report.
- Loan receivable and obligation report.
- Lender-position and tranche report.
- Collateral custody and valuation report.
- Delinquency, default, and recovery report.
- Payment settlement and suspense report.
- Treasury and reserve report.
- UFT supply, allocation, staking, vesting, and burn report.
- Bridge-backing report.
- Insurance solvency report.
- Protocol revenue and expense report.
- User asset and liability reconciliation report.

## 92. User Statements

Borrower statements shall show at minimum:

- Original principal.
- Disbursed amount.
- Current principal.
- Accrued interest.
- Fees and penalties.
- Payments received.
- Payment allocations.
- Collateral status.
- Next due date.
- Final maturity.
- Disputed or provisional items.

Lender statements shall show:

- Position ownership.
- Principal funded.
- Principal outstanding.
- Interest earned and received.
- Fees deducted.
- Transfers.
- Loss allocations.
- Recoveries.
- Current position value where provided, clearly marked as valuation rather than guaranteed redemption.

## 93. Public Protocol Reporting

Subject to privacy rules, Unified shall publish auditable aggregate information on:

- Loan originations.
- Outstanding principal.
- Repayments.
- Defaults.
- Liquidations.
- Recoveries.
- Protocol revenue.
- Treasury balances.
- Insurance reserves.
- UFT supply and burns.
- Staking and reward liabilities.
- Cross-chain backing.

Public reports must not reveal restricted identity or financial data.

---

# Part XIV — Accounting Events

## 94. Required Event Families

The accounting system must consume or produce events including:

```text
JournalEntryPosted
JournalEntryReversed
ReconciliationDifferenceDetected
ReconciliationDifferenceResolved
LoanPrincipalRecognized
InterestAccrued
InterestCapitalized
PaymentReceived
PaymentFinalized
PaymentAllocated
PaymentReversed
LoanWrittenOff
RecoveryReceived
CollateralDeposited
CollateralReleased
CollateralLiquidated
LiquidationProceedsAllocated
LenderClaimIssued
LenderClaimTransferred
LenderDistributionCompleted
InsurancePremiumEarned
InsuranceClaimRecognized
InsuranceClaimPaid
UFTGenesisMintRecorded
UFTVested
UFTRewardEarned
UFTRewardPaid
UFTBurned
UFTBridgeBackingChanged
TreasuryAllocationChanged
ReserveFunded
ReserveUsed
```

Each event must identify the relevant policy and version where financially material.

---

# Part XV — Accounting Invariants

## 95. Foundational Invariants

1. Every posted journal entry balances.
2. Posted entries are immutable.
3. Corrections use linked reversals and replacements.
4. One external event creates at most one economic posting per intended ledger effect.
5. No payment reduces debt finally before required settlement finality.
6. Borrower debt cannot be reduced without an authorized payment, waiver, settlement, collateral application, insurance payment, guarantee payment, or write-off.
7. A write-off does not create a false cash settlement.
8. Aggregate lender principal claims cannot exceed funded principal plus expressly capitalized amounts.
9. Fractional positions cannot exceed the underlying lender claim.
10. Tranche distributions follow contractual priority.
11. User collateral is not protocol revenue or treasury inventory.
12. Collateral release cannot occur while secured debt remains unless the agreement authorizes a partial release.
13. Liquidation proceeds cannot be allocated twice.
14. Borrower surplus from liquidation cannot be retained without contractual authority.
15. Protocol fees cannot be deducted unless disclosed and triggered.
16. Third-party processing costs are not protocol revenue.
17. Provisional fiat and card payments remain distinguishable from final settlement.
18. Chargebacks reinstate previously reduced obligations according to the original allocation.
19. Bridge-issued assets cannot exceed verified canonical backing.
20. Canonical UFT supply cannot exceed the genesis cap.
21. Burned UFT cannot remain in treasury balances.
22. Staking rewards cannot exceed funded reward resources.
23. veUFT does not create additional UFT supply or independent asset value.
24. UFT locked as collateral, staking capital, bridge backing, or governance lock cannot be double-counted in the same capacity.
25. Insurance reserves cannot exceed funded assets merely because a governance target exists.
26. Insurance claim payments must reduce the correct loss or create the correct recovery right.
27. Suspense balances cannot be silently written to revenue.
28. Foreign-exchange differences are separate from service fees.
29. Rounding and dust remain accounted for.
30. Ledger balances must reconcile to canonical contracts and providers.
31. An interface or indexer cannot alter posted accounting.
32. Governance cannot create accounting entries that contradict active loan terms.
33. Emergency actions remain fully journaled and auditable.
34. Privacy restrictions do not permit omission of financial evidence; sensitive evidence must be referenced securely.
35. No asset, liability, revenue, expense, reserve, or supply figure may be reported without a traceable ledger basis.

---

# Part XVI — Implementation Boundaries

## 96. Smart Contracts

Smart contracts shall:

- Emit deterministic financial events.
- Maintain canonical balances where they control assets or obligations.
- Prevent unauthorized asset movement.
- Expose sufficient state for reconciliation.
- Avoid hidden balance transformations.

Smart contracts are not required to implement the complete general ledger, but their state and events must support exact ledger reconstruction.

## 97. Accounting Service

The accounting service shall:

- Consume canonical events.
- Validate policy and event versions.
- Enforce idempotency.
- Produce balanced entries.
- Maintain account balances.
- Support reversals and corrections.
- Reconcile external authorities.
- Expose audit-grade reports.

It may not change contractual state.

## 98. Loan Servicing Service

The servicing service calculates amounts due under approved policies and requests accounting entries. The accounting service independently validates posting structure and evidence.

## 99. Payment Orchestrator

The payment orchestrator manages external payment states and evidence. It cannot declare final debt reduction without satisfying the settlement policy and posting the required accounting entries.

## 100. Indexers and Analytics

Indexers and analytics systems are derived. They may detect discrepancies but cannot post financial corrections without controlled accounting authorization.

---

# Part XVII — Required Follow-On Artifacts

## 101. Subordinate Specifications

The following documents must be produced after ratification of this specification:

1. `UNIFIED_CHART_OF_ACCOUNTS_v0.1.csv`
2. `JOURNAL_ENTRY_SCHEMA_v0.1.json`
3. `ACCOUNTING_EVENT_SCHEMA_v0.1.json`
4. `LOAN_ACCOUNTING_RULES_v0.1.md`
5. `PAYMENT_AND_SETTLEMENT_ACCOUNTING_v0.1.md`
6. `UFT_ACCOUNTING_AND_SUPPLY_CONTROLS_v0.1.md`
7. `TREASURY_AND_RESERVE_POLICY_v0.1.md`
8. `RECONCILIATION_CONTROL_MATRIX_v0.1.md`
9. `FINANCIAL_REPORTING_SCHEMA_v0.1.md`
10. `ACCOUNTING_INVARIANT_TEST_PLAN_v0.1.md`

## 102. Architecture Decisions Required

Architecture decision records must resolve:

- Whether protocol accounting uses a single global ledger or entity-scoped ledgers with consolidation.
- Base reporting currency or currencies.
- Accounting treatment of direct peer-to-peer principal flows.
- Jurisdiction-specific legal-entity boundaries.
- Expected-credit-loss methodology.
- Treasury asset valuation policy.
- UFT accounting classification for financial reporting.
- Treatment of protocol-owned liquidity.
- Treatment of token grants and contributor compensation.
- Finality thresholds by chain and payment provider.
- Storage technology and cryptographic integrity for the ledger.
- Period-close governance and approval roles.

---

# Part XVIII — Ratification Checklist

This specification is ready for ratification when Unified can answer:

```text
Which account records each asset and obligation?
What evidence authorizes each journal entry?
When does a payment become final?
How is every repayment allocated?
How do lender claims reconcile to borrower obligations?
How are syndicate and tranche cash flows divided?
How is collateral controlled without being treated as protocol property?
How are defaults, write-offs, recoveries, guarantees, and insurance distinguished?
How do fiat, card, blockchain, and cross-chain balances reconcile?
How does UFT supply reconcile across treasury, vesting, staking, burns, and bridges?
How are errors corrected without rewriting history?
How are suspense and reconciliation differences resolved?
Which reports demonstrate protocol solvency and user-asset backing?
```

---

# Conclusion

The Unified Financial Accounting Specification establishes one auditable financial language across smart contracts, services, payment providers, chains, UFT, loans, collateral, lenders, borrowers, treasury, and governance.

Unified may support extreme product complexity, but it must never support ambiguous money movement. Every economic event must have a canonical source, a defined finality point, a balanced journal entry, an accountable owner, and a reproducible audit trail.
