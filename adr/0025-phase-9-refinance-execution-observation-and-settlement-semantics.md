# ADR 0025: Phase 9 Refinance Execution Observation and Settlement Semantics

Status: accepted for synthetic-local specification freeze; D3 remains closed

Date: 2026-07-27

Qualification: ADR 0026 repartitions this ADR's unchanged execution semantics across
fixed prepare and finalize modules. Any inherited reference to ADR 0023's three-module
candidate is historical. Snapshot, payout, provisional-state, lien-barrier, replay,
event, and rollback semantics in this ADR remain unchanged and cannot be weakened to
meet a code-size budget.

## Context

ADR 0021 fixes the Phase 9 atomic-refinance boundary, but four details remain too
ambiguous to implement or test safely:

- private checkpoint arrays cannot be enumerated through the frozen ABI, so a claim
  that execution proved the complete private history unchanged is not computable;
- a flat recipient-delta tuple is ambiguous when two canonical payout legs name the
  same external address;
- treating `EXECUTING` as both a transaction-local guard and a durable transition
  would create an extra version and event not represented by the terminal result; and
- per-collateral begin/complete interleaving does not prove that the complete old-lien
  set entered the pending state before any successor lien became active.

These are specification blockers for the D3 execution slice. They are resolved here
without changing any selector, event, error, tuple, storage declaration, interface,
library partition, or method-activation boundary.

## Decision

### 1. Authority and activation boundary

This ADR refines ADR 0021 Sections 2, 3, 9, 14, and 16 for the synthetic-local
candidate. It is subordinate to the historical `UNI-ABI-009` freeze and to the
candidate partition and activation controls in ADRs 0023 and 0024.

Acceptance of this ADR is documentation-only. `executeRefinance`, cancellation, and
refund remain D3 freeze stubs. `UNI-REFI-001`, `UNI-REFI-002`, every D1-D4 activation
gate, and `P9-REFI-001` remain closed. No implementation or deployment is authorized.

### 2. Computable old-position execution observations

Execution proves only facts observable through the frozen public views at one EVM
block. It does not claim to enumerate, hash, or prove the complete private checkpoint
arrays.

The canonical old position manager is re-resolved through the factory, account, and
loan registry. Execution requires `block.number <= type(uint64).max` and fixes:

```text
execution_block = uint64(block.number)
```

The names `ownerAt`, `votingPowerAt`, and `claimAt` below refer only to the already
frozen `positionOwnerAt`, `positionVotingPowerAt`, and `positionClaimAt` selectors.
They do not authorize shorter alias selectors.

The exact observations are:

```text
ordered_tranche_ids = old_position_manager.trancheIds()
ordered_tranches[i] = old_position_manager.tranche(ordered_tranche_ids[i])
ordered_tranche_ids_hash = keccak256(abi.encode(ordered_tranche_ids))
ordered_tranches_hash = keccak256(abi.encode(ordered_tranches))

old_tranche_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_TRANCHE_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_tranche_ids_hash,
  ordered_tranches_hash
))

ordered_position_ids = old_position_manager.positionIds()
ordered_positions[i] = old_position_manager.position(ordered_position_ids[i])
ordered_position_ids_hash = keccak256(abi.encode(ordered_position_ids))
ordered_positions_hash = keccak256(abi.encode(ordered_positions))

old_position_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_POSITION_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_position_ids_hash,
  ordered_positions_hash
))

owners_at_execution[i] =
  old_position_manager.positionOwnerAt(ordered_position_ids[i], execution_block)
voting_power_at_execution[i] =
  old_position_manager.positionVotingPowerAt(ordered_position_ids[i], execution_block)
claims_at_execution[i] =
  old_position_manager.positionClaimAt(ordered_position_ids[i], execution_block)
total_voting_power_at_execution =
  old_position_manager.totalVotingPowerAt(execution_block)
owners_at_execution_hash = keccak256(abi.encode(owners_at_execution))
voting_power_at_execution_hash = keccak256(abi.encode(voting_power_at_execution))
claims_at_execution_hash = keccak256(abi.encode(claims_at_execution))

old_rights_execution_snapshot_hash = keccak256(abi.encode(
  "UNIFIED_REFINANCE_OLD_RIGHTS_EXECUTION_SNAPSHOT_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  old_loan_id,
  old_position_manager,
  execution_block,
  ordered_position_ids_hash,
  owners_at_execution_hash,
  voting_power_at_execution_hash,
  claims_at_execution_hash,
  total_voting_power_at_execution
))
```

