# Phase 9 Refinance Acceptance and Threat Matrix

Status: normative design and compatibility gate; implementation not accepted

Date: 2026-07-26

## Purpose and authority

This document is the acceptance contract for the first synthetic-local atomic
refinance slice governed by ADR 0019, ADR 0020, and ADR 0021. ADR 0021 controls
where earlier Phase 9 prose describes a state or authority that the frozen five
coordinator selectors cannot reach.

This is a boundary-only milestone. It does not authorize a successful Solidity
refinance path, mark `UNI-REFI-001` or `UNI-REFI-002` complete, authorize real
funds, or authorize any public-network or production deployment.

The implementation may activate only the exact methods listed by ADR 0021 and
only after every applicable `P9R-*` row below passes. A passing document review
is not implementation evidence.

## Fixed first-slice interpretation

- The frozen coordinator surface consists only of `requestRefinance`,
  `recordFundingCommitment`, `executeRefinance`, `cancelRefinance`, and
  `refundCommitment`.
- `requestRefinance` is the canonical borrower's direct acceptance of the exact
  proposal. Caller-supplied refinance/quote identities and derived state are zero;
  the coordinator atomically bootstraps the old fixture when needed, issues the
  quote, derives the identities, creates dormant replacement clones, and first
  stores `ACCEPTED`. `REQUESTED`, `QUOTED`, and `OFFERED` are off-chain evidence
  stages and `REJECTED` is an off-chain outcome.
- The first successful funding commitment advances the refinance from `ACCEPTED`
  to `FUNDING_ESCROWED`. Additional partial funding remains
  `FUNDING_ESCROWED`; execution requires exact full funding.
- The first-slice replacement principal is exactly the funding amount, and the
  funding amount is exactly old net payoff plus refinance fee plus borrower
  proceeds.
- Canonical asset, policy, loan, account, position, custody, and lien resolvers
  supply every authoritative fact. Calldata and service payloads only propose
  values that the coordinator reconstructs and verifies.
- Direct token donations to the coordinator create no escrow liability or claim,
  do not fund or block a refinance, are never swept, and are removed only by the
  disposable chain-31337 reset.
- `RefinanceStateTransitioned` and `UnknownFundingCommitment(bytes32)` on the
  refinance coordinator plus `UnknownLienHandoff(bytes32)` on the lien registry are
  the only additive ABI items authorized by ADR 0021. No new selector or other event/error, tuple field, storage field,
  inheritance edge, slot, offset, type, or field order is authorized.

## Mandatory acceptance matrix

Each identifier is stable. Tests and evidence MUST cite the exact three-digit
identifier. One test may cover several rows only when its assertion output names
every covered row.

