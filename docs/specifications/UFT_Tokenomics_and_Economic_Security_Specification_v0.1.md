# UFT Tokenomics and Economic Security Specification

**Document:** UFT Tokenomics and Economic Security Specification  
**Version:** 0.1 — Foundational Economic Baseline  
**Status:** Architecture baseline for simulation, review, and ratification  
**Authority:** Subordinate to the Unified Constitution, ratified protocol invariants, Unified Domain Model, Universal Loan Model and State Machine Specification, and Unified Financial Accounting Specification  
**Applies to:** Unified Coin (UFT), genesis distribution, vesting, governance, staking, protocol fees, burns, liquidity programs, collateral markets, insurance, treasury, cross-chain representations, rewards, and economic-risk controls

---

## 1. Purpose

This specification defines the initial quantitative and behavioral economic model of Unified Coin (`UFT`).

It establishes:

- UFT’s fixed maximum supply and genesis issuance model.
- Allocation percentages and custody destinations.
- Vesting, cliffs, unlock limits, and distribution controls.
- Community, contributor, investor, and public-distribution rules.
- Protocol-fee collection and revenue-allocation policy.
- Permanent burn and buyback controls.
- Security staking, reward funding, cooldowns, and slashing.
- Liquidity incentives and protocol-owned liquidity.
- Governance voting power, thresholds, quorum, and timelocks.
- UFT collateral parameters and systemic-risk limits.
- Insurance and bad-debt capitalization.
- Cross-chain UFT backing and exposure limits.
- Economic-security invariants and required stress tests.

This document does not promise UFT price appreciation, stable value, investment return, protocol revenue, or continuous liquidity. It provides an auditable economic architecture whose assumptions must be tested before production deployment.

---

## 2. Governing Hierarchy

This specification shall be interpreted in the following order:

1. Unified Constitution.
2. Ratified protocol invariants.
3. Unified Domain Model.
4. Universal Loan Model and State Machine Specification.
5. Unified Financial Accounting Specification.
6. This specification.
7. Ratified architecture decision records.
8. Versioned smart-contract and service interfaces.
9. Governance-approved parameters within the bounds defined here.
10. Product configurations and incentive campaigns.

A UFT parameter, governance vote, treasury action, bridge operation, or staking program may not override a higher-authority user protection or active-loan term.

---

# Part I — UFT Monetary Constitution

## 3. Token Identity

| Property | Baseline |
|---|---|
| Name | Unified Coin |
| Symbol | UFT |
| Canonical standard | ERC-20-compatible fungible token |
| Decimals | 18 |
| Canonical home chain | Selected before deployment by ratified ADR |
| Maximum supply | `1,000,000,000 UFT` |
| Genesis issuance | 100% of maximum supply minted once |
| Post-genesis minting | Permanently unavailable |
| Burning | Permitted only from tokens held by an authorized burner or consenting holder |
| Transfer tax | None |
| Ordinary rebasing | None |
| Price peg | None |
| Stablecoin status | UFT is not a stablecoin |
| Governance source | Governance-locked UFT, represented through veUFT |
| Security-staking receipt | sUFT |
| Satellite-chain representation | wUFT or chain-specific canonical wrapper |

The maximum supply is a constitutional ceiling, not a target circulating supply.

## 4. Supply Equations

Let:

```text
G = 1,000,000,000 UFT genesis supply
B(t) = cumulative permanently burned canonical UFT at time t
TS(t) = canonical total supply at time t
```

Then:

```text
TS(t) = G − B(t)
TS(t) ≤ G
```

No reward program, governance proposal, bridge adapter, vesting contract, recovery function, or protocol upgrade may cause `TS(t)` to exceed `G`.

## 5. Circulating Supply

Circulating supply is distinct from total supply.

```text
CirculatingSupply(t) =
    TS(t)
  − UnvestedAllocations(t)
  − RestrictedTreasuryReserves(t)
  − UnreleasedRewardReserves(t)
  − LockedGovernanceUFT(t)
  − SafetyStakedUFT(t)
  − CanonicalBridgeEscrow(t)
  − OtherContractuallyRestrictedUFT(t)
```

The public dashboard shall disclose at minimum:

- Maximum supply.
- Total canonical supply.
- Cumulative burns.
- Circulating supply.
- Unvested supply.
- Treasury-controlled supply by mandate.
- Reward-reserve balance.
- Governance-locked supply.
- Safety-staked supply.
- Bridge-escrow balance.
- Wrapped UFT supply by chain.
- Next 30-day, 90-day, and 365-day scheduled unlocks.

---

# Part II — Genesis Allocation

## 6. Baseline Allocation

The complete genesis supply shall be allocated as follows:

| Allocation | Percentage | UFT Amount | Primary custody |
|---|---:|---:|---|
| Community and ecosystem incentives | 24.0% | 240,000,000 | Ecosystem Incentive Vault |
| Protocol treasury and strategic reserves | 18.0% | 180,000,000 | Treasury Timelock Vault |
| Protocol-security staking rewards | 12.0% | 120,000,000 | Staking Reward Reserve |
| Insurance and bad-debt reserve bootstrap | 10.0% | 100,000,000 | Segregated Insurance Reserve |
| Core contributors and future team | 15.0% | 150,000,000 | Contributor Vesting Vaults |
| Early strategic investors | 10.0% | 100,000,000 | Investor Vesting Vaults |
| Public distribution and IDO | 6.0% | 60,000,000 | Public Distribution Contract |
| Liquidity bootstrap and protocol-owned liquidity | 4.0% | 40,000,000 | Liquidity Mandate Vault |
| Advisors, research, and ecosystem partners | 1.0% | 10,000,000 | Partner Vesting Vaults |
| **Total** | **100.0%** | **1,000,000,000** | — |

## 7. Allocation Principles

1. Every allocation shall be minted directly into a named contract or multisignature-controlled vault, not an unrestricted personal wallet.
2. Every vesting or release contract shall be publicly inspectable.
3. Allocation contracts shall emit release, transfer, cancellation, and beneficiary-change events.
4. Unvested contributor, investor, advisor, or partner allocations shall not vote.
5. Unreleased reward and ecosystem allocations shall not vote.
6. Treasury balances shall not vote unless a specific constitutional governance rule permits neutral delegation; the baseline is no treasury voting.
7. Tokens assigned to insurance may not be spent as ordinary operating capital.
8. Tokens assigned to staking rewards may not be reclassified as treasury inventory without a constitutional-tier governance action.
9. The sum of all allocation vault balances, released allocations, and burns must reconcile to the genesis supply.

