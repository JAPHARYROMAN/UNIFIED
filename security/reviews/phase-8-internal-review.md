# Phase 8 Internal Security Review

Date: 2026-07-25

Status: implementation review complete within the bounded local-only scope. The
separate engineering exit remains reserved for `UNI-REVIEW-011`.

Scope: Phase 8 cross-chain schemas and deterministic codecs; chain, route, finality,
coordinator, recovery, exposure, bridge, wrapped-token, home-loan, satellite-loan,
collateral, and settlement contracts; authenticated source and destination projection;
transport-only provider failover; durable coordinator, accounting, and reconciliation
stores; independent models and simulations; two-domain local deployment; release
evidence; and reset controls.

## Review basis

The review traced the current implementation across:

- `schemas/proto/unified/v1/crosschain.proto`, the generated Go, Python, TypeScript, and
  Solidity surfaces, and the independent cross-language codecs and golden vectors;
- `protocol/src/crosschain`, the Phase 8 interfaces, deployment script, ABI snapshots,
  contract tests, fuzz tests, recovery-ordering tests, and stateful invariants;
- `services/cross-chain-coordinator`, `services/chain-indexer`, and the Phase 8 portions
  of `services/foundation-ledger`;
- migrations `000010` through `000012` and their disposable-PostgreSQL tests;
- `models/foundation_model/src/unified_foundation/cross_chain.py`, its codec, and their
  failure simulations;
- `infrastructure/local/cross-chain`, both transport-only mock providers, the local
  worker, PowerShell and Bash smoke wrappers, release-evidence assembly and validation,
  and one-command reset;
- ADR 0018, the Phase 8 architecture and data-layout documents, risks
  `RISK-PHASE8-001` through `RISK-PHASE8-010`, and assumptions `ASM-026` through
  `ASM-033`.

Independent checks completed during review:

- standard non-IR Foundry build: passed with Solidity 0.8.36;
- full Foundry suite: 106 tests passed, including 128-run stateful invariants and
  256-case fuzz properties;
- focused cancellation and disbursement-race suite: 3 tests passed;
- `go test ./...`: passed across the coordinator, provider, recovery, store, worker,
  indexer, accounting, and reconciliation packages;
- `uv run pytest -q models tests`: 112 tests passed;
- `pnpm check`: TypeScript build and deterministic console checks passed;
- `tools/check_phase8.py`: Phase 8 architecture and local-safety checks passed;
- `scripts/check-contract-sizes.py`: 132 production artifacts passed the deployed-size
  limit.

The authoritative live-stack smoke and pre-reset/post-reset release-evidence checks are
owned by the separate release/governance run. This review consumes their signed,
schema-validated evidence but does not substitute its own in-memory or mocked success
claim for that gate.

## Reviewed properties

### Authority, identity, and deterministic encoding

- Protobuf is the intended canonical public interface. Identifiers, integer units,
  addresses, policies, typed actions, proofs, certificates, acknowledgements,
  governance operations, recovery records, accounting intents, and reconciliation
  evidence have additive definitions and deterministic generated bindings.
- Solidity ABI encoders, Go digest builders, TypeScript and Python codecs, and golden
  vectors bind field order, widths, enum ordinals, dynamic offsets, legacy Keccak, and
  domain strings. A changed security field changes the message, proof, recovery, or
  certificate identity.
- Chain and route identities bind chain versions, coordinators, component code hashes,
  action family and mask, adapter policy, finality policies, signer sets, caps, and
  activation time. Route replacement is versioned; deprecation and pause cannot rewrite
  an existing envelope.
- Message identity binds protocol, both domains and coordinators, both components, lane,
  source nonce, aggregate, action, payload, timestamps, route/finality/adapter policies,
  and correlation, causation, and supersession identities.

### Ordering, replay, execution, and acknowledgement

- Outbound messages require the exact registered source component and the next lane
  nonce. Inbound messages require the exact next nonce and reject a conflicting message
  at the same lane position.
