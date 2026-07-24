# Phase 6B Storage Layouts

Compiler: Solidity `0.8.36`

Foundry: `1.7.1`

OpenZeppelin Contracts: `5.6.1`

Optimizer: enabled, 200 runs

`UnderwrittenLoanFactory` has no linear storage slots. Its registry, manager, controller,
and implementation dependencies are constructor immutables. OpenZeppelin's reentrancy
guard uses its isolated namespaced location and does not add a linear application slot.

The Phase 6B change to `CoreLoanFactory` adds only a policy-interface rejection and
changes no storage or external interface. Existing version-2 factory and account
deployments are not upgraded.

All Phase 6B contracts are non-upgradeable. A semantic change requires a new implementation
version, new factory deployment, and explicit role and policy review.
