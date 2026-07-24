"""Extract the formal invariant catalog for repository traceability."""

from __future__ import annotations

import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "docs"
    / "specifications"
    / "Unified_Protocol_Invariants_and_Formal_Verification_Specification_v0.1.md"
)
OUTPUT = ROOT / "security" / "invariant-catalog.csv"
PATTERN = re.compile(r"^###\s+((?:INV|LIVE|REC)-[A-Z]+-\d{3}|REC-\d{3})\s+—\s+(.+?)\s*$")


def main() -> None:
    records: list[tuple[str, str, int]] = []
    seen: set[str] = set()
    for line_number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), 1):
        match = PATTERN.match(line)
        if not match:
            continue
        identifier, title = match.groups()
        if identifier in seen:
            raise SystemExit(f"Duplicate invariant identifier: {identifier}")
        seen.add(identifier)
        records.append((identifier, title, line_number))
    if len(records) < 100:
        raise SystemExit(f"Expected at least 100 formal properties, found {len(records)}")
    with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["id", "title", "source", "line"])
        for identifier, title, line_number in records:
            writer.writerow(
                [
                    identifier,
                    title,
                    SOURCE.relative_to(ROOT).as_posix(),
                    line_number,
                ]
            )


if __name__ == "__main__":
    main()

