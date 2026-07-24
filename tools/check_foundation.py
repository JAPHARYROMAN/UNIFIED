"""Repository-level foundation conformance checks."""

from __future__ import annotations

import csv
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "docs" / "specifications" / "registry.yaml"
SPEC_ROOTS = [ROOT / "constitution", ROOT / "docs" / "specifications"]
REQUIRED_DIRS = [
    "constitution",
    "docs",
    "adr",
    "rfcs",
    "protocol",
    "services",
    "apps",
    "packages",
    "schemas",
    "models",
    "infrastructure",
    "deployments",
    "operations",
    "security",
    "simulations",
    "tests",
    "scripts",
    "tools",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def check_structure() -> None:
    missing = [path for path in REQUIRED_DIRS if not (ROOT / path).is_dir()]
    if missing:
        fail(f"missing required directories: {', '.join(missing)}")


def registry_records() -> list[tuple[str, str]]:
    if not REGISTRY.is_file():
        fail("specification registry is missing")
    text = REGISTRY.read_text(encoding="utf-8")
    records = re.findall(
        r"path:\s+'([^']+)'\n\s+version:.*?\n\s+sha256:\s+([0-9a-f]{64})",
        text,
        flags=re.DOTALL,
    )
    if len(records) != 12:
        fail(f"registry must contain 12 specifications, found {len(records)}")
    return records


def check_registry_hashes() -> None:
    for relative, expected in registry_records():
        path = ROOT / relative
        if not path.is_file():
            fail(f"registered specification does not exist: {relative}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            fail(f"specification hash mismatch: {relative}")


def check_cross_references() -> None:
    markdown = [
        path
        for root in SPEC_ROOTS
        for path in root.glob("*.md")
        if path.name != "README.md"
    ]
    if len(markdown) != 12:
        fail(f"expected 12 canonical Markdown specifications, found {len(markdown)}")
    combined = "\n".join(path.read_text(encoding="utf-8") for path in markdown)
    stale = [
        "All eleven governing documents are indexed",
        "`FINANCIAL_ACCOUNTING_SPEC.md`",
        "The next security foundation is the **Unified Protocol Invariants",
    ]
    for phrase in stale:
        if phrase in combined:
            fail(f"stale specification reference remains: {phrase}")


def check_invariants() -> None:
    catalog = ROOT / "security" / "invariant-catalog.csv"
    if not catalog.is_file():
        fail("invariant catalog is missing")
    with catalog.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    identifiers = [row["id"] for row in rows]
    if len(identifiers) < 100 or len(identifiers) != len(set(identifiers)):
        fail("invariant catalog is incomplete or contains duplicate identifiers")


def check_risk_ownership() -> None:
    text = (ROOT / "security" / "risk-register.yaml").read_text(encoding="utf-8")
    critical_blocks = re.findall(
        r"- id:\s+(\S+)(.*?)(?=\n\s+- id:|\Z)", text, flags=re.DOTALL
    )
    for risk_id, block in critical_blocks:
        if re.search(r"severity:\s+(?:EXISTENTIAL|CRITICAL)", block):
            owner = re.search(r"owner:\s+(.+)", block)
            if not owner or not owner.group(1).strip():
                fail(f"critical risk has no owner: {risk_id}")


def check_forbidden_financial_typescript() -> None:
    forbidden = list((ROOT / "services").rglob("*.ts"))
    if forbidden:
        fail("financial/domain service TypeScript is forbidden: " + str(forbidden[0]))


def check_template_manifest() -> None:
    manifest = ROOT / "tools" / "templates" / "manifest.yaml"
    text = manifest.read_text(encoding="utf-8")
    paths = re.findall(r"^\s+\w+:\s+(.+)$", text, flags=re.MULTILINE)
    if len(paths) < 10:
        fail("template manifest is incomplete")
    for relative in paths:
        if not (ROOT / relative.strip()).exists():
            fail(f"template target does not exist: {relative}")


def main() -> None:
    check_structure()
    check_registry_hashes()
    check_cross_references()
    check_invariants()
    check_risk_ownership()
    check_forbidden_financial_typescript()
    check_template_manifest()
    print("Foundation conformance checks passed.")


if __name__ == "__main__":
    main()
