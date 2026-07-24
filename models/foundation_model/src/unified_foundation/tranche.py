"""Deterministic principal and loss waterfalls for bounded tranche simulations."""

from dataclasses import dataclass


@dataclass(frozen=True)
class TrancheBalance:
    tranche_id: str
    seniority_rank: int
    outstanding_units: int

    def __post_init__(self) -> None:
        if not self.tranche_id or self.seniority_rank <= 0 or self.outstanding_units < 0:
            raise ValueError("invalid tranche balance")


def senior_first_distribution(
    tranches: tuple[TrancheBalance, ...], amount: int
) -> dict[str, int]:
    """Allocate a finalized principal payment from most senior to most junior."""
    return _allocate(tranches, amount, reverse=False)


def junior_first_loss(
    tranches: tuple[TrancheBalance, ...], amount: int
) -> dict[str, int]:
    """Preview contractual loss absorption from most junior to most senior."""
    return _allocate(tranches, amount, reverse=True)


def _allocate(
    tranches: tuple[TrancheBalance, ...], amount: int, *, reverse: bool
) -> dict[str, int]:
    if amount < 0:
        raise ValueError("amount cannot be negative")
    ranks = [tranche.seniority_rank for tranche in tranches]
    if len(set(ranks)) != len(ranks):
        raise ValueError("seniority ranks must be unique")
    total = sum(tranche.outstanding_units for tranche in tranches)
    if amount > total:
        raise ValueError("amount exceeds outstanding rights")
    ordered = sorted(tranches, key=lambda tranche: tranche.seniority_rank, reverse=reverse)
    remaining = amount
    allocations = {tranche.tranche_id: 0 for tranche in tranches}
    for tranche in ordered:
        allocation = min(remaining, tranche.outstanding_units)
        allocations[tranche.tranche_id] = allocation
        remaining -= allocation
    if remaining:
        raise AssertionError("waterfall did not conserve amount")
    return allocations
