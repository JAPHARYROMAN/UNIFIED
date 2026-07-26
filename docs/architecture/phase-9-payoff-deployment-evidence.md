# Phase 9 payoff deployment evidence

The payoff deployment has two deliberately separate stages. A Forge simulation cannot
authorize activation because script-side reads and file writes occur before Forge sends
broadcast transactions.

## Stage A: broadcast and non-accepted candidate

`DeployPhase9Local.s.sol` deploys the exact local token and the constructor-only pair
deployer. The pair deployment transaction creates the payoff engine at pair-deployer
nonce `1` and the refinance coordinator immediately afterward at nonce `2`. The script
writes only `PHASE9_PAYOFF_DEPLOYMENT_CANDIDATE`, with `activation_accepted = false` and
`post_broadcast_verification_required = true`. Running without `--broadcast` can never
produce accepted evidence. `maximum_quote_validity` is serialized as a base-10 decimal
string so the full `uint64` range remains portable across JSON consumers. The entrypoint
rejects every output path except the canonical candidate path before broadcasting.

From `protocol/`, substitute the existing local dependency addresses:

```powershell
New-Item -ItemType Directory -Force deployments/local | Out-Null
forge script script/DeployPhase9Local.s.sol:DeployPhase9Local `
  --rpc-url http://127.0.0.1:8545 `
  --broadcast `
  --sig "run((address,address,address,address,address,address,address,address,address,uint64),string)" `
  "(<loan-registry>,<phase9-factory>,<quote-policy>,<lien-registry>,<asset-registry>,<refinance-policy>,<emergency-controller>,<treasury-recipient>,<fixture-allocator>,3600)" `
  "deployments/local/phase9-payoff-deployment-candidate.json"
```

The actual Forge artifact is expected at
`protocol/broadcast/DeployPhase9Local.s.sol/31337/run-latest.json`.

Before any broadcast, verify the reviewed manifest against the current Forge artifacts
without making a network call:

```powershell
uv run python tools/verify_phase9_payoff_deployment.py --check-pins
```

This command accepts only the canonical manifest at
`infrastructure/local/phase9-payoff-deployment-code-hashes.json`. It verifies the
reviewed manifest digest, compiler profile, exact repository-relative artifact paths,
compiler source hashes, and creation/runtime bytecode sizes and hashes. Stale artifacts
and absolute, traversal, alternate, or symlinked artifact paths are rejected.

## Stage B: post-broadcast verification

From the repository root, run:

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
and reads runtime code plus engine slots `0..3` and coordinator slots `0..8` at the pair
receipt block.

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
was reverted. No loan or quote may be created before accepted evidence exists.
