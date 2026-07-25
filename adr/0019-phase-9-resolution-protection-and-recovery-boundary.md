# ADR 0019: Phase 9 Resolution, Protection, and Recovery Boundary

Status: accepted for synthetic local engineering

Date: 2026-07-25

## Context

Phase 8 closes a bounded cross-chain and wrapped UFT engineering milestone. It does not
authorize loan modification, lien replacement, insurance promises, funded reserves,
guarantor enforcement, legal recovery, write-off, or loss socialization. Phase 9 must
implement all five work packages in the governing master plan:

1. payoff quote engine;
2. refinance coordinator;
3. restructuring controller;
4. insurance manager; and
5. recovery manager.

These capabilities can change lender priority, borrower debt, collateral rights, funded
capacity, loss recognition, and later recovery ownership. A merely administrative
workflow would be unsafe. The boundary must make economic authority canonical,
separate proposals and evidence from value movement, preserve protected consent,
maintain one senior lien, and prevent one loss or recovery from being counted twice.

The first Phase 9 milestone remains synthetic and local. Real reserves, insurance
guarantees, legal or off-chain recovery authority, production providers, public
networks, production keys, real assets, live loans, and real funds are prohibited.
Synthetic reserve funding and mocked external evidence are required only to exercise the
complete state machines, conservation rules, accounting, and recovery controls.

## Decision

### 1. Bounded environment and complete product

The complete first product runs on the existing isolated local EVM home domain with
chain ID `31337`. It uses:

- one synthetic fungible settlement asset with exact balance-delta semantics;
- one synthetic fungible collateral asset under canonical local custody;
- one old secured loan with a canonical debt-component snapshot;
- one proposed replacement loan and new lender;
- immutable refinance and amendment policies;
- a deterministic position-right snapshot with borrower consent and lender voting;
- one segregated reserve pool funded with synthetic settlement assets;
- one synthetic coverage policy, premium, eligible loss, claim, and payout;
- one capped synthetic guarantor commitment and actual local payment;
- one loss record, write-off, subrogation record, and later recovery receipt; and
- append-only accounting, reconciliation, restart, replay, and reset evidence.

The authoritative product flow is:

```text
canonical debt snapshot
  -> expiring payoff quote
  -> new lender funding escrow
  -> exact old-lender payoff
  -> old senior lien extinguished
  -> collateral assigned to replacement loan
  -> replacement loan activated
  -> residual proceeds paid to canonical borrower
  -> policy-bound restructuring proposal
  -> immutable position snapshot and borrower consent
  -> quorum/approval and exact amendment execution
  -> funded synthetic reserve and premium-backed coverage
  -> covered loss and threshold claim adjudication
  -> deterministic guarantor and reserve payout
  -> exact residual write-off and subrogation
  -> actual later recovery receipt
  -> deterministic recovery allocation and reconciliation
```

All amounts are integers in one exact synthetic asset denomination. The flow exercises
nonzero principal, accrued interest, fees, penalties, credits, borrower proceeds,
premium, deductible, guarantor payment, insurance payment, write-off, and later
recovery. Zero-only fixtures cannot satisfy the exit.

Existing Phase 3 through Phase 8 loan, collateral, position, bridge, and recovery
contracts are not retrofitted. Phase 9 uses `IMPLEMENTATION_VERSION = 9` with
`Phase9LoanFactory`, `Phase9LoanAccount`, `PositionManagerV2`,
`CollateralCustodyV2`, and `LienRegistry`. The existing `LoanRegistry` remains the
registration authority, but existing loan IDs and histories remain immutable and a
replacement loan receives a new ID. Phase 8 cross-chain loans, satellite collateral,
bridge backing, wrapped UFT, and message recovery are outside this product and
unreachable from every Phase 9 component.

### 2. Canonical authorities

Authority remains divided:

