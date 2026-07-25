# ADR 0020: Phase 9 Payoff Authority and Implementation Activation

Status: accepted for synthetic local implementation activation

Date: 2026-07-25

## Context

ADR 0019 and the reviewed `UNI-ABI-009` interface and storage freeze define the
Phase 9 payoff-quote tuple, events, errors, state machine, and exact storage declaration.
They deliberately prevent caller-supplied debt components, beneficiaries, assets, routes,
or deployment authority. The freeze does not, however, grant an implementation permission
to invent the missing quote-policy resolver, component commitment, route commitment,
caller authorization, replay behavior, nonce origin, or effective-expiry behavior.

`UNI-PAYOFF-001` therefore remains blocked until this decision fixes those facts and the
always-run boundary tooling distinguishes unopened freeze stubs from a specifically
activated implementation. This decision is subordinate to ADR 0019 and changes neither
the frozen `IPayoffQuoteEngineV2` external ABI nor the exact `PayoffQuoteEngine` storage
declaration.

The authority remains synthetic and local. It applies only to the isolated EVM home
domain with chain ID `31337`, the dedicated `Phase9LocalSyntheticToken`, synthetic loans,
synthetic positions, and mocked evidence. It grants no production, public-network,
real-value, insurance, guarantee, legal-recovery, provider, key, asset, loan, reserve, or
fund authority.

## Decision

### 1. Caller authority

The constructor-bound `RefinanceCoordinator` is the only caller authorized to invoke:

- `issueQuote(bytes32,uint64)`;
- `consumeQuote(bytes32,bytes32,uint64,bytes32)`; and
- `invalidateQuote(bytes32,bytes32)`.

Every other caller reverts `UnauthorizedQuoteCaller(caller)`. The public `quote(bytes32)`
view remains permissionless and grants no state-changing authority.

The engine accepts only `loanId` and `validUntil` at issuance. Debt, beneficiaries,
obligation codes, policy, asset, token, route, version, and quote identity are resolved
from constructor-bound or loan-bound canonical authorities. No caller value may replace
or supplement them.

### 2. Loan and debt eligibility

At issuance, the loan must:

- exist in the constructor-bound `LoanRegistry` and not be terminal;
- have protocol version `9`;
- resolve to a contract whose `configuration().loanId` equals the requested loan ID;
- equal `IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId)`, so the
  constructor-approved factory and registry independently resolve the same account;
- bind that same loan registry, the approved Phase 9 factory, this quote engine, and the
  constructor-bound refinance coordinator;
- use lifecycle `ACTIVE`; and
- use servicing state `CURRENT`, `DELINQUENT`, or `DEFAULTED`.

The engine reads one canonical `debtState()` and never accepts component amounts from the
caller. In the first quote-policy slice, `capitalizedInterest` and `recoverableCosts` must
both be zero. A nonzero value requires a later quote-policy version, new cross-language
golden vectors, and an explicit compatibility review.

The exact equations are:

```text
gross payoff = outstanding principal
             + accrued interest
             + accrued fees
             + accrued penalties

0 <= unapplied credit <= accrued fees + accrued penalties
net payoff = gross payoff - unapplied credit
net payoff > 0
```

Checked arithmetic is mandatory. Overflow, a credit outside the bound, a zero net payoff,
an unsupported debt component, or an ineligible loan state reverts `InvalidQuoteInput()`.

### 3. Canonical lender and policy authorities

The loan account's constructor-bound `positionManager` is the lender-beneficiary
authority. Issuance requires exactly one `ACTIVE` lender position, a nonzero owner, and an
active claim exactly equal to `outstandingPrincipal + accruedInterest`. That owner is the
canonical beneficiary for both principal and accrued interest. Zero or multiple active
positions, a mismatched claim, or a substituted owner reverts `InvalidQuoteInput()`.

The existing `_quotePolicyRegistry` storage field is the constructor-bound immutable
quote-policy source. Its local/internal typed surface is exactly:

```solidity
interface IPhase9PayoffQuotePolicySource {
    function resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)
        external
        view
        returns (
            bytes32 policyHash,
            bytes32 boundPolicySetHash,
            address feePenaltyBeneficiary,
            bytes32 settlementAssetId,
            address settlementToken,
            uint64 maximumValidity,
            bool active
        );
}
```

