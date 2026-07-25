"""Write reviewed Phase 9 storage snapshots from deterministic compiler output."""

from __future__ import annotations

import json

from check_phase9_storage_layouts import (
    PHASE9_CONTRACTS,
    SNAPSHOT_ROOT,
    load_actual_layouts,
)


def main() -> None:
    layouts = load_actual_layouts()
    SNAPSHOT_ROOT.mkdir(parents=True, exist_ok=True)
    for contract in PHASE9_CONTRACTS:
        path = SNAPSHOT_ROOT / f"{contract}.storage.json"
        path.write_text(
            json.dumps(layouts[contract], ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    print(f"Phase 9 storage-layout snapshots updated ({len(PHASE9_CONTRACTS)} contracts).")


if __name__ == "__main__":
    main()
