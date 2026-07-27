# Phase 9 Refinance Acceptance and Threat Matrix

Status: normative design and compatibility gate; implementation not accepted

Date: 2026-07-27

## Purpose and authority

This document is the acceptance contract for the first synthetic-local atomic
refinance slice governed by ADR 0019, ADR 0020, ADR 0021, ADR 0022, the
historical candidate-only fixed-module boundary in ADR 0023, and the synthetic-local
activation-topology control in ADR 0024, as refined by the D3 execution-semantics
freeze in ADR 0025. ADR 0026 records a historical rejected repartition and ADR 0027
freezes security-approved semantics while recording a size-unproven candidate; no deployment topology is
accepted. ADR 0021
controls where earlier Phase 9 prose describes a state or authority that the frozen
five coordinator selectors cannot reach; ADR 0022 controls factory, account, manager,
clone, creation-replay, version-zero, ordering, and checkpoint implementation details
left open by that boundary. ADR 0023 records the measured historical candidate;
ADR 0027 rejects ADR 0026's module count and records mandatory transaction-local
validation semantics, but accepts no replacement linked-call count or deployment order.
ADR 0024 selects explicit
Anvil nonce preconditioning and the exact
verification-before-governance-grant order. Neither decision activates a selector,
method, checkpoint, or deployment.

ADR 0025 replaces inaccessible private checkpoint-history claims with exact public
execution-block observations, fixes canonical recipient aliasing and balance
conservation, makes `EXECUTING` provisional and unversioned, and requires a sorted
four-phase lien handoff. It changes no selector, event, error, tuple, storage field,
interface, or method activation and does not open D3. ADR 0027 retains the all-static
68-word/2,176-byte execution plan and freezes the six-stage phase-ticket semantics, but
does not accept the measured eight-library/12-call/15-CREATE size closure because its
figures predate the exact fresh current-context receipt and independently authoritative
lien/finalize checks. Implementation and topology
selection remain closed pending reproducible remeasurement or repartition.

This is a boundary-only milestone. It does not authorize a successful Solidity
refinance path, mark `UNI-REFI-001` or `UNI-REFI-002` complete, authorize real
funds, or authorize any public-network or production deployment.

The implementation may activate only the exact methods listed by ADR 0021, as
interpreted by ADR 0022 and a future successor topology, and only after every applicable
`P9R-*` row below passes. A passing document or candidate-architecture review is not
implementation evidence.

ADR 0023 permitted one preliminary topology checkpoint that cannot satisfy any
`P9R-*` row and is now historical only: a dedicated disposable Anvil broadcaster with no imported or
production-origin key and no real value is observed at nonce `0x0`, preconditioned to
`0x1` through an evidenced `anvil_setNonce` call, and used for exactly ten zero-value
top-level `CREATE` transactions at nonces 1 through 10. Immediate pre-broadcast nonce
reads must be `0x1`; post-broadcast `latest` and `pending` reads must be `0xb`. The
checkpoint stops after the nonce-10 coordinator creation and performs no role grant,
policy/setup/repair call, business action, method activation, or checkpoint activation.
ADR 0024 rejects a nonce-0 `RoleManager` deployment by the candidate broadcaster and
selects explicit nonce preconditioning for activation-grade synthetic-local evidence.
It requires the complete ten-CREATE graph to verify with the factory role absent before
one distinct governance executor grants the exact factory role. The preliminary
checkpoint here still stops before that grant and cannot satisfy activation-grade
deployment evidence. The non-accepted ADR-0027 15-CREATE graph and the existing ten- and
twelve-CREATE plans and observations cannot be relabeled; a successor ADR must freeze
and measure a new graph before any deployment row can pass.

## Fixed first-slice interpretation

- The frozen coordinator surface consists only of `requestRefinance`,
  `recordFundingCommitment`, `executeRefinance`, `cancelRefinance`, and
  `refundCommitment`.
- No execution topology is selected. A successor must retain the same protocol-facing
  coordinator, lifecycle-only separation, and six semantic execution stages
  `prepareExecution`, `executePayoff`, `validatePreLien`, `executeLienBarrier`,
  `validatePreFinalize`, and `finalizeExecution`, while independently proving its exact
  library/call/CREATE inventory fits every budget. No module may link or delegate again,
  and none of its library entries may enter the protocol ABI.
- First execution transports only pre-payoff-produced `ValidationPayloadV1`, the exact
  unchanged all-static 68-word/2,176-byte `ExecutionPlanV1`, and the fixed receipts and
  two-word phase proofs defined by ADR 0027. Every dispatch rehashes unchanged payload
  and plan bytes; no transport is external or persisted; and no call occurs between a
  post-validator and its consumer. Replay remains storage-only and returns before every
  dependency read.
- `requestRefinance` is the canonical borrower's direct acceptance of the exact
  proposal. Caller-supplied refinance/quote identities and derived state are zero;
  the coordinator atomically bootstraps the old fixture when needed, issues the
  quote, derives the identities, creates dormant replacement clones, and first
  stores `ACCEPTED`. `REQUESTED`, `QUOTED`, and `OFFERED` are off-chain evidence
  stages and `REJECTED` is an off-chain outcome.
