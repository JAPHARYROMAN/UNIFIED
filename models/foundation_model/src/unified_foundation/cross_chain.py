"""Deterministic Phase 8 cross-chain conservation and recovery state machine."""

from dataclasses import dataclass, field
from enum import StrEnum


class CrossChainScenario(StrEnum):
    NORMAL = "NORMAL"
    PROVIDER_FAILOVER = "PROVIDER_FAILOVER"
    BOTH_PROVIDERS_OUTAGE = "BOTH_PROVIDERS_OUTAGE"
    DUPLICATE_REORDER = "DUPLICATE_REORDER"
    DEPENDENCY_REORDER = "DEPENDENCY_REORDER"
    DELIVERY_DELAY = "DELIVERY_DELAY"
    PRE_FINALITY_REORG = "PRE_FINALITY_REORG"
    DEEP_FINALITY_REORG = "DEEP_FINALITY_REORG"
    SIGNER_COMPROMISE = "SIGNER_COMPROMISE"
    RELAYER_FABRICATION = "RELAYER_FABRICATION"
    TIMEOUT_BEFORE_EXECUTION = "TIMEOUT_BEFORE_EXECUTION"
    TIMEOUT_EXECUTION_RACE = "TIMEOUT_EXECUTION_RACE"
    COMPLETE_ROUTE_LOSS = "COMPLETE_ROUTE_LOSS"
    BACKING_IMPAIRMENT = "BACKING_IMPAIRMENT"
    WORKER_RESTART = "WORKER_RESTART"
    DIRECT_HOME_REPAYMENT = "DIRECT_HOME_REPAYMENT"


class CrossChainOutcome(StrEnum):
    ACTIVE = "ACTIVE"
    CLOSED = "CLOSED"
    RECOVERED = "RECOVERED"
    RECOVERY_PENDING = "RECOVERY_PENDING"
    DISPUTED = "DISPUTED"


@dataclass(frozen=True)
class CrossChainResult:
    scenario: CrossChainScenario
    outcome: CrossChainOutcome
    provider: str | None
    debt_before: int
    debt_after: int
    home_uft_locked: int
    wrapped_uft_supply: int
    lender_home_uft_received: int
    collateral_locked: bool
    collateral_released: bool
    destination_tombstoned: bool
    source_compensated: bool
    duplicate_executions: int
    failover_count: int
    reconciliation_difference: int
    route_paused: bool
    provider_attempts: tuple[str, ...]
    accepted_finality_certificates: int
    execution_count: int
    acknowledgement_count: int
    recovery_count: int
    dependency_deferrals: int
    incident_opened: bool
    event_trace: tuple[str, ...]

    @property
    def backing_exact(self) -> bool:
        return self.home_uft_locked == self.wrapped_uft_supply

    @property
    def ledger_balanced(self) -> bool:
        return self.reconciliation_difference == 0

    @property
    def safely_terminal(self) -> bool:
        return (
            self.outcome in {CrossChainOutcome.CLOSED, CrossChainOutcome.RECOVERED}
            and self.ledger_balanced
            and not self.route_paused
            and self.execution_count <= 1
            and self.recovery_count <= 1
            and not (self.execution_count and self.source_compensated)
        )