- Exact executed-message replay returns the stored result without calling the receiver
  again. Changed payloads, envelopes, proofs, certificates, or route identities fail
  before another effect.
- Destination execution stores the verified envelope, receiver result, and monotonic
  state in one transaction. A zero receiver result reverts the whole transaction.
- Acknowledgements bind the original stored envelope, exact destination result, and
  independently verified destination-execution evidence.
- Safety exits and completed-effect reports remain executable across the deliberately
  bounded pause/deprecation and transport-expiry cases; new exposure does not.

### Finality and source-event evidence

- The local chain observer signs a complete header commitment with a distinct
  domain-pinned Ed25519 fixture key. Consumer-pinned policy and authority hashes reject
  alternate observers.
- Source evidence binds the block, transaction hash and index, receipt root and proof,
  log index and event, finality head and depth, signed-header authority, and finality
  policy.
- Transaction and receipt Merkle-Patricia inclusion, successful receipt status,
  canonical typed/legacy receipt encoding, exact contract/log identity, and finality
  depth are verified before an event becomes executable evidence.
- A separate two-of-three ECDSA signer set signs the full source-proof digest. Signer
  sets are canonical and distinct; duplicate, unknown, wrong-set, insufficient, and
  changed-proof signatures do not satisfy the threshold.
- Pre-finality replacement and reorganization records retain signed provenance.
  Finalized contradiction becomes a dispute/incident instead of silently rewriting an
  already consumed effect.

### Transport-only provider boundary

- Mock providers transport an exact serialized envelope and source proof. They do not
  sign source authority, select the call, change recipients or units, attest finality,
  or carry value.
- The authenticated flow performs real loopback HTTP POSTs. Sequence one observes
  provider A return a retryable `503` and provider B accept the same immutable content;
  later sequences observe provider A accept directly.
- Provider identity, `TRANSPORT_ONLY` authority, `contains_real_value=false`, response
  status, and receipt hash are recorded from the actual response. Non-loopback,
  authenticated, malformed, oversized, false-authority, or value-bearing provider
  responses fail closed.

### Recovery, tombstones, and compensation

- Recovery binds the immutable envelope, route, asset/amount commitment, source and
  destination state commitments, compensation-payload hash, original expiry, ordered
  recovery nonce, reason, action, and authorizer-set identity.
- A two-of-three recovery threshold is required. The destination tombstone must be
  finalized before source compensation and consumes the original lane position.
- Execution and tombstoning are mutually exclusive at the coordinator. Source
  compensation is restricted to the original component and predefined effect; it
  cannot choose arbitrary assets, recipients, amounts, or calls.
- Exact recovery replay returns the stored result. Changed compensation, wrong order,
  duplicate nonce, conflicting recovery, execution-before-tombstone, and
  tombstone-after-execution fail without a second effect.

### Post-mint, pre-disbursement loan cancellation

- Loan cancellation is a distinct governed two-of-three 12-field authorization,
  domain-separated by home chain and recovery controller and bound to the loan router,
  loan, funding lock, exact disbursement message/tombstone pair, amount, policy, ordered
  nonce, validity deadline, reason, and authorizer set. Signatures are separate call
  inputs and are not a thirteenth authorization field.
- One signature, duplicate signatures, an authorized-plus-unknown signer set, wrong
  nonce, expiry, changed request, and conflicting reuse fail without consuming the
  cancellation nonce or storing an authorization.
- If no disbursement message exists, both disbursement and tombstone identities must be
  zero. If a disbursement message exists, the satellite vault requires its exact local
  `DESTINATION_TOMBSTONED` state and tombstone hash and a zero execution result.
- Action 12 atomically marks the satellite settlement record, burns the exact escrowed
  wrapped UFT once, and emits action 14 with the exact burn result. The home refund is
  authorized only by finalized action 14, consumes the exact loan backing, reduces
  exposure, pays the canonical lender, and cannot replay.
