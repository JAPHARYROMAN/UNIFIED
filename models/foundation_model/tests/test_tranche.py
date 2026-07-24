import pytest
from unified_foundation.tranche import (
    TrancheBalance,
    junior_first_loss,
    senior_first_distribution,
)

TRANCHES = (
    TrancheBalance("senior", 1, 60),
    TrancheBalance("mezzanine", 2, 25),
    TrancheBalance("junior", 3, 15),
)


@pytest.mark.parametrize("amount", [0, 1, 15, 60, 61, 99, 100])
def test_waterfalls_conserve_every_boundary_amount(amount: int) -> None:
    distribution = senior_first_distribution(TRANCHES, amount)
    loss = junior_first_loss(TRANCHES, amount)
    assert sum(distribution.values()) == amount
    assert sum(loss.values()) == amount


def test_priority_directions_are_opposite_and_deterministic() -> None:
    assert senior_first_distribution(TRANCHES, 70) == {
        "senior": 60,
        "mezzanine": 10,
        "junior": 0,
    }
    assert junior_first_loss(TRANCHES, 70) == {
        "senior": 30,
        "mezzanine": 25,
        "junior": 15,
    }


def test_invalid_waterfall_inputs_are_rejected() -> None:
    with pytest.raises(ValueError, match="exceeds"):
        junior_first_loss(TRANCHES, 101)
    with pytest.raises(ValueError, match="unique"):
        senior_first_distribution(
            (TrancheBalance("a", 1, 1), TrancheBalance("b", 1, 1)), 1
        )