### Compatibility, checkpoint, and risk gates

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-COMPAT-001` | Compare every existing ABI item and storage declaration with the historical `UNI-ABI-009` snapshot | Every historical item is byte-for-byte unchanged | ADR 0021 sections 1 and 3 |
| `P9R-COMPAT-002` | Compare each candidate ABI with the historical snapshot plus the reviewed per-contract additive allowlist | The coordinator adds only the exact typed transition event and funding error; the lien registry adds only the exact typed handoff error | ADR 0021 section 3 |
| `P9R-COMPAT-003` | Scan the candidate source set for added selectors, other events/errors, tuple/storage fields, bases, and layout drift | No unapproved surface or storage change exists | ADR 0021 section 3 |
| `P9R-CHECK-001` | Evaluate the method-level activation manifest against the exact source head | Only ADR-activated methods may differ from their fail-closed bodies | ADR 0021 section 17 |
| `P9R-CHECK-002` | Attempt to accept only one refinance backlog item or only part of the method bundle | Activation fails unless `UNI-REFI-001` and `UNI-REFI-002` are bundled and every required method/evidence row passes | ADR 0021 section 17 |
| `P9R-RISK-001` | Cross-check the risk and assumption registers against this matrix | Every existential or critical refinance risk and assumption has an owner, mitigation, evidence target, and status | ADR 0021 Verification and registered risk/assumption evidence |

### Deployment and local bootstrap

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-DEPLOY-001` | Deploy the full refinance dependency graph from a fresh chain-31337 broadcaster bound as synthetic governance executor, with a distinct synthetic local administrator | Every top-level dependency is created by sequential top-level `CREATE` in the recorded order; the payoff engine is immediately before the coordinator; the only following transaction is the predeclared zero-value factory-role initialization | ADR 0021 section 18 |
| `P9R-DEPLOY-002` | Independently predict the coordinator, verify reciprocal constructor bindings, and verify final `grantRole(LOAN_FACTORY_ROLE, phase9Factory, type(uint64).max)` calldata/receipt/log/state | Lien registry and payoff engine bind the exact predicted coordinator; coordinator binds exact dependencies; the exact factory alone has the permanent loan-factory role before any business action, with no other grant/admin change | ADR 0021 section 18 |
| `P9R-DEPLOY-003` | Verify every manifest transaction, receipt/log, code, constructor argument, runtime hash, dependency getter, role expiry/membership, and reviewed storage slot | Candidate and post-broadcast evidence agree exactly through canonical block-hash reads; missing, stale, or mismatched evidence fails | Refinance deployment evidence |
| `P9R-DEPLOY-004` | Attempt public-chain, reused-key, CREATE2 top-level, reordered/undeclared transaction, mismatched/failed/late role initialization, post-hoc repair, or external-provider deployment | Every attempt is rejected, requires bounded reset, and creates no accepted deployment checkpoint | ADR 0021 sections 1 and 18 |
| `P9R-BOOT-001` | Request when the unique old bootstrap clone/records are absent | The borrower calls the coordinator; the coordinator-only factory call resolves borrower/configuration itself, initializes exact `ACTIVE/CURRENT` old debt, then installs positions/custody/liens before quote issuance in one transaction; old position owner/beneficiary/claims equal `oldLender` and the old debt/quote route with no alternate | ADR 0021 sections 6, 8, and 11 |
| `P9R-BOOT-002` | Retry exact bootstrap records; mutate one; invoke after the unique marker is consumed or off chain 31337 | Exact existing records are inert; any mismatch or unauthorized reuse reverts the complete request, including clone and quote effects | ADR 0021 section 11 |
| `P9R-BOOT-003` | Observe replacement creation during a successful request | No replacement preexists; after internal quote and refinance-ID derivation the coordinator creates deterministic clones as `CREATED/NONE`, zero debt, no position/lien/custody, bound to that refinance only | ADR 0021 sections 6 and 11 |
| `P9R-BOOT-004` | Force clone-address, initialization, registration, creation-ID, nonce, implementation, position, custody, lien, quote, or final validation failure | The entire borrower request reverts bootstrap, quote, replacement clones, registry effects, nonce, state, and events | ADR 0021 sections 6 and 11 |
| `P9R-BOOT-005` | Recalculate new-loan/bootstrap/creation/clone/activation/tranche/position/custody/lien identities independently and replay factory/setup calls | Every preimage is acyclic; factory/setup exact replay is inert or returns stored clones, changed reuse conflicts, while exact request replay rejects before a quote | Refinance reference evidence |

### Caller authority and identities

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-AUTH-001` | Call `requestRefinance` as borrower and as every other role | Only the exact canonical borrower can create the accepted record | ADR 0021 section 5 |
| `P9R-AUTH-002` | Call `recordFundingCommitment` as the named funder and substituted callers | Only the commitment's canonical funder can fund it | ADR 0021 section 5 |
| `P9R-AUTH-003` | Call `executeRefinance` from arbitrary callers after exact readiness and before readiness | Execution is permissionless only after all immutable facts and full funding validate | ADR 0021 section 5 |
| `P9R-AUTH-004` | Cancel before expiry as borrower and substituted callers | Only the borrower can cancel before expiry | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-005` | Persist expiry at and after the deadline as arbitrary callers | Expiry is permissionless and cannot select a recipient or economic value | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-006` | Refund from arbitrary callers with recipient substitutions | Refund is permissionless but always pays the stored commitment funder the stored amount | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-007` | Exercise pause/emergency authority before and after accepted funding | It may stop new requests or commitments but cannot alter accepted facts, redirect value, sweep donations, or block valid exit/refund | ADR 0021 section 5 |
| `P9R-AUTH-008` | Scan for delegation, signature, arbitrary-call, rescue, sweep, recipient-selection, and operator override paths | No such authority is reachable in the first slice | ADR 0021 sections 1 and 5 |