- The first successful funding commitment advances the refinance from `ACCEPTED`
  to `FUNDING_ESCROWED`. Additional partial funding remains
  `FUNDING_ESCROWED`; execution requires exact full funding.
- `EXECUTING` is a provisional reentrancy guard with no version, attempt, or event.
  Success persists one `FUNDING_ESCROWED -> COMPLETED` version increment, stores
  attempt one, emits the frozen execution event followed by one typed completion
  transition, and binds both to `terminal_result_hash`.
- Old manager evidence is the exact pre/payoff/post equality of three public-view
  snapshot hashes at one `uint64(block.number)`, not proof of private checkpoint arrays.
- The four payout legs reject zero/coordinator/settlement-token recipients before effects, allow
  canonical external aliases, prove immediate leg deltas, then prove strictly
  increasing-`uint160` unique-address aggregates and exact coordinator outflow.
- Lien handoff is begin-all, verify-all-pending, complete-all, verify-all-active in
  sorted collateral order, with only canonical lien-registry calls in the pending
  window.
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
- Factory creation replay classifies the stored creation ID before the current global
  nonce, validates the exact stored request and active creation-resolver tuple, and
  returns the original verified clones with no write, state-changing call, deployment,
  initialization, registration, nonce movement, or event. It never reconstructs a
  historical creation with the current nonce.
- Minimal clones use the exact OpenZeppelin-compatible EIP-1167 bytecode and ADR 0021
  salts without importing new ABI errors. Existing declaration-initialized flags lock
  the implementation instances; account initialization precedes manager initialization,
  and manager factory authority comes only from the initialized account configuration.
- Every configuration commitment is nonzero. The first-slice settlement asset is the
  direct padded-ASCII mapping of `asset:phase9:p9unit`, never a string hash, and the
  settlement token has the exact local runtime. Only the coordinator calls its frozen
  asset resolver; factory, account, and manager validate their existing resolver-bound
  facts without new storage or selectors.
- Tranche, position, collateral, custody, and lien IDs use strictly increasing unsigned
  raw `bytes32` order. Agreement version zero remains empty for a dormant replacement,
  and each checkpoint series coalesces to one canonical entry per block.

## Mandatory acceptance matrix

Each identifier is stable. Tests and evidence MUST cite the exact three-digit
identifier. One test may cover several rows only when its assertion output names
every covered row.

