import pytest
from unified_foundation import Money


def test_exact_addition() -> None:
    total = Money("asset:local:usd", 700).add(Money("asset:local:usd", 300))
    assert total.units == 1000


def test_cross_asset_addition_is_rejected() -> None:
    with pytest.raises(ValueError, match="different assets"):
        Money("asset:local:usd", 1).add(Money("asset:local:uft", 1))