| Fact or action | Canonical authority |
| --- | --- |
| Debt components and debt state version | active loan account |
| Payoff quote identity and expiry | payoff quote engine derived from the active loan |
| Old-loan payoff and closure | old loan account |
| Senior collateral lien | canonical lien registry |
| New-loan terms and activation | replacement loan account and refinance coordinator |
| Amendment policy | policy hash bound to the active loan before proposal |
| Position voting weight | immutable position snapshot at proposal creation |
| Borrower consent | domain-bound signature over the exact amendment |
| Reserve assets | actual reserve-vault token custody |
| Stress valuation and capacity | immutable reserve policy and exact custody |
| Covered loss | canonical loss record after credited recovery sources |
| Claim approval | distinct local two-of-three adjudicator set over exact claim facts |
| Claim payment | reserve vault executing the approved canonical beneficiary and amount |
| Guarantee recovery | actual guarantor token receipt, not the commitment itself |
| Off-chain or legal recovery | actual token receipt plus descriptive mocked evidence |
| Write-off | policy-bound approval over the exact remaining loss |
| Subrogation and later allocation | recovery manager and immutable waterfall policy |
| Financial history | append-only balanced ledger posting |

A quote, proposal, vote, signature, evidence hash, claim approval, guarantee commitment,
mock provider response, operator assertion, database row, or journal intent cannot by
itself transfer value or reduce debt.

### 3. Payoff quote

The quote preimage binds:

```text
"UNIFIED_PAYOFF_QUOTE_V1"
loan ID
loan implementation and policy-set hash
debt state version
principal
accrued interest
fees
penalties
credits
net payoff amount
settlement asset
canonical component-beneficiary vector
settlement route hash
issued at
valid until
quote nonce
```

The quote ID is the hash of that preimage and is never included in its own preimage.

The canonical equation is:

```text
net payoff
= principal
 + accrued interest
 + fees
 + penalties
 - credits
```

Credits cannot exceed the gross components. Every component comes from the canonical
debt snapshot; callers cannot supply or omit a component. Quote validity is bounded by
policy, and execution requires the exact debt state version, policy, asset, recipient,
route, and unexpired quote. Any repayment, waiver, accrual, correction, or restructuring
that changes the debt version invalidates the quote.

The legacy protocol API returns only a payoff total and expiry and is insufficient for
this boundary. Phase 9 adds an ABI-compatible `IPayoffQuoteEngineV2` view and event that
expose every component, component beneficiary, asset, route, version, nonce, and hash
commitment.
Existing interfaces and event meanings remain unchanged. Likewise, a legacy claim
payment method that accepts a recipient must require that argument to equal the
policy-bound beneficiary; it grants no recipient-selection authority.

### 4. Refinance state and identity

The monotonic local refinance states are:

```text
NONE
  -> REQUESTED
  -> QUOTED
  -> OFFERED
  -> ACCEPTED
  -> FUNDING_ESCROWED
  -> EXECUTING
  -> COMPLETED

OFFERED -> REJECTED | EXPIRED | CANCELLED
ACCEPTED -> EXPIRED | CANCELLED only before funding
FUNDING_ESCROWED -> REFUNDABLE only before execution begins
REFUNDABLE -> REFUNDED
any safety contradiction -> DISPUTED
```

The refinance ID binds the old loan, proposed loan, borrower, old and new lenders,
quote, exact old payoff, new principal, settlement asset, collateral set and lien
version, proposed terms, policy set, funding amount, borrower proceeds, fees, expiry,
and nonce.

New funding is pulled into coordinator escrow before execution. Execution is one local
EVM transaction:

1. lock the refinance record against reentry and replay;
2. verify the quote, debt state, funding, collateral, parties, policies, and expiry;
3. settle every payoff component to its bound beneficiary and extinguish the quoted
   old debt;
4. transfer the one canonical senior lien from old loan to replacement loan without
   exposing collateral to borrower or caller;
5. activate the exact replacement loan;
6. pay only the committed residual proceeds to the canonical borrower;
7. record terminal refinance and old/new loan evidence; and
8. leave no coordinator or lien-transfer balance.

The lien registry has one enforceable owner per collateral ID. A pending target has no
independent senior claim. Old ownership changes to new ownership only inside the
successful execution transaction. Any revert restores funding, debt, lien, loan, and
recipient balances atomically.

