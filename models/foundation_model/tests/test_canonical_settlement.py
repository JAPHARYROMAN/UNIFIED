import pytest
from unified_foundation.canonical_settlement import (
    CanonicalSettlementOutcome,
    CanonicalSettlementReorgKind,
    simulate_canonical_settlement,
)


def test_one_to_one_excess_settlement_conserves_every_unit() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_250,
        target_units=1_250,
        debt_before=1_000,
    )

    assert result.outcome == CanonicalSettlementOutcome.CONFIRMED
    assert result.principal == 1_000
    assert result.refundable_excess == 250
    assert result.debt_after == 0
    assert result.principal + result.refundable_excess == 1_250
    assert result.lender_payout + result.borrower_refund == 1_250
    assert result.source_provider_asset == 0
    assert result.source_unallocated == 0
    assert result.target_custody == 0
    assert result.target_unallocated == 0
    assert result.posted_journals == 8


def test_partial_settlement_posts_no_refund_journal() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=400,
        target_units=400,
        debt_before=1_000,
    )

    assert result.principal == 400
    assert result.refundable_excess == 0
    assert result.debt_after == 600
    assert result.posted_journals == 7


@pytest.mark.parametrize(
    ("mature", "matched", "phase7b", "target_units"),
    (
        (False, True, False, 1_000),
        (True, False, False, 1_000),
        (True, True, True, 1_000),
        (True, True, False, 999),
    ),
)
def test_premature_mismatched_or_double_allocation_is_ineligible(
    mature: bool,
    matched: bool,
    phase7b: bool,
    target_units: int,
) -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=target_units,
        debt_before=1_000,
        mature=mature,
        reconciliation_matched=matched,
        phase7b_allocated=phase7b,
    )

    assert result.outcome == CanonicalSettlementOutcome.INELIGIBLE
    assert result.debt_after == result.debt_before
    assert result.lender_payout == 0
    assert result.borrower_refund == 0
    assert result.posted_journals == 0


def test_gateway_failure_and_unfinalized_chain_create_no_accounting() -> None:
    failed = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=1_000,
        debt_before=1_000,
        gateway_succeeds=False,
    )
    submitted = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=1_000,
        debt_before=1_000,
        chain_final=False,
    )

    assert failed.outcome == CanonicalSettlementOutcome.FAILED
    assert submitted.outcome == CanonicalSettlementOutcome.SUBMITTED
    assert failed.posted_journals == submitted.posted_journals == 0
    assert failed.debt_after == submitted.debt_after == 1_000


def test_ledger_outage_never_retries_or_undoes_canonical_execution() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=1_000,
        debt_before=1_000,
        ledger_available=False,
    )

    assert result.outcome == CanonicalSettlementOutcome.CONFIRMED
    assert result.debt_after == 0
    assert result.lender_payout == 1_000
    assert result.posted_journals == 0
    assert result.accounting_pending


def test_deep_reorg_restores_phase7a_source_and_compensates_whole_batch() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_250,
        target_units=1_250,
        debt_before=1_000,
        deep_reorg_after_post=True,
    )

    assert result.outcome == CanonicalSettlementOutcome.REORG_COMPENSATED
    assert result.source_provider_asset == 1_250
    assert result.source_unallocated == 1_250
    assert result.debt_after == result.debt_before
    assert result.lender_payout == 0
    assert result.borrower_refund == 0
    assert result.posted_journals == result.reversal_journals == 8
    assert result.reorg_kind == CanonicalSettlementReorgKind.DEEP
    assert result.compensation_required


def test_shallow_reorg_removes_provisional_evidence_without_compensation() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=1_000,
        debt_before=1_000,
        shallow_reorg_before_finality=True,
    )

    assert result.outcome == CanonicalSettlementOutcome.SHALLOW_REORG
    assert result.reorg_kind == CanonicalSettlementReorgKind.SHALLOW
    assert not result.compensation_required
    assert result.posted_journals == result.reversal_journals == 0
    assert result.incident_count == 0


def test_late_provider_contradiction_is_incident_only() -> None:
    result = simulate_canonical_settlement(
        source_asset_id="fiat-usd",
        target_asset_id="usdc-mainnet",
        source_units=1_000,
        target_units=1_000,
        debt_before=1_000,
        contradictory_provider_event=True,
    )

    assert result.outcome == CanonicalSettlementOutcome.INCIDENT
    assert result.incident_count == 1
    assert result.debt_after == 0
    assert result.lender_payout == 1_000
    assert result.reversal_journals == 0


def test_same_asset_identity_is_not_a_conversion() -> None:
    with pytest.raises(ValueError):
        simulate_canonical_settlement(
            source_asset_id="usdc-mainnet",
            target_asset_id="usdc-mainnet",
            source_units=1_000,
            target_units=1_000,
            debt_before=1_000,
        )