### Compatibility, checkpoint, and risk gates

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-COMPAT-001` | Compare every existing ABI item and storage declaration with the historical `UNI-ABI-009` snapshot | Every historical item is byte-for-byte unchanged; declaration initializer values do not alter the frozen slot graph | ADR 0021 sections 1 and 3 and ADR 0022 sections 1 and 3 |
| `P9R-COMPAT-002` | Compare each candidate ABI with the historical snapshot plus the reviewed per-contract additive allowlist | The coordinator adds only the exact typed transition event and funding error; the lien registry adds only the exact typed handoff error; no account/manager constructor or OpenZeppelin clone error is added | ADR 0021 section 3 and ADR 0022 sections 1 and 3 |
| `P9R-COMPAT-003` | Scan the candidate source set for added selectors, other events/errors, tuple/storage fields, bases, constructor ABI items, imported clone errors, layout drift, undeclared libraries, module storage, nested links, and delegatecall drift | No unapproved protocol surface or storage change exists; the future successor's exact reviewed same-file libraries are storage-free; effect-free validation passes its stripped-opcode gate; directly deployed account/manager implementations remain locked; and the historical freeze error remains only through its approved compatibility marker | ADR 0021 section 3, ADR 0022 sections 1, 3, and 6, and ADR 0027 sections 2 and 7 |
| `P9R-CHECK-001` | Evaluate the method-level activation manifest and linked-module checker against the exact source head | Only ADR-activated methods may differ from their fail-closed bodies; every unopened mutator retains the exact freeze error; only a topology explicitly selected by a successor ADR may pass after its independently frozen library/call/CREATE counts and normative compilation satisfy the payload, plan, proof, current-guard, callback-closure, layout, opcode, link, ABI, compiler, 22,118-byte execution-module budget, EIP-170, and EIP-3860 gates; ADR 0027's candidate and planning sizes cannot pass | ADR 0021 section 17, ADR 0022 section 6, and ADR 0027 sections 2 through 10 |
| `P9R-CHECK-002` | Attempt to accept only one refinance backlog item, only part of the method bundle, or evidence omitting an ADR 0022 through ADR 0027 semantic pin and the future successor-topology pin | Activation fails unless the existing prerequisite backlog rows, both refinance implementation rows, ADR 0027 semantic gates, a measured successor topology, and every required method/evidence row and D1-D4 decision check bind the same reviewed head; accepted specification, architecture, and topology controls alone activate nothing | ADR 0021 section 17, ADR 0022 section 6, ADR 0024 section 6, ADR 0025 sections 1 and 6, and ADR 0027 section 10 |
| `P9R-RISK-001` | Cross-check the risk and assumption registers against this matrix | Every existential or critical refinance risk and assumption has an owner, mitigation, evidence target, and status | ADR 0021 Verification and registered risk/assumption evidence |

### Deployment and local bootstrap

The separately named candidate script, reset-bounded Anvil harness, verifier, tests,
plan/candidate/evidence schemas, canonical topology artifacts, and raw Forge broadcast
path are pinned in ADR 0023 and the refinance deployment-evidence document. Their
existence or a passing topology verification is not asserted here and cannot satisfy
the activation-grade rows below.

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-DEPLOY-001` | Deploy the full refinance graph using ADR 0024's explicit nonce-preconditioning and role-initialization order | Reserved and unsatisfied until a successor ADR selects and freezes a reproducibly measured exact graph; ADR 0027's current 15-CREATE candidate is not deployment authority | ADR 0024 sections 1, 2, 4, and 5 and ADR 0027 sections 8 through 10 |
| `P9R-DEPLOY-002` | Independently verify the prerequisite RoleManager, nonce precondition, exact future module/coordinator predictions, fixed links, reciprocal constructor bindings, and final governance role initialization | Reserved and unsatisfied until a successor ADR pins the exact nonces, coordinator address, final nonce, and link inventory from normative compilation; ADR 0027's nonce-15 prediction and final nonce 16 are unproven-candidate measurements only | ADR 0024 sections 2, 4, and 5 and ADR 0027 sections 8 through 10 |
| `P9R-DEPLOY-003` | Verify every activation-grade manifest transaction, receipt/log, code, constructor argument, module self-address runtime patch, link offset, fully linked runtime hash, dependency getter, role expiry/membership, reviewed storage slot, runtime/initcode size, execution-module budget, and direct account/manager implementation lock | Reserved and unsatisfied until every successor module and the coordinator match independently pinned compiler output and budgets; the exact single role grant remains last; missing, stale, unresolved, swapped, extra, or mismatched evidence fails | Refinance deployment evidence, ADR 0022 section 3, ADR 0024 sections 4 through 7, and ADR 0027 sections 8 through 10 |
| `P9R-DEPLOY-004` | Attempt public-chain, reused/production key, real value, nonce-zero candidate RoleManager, wrong or unevidenced nonce preconditioning, CREATE2 top-level, reordered/undeclared transaction, premature or wrong-sender role grant, role-admin change, setup/business action, post-hoc repair, or external-provider deployment | Every attempt is rejected, requires bounded reset, and creates no accepted deployment checkpoint | ADR 0021 sections 1 and 18, ADR 0024 section 7, and ADR 0027 sections 8 through 10 |
| `P9R-BOOT-001` | Request when the unique old bootstrap clone/records are absent | The borrower calls the coordinator; the coordinator-only factory call resolves borrower/configuration itself, deploys both clones, initializes the account before its manager, records the agreement hash only at the nonzero active terms version, registers the account once, then installs positions/custody/liens before quote issuance in one transaction; old position owner/beneficiary/claims equal `oldLender` and the old debt/quote route with no alternate | ADR 0021 sections 6, 8, and 11 and ADR 0022 sections 3 and 4 |
| `P9R-BOOT-002` | Retry exact bootstrap records; mutate one; invoke after the unique marker is consumed or off chain 31337 | Exact existing records are inert; any mismatch or unauthorized reuse reverts the complete request, including clone and quote effects | ADR 0021 section 11 |
| `P9R-BOOT-003` | Observe replacement creation during a successful request and query agreement versions zero and the later nonzero activation version | No replacement preexists; after internal quote and refinance-ID derivation the coordinator creates deterministic clones as `CREATED/NONE`, zero debt, no position/lien/custody, and `agreementVersionHash(0) == 0`, bound to that refinance only; activation writes the agreement hash only at its nonzero effective terms version | ADR 0021 sections 6 and 11 and ADR 0022 section 4 |
| `P9R-BOOT-004` | Force clone-address, implementation-code, initialization-order/authentication, registration, creation-ID, nonce, implementation, position, custody, lien, quote, or final validation failure; observe reentry at the first clone/initialization/registry boundary; and assert the frozen error mapping | The exact request, processed marker, predicted mappings, and advanced nonce are reserved after resolver/identity validation but before clone deployment or initialization/registry effects so reentry cannot create a second path; wrong account initializer callers are classified before initialized/configuration errors; the exact existing factory/account/manager error is returned for each locally classified failure; and the entire borrower request reverts reservations, bootstrap, quote, replacement clones, initialization, registry effects, nonce, state, and events | ADR 0021 sections 6 and 11 and ADR 0022 sections 2, 3, and 5 |
| `P9R-BOOT-005` | Recalculate new-loan/bootstrap/creation/clone/activation/tranche/position/custody/lien identities independently, including operation-ID-bound custody identity and equal refinance/new-loan nonce; prove fresh coordinator creation supplies zero and the factory stores its internally derived canonical nonzero ID; replay that canonical bootstrap creation after later successful creations and after the bootstrap loan becomes terminal; mutate the stored request/resolver facts; and reuse the loan under another creation ID | Every preimage is acyclic; only custody's passed operation ID is contract-authoritative while activation/tranche/position/lien operation hashes are correlation evidence; a fresh nonzero creation ID fails; exact canonical factory replay branches before the current nonce, verifies canonical registry identity regardless of the current terminal flag, and returns its verified original clones without effects; changed processed creation facts revert `InvalidPhase9LoanConfiguration`; an alternate or zero-ID creation collision reverts `Phase9LoanAlreadyExists`; exact setup replay is inert; and exact outer request replay rejects before a quote | Refinance reference evidence and ADR 0022 section 2 |