Before execution, rejection, expiry, or cancellation returns escrow once to the
canonical new lender. After execution begins, the transaction either completes or
reverts; no operator-selected partial completion exists in this local slice. External
settlement and non-atomic lien systems remain prohibited.

### 5. Restructuring and consent

The monotonic restructuring states are:

```text
NONE
  -> PROPOSED
  -> REVIEW
  -> VOTING
  -> APPROVED
  -> EXECUTING
  -> EFFECTIVE

REVIEW | VOTING -> REJECTED | EXPIRED | WITHDRAWN
any safety contradiction -> DISPUTED
```

The restructuring ID binds the loan, active terms version, amendment-policy hash,
closed modification vocabulary, amended terms hash, disclosure hash, accounting-delta
hash, position snapshot root and block, eligible voting weight, quorum, approval
threshold, borrower, borrower-consent nonce, review start, expiry, and proposal nonce.

The first slice supports policy-bounded maturity extension, rate reduction, payment
holiday, fee or penalty waiver, arrears capitalization, added collateral commitment,
and explicit partial forgiveness. Each modification has an independent policy cap.
Unrecognized fields, a rate increase, hidden recipient change, lender-right
substitution, unsupported asset change, or arithmetic outside the accepted policy
fails.

Borrower consent is required over the exact proposal. Position votes use one immutable
snapshot. A position ID can vote once; current ownership after the snapshot cannot
create or duplicate weight. Quorum and approval are computed from eligible snapshot
weight. General protocol governance cannot amend an individual loan.

Execution requires the unchanged active debt/terms version, approved borrower consent,
quorum, threshold, unexpired proposal, exact schedule, and balanced accounting delta.
Debt can decrease only through an explicitly disclosed and approved forgiveness or
settlement amount that produces the corresponding loss and position allocation.

### 6. Synthetic reserve and coverage

The reserve vault accepts only registered synthetic local tokens with exact
balance-delta behavior. Deposits are segregated from operating treasury, bridge
backing, user balances, and collateral. There is no general withdrawal, rescue, swap,
borrow, investment, or arbitrary call.

The first product uses one dedicated product-specific protection pool. It does not use
or imply authority over the protocol-wide `3200 Insurance Reserve`, the UFT genesis
insurance allocation, operating treasury, or another product reserve. A genesis
allocation is not proof of funded, legally available, eligible reserve assets.

For each asset and pool:

```text
gross funded assets              = exact reserve-vault custody
eligible risk-adjusted assets    = floor(
                                   gross assets * stress haircut bps / 10_000
                                  )
modeled covered loss             = immutable synthetic loss fixture
                                  at the policy target confidence
approved unpaid claims           = sum of approved claim payables
unclaimed coverage commitments   = sum of policy remaining limits
                                  excluding amounts converted to approved payables
encumbered capacity              = approved unpaid claims
                                  + unclaimed coverage commitments
unencumbered payout liquidity     = custody - all approved unpaid claims
claim-specific payment liquidity = custody
                                   - approved unpaid claims for other claims
available underwriting capacity  = eligible risk-adjusted assets
                                   - encumbered capacity
reserve coverage ratio           = eligible risk-adjusted assets
                                   / modeled covered loss
commitment coverage ratio        = eligible risk-adjusted assets
                                   / max(encumbered capacity, 1)
```

The stress haircut is an integer from `0` through `10_000` basis points and modeled
covered loss is strictly positive before either ratio is computed. All values are
denomination-specific. No FX or cross-asset netting is permitted. A
correlated synthetic UFT-class reserve receives the immutable stress haircut required
by policy. Its undiscounted market or fixture value cannot be used for coverage.
`modeled covered loss` and target confidence are deterministic synthetic fixtures, not
actuarial or production-capital evidence.

Approval atomically converts the approved amount from the policy's unclaimed commitment
into an approved unpaid payable. It is never present in both terms. Payment reduces the
payable and actual custody. A deficit blocks new coverage and may leave an approved
claim visibly payment-pending; it cannot erase a claim, invent liquidity, or silently
lower modeled loss.

