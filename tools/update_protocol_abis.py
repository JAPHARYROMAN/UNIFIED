"""Create reviewed protocol ABI snapshots after an intentional interface review."""

from __future__ import annotations

import argparse
import json

from check_abi import ABI_PAIRS


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--phase",
        help="update only snapshots whose parent directory has this name (for example phase9)",
    )
    args = parser.parse_args()

    selected = [
        (contract, compiled_path, baseline_path)
        for contract, (compiled_path, baseline_path) in ABI_PAIRS.items()
        if contract != "FoundationProbe"
        and (args.phase is None or baseline_path.parent.name == args.phase)
    ]
    if not selected:
        raise SystemExit(f"No ABI snapshots matched phase {args.phase!r}.")

    for contract, compiled_path, baseline_path in selected:
        if not compiled_path.is_file():
            raise SystemExit(f"{contract}: compile Solidity before updating ABI snapshots")
        payload = json.loads(compiled_path.read_text(encoding="utf-8"))
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    print(f"Protocol ABI snapshots updated ({len(selected)} contracts).")


if __name__ == "__main__":
    main()
