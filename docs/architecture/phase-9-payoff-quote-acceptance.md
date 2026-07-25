# Phase 9 Payoff Quote Acceptance and Threat Matrix

Status: normative implementation gate for synthetic local engineering

Authority: subordinate to ADR 0020 and ADR 0019. If this document conflicts with either
ADR, the ADR controls and this matrix must be corrected before `UNI-PAYOFF-001` can be
marked complete.

## Purpose and scope

This document defines the minimum implementation, security, fuzz, invariant, and
compatibility evidence required to activate `PayoffQuoteEngine`. It applies only to the
synthetic local Phase 9 product on the isolated EVM home domain. It does not authorize
refinance execution, debt reduction, settlement, lien movement, production policy,
public-network deployment, a live provider, or real value.

The quote engine is an immutable fact-derivation and terminal-disposition component. It
may read canonical loan, position, and policy state and may store quotes and their
dispositions. It MUST NOT custody, approve, transfer, burn, mint, escrow, repay, write
off, forgive, or otherwise move or recognize value.

## Normative first-slice rules

### Authority and canonical sources

- `issueQuote`, `consumeQuote`, and `invalidateQuote` are callable only by the exact
  constructor-bound `RefinanceCoordinator`. Every other caller fails with
  `UnauthorizedQuoteCaller`.
- `quote` is a public read.
- The `LoanRegistry` identifies the canonical account for the loan and its Phase 9
  protocol version. At both issue and first consumption, the exact account equality is
  `IPhase9LoanFactory(_approvedPhase9Factory).loanAccount(loanId) ==
  _loanRegistry.loanAccount(loanId) == loanAccount`.
- The account configuration MUST bind the same loan ID, registry, approved factory,
  quote engine, refinance coordinator, position manager, settlement asset ID,
  settlement token, and policy-set hash used by the quote.
- At issue and first consumption, position authority is independently anchored by
  `IPhase9LoanFactory(_approvedPhase9Factory).positionManager(loanId) ==
  configuration.positionManager`. That address MUST be nonzero and contain code. A
  configuration-selected manager cannot win merely by returning position contents that
  match the approved manager.
- The account debt state is the sole source of principal, accrued interest, fees,
  penalties, credits, and debt-state version.
- Exactly one active lender position is supported. Its owner is the principal and
  accrued-interest beneficiary, and its claim MUST equal
  `principal + accrued_interest` at issuance and consumption.
- The constructor-bound immutable policy source implements the internal-only
  `IPhase9PayoffQuotePolicySource` interface. Its exact selector is
  `resolvePayoffQuotePolicy(bytes32 loanId, address loanAccount)` and its exact return
  order is `policyHash`, `boundPolicySetHash`, `feePenaltyBeneficiary`,
  `settlementAssetId`, `settlementToken`, `maximumValidity`, and `active`. The returned
  policy-set hash, asset, token, and maximum validity MUST equal the account and engine
  bindings, and `active` MUST be true.
- The resolver-returned `policyHash` is not opaque. The engine MUST independently
  reconstruct and require this exact commitment:

  ```text
  keccak256(abi.encode(
    "UNIFIED_PAYOFF_POLICY_V1",
    block.chainid,
    address(this),
    _quotePolicyRegistry,
    loanId,
    loanAccount,
    boundPolicySetHash,
    feePenaltyBeneficiary,
    settlementAssetId,
    settlementToken,
    maximumValidity
  ))
  ```

  The dynamic domain string and every field occupy their canonical `abi.encode` words.
  `abi.encodePacked`, omission, reordering, an alternate domain, or trusting a returned
  digest without reconstruction is prohibited.
- If `_latestQuoteId[loanId]` is materialized, every successor issuance MUST resolve the
  same `policyHash` as that prior stored quote, including after terminal disposition or
  effective expiry. Policy evolution for an existing `(loanId, loanAccount)` is deferred.
  First consumption MUST reconstruct the same commitment and require it to equal the
  stored quote policy hash. Coordinated changes to account policy-set state and the
  resolver tuple cannot preserve consumability.
- The engine is local-only. Issue and first consumption MUST reject
  `block.chainid != 31337`. At both gates, the settlement token MUST contain code and satisfy
  `settlementToken.codehash ==
  keccak256(type(Phase9LocalSyntheticToken).runtimeCode)` under the pinned Solidity
  compiler, optimizer settings, and OpenZeppelin version. Matching metadata, interface
  responses, account configuration, and policy output are not substitutes for this exact
  runtime-code commitment. Under Foundry `1.7.1`, Solidity `0.8.36`, optimizer runs
  `200`, EVM Prague, and OpenZeppelin `5.6.1`, the golden runtime code hash is
  `0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5`.
- A caller, service, database row, event payload, or mock-provider response cannot
  supply or override a debt component, beneficiary, policy, route, asset, token,
  `issuedAt`, version, nonce, or digest field. The constructor-bound coordinator selects
  only `loanId` and `validUntil`; `validUntil` is its sole time input and is accepted only
  within the canonical half-open and maximum-validity rules below.

All dependent reads are fully revalidated before a first consumption. Matching the
caller-provided `expectedDebtStateVersion` to a stored field is not sufficient. A quote
that already has a terminal disposition is classified for exact replay or conflict
before first-consumption revalidation; this preserves a successful consume result after
the atomic refinance has legitimately changed the live debt.

An eligible account exists in the registry, is nonterminal, has protocol version `9`,
has deployed code, uses lifecycle `ACTIVE`, and uses servicing state `CURRENT`,
`DELINQUENT`, or `DEFAULTED`. No other lifecycle or servicing state is accepted.

### Immutable constructor-cycle deployment