Coverage activation binds pool, loan, beneficiary, settlement asset, covered events,
deductible, coverage percentage, policy limit, premium, loss priority, subrogation
priority, activation, and expiry. Each new or increased commitment must not exceed the
pre-activation available underwriting capacity, and the postcondition must preserve
`encumbered capacity <= eligible risk-adjusted assets` plus both policy ratio floors.
Impairment may leave existing commitments above current capacity, but then all new or
increased coverage is blocked without erasing an existing payable. A premium becomes
funded only after the exact token receipt; a receivable or promise does not increase
capacity.

### 7. Claims and guarantee

The claim states are:

```text
NONE
  -> SUBMITTED
  -> UNDER_REVIEW
  -> APPROVED | PARTIALLY_APPROVED | REJECTED | EXPIRED | DISPUTED
APPROVED | PARTIALLY_APPROVED
  -> PAYMENT_PENDING
  -> PAID
```

The eligible claim uses a covered-loss exposure, not a prematurely recognized realized
accounting loss:

```text
eligible uncovered loss
= gross covered-loss exposure
 - collateral recovery credited to the loss
 - guarantor payment credited to the loss
 - prior insurance payment
 - other recovery credited to the loss

coverage-formula amount
= max(eligible uncovered loss - deductible, 0) * coverage percentage

approval cap
= min(
     requested amount,
     coverage-formula amount,
     unclaimed policy limit,
     unclaimed policy commitment,
     claim-specific payment liquidity,
     beneficiary covered unresolved entitlement
   )

approved amount = min(adjudicated amount, approval cap)
payable amount  = approved amount - paid amount
payment permitted <=> claim-specific payment liquidity >= payable amount
payment amount     = payable amount when permitted; otherwise zero
```

The beneficiary entitlement is derived from the immutable position-loss allocation and
cannot exceed that beneficiary's unresolved covered right. It prevents aggregate loss
or pool liquidity from authorizing payment above the stored claimant right.

The first local product does not make partial claim transfers. Insufficient liquidity
leaves the full payable in `PAYMENT_PENDING`; one nonce-bound payment consumes the
decision only when it can pay the exact remaining payable.

The two-of-three local adjudicator set signs the claim ID, coverage, loss ID, exact loss
state version, requested and adjudicated amounts, evidence hash, adjudication nonce,
validity deadline, and policy version. The contract independently applies the approval
cap and derives the approved amount; approved amount cannot substitute for the signed
adjudicated amount. Duplicate,
unknown, expired, wrong-policy, changed-loss, changed-amount, or cross-contract
signatures fail. Adjudicators cannot select payout recipient; the beneficiary is bound
by coverage.

A guarantee commitment records a maximum and covered obligation but is not a funded
recovery. Only an exact synthetic token payment into the recovery vault reduces loss.
That payment creates a bounded guarantor subrogation right if the policy provides it.
Unfunded, external, or legal guarantees remain prohibited.

### 8. Loss, write-off, subrogation, and recovery

One immutable loss ID binds loan, debt version, default event, asset, gross covered-loss
exposure, collateral proceeds, borrower credits, policy set, lender-position snapshot,
and waterfall. Every source uses that loss ID. Expected loss, covered-loss exposure,
approved claim payable, funded claim payment, residual loss exposure, realized loss,
and write-off are distinct facts and states.

```text
residual loss exposure
= gross covered-loss exposure
 - collateral recovery
 - guarantor payment
 - insurance payment
 - other credited recovery
 - authorized forgiveness already recognized
```

No component may reduce exposure below zero. Accounting recognizes realized loss only
when contractual recovery sources are exhausted or an exact valid write-off is
approved. A write-off cannot exceed residual loss exposure, creates no payment, and
preserves historical debt and recovery rights unless a separate synthetic settlement
explicitly releases them.

Later collateral, guarantor, or mocked off-chain/legal recovery evidence becomes value
only after an exact registered token receipt. Mock evidence contains no personal or
restricted data and cannot select the amount, asset, payer, or recipients.

