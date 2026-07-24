"""Compare the compiled foundation ABI with its reviewed snapshot."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPILED = ROOT / ".cache" / "solc" / "protocol_src_FoundationProbe_sol_FoundationProbe.abi"
BASELINE = ROOT / "protocol" / "abi" / "FoundationProbe.abi.json"


def main() -> None:
    if not COMPILED.is_file():
        raise SystemExit("compiled FoundationProbe ABI is missing")
    compiled = json.loads(COMPILED.read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    if compiled != baseline:
        raise SystemExit(
            "FoundationProbe ABI changed. Review compatibility and update "
            "the snapshot through an ADR."
        )
    print("Foundation ABI compatibility check passed.")


if __name__ == "__main__":
    main()