The quote engine and refinance coordinator have a reciprocal immutable dependency: the
engine authorizes the coordinator, and the coordinator binds the engine. One reviewed
deployer contract MUST resolve this cycle in a single EVM transaction without a setter,
proxy, administrator, temporary open authorization, or separately broadcast deployment
step. CREATE2, rebinding, and post-deployment repair are prohibited.

For a dedicated CREATE deployer with next nonce `n`, deployment evidence computes the
coordinator address at nonce `n + 1`, deploys the engine at nonce `n` bound to that
predicted coordinator, and immediately—with no intervening creation, callback, or
external deployment step—deploys the coordinator at nonce `n + 1` bound to the actual
engine address. The evidence records the deployer, `n`, predicted and actual addresses,
deployment transactions, constructor arguments, chain ID, and code hashes. It proves:

```text
predicted_coordinator == actual_coordinator
engine.authorized_coordinator == actual_coordinator
coordinator.payoff_quote_engine == actual_engine
```

The deployer controls both constructor argument lists, checks the predicted and actual
addresses and code before returning, and reverts the single transaction on an intervening
CREATE, changed deployer nonce, wrong prediction, wrong controlled constructor argument,
missing code, or address mismatch. Reciprocal private bindings are then independently
audited from recorded constructor arguments and the reviewed compiler storage-layout
fields and confirmed behaviorally by successful coordinator access and rejection of
every other caller. Those post-deployment raw-storage reads are release evidence only:
they cannot revert a completed transaction. Any evidence mismatch rejects activation and
requires disposal/reset of the bounded local deployment; it MUST NOT be repaired through
a setter, proxy, rebinding, or later administrative transaction. No loan or quote may be
created before that evidence passes.

### Amount equation and supported debt

The first-slice equation is exact integer arithmetic:

```text
gross_payoff = principal + accrued_interest + fees + penalties
net_payoff   = gross_payoff - credits

0 <= credits <= fees + penalties
0 < net_payoff
```

Credits are authorized only against the fee-and-penalty route. They cannot reduce the
active lender's principal or accrued-interest claim. Nonzero capitalized interest and
nonzero recoverable costs are unsupported by quote-policy V1 and MUST fail rather than
being omitted, aliased, or folded into another component. Overflow, malformed canonical
state, or an unsupported debt component fails without consuming a nonce or creating
partial storage.

### Fixed component vector

Every accepted quote contains exactly these five entries in this order:

| Index | Kind | Amount | Beneficiary | Obligation code |
|---:|---|---:|---|---|
| 0 | `PRINCIPAL` | canonical principal | active lender-position owner | `PRINCIPAL` |
| 1 | `ACCRUED_INTEREST` | canonical accrued interest | active lender-position owner | `ACCRUED_INTEREST` |
| 2 | `FEE` | canonical fees | policy-bound fee/penalty beneficiary | `FEE` |
| 3 | `PENALTY` | canonical penalties | policy-bound fee/penalty beneficiary | `PENALTY` |
| 4 | `CREDIT` | canonical credits | policy-bound fee/penalty beneficiary | `FEE_PENALTY_CREDIT` |

Zero-valued entries remain present. `NONE`, `CAPITALIZED_INTEREST`,
`RECOVERABLE_COST`, duplicate kinds, extra entries, changed strings, or a reordered
entry are invalid in this slice.

The component commitment uses the exact ADR 0020 domain and ordered ABI encoding:

```text
component_beneficiary_hash = keccak256(abi.encode(
  "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1",
  components
))
```

The settlement-route commitment is exactly:

```text
settlement_route_hash = keccak256(abi.encode(
  "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1",
  block.chainid,
  address(this),
  refinance_coordinator,
  loan_id,
  loan_account,
  settlement_asset_id,
  settlement_token,
  lender_beneficiary,
  fee_penalty_beneficiary,
  policy_hash
))
```

Tests MUST NOT substitute `abi.encodePacked`, JSON serialization, a caller-provided
digest, or an aggregate amount. The exact route preimage is a compatibility surface even
though it is not a separate external ABI tuple.

### Quote identity

`quoteId` is exactly:

```text
keccak256(abi.encode(
  "UNIFIED_PAYOFF_QUOTE_V1",
  address(this),
  block.chainid,
  loan_id,
  loan_account,
  quote_policy_hash,
  debt_state_version,
  principal,
  accrued_interest,
  fees,
  penalties,
  credits,
  component_beneficiary_hash,
  net_payoff,
  settlement_asset_id,
  settlement_token,
  settlement_route_hash,
  issued_at,
  valid_until,
  quote_nonce
))
```

The quote ID is not in its own preimage. `grossPayoff` is derived and stored evidence
and is not added to the preimage. The domain is a Solidity dynamic string in
`abi.encode`, not a packed byte prefix. Every `uint64` occupies its canonical ABI word.

### Nonces, one-live-quote rule, and time

- Quote nonces are per loan, start at `1`, and increase by exactly one only after a
  successful issue.
- A failed issue leaves the next nonce unchanged. A nonce MUST NOT wrap.
- Exhaustion at `type(uint64).max` fails closed with
  `QuoteReplayConflict(bytes32(0))` using the frozen error payload.
- After deriving the quote ID and before any quote, component, latest-ID, or nonce write,
  the engine MUST reject `quoteId == bytes32(0)` or an already materialized
  `_quotes[quoteId].quoteId != bytes32(0)` with `QuoteReplayConflict(quoteId)`. A collision
  is never an idempotent issue, never returns an existing quote, and never consumes a
  nonce.
