"""Exact money reference behavior matching ADR 0003."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Money:
    asset_id: str
    units: int

    def __post_init__(self) -> None:
        if not self.asset_id:
            raise ValueError("asset_id is required")

    def add(self, other: Money) -> Money:
        if self.asset_id != other.asset_id:
            raise ValueError("cannot add different assets")
        return Money(asset_id=self.asset_id, units=self.units + other.units)

