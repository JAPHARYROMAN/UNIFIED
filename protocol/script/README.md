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

## Phase 7C synthetic mature settlement

`DeployPhase7C.s.sol` attaches one immutable mature-settlement policy and one exact-token
canonical repayment gateway to an existing local deployment. The broadcaster must
already hold policy-registration authority. The gateway is permanently bound to one
loan-factory address and protocol version; another factory/version requires another
gateway.

The policy input fixes distinct provider and target-token asset identities, separate
conversion and finality policy hashes, and a minimum reversal delay. Loans must include
the returned complete policy reference in their activation-time policy set. Current
`PAYMENT_FINALIZER_ROLE` and `ACCOUNTING_ATTESTER_ROLE` operators are intentionally
granted outside this script so deployment does not silently combine operating
authorities.

This harness is synthetic and local only. It deploys no provider connection, reserve,
swap, mint, collateral release, withdrawal, production credential, or live-fund path.