The first product freezes the protection and loss order as:

1. collateral recovery;
2. borrower reserve or security deposit, fixed at zero and unsupported in this slice;
3. actual funded guarantor payment;
4. junior-position first-loss allocation;
5. loan-specific coverage paid only from the dedicated product-specific pool; and
6. residual senior and junior lender loss.

There is no separate protocol-wide insurance-reserve or safety-module fallback. The
dedicated product pool is the only synthetic coverage source.

The first-slice later-recovery allocation is immutable:

1. authorized recovery costs, fixed at zero in the local product;
2. lender uncovered loss, with senior restoration before junior restoration;
3. product-pool subrogation up to prior coverage payment;
4. guarantor subrogation up to prior guarantee payment; and
5. canonical borrower surplus.

Each receipt and allocation is single-use. A recovery cannot be recorded as both debt
repayment and recovery income, both lender proceeds and reserve replenishment, or both
collateral and guarantor value.

### 9. Durable data, accounting, and reconciliation

Phase 9 uses append-only migrations `000013` through `000015`:

- `000013_resolution_core.sql`: debt snapshots, quotes, refinance, lien handoff,
  replacement-loan activation, restructuring, consent, snapshots, and votes;
- `000014_protection_recovery.sql`: pools, assets, coverage, premium, guarantees,
  losses, claims, adjudication, write-offs, subrogation, receipts, and allocations; and
- `000015_resolution_accounting.sql`: accounting identities, exact journal links,
  reconciliation snapshots, differences, incidents, and release evidence.

Runtime roles are separated for resolution projection, consent verification, claim
adjudication verification, reserve custody projection, recovery receipt verification,
accounting, reconciliation, and release assembly. No runtime role can directly insert
or update authoritative success, claim, payment, write-off, or allocation rows.

Accounting uses the existing chart, including:

- `1310` principal, `1320` interest, `1330` fees, `1340` penalties;
- `1350` recovery and `1360` insurance recoverables;
- `1370` guarantor recoverable;
- `2130` lender repayment, `2310` principal claims, `2370` accrued lender interest
  claims, `2380` refinance funding escrow liability, `2390` refinance refund payable,
  and `2450` claim payable;
- `3210` product-specific risk reserve; `3200` protocol-wide insurance reserve is
  unused and unauthorized in the first product;
- `4130` refinance, `4140` restructuring, and `4300` premium revenue;
- `5300` credit loss and `5360` insurance claim expense;
- `6130` guarantee and `6140` coverage control; and
- `8160` written-off and `8170` recovered-principal control.

Existing `2320` remains the implemented syndicate funding-commitment liability and is
never reinterpreted as accrued lender interest.

Every economic transition has one balanced, immutable, idempotent journal batch linked
to the canonical contract transition and durable evidence. Memorandum coverage or
guarantee entries never masquerade as funded assets.

Reconciliation compares debt components, quote version, escrow, lien owner, old/new
loan states, collateral custody, position snapshot and votes, reserve custody and
stress value, commitments, claims, guarantee payments, loss components, write-off,
subrogation, receipts, allocations, journals, and read models. Differences remain
visible with owner, age, deadline, and evidence.

### 10. Phase 8 residual carry-forward

This boundary creates stable records for:

- `UNI-RESIDUAL-003`: cancellation authorization expiry and safe supersession; and
- `UNI-RESIDUAL-004`: authenticated collateral absence and terminalization.

Registering these items does not resolve them. Phase 9 must not reinterpret a payoff,
refinance, restructure, insurance, write-off, or recovery action as authority to bypass
the Phase 8 destination-tombstone, burn-report, lender-refund, late-collateral, or
borrower-release controls. Any production resolution requires a separate ratified ADR.

### 11. Risks and assumptions

The Phase 9 risk register must include:

