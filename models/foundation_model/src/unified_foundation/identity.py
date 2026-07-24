"""Synthetic identity, exposure, and atomic-activation simulations for Phase 6."""

from dataclasses import dataclass, replace
from enum import StrEnum


class ExposureStatus(StrEnum):
    RESERVED = "RESERVED"
    ACTIVE = "ACTIVE"
    RELEASED = "RELEASED"
    CANCELLED = "CANCELLED"


@dataclass
class ExposureReservation:
    loan_id: str
    decision_id: str
    subject_commitment: str
    account_id: str
    asset_id: str
    amount: int
    expires_at: int
    status: ExposureStatus = ExposureStatus.RESERVED


class ExposureBook:
    """Conservatively aggregate reservations by opaque subject commitment and asset."""

    def __init__(self) -> None:
        self._reservations: dict[str, ExposureReservation] = {}
        self._reserved: dict[tuple[str, str], int] = {}
        self._active: dict[tuple[str, str], int] = {}

    def reserve(
        self,
        *,
        loan_id: str,
        decision_id: str,
        subject_commitment: str,
        account_id: str,
        asset_id: str,
        amount: int,
        decision_limit: int,
        expires_at: int,
        now: int,
    ) -> ExposureReservation:
        if (
            not loan_id
            or not decision_id
            or not subject_commitment
            or not account_id
            or not asset_id
            or amount <= 0
            or decision_limit <= 0
            or expires_at <= now
            or loan_id in self._reservations
        ):
            raise ValueError("invalid exposure reservation")
        key = (subject_commitment, asset_id)
        if self.recognized(subject_commitment, asset_id) + amount > decision_limit:
            raise ValueError("decision exposure limit exceeded")
        reservation = ExposureReservation(
            loan_id=loan_id,
            decision_id=decision_id,
            subject_commitment=subject_commitment,
            account_id=account_id,
            asset_id=asset_id,
            amount=amount,
            expires_at=expires_at,
        )
        self._reservations[loan_id] = reservation
        self._reserved[key] = self._reserved.get(key, 0) + amount
        return reservation

    def activate(self, loan_id: str, *, now: int) -> None:
        reservation = self._reservation(loan_id)
        if reservation.status is not ExposureStatus.RESERVED or now >= reservation.expires_at:
            raise ValueError("reservation cannot activate")
        key = (reservation.subject_commitment, reservation.asset_id)
        self._reserved[key] -= reservation.amount
        self._active[key] = self._active.get(key, 0) + reservation.amount
        reservation.status = ExposureStatus.ACTIVE

    def cancel_expired(self, loan_id: str, *, now: int) -> None:
        reservation = self._reservation(loan_id)
        if reservation.status is not ExposureStatus.RESERVED or now < reservation.expires_at:
            raise ValueError("reservation cannot cancel")
        key = (reservation.subject_commitment, reservation.asset_id)
        self._reserved[key] -= reservation.amount
        reservation.status = ExposureStatus.CANCELLED

    def release(self, loan_id: str, *, terminal: bool, outstanding: int) -> None:
        reservation = self._reservation(loan_id)
        if (
            reservation.status is not ExposureStatus.ACTIVE
            or not terminal
            or outstanding != 0
        ):
            raise ValueError("active exposure cannot release")
        key = (reservation.subject_commitment, reservation.asset_id)
        self._active[key] -= reservation.amount
        reservation.status = ExposureStatus.RELEASED

    def totals(self, subject_commitment: str, asset_id: str) -> tuple[int, int]:
        key = (subject_commitment, asset_id)
        return self._reserved.get(key, 0), self._active.get(key, 0)

    def recognized(self, subject_commitment: str, asset_id: str) -> int:
        reserved, active = self.totals(subject_commitment, asset_id)
        return reserved + active

    def _reservation(self, loan_id: str) -> ExposureReservation:
        try:
            return self._reservations[loan_id]
        except KeyError as error:
            raise ValueError("unknown exposure reservation") from error


def scoped_uniqueness_key(
    provider_id: str, scope_id: str, epoch: int, subject_commitment: str
) -> tuple[str, str, int, str]:
    """Represent only the provider/scope/epoch uniqueness actually attested."""
    if not provider_id or not scope_id or epoch <= 0 or not subject_commitment:
        raise ValueError("invalid scoped uniqueness evidence")
    return provider_id, scope_id, epoch, subject_commitment


@dataclass(frozen=True)
class AtomicActivationState:
    """Synthetic Phase 6B state used to prove all-or-nothing activation."""

    reserved: int
    active: int
    loan_registered: bool
    offer_consumed: bool
    tender_fulfilled: bool
    funding_units: int
    lender_units: int
    borrower_units: int
    fee_units: int


ACTIVATION_STEPS = (
    "reserve",
    "consume_offer",
    "register_loan",
    "fund",
    "activate",
    "fulfill_tender",
)


def simulate_atomic_activation(
    initial: AtomicActivationState,
    *,
    principal: int,
    fee: int,
    fail_at: str | None = None,
) -> AtomicActivationState:
    """Return the committed state, or the exact initial state on a synthetic revert."""
    if (
        principal <= 0
        or fee < 0
        or fee >= principal
        or initial.loan_registered
        or initial.offer_consumed
        or initial.tender_fulfilled
        or initial.funding_units != 0
        or fail_at not in (*ACTIVATION_STEPS, None)
    ):
        raise ValueError("invalid atomic activation")

    staged = replace(initial, reserved=initial.reserved + principal)
    if fail_at == "reserve":
        return initial
    staged = replace(staged, offer_consumed=True)
    if fail_at == "consume_offer":
        return initial
    staged = replace(staged, loan_registered=True)
    if fail_at == "register_loan":
        return initial
    if initial.lender_units < principal:
        return initial
    staged = replace(
        staged,
        funding_units=principal,
        lender_units=initial.lender_units - principal,
        borrower_units=initial.borrower_units + principal - fee,
        fee_units=initial.fee_units + fee,
    )
    if fail_at == "fund":
        return initial
    staged = replace(
        staged,
        reserved=staged.reserved - principal,
        active=staged.active + principal,
    )
    if fail_at == "activate":
        return initial
    staged = replace(staged, tender_fulfilled=True)
    if fail_at == "fulfill_tender":
        return initial
    return staged
