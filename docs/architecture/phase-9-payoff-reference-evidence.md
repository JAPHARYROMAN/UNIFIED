# Phase 9 payoff reference evidence

Status: reference evidence prepared; `UNI-PAYOFF-001` implementation acceptance is not
claimed by this document.

This evidence independently fixes the ABI field order and Solidity types used to verify
the payoff engine. The Python and TypeScript implementations do not import production
`PayoffQuoteEngine` logic or its test harness. The quote-ID differential does compare the
new independent encoder with the previously frozen cross-language quote codec so the
existing `632cc3...a2058` behavior cannot be redefined.

## Exact preimages

| Commitment | Exact `abi.encode` fields after the domain string |
| --- | --- |
| `UNIFIED_PAYOFF_POLICY_V1` | `uint256 chainId`, `address payoffQuoteEngine`, `address quotePolicyRegistry`, `bytes32 loanId`, `address loanAccount`, `bytes32 boundPolicySetHash`, `address feePenaltyBeneficiary`, `bytes32 settlementAssetId`, `address settlementToken`, `uint64 maximumValidity` |
| `UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1` | one `IPayoffQuoteEngineV2.PayoffComponentV2[]`; each tuple is `(uint8 kind, uint256 amount, address beneficiary, string obligationCode)` |
| `UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1` | `uint256 chainId`, `address payoffQuoteEngine`, `address refinanceCoordinator`, `bytes32 loanId`, `address loanAccount`, `bytes32 settlementAssetId`, `address settlementToken`, `address lenderBeneficiary`, `address feePenaltyBeneficiary`, `bytes32 policyHash` |
| `UNIFIED_PAYOFF_QUOTE_V1` | `address payoffQuoteEngine`, `uint256 chainId`, `bytes32 loanId`, `address loanAccount`, `bytes32 policyHash`, `uint64 debtStateVersion`, five `uint256` values for principal, accrued interest, fees, penalties, and credits, `bytes32 componentBeneficiaryHash`, `uint256 netPayoff`, `bytes32 settlementAssetId`, `address settlementToken`, `bytes32 settlementRouteHash`, three `uint64` values for issued at, valid until, and quote nonce |

Gross payoff and quote ID are deliberately absent from the quote-ID preimage. Component
encoding retains exactly five entries, including zero-valued entries, in this order:
`PRINCIPAL`, `ACCRUED_INTEREST`, `FEE`, `PENALTY`, `CREDIT`. It uses the enum values
`1, 2, 4, 5, 7` and exact obligation strings fixed by ADR 0020.

## Deterministic vector

The disposable local vector uses chain `31337`, engine `0x11..11`, policy registry
`0x12..12`, coordinator `0x13..13`, loan ID `0x33..33`, account `0x44..44`, policy-set
hash `0x88..88`, lender `0x99..99`, fee beneficiary `0x77..77`, asset ID `0xaa..aa`,
token `0x22..22`, maximum validity `300`, debt version `7`, amounts `90/5/3/3/1`
million units, issuance `1800000000`, expiry `1800000300`, and nonce `1`.

| Value | Keccak-256 |
| --- | --- |
| Policy hash | `0x5777a058cd8923e844c1c2e74ee82a0a8c4073084eddf4a44e860f68a3f5e718` |
| Component-beneficiary hash | `0xb43d774823fee6ffb1b0aaeaa005a119300aa1e65bcea9206f434fa4c3f01189` |
| Settlement-route hash | `0xadc8f2b001860d4d37fe42ce1340628670fe587ea3401947f75d8b2c6aac3aba` |
| Fully derived quote ID | `0xbfb9a4e4e14118a568ad2742e9607a45dc9ed0b3bf80b1d01364003f91d16988` |
| Frozen codec differential | `0x632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058` |

The four fully derived values were also reproduced with Foundry `cast abi-encode` and
`cast keccak` using the exact types above. Both language suites mutate every policy,
route, and quote-ID field; mutate component kind/order, amount, beneficiary, and string;
reject a four-entry vector; and prove zero entries remain materialized.

## Acceptance traceability