### Identity, schema boundary, and canonical sources

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-ID-001` | Reconstruct refinance, policy, commitment, creation, operation, and result identities in Solidity and independent models | Every digest uses the exact domain and typed `abi.encode` preimage in the reference-evidence document | ADR 0021 sections 8, 11, 12, and 16 |
| `P9R-ID-002` | Exercise wire normalization for identifier/loan hex, EVM PartyId, Money decimal/asset, timestamp, and policy reference | Only the exact lowercase widths, ranges, `asset:phase9:p9unit` direct mapping, zero nanos, and exact policy ID/version/hash pass | ADR 0021 section 4 and reference evidence |
| `P9R-ID-003` | Submit nonzero caller refinance/quote/request digest/derived state and concurrent same/next nonce requests, then repeat success | Derived input fails before effects; the high-bit lock permits one owner, and concurrent/exact repeat fails before another quote while later released nonce gets a distinct quote | ADR 0021 sections 4, 6, and 16 |
| `P9R-ID-004` | Encode Protobuf `new_position_manager` with 0, 19, 20, 21, and 32 bytes | Only exactly 20 bytes is structurally admissible | ADR 0021 sections 6 and 8 |
| `P9R-ID-005` | Decode the 20-byte manager as zero, exact predicted factory manager, and substituted nonzero addresses | Only the nonzero address equal to the factory-salt prediction and resolved creation/account binding passes | ADR 0021 sections 6, 8, and 10 |
| `P9R-ID-006` | Trace validation order around `new_position_manager` | Length, nonzero, prediction, and resolver equality checks occur before refinance-ID reconstruction and before any effect | Refinance reference evidence |
| `P9R-SRC-001` | Resolve old bootstrap and replacement creation/loan facts through policy registry, loan registry, and factory at request/execution; substitute the registry account or premark the old loan terminal | The missing old clone may be created only by unique bootstrap; replacement must be absent at entry then exact dormant; every registered/deployed fact agrees, and mismatch or preterminal state fails before effects | ADR 0021 sections 6, 8, 11, and 14 |
| `P9R-SRC-002` | Mutate either account configuration or factory manager | Factory and account manager disagreement fails, including an identical-content attacker manager | ADR 0021 sections 6 and 10 |
| `P9R-SRC-003` | Resolve settlement and custody asset tuples and independently inspect each token | Active exact-balance-delta address/code/runtime agreement holds; settlement matches coordinator/accounts while custody may be distinct but must match bootstrap identity and deployed code | ADR 0021 sections 7 and 9 |
| `P9R-SRC-004` | Mutate each creation/bootstrap/refinance policy fact and vector; exceed 16 collateral, 32 commitments, 8 tranches, or 32 positions | Exact reconstruction/caps fail before loops or effects; caller/service values never override a resolver | ADR 0021 section 8 |
| `P9R-SRC-005` | Substitute bootstrap custody/lien/token/code/quantity/allowance/balance/attribution facts, inject fee/rebase/callback/reentrancy, or replay exact records | Missing custody pulls exact borrower tokens and records `HELD`/total before lien; exact replay validates without retransfer; every mismatch/failure reverts the whole request before a false lien or quote | ADR 0021 section 9 |
| `P9R-SRC-006` | Change canonical debt, quote version, policy, asset, collateral, account, or manager after acceptance | First execution rejects the stale/substituted graph without consuming the quote or changing value/claims | ADR 0021 sections 6 through 10 |

### Reachable state and views

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-STATE-001` | Submit each nonzero caller-supplied refinance ID, quote ID, request digest, state, counter, or terminal hash | Only zero derived input is accepted; coordinator internally derives identities and storage begins `ACCEPTED`, version 1 | ADR 0021 sections 2, 4, and 6 |
| `P9R-STATE-002` | Exercise all state edges with the tagged old-loan lock | Only the exact graph persists; first/later funding is `FUNDING_ESCROWED`; `ACCEPTED`/escrow/refundable retain the lock and exact terminal states release it after effects | ADR 0021 sections 2, 6, 12, and 13 |
| `P9R-STATE-003` | Attempt to persist `REQUESTED`, `QUOTED`, `OFFERED`, `REJECTED`, or `DISPUTED` | No frozen selector can persist those states in this slice | ADR 0021 section 2 |
| `P9R-STATE-004` | Revert execution after the transaction-local `EXECUTING` write | No `EXECUTING` state, version, event, quote disposition, or economic effect survives | ADR 0021 sections 2 and 14 |
| `P9R-VIEW-001` | Query every refinance/terminal/commitment-list/escrow/commitment/lien/handoff and boolean membership/processed view for unknown, known nonterminal, and terminal IDs | Unknown refinance-scoped views revert `UnknownRefinance`; unknown commitment/lien/handoff use their exact typed errors; known nonterminal terminal result is canonical zero; boolean membership/processed views may return false | ADR 0021 sections 3 and 16 |

