"""Reject obvious raw financial-data fields from the public payment schema."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAYMENT_SCHEMA = ROOT / "schemas" / "proto" / "unified" / "v1" / "payment.proto"
FORBIDDEN_FIELDS = (
    "account_number",
    "bank_account",
    "routing_number",
    "sort_code",
    "iban",
    "swift_code",
    "card_number",
    "cardholder_name",
    "expiry_month",
    "expiry_year",
    "security_code",
    "cvv",
    "cvc",
    "pin",
)
REQUIRED_HASHES = (
    "raw_payload_hash",
    "signature_hash",
    "evidence_hash",
    "provider_snapshot_hash",
    "ledger_snapshot_hash",
)


def main() -> None:
    if not PAYMENT_SCHEMA.is_file():
        raise SystemExit("missing public payment schema")
    source = PAYMENT_SCHEMA.read_text(encoding="utf-8").lower()
    failures: list[str] = []
    for field in FORBIDDEN_FIELDS:
        if re.search(rf"\b{re.escape(field)}\b", source):
            failures.append(f"payment schema exposes forbidden financial field {field}")
    for required in REQUIRED_HASHES:
        if required not in source:
            failures.append(f"payment schema is missing opaque evidence field {required}")
    if re.search(r"\bbytes\s+raw_payload\s*=", source):
        failures.append("payment schema publishes a raw provider payload")
    if failures:
        raise SystemExit("\n".join(failures))
    print("Public payment privacy-surface check passed.")


if __name__ == "__main__":
    main()
