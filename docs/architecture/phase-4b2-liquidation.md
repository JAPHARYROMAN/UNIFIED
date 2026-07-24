# Phase 4B2 Liquidation and Recovery Settlement

Status: implemented for local and testnet engineering; not approved for production funds

## Authorization and execution

```text
servicing engine confirms objective default
  -> risk council submits policy hash, trigger snapshot, lot, route, and observation
  -> engine verifies canonical debt, custody, quote asset, freshness, and price bounds
  -> one immutable active case locks the collateral position
  -> direct buyer, Dutch buyer, or English bidders provide exact settlement units
  -> execution rechecks default, debt, custody, and the same canonical observation
  -> collateral moves atomically with the final proceeds waterfall
  -> canonical loan repayment reduces the lender claim
  -> surplus returns to the borrower and residual bad debt remains explicit
```

The risk council cannot choose an arbitrary cash amount. Reference proceeds derive from
the approved normalized observation, asset-registry decimals, and collateral quantity:

```text
normalized proceeds = normalized price × collateral base units / 10^collateral decimals
reference proceeds  = normalized proceeds × 10^settlement decimals / 10^18
reserve price       = reference proceeds × minimum proceeds bps / 10,000
```

Minimum proceeds are bounded to 50%–100% of reference value. Execution costs are capped
at 2% of reserve price and the liquidation incentive at 12% of realized proceeds.

## Routes

| Route | Price/finality rule | Failure behavior |
|---|---|---|
| Direct | Exact reserve price supplied atomically by the buyer | Expiry leaves the lot locked |
| Dutch | Linear reference-to-reserve curve; buyer supplies a maximum-price guard | Expiry leaves the lot locked |
| English | Reserve plus 0.5%–20% configured minimum increment; winning bid is escrowed | No bid, stale price, cure, or repayment refunds escrow and leaves the lot locked |
| NFT | English route with quantity exactly one | Failed and expired auctions never transfer ownership |

Outbid balances are pull-withdrawn. A bidder callback or token receiver therefore cannot
block later bidding. Fee-on-transfer, rebasing, and other non-exact settlement tokens
remain unsupported.

## Waterfall and accounting

```text
gross proceeds
  = execution costs
  + liquidation incentive
  + secured principal claim paid
  + borrower surplus

debt before settlement
  = secured principal claim paid
  + residual bad debt
```

The loan account's unique liquidation payment ID enforces single debt reduction. The
foundation ledger independently checks both equations, posts the principal recovery and
protocol cost recovery as balanced finality-gated journals, and persists the complete
settlement in an immutable reconciliation table.

Junior claims, reserve recoveries, and insurance are zero in this single-lender Phase 4
slice. They require an explicit later waterfall version rather than implicit netting.

## Safe cancellation and failure

A full repayment before execution invalidates the case and permits cancellation without
collateral movement. An English auction with a funded winning bid can settle only after
its end time and while the original observation is still canonical and fresh. Otherwise,
expiry makes the bid refundable. There is no privileged price override or forced stale
settlement path.

## Deployment boundary

`DeployPhase4B2` deploys the engine but cannot bind it. The existing governance executor
must separately call the collateral manager's one-time binding function after reviewing
the deployed bytecode, constructor dependencies, treasury, policy configuration, and
test evidence. This repository contains no live configuration or production deployment.