- `RISK-PHASE9-001`: stale, incomplete, or manipulated payoff quote;
- `RISK-PHASE9-002`: duplicate senior lien or unsafe collateral handoff;
- `RISK-PHASE9-003`: partial refinance loses funding, payoff, collateral, or proceeds;
- `RISK-PHASE9-004`: old-lender payoff, fee, or borrower proceeds are redirected;
- `RISK-PHASE9-005`: refinance or restructuring replay, griefing, expiry, or refund
  freezes funds, collateral, or votes;
- `RISK-PHASE9-006`: unauthorized amendment, consent forgery, quorum substitution, or
  vote replay;
- `RISK-PHASE9-007`: replacement or modification erases, duplicates, or inflates debt
  or lender rights;
- `RISK-PHASE9-008`: reserve funding, segregation, stress value, or capacity is
  overstated, correlated, or double counted;
- `RISK-PHASE9-009`: an ineligible, duplicate, excessive, or wrong-recipient claim is
  approved or paid;
- `RISK-PHASE9-010`: claim approval, reserve custody, payment, and reconciliation roles
  collude, substitute authority, enable a manual bailout, or spend restricted reserves
  as hidden socialized loss;
- `RISK-PHASE9-011`: waterfall priority or aggregate receipts overpay a creditor or
  double count repayment, collateral, guarantor, insurance, or later recovery;
- `RISK-PHASE9-012`: mocked guarantor, legal, or off-chain evidence fabricates value,
  release, or subrogation;
- `RISK-PHASE9-013`: write-off hides debt, erases rights, or duplicates later recovery;
- `RISK-PHASE9-014`: contracts, durable state, ledger, and solvency metrics diverge
  after retry, restart, or stale writer; and
- `RISK-PHASE9-015`: Phase 9 recovery or emergency authority crosses into Phase 8
  message, bridge-backing, wrapped-token, cancellation, or collateral-release authority.

Final implementation findings remain `CONTROLLED_LOCAL_ONLY`; local controls do not
resolve production risk.

The assumption register must include:

- `ASM-034`: every Phase 9 asset, balance, loan, position, reserve, guarantee, claim,
  recovery, party, key, and provider is synthetic and local;
- `ASM-035`: registered tokens have exact balance-delta behavior with no transfer fee,
  rebase, hook, blacklist, or external freeze;
- `ASM-036`: canonical debt uses deterministic local time and fixed, complete principal,
  accrued-interest, fee, penalty, and credit inputs; all accounting uses one exact
  denomination with no live benchmark, FX, slippage, rounding, tax, legal cost, or
  external provider fee;
- `ASM-037`: refinancing is same-chain and atomic in the initial product, with no
  external settlement or legal-title handoff;
- `ASM-038`: the canonical local lien registry is the only senior-lien authority for the
  synthetic collateral;
- `ASM-039`: the position set is bounded and local, and its immutable snapshot fully
  represents eligible lender amendment rights;
- `ASM-040`: synthetic reserve custody is actually prefunded but available only for the
  registered local policy and creates no real capital or insurance promise;
- `ASM-041`: local policy, claim, guarantee, borrower, and adjudicator evidence is
  synthetic and does not represent production identity, consent, insurance, or legal
  enforceability;
- `ASM-042`: mocked guarantor and off-chain/legal recovery attestations have no value
  until an exact local token receipt is verified;
- `ASM-043`: Anvil verifies local transaction and state-machine mechanics, not
  production consensus, finality, custody, title, or legal priority; and
- `ASM-044`: reserve valuation, stress haircuts, loss facts, and confidence inputs are
  deterministic fixtures, not oracle, actuarial, capital-adequacy, or solvency evidence.

The synthetic signatures covered by `ASM-041` include local position snapshots and
borrower/adjudicator signatures. They are authentic test fixtures within this milestone
only.

### 12. Verification and exit

Tests must prove:

- exact quote equation, expiry, version invalidation, component and recipient binding;
- refinance replay, competing refinance, funding, payoff, lien, activation, proceeds,
  cancellation, expiry, refund, callback, and revert safety;
- no independent double senior lien at any observable state;
- borrower consent, immutable snapshot, one-position-one-vote, quorum, threshold,
  review period, expiry, disclosure, amendment cap, and accounting-delta binding;