- At most one quote per loan has effective state `ISSUED`.
- Issuing while `_latestQuoteId[loanId]` is effectively `ISSUED` reverts
  `InvalidQuoteInput`. There is no implicit supersession or silent invalidation. A new
  quote is permitted only after the latest quote has a stored terminal disposition or
  is effectively expired.
- Quote validity is the half-open interval `[issuedAt, validUntil)`.
- `issuedAt` is the checked `uint64` representation of `block.timestamp` and is never a
  coordinator input.
- Coordinator-selected `validUntil` MUST be greater than `issuedAt` and no later than the
  immutable policy-bound maximum validity. No other caller-selected time is accepted.
- At `block.timestamp >= validUntil`, `quote()` returns effective state `EXPIRED`, and
  `consumeQuote()` reverts `QuoteExpired`.
- Calling `invalidateQuote()` on an effectively expired quote persists terminal state
  `EXPIRED`; before expiry it persists `INVALIDATED`.

`CONSUMED`, `EXPIRED`, and `INVALIDATED` are terminal.

### Consumption, invalidation, and replay

Consumption requires all of the following to remain exact:

```text
canonical registry account
approved factory account
approved factory position manager
Phase 9 implementation version
account configuration identities
account lifecycle eligibility
debt state and debt-state version
one active lender position and claim
policy-set and exact reconstructed quote-policy commitment
five components and beneficiaries
component commitment
settlement asset, exact local token runtime code hash, and chain 31337
settlement route commitment
unexpired validity
nonzero refinance ID and source-event ID
```

A repayment, accrual, waiver, correction, restructuring, position change, policy
substitution, account substitution, recipient change, asset change, token change, or
route change makes the quote unconsumable even if an adversarial dependency fails to
increment the debt-state version.

`invalidateQuote` also requires a nonzero `sourceEventId`, both before expiry and when
persisting effective expiry. A zero source-event ID reverts `InvalidQuoteInput` without a
disposition or event. Caller authorization and quote-existence validation precede this
zero check; the zero check precedes terminal classification.

The terminal replay rules are:

- an exact retry of the original consume returns the same stored quote in state
  `CONSUMED` and emits no second disposition;
- an exact retry of the original invalidation or expiry persistence is a no-op and emits
  no second disposition;
- changed reuse of the same terminal action reverts `QuoteReplayConflict`;
- attempting a different terminal action reverts `QuoteTerminal` with the stored
  terminal state;
- an unknown quote reverts `UnknownQuote`; it never returns or materializes a zero
  tuple.

The exact disposition identity is `(CONSUMED, refinanceId,
expectedDebtStateVersion, sourceEventId)` for consumption and `(INVALIDATED|EXPIRED,
bytes32(0), storedQuoteDebtStateVersion, sourceEventId)` for invalidation. The stored
quote version makes an exact retry stable even if canonical debt later changes. Exact
replay means equality of the complete applicable identity, not merely the quote ID or
source event.

## Unit and adversarial acceptance matrix

All rows are mandatory unless ADR 0020 explicitly marks a row non-applicable with an
equivalent stronger control.