### Funding and escrow

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-FUND-001` | Submit a commitment with each non-`NONE` state or nonzero funding result | It fails before token, storage, counter, or event effects | ADR 0021 sections 4 and 12 |
| `P9R-FUND-002` | Fund separately below, at, and above the exact remaining amount | First funding reaches `FUNDING_ESCROWED`, later partial/full funding stays there, execution requires equality, and overfunding fails | ADR 0021 section 12 |
| `P9R-FUND-003` | Use zero/duplicate or changed-reuse IDs, positions, tranches, funders, amounts, nonces, bad digests, over-32 count, or expired requests | Invalid/changed reuse fails atomically; exact commitment repeat is inert with no transfer/write/event | ADR 0021 sections 10, 12, and 16 |
| `P9R-FUND-004` | Exercise transfer failure, fee-on-transfer, rebasing/lookalike token, and balance-delta mismatch | No commitment is recorded unless exact coordinator and funder deltas equal the commitment | ADR 0021 sections 7 and 12 |
| `P9R-FUND-005` | Compare accepted commitment order and complete position/tranche allocation | Every commitment maps once to one canonical active position; claims and all aggregate amounts equal `newPrincipal == fundingAmount` | ADR 0021 sections 10 and 12 |

### Atomic execution

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-EXEC-001` | Execute with underfunding, overfunding, at/after expiry, stale quote, or changed canonical graph | Execution fails before any durable effect | ADR 0021 sections 12 through 15 |
| `P9R-EXEC-002` | Validate first-slice equations with zero, boundary, and overflow-adjacent inputs | `newPrincipal == fundingAmount == oldNetPayoff + refinanceFee + borrowerProceeds` with checked arithmetic | ADR 0021 sections 10 and 14 |
| `P9R-EXEC-003` | Trace the success call order | Operation/reentrancy validation, canonical revalidation, quote consumption, quote-component payouts, old-account payoff, sorted lien handoffs, tranche/position registration and replacement activation, refinance-fee payout, borrower-proceeds payout, commitment consumption/escrow clearing, completion evidence, and exact delta proof occur in that order in one transaction | ADR 0021 section 14 |
| `P9R-EXEC-004` | Measure old lender, fee beneficiary, borrower, and coordinator attributed-escrow balance deltas | Each recipient receives exactly its component and attributed escrow reaches zero; unrelated token surplus is excluded | ADR 0021 sections 14 and 15 |
| `P9R-EXEC-005` | Inspect nonterminal registry state before payoff, exact old debt and terminal registry state after payoff, unchanged raw tranche/position/checkpoint state, then use a malicious stale `ACTIVE` position against every consumer | The registered old account atomically marks the exact loan terminal; coordinator re-verifies terminal registry/factory/account identity; debt is `CLOSED/TERMINAL`, every debt/loss/credit amount is zero, version/nonce advance once, and terms/time/schedule stay fixed; raw issuance facts remain unchanged but effective claim/vote/payment rights are zero, all position mutations remain frozen, and quote/payment/distribution/transfer/snapshot/vote/restructure/lien/collateral/liquidation/recovery/protection cannot authorize | ADR 0021 section 14 |
| `P9R-EXEC-006` | Inspect all ordered liens during success and inject a failure at each handoff | Pending targets never become enforceable; old liens end before new liens activate; any failure rolls all records back | ADR 0021 sections 9 and 14 |
| `P9R-EXEC-007` | Inspect replacement debt, tranches, positions, and manager after success | The complete immutable policy tuple activates once with every funded claim exactly represented and no unfunded claim | ADR 0021 sections 10 and 14 |
| `P9R-EXEC-008` | Inject a revert at every dependency call and external token transfer, including registry mark failure, false terminal postcondition, wrong registered account, and registry reentry | Registry terminality, debt, quote, payouts, liens, claims, escrow, versions, nonces, counters, results, and events revert to the exact pre-state | ADR 0021 sections 14 and 15 |
| `P9R-EXEC-009` | Retry exact and changed execute operation IDs after terminal lock release | Exact replay branches before lock ownership and returns the stored result with no second effect/event; changed reuse conflicts | ADR 0021 section 16 |

