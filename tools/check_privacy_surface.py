"""Reject obvious raw-identity fields from Phase 6 public protocol surfaces."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_PATHS = [
    ROOT / "schemas" / "proto" / "unified" / "v1" / "identity.proto",
    ROOT / "protocol" / "src" / "identity" / "IdentityTypes.sol",
]
FORBIDDEN_FIELDS = (
    "first_name",
    "last_name",
    "full_name",
    "email_address",
    "phone_number",
    "date_of_birth",
    "document_number",
    "passport_number",
    "national_id",
    "physical_address",
    "bank_account",
    "biometric",
)
REQUIRED_COMMITMENTS = (
    "subject_commitment",
    "claims_commitment",
    "feature_evidence_root",
    "reason_codes_hash",
)


def main() -> None:
    combined = ""
    failures: list[str] = []
    for path in PUBLIC_PATHS:
        if not path.is_file():
            failures.append(f"missing public identity surface: {path.relative_to(ROOT)}")
            continue
        text = path.read_text(encoding="utf-8").lower()
        combined += "\n" + text
        for field in FORBIDDEN_FIELDS:
            if re.search(rf"\b{re.escape(field)}\b", text):
                failures.append(
                    f"{path.relative_to(ROOT)} exposes forbidden identity field {field}"
                )
    for required in REQUIRED_COMMITMENTS:
        if required not in combined:
            failures.append(f"public identity surface is missing {required}")
    if failures:
        raise SystemExit("\n".join(failures))
    print("Public identity privacy-surface check passed.")


if __name__ == "__main__":
    main()