- Cancellation and disbursement are mutually exclusive at the satellite vault. If
  cancellation wins, later disbursement fails. If disbursement wins, the authentic
  action 7 report narrowly resolves the home `RECOVERY_PENDING` race only when a
  cancellation and exact disbursement already exist, no refund occurred, mint and
  collateral are confirmed, and funding lock, amount, policy, and operation identity
  match. It atomically records the exact principal and enters `ACTIVE`.
- Once disbursement wins, late action 12 and action 14 cannot refund or burn value, and
  both direct-home and remote wrapped-UFT repayment remain available.
- A cancellation completed before the collateral report cannot falsely conclude that
  collateral was absent. The home remains recovery-pending, accepts the late finalized
  collateral truth, authorizes one exact borrower release, and closes without debt.

### Wrapped UFT, backing, and exposure

- Canonical UFT is locked before wrapped mint. Wrapped UFT is burned before canonical
  release. Each lock, mint, burn, permanent burn, repayment burn, cancellation burn,
  release, and compensation identity is single-use.
- Exact token-balance deltas reject unsupported fee behavior. Route identity pins the
  canonical token, bridge hub, wrapped token, destination component, backing route, and
  recipient.
- Per-loan backing, route backing, total bridge backing, hub custody, wrapped supply,
  and bridge surplus are distinct. Donation cannot become attributed loan backing.
- A generic wrapped exit cannot consume another wrapped implementation's or another
  loan's backing. Direct home repayment reduces loan attribution without pretending to
  burn still-circulating wrapped supply.
- Exposure policy versions freeze circulating-supply reference and evidence plus route,
  chain, adapter, and aggregate absolute and percentage caps. Historic looser policy
  reuse fails. Effective increases, reference changes, and evidence-hash changes require
  at least one day between registration and activation; immediate strict reductions
  remain possible.

### Home and satellite loan authority

- Home loan terms and policy configuration are immutable. Satellite actions can report
  bounded mint, collateral, disbursement, repayment-burn, cancellation-burn, and release
  facts but cannot rewrite lender, borrower, asset, amount, maturity, interest, policy,
  or home repayment behavior.
- Home debt becomes active only after exact finalized mint, exclusive collateral lock,
  and actual borrower disbursement. No debt is created by mint or collateral alone.
- Remote repayment burns wrapped UFT and releases the exact lender backing once. Direct
  repayment remains available independently of adapter health and cannot share a
  payment identity with remote repayment.
- Satellite collateral accepts one canonical provisioning and one exact borrower lock,
  rejects duplicate custody, and releases once to the canonical borrower only after a
  finalized home authorization. Cancellation cannot release collateral before the
  satellite burn and home refund are final.

### Durable services, accounting, and reconciliation

- Coordinator message, attempt, proof, certificate, execution, acknowledgement,
  recovery, route, signer, and reorganization records are immutable or monotonic
  compare-and-set projections with deterministic identities.
- Runtime, observer, finality-attester, recovery-verifier, and
  reorganization-verifier PostgreSQL roles are separated. Supported functions own
  authoritative transitions; tests reject direct runtime writes outside the reviewed
  boundary.
- Cross-chain journals are balanced, append-only, evidence-bound, and idempotent for
  canonical lock, wrapped outstanding, satellite receivable, disbursement, debt,
  repayment, collateral, burn, release, cancellation, and recovery stages.
- The required cancellation-accounting property is that cancellation intent alone is
  not economic authority and only the finalized satellite burn report can commit the
  home refund journals. The authenticated cancellation path is executable through the
  worker, and its object rehydration, SQL replay, substitution, rollback, privilege, and
  first-insert concurrency tests pass.
- Reconciliation compares canonical escrow, attributed and aggregate backing, wrapped
  supply, settlement-vault custody, active debt, collateral state, message state,
  exposure, journals, and recovery state. Differences retain owner, age, deadline, and
  evidence instead of netting away.
- Crash/restart and exact replay preserve message and journal identities. SQL commits
  keep transition, evidence, journals, and reconciliation authority atomic.

### Reproducible local release and reset