### Exit, replacement, time, and failure handling

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-EXIT-001` | Cancel/expire with no funding using reasons 0/1/2 and injected quote-invalidation failure | Reason zero fails; quote/refinance terminalize atomically with bound disposition/source, then owned lock releases; failure rolls everything back | ADR 0021 sections 6, 13, and 16 |
| `P9R-EXIT-002` | Cancel/expire after partial/full funding and try a later old-loan request | Nonterminal `REFUNDABLE` keeps terminal result/evidence zero and retains the active lock; terminal quote cannot consume and no later request proceeds until final refund | ADR 0021 sections 6 and 13 |
| `P9R-EXIT-003` | Refund commitments in arbitrary order and through arbitrary callers; reconcile ordered stored commitments to events/results | Each stored funder receives its exact amount once; one matched refund transition/result exists per commitment with no missing/duplicate/unmatched event; partial refunds remain `REFUNDABLE` | ADR 0021 sections 13 and 16 |
| `P9R-EXIT-004` | Refund the last liability and reconstruct the aggregate cross-language before exact/changed retry | Last refund stores `REFUNDED` from ordered stored facts with immutable funding proofs and zero liabilities, then permissionlessly releases the owned lock; exact replay after release is inert and changed reuse conflicts | ADR 0021 sections 6, 13, and 16 and reference evidence |
| `P9R-EXIT-005` | Attempt old-quote consume plus funding/execution/cancellation/refund on incompatible or terminal states; replay exact/changed invalidate source | Old quote cannot consume after `CANCELLED`/`REFUNDABLE`/`EXPIRED`; invalid edges fail, exact cancel/invalidate replay is inert, changed source conflicts, and evidence/economics do not drift | ADR 0021 sections 2, 13, and 16 |
| `P9R-RPL-001` | Compare policy tranches/positions with commitment set | `1..8` tranches and `1..32` positions are strictly ordered, unique, complete, aggregate exactly, and every position owner equals its commitment funder | ADR 0021 section 10 |
| `P9R-RPL-002` | Mutate replacement lifecycle, servicing, versions, schedule, maturity, template active refinance, dormant clone, or factory refinance binding | Policy template requires zero active refinance; coordinator injects only the derived ID at activation; every mismatch or terminal/cross-refinance reuse fails | ADR 0021 sections 10, 11, and 13 |
| `P9R-RPL-003` | Add accrued/capitalized/fee/loss/credit/restructure amounts at first activation | Any nonzero prohibited component fails | ADR 0021 section 10 |
| `P9R-RPL-004` | Substitute a position owner/claim/tranche or add/remove a commitment | Exact one-to-one commitment-position mapping fails | ADR 0021 section 10 |
| `P9R-TIME-001` | Test one second before, exactly at, and one second after `expiresAt`, including maximum validity, and attempt any refinance/quote deadline mismatch | Request passes the proposal `expiresAt` as quote `validUntil` and stores exact equality; acceptance/funding/execution use `< expiresAt`; both quote/refinance expiry use the same `>= expiresAt` boundary; mismatched, overlong, or zero validity fails | ADR 0021 sections 6 and 13 |
| `P9R-FAIL-001` | Make each resolver revert or return malformed data | Call fails closed with exact pre-state preserved | ADR 0021 sections 6 through 10 |
| `P9R-FAIL-002` | Reenter from resolver, factory, account, token, and every dependency callback opportunity | The pre-external-call old-loan lock/guards reject reentry and no duplicate quote, clone, custody, payout, handoff, activation, refund, or event occurs | ADR 0021 sections 6, 9, 14, and 15 |
| `P9R-FAIL-003` | Force checked arithmetic plus tagged-nonce high-bit/mismatch/active/refundable/wrong-owner/rollback/reentrancy/`MASK` boundaries | Invalid ownership and overflow fail before effects; terminal release is permissionless where specified, `MASK` is exhausted, and successful sequences stay gapless | ADR 0021 sections 6, 11, 12, and 16 |
| `P9R-FAIL-004` | Reconcile a failed transaction against an independent pre-state snapshot | All contract, token, debt, position, lien, quote, counter, and evidence state is unchanged | ADR 0021 section 14 |

### Donation surplus, events, invariants, and release boundary

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-DON-001` | Directly transfer settlement tokens before request, during partial/full funding, and before refund/execution | Donation units create no accepted funding, escrow liability, commitment, claim, recipient right, or state transition | ADR 0021 section 15 |
| `P9R-DON-002` | Execute or refund while coordinator balance includes unrelated surplus | Readiness and terminal checks use only `_escrowedUnits(refinanceId)`; donation surplus neither blocks nor enables the operation | ADR 0021 section 15 |
| `P9R-DON-003` | Search every ordinary and emergency path for sweep/rescue/assignment | No donation can be swept, refunded, assigned, or counted as protocol assets/liabilities | ADR 0021 sections 5 and 15 |
| `P9R-DON-004` | Reset the disposable local stack | The reset-generation evidence proves one-command surplus removal without a production disposal or recovery authority | Refinance deployment evidence and ADR 0021 section 15 |
| `P9R-EVT-001` | Observe every successful persistent transition | Exactly one typed `RefinanceStateTransitioned` event emits with previous/next state, version, operation ID, and reconstructed evidence hash | ADR 0021 sections 3 and 16 |
| `P9R-EVT-002` | Retry exact operations and force reverted transitions | Exact replay and revert emit no additional durable transition event | ADR 0021 sections 3 and 16 |
| `P9R-EVT-003` | Independently reconstruct all frozen and additive events from state/results | Event facts and order match the reference-evidence preimages and contain no opaque caller-selected terminal truth | ADR 0021 sections 3 and 16 |
| `P9R-INV-001` | Run stateful arbitrary sequences against an independent model, including malicious stale `ACTIVE` historical positions | Every transition is authorized, atomic, conserved over effective claims plus exact debt, replay-correct, and terminally consistent; raw historical views alone never imply a receivable/vote/payment right; failed calls preserve pre-state | ADR 0019 and ADR 0021 sections 14 and 16 |
| `P9R-FZ-001` | Run ABI/storage/compiler/source-set compatibility and generated-freshness checks | Historical freeze remains intact and only the reviewed event, two errors, and method bodies are accepted by the later checkpoint | ADR 0021 sections 3 and 17 |
| `P9R-LOCAL-001` | Scan dependencies, RPCs, keys, addresses, assets, and fixtures | Only disposable chain-31337 synthetic-local dependencies and mock providers are present | ADR 0021 sections 1 and 18 |
| `P9R-LOCAL-002` | Run a clean checkout bootstrap, the complete first-slice flow, restart/replay, and one-command reset | The deterministic local flow passes without external providers or retained value | ADR 0021 section 18 and Explicitly not authorized |
| `P9R-LOCAL-003` | Attempt to classify evidence as production approval or reuse it on another chain/source head | Acceptance fails; the evidence has no live-fund, mainnet, production-key, provider, or deployment authority | ADR 0021 section 1 and Explicitly not authorized |

## Required evidence packages

The candidate implementation must publish all of the following for the same
source head:

1. historical ABI/storage comparison plus the exact one-event/two-error additive-
   allowlist review;
2. deterministic reference vectors defined by
   `phase-9-refinance-reference-evidence.md` in Solidity, Go, TypeScript, and
   Python;
3. fresh-chain deployment evidence defined by
   `phase-9-refinance-deployment-evidence.md`;
4. unit, boundary, authorization, negative, differential, fuzz, and stateful
   invariant results keyed to every `P9R-*` row;
5. complete method-level activation and exact-source checkpoint evidence;
6. documentation-to-invariant, risk, assumption, dependency, secret, and
   forbidden-boundary results; and
7. independent architecture and security approvals for the exact source head.

## Completion gate

`UNI-REFI-001` and `UNI-REFI-002` remain `TODO` until the complete bundled
implementation passes every applicable row above on a clean checkout and the
reviewed method-level checkpoint is recorded. Neither row may be accepted alone.
No result from this matrix authorizes real value, a public chain, a production
credential, an external provider, a production-like identity, or a mainnet
deployment.
