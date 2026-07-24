"""Synthetic Phase 7C mature canonical-settlement conservation model."""

from dataclasses import dataclass
from enum import StrEnum


class CanonicalSettlementOutcome(StrEnum):
    INELIGIBLE = "INELIGIBLE"
    FAILED = "FAILED"
    SUBMITTED = "SUBMITTED"
    CONFIRMED = "CONFIRMED"
    INCIDENT = "INCIDENT"
    SHALLOW_REORG = "SHALLOW_REORG"
    REORG_COMPENSATED = "REORG_COMPENSATED"


class CanonicalSettlementReorgKind(StrEnum):
    NONE = "NONE"
    SHALLOW = "SHALLOW"
    DEEP = "DEEP"


@dataclass(frozen=True)
class CanonicalSettlementResult:
    outcome: CanonicalSettlementOutcome
    eligible: bool
    source_provider_asset: int
    source_unallocated: int
    target_custody: int
    target_unallocated: int
    debt_before: int
    principal: int
    refundable_excess: int
    debt_after: int
    lender_payout: int
    borrower_refund: int
    posted_journals: int
    reversal_journals: int
    incident_count: int
    accounting_pending: bool
    reorg_kind: CanonicalSettlementReorgKind = CanonicalSettlementReorgKind.NONE
    compensation_required: bool = False


def simulate_canonical_settlement(
    *,
    source_asset_id: str,
    target_asset_id: str,
    source_units: int,
    target_units: int,
    debt_before: int,
    mature: bool = True,
    reconciliation_matched: bool = True,
    phase7b_allocated: bool = False,
    gateway_succeeds: bool = True,
    chain_final: bool = True,
    ledger_available: bool = True,
    shallow_reorg_before_finality: bool = False,
    deep_reorg_after_post: bool = False,
    contradictory_provider_event: bool = False,
) -> CanonicalSettlementResult:
    """Model one exact, fee-free conversion and canonical repayment.

    Provider and token assets remain distinct identities. Phase 7C accepts only an
    exact one-to-one unit conversion after provider reversal risk has matured.
    """
    if (
        not source_asset_id
        or not target_asset_id
        or source_asset_id == target_asset_id
        or source_units <= 0
        or target_units <= 0
        or debt_before <= 0
        or (shallow_reorg_before_finality and deep_reorg_after_post)
    ):
        raise ValueError("invalid canonical settlement simulation")

    eligible = (
        mature
        and reconciliation_matched
        and not phase7b_allocated
        and source_units == target_units
    )
    if not eligible:
        return _unchanged(
            CanonicalSettlementOutcome.INELIGIBLE,
            debt_before,
            source_units,
        )
    if not gateway_succeeds:
        return _unchanged(
            CanonicalSettlementOutcome.FAILED,
            debt_before,
            source_units,
            eligible=True,
        )
    if shallow_reorg_before_finality:
        return _unchanged(
            CanonicalSettlementOutcome.SHALLOW_REORG,
            debt_before,
            source_units,
            eligible=True,
            reorg_kind=CanonicalSettlementReorgKind.SHALLOW,
        )

    principal = min(target_units, debt_before)
    excess = target_units - principal
    debt_after = debt_before - principal
    if not chain_final:
        return CanonicalSettlementResult(
            outcome=CanonicalSettlementOutcome.SUBMITTED,
            eligible=True,
            source_provider_asset=source_units,
            source_unallocated=source_units,
            target_custody=0,
            target_unallocated=0,
            debt_before=debt_before,
            principal=0,
            refundable_excess=0,
            debt_after=debt_before,
            lender_payout=0,
            borrower_refund=0,
            posted_journals=0,
            reversal_journals=0,
            incident_count=0,
            accounting_pending=False,
        )
    if not ledger_available:
        return CanonicalSettlementResult(
            outcome=CanonicalSettlementOutcome.CONFIRMED,
            eligible=True,
            source_provider_asset=source_units,
            source_unallocated=source_units,
            target_custody=0,
            target_unallocated=0,
            debt_before=debt_before,
            principal=principal,
            refundable_excess=excess,
            debt_after=debt_after,
            lender_payout=principal,
            borrower_refund=excess,
            posted_journals=0,
            reversal_journals=0,
            incident_count=0,
            accounting_pending=True,
        )

    journal_count = 8 if excess else 7
    if deep_reorg_after_post:
        return CanonicalSettlementResult(
            outcome=CanonicalSettlementOutcome.REORG_COMPENSATED,
            eligible=True,
            source_provider_asset=source_units,
            source_unallocated=source_units,
            target_custody=0,
            target_unallocated=0,
            debt_before=debt_before,
            principal=0,
            refundable_excess=0,
            debt_after=debt_before,
            lender_payout=0,
            borrower_refund=0,
            posted_journals=journal_count,
            reversal_journals=journal_count,
            incident_count=1,
            accounting_pending=False,
            reorg_kind=CanonicalSettlementReorgKind.DEEP,
            compensation_required=True,
        )

    outcome = (
        CanonicalSettlementOutcome.INCIDENT
        if contradictory_provider_event
        else CanonicalSettlementOutcome.CONFIRMED
    )
    return CanonicalSettlementResult(
        outcome=outcome,
        eligible=True,
        source_provider_asset=0,
        source_unallocated=0,
        target_custody=0,
        target_unallocated=0,
        debt_before=debt_before,
        principal=principal,
        refundable_excess=excess,
        debt_after=debt_after,
        lender_payout=principal,
        borrower_refund=excess,
        posted_journals=journal_count,
        reversal_journals=0,
        incident_count=1 if contradictory_provider_event else 0,
        accounting_pending=False,
    )


def _unchanged(
    outcome: CanonicalSettlementOutcome,
    debt_before: int,
    source_units: int,
    *,
    eligible: bool = False,
    reorg_kind: CanonicalSettlementReorgKind = CanonicalSettlementReorgKind.NONE,
) -> CanonicalSettlementResult:
    return CanonicalSettlementResult(
        outcome=outcome,
        eligible=eligible,
        source_provider_asset=source_units,
        source_unallocated=source_units,
        target_custody=0,
        target_unallocated=0,
        debt_before=debt_before,
        principal=0,
        refundable_excess=0,
        debt_after=debt_before,
        lender_payout=0,
        borrower_refund=0,
        posted_journals=0,
        reversal_journals=0,
        incident_count=0,
        accounting_pending=False,
        reorg_kind=reorg_kind,
        compensation_required=False,
    )