- no debt disappearance except an explicit approved concession or write-off;
- exact reserve custody, segregation, stress haircut, commitment, payable, capacity,
  ratio, impairment, and no-double-count reconciliation;
- premium, policy, deductible, percentage, loss, adjudication, beneficiary, payout, and
  policy-limit correctness;
- guarantee commitment versus actual payment separation;
- one loss identity across collateral, guarantor, insurance, write-off, subrogation,
  later receipt, allocation, and borrower surplus;
- all `INV-ACC-001` through `INV-ACC-007`, `INV-AUTH-001` through `INV-AUTH-009`,
  `INV-LOAN-001` through `INV-LOAN-015`, `INV-FUND-001` through `INV-FUND-011`,
  `INV-INT-001` through `INV-INT-012`, `INV-COL-001` through `INV-COL-012`,
  `INV-LIQ-005` through `INV-LIQ-012`, `INV-REFI-001` through `INV-REFI-008`,
  `INV-INS-001` through `INV-INS-009`, `REC-001` through `REC-008`, and
  `LIVE-REFI-001` trace to executable tests or explicit reviewed non-applicability
  evidence and release commitments;
- no duplicate payment, claim, recovery, income, reserve replenishment, or debt credit;
- exact balanced journals, append-only durable replay, stale-writer rejection, runtime
  privilege denial, transaction rollback, crash/restart, and reconciliation;
- randomized interruption and substitution sequences for all five work packages;
- a clean local end-to-end product, exact release evidence, one-command reset, and
  post-reset absence; and
- no production credential, real identity, external provider, public network, real
  asset, real reserve, live insurance promise, enforceable guarantee, legal recovery,
  or real fund.

Phase 9 exits only when all five work packages and all six master-plan exit criteria
pass, no critical or existential synthetic-local risk remains unresolved, all
implementation backlog rows are complete, and a separate exit-review PR passes the
protected Foundation and Security checks.

## Consequences

- A payoff quote is a deterministic view of canonical debt, not a lender invoice.
- A refinance is one funding/payoff/lien/activation transaction, not a sequence of
  operator assertions.
- Restructuring authority comes only from the amendment policy and exact protected
  consent bound at origination.
- Coverage is constrained by actual segregated custody and stress policy.
- A claim approval is not a payment, a guarantee is not a recovery, and a write-off is
  not forgiveness.
- Later recovery follows the original loss rights and cannot be counted twice.
- Safety favors explicit unresolved or disputed state over invented success.

## Explicitly deferred

This ADR does not authorize:

- real reserves, insurance promises, guarantees, indemnities, or loss guarantees;
- legal, court, collection-agency, bankruptcy, repossession, or off-chain enforcement;
- production payment, identity, oracle, servicing, insurer, guarantor, recovery, or
  legal providers;
- public testnet, mainnet, production RPC, production keys, HSM/KMS, custody, or live
  operations;
- real UFT, stablecoins, fiat, collateral, loans, lender or borrower funds, treasury
  assets, user identities, raw personal data, production payment credentials, or legal
  records;
- external or cross-chain lien transfer, non-atomic settlement, title registration, or
  priority conclusions;
- FX, cross-asset coverage, floating external valuation, tax, legal costs, provider
  fees, slippage, rounding, or fee-on-transfer tokens;
- reserve investment, yield, lending, staking, liquidity, leverage, reinsurance, or
  fractional-reserve underwriting;
- discretionary debt confiscation, general governance amendment, unilateral claim
  approval, manual balance correction, administrator rescue, arbitrary reserve
  withdrawal, or hidden socialized loss; or
- production solvency, capital adequacy, accounting, legal, licensing, tax, sanctions,
  audit, actuarial, consumer-protection, formal-verification, penetration-test, SLO,
  monitoring, disaster-recovery, or incident-response conclusions.

Each production capability requires separately ratified legal and architecture
authority, provider due diligence, funded-capital and actuarial analysis, updated threat
and economic-risk models, least-privilege IAM, key ceremony, operational runbooks,
independent audit, and explicit deployment approval.
