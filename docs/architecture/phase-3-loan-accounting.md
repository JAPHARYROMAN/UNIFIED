# Phase 3 Core Loan Origination and Accounting Spine

Status: implemented for local and testnet engineering; not approved for production funds

## Product boundary

The implemented path is a zero-interest, same-chain, single-lender loan settled with an
active registry-approved ERC-20. It deliberately excludes collateral, oracles, default,
liquidation, variable or capitalized interest, syndication, refinancing, cross-chain
messages, fiat, cards, and external providers.

## Canonical flow

```text
borrower registers tender
  -> lender submits EIP-712 offer
  -> borrower accepts through CoreLoanFactory
  -> offer and nonce are consumed once
  -> deterministic account is registered
  -> lender funds borrower and protocol fee atomically
  -> loan activates and emits journal evidence
  -> final chain event posts balanced accounting
  -> payer repays lender with a unique payment ID
  -> principal obligation and lender claim reduce once
  -> zero outstanding principal closes the loan
  -> registry terminal marker prevents reactivation
```

## Components

| Area | Component | Authority and invariant |
|---|---|---|
| Tender | `TenderRegistry` | Borrower creates and cancels; the registered factory alone selects and fulfills; expiration is permissionless. |
| Offer | `OfferManager` | EIP-712 ECDSA signature, exact terms hash, counteroffer lineage, expiry, per-lender nonce cancellation, and one-time consumption. |
| Funding | `FundingManager` | Registered factory only; direct lender-to-borrower principal and protocol fee transfers; exact balance deltas reject unsupported token mechanics. |
| Loan | `CoreLoanAccount` | One-time initialization, immutable agreement snapshot, principal-only debt, unique payment IDs, exact lender receipt, terminal closure. |
| Orchestration | `CoreLoanFactory` | Atomic policy, tender, offer, asset, deployment, registration, funding, activation, and fulfillment transaction. |
| Accounting | `foundation-ledger` | Atomic balanced batches, immutable journals, linked reversals, loan and party dimensions, idempotent event posting. |
| Projection | `chain-indexer` | Canonical-parent checks, transactional reorg replacement, finality labels, deterministic replay and rebuild. |
| API | `core-api` | Bearer-authenticated query and command boundaries; unsigned and expiring transaction preparations only. |

## Authority boundary

On-chain contracts are authoritative for tender, offer, funding, payment, and loan
state. The Unified ledger is authoritative for accounting. The indexer and API are
rebuildable projections and cannot mutate either authority.

Provisional chain events may update provisional projections, but the accounting service
rejects them. Only events marked final can post journals. A later accounting correction
must use a separately linked reversal; posted history is never edited or deleted.

## Accounting model

Activation:

```text
Debit  1310 Principal Receivable
Credit 2310 Lender Principal Claims
```

Settled origination fee:

```text
Debit  1220 Stablecoin Treasury Holdings
Credit 4100 Loan Origination Fee Revenue
```

Principal repayment:

```text
Debit  2310 Lender Principal Claims
Credit 1310 Principal Receivable
```

All quantities are canonical base-10 integer strings in the asset's smallest unit.

## Evidence

- `Phase3CoreLoan.t.sol` demonstrates tender, signed offer, atomic funding and
  activation, idempotent repayment, lender receipt, closure, rollback, pause behavior,
  counteroffer lineage, and fuzzed principal reduction.
- Go tests demonstrate atomic accounting batches, immutable reversal, finality gating,
  event replay, payment uniqueness, reorg rollback, projection rebuild, API
  authentication, and unsigned transaction preparation.
- Protobuf is the shared interface source for tenders, offers, state vectors, chain
  evidence, activation, repayment, and transaction preparation.
- Phase 3 ABIs and storage layouts are reviewed derivatives.

## Deployment restrictions

The deployment script attaches the Phase 3 contracts to an existing Phase 2 kernel and
grants only the new factory the required factory role. It embeds no private key. This
repository still contains no production deployment, custody integration, identity
provider, real payment provider, or mainnet configuration.
