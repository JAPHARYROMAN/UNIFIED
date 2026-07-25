"""Protect the immutable Phase 9 storage freeze from accidental regeneration."""

from __future__ import annotations


def main() -> None:
    raise SystemExit(
        "Phase 9 storage snapshots are the immutable freeze baseline; add a reviewed "
        "implementation checkpoint instead."
    )


if __name__ == "__main__":
    main()
