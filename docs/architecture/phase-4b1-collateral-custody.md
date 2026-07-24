# Phase 4B1 Multi-Asset Collateral Custody

Status: implemented for local and testnet engineering; liquidation binding is a separate
Phase 4B2 governance action

## Custody flow

```text
risk council configures immutable asset identity and kind
  -> borrower creates deterministic per-loan vault
  -> borrower approves that vault
  -> manager verifies active loan, borrower, asset, kind, and UFT limits
  -> vault initiates exact transfer and verifies custody
  -> manager records loan and borrower exposure
  -> release waits for terminal loan plus zero debt
  -> vault returns only to the borrower and exposure reduces atomically
```

The vault stores the canonical item identity: collateral ID, asset ID, kind, token,
token ID, quantity, owner, lock time, and status. ERC-721 quantity is always one.
ERC-1155 and fungible/native items support partial disposition; every reduction updates
vault, loan, and borrower quantities in the same transaction.

## Reconciliation

For every asset in a vault:

```text
vault balance = sum(LOCKED item quantities)
```

Tests reconcile ERC-20 balance, native balance, ERC-721 owner, ERC-1155 balance, and
the manager exposure maps. Failed, premature, unsolicited, excessive, and duplicate
operations revert completely.

## UFT controls

- Canonical UFT identity cannot be configured as non-UFT collateral.
- Per-loan quantity is at most 0.25% of current UFT supply.
- Per-borrower quantity is at most 0.50% of current UFT supply.
- A risk-council-attested UFT-backed debt value must exist before deposit.
- Aggregate bound debt cannot exceed the configured protocol ceiling.
- `isUFTExposureCompliant` exposes post-burn monitoring because a later UFT supply
  reduction can tighten percentage limits without a new deposit.
- Debt-ceiling capacity closes only after zero debt, terminal state, and zero remaining
  UFT custody.

Market-cap and liquidity-adjusted ceiling derivation will use Phase 4A finalized oracle
observations in the Phase 4B2 policy. Phase 4B1 stores the approved ceiling and evidence;
it does not invent a valuation.

## Liquidation boundary

The manager can bind one immutable liquidation-engine address. That address can request
a bounded partial or full disposition, but Phase 4B1 contains no eligibility or sale
logic. Phase 4B2 defines and reviews that logic. Its deployment intentionally remains
unbound until the governance executor separately approves the deployed dependencies and
performs the manager's one-time binding.
