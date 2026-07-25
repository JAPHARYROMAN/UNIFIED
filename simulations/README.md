# Simulations

Economic, liquidity, governance-concentration, collateral, and failure simulations live
in `models/foundation_model/src/unified_foundation`.

Phase 8 adds an event-traced cross-chain loan and wrapped-UFT conservation state machine
in `cross_chain.py`. It covers normal completion, delay, duplicate and dependency
reordering, worker restart, one- and two-provider outage, pre- and post-finality
reorganization, signer compromise, relayer fabrication, timeout-before-execution and
timeout/execution races, complete route loss, backing impairment, and partial or full
remote and direct-home repayment. Every result exposes message executions,
acknowledgements, recovery attempts, provider attempts, reconciliation difference, and
the ordered economic event trace. Unsafe or contradictory authority fails closed
without both executing and compensating the same message or releasing both home value
and satellite collateral.