| ID | Setup or action | Required result | Primary properties |
|---|---|---|---|
| `P9Q-CFG-001` | Deploy with any zero authority or zero maximum validity | `InvalidQuoteInput`; no deployment | `INV-AUTH-001`, `INV-AUTH-002` |
| `P9Q-CFG-002` | Resolved policy maximum differs from constructor maximum | Issuance fails; weaker/later caller value cannot win | `INV-LOAN-004`, `INV-LOAN-006` |
| `P9Q-DEPLOY-001` | In one transaction, predict the coordinator at deployer nonce `n + 1`, deploy engine at `n`, then coordinator immediately next | Predicted and actual coordinator match; both contracts contain code; reciprocal bindings pass | `INV-AUTH-001`, `INV-AUTH-004` |
| `P9Q-DEPLOY-002` | Insert an intervening CREATE or callback creation, or perturb the deployer nonce inside the single deployment transaction | Actual coordinator differs from prediction; the complete transaction reverts and no evidence is accepted | `INV-AUTH-001`, `INV-LOAN-015` |
| `P9Q-DEPLOY-003` | Make the deployer pass a wrong controlled engine/coordinator constructor argument | The single deployment transaction reverts; no accepted manifest exists | `INV-AUTH-004`, `INV-LOAN-015` |
| `P9Q-DEPLOY-004` | Inspect ABI, source, bytecode surface, and post-deployment behavior for rebinding | No coordinator/engine setter, proxy initialization, CREATE2, delegatecall, or administrative repair path exists | `INV-AUTH-002`, `INV-AUTH-004` |
| `P9Q-DEPLOY-005` | Post-deployment raw-storage or recorded-argument evidence disagrees after the deployment transaction completed | Activation is rejected, no loan/quote is created, and bounded local state is reset; evidence is not claimed to revert history | `INV-AUTH-004`, `INV-LOAN-015` |
| `P9Q-AUTH-001` | Bound coordinator issues, consumes, and invalidates | Calls reach semantic validation | `INV-AUTH-001`, `INV-AUTH-002` |
| `P9Q-AUTH-002` | Borrower, lender, account, factory, policy source, or arbitrary caller invokes a mutator | `UnauthorizedQuoteCaller`; no state change | `INV-AUTH-001`, `INV-AUTH-004` |
| `P9Q-SRC-001` | Zero or unknown loan ID | `InvalidQuoteInput`; nonce unchanged | `INV-REFI-001` |
| `P9Q-SRC-002` | Registry protocol version is not 9 | Rejected | `INV-LOAN-005`, `INV-LOAN-006` |
| `P9Q-SRC-003` | Registry and approved factory identify different accounts | Rejected | `INV-AUTH-004`, `INV-LOAN-001` |
| `P9Q-SRC-004` | Account configuration changes loan, factory, registry, engine, coordinator, position manager, policy set, asset, or token | Rejected | `INV-LOAN-004`, `INV-REFI-001` |
| `P9Q-SRC-005` | Account is uninitialized, terminal, lacks code, is not `ACTIVE`, or has an unsupported servicing state | Rejected | `INV-LOAN-008`, `INV-LOAN-013` |
| `P9Q-SRC-006` | Zero, missing, or multiple active lender positions | Rejected | `INV-FUND-004`, `INV-REFI-001` |
| `P9Q-SRC-007` | Active position owner is zero or claim differs from principal plus interest | Rejected | `INV-FUND-005`, `INV-INT-011` |
| `P9Q-SRC-008` | Policy source reverts, is malformed, or returns a zero/mismatched fact | `InvalidQuoteInput`; no partial state | `INV-AUTH-001`, `INV-LOAN-005` |
| `P9Q-SRC-009` | Canonical account, position, or policy read reverts | No quote, nonce, component, or disposition write | `INV-LOAN-014` |
| `P9Q-SRC-010` | Policy source or returned settlement token has no code | Rejected | `INV-ASSET-002`, `INV-LOAN-005` |
| `P9Q-SRC-011` | Factory `positionManager(loanId)` differs from account configuration, while both managers return identical active-position owner and claim | Rejected at issue and consume; configuration cannot select position authority | `INV-AUTH-004`, `INV-FUND-005` |
| `P9Q-SRC-012` | Factory/account position-manager address is zero or has no code | Rejected | `INV-AUTH-004`, `INV-LOAN-005` |
| `P9Q-SRC-013` | Settlement token has code and matching metadata/interface output but a runtime code hash other than `0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5` | Rejected at issue and consume | `INV-ASSET-002`, ADR 0019 boundary |
| `P9Q-SRC-014` | Compile the pinned `Phase9LocalSyntheticToken` under the locked toolchain and settings | `keccak256(type(Phase9LocalSyntheticToken).runtimeCode)` equals the committed golden runtime hash | `INV-VER-001`, `INV-VER-002` |
| `P9Q-POL-001` | Independently encode the exact `UNIFIED_PAYOFF_POLICY_V1` preimage | Reconstructed digest equals resolver output and stored quote policy hash | `INV-AUTH-004`, `INV-VER-001` |
| `P9Q-POL-002` | Resolver returns an opaque digest or a digest encoded with packed, omitted, reordered, alternate-domain, wrong-chain, wrong-engine, or wrong-source fields | `InvalidQuoteInput`; no partial state or nonce advancement | `INV-AUTH-004`, `INV-VER-002` |
| `P9Q-POL-003` | After a terminal or effectively expired quote, change any policy commitment field before successor issue | Successor issuance is rejected because current policy hash differs from the prior stored quote | `INV-LOAN-004`, `INV-AUTH-004` |
| `P9Q-POL-004` | Change account policy-set and resolver tuple together without changing debt version before consumption | Reconstructed policy hash differs from the stored quote and consumption is rejected | `INV-AUTH-004`, `INV-REFI-001` |
| `P9Q-EQ-001` | Canonical `90/5/3/3/1` fixture | Gross `101`, credit `1`, net `100`; lender claim `95`; fee route net `5` | `INV-REFI-001`, `INV-INT-011` |
| `P9Q-EQ-002` | Arbitrary valid bounded integers | Exact equation and route reconciliation | `INV-INT-001`, `INV-INT-003` |
| `P9Q-EQ-003` | Credits equal fees plus penalties while lender claim is nonzero | Accepted; credit affects only fee/penalty route | `INV-INT-009`, `INV-INT-012` |
| `P9Q-EQ-004` | Credits exceed fees plus penalties | `InvalidQuoteInput`; no state | `INV-INT-009`, `INV-INT-012` |
| `P9Q-EQ-005` | Net payoff is zero | Rejected | `INV-REFI-001` |
| `P9Q-EQ-006` | Addition overflows `uint256` | Rejected with complete rollback | `INV-NUM-003`, `INV-LOAN-014` |
| `P9Q-EQ-007` | Capitalized interest or recoverable costs are nonzero | Rejected; neither amount is hidden or folded | `INV-INT-009`, `INV-REFI-001` |
| `P9Q-COMP-001` | Read a canonical quote | Exactly five entries, fixed order, exact codes and beneficiaries | `INV-REFI-001`, `INV-INT-011` |
| `P9Q-COMP-002` | A supported component amount is zero | Its fixed entry remains present | `INV-VER-002` |
| `P9Q-COMP-003` | Independently encode the component vector | Domain-separated hash equals stored/event hash | `INV-VER-001`, `INV-VER-002` |
| `P9Q-COMP-004` | Reorder, omit, duplicate, or alter a kind, amount, beneficiary, code, or credit | Different commitment and quote ID; never accepted as original | `INV-AUTH-004`, `INV-REFI-001` |
| `P9Q-ROUTE-001` | Independently encode the route | Exact ADR 0020 hash equals stored/event hash | `INV-VER-001`, `INV-VER-002` |
| `P9Q-ROUTE-002` | Substitute lender, fee beneficiary, policy, asset, token, component commitment, or route fact | Different hash and unconsumable quote | `INV-AUTH-004`, `INV-INT-011` |
| `P9Q-TIME-001` | `validUntil <= issuedAt` | `InvalidQuoteInput`; nonce unchanged | `INV-AUTH-007`, `INV-NUM-006` |
| `P9Q-TIME-002` | `validUntil == issuedAt + maximumValidity` | Accepted | `INV-AUTH-007`, `INV-NUM-006` |
| `P9Q-TIME-003` | Validity exceeds maximum by one second | Rejected; nonce unchanged | `INV-AUTH-007` |
| `P9Q-TIME-004` | Consume one second before expiry | Accepted when all other facts match | `INV-AUTH-007` |
| `P9Q-TIME-005` | Consume exactly at or after expiry | `QuoteExpired`; no consumption | `INV-AUTH-007` |
| `P9Q-TIME-006` | Read at or after expiry before persistence | Effective state is `EXPIRED` | `INV-LOAN-012` |
| `P9Q-TIME-007` | Invalidate after effective expiry | Persists `EXPIRED`, emits one terminal disposition | `INV-LOAN-015` |
| `P9Q-TIME-008` | Coordinator selects arbitrary valid `validUntil` values within the inclusive maximum | Each value is accepted as the sole caller-selected time input; `issuedAt` remains canonical block time | `INV-AUTH-002`, `INV-AUTH-007` |
| `P9Q-NONCE-001` | First quote succeeds, becomes terminal/effectively expired, then a second succeeds | Nonces `1`, `2`; distinct IDs | `INV-AUTH-006` |
| `P9Q-NONCE-002` | Failed issue between successes | Failure consumes no nonce | `INV-AUTH-006`, `INV-LOAN-014` |
| `P9Q-NONCE-003` | Quotes for different loans | Independent nonce sequences | `INV-AUTH-006` |
| `P9Q-NONCE-004` | Force nonce exhaustion at `uint64.max` in a test harness | `QuoteReplayConflict(bytes32(0))`; nonce cannot wrap to zero | `INV-AUTH-006`, `INV-NUM-003` |
| `P9Q-NONCE-005` | Force the derived quote ID to zero in a test harness | `QuoteReplayConflict(bytes32(0))` before every write; nonce and latest quote remain unchanged | `INV-AUTH-006`, `INV-LOAN-014` |
| `P9Q-NONCE-006` | Pre-materialize the derived nonzero quote ID in `_quotes` in a test harness | `QuoteReplayConflict(quoteId)` before every write; existing quote, components, nonce, and latest ID remain unchanged | `INV-AUTH-006`, `INV-LOAN-014` |
| `P9Q-LIVE-001` | Issue while the latest quote is effectively live | `InvalidQuoteInput`; prior quote and next nonce remain unchanged | `INV-LOAN-012`, `INV-LOAN-014` |
| `P9Q-LIVE-002` | Issue after latest quote is stored-terminal or effectively expired | Successor is the sole live quote; no implicit mutation of prior content | `INV-AUTH-007`, `INV-LOAN-015` |
| `P9Q-ID-001` | Independent `abi.encode` of all frozen quote fields | Digest equals stored key and `quoteId` | `INV-VER-001`, `INV-VER-002` |
| `P9Q-ID-002` | Use `abi.encodePacked`, include gross, include quote ID, or reorder fields | Digest differs and is rejected | `INV-AUTH-004`, `INV-VER-002` |
| `P9Q-ID-003` | Change each preimage field one at a time | Every changed preimage produces a different ID | `INV-AUTH-004` |
| `P9Q-ID-004` | Same economic fields on another engine address or chain | Different ID | `INV-AUTH-005` |
| `P9Q-EVT-001` | Successful issue | Exactly one `PayoffQuoteIssued`; every indexed and data field matches storage | `INV-LOAN-015` |
| `P9Q-VIEW-001` | Read unknown or zero quote | `UnknownQuote`, never a zero tuple | `INV-AUTH-001` |
| `P9Q-VIEW-002` | Repeatedly read a quote | Immutable tuple/components; only the defined effective expiry overlay changes | `INV-LOAN-004` |
| `P9Q-CONS-001` | Consume with exact stored and live version plus nonzero refinance/source IDs | Terminal `CONSUMED`; return, storage, and event agree | `INV-REFI-001`, `INV-LOAN-015` |
| `P9Q-CONS-002` | Caller expected version differs from quote | `StaleDebtVersion`; no disposition | `INV-REFI-001` |
| `P9Q-CONS-003` | Live version differs while caller supplies either old or live version | `StaleDebtVersion`; caller cannot select truth | `INV-REFI-001`, `INV-AUTH-004` |
| `P9Q-CONS-004` | Repayment, accrual, waiver, correction, or restructuring bumps version | Original quote cannot consume | `INV-REFI-001`, `INV-INT-003` |
| `P9Q-CONS-005` | Dependency changes amount, position, policy, recipient, asset, token, or route without bumping version | Full revalidation rejects consumption | `INV-AUTH-004`, `INV-REFI-001` |
| `P9Q-CONS-006` | Zero refinance ID or source-event ID | `InvalidQuoteInput`; no disposition | `INV-AUTH-006`, `INV-LOAN-015` |
| `P9Q-CONS-007` | Stored content or quote ID does not reconstruct from the exact issued facts | `InvalidQuoteInput`; no disposition | `INV-VER-001`, `INV-REFI-001` |
| `P9Q-TERM-001` | Invalidate an issued, unexpired quote | Terminal `INVALIDATED`; one event | `INV-LOAN-012`, `INV-LOAN-015` |
| `P9Q-TERM-002` | Consume invalidated/expired quote or invalidate consumed quote | `QuoteTerminal` or `QuoteExpired` as defined above; no mutation | `INV-LOAN-012` |
| `P9Q-TERM-003` | Invalidate an unexpired quote with zero source-event ID | `InvalidQuoteInput`; no `INVALIDATED` disposition or event | `INV-AUTH-006`, `INV-LOAN-015` |
| `P9Q-TERM-004` | Persist effective expiry with zero source-event ID | `InvalidQuoteInput`; no `EXPIRED` disposition or event | `INV-AUTH-006`, `INV-LOAN-015` |
| `P9Q-TERM-005` | Combine zero invalidation source with an unauthorized caller, unknown quote, or existing terminal disposition | Authorization fails first, then unknown-quote validation, then zero-source validation, all before terminal replay classification | `INV-AUTH-001`, `INV-LOAN-015` |
| `P9Q-RPL-001` | Exact consume retry | Same consumed quote; no second event/effect | `INV-ACC-004`, `REC-002` |
| `P9Q-RPL-002` | Change refinance, source, or expected version after consumption | `QuoteReplayConflict` | `INV-AUTH-006`, `REC-002` |
| `P9Q-RPL-003` | Exact invalidation/expiry-persistence retry | No-op; no second event | `INV-ACC-004`, `REC-002` |
| `P9Q-RPL-004` | Change source after invalidation/expiry persistence | `QuoteReplayConflict` | `INV-AUTH-006`, `REC-002` |
| `P9Q-RPL-005` | Exact consume retry after the successful refinance changed live debt | Original consumed quote is returned; the retry does not re-execute first-consumption validation or value logic | `INV-ACC-004`, `REC-002` |
| `P9Q-RPL-006` | Exact invalidation retry after canonical debt changed | No-op based on the stored quote version; no second event | `INV-ACC-004`, `REC-002` |
| `P9Q-NOVAL-001` | Issue, consume, invalidate, reject a concurrent issue, and replay | No token/ETH/allowance/debt/lien/journal effect | `INV-ACC-001`, `INV-AUTH-004` |
| `P9Q-NOVAL-002` | Attach `msg.value` to any mutator | Nonpayable rejection and complete pre-state preservation | `INV-ACC-001`, `INV-LOAN-014` |
| `P9Q-NOVAL-003` | Use an instrumented synthetic token | Token observes zero calls from the quote engine | `INV-ASSET-003`, `INV-AUTH-004` |
| `P9Q-NOVAL-004` | Place forced ETH on the engine in the harness | No function can transfer or rescue it | `INV-AUTH-004` |
| `P9Q-LOCAL-001` | Scan dependencies, bytecode surface, fixtures, and deployment inputs | No Phase 8 route, external provider, production key, public network, real asset, or real-fund authority | ADR 0019 boundary |
| `P9Q-LOCAL-002` | Run every semantic flow with the exact committed local token on chain 31337 | Accepted local fixture; no external provider or real-value dependency | ADR 0019 boundary |
| `P9Q-LOCAL-003` | Attempt issue and first consumption with `block.chainid != 31337` | `InvalidQuoteInput`; no quote, nonce, or disposition state changes | `INV-AUTH-004`, ADR 0019 boundary |