This selector is an internal implementation dependency. It is not added to
`IPayoffQuoteEngineV2`, does not add a `PayoffQuoteEngine` selector, and requires no new
engine storage. The source address and each successful `(loanId, loanAccount)` binding are
immutable for this local slice.

The returned tuple is accepted only when:

- `active` is true;
- `policyHash`, `boundPolicySetHash`, `feePenaltyBeneficiary`, `settlementAssetId`, and
  `settlementToken` are nonzero;
- `boundPolicySetHash` equals the loan account's `policySetHash`;
- `settlementAssetId` and `settlementToken` equal the loan configuration;
- `maximumValidity` is nonzero and equals the constructor-bound
  `_maximumQuoteValidity`; and
- the policy source and settlement token contain code.

A changed resolver response, inactive binding, asset substitution, token substitution,
policy-set substitution, beneficiary substitution, or maximum-validity substitution is
invalid canonical state. Neither deprecation nor a later policy may reinterpret an
already issued quote.

### 4. Exact component and route commitments

Every issued quote stores exactly five components, including zero-valued components, in
this order:

| Index | Kind | Amount | Beneficiary | Exact obligation code |
| --- | --- | --- | --- | --- |
| 0 | `PRINCIPAL` | outstanding principal | canonical lender beneficiary | `PRINCIPAL` |
| 1 | `ACCRUED_INTEREST` | accrued interest | canonical lender beneficiary | `ACCRUED_INTEREST` |
| 2 | `FEE` | accrued fees | policy-bound fee/penalty beneficiary | `FEE` |
| 3 | `PENALTY` | accrued penalties | policy-bound fee/penalty beneficiary | `PENALTY` |
| 4 | `CREDIT` | unapplied credit | policy-bound fee/penalty beneficiary | `FEE_PENALTY_CREDIT` |

The credit is an allocation against the fee-and-penalty route. It is not cash, borrower
proceeds, principal reduction, or recipient-selection authority.

The component-beneficiary commitment is exactly:

```solidity
keccak256(
    abi.encode(
        "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1",
        components
    )
)
```

where `components` is the complete ordered
`IPayoffQuoteEngineV2.PayoffComponentV2[]` above, encoded with `abi.encode`, including the
dynamic obligation-code strings. `abi.encodePacked`, omission of a zero-valued component,
sorting, aggregation, or alternate text is prohibited.

The settlement-route commitment is exactly:

```solidity
keccak256(
    abi.encode(
        "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
        block.chainid,
        address(this),
        refinanceCoordinator,
        loanId,
        loanAccount,
        settlementAssetId,
        settlementToken,
        lenderBeneficiary,
        feePenaltyBeneficiary,
        policyHash
    )
)
```

Here `refinanceCoordinator` is the constructor-bound coordinator. Every address and value
comes from the canonical authorities above; none is a command parameter.

The quote ID remains the exact `UNIFIED_PAYOFF_QUOTE_V1` preimage frozen by ADR 0019.
`componentBeneficiaryHash` remains immediately after `credits`; `grossPayoff` remains
stored evidence and is not inserted into the quote-ID preimage.

### 5. Nonce, active quote, and validity rules

Quote nonce `0` is reserved. The first successful quote for a loan uses nonce `1`.
`_nextQuoteNonce[loanId] == 0` is interpreted as an uninitialized next nonce of `1`.
After a successful issuance the stored next nonce advances by one. A revert, rejected
input, collision, unauthorized call, or failed event-producing transaction does not
advance it. Exhaustion at `type(uint64).max` fails closed with
`QuoteReplayConflict(bytes32(0))`; zero communicates that no new quote identity was
created.

There is at most one effective `ISSUED` quote per loan. If `_latestQuoteId[loanId]` has no
terminal disposition and `block.timestamp < validUntil`, a new issuance reverts
`InvalidQuoteInput()`. There is no implicit supersession and no automatic invalidation of
an unexpired quote. A stored terminal disposition or effective expiry permits a later
successful issuance with the next nonce.

Validity is the half-open interval `[issuedAt, validUntil)`:

- `issuedAt = uint64(block.timestamp)`;
- `validUntil` must be strictly greater than `issuedAt`;
- `validUntil - issuedAt` must be less than or equal to both the constructor-bound and
  resolved policy `maximumValidity`; and
- at `block.timestamp >= validUntil`, consumption reverts
  `QuoteExpired(quoteId, validUntil)`.

The inclusive maximum-validity boundary is valid. `quote()` overlays the effective state
`EXPIRED` when stored content is `ISSUED`, no disposition is recorded, and
`block.timestamp >= validUntil`; the view does not write storage. A coordinator call to
`invalidateQuote` at or after the deadline persists the one terminal `EXPIRED`
disposition. Before the deadline it persists `INVALIDATED`.

### 6. Consumption and full canonical revalidation

Before recording `CONSUMED`, the engine re-resolves and revalidates all canonical facts:

- registry existence, nonterminal state, protocol version, and exact loan-account
  address;
- independent equality of the registry account and
  `IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId)`;
- loan ID, registry, approved factory, engine, coordinator, settlement asset, settlement
  token, policy-set hash, lifecycle, and supported servicing state;
- the complete debt state, stored debt-state version, gross equation, credit bound, and
  nonzero net payoff;
- exactly one active lender position, its owner, and its exact principal-plus-interest
  claim;
- the complete active policy-source tuple and its immutable equality to the issued
  binding;
- every component kind, amount, beneficiary, and obligation code;
- the component-beneficiary commitment and settlement-route commitment; and
- the exact quote-ID preimage reconstructed from the stored issuance facts.

The caller's `expectedDebtStateVersion`, the stored quote version, and the live loan
version must be equal. A mismatch reverts
`StaleDebtVersion(expectedVersion, actualVersion)`. Any other canonical substitution or
content mismatch reverts `InvalidQuoteInput()`.

Full revalidation does not recalculate a different quote identity. It proves that the
immutable issued content still equals the current canonical authorities. Successful
consumption records one `CONSUMED` disposition and returns the stored tuple with its
effective state overlaid. When called inside atomic refinance execution, a later revert
must roll back consumption with every payoff, lien, activation, funding, and proceeds
effect.

If a terminal disposition already exists, the engine classifies exact replay, changed
replay, or a different terminal action before performing first-consumption live-state
revalidation. This preserves an exact successful consume result after the same atomic
refinance has legitimately changed the old loan's live debt. It does not let a new or
changed consume bypass revalidation.

### 7. Terminal replay behavior

A disposition is identified by its terminal action and all arguments represented in the
frozen disposition storage:

- consume: `CONSUMED`, `refinanceId`, `expectedDebtStateVersion`, and `sourceEventId`;
- invalidate before deadline: `INVALIDATED`, zero refinance ID, the quote's stored
  debt-state version, and `sourceEventId`; and
- invalidate at or after deadline: `EXPIRED`, zero refinance ID, the quote's stored
  debt-state version, and `sourceEventId`.

An exact replay of the same terminal action and the same bound fields is idempotent:

- exact `consumeQuote` replay returns the original stored quote with state `CONSUMED`;
- exact `invalidateQuote` replay succeeds without another write; and
- neither exact replay emits a second disposition event or changes a nonce.

Reuse of the same terminal action with a changed refinance ID, changed consume-expected
debt version, or changed source event ID reverts `QuoteReplayConflict(quoteId)`. An
attempted different terminal action after any terminal disposition reverts
`QuoteTerminal(quoteId, existingState)`. Unknown IDs revert `UnknownQuote(quoteId)`.

### 8. Deterministic local constructor cycle

The immutable engine/coordinator binding is deployed by one reviewed local deployer with
ordinary sequential `CREATE`:

1. before deploying either component, the deployer predicts the coordinator address from
   its own address and the nonce of the immediately next `CREATE` after the engine;
2. it deploys `PayoffQuoteEngine` with that exact predicted coordinator address;
3. with no intervening contract creation, callback, or external deployment step, it
   deploys `RefinanceCoordinator` bound to the actual engine address; and
