# Phase 4B2 Internal Security Review

Date: 2026-07-24

Scope: `LiquidationEngine`, its collateral/oracle/servicing/loan boundaries, settlement
schema, accounting adapter, migration, deployment script, and Phase 4 liquidation tests.

## Reviewed properties

- INV-LIQ-002: plan creation and execution both require canonical default eligibility.
- INV-LIQ-003: policy, trigger, lot, observation, route, bounds, timestamps, bids, and
  settlement outputs are recorded.
- INV-LIQ-004: the lot cannot exceed its currently locked quantity and an ERC-721 lot is
  exactly one.
- INV-LIQ-005/006: exact-token proceeds conserve the fixed single-lender waterfall.
- INV-LIQ-007/008: payment through the canonical loan account caps and reduces the claim
  once before surplus.
- INV-LIQ-009: English collateral moves only after escrowed payment and auction end.
- INV-LIQ-011: residual bad debt is stored on-chain and reconciled in accounting.
- INV-LIQ-012: full repayment before execution cancels without collateral movement.
- INV-ORC-008: stale or replaced pricing evidence blocks execution and safely unwinds an
  expired English auction.

## Threat checks

- One active case prevents overlapping first-priority disposition of one item.
- Checks-effects-interactions are protected by reentrancy guards and atomic EVM rollback.
- Exact input/output balance deltas reject unsupported settlement-token mechanics.
- Pull refunds prevent a hostile outbid recipient from blocking an auction.
- Failed and expired NFT auctions leave vault ownership and item state unchanged.
- The deployment script cannot perform the manager's one-time governance binding.

## Residual boundary

This is an internal engineering review, not an independent audit or production approval.
Lender in-kind claims, insurance, reserve recovery, junior priorities, negotiated
recovery, legal write-off, off-chain collateral, and live market adapters remain
unsupported. No production funds or keys are authorized.