## Fuzz requirements

Fuzz tests MUST use bounded valid generators and separate invalid/overflow generators.
At minimum they prove:

1. `grossPayoff == principal + accruedInterest + fees + penalties`.
2. `credits <= fees + penalties` and `netPayoff > 0` for every accepted quote.
3. The fixed component amounts, beneficiaries, codes, and route netting reconcile.
4. The independent policy, component, route, and quote encoders equal the engine for every
   valid generated input.
5. Flipping any bound policy, component, route, or quote preimage field changes the
   relevant commitment or quote ID.
6. A successor issue or first consumption cannot accept a changed policy commitment,
   including a coordinated policy-set and resolver-tuple change without a debt-version
   change.
7. Factory/account position-manager disagreement is rejected even when both managers
   return identical position contents.
8. Failed issuance never advances a nonce or changes the one-live-quote state.
9. Successful nonces are exactly `1..n` per loan without gaps caused by failures.
10. Derived quote IDs are nonzero and unmaterialized before issue; forced zero IDs and
    collisions fail before every write and nonce change.
11. A stale quote cannot consume for any caller-supplied expected version.
12. The coordinator-selected valid time interval is exactly `[issuedAt, validUntil)` and
    no caller value can replace `issuedAt`.
13. Every persisted invalidation or expiry has a nonzero source-event ID.
14. Terminal dispositions are monotonic.
15. Exact retries are idempotent and changed retries conflict.
16. The exact token runtime code hash is invariant under the pinned toolchain, and any
    generated wrong-runtime token is rejected.