The ID vectors retain their bounded, strictly increasing unsigned-`bytes32` order.
Before the first external execution effect, these view results must match the accepted
canonical bootstrap issuance facts. After old-debt payoff and again before terminal
persistence, recomputation at the same `execution_block` must return the identical
three hashes. The terminal evidence binds those hashes and the effective-rights result.
At every observation point, each returned tranche/position embeds its indexed ID;
`owners_at_execution[i] == ordered_positions[i].owner`,
`voting_power_at_execution[i] == ordered_positions[i].votingPower`,
`claims_at_execution[i] == ordered_positions[i].claim`, and the checked sum of raw
position voting power equals `total_voting_power_at_execution`.

This proves the exact public execution-block observations and that execution did not
change them. It does not prove the length, contents, or byte identity of any private
checkpoint series. Effective claim and voting rights still become zero only through
the joined terminal-loan/debt rule in ADR 0021, not through mutation of raw issuance
facts or a checkpoint-only lookup.

### 3. Canonical payout legs, aliasing, and conservation

Execution has exactly four ordered payout legs, all derived from the consumed quote,
accepted record, and constructor-bound fee recipient:

```text
0 = (old_lender, old_lender_payoff_amount)
1 = (payoff_fee_recipient, payoff_fee_amount)
2 = (refinance_fee_recipient, refinance_fee)
3 = (borrower, borrower_proceeds)

old_lender_payoff_amount = quote.principal + quote.accruedInterest
payoff_fee_amount = quote.fees + quote.penalties - quote.credits
old_lender_payoff_amount + payoff_fee_amount = quote.netPayoff
```

Each of the four resolved recipients must be nonzero and must equal neither the
refinance coordinator nor the settlement-token address, including when its leg amount
is zero. Those checks complete before the quote is consumed or any balance changes.
The caller cannot select or replace a
recipient. Two or more of these canonical external recipients may be the same address;
such aliasing is valid and does not merge, omit, or reorder a payout leg. Token-address
self-transfer is rejected because it can satisfy superficial deltas while trapping
payoff value in a no-rescue slice. Beyond that explicit rejection, this freeze adds no
EOA/code-size/system-contract classification: another canonical code/system recipient
is allowed when every exact delta check passes. This is canonical-source tolerance,
not caller authority; no caller can introduce such an address.

For every leg in index order, the coordinator records the settlement-token balances
immediately before and after that leg. A positive leg performs exactly one transfer and
must satisfy both recipient inflow and coordinator outflow equal to the leg amount. A
zero leg performs no token call and both balances must be unchanged. The exact per-leg
commitment is:

```text
payout_leg_delta_hash[i] = keccak256(abi.encode(
  "UNIFIED_REFINANCE_PAYOUT_LEG_DELTA_V1",
  chainid,
  refinance_coordinator,
  refinance_id,
  settlement_token,
  uint8(i),
  payout_recipients[i],
  payout_amounts[i],
  leg_recipient_balance_before[i],
  leg_recipient_balance_after[i],
  leg_coordinator_balance_before[i],
  leg_coordinator_balance_after[i]
))
```

After the four leg-local checks, the coordinator forms the unique recipient vector by
sorting distinct recipient addresses in strictly increasing unsigned-`uint160` order.
For each unique address, its expected amount is the checked sum of every leg naming
that address. Its balance before the first leg and after the last leg must differ by
exactly that aggregate amount. Unsigned-`uint160` order is used because it is canonical,
independent of which role first names an alias, and directly implementable from an EVM
address without a new interface.

The final operation checks are exact:

```text
sum(payout_amounts) == funding_amount
funding_amount > 0
attributed_escrow_before == funding_amount
attributed_escrow_after == 0
coordinator_balance_before_all - coordinator_balance_after_all == funding_amount
```

Unattributed donations remain in the coordinator balance and are neither a liability
nor a payout source. Because the proof is a before/after outflow, donations do not have
to be zero and cannot hide a short payment. The exact aggregate evidence preimage is
defined in the refinance reference-evidence document.

### 4. `EXECUTING` is provisional and unversioned

`EXECUTING` is only a transaction-local, provisional reentrancy guard stored during an
execution attempt. Entering it:

- does not increment `stateVersion`;
- does not emit `RefinanceStateTransitioned` or any other state-transition evidence;
- does not write a terminal result; and
- is fully rolled back with every other effect when execution reverts.

On success there is exactly one durable state transition: the stored
`FUNDING_ESCROWED` state becomes `COMPLETED`, `stateVersion` increments exactly once,
and exactly one `RefinanceStateTransitioned` event reports
`FUNDING_ESCROWED -> COMPLETED` with the execute operation ID and
`evidenceHash == terminal_result_hash`. The frozen `RefinanceExecuted` success event
may still report the same terminal result; it is not a second state transition.

First execution requires `executionAttempts == 0` and the stored
`FUNDING_ESCROWED` version below `type(uint64).max`, both before external effects. The
successful terminal write sets the attempt to exactly `1` and the version to its checked
successor; a revert leaves the attempt at `0`, and an exact terminal replay leaves it at
`1`. The execution event ID therefore binds `execution_attempt == 1`. The provisional
`EXECUTING` state can never satisfy exact terminal replay: replay requires stored
`COMPLETED`, the matching processed execute operation, and the matching nonzero terminal
result. Only first execution reads the stored quote, recomputes the execute operation ID
from its pre-payoff debt-state version, and requires supplied-ID equality before writing
provisional `EXECUTING`. After terminal storage, the frozen
`RefinanceExecuted` event is emitted first and the one additive completion transition
event is emitted second, both binding the same `terminal_result_hash`.

After readiness validation and canonical re-resolution, but before the first external
execution effect, execution also requires `block.timestamp <= type(uint64).max` and
captures exactly one `executed_at = uint64(block.timestamp)`. That value is reused by
the execution-event ID, terminal-result preimage, stored terminal `recordedAt`, and all
execution result/event evidence; it is never resampled later in the transaction.

No durable view, replay result, version history, or event may represent `EXECUTING`.
An in-transaction reentrant mutator observes the provisional guard and fails. Exact
terminal replay branches before every first-execution current-state, old-loan-lock,
quote, or dependency read and is dependency-call-free. The record key and stored
`refinanceId` must identify the same nonzero refinance; the record must be `COMPLETED`
with attempt one; the supplied operation ID must be nonzero and processed; and the
terminal result must identify that refinance, be `COMPLETED`, have a nonzero event ID,
and have a nonzero result hash equal to terminal evidence. Replay reconstructs the
execution-event ID from the exact domain, chain, coordinator, refinance ID, stored
`quoteId`, supplied operation ID, `uint32(1)`, and terminal `recordedAt`. The reconstructed
ID must be nonzero and equal the stored event ID. Any identity, state, attempt, operation,
quote-ID, recorded-time, event-ID, result, or evidence mismatch reverts
`RefinanceReplayConflict`. Exact replay returns the stored result with zero dependency
calls, writes, transfers, counters, or logs and never recomputes the execute operation ID
from a debt version.

### 5. Sorted two-pass lien handoff

All collateral IDs and expected handoff IDs are derived and validated before the first
handoff call. The vector has `1..16` members; count, order, tuple, ID, and version checks
complete before the first begin. The coordinator then uses the strictly increasing
unsigned-`bytes32` collateral order in four complete loops:

1. call `beginHandoff` for every collateral and require every returned handoff ID to
   equal its canonical `UNIFIED_LIEN_HANDOFF_V1` identity; before this loop, require
   every prior version to be below `type(uint64).max` and compute the exact checked
   `nextLienVersion = priorLienVersion + 1`;
