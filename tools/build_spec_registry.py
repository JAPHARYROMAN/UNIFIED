"""Generate the canonical specification registry with SHA-256 content hashes."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "specifications" / "registry.yaml"

SPECS = [
    {
        "id": "UNI-CONSTITUTION",
        "path": "constitution/Unified_Constitution_v0.1.md",
        "owner": "Program Authority",
        "authority": "constitutional",
        "depends": [],
    },
    {
        "id": "UNI-DOMAIN",
        "path": "docs/specifications/Unified_Domain_Model_v0.1.md",
        "owner": "Protocol Architecture Authority",
        "authority": "subordinate",
        "depends": ["UNI-CONSTITUTION"],
    },
    {
        "id": "UNI-LOAN",
        "path": "docs/specifications/Universal_Loan_Model_and_State_Machines_v0.1.md",
        "owner": "Protocol Architecture Authority",
        "authority": "subordinate",
        "depends": ["UNI-CONSTITUTION", "UNI-DOMAIN"],
    },
    {
        "id": "UNI-ACCOUNTING",
        "path": "docs/specifications/Unified_Financial_Accounting_Specification_v0.1.md",
        "owner": "Accounting and Economic Risk Authority",
        "authority": "subordinate",
        "depends": ["UNI-CONSTITUTION", "UNI-DOMAIN", "UNI-LOAN"],
    },
    {
        "id": "UNI-UFT",
        "path": "docs/specifications/UFT_Tokenomics_and_Economic_Security_Specification_v0.1.md",
        "owner": "Accounting and Economic Risk Authority",
        "authority": "subordinate",
        "depends": ["UNI-CONSTITUTION", "UNI-DOMAIN", "UNI-LOAN", "UNI-ACCOUNTING"],
    },
    {
        "id": "UNI-THREAT",
        "path": (
            "docs/specifications/"
            "Unified_Threat_Model_and_Adversarial_Security_Specification_v0.1.md"
        ),
        "owner": "Security Authority",
        "authority": "subordinate",
        "depends": ["UNI-CONSTITUTION", "UNI-DOMAIN", "UNI-LOAN", "UNI-ACCOUNTING", "UNI-UFT"],
    },
    {
        "id": "UNI-INVARIANTS",
        "path": (
            "docs/specifications/"
            "Unified_Protocol_Invariants_and_Formal_Verification_Specification_v0.1.md"
        ),
        "owner": "Security Authority",
        "authority": "subordinate",
        "depends": [
            "UNI-CONSTITUTION",
            "UNI-DOMAIN",
            "UNI-LOAN",
            "UNI-ACCOUNTING",
            "UNI-UFT",
            "UNI-THREAT",
        ],
    },
    {
        "id": "UNI-API",
        "path": (
            "docs/specifications/"
            "Unified_Smart_Contract_Interface_and_Protocol_API_Specification_v0.1.md"
        ),
        "owner": "Protocol Architecture Authority",
        "authority": "subordinate",
        "depends": ["UNI-DOMAIN", "UNI-LOAN", "UNI-INVARIANTS"],
    },
    {
        "id": "UNI-DATA",
        "path": (
            "docs/specifications/"
            "Unified_OnChain_OffChain_Data_Architecture_and_Event_Contract_Specification_v0.1.md"
        ),
        "owner": "Protocol Architecture Authority",
        "authority": "subordinate",
        "depends": ["UNI-DOMAIN", "UNI-ACCOUNTING", "UNI-INVARIANTS", "UNI-API"],
    },
    {
        "id": "UNI-SYSTEM",
        "path": (
            "docs/specifications/"
            "Unified_System_Architecture_Service_Boundaries_and_Deployment_Topology_"
            "Specification_v0.1.md"
        ),
        "owner": "Protocol Architecture Authority",
        "authority": "subordinate",
        "depends": ["UNI-DATA", "UNI-API", "UNI-INVARIANTS", "UNI-THREAT"],
    },
    {
        "id": "UNI-ENGINEERING",
        "path": (
            "docs/specifications/"
            "Unified_Repository_Architecture_Engineering_Constitution_and_Delivery_"
            "Workflow_Specification_v0.1.md"
        ),
        "owner": "Release Authority",
        "authority": "delivery",
        "depends": ["UNI-SYSTEM", "UNI-DATA", "UNI-INVARIANTS"],
    },
    {
        "id": "UNI-PLAN",
        "path": (
            "docs/specifications/"
            "Unified_Implementation_Master_Plan_Work_Breakdown_and_Parallel_Agent_"
            "Orchestration_Specification_v0.1.md"
        ),
        "owner": "Program Authority",
        "authority": "delivery",
        "depends": ["UNI-ENGINEERING", "UNI-SYSTEM", "UNI-DATA", "UNI-API", "UNI-INVARIANTS"],
    },
]


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> None:
    lines = [
        "version: 1",
        "baseline: spec-baseline-v0.1.0",
        "baseline_status: APPROVED_FOR_FOUNDATION_IMPLEMENTATION",
        "production_ratified: false",
        "reviewed_at: 2026-07-24",
        "specifications:",
    ]
    for spec in SPECS:
        path = ROOT / str(spec["path"])
        if not path.is_file():
            raise SystemExit(f"Missing specification: {path}")
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        dependencies = ", ".join(str(item) for item in spec["depends"])
        lines.extend(
            [
                f"  - id: {spec['id']}",
                f"    path: {quote(str(spec['path']))}",
                "    version: '0.1'",
                f"    sha256: {sha}",
                f"    owner: {quote(str(spec['owner']))}",
                f"    authority: {spec['authority']}",
                f"    dependencies: [{dependencies}]",
            ]
        )
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