- Home and satellite Anvil domains use distinct local chain IDs, observer identities,
  deployment manifests, coordinators, registries, signer sets, and contract code hashes.
- The release evidence derives runtime authority from deployed contracts rather than
  trusting editable fixture JSON. Raw block, transaction, receipt, proof, log, signed
  header, certificate, execution, provider, SQL, broker, object, accounting,
  reconciliation, and reset evidence is hash-bound and schema validated.
- The local flow uses synthetic assets, unlocked Anvil fixture accounts, fixed local
  signers, loopback providers, disposable PostgreSQL, broker, and object storage. The
  reset plan removes the complete disposable topology and post-reset validation rejects
  retained authoritative state.

## Adversarial coverage

- changed protocol, chain, coordinator, component, code hash, route, action, aggregate,
  nonce, payload, expiry, policy, adapter, correlation, causation, and supersession;
- duplicate, skipped, reordered, conflicting, expired, paused, deprecated, replayed, and
  acknowledgement-conflicting messages;
- alternate observer, wrong finality policy, shallow depth, changed header,
  transaction, receipt, trie proof, log, event, finality head, signer set, signature, or
  certificate;
- canonical legacy and typed receipt edge cases, malformed trie children, oversized
  proofs and provider responses, non-loopback provider URLs, retryable failover, and
  false provider authority/value assertions;
- recovery before expiry, wrong nonce, insufficient/duplicate/unknown signers, changed
  commitments or compensation, tombstone/execution races, source compensation before
  tombstone, and exact replay;
- one-signature, duplicate-signer, unknown-signer, wrong-nonce, expired, changed-amount,
  changed-tombstone, changed-burn-result, replayed, and late loan cancellation;
- cancellation with no disbursement, cancellation after exact disbursement tombstone,
  late collateral truth, disbursement-winning race, late cancellation report, and
  direct/remote repayment after the race;
- lock/mint/burn/release replay, alternate wrapped implementation, fee-token balance
  mismatch, expired wrapped exits, permanent burn, repayment-burn recovery and retry,
  backing donation, cap boundaries, strict reduction, historic policy rollback,
  zero-delay cap/reference/evidence changes, and delayed activation;
- duplicate collateral provisioning, competing custody, premature release, changed
  recipient/amount/policy, double release, and terminal replay;
- process crash, database outage, restart rehydration, stale writer, conflicting durable
  replay, direct-write privilege failure, broker/object evidence checks, journal
  imbalance/conflict, and reconciliation mismatch;
- stateful invariants for cap dimensions, backing floors and sums, wrapped-supply
  ceiling, lane/message at-most-once progression, and collateral exclusivity.

## Findings and disposition

### P8-IR-001 — Disbursement-winning cancellation race stranded home debt

Severity before correction: HIGH.

An executed satellite disbursement could be followed by a governed cancellation carrying
a fabricated or stale tombstone. The vault correctly rejected cancellation, but the home
account had already entered `RECOVERY_PENDING` and rejected the authentic action 7
disbursement report, leaving borrower value without recorded home debt.

Disposition: corrected. The action 7 race-resolution path is narrowly gated as described
above, records exact principal and `ACTIVE` atomically, rejects later cancellation
effects, and preserves both repayment paths. The focused race and full Foundry suites
pass.

### P8-IR-002 — Exposure evidence replacement lacked explicit delay coverage

Severity before correction: MEDIUM.

A replacement policy must not swap its frozen circulating-supply evidence immediately,
even if headline caps do not increase.

Disposition: corrected. Evidence-hash change now independently requires the minimum
one-day activation delay. Tests cover zero-delay rejection and delayed success while
retaining immediate strict reductions with unchanged evidence.

### P8-IR-003 — Loan-cancellation public schema lagged the contract protocol

Severity before correction: MEDIUM.

The late exact 12-field loan-cancellation authorization and 11-word action 12 request and
action 14 completed-burn payloads were implemented in Solidity and manually decoded by
services before canonical Protobuf contained matching additive records. That violates
the Phase 8 rule that Protobuf is the public source and generated language bindings are
derivatives.

