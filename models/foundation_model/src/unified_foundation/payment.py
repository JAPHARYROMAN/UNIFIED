"""Synthetic Phase 7A callback-delivery and reconciliation fault model."""

from dataclasses import dataclass
from enum import StrEnum


class PaymentStatus(StrEnum):
    CREATED = "CREATED"
    PROCESSING = "PROCESSING"
    PROVISIONAL = "PROVISIONAL"
    FINAL = "FINAL"
    FAILED = "FAILED"
    REVERSED = "REVERSED"


@dataclass(frozen=True)
class Callback:
    event_id: str
    status: PaymentStatus
    units: int
    authenticated: bool = True
    unexpired: bool = True


@dataclass(frozen=True)
class SimulationResult:
    status: PaymentStatus
    raw_ingress_count: int
    economic_effect_count: int
    provisional_units: int
    final_units: int
    quarantine_count: int
    replay_count: int
    outage_count: int
    reconciliation_difference: int


def simulate_callback_delivery(
    *,
    payment_units: int,
    callbacks: tuple[Callback, ...],
    statement_units: int,
    fail_once_event_ids: frozenset[str] = frozenset(),
) -> SimulationResult:
    """Apply at-least-once synthetic callbacks while conserving economic effects."""
    if payment_units <= 0 or statement_units < 0:
        raise ValueError("invalid payment simulation")

    status = PaymentStatus.CREATED
    raw_ingress_count = 0
    economic_effect_count = 0
    provisional_units = 0
    final_units = 0
    quarantine_count = 0
    replay_count = 0
    outage_count = 0
    seen: dict[str, Callback] = {}
    failed_once: set[str] = set()

    for callback in callbacks:
        raw_ingress_count += 1
        if not callback.event_id or callback.units <= 0:
            raise ValueError("invalid callback")
        if not callback.authenticated or not callback.unexpired:
            quarantine_count += 1
            continue
        if callback.units != payment_units:
            quarantine_count += 1
            continue
        if callback.event_id in seen:
            if seen[callback.event_id] == callback:
                replay_count += 1
            else:
                quarantine_count += 1
            continue
        if (
            callback.event_id in fail_once_event_ids
            and callback.event_id not in failed_once
        ):
            failed_once.add(callback.event_id)
            outage_count += 1
            continue
        if not _allowed(status, callback.status):
            quarantine_count += 1
            continue

        previous = status
        status = callback.status
        seen[callback.event_id] = callback
        if status == PaymentStatus.PROVISIONAL:
            provisional_units = payment_units
            economic_effect_count += 1
        elif status == PaymentStatus.FINAL:
            provisional_units = 0
            final_units = payment_units
            economic_effect_count += 1
        elif status == PaymentStatus.REVERSED:
            if previous == PaymentStatus.PROVISIONAL:
                provisional_units = 0
                economic_effect_count += 1
            else:
                final_units = 0
                economic_effect_count += 2

    if provisional_units < 0 or final_units < 0:
        raise AssertionError("payment units became negative")
    return SimulationResult(
        status=status,
        raw_ingress_count=raw_ingress_count,
        economic_effect_count=economic_effect_count,
        provisional_units=provisional_units,
        final_units=final_units,
        quarantine_count=quarantine_count,
        replay_count=replay_count,
        outage_count=outage_count,
        reconciliation_difference=statement_units - final_units,
    )


def _allowed(current: PaymentStatus, target: PaymentStatus) -> bool:
    return (
        (
            current == PaymentStatus.CREATED
            and target in (PaymentStatus.PROCESSING, PaymentStatus.FAILED)
        )
        or (
            current == PaymentStatus.PROCESSING
            and target in (PaymentStatus.PROVISIONAL, PaymentStatus.FAILED)
        )
        or (
            current == PaymentStatus.PROVISIONAL
            and target in (PaymentStatus.FINAL, PaymentStatus.REVERSED)
        )
        or (current == PaymentStatus.FINAL and target == PaymentStatus.REVERSED)
    )


@dataclass(frozen=True)
class AllocationResult:
    debt_before: int
    principal: int
    refundable_excess: int
    debt_after: int
    reversed_debt: int
    journal_count: int


def simulate_final_allocation(
    *,
    payment_units: int,
    outstanding_principal: int,
    final: bool,
    reconciliation_matched: bool,
    reverse: bool = False,
    accounting_failure: bool = False,
) -> AllocationResult:
    """Conserve a principal-only allocation or return untouched state on failure."""
    if payment_units <= 0 or outstanding_principal <= 0:
        raise ValueError("invalid allocation simulation")
    if not final or not reconciliation_matched or accounting_failure:
        return AllocationResult(
            debt_before=outstanding_principal,
            principal=0,
            refundable_excess=0,
            debt_after=outstanding_principal,
            reversed_debt=outstanding_principal,
            journal_count=0,
        )
    principal = min(payment_units, outstanding_principal)
    excess = payment_units - principal
    debt_after = outstanding_principal - principal
    return AllocationResult(
        debt_before=outstanding_principal,
        principal=principal,
        refundable_excess=excess,
        debt_after=debt_after,
        reversed_debt=outstanding_principal if reverse else debt_after,
        journal_count=4 if reverse else 2,
    )
