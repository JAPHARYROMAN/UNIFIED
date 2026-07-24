# Phase 2 Deployment

`DeployPhase2.s.sol` creates the kernel, all nine genesis vaults, fixed-supply UFT,
registries, version-1 loan identity implementation, burner, fee router, and immutable
protocol directory.

Run it only against a disposable local chain first. The configured broadcaster must be
the governance address passed to `run`. Inputs are:

1. a distinct administrator;
2. the governance executor/broadcaster;
3. seven mutually distinct operators in policy, asset, loan-factory, servicer,
   treasury, risk, and pause order; and
4. six revenue receivers in insurance, staker, treasury, suspended-burn reserve,
   liquidity, and public-goods order.

Operational account grants expire after 30 days. Contract roles held by the loan
factory and fee router are non-expiring; administrator, governance, and operational
accounts remain separated after bootstrap.

Use `forge script` without `--broadcast` for the mandatory simulation. Add
`--broadcast` only for an explicitly authorized local or testnet deployment. Private
keys must come from the wallet/runtime configuration and must never be embedded in this
repository or passed as Solidity arguments.