## 8. Community and Ecosystem Allocation

The `240,000,000 UFT` community and ecosystem allocation may fund:

- Verified early-user distributions.
- Borrower and lender adoption programs.
- Developer grants.
- Education and financial-literacy initiatives.
- Governance participation incentives.
- Regional access programs.
- Bug bounties and security research.
- Integrator incentives.
- Reputation-linked fee rebates.
- Community-owned product experiments.

### 8.1 Release envelope

- Maximum year-one release: `36,000,000 UFT`.
- Maximum year-two release: `48,000,000 UFT`.
- Maximum annual release from year three onward: `15%` of the remaining vault balance.
- No single campaign may receive more than `2%` of the original community allocation without a higher-tier governance vote.
- Unused annual capacity does not automatically carry forward.

### 8.2 Distribution quality controls

Programs must define:

- Objective and eligible behavior.
- Budget and duration.
- Claim formula.
- Sybil-resistance method.
- Geographic or identity restrictions, where applicable.
- Vesting or delayed claim rules.
- Fraud-recovery mechanism.
- Measurable completion criteria.

## 9. Treasury Allocation

The `180,000,000 UFT` treasury allocation is divided into mandates:

| Treasury mandate | Share of treasury | UFT Amount |
|---|---:|---:|
| Long-term protocol development | 30% | 54,000,000 |
| Strategic ecosystem and integrations | 20% | 36,000,000 |
| Operating runway | 20% | 36,000,000 |
| Emergency and incident response | 10% | 18,000,000 |
| Governance grants and public goods | 10% | 18,000,000 |
| Cross-chain and payment-rail risk reserve | 10% | 18,000,000 |

Treasury mandates are accounting and governance restrictions. A transfer between mandates requires a governance action appropriate to the risk tier.

## 10. Contributor Allocation

The `150,000,000 UFT` contributor allocation applies to founders, employees, and future long-term core contributors.

Baseline vesting:

```text
Cliff: 12 months from Token Generation Event (TGE)
Vesting duration: 48 months total
Release after cliff: monthly linear vesting
Initial unlocked amount at TGE: 0%
Acceleration: prohibited except through disclosed merger, shutdown, or contributor-protection policy approved before grant issuance
```

Additional rules:

- Unvested grants may be cancelled when service ends, subject to the signed grant agreement.
- Reallocated unvested tokens return to the contributor pool, not an individual administrator.
- Beneficiary changes require documented legal and governance authorization.
- Contributor grants shall not vote until vested and governance-locked.

## 11. Investor Allocation

The `100,000,000 UFT` early-investor allocation uses:

```text
Cliff: 12 months from TGE
Vesting duration: 36 months total
Release after cliff: monthly linear vesting
Initial unlocked amount at TGE: 0%
```

No investor side agreement may create:

- Hidden token warrants beyond the fixed supply.
- Preferential governance votes not disclosed publicly.
- Guaranteed protocol revenue.
- Guaranteed liquidity or exit price.
- Senior claim over user collateral.
- Authority to bypass governance or timelocks.

## 12. Public Distribution and IDO

The `60,000,000 UFT` public-distribution allocation shall be divided provisionally as follows:

| Component | UFT Amount | Rule |
|---|---:|---|
| Public IDO | 35,000,000 | Transparent price and allocation rules |
| Community launch claims | 15,000,000 | Eligibility and Sybil controls |
| Market-access and regional participation | 5,000,000 | Capped individual allocations |
| Launch contingency reserve | 5,000,000 | Unused amount returns to treasury or community vault |

Baseline public unlock:

```text
At TGE: 25%
Months 2–7: remaining 75% released monthly and linearly
```

The IDO contract must enforce:

- Per-wallet and, where lawful and practical, per-participant caps.
- Refund rules where the sale does not meet published conditions.
- No administrator ability to alter allocations after finalization.
- Public reconciliation between funds received and UFT distributed.

## 13. Advisors and Partners

The `10,000,000 UFT` partner allocation uses:

```text
Cliff: 6 months
Vesting duration: 30 months
Release: monthly linear after cliff
Milestone condition: may apply to individual grants
```

A grant linked to an integration or deliverable shall contain objective milestone evidence and cancellation rules.

---

# Part III — Launch Circulation and Unlock Controls

## 14. Target Initial Circulating Supply

The target initial circulating supply shall not exceed `8.5%` of genesis supply, or `85,000,000 UFT`, unless a ratified launch amendment provides updated simulation evidence.

A provisional launch composition is:

| Source | Initial circulating amount |
|---|---:|
| Public-distribution TGE unlock | 15,000,000 |
| Community launch incentives | 15,000,000 |
| Liquidity bootstrap | 30,000,000 |
| Ecosystem integrations and market access | 15,000,000 |
| Treasury operational liquidity | 10,000,000 |
| **Maximum initial circulation** | **85,000,000** |

Contributor and investor allocations have no TGE unlock.

## 15. Unlock Concentration Limits

Except for public-distribution schedules disclosed at launch:

- No 30-day period may unlock more than `2.5%` of genesis supply.
- No 90-day period may unlock more than `6%` of genesis supply.
- Any scheduled breach requires a protocol-tier vote and an updated liquidity-impact simulation.
- Vesting releases do not guarantee market liquidity and shall be displayed separately from actual transfers to exchanges.

## 16. Insider Transfer Transparency

Contributor, investor, advisor, and treasury vault transfers shall be indexed and labeled publicly.

The protocol interface shall display:

- Allocation category.
- Original grant.
- Vested amount.
- Claimed amount.
- Remaining amount.
- Next release date.
- Recipient or beneficiary address where public disclosure is appropriate.

---

# Part IV — UFT Utility and Demand Architecture

## 17. Authorized UFT Utilities

UFT may be used for:

1. Governance locking.
2. Protocol-security staking.
3. Loan principal and repayment where voluntarily selected.
4. Approved loan collateral.
5. Unified protocol fees.
6. Governance proposal bonds.
7. Insurance and guarantee capitalization.
8. Liquidity provision.
9. Marketplace deposits and anti-spam bonds.
10. Cross-chain settlement and representations.
11. Premium services and API plans.
12. Secondary-market settlement.
13. Developer, validator, oracle, or attester security bonds.
14. Community and reputation incentives.