4. the deployment script verifies the actual coordinator equals the prediction and that
   the coordinator's engine binding and the engine's coordinator binding are reciprocal
   before any loan or quote is created. Because the frozen ABI intentionally exposes no
   configuration getter, this local verification reads the exact fields identified by
   the reviewed compiler storage-layout artifacts and cross-checks the recorded
   constructor arguments; those reads are release evidence, not protocol authority.

This local sequence uses no mutable setter, proxy initialization, rebinding, late
registration, or `CREATE2`. A nonce mismatch, intervening creation, predicted/actual
address mismatch, or reciprocal-binding mismatch reverts the deployment. The prediction
is local deployment mechanics only and grants no production or public-network authority.

### 9. Historical baseline and implementation checkpoint

The accepted `UNI-ABI-009` freeze remains a historical compatibility baseline. Its
reviewed ABI hashes, storage-layout hashes, compiler settings, source-set hash, manifest
hash, review decision, merge commit, and tag must remain reproducible and must not be
rewritten to pretend that implementation source existed at the freeze checkpoint.

Activating `UNI-PAYOFF-001` creates a new exact-source implementation checkpoint:

1. the external ABI and compiler storage layout are compared with the historical freeze;
2. the current implementation source and complete reviewed Phase 9 source set receive new
   exact hashes in an implementation checkpoint manifest;
3. the review record names both the immutable historical freeze and the current
   exact-source checkpoint;
4. source-only changes require regenerated source hashes and renewed architecture and
   security review, but do not replace historical evidence;
5. any selector, event, error, tuple, mapping, field, base contract, slot, offset, type,
   or compiler-setting change remains blocked until a separate explicit additive
   compatibility decision is accepted; and
6. checkers validate the current exact-source checkpoint while separately proving that
   frozen ABI and storage compatibility has not drifted.

The always-run Phase 9 checker must use reviewed backlog-to-contract activation mapping.
It continues to require the exact `Phase9ImplementationNotFrozen()` body for unopened
contracts and functions. It permits successful state-changing logic only for a work item
whose activation ADR and required tooling are `DONE`, and it rejects an implementation
row completed before its activation decision. Removing a freeze assertion globally or
treating every Phase 9 stub as activated is prohibited.

`UNI-ADR-015` records this decision and the reviewed tooling activation. It must be `DONE`
before `UNI-PAYOFF-001` may become `DONE`.

## Verification

The implementation and its independent review must prove:

- coordinator-only issue, consume, and invalidate authority;
- canonical registry, approved-factory account, account configuration, position, policy,
  asset, token, beneficiary, and route resolution with substitution failures;
- exact five-component order, strings, zero-component retention, and both commitment
  preimages;
- the exact quote-ID preimage and cross-language golden digest;
- the payoff and credit equations with checked arithmetic and nonzero net payoff;
- nonce origin, success-only advancement, collision behavior, and one effective issued
  quote per loan;
- half-open validity, inclusive maximum window, view-only expiry overlay, and persisted
  expiry through invalidation;
- full canonical consumption revalidation, stale-version failure, exact replay, changed
  replay conflict, different-terminal-action failure, and atomic rollback; and
- historical freeze preservation plus deterministic current source, ABI, storage, and
  review checkpoint checks.

## Consequences

- The quote engine can now be implemented without inventing external engine selectors or
  storage.
- A quote cannot be issued or disposed by a borrower, lender, operator, or arbitrary
  service account.
- Aggregate-valid but recipient-substituted quotes fail because both component and route
  commitments are canonical and independently reproducible.
- Effective expiry is visible immediately while durable disposition remains an explicit
  coordinator action.
- Exact retries are safe, while changed retries and incompatible terminal actions fail
  closed.
- Implementation evidence advances through a new exact-source checkpoint without erasing
  the reviewed interface/storage freeze.

## Explicitly not authorized

This decision does not authorize real funds, real UFT or stablecoins, public networks,
public testnets, production RPCs or keys, live borrowers or lenders, production identity,
external providers, cross-chain or off-chain settlement, real collateral, real reserves,
insurance, guarantees, legal recovery, discretionary debt changes, administrator rescue,
or production deployment. Every such capability requires a separate ratified decision
and the legal, security, economic-risk, operational, and release approvals withheld by
ADR 0019.
