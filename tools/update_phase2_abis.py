"""Create reviewed Phase 2 ABI snapshots after an intentional interface review."""

from __future__ import annotations

import json

from check_abi import ABI_PAIRS


def main() -> None:
    for contract, (compiled_path, baseline_path) in ABI_PAIRS.items():
        if contract == "FoundationProbe":
            continue
        if not compiled_path.is_file():
            raise SystemExit(f"{contract}: compile Solidity before updating ABI snapshots")
        payload = json.loads(compiled_path.read_text(encoding="utf-8"))
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    print("Phase 2 ABI snapshots updated.")


if __name__ == "__main__":
    main()
