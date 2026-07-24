"""Reject privileged Solidity surfaces from the foundation milestone."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "protocol" / "src"
FORBIDDEN = {
    r"\bfunction\s+mint\s*\(": "UFT or asset mint path",
    r"\bselfdestruct\s*\(": "selfdestruct",
    r"\bdelegatecall\s*\(": "delegatecall",
    r"\btx\.origin\b": "tx.origin authorization",
}


def main() -> None:
    failures: list[str] = []
    for path in SOURCE_ROOT.rglob("*.sol"):
        source = path.read_text(encoding="utf-8")
        for pattern, label in FORBIDDEN.items():
            if re.search(pattern, source, flags=re.IGNORECASE):
                failures.append(f"{path.relative_to(ROOT)}: forbidden {label}")
    if failures:
        raise SystemExit("\n".join(failures))
    print("Privileged Solidity surface check passed.")


if __name__ == "__main__":
    main()

