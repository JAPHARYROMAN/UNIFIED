# Phase 4 Engineering Exit Review

Date: 2026-07-24

Decision: PASS for the bounded local/testnet engineering milestone

Production authorization: NOT GRANTED

## Reviewed scope

This review covers the Phase 4A deterministic risk and servicing foundation, Phase 4B1
multi-asset collateral custody, and Phase 4B2 reproducible liquidation and recovery
settlement merged through commit `edf39cc`.

## Exit criteria

| Criterion | Result | Evidence |
|---|---|---|
| Debt calculations are deterministic across contracts and services | PASS | `Phase4RiskEngines.t.sol` and `services/risk-engine/internal/calculation` use exact shared vectors |
| Oracle failures enter safe mode | PASS | quorum, deviation, freshness, canonical metadata, circuit-breaker, and recovery tests |
| Collateral cannot release before final debt settlement | PASS | terminal-state, zero-debt, borrower-recipient, and no-double-release gates |
| Every supported liquidation is reproducible | PASS | policy hash, trigger snapshot, lot, route, observation, price curve, timestamps, bids, and waterfall are recorded |
| UFT collateral ceilings and concentrations work | PASS | canonical UFT identity, per-loan/per-borrower supply limits, aggregate debt ceiling, and post-burn compliance |
| NFT auctions fail and expire safely | PASS | no-bid, stale-price, and expiry paths retain vault ownership and expose refunds |
| Liquidation accounting reconciles | PASS | on-chain proceeds/debt equations, finality-gated idempotent Go posting, immutable SQL constraints, and local migration smoke |
| Production runtime bytecode remains deployable | PASS | 96 production artifacts pass the 24,576-byte optimized size gate; `LiquidationEngine` is 17,316 bytes |
| Generated interfaces remain compatible and deterministic | PASS | Buf lint/build/breaking and clean Solidity/Go/TypeScript/Python regeneration |
| Critical and existential risks have owners and controls | PASS | Phase 4 risk register entries and internal security reviews contain owners, evidence, expiry, and validation |

The pinned Foundry suite contains 36 passing tests, including 256-run fuzz coverage and
two 128,000-call stateful UFT supply invariant runs. The complete foundation check, all
four protected GitHub checks, and the disposable five-service local smoke test pass.

## Authority separation

- The oracle manager configures sources but cannot create a liquidation case.
- The risk council confirms policy-bound cases but cannot move vault assets directly.
- Permissionless buyers and bidders execute only within immutable case bounds.
- The canonical loan account, not the liquidation engine, reduces lender claims.
- The accounting ledger accepts only final events and cannot mutate posted history.
- The release authority retains CI and deployment provenance control.
- Deployment does not perform the collateral manager's one-time governance binding.

## Deferred capabilities

The exit applies only to the implemented single-lender, same-chain, exact-ERC20
settlement slice. It does not claim completion of:

- lender in-kind collateral claims or negotiated recovery;
- junior/tranche priorities, syndication, or secondary loan positions;
- insurance, reserve recovery, legal write-off, or debt forgiveness;
- off-chain, bridged, LP, or tokenized-real-world collateral;
- live oracle/provider integration or production economic configuration;
- independent audit, formal proof completion, public testnet approval, or mainnet use.

Residual bad debt remains an explicit outstanding claim. It is not written off,
forgiven, hidden in suspense, or implicitly covered by protocol reserves.

## Next milestone

Phase 5 may begin with a separate ADR for lender-position identity, share conservation,
tranche priority, voting, transfer restrictions, and waterfall compatibility. No Phase 5
contract should be connected to live funds or the Phase 4 liquidation engine before that
boundary and its accounting model are reviewed.
