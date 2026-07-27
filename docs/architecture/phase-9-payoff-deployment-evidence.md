# Phase 9 payoff deployment evidence

Status: historical evidence for the accepted payoff-only checkpoint

This document preserves the reviewed nested pair-deployer procedure and its two stages.
It does not describe the current refinance deployment topology. ADRs 0021, 0023, and
0024 supersede that current-deployment use with an explicitly linked ten-CREATE graph
that forbids a pair deployer. A Forge simulation cannot authorize activation because
script-side reads and file writes occur before Forge sends broadcast transactions.

## Historical Stage A: broadcast and non-accepted candidate

`DeployPhase9Local.s.sol` deploys the exact local token and the constructor-only pair
deployer. The pair deployment transaction creates the payoff engine at pair-deployer
nonce `1` and the refinance coordinator immediately afterward at nonce `2`. The script
writes only `PHASE9_PAYOFF_DEPLOYMENT_CANDIDATE`, with `activation_accepted = false` and
`post_broadcast_verification_required = true`. Running without `--broadcast` can never
produce accepted evidence. `maximum_quote_validity` is serialized as a base-10 decimal
string so the full `uint64` range remains portable across JSON consumers. The entrypoint
rejects every output path except the canonical candidate path before broadcasting.

At the reviewed payoff commit, the Stage A invocation from `protocol/` was:

```powershell
New-Item -ItemType Directory -Force deployments/local | Out-Null
forge script script/DeployPhase9Local.s.sol:DeployPhase9Local `
  --rpc-url http://127.0.0.1:8545 `
  --broadcast `
  --sig "run((address,address,address,address,address,address,address,address,address,uint64),string)" `
  "(<loan-registry>,<phase9-factory>,<quote-policy>,<lien-registry>,<asset-registry>,<refinance-policy>,<emergency-controller>,<treasury-recipient>,<fixture-allocator>,3600)" `
  "deployments/local/phase9-payoff-deployment-candidate.json"
```

The corresponding historical Forge artifact path was
`protocol/broadcast/DeployPhase9Local.s.sol/31337/run-latest.json`.

At the payoff checkpoint's reviewed commit, the reviewed manifest was verified against
that commit's Forge artifacts without making a network call:

```powershell
uv run python tools/verify_phase9_payoff_deployment.py --check-pins
```

The historical tool and command are retained for reviewed-commit reconstruction and
their isolated regression fixtures. They are intentionally not invoked by the current
foundation gate and must not be used to validate, link, or authorize the current
refinance artifacts. Those artifacts are governed by
`phase-9-refinance-deployment-evidence.md` and its linked-module and ten-CREATE
verifiers.

The command accepts only the canonical manifest at
`infrastructure/local/phase9-payoff-deployment-code-hashes.json`. It verifies the
reviewed manifest digest, compiler profile, exact repository-relative artifact paths,
compiler source hashes, and creation/runtime bytecode sizes and hashes. Stale artifacts
and absolute, traversal, alternate, or symlinked artifact paths are rejected.

## Historical Stage B: post-broadcast verification

At the reviewed payoff commit, the post-broadcast invocation was:

```powershell
uv run python tools/verify_phase9_payoff_deployment.py `
  --candidate protocol/deployments/local/phase9-payoff-deployment-candidate.json `
  --broadcast protocol/broadcast/DeployPhase9Local.s.sol/31337/run-latest.json `
  --rpc-url http://127.0.0.1:8545 `
  --pins infrastructure/local/phase9-payoff-deployment-code-hashes.json `
  --output protocol/deployments/local/phase9-payoff-deployment-evidence.json `
  --rejection-output protocol/deployments/local/phase9-payoff-deployment-rejection.json
```

Activation mode accepts only these documented candidate, broadcast, manifest, accepted,
and rejection paths. Accepted or rejection output cannot be redirected to another file.
The RPC URL must be credential-free literal loopback HTTP with an explicit port:
`127.0.0.1`, `localhost`, or `::1`. HTTPS, LAN addresses, host aliases, URL credentials,
paths, queries, fragments, redirects, and proxy routing are rejected or disabled. The
verifier calls `eth_chainId` and requires the canonical `0x7a69` response before accepting
any evidence.

The verifier rejects dry-run artifacts. It binds both nonzero transaction hashes to the
RPC transactions and successful receipts; checks sender, consecutive sender nonces,
zero value, blocks, contract addresses, exact reviewed creation bytecode plus constructor
arguments, and the exact `PayoffPairDeployed` log; recomputes CREATE addresses and
constructor/configuration digests; independently checks reviewed compiled artifact pins;
and reads runtime code plus engine slots `0..3` and coordinator slots `0..8` through
EIP-1898 canonical block-hash references. The token observation is bound to its receipt
block hash; the pair, engine, coordinator, and storage observations are bound to the pair
receipt block hash. A same-height replacement block cannot authorize evidence.

The broadcast file must contain exactly two ordered CREATE transactions—local token,
then pair deployer—and exactly their two ordered receipts. Accepted evidence records the
canonical RPC URL, canonical RPC chain ID, and reviewed pin-manifest SHA-256. JSON inputs
with duplicate keys or noncanonical quantities are rejected, and the final accepted
payload is validated against the reviewed evidence schema before it is written.

Only this verifier writes `activation_accepted = true`. On failure it removes the named
accepted-output file and can write a rejection receipt with
`bounded_local_reset_required = true` and `deployment_history_reverted = false`. Dispose
of the bounded local deployment with:

```powershell
pwsh ./scripts/local-reset.ps1
```

Reset disposes local state; it does not claim that a completed historical transaction
was reverted. Once a rejection receipt exists, a later invocation cannot create accepted
evidence until the bounded reset removes the canonical local evidence directory. Accepted
and rejected evidence therefore cannot coexist. No loan or quote may be created before
accepted evidence exists. Canonical path checks reject symlink, Windows junction, and
other Windows reparse components and re-check final resolved containment within the
repository before reading, writing, or deleting any evidence file.