Disposition: corrected. Canonical Protobuf now contains the exact 12-field
`LoanCancellationAuthorization`, 11-field action 12
`LoanCancellationRequestedPayload`, and 11-field action 14
`SatelliteFundingCancelledPayload`, with additive action-payload oneof tags 40 and 42.
Go, Python, TypeScript, and Solidity derivatives regenerate deterministically; two
successive generations produced identical SHA-256 values for all 42 generated,
registry, and invariant files. Buf lint, build, and baseline breaking checks pass.
Go, Python, and TypeScript wire/ABI goldens and Solidity layout goldens bind the reviewed
field order and widths. The full Go suite, 112-test Python suite, and TypeScript check
pass on the regenerated state.

### P8-IR-004 — Loan cancellation lacked typed durable accounting

Severity before correction: MEDIUM inside the synthetic local scope. This was
production-blocking accounting and reconciliation work, not evidence of an on-chain
double spend.

The action 12 cancellation request and action 14 satellite burn/refund completion were
correctly bounded on-chain, but the durable accounting path did not project or commit
them. At discovery, the local worker's payload decoding, economic projection, and
action commit paths covered actions 1, 2, 5, 6, 7, 8, 9, and 10 only. Migrations
`000010` through `000012` had no loan-cancellation request/completion row or commit
function; the wrapped-burn kind and commit function recognized ordinary redemption,
loan repayment, and permanent burn only.

The remediation defines cancellation payload decoding and projection, Go
authority and journal construction, action 12 and action 14 worker commits, a separate
strict two-message cancellation import mode, append-only SQL request/completion
records, registered accounting identities, concurrency-safe completion replay, and
four immutable source/acknowledgement inclusion objects that are rehydrated before the
worker reports durable success. Focused worker tests establish that object-store
restart property.

Independent disposable-PostgreSQL execution exposed and corrected an invalid interim
nonzero-branch precondition. The interim SQL required the disbursement message both to
have produced an acknowledged `disbursement_authorizations` row and to have an exact
destination tombstone. An authorization row is derived only after destination
execution and acknowledgement, while the coordinator correctly forbids an executed
message from being tombstoned; those states cannot coexist.

The corrected durable boundary instead binds the original action 6 message in
`DESTINATION_TOMBSTONED`, its exact route policy, family, components, loan aggregate,
tombstone, source finality, and absence of execution or acknowledgement. Action 12
causation binds that message, or the exact wrapped-mint message in the zero-disbursement
case; action 14 causation binds the stored action 12. Fresh isolated PostgreSQL now
passes both branches, exact and conflicting replay, changed route and executed-action-6
substitution, generic action-14 rejection, late-journal transaction rollback, exact
balanced journals, runtime privilege checks, and owner-context append-only triggers.
A deterministic two-session first-completion test additionally observes the second
writer waiting on a PostgreSQL lock before both same-input calls and a later terminal
replay succeed with one completion row, one terminal loan transition, and exactly the
three reviewed journal pairs. Two independent executions of that harness passed.

Generic recovery compensation is safely separate but is not a substitute. It requires
a recovery request, finalized destination tombstone, and compensation of an original
failed message. Its journals reverse an original action 1 lock or restore an original
action 3, 8, or 15 burn. Governed loan cancellation instead follows the normal action
12 to typed action 14 message path and creates no generic recovery-compensation row.
The shared ordinal 14 therefore grants no accounting authority by itself.

Closure evidence satisfied:

- retain an immutable action 12 request projection but post no economic journal from
  cancellation intent alone;
- provide a bounded authenticated cancellation input path that is actually reachable
  from the executable importer through projection and SQL commit, independently of the
  fixed eight-message happy-path flow;