No product may require UFT solely to manufacture artificial demand where another asset is economically necessary for the user’s underlying transaction.

## 18. Utility Separation

UFT may perform several compatible functions, but the system must prevent double counting.

Examples:

- UFT in a user wallet is liquid but creates no direct vote until governance-locked.
- UFT in a collateral vault secures debt and cannot simultaneously vote.
- UFT in bridge escrow backs wUFT and cannot simultaneously circulate on the home chain.
- UFT in a staking vault backs defined protocol risks; the corresponding sUFT represents the depositor’s claim.
- Unvested UFT is allocated but neither liquid nor votable.

---

# Part V — Protocol Fees and Revenue Routing

## 19. Fee Principles

1. Unified shall not impose an automatic tax on ordinary UFT transfers.
2. Protocol fees shall be explicit and linked to a service or transaction.
3. Third-party bank, card, bridge, network-gas, or payment-provider costs shall be distinguished from net protocol revenue.
4. Fee rates applicable to an active loan shall be fixed by the accepted agreement or its versioned policy.
5. Governance may change fee schedules for future actions but not retroactively.
6. Fees shall be recorded through the Unified Financial Accounting Specification.

## 20. Baseline Fee Envelope

The following are maximum protocol-level baseline ranges, not mandatory fees:

| Fee category | Baseline range or cap |
|---|---|
| Loan origination | 0.25%–1.50% of principal |
| Loan servicing | 0%–0.50% annually or fixed disclosed fee |
| Secondary-market trade | 0.10%–0.75% of trade value |
| Refinancing | 0.10%–1.00% of refinanced principal |
| Liquidation protocol fee | 0%–2.00% of realized collateral proceeds, excluding liquidator incentive |
| Cross-chain coordination | Cost plus up to 0.30% |
| Exchange routing | 0%–0.30% excluding venue fees |
| Premium features | Fixed subscription or disclosed usage pricing |
| Governance proposal bond | Parameterized UFT bond; refundable under policy |

Any fee above the baseline cap requires an economic-tier governance proposal and a documented user-impact analysis.

## 21. Net Protocol Revenue Split

The baseline split of **net protocol revenue**, after direct third-party costs and user refunds, is:

| Destination | Baseline share |
|---|---:|
| Insurance and bad-debt reserves | 30% |
| UFT security stakers | 25% |
| Protocol treasury | 25% |
| Permanent UFT burn or buyback-and-burn | 10% |
| Protocol-owned liquidity | 5% |
| Community and developer public goods | 5% |
| **Total** | **100%** |

## 22. Revenue-Split Bounds

Governance may modify the split only within these bounds:

| Destination | Minimum | Maximum |
|---|---:|---:|
| Insurance and bad-debt reserves | 20% | 50% |
| Security stakers | 10% | 35% |
| Treasury | 15% | 40% |
| Burn or buyback-and-burn | 0% | 20% |
| Protocol-owned liquidity | 0% | 15% |
| Public goods | 0% | 15% |

The percentages must always total `100%`.

The insurance share may not fall below `30%` while any system-wide reserve-coverage ratio is below its approved target.

## 23. Fee Payment Assets

Users may pay protocol fees in:

- UFT.
- The loan principal asset.
- An approved stable settlement asset.
- Another approved asset routed through the Payment Router.

Where an asset conversion is required, the user must receive a quote showing:

- Input asset and amount.
- Expected output.
- Price source.
- Maximum slippage.
- Third-party costs.
- Protocol fee.
- Quote expiration.

---

# Part VI — Burn and Buyback Policy

## 24. Direct UFT Burn

When net protocol revenue is received in UFT, the burn allocation may be transferred to the canonical `UFTBurner` and permanently destroyed.

Every burn shall emit:

```text
UFTBurned(
  amount,
  sourceRevenuePeriod,
  sourceAsset,
  executionReference,
  cumulativeBurnedSupply,
  resultingTotalSupply
)
```

## 25. Buyback-and-Burn

Where revenue is received in another asset, the burn allocation may be used to purchase UFT through approved venues.

Execution controls:

- Maximum daily buyback: lesser of `0.05%` of circulating supply or `10%` of trailing 30-day average legitimate market volume.
- Maximum price impact per transaction: `0.75%`.
- Maximum oracle deviation: `1.50%` from the approved reference price.
- Time-weighted execution is required for orders above the defined small-order threshold.
- At least two approved liquidity venues must be considered where available.
- Buyback execution may pause during oracle, bridge, or market-integrity incidents.

## 26. Burn Suspension

Burns shall be suspended automatically where:

- Insurance capitalization is below its minimum floor.
- The protocol has unresolved material bad debt.
- A bridge-backing deficit exists.
- The treasury runway is below the approved emergency minimum.
- Governance has activated a constitutional emergency reserve mode.

Suspended burn allocations shall remain in a segregated reserve until governance determines a lawful destination within the revenue-split bounds.

## 27. No Appreciation Promise

All UFT documents and interfaces shall state:

> Token burns reduce canonical total supply but do not guarantee price appreciation, liquidity, demand, or preservation of purchasing power.

---

# Part VII — Protocol-Security Staking

## 28. Staking Architecture

Users deposit canonical UFT into the `UFTStakingVault` and receive `sUFT` shares representing a proportional claim on accounted vault assets.

The vault should use an ERC-4626-compatible share model. Because safety-module withdrawals may be delayed, the implementation shall support asynchronous redemption or an equivalent request queue.

## 29. Covered Risks

Security stake may be used under a ratified loss policy to absorb losses arising from:

- Unsecured-loan defaults assigned to a covered risk pool.
- Liquidation shortfalls.
- Approved oracle failures.
- Approved bridge failures.
- Approved payment-provider settlement failures.
- Card chargebacks allocated to a covered reserve.
- Protocol-contract failure where insurance coverage applies.
- Fraud by a bonded attester, operator, or service provider.

Security staking does not automatically guarantee every user loss.

## 30. Reward Sources

Staking rewards may come only from:

1. The pre-minted `120,000,000 UFT` staking reward reserve.
2. The staker share of net protocol revenue.
3. Defined insurance or risk premiums.
4. Liquidation penalties allocated to the safety module.
5. Slashed bonds or stake redistributed under policy.
6. Governance-approved treasury transfers within mandate.

Rewards cannot be created through post-genesis minting.

## 31. Reward-Reserve Release

Maximum emissions from the pre-minted staking reward reserve:

| Period | Maximum UFT release |
|---|---:|
| Year 1 | 18,000,000 |
| Year 2 | 15,000,000 |
| Year 3 | 12,000,000 |
| Year 4 | 10,000,000 |
| Year 5 | 8,000,000 |
| Year 6 onward | Maximum 10% of remaining reserve annually |

Unused annual capacity remains in the reserve and does not automatically increase the next year’s cap.

## 32. Reward Formula

For staking epoch `e`:

```text
RewardPool(e) =
    FundedEmission(e)
  + AllocatedProtocolRevenue(e)
  + AllocatedRiskPremiums(e)
  + AllocatedSlashingProceeds(e)
```

For participant `i`:

```text
ParticipantReward(i,e) =
  RewardPool(e)
  × TimeWeightedEligibleShares(i,e)
  ÷ TotalTimeWeightedEligibleShares(e)
```

Interfaces may display historical or projected annualized yield but shall not represent an unfunded projection as guaranteed.

## 33. Staking Cooldown and Withdrawal

Baseline withdrawal rules:

```text
Minimum stake age before ordinary withdrawal request: 7 days
Cooldown after request: 14 days
Claim window after cooldown: 7 days
Unclaimed request after window: returns to active stake
Emergency extension: up to 30 additional days under declared covered incident
```

A pending withdrawal remains subject to losses arising from incidents that occurred before the withdrawal request’s effective cutoff, according to the ratified loss policy.

## 34. Slashing

Baseline slashing rules:

- No slash without a defined covered event and verifiable evidence.
- Maximum ordinary slash per incident: `10%` of eligible staked assets.
- Maximum aggregate slash in a rolling 90-day period: `25%`.
- A constitutional emergency proposal may authorize a higher amount only where required to satisfy a previously disclosed safety guarantee.
- Slashing shall be proportional unless a participant’s own misconduct justifies targeted bond slashing.
- Slash proceeds shall follow the covered-loss waterfall and may not become ordinary protocol revenue.

## 35. sUFT Use as Collateral

sUFT may be approved as collateral only where:

- Its redemption and loss exposure are clearly disclosed.
- The oracle values its redeemable underlying claim, not a speculative secondary-market premium.
- A haircut accounts for cooldown, slashing, and liquidity risk.
- The same underlying UFT is not also counted as freely available safety capital for the same obligation.

Baseline sUFT collateral haircut: `25%` relative to redeemable underlying value, subject to stricter market-specific limits.

---

# Part VIII — Liquidity Incentives and Protocol-Owned Liquidity

## 36. Liquidity Bootstrap Allocation

The `40,000,000 UFT` liquidity allocation is divided:

| Purpose | UFT Amount |
|---|---:|
| Initial protocol-owned liquidity | 25,000,000 |
| Market-maker and venue mandates | 5,000,000 |
| Liquidity-gauge incentives | 8,000,000 |
| Cross-chain liquidity bootstrap | 2,000,000 |

## 37. Protocol-Owned Liquidity

Protocol-owned liquidity (`POL`) belongs to the treasury under a restricted liquidity mandate.

POL objectives include:

- Persistent UFT market depth.
- Liquidation support.
- Reduced dependence on perpetual token emissions.
- Treasury fee generation.
- Cross-chain liquidity support.

POL may not be used to create artificial volume or misleading market activity.

## 38. Approved Initial Pool Classes

- UFT / approved stablecoin.
- UFT / canonical network asset.
- UFT / approved regional stable settlement asset.
- UFT / selected lender-position assets.
- Canonical UFT / wUFT reconciliation pools where necessary.

## 39. Liquidity Incentive Controls

- Maximum year-one gauge incentives: `4,000,000 UFT`.
- Maximum per-pool share: `35%` of an epoch budget.
- Reward epochs: 28 days.
- Time-weighted liquidity is required.
- Wash volume and self-trading do not qualify.
- A pool must meet oracle, liquidity, audit, and market-integrity requirements.
- Incentives stop automatically when the pool becomes unsupported or materially unsafe.

## 40. Liquidity Concentration Targets

At launch, no single external venue should custody or control more than `40%` of UFT’s approved protocol-supported liquidity. The target after the first operational year is no more than `30%` on one venue, subject to actual market availability.

---

# Part IX — Governance Economics

## 41. Governance Voting Asset

Liquid UFT does not vote directly.

Users lock vested and eligible UFT to receive non-transferable `veUFT` voting power. Voting power uses checkpointed historical balances and delegation.

Baseline rule:

```text
1 eligible UFT locked = 1 base unit of veUFT voting power
```

Lock duration does not multiply base voting power in v0.1. Longer locks may receive non-voting benefits, but a duration multiplier requires constitutional review because it may concentrate governance.

## 42. Governance Lock

```text
Minimum lock: 30 days
Maximum lock: 4 years
Minimum remaining lock to create a proposal: voting delay + voting period + applicable timelock
veUFT transferability: none
Delegation: permitted
Early withdrawal: prohibited except through a pre-ratified emergency mechanism
```

## 43. Proposal Classes

### 43.1 Community proposal

Examples:

- Grants.
- Education campaigns.
- Non-critical interface priorities.

Parameters:

```text
Proposal threshold: 0.05% of eligible veUFT supply
Voting delay: 2 days
Voting period: 7 days
Quorum: 4%
Approval: simple majority
Timelock: 2 days
```

### 43.2 Economic proposal

Examples:

- Fee split changes.
- Liquidity-gauge budgets.
- Staking reward policy.
- Treasury mandate allocations.

Parameters:

```text
Proposal threshold: 0.10%
Voting delay: 3 days
Voting period: 10 days
Quorum: 8%
Approval: at least 55% of votes cast
Timelock: 5 days
```

### 43.3 Risk proposal

Examples:

- UFT collateral ratios.
- Debt ceilings.
- Oracle additions.
- Insurance coverage.
- Bridge exposure.

Parameters:

```text
Proposal threshold: 0.15%
Voting delay: 4 days
Voting period: 12 days
Quorum: 12%
Approval: at least 60% of votes cast
Timelock: 7 days
Required review: Risk Council opinion published before voting closes
```

### 43.4 Protocol proposal

Examples:

- New core implementation versions.
- Treasury authority changes.
- New settlement or bridge adapters with asset-moving powers.

Parameters:

```text
Proposal threshold: 0.25%
Voting delay: 7 days
Voting period: 14 days
Quorum: 15%
Approval: at least 66.67% of votes cast
Timelock: 14 days
Required review: security assessment and implementation hash
```