2. call only lien-registry views for every collateral/handoff and verify that every old
   lien is `HANDOFF_PENDING`, still names the old senior loan and prior lien version,
   names the exact pending refinance and target loan, and that every handoff result is
   the exact corresponding `EXECUTING` record;
3. call `completeHandoff` for every handoff in the same order and require each returned
   result to be the exact `ACTIVE_NEW` record with `nextLienVersion ==
   priorLienVersion + 1`; each call supplies the indexed canonical handoff ID and exact
   indexed handoff evidence hash, and the returned tuple equals the expected tuple; and
4. call only lien-registry views for every collateral/handoff and verify that every
   lien is `ACTIVE` for the successor loan at the next version with zero pending IDs,
   and every stored handoff equals its returned `ACTIVE_NEW` result.

The pending window starts with the first `beginHandoff` and ends only after the last
active-state verification. During that window the coordinator makes only calls to the
canonical lien registry. In particular, there is no settlement-token, account,
position-manager, custody, resolver, registry-other-than-lien, arbitrary-target, or
callback-capable external call. All calculations and non-lien external observations
needed by completion are performed before the first begin call.

`LienRegistry.beginHandoff`, `completeHandoff`, `lien`, and `handoff` themselves make
no external call. They operate only on the registry's frozen storage and emit their
typed events. The final view equality proves the stored active handoff equals the tuple
returned by its indexed completion call.

Any mismatch or failure reverts every begin and completion in the transaction. A
pending target is never enforceable; the stored old senior identity remains the
enforceable lien throughout the pending phase; and no successor lien becomes active
until the complete old-lien set has passed the pending verification loop.

The pending `Lien` tuple preserves `collateralId`, `collateralManager`, `vault`,
`assetId`, `quantity`, and `borrower`; it has `seniorLoanId == oldLoanId`, the prior
version, `HANDOFF_PENDING`, and the exact nonzero pending refinance and target loan IDs.
The pending `LienHandoffResult` has the canonical handoff/refinance/collateral/old/new
IDs, the exact prior/next versions, `EXECUTING`, and zero evidence hash. The active
`Lien` preserves the same collateral facts, replaces only the senior loan and version,
has `ACTIVE`, and clears both pending IDs. The final `LienHandoffResult` preserves the
same identities and versions, has `ACTIVE_NEW`, and stores the exact handoff evidence
hash supplied to `completeHandoff`. Version overflow or any tuple mismatch fails before
the first begin call or reverts the complete transaction.

### 6. Evidence and completion gate

The exact V1 snapshot, payout, aggregate-recipient, coordinator-outflow, pending-lien,
and active-lien preimages in the reference-evidence document are normative. Independent
Solidity and cross-language vectors must mutate every field and ordering boundary.
`component_payout_hash` binds the consumed quote's exact stored
`componentBeneficiaryHash` directly, not an undefined or caller-authored component
hash. The coordinator re-hashes the exact five ordered
`IPayoffQuoteEngineV2.PayoffComponentV2[]` values returned for that quote under the
frozen `UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1` domain and requires equality with
both the consumed quote and accepted record before using the hash.
Replacement debt, tranche, and position hashes are exactly
`keccak256(abi.encode(value))` over the canonical resolver-returned frozen
`Phase9Types.DebtState`, `Phase9Types.Tranche[]`, and `Phase9Types.Position[]` values.

This ADR completes only `UNI-ADR-020`. D3 logic may open only after the complete bundled
implementation, compatibility, evidence, threat, and independent-review gates pass on
one reviewed commit. Nothing here changes the frozen ABI/storage/interface surface or
authorizes real funds, production keys, external providers, a public network, or a
mainnet deployment.

## Consequences

- Old issuance evidence is computable from frozen views and no longer overclaims proof
  of inaccessible private history.
- Recipient aliasing is safe because every leg and every distinct address reconcile.
- One execution produces one durable state version and one transition event.
- Every old lien is observed pending before any new lien can become active.
- D3 implementation and activation remain blocked.