17. No quote action changes a tracked ETH balance, token balance, allowance, debt amount,
    position claim, or recipient balance.

The existing Solidity conceptual-order digest and the committed Python/TypeScript
digest MUST remain stable. A Solidity vector using the exact Python/TypeScript fixture
MUST reproduce `632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058`.
An engine-issued quote MUST also be reproducible by an independent reference encoder;
the fixed golden context is not a production policy source.

## Stateful invariant harness

The handler exposes arbitrary ordered actions:

```text
issue
warp
bump debt version
mutate debt without version
replace registry or factory account
replace factory position manager with identical-content manager
mutate account coordinator or position-manager binding
mutate position owner or claim
mutate policy-set and resolver tuple independently or together
mutate policy, asset, token, token runtime, beneficiary, or route
switch chain ID away from or back to 31337
attempt successor issue under changed policy binding
force zero or materialized quote ID
consume exact
consume stale
consume substituted
invalidate exact
invalidate changed
invalidate with zero source event before and after expiry
retry exact
attack as unauthorized caller
```

The handler maintains an independent model of every successfully issued quote, nonce,
effective live quote, immutable tuple, component vector, and terminal disposition. The
invariant suite proves after every generated sequence:

- every successful `(loanId, quoteNonce)` maps to exactly one immutable quote;
- quote IDs equal the independent reference preimage, are nonzero, and are unique and
  previously unmaterialized in the generated state;