### 43.5 Constitutional proposal

Examples:

- Amendment of constitutional economic protections.
- Change to fixed-supply enforcement architecture.
- Change to governance structure.

Parameters:

```text
Proposal threshold: 0.50%
Voting delay: 14 days
Voting period: 21 days
Quorum: 25%
Approval: at least 75% of votes cast
Timelock: 30 days
Required review: public constitutional impact report and independent security review
```

The maximum UFT supply cannot be increased even through a constitutional proposal unless a future constitution explicitly replaces the existing system through a migration in which users voluntarily choose whether to participate. The canonical UFT contract itself remains non-mintable.

## 44. Late-Quorum Protection

Where quorum is reached near the end of voting, the voting period shall be extended by at least 48 hours to reduce last-minute governance capture.

## 45. Proposal Bonds

A proposal class may require a refundable UFT bond.

The bond may be partly or fully forfeited only for objectively defined cases such as:

- Malicious executable payload.
- Proven spam repetition.
- Deliberate misrepresentation of the proposal’s execution target.

A defeated good-faith proposal shall not lose its bond solely because it failed.

## 46. Governance Capture Controls

1. Checkpointed voting power prevents post-snapshot token reuse.
2. Treasury, unvested, collateralized, bridged, and unreleased reserve UFT cannot generate duplicate votes.
3. A single delegate’s displayed voting concentration must be public.
4. When one delegate controls more than `20%` of active veUFT, the interface shall display a concentration warning.
5. Constitutional proposals require participation from at least `100` distinct voting addresses or an updated Sybil-resistant participation threshold approved before proposal creation.
6. Governance may add a quadratic advisory poll, but binding execution remains based on the ratified on-chain voting rule unless constitutionally amended.

## 47. Initial Governance Transition

Unified may begin with a guarded launch council while token distribution and operational maturity develop.

Transition stages:

```text
Stage 0: Deployment multisignature with narrow launch powers
Stage 1: Governor active; multisignature retains bounded emergency pause
Stage 2: Timelock controls protocol authorities; council becomes elected Risk and Emergency Councils
Stage 3: Full constitutional governance with independently administered oversight roles
```

Each stage requires published exit criteria. The launch council may not mint UFT, seize user assets, or rewrite active loans.

---

# Part X — UFT as Collateral

## 48. UFT Collateral Market

UFT shall operate in an isolated collateral-risk category during its initial production period.

It may secure loans denominated in approved assets, subject to market-specific limits.

## 49. Baseline UFT Collateral Parameters

| Parameter | Baseline |
|---|---:|
| Maximum initial loan-to-value (`LTV`) | 35% |
| Maintenance LTV | 45% |
| Liquidation threshold | 50% |
| Target post-liquidation LTV | 35% |
| Liquidation bonus range | 5%–12% |
| Maximum single-loan UFT collateral exposure | 0.25% of circulating UFT supply |
| Maximum borrower UFT collateral exposure | 0.50% of circulating UFT supply |
| Protocol-wide UFT-backed debt ceiling | Lesser of 7.5% of circulating UFT market capitalization or approved liquidity-adjusted ceiling |
| Oracle maximum staleness | 30 minutes under normal operation |
| Minimum independent price sources | 3 where available |
| Maximum source deviation before circuit breaker | 7.5% |

These are conservative launch parameters, not permanent values.

## 50. Dynamic Collateral Formula

```text
RequiredInitialCollateralRatio = clamp(
  MinimumRatio,
  MaximumRatio,
  BaseRatio
  + VolatilityAddOn
  + LiquidityAddOn
  + ConcentrationAddOn
  + MarketStressAddOn
  + CrossChainAddOn
  − ReputationAdjustment
)
```

Baseline bounds:

```text
MinimumRatio = 200% collateral value relative to debt
MaximumRatio = 500%
Maximum reputation reduction = 20 percentage points
```

Reputation may reduce the origination requirement but may not lower the liquidation threshold for an active loan.

## 51. Oracle Requirements

The UFT oracle shall use:

- Multiple approved venues.
- Time-weighted prices.
- Liquidity-depth checks.
- Staleness checks.
- Outlier rejection.
- Circuit breakers.
- A documented fallback hierarchy.

A single low-liquidity pool may not determine the value of all UFT collateral.

## 52. Reflexivity Controls

Because Unified distress may reduce UFT value while UFT secures Unified loans, the protocol shall apply:

- Isolated debt ceilings.
- Conservative LTV.
- Concentration caps.
- Partial liquidation where safe.
- Auction liquidation during stressed liquidity.
- Buyback suspension during reserve deficits.
- Higher insurance targets for UFT-backed credit.
- Prohibition on counting UFT collateral value as insurance reserve capital for the same correlated risk.

## 53. UFT-to-UFT Loans

A loan whose principal and collateral are both UFT shall be disabled by default because it normally creates circular economic exposure without meaningful collateral diversification. A specialized product requires a separate risk policy and explicit purpose.

---

# Part XI — Insurance and Bad-Debt Capitalization

## 54. Bootstrap Insurance Reserve

The genesis allocation provides `100,000,000 UFT` to the segregated insurance reserve.

Because UFT is correlated with protocol risk, the reserve shall diversify over time into approved stable and high-liquidity assets.

## 55. Diversification Targets

Measured by conservative risk-adjusted value:

| Operational stage | Maximum UFT share of insurance reserve |
|---|---:|
| Pre-revenue launch | 100%, with explicit limitation disclosure |
| After first 12 months or adequate liquidity | 70% |
| Mature target | 40% |

Protocol revenue routed to insurance should preferentially build non-UFT reserve assets until diversification targets are met.

## 56. Reserve Coverage Ratio

```text
ReserveCoverageRatio =
  EligibleRiskAdjustedReserveAssets
  ÷
  ModeledCoveredLossAtTargetConfidence
```

Target zones:

| Ratio | Status | Required response |
|---|---|---|
| `≥ 1.50` | Strong | Normal operation |
| `1.20–1.49` | Adequate | Standard monitoring |
| `1.00–1.19` | Constrained | Higher insurance revenue allocation; incentive review |
| `0.75–0.99` | Deficient | Burn suspended; new covered exposure restricted |
| `< 0.75` | Critical | Emergency risk reduction and governance response |

## 57. Loss Waterfall

Unless a product defines a stricter disclosed waterfall:

