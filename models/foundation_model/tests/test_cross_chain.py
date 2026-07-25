import pytest
from unified_foundation.cross_chain import (
    CrossChainOutcome,
    CrossChainScenario,
    simulate_cross_chain_loan,
)


@pytest.mark.parametrize(
    "scenario",
    (
        CrossChainScenario.NORMAL,
        CrossChainScenario.DELIVERY_DELAY,
        CrossChainScenario.DUPLICATE_REORDER,
        CrossChainScenario.DEPENDENCY_REORDER,
        CrossChainScenario.WORKER_RESTART,
        CrossChainScenario.TIMEOUT_EXECUTION_RACE,
    ),
)
def test_delivery_reorder_restart_and_timeout_race_execute_once(
    scenario: CrossChainScenario,
) -> None:
    result = simulate_cross_chain_loan(units=1_000, debt_before=1_000, scenario=scenario)

    assert result.outcome == CrossChainOutcome.CLOSED
    assert result.debt_after == 0
    assert result.home_uft_locked == result.wrapped_uft_supply == 0
    assert result.lender_home_uft_received == 1_000
    assert result.collateral_released
    assert result.execution_count == 1
    assert result.duplicate_executions == 0
    assert result.recovery_count == 0
    assert not result.source_compensated
    assert result.safely_terminal


def test_dependency_reorder_is_deferred_until_activation() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.DEPENDENCY_REORDER,
    )

    assert result.dependency_deferrals == 1
    assert result.event_trace.index("repayment.deferred.missing-activation") < (
        result.event_trace.index("destination.minted")
    )
    assert result.execution_count == result.acknowledgement_count == 1


def test_provider_failure_uses_transport_only_failover() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.PROVIDER_FAILOVER,
    )

    assert result.provider == "mock-bridge-provider-b"
    assert result.provider_attempts == (
        "mock-bridge-provider-a",
        "mock-bridge-provider-b",
    )
    assert result.failover_count == 1
    assert result.safely_terminal


@pytest.mark.parametrize(
    "scenario",
    (
        CrossChainScenario.BOTH_PROVIDERS_OUTAGE,
        CrossChainScenario.COMPLETE_ROUTE_LOSS,
    ),
)
def test_total_route_outage_preserves_value_for_recovery(
    scenario: CrossChainScenario,
) -> None:
    result = simulate_cross_chain_loan(
        units=1_000, debt_before=1_000, scenario=scenario
    )

    assert result.outcome == CrossChainOutcome.RECOVERY_PENDING
    assert result.provider is None
    assert len(result.provider_attempts) == 2
    assert result.home_uft_locked == 1_000
    assert result.wrapped_uft_supply == 0
    assert result.debt_after == result.debt_before
    assert result.execution_count == result.recovery_count == 0
    assert not result.collateral_released


def test_partial_remote_repayment_releases_equal_backing_and_keeps_collateral() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        repayment_units=400,
    )

    assert result.outcome == CrossChainOutcome.ACTIVE
    assert result.debt_after == 600
    assert result.home_uft_locked == result.wrapped_uft_supply == 600
    assert result.lender_home_uft_received == 400
    assert result.collateral_locked
    assert not result.collateral_released
    assert result.backing_exact


@pytest.mark.parametrize(
    "scenario",
    (
        CrossChainScenario.PRE_FINALITY_REORG,
        CrossChainScenario.TIMEOUT_BEFORE_EXECUTION,
    ),
)
def test_unexecuted_message_tombstones_before_source_compensation(
    scenario: CrossChainScenario,
) -> None:
    result = simulate_cross_chain_loan(
        units=1_000, debt_before=1_000, scenario=scenario
    )

    assert result.destination_tombstoned
    assert result.source_compensated
    assert result.outcome == CrossChainOutcome.RECOVERED
    assert result.debt_after == result.debt_before
    assert result.execution_count == 0
    assert result.recovery_count == 1
    assert result.event_trace.index("destination.tombstoned") < result.event_trace.index(
        "source.compensated"
    )
    assert result.backing_exact
    assert result.safely_terminal