- per-loan nonces are gapless over successful issuance and never wrap;
- at most one quote per loan is effectively `ISSUED`;
- stored quote content and components never change after issuance;
- every stored policy hash equals the independent exact policy preimage, and successor
  quotes for one `(loanId, loanAccount)` preserve that commitment;
- the factory and account configuration identify the same deployed position manager;
- every accepted settlement token has the pinned local runtime code hash and every
  accepted engine runs on chain `31337`;
- no stale, substituted, or expired quote reaches `CONSUMED`;
- each quote has at most one terminal disposition and at most one consuming refinance;
- every persisted terminal disposition has a nonzero source-event ID;
- terminal state never returns to `ISSUED` or changes to another terminal state;
- exact retries add no event or state effect;
- failed calls preserve the modeled pre-state;
- unknown quotes never become materialized by a failed call; and
- the engine, account, token, beneficiaries, registry, factory, position manager, and
  policy source have unchanged economic balances and claims.

Foundry invariant settings MUST be bounded but nontrivial and MUST target only the
handler selectors. A deterministic seed that reproduces every discovered failure is
retained in the test evidence.

## Required synthetic harnesses and mocks

| Harness | Required behavior |
|---|---|
| Canonical loan registry | Returns loan account/version and supports adversarial account substitution for negative tests |
| Approved Phase 9 factory | Independently returns the canonical account and position manager and exposes disagreement scenarios for each |
| Phase 9 loan account | Returns configuration/debt and supports controlled version, component, lifecycle, coordinator, position-manager, asset, token, and policy-set mutation |
| Position manager | Exposes zero, one, and multiple active positions plus owner/claim mutation and an identical-content attacker-manager variant |
| Immutable quote-policy source | Implements the exact internal `resolvePayoffQuotePolicy` selector and returns the valid policy, policy-set binding, beneficiary, asset, token, maximum validity, and active flag |
| Adversarial policy source | Reverts, returns malformed data, or substitutes one fact at a time |
| Coordinator caller proxy | Is the exact constructor-bound authorized caller and records returned/reverted data |
| Unauthorized caller proxies | Exercise borrower, lender, account, factory, policy, and arbitrary identities |
| Instrumented synthetic token | Has fixed local balances/allowances and records any attempted token call; an exact-metadata wrong-runtime variant proves code-hash rejection |
| Pure reference model | Independently calculates the exact policy hash, equations, fixed components, component hash, route hash, and quote ID |
| Quote-ID collision harness | Forces zero and already materialized derived IDs and snapshots all quote, component, nonce, and latest-ID storage before the call |
| Invariant handler/model | Generates arbitrary action sequences and retains the independent expected state |
| Constructor-cycle deployment harness | Deploys both contracts in one transaction, predicts consecutive CREATE addresses, controls both constructor argument lists, records evidence, verifies reciprocal bindings, and injects nonce/argument perturbations |

All identities, contracts, balances, tokens, and evidence in these harnesses are
disposable local fixtures. The tests MUST NOT load a production credential, contact an
external payment/identity/oracle/bridge/provider endpoint, fork a public network, or
represent a real loan, lender claim, asset, reserve, or fund.

## Threat matrix

| Threat | Required control | Mandatory evidence |
|---|---|---|
| Caller supplies or omits debt components | Engine reads the complete canonical account state | Source-substitution and component-omission tests |
| Registry/account substitution | Registry, approved factory, and account configuration agree | Mismatch tests at issue and consume |
| Position-manager or lender substitution | Factory and account bind the same deployed manager; one active position plus policy-bound fee beneficiary; commitments bind recipients | Manager disagreement with identical contents plus position/policy mutation tests |
| Credit reduces lender claim | Credit is capped by fees plus penalties and bound to that route | Boundary fuzz around `fees + penalties` |
| Aggregate-valid but misrouted quote | Fixed component vector and domain-separated component/route commitments | Reorder/recipient/code/route mutation tests |
| Stale debt quote | Stored version and full current state are revalidated | Each debt-changing cause plus no-version adversarial mutation |
| Opaque, mutable, or substituted policy | Engine reconstructs the exact domain-separated policy commitment; successors preserve it and consumption matches stored policy | Every-field encoder negatives, coordinated policy-set/resolver mutation, and successor-policy-change tests |
| Public-chain or lookalike-token bleed | Issue/consume require chain 31337 and the pinned exact token runtime code hash | Wrong-chain issue/consume, golden runtime hash, and exact-metadata wrong-runtime negatives |
| Expiry boundary bypass | Half-open validity and effective/persistent expiry | Before/at/after deadline tests |
| Multiple live quotes | Reject issuance while the latest quote is effectively live | Sequential issue and stateful invariant tests |
| Nonce gap, reuse, or wrap | Successful per-loan sequence starts at one and is checked | Failure-between-successes and max-nonce tests |
| Zero or colliding quote identity | Zero and already materialized derived IDs fail before every write and nonce advancement | Forced-zero and pre-materialized-ID storage-preservation tests |
| Terminal replay or changed retry | Exact idempotency plus conflict detection | Consume/invalidate replay matrix |
| Unattributed invalidation | Every invalidation and expiry persistence requires a nonzero source-event ID | Zero-ID negatives before and after expiry |
| Storage griefing by arbitrary issuers | Coordinator-only issuance | Unauthorized issuer tests |
| Constructor cycle creates an open or mutable authority window | Single-transaction consecutive CREATE prediction plus reciprocal immutable binding; no setter | Positive deployment evidence, nonce/argument perturbation negatives, and explicit post-deployment evidence rejection/reset behavior |
| Dependency failure leaves partial state | Checks precede commitment and EVM rollback is complete | Reverting/malformed dependency tests |
| Packed or cross-language digest drift | Exact `abi.encode` domains and committed vectors | Solidity/model/Python/TypeScript differential tests |
| Quote mistaken for payment authority | Engine has no value-moving selector or call path | Instrumented token, ETH, debt, and static-surface tests |
| Phase 8 or production authority bleed | No Phase 8 dependency, public network, provider, key, or real asset | Dependency and release-boundary scan |