@dataclass
class _Simulation:
    scenario: CrossChainScenario
    units: int
    debt_before: int
    repayment: int
    debt_after: int = field(init=False)
    home_uft_locked: int = 0
    wrapped_uft_supply: int = 0
    lender_home_uft_received: int = 0
    collateral_locked: bool = False
    collateral_released: bool = False
    destination_tombstoned: bool = False
    source_compensated: bool = False
    provider: str | None = None
    provider_attempts: list[str] = field(default_factory=list)
    failover_count: int = 0
    reconciliation_difference: int = 0
    route_paused: bool = False
    accepted_finality_certificates: int = 0
    execution_count: int = 0
    acknowledgement_count: int = 0
    recovery_count: int = 0
    dependency_deferrals: int = 0
    incident_opened: bool = False
    events: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.debt_after = self.debt_before

    def lock(self) -> None:
        self.home_uft_locked += self.units
        self.events.append("home.locked")

    def submit(self, provider: str, *, succeeds: bool) -> None:
        self.provider_attempts.append(provider)
        self.events.append(f"provider.{provider}.{'accepted' if succeeds else 'failed'}")
        if succeeds:
            self.provider = provider

    def accept_finality(self) -> None:
        if self.accepted_finality_certificates:
            self.events.append("source.finality.replay")
            return
        self.accepted_finality_certificates = 1
        self.events.append("source.finality.accepted")

    def execute_mint(self) -> None:
        if not self.accepted_finality_certificates or self.destination_tombstoned:
            self.events.append("destination.execution.rejected")
            return
        if self.execution_count:
            self.events.append("destination.execution.replay")
            return
        self.execution_count = 1
        self.wrapped_uft_supply += self.units
        self.collateral_locked = True
        self.events.extend(("destination.minted", "satellite.collateral.locked"))

    def acknowledge(self) -> None:
        if self.execution_count != 1:
            self.events.append("acknowledgement.rejected")
            return
        if self.acknowledgement_count:
            self.events.append("acknowledgement.replay")
            return
        self.acknowledgement_count = 1
        self.events.append("acknowledgement.accepted")

    def remote_repay(self) -> None:
        if self.execution_count != 1 or self.destination_tombstoned:
            self.events.append("repayment.rejected")
            return
        self.wrapped_uft_supply -= self.repayment
        self.home_uft_locked -= self.repayment
        self.debt_after -= self.repayment
        self.lender_home_uft_received += self.repayment
        self.events.extend(("satellite.wrapped.burned", "home.backing.released"))
        if self.debt_after == 0:
            self.collateral_locked = False
            self.collateral_released = True
            self.events.append("satellite.collateral.released")

    def direct_home_repay(self) -> None:
        self.debt_after -= self.repayment
        self.lender_home_uft_received += self.repayment
        self.events.append("home.repayment.posted")
        if self.debt_after == 0:
            self.collateral_locked = False
            self.collateral_released = True
            self.events.append("satellite.collateral.released")

    def tombstone(self) -> None:
        if self.execution_count:
            self.events.append("destination.tombstone.rejected.executed")
            return
        if self.destination_tombstoned:
            self.events.append("destination.tombstone.replay")
            return
        self.destination_tombstoned = True
        self.events.append("destination.tombstoned")

    def compensate(self) -> None:
        if (
            not self.destination_tombstoned
            or self.execution_count
            or self.source_compensated
        ):
            self.events.append("source.compensation.rejected")
            return
        self.home_uft_locked = 0
        self.lender_home_uft_received += self.units
        self.source_compensated = True
        self.recovery_count = 1
        self.events.append("source.compensated")

    def dispute(self, reason: str, *, difference: int = 0) -> None:
        self.route_paused = True
        self.incident_opened = True
        self.reconciliation_difference = difference
        self.events.extend((f"incident.{reason}", "route.paused"))

    def finish(self) -> CrossChainResult:
        if self.incident_opened:
            outcome = CrossChainOutcome.DISPUTED
        elif self.source_compensated:
            outcome = CrossChainOutcome.RECOVERED
        elif self.provider is None and self.home_uft_locked:
            outcome = CrossChainOutcome.RECOVERY_PENDING
        elif self.debt_after == 0:
            outcome = CrossChainOutcome.CLOSED
        else:
            outcome = CrossChainOutcome.ACTIVE
        return CrossChainResult(
            scenario=self.scenario,
            outcome=outcome,
            provider=self.provider,
            debt_before=self.debt_before,
            debt_after=self.debt_after,
            home_uft_locked=self.home_uft_locked,
            wrapped_uft_supply=self.wrapped_uft_supply,
            lender_home_uft_received=self.lender_home_uft_received,
            collateral_locked=self.collateral_locked,
            collateral_released=self.collateral_released,
            destination_tombstoned=self.destination_tombstoned,
            source_compensated=self.source_compensated,
            duplicate_executions=max(0, self.execution_count - 1),
            failover_count=self.failover_count,
            reconciliation_difference=self.reconciliation_difference,
            route_paused=self.route_paused,
            provider_attempts=tuple(self.provider_attempts),
            accepted_finality_certificates=self.accepted_finality_certificates,
            execution_count=self.execution_count,
            acknowledgement_count=self.acknowledgement_count,
            recovery_count=self.recovery_count,
            dependency_deferrals=self.dependency_deferrals,
            incident_opened=self.incident_opened,
            event_trace=tuple(self.events),
        )