```text
1. Loan-specific collateral and recoveries
2. Borrower or originator reserve
3. Guarantor stake
4. Junior tranche or first-loss capital
5. Product-specific reserve
6. Insurance reserve
7. Eligible protocol-security stake
8. Senior lender loss
```

No layer may be represented as guaranteed beyond funded and legally available assets.

---

# Part XII — Cross-Chain UFT

## 58. Canonical Supply Model

Canonical UFT exists on one home chain.

Satellite-chain UFT must be backed through:

```text
Canonical UFT locked in bridge escrow
→ verified cross-chain message
→ equivalent wUFT issued on satellite chain
```

## 59. Backing Invariants

For chain `c`:

```text
WrappedSupply(c) ≤ CanonicalBackingEscrow(c)
```

Globally:

```text
Σ WrappedSupply(all chains)
≤ TotalCanonicalUFTLockedForBridging
```

No message failure, replay, governance action, or adapter upgrade may create unbacked wUFT.

## 60. Bridge Exposure Limits

At launch:

- Maximum UFT backing in any one bridge: `5%` of canonical circulating supply.
- Maximum aggregate UFT in all bridge escrows: `15%` of canonical circulating supply.
- A bridge must pass technical, economic, operational, and governance review.
- An adapter’s exposure limit is independent from the underlying chain’s limit.
- Exposure increases require a risk proposal and bridge stress analysis.

## 61. Cross-Chain Burns

When wUFT is permanently burned on a satellite chain:

1. The satellite burn is finalized.
2. A verified burn message is submitted to the home chain.
3. The corresponding canonical backing is burned or permanently removed according to policy.
4. Global supply accounting is reconciled.

Burning wUFT without reconciling canonical backing does not reduce canonical total supply.

## 62. Cross-Chain Governance

A unit of UFT may vote on only one governance domain for a given snapshot.

Remote voting requires:

- Lock or immobilization of the satellite representation.
- A verified voting-power commitment.
- Replay protection.
- Snapshot alignment.
- Prevention of simultaneous home-chain and satellite voting.

---

# Part XIII — Market Integrity and Anti-Manipulation

## 63. Prohibited Protocol Conduct

Unified-controlled actors and contracts shall not:

- Manufacture false trading volume.
- Conceal treasury market transactions.
- Misstate burns, circulating supply, or reserve backing.
- Use undisclosed wallets to manipulate governance or market prices.
- Promise guaranteed token appreciation.
- Represent incentive emissions as organic protocol revenue.
- Use user collateral for market support without contractual authority.
- Treat unfinalized bridge or payment assets as available reserves.

## 64. Treasury Market Operations

Treasury purchases, sales, liquidity deployment, or market-maker mandates must define:

- Maximum amount.
- Execution period.
- Approved venues.
- Price and slippage bounds.
- Counterparty requirements.
- Reporting frequency.
- Conflict-of-interest controls.
- Emergency stop conditions.

## 65. Market-Maker Mandates

A market maker may receive inventory or credit only through a public mandate containing:

- Inventory ownership.
- Recall rights.
- Permitted venues.
- Spread and depth objectives.
- Prohibited conduct.
- Reporting requirements.
- Collateral or bond requirements.
- Loss allocation.
- Termination rights.

---

# Part XIV — Economic Security Invariants

## 66. Supply Invariants

1. Canonical UFT total supply never exceeds `1,000,000,000 UFT`.
2. The canonical token has no post-genesis mint function or mint authority.
3. Burns are permanent and reduce canonical total supply.
4. Wrapped UFT does not increase canonical economic supply because it is fully backed by locked canonical UFT.
5. Vesting releases change circulating supply but not total supply.
6. Reward distributions cannot exceed funded reward balances.

## 67. Allocation Invariants

7. Genesis allocations total exactly 100%.
8. Unvested tokens cannot be claimed before schedule.
9. Unreleased allocation tokens cannot vote.
10. Insurance assets cannot be silently reclassified as ordinary treasury assets.
11. Staking reward reserves cannot fund unrelated operations without the required governance tier.
12. Every allocation movement is auditable and reconcilable.

## 68. Governance Invariants

13. Liquid wallet balances do not vote directly.
14. veUFT is non-transferable.
15. Voting uses historical checkpoints.
16. One underlying UFT cannot create duplicate voting power.
17. Treasury, collateralized, unvested, and bridge-escrow UFT do not vote by default.
18. Successful proposals execute through the applicable timelock.
19. Governance cannot change active-loan economics.
20. Governance cannot mint beyond the fixed supply.

## 69. Staking Invariants

21. Every sUFT share is backed by accounted staking-vault assets.
22. Rewards are funded before distribution.
23. Slashing requires a defined covered event.
24. Slash proceeds follow a covered-loss waterfall.
25. Pending withdrawals follow the disclosed incident-cutoff policy.
26. Staked UFT cannot simultaneously be treated as unrestricted treasury capital.

## 70. Fee and Burn Invariants

27. Revenue routing applies only to net protocol revenue.
28. Third-party costs and user refunds are not burnable revenue.
29. Revenue-split percentages always equal 100%.
30. User principal and collateral cannot be burned as protocol revenue.
31. Burn execution is independently auditable.
32. Burn suspends under defined reserve-deficiency conditions.

## 71. Collateral and Reserve Invariants

33. UFT collateral uses approved fresh prices and risk limits.
34. Aggregate UFT-backed debt remains below its approved ceiling.
35. Reputation cannot remove minimum liquidation protections.
36. Insurance coverage cannot exceed funded and eligible resources.
37. Correlated UFT reserve value is haircut appropriately.
38. Collateral and reserve assets are not counted twice.

## 72. Cross-Chain Invariants

39. Wrapped supply does not exceed canonical backing.
40. Every cross-chain mint or release consumes one unique verified message.
41. Bridge failures cannot create duplicate UFT.
42. A bridged unit cannot vote simultaneously on multiple chains.
43. Cross-chain burns reconcile against canonical backing.
44. Bridge exposure remains within approved limits.

---

# Part XV — Required Economic Simulations

## 73. Simulation Program

No production launch shall occur until the following simulations have been implemented and reviewed.

### 73.1 Supply and unlock simulation

Model at least 10 years with:

- Every allocation and vesting schedule.
- Expected and maximum claims.
- Burns.
- Reward releases.
- Treasury distributions.
- Governance locks.
- Bridge locks.
- Staking participation.

Outputs:

- Monthly total supply.
- Monthly circulating supply.
- Unlock pressure.
- Holder concentration.
- Treasury runway.
- Reward-reserve runway.

### 73.2 Revenue sensitivity

Scenarios:

- Zero protocol revenue for 36 months.
- Low adoption.
- Base adoption.
- High adoption.
- Revenue collapse after rapid growth.

Outputs:

- Staker yield funded by emissions versus revenue.
- Insurance capitalization.
- Treasury runway.
- Burn volume.
- Required expense reductions.

### 73.3 UFT price stress

Required shocks:

```text
−30% in 24 hours
−50% in 7 days
−80% in 30 days
−95% sustained decline
```

Model:

- UFT collateral liquidations.
- Insurance reserve impairment.
- sUFT redemption pressure.
- Liquidity depth.
- Slippage.
- Governance participation.
- Bridge exits.
- Treasury solvency.

### 73.4 Liquidity stress

Model:

- 70% reduction in normal trading depth.
- One major venue failure.
- Market-maker withdrawal.
- Stablecoin pair impairment.
- Cross-chain liquidity fragmentation.
- Liquidations equal to 5%, 10%, and 20% of circulating UFT.

### 73.5 Governance concentration

Model:

- Top 1, 5, 10, and 20 holders.
- Delegate concentration.
- Voter turnout between 2% and 40%.
- Bribery and vote-rental assumptions.
- Late-quorum attack.
- Treasury or insider collusion.
- Cross-chain vote duplication attempts.

### 73.6 Staking and slashing

Model:

- 10%, 25%, 50%, and 70% staking participation.
- Multiple incidents in one quarter.
- Maximum ordinary slash.
- Withdrawal queue congestion.
- Reward reserve depletion.
- Revenue-free periods.

### 73.7 Insurance and bad debt

Model:

- Unsecured-loan defaults.
- NFT liquidation shortfall.
- Bridge loss.
- Payment-provider failure.
- Card chargebacks.
- Correlated borrower defaults.
- Correlated UFT price decline and insurance impairment.

### 73.8 Cross-chain failure

Model:

- Delayed messages.
- Duplicate messages.
- Compromised relayer.
- Bridge insolvency.
- Satellite-chain reorganization.
- Emergency bridge shutdown.
- 100% loss of one bridge’s exposed assets.

## 74. Launch Economic Gates

Production launch requires evidence that:

1. The token allocation reconciles exactly to maximum supply.
2. Initial circulating supply remains within the ratified cap.
3. Treasury has at least 24 months of conservative operating runway, excluding user assets and restricted insurance funds.
4. Staking rewards remain funded for at least 36 months under the zero-revenue scenario at the launch emission policy.
5. The insurance reserve meets the launch coverage target for enabled insured products.
6. UFT collateral liquidation can occur under the `−50% / 7-day` scenario without projected unrecoverable protocol insolvency.
7. No single bridge breach within approved limits creates unbounded canonical supply or protocol-wide insolvency.
8. Governance thresholds resist the modeled realistic concentration profile.
9. The maximum scheduled 30-day unlock remains inside the unlock cap.
10. Every public tokenomic claim is reproducible from contracts and ledger records.

Failure of a gate requires a parameter revision, scope control, added capitalization, or explicit ratified risk acceptance. It may not be hidden through optimistic assumptions.

---

# Part XVI — Parameter Governance

## 75. Immutable Parameters

The following are immutable for canonical UFT v0.1:

- Maximum supply of `1,000,000,000 UFT`.
- One-time genesis mint.
- Absence of post-genesis mint authority.
- Non-rebasing design.
- No automatic transfer tax.
- Burns cannot be reversed.

## 76. Constitutional Parameters

Changes require a constitutional proposal:

- Allocation category percentages before deployment.
- Governance architecture.
- Whether treasury or restricted balances may vote.
- Fundamental staking-loss rights.
- Bridge-backing model.
- Core user-asset protections.

After genesis mint, allocation percentages describe historical issuance and cannot be rewritten; governance may only transfer permitted remaining balances under mandate.

## 77. Risk Parameters

Changes require a risk proposal:

- UFT LTV and liquidation threshold.
- Debt ceilings.
- Oracle rules.
- Bridge exposure.
- Insurance coverage targets.
- Slashing incident caps within constitutional limits.

## 78. Economic Parameters

Changes require an economic proposal:

- Revenue split within bounds.
- Reward epochs and budgets within funded reserves.
- Liquidity gauge allocation.
- Treasury mandate budgets.
- Fee rates within caps.

## 79. Operational Parameters

Bounded operational authorities may adjust:

- Approved execution venues within a ratified registry.
- Small buyback scheduling.
- Reward-claim processing windows.
- Market-maker inventory within mandate.
- Emergency pauses.

Every operational adjustment must be public, bounded, and reversible by governance.

---

# Part XVII — Contract and Service Requirements

## 80. Required UFT Contracts

```text
UnifiedToken
GenesisDistributionVault
ContributorVestingVault
InvestorVestingVault
PartnerVestingVault
CommunityIncentiveVault
TreasuryTimelockVault
InsuranceReserveVault
StakingRewardReserve
ProtocolFeeRouter
UFTBurner
BuybackExecutor
UFTStakingVault
WithdrawalQueue
SlashingController
VoteEscrowUFT
UnifiedGovernor
GovernanceTimelock
LiquidityGaugeController
ProtocolOwnedLiquidityManager
UFTCollateralAdapter
UFTOracleAdapter
UFTBridgeHub
BridgeEscrow
WrappedUFT
CrossChainSupplyController
```

## 81. Required Services

```text
Token Supply Indexer
Vesting and Unlock Monitor
Treasury Accounting Service
Governance Indexer
Reward Epoch Processor
Staking Risk Monitor
Insurance Coverage Monitor
UFT Collateral Risk Engine
Liquidity and Market Integrity Monitor
Buyback Execution Service
Bridge Backing Reconciler
Economic Simulation Service
Public Tokenomics Dashboard
```

## 82. Required Events

At minimum:

```text
GenesisMinted
AllocationFunded
VestingGrantCreated
TokensVested
TokensClaimed
TreasuryMandateTransfer
ProtocolFeeCollected
RevenueAllocated
UFTBurned
BuybackExecuted
UFTStaked
WithdrawalRequested
WithdrawalClaimed
StakeSlashed
RewardFunded
RewardDistributed
GovernanceLockCreated
VoteDelegated
ProposalCreated
ProposalQueued
ProposalExecuted
LiquidityIncentiveAllocated
CollateralParameterUpdated
BridgeBackingLocked
WrappedUFTMinted
WrappedUFTBurned
CanonicalBackingReleased
InsuranceReserveFunded
InsuranceReserveUsed
```