- for a nonzero disbursement/tombstone pair, require the referenced original action 6
  message to use the exact reviewed disbursement route, family, source and destination
  components and loan aggregate, be in `DESTINATION_TOMBSTONED`, match the exact
  tombstone, and have no execution result or acknowledgement; do not require an
  acknowledged disbursement-authorization projection that is mutually exclusive with
  the tombstone;
- bind the action 12 causation to that exact tombstoned action 6 message, or, for the
  zero-disbursement branch, to the exact wrapped-mint message for the funding lock; bind
  action 14 causation to the stored action 12 message;
- add an append-only typed action 14 completion record binding the exact cancellation,
  loan, funding lock, disbursement message/tombstone pair, escrow-burn result, home loan
  account, lender, wrapped-token address, canonical and wrapped accounting asset
  identities, units, policy, route, source component, source burn evidence, and
  destination refund execution;
- permit only an acknowledged `SATELLITE_FUNDING_CANCELLED` action 14 on the exact
  report route and source component to post, atomically and idempotently, the wrapped
  cancellation-burn control journal (`7160` debit / `9150` credit), canonical-refund
  financial journal (`2230` debit / `1410` credit), and canonical-refund control journal
  (`9150` debit / `7150` credit);
- keep EVM addresses distinct from ledger party and asset identifiers, with both
  independently bound to the registered loan and typed projection;
- reject action 12, generic `SOURCE_COMPENSATED`, wrong stage, route, family, source,
  typed payload, cancellation ID, funding lock, disbursement/tombstone, burn result,
  account, lender, token, accounting identity, units, or policy without a row or
  journal; and
- prove exact replay, conflicting replay, transaction rollback, append-only/direct-write
  privilege enforcement, concurrency-safe same-input replay, and balanced journal
  links in Go and disposable PostgreSQL.

Disposition: corrected. The Go authority and worker projection suites, immutable-object
restart and rehydration test, fresh disposable-PostgreSQL migration suite, runtime and
owner privilege checks, deterministic first-insert contention harness, and balanced
journal assertions pass. The full Go, Python, TypeScript, schema, architecture,
privileged-surface, ABI, and Solidity compilation checks also pass on the reviewed
source state. Two consecutive generations remain byte-deterministic across all 42
generated, registry, and invariant files. The repository-wide freshness command still
compares the intentionally uncommitted Phase 8 source state to Git `HEAD`; therefore its
working-tree `git diff --exit-code` is not used as generation-determinism evidence in
this pre-commit review.

## Residual boundaries

### Cancellation authorization expiry and reissue

The recovery controller intentionally permits one cancellation authorization identity per
loan, and the factory returns the same action 12 message for exact replay. If that
authorized message expires before satellite execution, there is no explicit protocol
path to issue a fresh later-expiry action 12 for the same loan. The loan can remain
`RECOVERY_PENDING` until governed remediation.

This is a liveness residual, not a double-spend or false-refund path: satellite burn
still requires the exact executable action, any existing disbursement requires its exact
destination tombstone, and home refund still requires finalized action 14. No canonical
or wrapped value moves merely because authorization expired. Before production, a
separate ADR must define either a domain-bound superseding authorization/message or an
explicit terminal recovery procedure with monotonic nonce, old-message invalidation, and
the same tombstone/burn/report/refund constraints.

### Authenticated collateral absence and terminalization

Cancellation may burn wrapped funding and refund the lender before the home domain has
received a finalized collateral report. The account correctly remains
`RECOVERY_PENDING`: it cannot infer from delayed delivery that collateral was never
locked. If collateral was locked, the late finalized report triggers one exact borrower
release and terminal closure.

If collateral was truly never locked, however, no positive report will arrive and the
current protocol has no authenticated absence proof or terminalization action. The loan
can therefore remain nonterminal even though wrapped funding is burned, the lender is
refunded, and home debt is zero. This is a state-liveness residual, not trapped lender
value, borrower debt, double spend, or false-refund authority. Before production, a
separate ADR must define a finality-bound negative-custody proof or governed terminal
procedure that cannot race a later valid collateral lock/report.

### Local-only authority

