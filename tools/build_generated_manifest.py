"""Build a deterministic manifest for checked-in generated artifacts."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATED_ROOTS = [
    ROOT / "packages" / "generated" / "go",
    ROOT / "packages" / "generated" / "typescript",
    ROOT / "packages" / "generated" / "python",
    ROOT / "protocol" / "src" / "generated",
]
OUTPUT = ROOT / "packages" / "generated" / "manifest.json"


def main() -> None:
    records: list[dict[str, str]] = []
    for generated_root in GENERATED_ROOTS:
        if not generated_root.exists():
            continue
        for path in sorted(item for item in generated_root.rglob("*") if item.is_file()):
            if "__pycache__" in path.parts:
                continue
            records.append(
                {
                    "path": path.relative_to(ROOT).as_posix(),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                }
            )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps({"version": 1, "files": records}, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


if __name__ == "__main__":
    main()