### Caller authority and identities

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-AUTH-001` | Call `requestRefinance` as borrower and as every other role | Only the exact canonical borrower can create the accepted record | ADR 0021 section 5 |
| `P9R-AUTH-002` | Call `recordFundingCommitment` as the named funder and substituted callers | Only the commitment's canonical funder can fund it | ADR 0021 section 5 |
| `P9R-AUTH-003` | Call `executeRefinance` from arbitrary callers after exact readiness and before readiness | Execution is permissionless only after all immutable facts and full funding validate | ADR 0021 section 5 |
| `P9R-AUTH-004` | Cancel before expiry as borrower and substituted callers | Only the borrower can cancel before expiry | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-005` | Persist expiry at and after the deadline as arbitrary callers | Expiry is permissionless and cannot select a recipient or economic value | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-006` | Refund from arbitrary callers with recipient substitutions | Refund is permissionless but always pays the stored commitment funder the stored amount | ADR 0021 sections 5 and 13 |
| `P9R-AUTH-007` | Pause the exact private request and funding capability IDs before and after accepted funding; replay exact/changed commitment IDs; try each pause against every other mutator | Only the matching capability stops a new request or first commitment; exact funding replay remains inert, changed reuse still conflicts, and neither pause can alter accepted facts, redirect value, sweep donations, or block execute/cancel/expiry/refund | ADR 0021 section 5 |
| `P9R-AUTH-008` | Scan for caller-selected delegation, nested module links/delegatecalls, signature, arbitrary-call, rescue, sweep, recipient selection, operator override, caller-authored execution transports, or caller-authored factory/account/manager authority paths | No caller-selected authority is reachable; only the future successor's independently frozen coordinator-to-fixed-library compiler links exist; no module delegates again; payload, plan, receipts, and proofs are module-produced, coordinator-checked, never external or persisted, and rehashed unchanged; and canonical dependency identity remains unchanged | ADR 0021 sections 1, 5, and 11, ADR 0022 section 3, ADR 0025 section 3, and ADR 0027 sections 2, 5, 6, and 7 |

### Identity, schema boundary, and canonical sources

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-ID-001` | Reconstruct refinance, policy, commitment, creation, operation, and result identities in Solidity and independent models | Every digest uses the exact domain and typed `abi.encode` preimage in the reference-evidence document | ADR 0021 sections 8, 11, 12, and 16 |
| `P9R-ID-002` | Exercise wire normalization for identifier/loan hex, EVM PartyId, Money decimal/asset, timestamp, and policy reference, including the direct asset bytes versus a string hash | Only the exact lowercase widths, ranges, `asset:phase9:p9unit` direct mapping to `0x61737365743a7068617365393a7039756e697400000000000000000000000000`, zero nanos, and exact policy ID/version/hash pass; the Foundry test hash is rejected | ADR 0021 section 4, ADR 0022 section 4, and reference evidence |
| `P9R-ID-003` | Submit nonzero caller refinance/quote/request digest/derived state; unequal/zero/high-bit/exhausted refinance/new-loan nonces; concurrent same/next nonce requests; exhaust the factory-global nonce; replay an old creation after later creations; then repeat outer-request success | Derived or unequal nonce input fails before effects; the high-bit lock permits one owner and one shared refinance/new-loan nonce, concurrent/exact outer-request repeat fails before another quote, a later released nonce gets a distinct replacement/quote, the factory starts at one and advances only on unique success, exhaustion fails, and creation replay never reads or moves the current factory nonce | ADR 0021 sections 4, 6, 11, and 16 and ADR 0022 section 2 |
| `P9R-ID-004` | Encode Protobuf `new_position_manager` with 0, 19, 20, 21, and 32 bytes | Only exactly 20 bytes is structurally admissible | ADR 0021 sections 6 and 8 |
| `P9R-ID-005` | Decode the 20-byte manager as zero, exact predicted factory manager, and substituted nonzero addresses | Only the nonzero address equal to the factory-salt prediction and resolved creation/account binding passes | ADR 0021 sections 6, 8, and 10 |
| `P9R-ID-006` | Trace validation order around `new_position_manager` | Length, nonzero, prediction, and resolver equality checks occur before refinance-ID reconstruction and before any effect | Refinance reference evidence |
| `P9R-SRC-001` | Resolve old bootstrap and replacement creation/loan facts through policy registry, loan registry, and factory at request/execution; derive first-execution replacement creation from checked current `nextLoanNonce - 1`, mapped clones/configuration, and `creationRequest`; substitute registry/account facts, premark the old loan terminal, or create a later unique loan | The missing old clone may be created only by unique bootstrap; replacement is absent at entry then exact dormant; first execution reconstructs and matches the exact stored creation request and mapped clone/registry graph without a scan or new field; mismatch, preterminal state, or intervening later factory creation fails stale before quote/value effects and leaves cancellation/refund available | ADR 0021 sections 6, 8, 11, and 14 and ADR 0025 sections 1 and 6 |
| `P9R-SRC-002` | Mutate either account configuration or factory manager; initialize the manager before its account, from a substituted caller, or against a substituted account/token | Factory and account manager disagreement fails, including an identical-content attacker manager; only account-before-manager initialization by the factory identified in the exact account configuration succeeds | ADR 0021 sections 6 and 10 and ADR 0022 section 3 |
| `P9R-SRC-003` | Resolve settlement and custody asset tuples and independently inspect each token; substitute the fixed settlement asset, token runtime, or the component attempting the asset-source call | Active exact-balance-delta address/code/runtime agreement holds; settlement uses the exact direct-mapped P9UNIT asset and local-token runtime and matches coordinator/accounts/manager; only the coordinator calls its frozen settlement asset source, while custody may be distinct but must match bootstrap identity and deployed code | ADR 0021 sections 7 and 9 and ADR 0022 section 4 |
| `P9R-SRC-004` | Mutate each creation/bootstrap/refinance policy fact and vector; set each configuration commitment to zero; exceed 16 collateral, 32 commitments, 8 tranches, or 32 positions | Every loan, settlement-asset, agreement, policy-set, amendment-policy, protection-policy, and recovery-policy hash is nonzero; exact reconstruction/caps fail before loops or effects; caller/service values never override a resolver | ADR 0021 section 8 and ADR 0022 section 4 |
| `P9R-SRC-005` | Substitute bootstrap custody/lien/token/code/quantity/allowance/balance/attribution facts; use zero/changed/cross-domain operation IDs, changed records, or unauthorized callers; inject fee/rebase/callback/reentrancy; replay exact records | Coordinator recomputes the operation ID and custody binds it into identity; first effects use checks-effects-interactions, exact same-operation/record replay is inert, changed/alternate reuse conflicts, and every mismatch/failure reverts before a false lien or quote | ADR 0021 sections 9 and 11 |
| `P9R-SRC-006` | Change canonical debt, quote version, policy, asset, collateral, account, or manager after acceptance | First execution rejects the stale/substituted graph without consuming the quote or changing value/claims | ADR 0021 sections 6 through 10 |