All Phase 8 chains, headers, observer keys, two-of-three signers, providers, accounts,
tokens, collateral, balances, RPCs, database rows, broker records, objects, and funds are
synthetic local fixtures. Anvil validates EVM mechanics; it is not a production
consensus, finality, bridge, or reorganization model. The Ed25519 observer and local
ECDSA threshold are assumed uncompromised test trust roots, not a light client or
production validator proof.

This review authorizes no production home or satellite chain, public testnet, mainnet,
bridge vendor, relayer, RPC, oracle, identity provider, real asset, real fund, treasury,
HSM/KMS key, production signer custody, fee/FX conversion, emergency override,
force-unlock, live monitoring claim, or legal/accounting/custody conclusion. Every such
item requires a separately ratified ADR, threat model, provider/chain due diligence,
production key ceremony, operational controls, and independent review.

`UNI-REVIEW-011` remains `TODO` and is reserved for the separate Phase 8 exit PR. This
internal review must not be used to bypass that gate.

## Proposed backlog status updates

These are proposed CSV transitions after the authoritative live smoke,
release-evidence validation, ABI freshness, generated-code freshness, full checks, and
clean reset all pass on the final source state. This document does not itself edit the
backlog.

| Backlog ID | Current | Proposed | Review basis |
| --- | --- | --- | --- |
| `UNI-ADR-013` | `DONE` | `DONE` | ADR 0018 remains the accepted bounded authority. |
| `UNI-LOCAL-002` | `TODO` | `DONE` | Two isolated local domains, manifests, smoke, and reset evidence. |
| `UNI-POLICY-007` | `TODO` | `DONE` | Immutable chain, route, finality, exposure, and loan policy binding. |
| `UNI-BRIDGE-001` | `TODO` | `DONE` | Domain-bound ordered coordinator and at-most-once execution. |
| `UNI-BRIDGE-002` | `TODO` | `DONE` | Exact transport-only loopback provider failover and proof authority separation. |
| `UNI-INDEX-006` | `TODO` | `DONE` | Signed-header, transaction/receipt inclusion, finality, and reorg projection. |
| `UNI-SCHEMA-012` | `TODO` | `DONE` | Exact additive cancellation types and deterministic four-language regeneration independently pass. |
| `UNI-RISK-002` | `TODO` | `DONE` | Ten risks, eight assumptions, frozen exposure evidence, owners, and tests. |
| `UNI-UFT-005` | `TODO` | `DONE` | Lock/mint and burn/release conservation with exact backing and cancellation burn. |
| `UNI-BRIDGE-003` | `TODO` | `DONE` | Ordered tombstone/compensation and bounded cancellation recovery; expiry reissue remains a recorded production liveness residual. |
| `UNI-DATA-002` | `TODO` | `DONE` | Additive cancellation rows, role separation, supported transitions, and direct-write rejection pass. |
| `UNI-ACCOUNTING-011` | `TODO` | `DONE` | Typed action 14 cancellation journals and substitution/replay/privilege tests pass. |
| `UNI-RECON-003` | `TODO` | `DONE` | Cross-domain backing, supply, custody, debt, message, journal, exposure, and recovery reconciliation. |
| `UNI-LOAN-003` | `TODO` | `DONE` | Debt only after borrower value; immutable economics and both repayment paths. |
| `UNI-COLLATERAL-009` | `TODO` | `DONE` | Exclusive satellite custody and one exact finalized borrower release. |
| `UNI-SATELLITE-001` | `TODO` | `DONE` | Bounded typed satellite reports cannot rewrite home economics. |
| `UNI-SIM-007` | `TODO` | `DONE` | Independent failure simulations, fuzzing, and stateful invariants. |
| `UNI-SEC-013` | `TODO` | `DONE` | Internal review finds no unresolved critical or existential local-scope issue. |
| `UNI-REVIEW-011` | `TODO` | `TODO` | Reserved for the separate bounded engineering exit PR. |

No unresolved critical or existential finding remains inside the explicitly synthetic
local-only boundary.