def _deliver_and_activate(simulation: _Simulation) -> None:
    simulation.accept_finality()
    simulation.execute_mint()
    simulation.acknowledge()


def simulate_cross_chain_loan(
    *,
    units: int,
    debt_before: int,
    repayment_units: int | None = None,
    scenario: CrossChainScenario = CrossChainScenario.NORMAL,
) -> CrossChainResult:
    """Run one bounded loan through message, value, debt, custody, and recovery state."""
    repayment = units if repayment_units is None else repayment_units
    if (
        units <= 0
        or debt_before <= 0
        or units != debt_before
        or repayment <= 0
        or repayment > debt_before
    ):
        raise ValueError("invalid Phase 8 local loan or repayment amount")

    sim = _Simulation(scenario, units, debt_before, repayment)
    sim.lock()

    if scenario in {
        CrossChainScenario.BOTH_PROVIDERS_OUTAGE,
        CrossChainScenario.COMPLETE_ROUTE_LOSS,
    }:
        sim.submit("mock-bridge-provider-a", succeeds=False)
        sim.submit("mock-bridge-provider-b", succeeds=False)
        sim.failover_count = 1
        sim.route_paused = scenario == CrossChainScenario.COMPLETE_ROUTE_LOSS
        if sim.route_paused:
            sim.events.append("route.paused")
        return sim.finish()

    if scenario == CrossChainScenario.PROVIDER_FAILOVER:
        sim.submit("mock-bridge-provider-a", succeeds=False)
        sim.submit("mock-bridge-provider-b", succeeds=True)
        sim.failover_count = 1
    else:
        sim.submit("mock-bridge-provider-a", succeeds=True)

    if scenario in {
        CrossChainScenario.PRE_FINALITY_REORG,
        CrossChainScenario.TIMEOUT_BEFORE_EXECUTION,
    }:
        sim.events.append(
            "source.pre-finality.reorg"
            if scenario == CrossChainScenario.PRE_FINALITY_REORG
            else "message.expired"
        )
        sim.tombstone()
        sim.compensate()
        return sim.finish()

    if scenario in {
        CrossChainScenario.SIGNER_COMPROMISE,
        CrossChainScenario.RELAYER_FABRICATION,
    }:
        sim.events.append(
            "finality.wrong-signer-set.rejected"
            if scenario == CrossChainScenario.SIGNER_COMPROMISE
            else "source-proof.fabricated.rejected"
        )
        sim.provider = None
        sim.dispute(
            "signer-compromise"
            if scenario == CrossChainScenario.SIGNER_COMPROMISE
            else "relayer-fabrication"
        )
        return sim.finish()

    if scenario == CrossChainScenario.DEPENDENCY_REORDER:
        sim.dependency_deferrals = 1
        sim.events.append("repayment.deferred.missing-activation")

    _deliver_and_activate(sim)

    if scenario in {
        CrossChainScenario.DUPLICATE_REORDER,
        CrossChainScenario.WORKER_RESTART,
    }:
        sim.accept_finality()
        sim.execute_mint()
        sim.acknowledge()

    if scenario == CrossChainScenario.TIMEOUT_EXECUTION_RACE:
        sim.events.append("timeout.observed.after-finalized-execution")
        sim.tombstone()
        sim.compensate()

    if scenario == CrossChainScenario.DEEP_FINALITY_REORG:
        sim.dispute("deep-finality-reorg")
        return sim.finish()

    if scenario == CrossChainScenario.BACKING_IMPAIRMENT:
        impairment = max(1, units // 10)
        sim.home_uft_locked -= impairment
        sim.dispute("backing-impairment", difference=-impairment)
        return sim.finish()

    if scenario == CrossChainScenario.DIRECT_HOME_REPAYMENT:
        sim.direct_home_repay()
    else:
        sim.remote_repay()
    return sim.finish()
