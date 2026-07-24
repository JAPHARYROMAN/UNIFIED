# Phase 2 Protocol Kernel

Status: implemented foundation; not approved for production funds

## Boundary

Phase 2 establishes protocol identity, authority, immutable registries, genesis UFT
issuance, allocation custody, vesting, fee allocation, and emergency controls. It does
not implement loan offers, activation, servicing, repayment, collateral, accounting,
default, liquidation, governance voting, bridging, or external-provider integration.

The `UnifiedProtocol` contract is an immutable directory. It records the protocol
version, deployment-chain identity, reviewed chain-configuration hash, and component
addresses; it is not a universal custodian.

## Components

| Area | Contracts | Authority and invariant |
|---|---|---|
| Authority | `RoleManager`, `EmergencyController` | Expiring roles; administrator and governance executor must differ; emergency actions expire within seven days; repayment and collateral top-up cannot be paused. |
| Registries | `AssetRegistry`, `PolicyRegistry`, `LoanRegistry` | Identities are append-only. Asset and policy deactivation affects future use. Loan identity and agreement hashes cannot be reassigned. |
| Versioning | `LoanFactory`, `VersionedLoanAccount` | Implementation versions are append-only; loan accounts use deterministic clones; initialization is one-time. |
| UFT | `UnifiedToken`, `UFTBurner` | Exactly 1 billion UFT is issued to nine distinct named destinations in the constructor. No callable issuance path exists. Burns only reduce supply. |
| Allocation | `AllocationVault`, `VestingPoolVault` | Vaults bind once to canonical UFT and verify their full allocation. Contributor, investor, and partner pools enforce fixed cliff and duration parameters. |
| Revenue | `ProtocolFeeRouter` | Actual receipt is measured, split bounds total 10,000 bps, and rounding remainder goes to public goods. Five tokenomics-defined safety flags suspend burns. |

## Security boundary

- Registries and the kernel do not receive user assets.
- Allocation vaults release only through the treasury-operator role and emit an
  authorization reference.
- Vesting pool grants are bounded by their genesis capacity. Cancellation returns only
  unvested capacity to the same pool.
- Policy bytecode and ERC-165 interface support are verified when registered.
- A deprecated policy remains resolvable for already-bound loans but cannot be selected
  for a new binding.
- Loan accounts in this phase are identity shells only. Adding servicing methods is a
  Phase 3 change and requires a new registered implementation version.

## Deployment restrictions

The deployment script requires distinct administrator, governance, and seven
operational-role addresses. The seven operator addresses must also be mutually distinct.
For local simulation they may be test accounts. Any non-local deployment must replace
them with approved multisig, timelock, or bounded automation identities.

No Phase 2 deployment is authorized to hold real funds or connect to mainnet, external
payment providers, production keys, bridges, or price oracles.