## Invariant and freeze traceability

| Property | Payoff-quote obligation |
|---|---|
| `INV-REFI-001` | Canonical complete debt, expiry, factory/account position authority, component beneficiaries, exact policy commitment, local asset, route, and version are bound and revalidated |
| `INV-AUTH-001` | All mutators deny every caller except the constructor-bound coordinator |
| `INV-AUTH-002` | The coordinator can record only a derived quote/disposition and select bounded `validUntil`; it cannot select another economic or time fact or move value |
| `INV-AUTH-003` | No ordinary administrative or reconciliation role exists in the engine; broader role separation remains an integration obligation |
| `INV-AUTH-004` | There is no rescue, override, arbitrary-call, recipient-selection, component-input, or value-moving path |
| `INV-AUTH-005` | Policy, quote, component, and route domains bind the contract, chain, authority, entity, economics, nonce, and expiry; the engine accepts no signature |
| `INV-AUTH-006` | Per-loan nonces begin at one, advance on success only, never wrap, zero/colliding quote identities fail before writes, and terminal retries are idempotent or conflicting |
| `INV-AUTH-007` | Validity is exactly `[issuedAt, validUntil)` with an immutable maximum and terminal expiry behavior |
| `INV-AUTH-008` | No delegation selector or delegate scope exists; any future delegation requires a separate decision |
| `INV-AUTH-009` | No revocable credential is consumed; the independently reconstructed policy commitment cannot be replaced at successor issue or consumption by a later policy response |
| `INV-INT-001` | Unsigned canonical components, checked addition, bounded credit, and positive net prevent negative debt representation |
| `INV-INT-002` through `INV-INT-008` | The engine does not originate principal or accrue interest; it depends on and snapshots the canonical account result without recomputation |
| `INV-INT-009` | Fees and penalties come only from canonical debt and the policy-bound route; credits cannot exceed them |
| `INV-INT-010` | The engine adds no fee-on-fee or hidden component |
| `INV-INT-011` | Fixed components and route commitments preserve lender and fee/penalty priority |
| `INV-INT-012` | Credits and net bounds prevent payoff underflow or recipient over-allocation |
| Historical ABI freeze | No selector, event, error, tuple field/order, or mutability change is permitted |
| Historical storage freeze | No mapping, field, type, slot, offset, inheritance, or compiler-setting drift is permitted |
| Implementation checkpoint | Current source hashes and complete source-set evidence are added separately without rewriting the historical freeze |

## Compatibility and completion gates

`UNI-PAYOFF-001` remains incomplete unless all of the following are true:

1. ADR 0020 is accepted and this matrix contains no unresolved semantic placeholder.
2. Every mandatory `P9Q-*` row passes locally and in CI.
3. Unit, fuzz, stateful invariant, golden-vector, and negative authorization tests pass.
4. The frozen `IPayoffQuoteEngineV2` external ABI remains byte-for-byte compatible.
5. `PayoffQuoteEngine` storage declaration order, slot, offset, and type remain identical
   to the accepted Phase 9 storage snapshot.
6. ABI, storage, source-set, generated-freshness, formatter, compiler-setting, contract-
   size, privileged-surface, secret, and forbidden-dependency checks pass.
7. The historical freeze manifest/review remains immutable, while the implementation
   receives a separate deterministic exact-source checkpoint naming both baselines.
8. The always-run boundary checker permits business logic only for the ADR-activated
   payoff engine and continues to require the canonical freeze body for unopened Phase
   9 mutators.
9. The implementation removes the fail-closed stub behavior only for the reviewed quote
   engine; it does not activate refinance, loan, lien, position, protection, recovery,
   or token authority outside this work package.
10. No quote call moves value or changes debt, position claims, custody, lien, ledger, or
    recipient balances.
11. The exact policy preimage has independent Solidity and reference-model vectors;
    successor issuance and first consumption reject every changed commitment field.
12. Factory/account position-manager equality, deployed code, and identical-content
    attacker-manager negatives pass at issue and consume.
13. The engine rejects another chain, the pinned local token runtime code hash equals
    `0xb4cb1bc940c6783f3ecad43dc045c0fa93b02fae77d6e874a8adaf7216c907e5`, and a
    matching-metadata wrong-runtime token is rejected.
14. Zero and materialized quote-ID collision tests prove complete pre-write preservation,
    and zero source-event invalidations fail before and after expiry.
15. The single-transaction constructor-cycle deployment and its post-deployment evidence
    rejection/reset path pass without claiming that off-chain reads revert history.
16. No real fund, production key, external provider, public network, real asset, or live
    loan is involved.
17. Independent architecture and security review approve the exact implementation head.

Primary traceability is `INV-REFI-001`, `INV-AUTH-001` through `INV-AUTH-007`,
`INV-LOAN-004`, `INV-LOAN-012` through `INV-LOAN-015`, `INV-INT-001`,
`INV-INT-003`, `INV-INT-009` through `INV-INT-012`, `INV-NUM-003`,
`INV-NUM-006`, `INV-VER-001`, `INV-VER-002`, `INV-FUND-004`,
`INV-FUND-005`, `INV-ACC-004`, and `REC-002`.
Properties outside the quote engine's non-value-moving boundary remain required by the
integrated Phase 9 exit but are not claimed complete by this work package.