---

# Part XVIII — Disclosure Requirements

## 83. Public Tokenomics Dashboard

The public dashboard shall expose:

- Fixed maximum supply.
- Current canonical total supply.
- Cumulative burned supply.
- Circulating supply methodology.
- Allocation balances.
- Vesting schedules and upcoming unlocks.
- Treasury mandate balances.
- Insurance reserve composition and coverage ratio.
- Staking reserve balance and emissions.
- Staking participation and withdrawal queue.
- Governance-locked supply and delegate concentration.
- Protocol revenue and its allocation.
- Buyback and burn history.
- Protocol-owned liquidity.
- UFT collateral exposure and debt ceiling utilization.
- Bridge backing by chain and adapter.

## 84. Risk Disclosures

Users shall be informed that:

- UFT may lose substantial or all market value.
- Fixed supply does not ensure appreciation.
- Burns do not guarantee demand.
- Staking rewards vary and staking may be slashed.
- sUFT may be less liquid than UFT.
- UFT collateral can be liquidated.
- Governance outcomes may be unfavorable to an individual holder.
- Cross-chain representations create bridge risk.
- Protocol insurance is limited to funded and covered events.
- Fiat conversion depends on third-party providers.

---

# Part XIX — Baseline Parameter Registry

## 85. Parameter Summary

| Parameter | v0.1 baseline |
|---|---:|
| Maximum UFT supply | 1,000,000,000 |
| Community and ecosystem | 24% |
| Treasury and strategic reserves | 18% |
| Staking reward reserve | 12% |
| Insurance bootstrap | 10% |
| Contributors | 15% |
| Investors | 10% |
| Public distribution | 6% |
| Liquidity bootstrap | 4% |
| Advisors and partners | 1% |
| Target maximum initial circulation | 8.5% |
| Contributor vesting | 12-month cliff, 48 months total |
| Investor vesting | 12-month cliff, 36 months total |
| Partner vesting | 6-month cliff, 30 months total |
| Baseline insurance revenue share | 30% |
| Baseline staker revenue share | 25% |
| Baseline treasury revenue share | 25% |
| Baseline burn share | 10% |
| Baseline POL share | 5% |
| Baseline public-goods share | 5% |
| Minimum governance lock | 30 days |
| Maximum governance lock | 4 years |
| UFT maximum initial LTV | 35% |
| UFT maintenance LTV | 45% |
| UFT liquidation threshold | 50% |
| Maximum bridge exposure per bridge | 5% of circulating supply |
| Maximum aggregate bridge exposure | 15% of circulating supply |
| Ordinary staking cooldown | 14 days |
| Maximum ordinary slash per incident | 10% |
| Maximum aggregate 90-day ordinary slash | 25% |

---

# Part XX — Ratification Checklist

## 86. Required Review Before Ratification

- [ ] Supply and allocation arithmetic independently verified.
- [ ] Vesting contracts specified and modeled.
- [ ] Ten-year circulating-supply simulation completed.
- [ ] Treasury runway modeled under zero-revenue and low-revenue conditions.
- [ ] Staking reward reserve modeled for at least ten years.
- [ ] Governance concentration modeled using expected holder distribution.
- [ ] UFT collateral stress tested through a 95% price decline.
- [ ] Insurance reserve diversification plan approved.
- [ ] Bridge exposure and backing model reviewed.
- [ ] Fee and revenue accounting reconciles with the Financial Accounting Specification.
- [ ] Public claims reviewed for accuracy and absence of guaranteed-return language.
- [ ] Smart-contract threat model completed.
- [ ] Independent economic review completed.
- [ ] Independent smart-contract audit completed before production deployment.

---

# Appendix A — Initial Unlock Illustration

The following is an illustrative schedule and must be replaced by generated monthly simulation output before launch.

```text
TGE
- Public distribution unlocks partially.
- Liquidity bootstrap is funded.
- Limited community launch programs begin.
- Contributor and investor allocations remain fully locked.

Months 2–7
- Remaining public-distribution allocation unlocks linearly.
- Community programs release within annual envelope.
- Staking rewards release only against active funded epochs.

Month 12
- Contributor and investor cliffs complete.
- Monthly linear vesting begins.
- Unlock concentration limits remain binding.

Years 2–5
- Contributor, investor, partner, community, and staking schedules overlap.
- Dashboard must show aggregate monthly unlocks and liquidity-risk indicators.
```

# Appendix B — Economic Scenario Matrix

| Scenario | UFT price | Revenue | Liquidity | Default rate | Bridge event | Required focus |
|---|---:|---:|---:|---:|---|---|
| Base | Stable assumption | Base | Normal | Expected | None | Runway and incentives |
| Adoption failure | −60% | Near zero | Thin | Moderate | None | Treasury and reward reserve |
| Credit crisis | −70% | Low | Thin | Severe | None | Insurance and staking losses |
| Bridge crisis | −50% | Low | Fragmented | Moderate | One bridge total loss | Backing and contagion |
| Governance crisis | Volatile | Base | Normal | Expected | None | Capture and timelock |
| Full stress | −95% | Zero | Illiquid | Extreme | Bridge and provider failure | Solvency and orderly shutdown |

# Appendix C — Standards Alignment Notes

The implementation should align with recognized interfaces where they preserve the constitutional model:

- ERC-20-compatible UFT for fungible-token interoperability.
- ERC-2612-style signed approvals where supported.
- ERC-4626-compatible sUFT share accounting.
- Asynchronous vault-request behavior for staking cooldowns.
- Checkpointed voting and delegation compatible with ERC-5805 concepts.
- Timelocked governance execution using a reviewed Governor and Timelock architecture.

Standards alignment does not replace Unified-specific security analysis, accounting, access-control review, or formal invariant testing.

---

## 87. Completion Statement

This v0.1 specification converts UFT from a general token concept into a bounded economic system with a fixed supply, explicit distribution, finite rewards, segregated reserves, governed revenue routing, collateral limits, staking-loss rules, cross-chain backing, governance thresholds, and measurable launch gates.

The parameters in this document are an initial architecture baseline. They become production parameters only after simulation, independent economic review, security review, and formal ratification under the Unified Constitution.
