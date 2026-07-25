# Phase 8 Engineering Exit Review

Date: 2026-07-25

Decision: PASS for the bounded synthetic local two-domain cross-chain and wrapped UFT
engineering milestone at merged commit
`75527934a83ff711e3b07d93719ff1b66d8120da`

Production chain, consensus, provider, signer, key, public-network, real-asset, or
real-fund authorization: NOT GRANTED

## Reviewed scope

This review covers the complete Phase 8 implementation merged through commit
`75527934a83ff711e3b07d93719ff1b66d8120da` and all five required work packages:

1. canonical cross-chain coordination;
2. bounded satellite loan components;
3. replaceable transport-only messaging adapters;
4. a fully backed, exposure-capped wrapped UFT bridge; and
5. timeout, failure, route-compromise, tombstone, cancellation, and compensation
   recovery.

The reviewed boundary includes canonical Protobuf and deterministic four-language
derivatives, authenticated source and destination inclusion/finality evidence,
at-most-once typed execution, immutable route and loan policy, home-owned economics,
exclusive satellite collateral custody, durable least-privilege stores, evidence-linked
accounting and reconciliation, failure simulations, the two-domain local topology,
release-evidence validation, and one-command reset.

## Exit criteria

| Criterion | Result | Evidence |
| --- | --- | --- |
| Cross-language identities are deterministic | PASS | Solidity, Go, TypeScript, and Python golden encoders bind the reviewed message, finality, recovery, acknowledgement, and cancellation preimages; the internal review recorded two byte-identical generations across all 42 generated, registry, and invariant files, and merged conformance independently passed freshness |
| Invalid authority or changed content fails closed | PASS | protocol, domain, coordinator, component, route, signer set, aggregate, action, payload, nonce, expiry, transaction, receipt, log, finality, policy, correlation, causation, and supersession substitutions are rejected |
| Messages execute at most once and in valid order | PASS | lane nonces, exact digest replay, conflicting-reuse rejection, atomic consume-and-effect, concurrent duplicates, restart, two-provider delivery, retryable target failure, acknowledgement, and replay tests pass |
| Transport cannot manufacture authority | PASS | two loopback providers carry the same immutable envelope and proof, provider A outage fails over to provider B without changing identity, and provider receipts cannot replace authenticated source inclusion or threshold finality |
| Finality and reorganization evidence is authenticated | PASS | signed domain-pinned headers, canonical transaction and receipt Merkle-Patricia inclusion, exact log decoding, threshold certificates, monotonic observations, finality depth, reorganization records, and alternate-authority rejection are enforced |
| Wrapped UFT remains fully backed and exposure bounded | PASS | canonical lock precedes wrapped mint, wrapped burn precedes canonical release, exact balance deltas and recipients are required, replay cannot move value twice, and stateful invariants preserve escrow, supply, route-absolute, chain-absolute, adapter-absolute, aggregate-absolute, route 5%, and aggregate 15% limits |
| Satellite execution cannot rewrite home economics | PASS | immutable home principal, parties, terms, policy, debt, and terminal state remain canonical; debt activates only after finalized collateral and borrower disbursement, while direct home repayment remains live during route outage |
| Collateral remains exclusive and releases once | PASS | one synthetic collateral asset supports one canonical lien and releases to the canonical borrower only after an exact finalized home authorization; duplicate custody and premature or conflicting release fail |
| Recovery cannot create destination effect and source unlock | PASS | expiry alone grants no refund; ordered destination tombstone precedes compensation, execution and tombstone are exclusive, cancellation burn precedes home refund, disbursement-winning races activate debt, and exact replay is idempotent |
| Durable accounting and reconciliation preserve evidence | PASS | the exact 49-table durable release-evidence commitment, separated runtime roles, approved transaction functions, append-only records, immutable authenticated objects, exact replay, balanced bridge/loan/cancellation/recovery journals, and owned reconciliation differences are validated |
| The product is reproducible and disposable | PASS | a clean two-domain local run deploys eight healthy services, processes the complete synthetic loan, preserves restart state, validates exact release evidence, resets with one command, and proves post-reset absence |
| Critical and existential risks are owned | PASS | `RISK-PHASE8-001` through `RISK-PHASE8-010` and `ASM-026` through `ASM-033` retain named owners, controls, expiry or review conditions, evidence, and local-only status; the internal review has no unresolved critical or existential local-scope finding |

## Verification evidence

Implementation PR #38 passed all four protected checks and merged as
`75527934a83ff711e3b07d93719ff1b66d8120da`:

- Foundation `conformance`: passed, including deterministic generation, schema,
  architecture, ABI, documentation, and invariant checks;
- Foundation `local-smoke`: passed every two-domain deploy, synthetic command/event,
  authenticated Phase 8 flow, concurrent cancellation, pre-reset evidence, reset, and
  post-reset validation step;
- Security `dependency-audit`: passed after moving to Go 1.26.5,
  `golang.org/x/text` v0.39.0, and `golang.org/x/net` v0.56.0; `govulncheck` found zero
  reachable or imported-package vulnerabilities; and
- Security `secrets-and-filesystem`: passed secret detection and the HIGH/CRITICAL
  filesystem scan.