| Acceptance IDs | Evidence |
| --- | --- |
| `P9Q-POL-001`, `P9Q-POL-002`, `P9Q-POL-003` | Independent policy encoder, golden, and every-field mutations |
| `P9Q-COMP-001` through `P9Q-COMP-004` | Fixed five-entry constructor, dynamic tuple-array encoder, zero retention, mutation and omission checks |
| `P9Q-ROUTE-001`, `P9Q-ROUTE-002` | Independent route encoder, golden, and every-field mutations |
| `P9Q-ID-001` through `P9Q-ID-004` | Independent quote-ID encoder, exact field-set check, every-field mutations, and frozen-codec differential |

These tests are reference evidence only. Engine-issued differential, fuzz, invariant,
authorization, replay, and state-transition coverage remains required before
`UNI-PAYOFF-001` can be accepted.

## Evidence serialization boundary

`maximumValidity` remains a Solidity `uint64` in every commitment. JSON deployment and
release evidence serializes `maximum_quote_validity` as a canonical base-10 decimal
string, and its verifier rejects values outside `1..18446744073709551615`. A JSON number
is prohibited because the full `uint64` range is not exactly representable by common
JavaScript consumers.

## Implementation-checkpoint preparation

After the exact Solidity implementation and its dependency closure are frozen, collect
review inputs without creating a PASS entry:

```powershell
uv run python tools/update_phase9_implementation_checkpoint.py `
  --contract PayoffQuoteEngine `
  --backlog-id UNI-PAYOFF-001 `
  --evidence-only
```

The output intentionally contains no `status`, `reviewPath`, or `reviewSha256`. It does
include `implementationEvidenceBundleSha256`, whose exact ordinal path list is exported as
`PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS` by both checkpoint implementations. That bundle
covers the activation ADR, acceptance and evidence documents, reference implementations
and tests, Solidity harnesses, deployment schemas and verifier, checkpoint and compatibility
gates, foundation workflow and entrypoint, compiler aggregation, size policy, dependency
preparation, Git attributes, pinned Node and Python dependency graphs, TypeScript and Python
configuration, and the pinned local toolchain. The review, checkpoint registry, and backlog
are deliberately excluded to prevent self-referential hashes.

Independent architecture, security, and tooling reviewers must approve that exact source,
source-set, dependency-closure, evidence-bundle, ABI, and structural-storage evidence. The
canonical combined review path is `security/reviews/phase-9-payoff-quote-engine.md`. Its
visible canonical fields must name distinct implementation, architecture, security, and
tooling identities plus the exact lowercase 40-hex reviewed commit. Only after that review
exists and contains the exact required hashes may the owner mark `UNI-PAYOFF-001` `DONE`,
preview the candidate, and then write it:

The reviewed commit must resolve to a Git commit object. The checkpoint checker compares
that commit's raw blobs with every implementation-evidence file, every frozen Phase 9
source-set file, every repository-tracked file in the payoff dependency closure, and the
pinned workflow, package, lockfile, compiler, type-checker, size-gate, remapping, toolchain,
and dependency-preparation provenance inputs. Before hashing, both checkpoint implementations
require every evidence file's worktree bytes to equal the bytes produced by Git's clean
attributes. `.gitattributes` is itself reviewed evidence, all text is repository-canonical
LF, and hash-critical PowerShell scripts have an explicit LF rule. The ignored `protocol/lib`
copy remains a reproducible prepared dependency: its installed bytes are covered by the exact
recursive dependency-closure hash, while the commit binds package integrity, remapping, and
the copy procedure. The later combined review, backlog transition, and checkpoint registry
are intentionally excluded from this commit-byte comparison.

```powershell
uv run python tools/update_phase9_implementation_checkpoint.py `
  --contract PayoffQuoteEngine `
  --backlog-id UNI-PAYOFF-001 `
  --review-path security/reviews/phase-9-payoff-quote-engine.md

uv run python tools/update_phase9_implementation_checkpoint.py `
  --contract PayoffQuoteEngine `
  --backlog-id UNI-PAYOFF-001 `
  --review-path security/reviews/phase-9-payoff-quote-engine.md `
  --write
```

The preview and write paths remain fail-closed on review content/hash and identities,
backlog state, historical ABI and storage compatibility, exact source, dependency, and
evidence-bundle hashes, source-set membership, and implementation-checkpoint ordering. No
review, backlog completion, or checkpoint mutation is performed by the evidence-only
command.