### Reachable state and views

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-STATE-001` | Submit each nonzero caller-supplied refinance ID, quote ID, request digest, state, counter, or terminal hash | Only zero derived input is accepted; coordinator internally derives identities and storage begins `ACCEPTED`, version 1 | ADR 0021 sections 2, 4, and 6 |
| `P9R-STATE-002` | Exercise all state edges with the tagged old-loan lock | Only the exact durable graph persists; first/later funding is `FUNDING_ESCROWED`; provisional `EXECUTING` consumes no version/attempt and cannot terminal-replay; success persists one direct `FUNDING_ESCROWED -> COMPLETED` increment with attempt one; `ACCEPTED`/escrow/refundable retain the lock and exact terminal states release it after effects | ADR 0021 sections 2, 6, 12, and 13 and ADR 0025 section 4 |
| `P9R-STATE-003` | Attempt to persist `REQUESTED`, `QUOTED`, `OFFERED`, `REJECTED`, or `DISPUTED` | No frozen selector can persist those states in this slice | ADR 0021 section 2 |
| `P9R-STATE-004` | Revert at every point after provisional `EXECUTING`, then execute successfully and attempt replay from forged/provisional state | Revert leaves the prior `FUNDING_ESCROWED` state/version, attempt zero, and no event/effect; success increments the version once, stores attempt one and `COMPLETED`, and provisional `EXECUTING` never qualifies for terminal replay | ADR 0021 sections 2 and 14 and ADR 0025 section 4 |
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
| `P9R-EXEC-003` | Trace the success call, phase-ticket transport, evidence, persistence, and log order | Storage-only replay returns the stored result with empty context and skips the other five execution calls. Effect-free pre-payoff validation produces the exact payload and guard; payoff bounded-`STATICCALL` rereads the quote/components, requires state version below `uint64` maximum, recomputes the supplied operation ID from the current quote debt version, rechecks all current guard facts, writes provisional `EXECUTING`, consumes the quote, performs legs 0/1 and payoff, and returns the unchanged 68-word plan and receipt; each fresh phase proof binds only non-action observations plus the exact 20-word current `EXECUTING` context receipt. With no intervening call/effect, lien independently validates old-active/no-pending tuples before its uninterrupted barrier, and finalization independently reconstructs the canonical `lienHandoffVectorHash`/lien result and validates active-new/completed-handoff tuples before activation, legs 2/3, conservation, escrow clearing, final proofs, completion write, frozen execution log, and completion-transition log. Neither facts nor ticket hashes authorize an effect | ADR 0021 section 14, ADR 0025 sections 2 through 5, and ADR 0027 sections 1 through 7 |
| `P9R-EXEC-004` | Exercise every equality partition of old lender, payoff-fee recipient, refinance-fee recipient, and borrower, including zero-amount legs, donations, and zero/coordinator/settlement-token recipients | Zero/coordinator/settlement-token recipients fail before effects; all four leg hashes exist; each immediate recipient/coordinator delta is exact; distinct recipients sorted by increasing `uint160` receive the checked aggregate of aliased legs; attributed escrow reaches zero; exact positive coordinator outflow equals funding; unrelated token surplus is excluded and preserved | ADR 0021 sections 14 and 15 and ADR 0025 section 3 |
| `P9R-EXEC-005` | At one exact `uint64(block.number)`, hash bounded `trancheIds/tranche`, `positionIds/position`, position owner/voting/claim-at-block, and total voting power before effects, after payoff, and before completion; inspect terminal debt and attack every consumer with stale raw `ACTIVE` facts | The three exact V1 public-view snapshot hashes match at all three observation points without claiming private checkpoint-series proof; the registered old account atomically marks the exact loan terminal; debt is `CLOSED/TERMINAL`, economic/loss/credit amounts are zero, debt version/nonce advance once, raw issuance observations remain stable, effective claim/vote/payment rights are zero, and no consumer authorizes from raw history alone | ADR 0021 section 14 and ADR 0025 section 2 |
| `P9R-EXEC-006` | Inspect each exact lien/handoff tuple through begin-all, verify-all-pending, complete-all, and verify-all-active; inject failure at every index and the between-pass boundaries, including prior-version overflow | IDs and versions are prevalidated; every pending lien retains the enforceable old senior identity while the pending target/successor is non-enforceable; no successor activates before the complete pending vector verifies; only lien-registry calls occur in the pending window; every active-new tuple clears pending IDs; all pending logs precede completion logs; any mismatch, overflow, or failure rolls the complete vector back | ADR 0021 sections 9 and 14 and ADR 0025 section 5 |
| `P9R-EXEC-007` | Inspect replacement debt, tranches, positions, and manager after success | The complete immutable policy tuple activates once with every funded claim exactly represented and no unfunded claim | ADR 0021 sections 10 and 14 |
| `P9R-EXEC-008` | Mutate every `ExecutionPlanV1` word, fixed-array tail, count/hash pair, header, suffix hash, returned plan hash, payload count/derived offset/padding, component element/string offset, phase domain, phase observation, ticket word, midpoint balance/hash, snapshot/debt evidence, current lien/handoff tuple, and ordering rule; canonically reconstruct identical payload bytes and attempt byte-different semantic re-encoding; inject a revert at every dependency, token, module-boundary, and lien-stage point | Canonical reconstruction producing identical raw bytes is harmless; every byte-different representation or mutation fails before a consumer effect. No catch converts failure; no payload, plan, receipt, or proof is caller-authored, external, persisted, or reusable; and every injected failure restores the exact prior `FUNDING_ESCROWED` state with no quote, payout, payoff, lien, replacement, escrow, terminal-storage, counter, or log residue | ADR 0021 sections 14 and 15, ADR 0025 sections 2 through 5, and ADR 0027 sections 3 through 8 |
| `P9R-EXEC-009` | Retry after terminal lock release while every dependency call is configured to fail; independently mutate keyed/stored refinance identity, record state, attempt, stored `quoteId`, zero/changed/unprocessed supplied operation ID, terminal refinance identity/state, terminal `recordedAt`, event ID, result hash, and terminal evidence | Exact replay is dependency-call-free and branches before every first-execution current-state/old-lock read. The complete stored terminal tuple must match, including record `COMPLETED`, attempt one, terminal `COMPLETED`, nonzero processed supplied ID, nonzero terminal event/result/evidence, and equal result/evidence. It reconstructs a nonzero execution-event ID from the exact domain, chain, coordinator, refinance ID, stored `quoteId`, supplied ID, `uint32(1)`, and terminal `recordedAt`; matches the stored event ID; returns the stored result with empty context/zero non-replay material; skips all remaining five execution calls; and makes zero dependency calls, writes, transfers, counter changes, and logs. It never recomputes `execute_operation_id`; every mutation and provisional `EXECUTING` reverts `RefinanceReplayConflict` | ADR 0021 section 16 and ADR 0025 section 4 |

### Exit, replacement, time, and failure handling

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-EXIT-001` | Cancel/expire with no funding using reasons 0/1/2 and injected quote-invalidation failure | Reason zero fails; quote/refinance terminalize atomically with bound disposition/source, then owned lock releases; failure rolls everything back | ADR 0021 sections 6, 13, and 16 |
| `P9R-EXIT-002` | Cancel/expire after partial/full funding and try a later old-loan request | Nonterminal `REFUNDABLE` keeps terminal result/evidence zero and retains the active lock; terminal quote cannot consume and no later request proceeds until final refund | ADR 0021 sections 6 and 13 |
| `P9R-EXIT-003` | Refund commitments in arbitrary order and through arbitrary callers; reconcile ordered stored commitments to events/results | Each stored funder receives its exact amount once; one matched refund transition/result exists per commitment with no missing/duplicate/unmatched event; partial refunds remain `REFUNDABLE` | ADR 0021 sections 13 and 16 |
| `P9R-EXIT-004` | Refund the last liability and reconstruct the aggregate cross-language before exact/changed retry | Last refund stores `REFUNDED` from ordered stored facts with immutable funding proofs and zero liabilities, then permissionlessly releases the owned lock; exact replay after release is inert and changed reuse conflicts | ADR 0021 sections 6, 13, and 16 and reference evidence |
| `P9R-EXIT-005` | Replay cancel/expiry before refunds, after each partial refund, and after final refund while every dependency call fails; mutate keyed identity, empty/`1..32` inventory bounds, duplicate/over-cap IDs, commitment ID or refinance identity, `NONE`/`CONSUMED`/other commitment state, refunded count, prior-version underflow, stored expiry, reasons 1/2, zero/unprocessed/cross-domain/other-refinance processed IDs, and incompatible refinance states | Old quote cannot consume after `CANCELLED`/`REFUNDABLE`/`EXPIRED`. Cancel replay is coordinator-storage-only. `CANCELLED`/`EXPIRED` require an empty commitment inventory; `REFUNDABLE`/`REFUNDED` require `1..32` unique IDs, each materializing the exact current-refinance commitment in only `FUNDED` or `REFUNDED`. It checked-counts `REFUNDED`, reconstructs `cancellation_prior_version = stored_refinance.stateVersion - refunded_count - 1`, uses stored `expiresAt`, permits only reason 1 for `CANCELLED`, only reason 2 for `EXPIRED`, and either canonical candidate for `REFUNDABLE`/`REFUNDED`, then requires exact supplied-candidate equality plus a nonzero processed marker. Exact replay makes zero dependency calls, writes, transfers, counters, and logs; it never uses `current stateVersion - 1` alone. Every inventory, identity, state, count, arithmetic, candidate, or operation mismatch reverts `RefinanceReplayConflict` | ADR 0021 sections 2, 13, and 16 and reference evidence |
| `P9R-RPL-001` | Compare policy tranches/positions with commitment set; submit duplicate/decreasing raw IDs, priority-only reorderings, exact/changed record replay, multiple same-block issuances, and an over-`uint64` block number | `1..8` tranches and `1..32` positions are strictly increasing by unsigned raw `trancheId`/`positionId`, unique, complete, and aggregate exactly; priority is not the comparator; every owner equals its commitment funder; exact replay is inert; changed reuse fails; each checkpoint series has one canonical entry per block and total voting power coalesces; owner checkpoints keep `value == 0`, while voting/claim/total checkpoints keep `owner == address(0)` | ADR 0021 section 10 and ADR 0022 section 5 |
| `P9R-RPL-002` | Mutate replacement lifecycle, servicing, versions, schedule, maturity, template active refinance, dormant clone, factory refinance binding, or agreement-version mapping zero/nonzero entries | Policy template requires zero active refinance; dormant creation leaves `agreementVersionHash(0) == 0`; coordinator injects only the derived refinance ID and activation writes the agreement hash only at the nonzero effective terms version; every mismatch or terminal/cross-refinance reuse fails | ADR 0021 sections 10, 11, and 13 and ADR 0022 section 4 |
| `P9R-RPL-003` | Add accrued/capitalized/fee/loss/credit/restructure amounts at first activation | Any nonzero prohibited component fails | ADR 0021 section 10 |
| `P9R-RPL-004` | Substitute a position owner/claim/tranche or add/remove a commitment | Exact one-to-one commitment-position mapping fails | ADR 0021 section 10 |
| `P9R-TIME-001` | Test one second before, exactly at, and one second after `expiresAt`, including maximum validity, and attempt any refinance/quote deadline mismatch | Request passes the proposal `expiresAt` as quote `validUntil` and stores exact equality; acceptance/funding/execution use `< expiresAt`; both quote/refinance expiry use the same `>= expiresAt` boundary; mismatched, overlong, or zero validity fails | ADR 0021 sections 6 and 13 |
| `P9R-FAIL-001` | Make each resolver revert or return malformed data and exercise every locally classified factory/account/manager error branch | Call fails closed with exact pre-state preserved and uses only `InvalidPhase9LoanConfiguration`, `Phase9LoanAlreadyExists`, `UnauthorizedPhase9LoanCaller`, `InvalidPhase9LoanOperation`, and `InvalidPositionOperation` under the exact ADR 0022 mapping | ADR 0021 sections 6 through 10 and ADR 0022 sections 2, 4, and 5 |
| `P9R-FAIL-002` | Reenter from resolver, factory, account, token, and every dependency callback opportunity; enumerate every effect-callee codehash, call edge, and reachable write set | The request stores the old-loan lock before any effect-capable dependency interaction; execution installs `EXECUTING` before its first effect, but that per-refinance guard alone is insufficient. A closed reviewed codehash/call-graph/write-set proof shows no effect callee can callback any coordinator mutator or same-/cross-refinance route and no reachable callee can mutate any refinance escrow, lock, quote, lien, replacement, commitment, or terminal state; no duplicate quote, clone, custody, payout, handoff, activation, refund, or event is possible | ADR 0021 sections 6, 9, 14, and 15 and ADR 0027 sections 2 and 7 |
| `P9R-FAIL-003` | Force checked arithmetic plus tagged-nonce high-bit/mismatch/active/refundable/wrong-owner/rollback/reentrancy/`MASK` boundaries, factory-global `uint64` exhaustion, creation replay after nonce movement, and checkpoint block-number overflow | Invalid ownership and overflow fail before effects; terminal release is permissionless where specified, `MASK` and the factory nonce are exhausted without wrap, successful sequences stay gapless, replay leaves the current factory nonce unchanged, and an unrepresentable checkpoint block fails | ADR 0021 sections 6, 11, 12, and 16 and ADR 0022 sections 2 and 5 |
| `P9R-FAIL-004` | Reconcile a failed transaction against an independent pre-state snapshot | All contract, token, debt, position, lien, quote, counter, and evidence state is unchanged | ADR 0021 section 14 |

