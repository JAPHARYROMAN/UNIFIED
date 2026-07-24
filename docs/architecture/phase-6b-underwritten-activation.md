# Phase 6B Underwritten Activation Boundary

Status: implemented for synthetic local/testnet engineering; not approved for production funds

## Atomic activation

```text
borrower-owned open tender
  + current exact decision
  + lender-signed exact offer
  + approved underwritten product policy
  + consent-evidence commitment
            |
            v
UnderwrittenLoanFactory (one transaction)
  1. validate global + underwritten activation capabilities
  2. derive version-3 loan ID and verify the activation agreement
  3. reserve exact subject/asset exposure
  4. select tender and consume signed offer
  5. clone, initialize, and canonically register CoreLoanAccount
  6. pull exact lender principal and disburse exact borrower proceeds/fee
  7. activate the loan account and exposure
  8. mark tender fulfilled and emit linked audit evidence
```

Every step is in one EVM transaction. A failure at step 2 through 8 reverts all prior
state and token movements. There is no persistent pre-funding reservation, partial
disbursement, or privileged completion method.

## Authorization binding

The factory-calculated agreement commitment binds:

```text
domain + chain + factory + loan + tender + offer
+ borrower + decision + product + asset + principal
+ final maturity + policy-set hash + metadata hash
+ consent-evidence commitment
```

The borrower owns the tender and directly submits the final activation transaction. The
lender's EIP-712 offer signs the same agreement, borrower, asset, amount, timing, policy
set, and metadata. Tender and offer consumption plus the version-3 loan ID prevent replay.
No relayer, delegate, session key, or consent-vault authorization is accepted in this
slice.

The consent evidence is an opaque, domain-separated commitment. It must never be a raw
disclosure, personal attribute, document, or guessable plain hash.

## Policy and decision match

One approved policy reference must implement the underwritten-credit marker and return
the exact product hash. Its policy ID and semantic version must equal the current credit
decision. A reviewed zero-interest policy remains mandatory.

The legacy version-2 factory rejects the underwritten-credit policy marker. The new
factory requires it. This creates a fail-closed policy path:

```text
underwritten marker + legacy factory       -> reject
missing underwritten marker + v3 factory   -> reject
decision/policy/product version mismatch   -> reject
exact current match                         -> continue
```

## Exposure and settlement conservation

Immediately before any loan state is created:

```text
recognized(subject, asset) + proposed principal <= current decision limit
```

The reservation binds the derived loan ID, decision, borrower, product, exact asset,
principal, duration, and factory. After exact funding and account activation, the same
transaction converts reserved exposure to active exposure. A revoked, expired, or
superseded decision fails the transaction.

Repayment continues directly through the canonical account and is not routed through the
factory. When the account reaches zero principal it marks the loan terminal. Exposure
release is permissionless and requires that same canonical terminal, zero-debt state.
Failure to call release only withholds future capacity.

## Emergency behavior

The factory checks both:

- the existing global `CAPABILITY_NEW_LOANS`; and
- a dedicated `CAPABILITY_UNDERWRITTEN_NEW_LOANS`.

Either pause blocks only new version-3 activation. Repayment, loan closure, lender receipt,
and terminal exposure release remain available.

## Implemented slice

Phase 6B implements:

- `IUnderwrittenCreditPolicy` and legacy-factory marker rejection;
- a stateless, non-upgradeable version-3 `UnderwrittenLoanFactory`;
- deterministic loan/agreement hash helpers and a local deployment script;
- additive activation-evidence Protobuf and four-language bindings;
- finality-gated activation and release control evidence;
- atomicity, replay, revocation, policy-bypass, repayment, and release tests;
- synthetic failure simulations and an internal security review.

The slice does not implement interest, schedules, collateral, syndication, default,
liquidation, write-off, reserves, cross-asset conversion, production model policy,
delegated consent, raw identity storage, live providers, ZK credentials, real funds,
public testnet configuration, or mainnet deployment.

## Acceptance-property mapping

- `INV-UW-002`, `INV-LOAN-007`, and `INV-FUND-001`: no principal disbursement
  exists without a canonical active loan and equal active recognized exposure.
- `INV-LOAN-014`: a failed activation changes no reservation, tender, offer, loan
  registry, account, lender balance, borrower balance, fee balance, or funding record.
- `INV-ID-006`, `INV-AUTH-005`, and `INV-LOAN-003`: borrower and lender authorize
  one identical decision, product, and agreement.
- `INV-LOAN-005` and `INV-UW-004`: a Phase 6B policy cannot activate through the
  legacy factory or against a mismatched decision product.
- `INV-LOAN-010` and `INV-LOAN-011`: repayment, closure, and terminal exposure
  release remain available during any new-loan pause.
- `INV-LOAN-001`, `INV-LOAN-002`, and `INV-LOAN-009`: one tender, offer, decision
  context, and derived loan ID cannot activate twice.