def test_timeout_execution_race_never_executes_and_compensates() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.TIMEOUT_EXECUTION_RACE,
    )

    assert "destination.tombstone.rejected.executed" in result.event_trace
    assert "source.compensation.rejected" in result.event_trace
    assert result.execution_count == 1
    assert result.recovery_count == 0
    assert result.outcome == CrossChainOutcome.CLOSED


@pytest.mark.parametrize(
    "scenario",
    (
        CrossChainScenario.SIGNER_COMPROMISE,
        CrossChainScenario.RELAYER_FABRICATION,
    ),
)
def test_fabricated_authority_is_visible_and_cannot_execute(
    scenario: CrossChainScenario,
) -> None:
    result = simulate_cross_chain_loan(
        units=1_000, debt_before=1_000, scenario=scenario
    )

    assert result.outcome == CrossChainOutcome.DISPUTED
    assert result.route_paused
    assert result.incident_opened
    assert result.accepted_finality_certificates == 0
    assert result.execution_count == 0
    assert result.debt_after == result.debt_before
    assert result.wrapped_uft_supply == 0
    assert not result.collateral_released


def test_deep_finality_reorg_freezes_without_second_value_movement() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.DEEP_FINALITY_REORG,
    )

    assert result.outcome == CrossChainOutcome.DISPUTED
    assert result.route_paused
    assert result.incident_opened
    assert result.execution_count == 1
    assert result.home_uft_locked == result.wrapped_uft_supply == 1_000
    assert result.debt_after == result.debt_before
    assert result.recovery_count == 0
    assert not result.source_compensated


def test_backing_impairment_pauses_route_and_exposes_exact_difference() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.BACKING_IMPAIRMENT,
    )

    assert result.outcome == CrossChainOutcome.DISPUTED
    assert result.reconciliation_difference == -100
    assert not result.backing_exact
    assert result.route_paused
    assert result.lender_home_uft_received == 0
    assert not result.collateral_released


def test_direct_home_repayment_closes_without_mutating_bridge_backing() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        scenario=CrossChainScenario.DIRECT_HOME_REPAYMENT,
    )

    assert result.outcome == CrossChainOutcome.CLOSED
    assert result.debt_after == 0
    assert result.home_uft_locked == result.wrapped_uft_supply == 1_000
    assert result.lender_home_uft_received == 1_000
    assert result.collateral_released
    assert result.backing_exact


def test_partial_direct_home_repayment_preserves_full_bridge_backing() -> None:
    result = simulate_cross_chain_loan(
        units=1_000,
        debt_before=1_000,
        repayment_units=400,
        scenario=CrossChainScenario.DIRECT_HOME_REPAYMENT,
    )

    assert result.outcome == CrossChainOutcome.ACTIVE
    assert result.debt_after == 600
    assert result.home_uft_locked == result.wrapped_uft_supply == 1_000
    assert result.lender_home_uft_received == 400
    assert result.collateral_locked
    assert not result.collateral_released


def test_bounded_repayment_sequences_preserve_debt_and_backing_conservation() -> None:
    for units in (1, 2, 3, 7, 31, 255, 1_000, 65_535):
        for repayment in sorted({1, units, max(1, units // 2), max(1, units - 1)}):
            result = simulate_cross_chain_loan(
                units=units,
                debt_before=units,
                repayment_units=repayment,
            )

            assert result.debt_after == units - repayment
            assert result.home_uft_locked == result.wrapped_uft_supply
            assert result.home_uft_locked == units - repayment
            assert result.lender_home_uft_received == repayment
            assert result.execution_count == result.acknowledgement_count == 1
            assert not (result.execution_count and result.source_compensated)
            assert result.ledger_balanced


@pytest.mark.parametrize(
    ("units", "debt", "repayment"),
    (
        (0, 1_000, None),
        (-1, 1_000, None),
        (1_000, 0, None),
        (999, 1_000, None),
        (1_000, 1_000, 0),
        (1_000, 1_000, 1_001),
    ),
)
def test_invalid_local_product_is_rejected(
    units: int,
    debt: int,
    repayment: int | None,
) -> None:
    with pytest.raises(ValueError):
        simulate_cross_chain_loan(
            units=units,
            debt_before=debt,
            repayment_units=repayment,
        )