### Donation surplus, events, invariants, and release boundary

| ID | Test | Required result | Trace |
|---|---|---|---|
| `P9R-DON-001` | Directly transfer settlement tokens before request, during partial/full funding, and before refund/execution | Donation units create no accepted funding, escrow liability, commitment, claim, recipient right, or state transition | ADR 0021 section 15 |
| `P9R-DON-002` | Execute or refund while coordinator balance includes unrelated surplus | Readiness and terminal checks use only `_escrowedUnits(refinanceId)`; donation surplus neither blocks nor enables the operation | ADR 0021 section 15 |
| `P9R-DON-003` | Search every ordinary and emergency path for sweep/rescue/assignment | No donation can be swept, refunded, assigned, or counted as protocol assets/liabilities | ADR 0021 sections 5 and 15 |
| `P9R-DON-004` | Reset the disposable local stack | The reset-generation evidence proves one-command surplus removal without a production disposal or recovery authority | Refinance deployment evidence and ADR 0021 section 15 |
| `P9R-EVT-001` | Observe every successful persistent transition, including provisional and successful execution | Exactly one typed event emits per durable transition; provisional `EXECUTING` emits none; successful execution emits one direct `FUNDING_ESCROWED -> COMPLETED` transition at the one incremented version with execute operation ID and `evidenceHash == terminal_result_hash` | ADR 0021 sections 3 and 16 and ADR 0025 section 4 |
| `P9R-EVT-002` | Retry exact operations and force reverted transitions | Exact replay and revert emit no additional durable transition event | ADR 0021 sections 3 and 16 |
| `P9R-EVT-003` | Independently reconstruct all frozen and additive events from state/results, including consumed-quote component binding, typed replacement hashes, one execution timestamp, revised snapshots, recipient, lien, old-debt, and terminal preimages | Event facts and order match exact reference preimages; one captured `executed_at` is reused in event ID terminal hash and terminal storage; every pending-lien log precedes every completion log; successful execution emits frozen `RefinanceExecuted` then the one direct completion transition, both binding `terminal_result_hash`; no undefined or opaque caller truth and no private checkpoint-series assertion exists | ADR 0021 sections 3 and 16 and ADR 0025 sections 2 through 6 |
| `P9R-INV-001` | Run stateful arbitrary sequences against an independent model, including recipient-alias partitions, malicious stale `ACTIVE` historical positions, creation replay after later loans, exact/changed issuance replay, same-block issuance, and four-phase handoff faults | Every transition is authorized, atomic, alias-aware conserved over exact coordinator outflow plus effective claims/debt, replay-correct, and terminally consistent; unique creations equal `nextLoanNonce - 1`; raw IDs are ordered and unique; allocated claims never exceed tranche claims; public one-block observations remain exact while raw history alone never implies a receivable/vote/payment right; lien phases never expose an enforceable pending target; failed calls preserve pre-state | ADR 0019, ADR 0021 sections 14 and 16, ADR 0022 sections 2 and 5, and ADR 0025 sections 2 through 5 |
| `P9R-FZ-001` | Run ABI/storage/compiler/source-set compatibility, linked-module, payload/plan/proof, and generated-freshness checks, including constructor-less initializer locking and OZ-compatible private clone helpers | Historical freeze remains intact; only reviewed ABI additions, activated bodies, an accepted exact measured set of same-file libraries and compiler-linked call sites, exact validation payload, 68-word plan, two-word proof, and reviewed assembly exceptions are accepted; ADR 0027 planning sizes alone are insufficient; no constructor ABI item, protocol selector, interface, tuple/storage field, base, logical slot, module storage, nested link/delegatecall, compiler-setting, unresolved-link, budget, EIP-170, or EIP-3860 drift exists | ADR 0021 sections 3 and 17, ADR 0022 sections 1, 3, and 6, ADR 0025, and ADR 0027 sections 2 through 10 |
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
3. the non-activating candidate topology evidence and, under ADR 0024's selected
   nonce and role order, fresh-chain activation-grade deployment evidence defined by
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
reviewed method-level checkpoint is recorded. Before `P9-REFI-001` can pass,
`UNI-ADR-019` and `UNI-ADR-020` must remain accepted; D3 evidence must match every
ADR 0025 preimage/order without any selector/storage/interface change; and
activation-grade evidence must prove ADR 0024's
explicit nonce precondition, pairwise-distinct authorities, verification-before-grant
order, and exact single governance-executor factory-role grant. The non-activating
topology candidate does not satisfy that requirement. Neither backlog row may be
accepted alone.
No result from this matrix authorizes real value, a public chain, a production
credential, an external provider, a production-like identity, or a mainnet
deployment.
