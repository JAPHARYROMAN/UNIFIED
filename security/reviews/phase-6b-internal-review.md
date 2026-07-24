# Phase 6B Internal Security Review

Date: 2026-07-24

Scope: version-3 underwritten activation factory, version-2 policy isolation, borrower
and lender authorization binding, atomic exposure/funding/loan activation, terminal
release, canonical schemas, final audit evidence, migration, simulation, and deployment.

## Reviewed properties

- `INV-UW-002`, `INV-LOAN-007`, and `INV-FUND-001`: successful disbursement produces
  one canonical active account, exact recorded funding, and equal active subject exposure.
- `INV-LOAN-014`: funding failure and synthetic failure injection at every activation
  stage restore reservation, tender, offer, registry, funding, balances, and clone state.
- `INV-ID-006`, `INV-AUTH-005`, and `INV-LOAN-003`: the direct borrower call, tender,
  signed lender offer, decision, product, agreement, and consent commitment agree exactly.
- `INV-LOAN-005` and `INV-UW-004`: version 3 requires the decision policy/version/product;
  version 2 rejects the underwritten-credit policy marker.
- `INV-LOAN-010` and `INV-LOAN-011`: new-loan pauses do not enter the account repayment
  or terminal exposure-release path.
- `INV-LOAN-001`, `INV-LOAN-002`, and `INV-LOAN-009`: deterministic loan identity,
  offer consumption, registry uniqueness, and exposure reservation prevent replay.

## Threat checks

- Only the version-3 factory receives both loan-factory and exposure-factory roles.
- The factory is non-upgradeable, has no linear application storage, and derives one loan
  ID from chain, factory, tender, offer, borrower, decision, and product.
- The agreement commitment binds exact economics and consent context; the EIP-712 offer
  separately binds timing, policy, metadata, nonce, and expiry.
- Asset, product, borrower, policy ID/version, amount, duration, credential, provider,
  decision currency, and decision freshness are rechecked in the activation transaction.
- Exposure is reserved before tender or offer mutation and activated only after exact
  funding, canonical registration, and account activation.
- Any downstream revert unwinds ERC-20 transfers and all prior cross-contract state.
- Both global and dedicated pauses stop new activation, while repayment and permissionless
  terminal zero-debt release remain callable.
- Finality-gated evidence requires complete decision, consent, tender, offer, account,
  asset, product, amount, duration, agreement, journal, and release linkage.
- The public privacy gate continues to cover all added identity Protobuf and Solidity
  surfaces; fixtures and evidence contain synthetic opaque values only.

## Residual boundary

This review is internal engineering evidence, not legal consent, production credit,
privacy, model-risk, provider, or independent security approval. The direct caller model
does not support relayers or delegated consent. A generic version-2 local loan remains
possible, but it cannot include the policy marker required to claim Phase 6B underwriting.
Provider duplication and weak off-chain commitment construction remain Phase 6A residual
risks.

No interest, collateral, syndication, default, loss recognition, reserve coverage,
cross-asset conversion, live identity provider, real personal data, real unsecured fund,
production key, public testnet approval, or mainnet deployment is authorized.