The clean source gate passed 32 Go packages, 112 Python tests with strict mypy across
29 files, TypeScript checks, 52 ABI snapshots, deterministic generated-code freshness,
109 Foundry tests, and 142 contract-size artifacts. The authoritative local release
cycle recorded eight authenticated messages, nine provider attempts, ten balanced
journals with twenty entries, sixteen content-addressed inclusion-evidence objects, the
exact 49-table commitment, restart rehydration, matched cross-domain reconciliation,
and terminal loan state `CLOSED`. A deterministic two-session cancellation test
observed the competing first writer waiting on the PostgreSQL row lock and preserved
one completion with exactly three balanced journal pairs.

Technical verification, the internal security review, the authoritative release gate,
and this governance review found no missing Phase 8 acceptance criterion and no
unresolved critical or existential finding within the explicitly synthetic local
boundary.

This decision becomes authoritative only when this separate exit-review change passes
the protected Foundation and Security checks and merges to `main`. PR #38 proves the
implementation revision; it does not bypass review of this exit artifact.

## Authority and value separation

- The home domain alone owns loan terms, principal, lender rights, debt, repayment
  allocation, and final closure.
- Satellite contracts report bounded custody, mint, disbursement, burn, repayment, and
  release facts but cannot originate or rewrite home economic authority.
- Messaging adapters transport immutable evidence; they cannot sign finality, select
  actions, recipients, or units, or carry value.
- Observer signatures, finality-threshold signatures, transport receipts, and
  accounting records remain separate authorities; none can substitute for another.
- Accounting consumes finalized, typed protocol evidence and cannot manufacture a
  bridge, cancellation, repayment, collateral-release, or compensation right.
- Route pause and cap reduction block new exposure while preserving evidence-gated
  redemption and recovery.

## Residual boundaries

### Cancellation authorization expiry and reissue

An exact governed cancellation authorization cannot currently be superseded with a
later expiry for the same loan. If action 12 expires before satellite execution, the
loan can remain `RECOVERY_PENDING` until governed remediation. This is a liveness
residual, not source-unlock or false-refund authority: no burn, refund, or value movement
occurs without the exact executable cancellation, destination tombstone when applicable,
satellite burn, and finalized action 14. Production use requires a separately accepted
supersession or terminal-recovery design.

### Authenticated collateral absence and terminalization

After a cancellation burn and lender refund, the home domain correctly waits for
finalized collateral truth. A late positive report releases exact collateral once and
closes the loan. When collateral was never locked, however, there is no authenticated
negative-custody proof or terminal action, so the zero-debt loan can remain nonterminal.
This is a state-liveness residual, not trapped lender value, borrower debt, double
spend, or false refund. Production use requires a finality-bound absence proof or a
governed terminal procedure that cannot race later valid custody.

### Unreachable dependency advisory

The configured Go dependency audit reports no reachable or imported-package finding.
The module graph includes `golang.org/x/crypto` v0.53.0, whose unused `openpgp` package
has the no-fix module-level advisory `GO-2026-5932`; the repository imports
`x/crypto/sha3`, not `openpgp`. Call-graph analysis and HIGH/CRITICAL filesystem
scanning both pass. This remains a dependency-review observation, not executable Phase
8 authority.

### Review horizon

The Phase 8 risk controls and assumptions are recorded only through 2026-10-25. Their
owners must revalidate them before that date or before any broader use, whichever comes
first. This exit does not extend local fixture assumptions into production.

Before any production-boundary proposal, the Program Authority must create stable
backlog IDs for the two liveness residuals and assign explicit Protocol Architecture and
Security owners with acceptance evidence. This exit record does not silently treat
those residuals as production-closed.

## Explicit production deferrals

This exit does not select or approve a production home or satellite chain, bridge,
relayer, messaging provider, RPC, header source, consensus verifier, light client,
finality threshold, oracle, identity provider, public testnet, or mainnet. It grants no
authority for real UFT, wrapped UFT, collateral, stablecoins, loans, lender or borrower
funds, treasury assets, production credentials, privileged operations, production
signers, HSM/KMS custody, or live recovery.

It also does not approve arbitrary chains or assets, non-EVM domains, multiple live
satellites, cross-asset exposure, FX, fees, slippage, rounding, interest, penalties,
multi-lender waterfalls, wrapped-token governance, staking, liquidity, reserves,
insurance, loss guarantees, production SLOs, disaster recovery, legal terms,
licensing, tax, custody, sanctions, external audit, penetration testing, or formal
verification.

Every production item requires a separately ratified ADR, provider and chain due
diligence, updated threat and economic-risk analysis, least-privilege IAM, production
key ceremony, operational and incident runbooks, independent audit, and explicit
deployment approval.

## Backlog decision and next milestone

`UNI-REVIEW-011` changes from `TODO` to `DONE` only when this exit-review revision
passes the required checks and merges to `main`. At that point all Phase 8 backlog rows
are complete inside the bounded synthetic local authority described above.

Phase 9 may begin only under a separately accepted boundary for refinancing,
restructuring, insurance, and recovery. This Phase 8 exit does not authorize payoff
accrual, lien replacement, policy voting, funded reserves, claims, write-off, or legal
recovery by implication.
