"""Phase 9 resolution, protection, and recovery conformance checks."""

from __future__ import annotations

import argparse
import csv
import re
from collections.abc import Iterable
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ADR_PATH = ROOT / "adr/0019-phase-9-resolution-protection-and-recovery-boundary.md"
ARCHITECTURE_PATH = ROOT / "docs/architecture/phase-9-resolution-protection-recovery.md"
DATA_LAYOUTS_PATH = ROOT / "docs/architecture/phase-9-data-layouts.md"
BACKLOG_PATH = ROOT / "docs/backlog/phase-9.csv"
WORKSTREAMS_PATH = ROOT / "docs/ownership/WORKSTREAMS.md"
MASTER_PLAN_PATH = (
    ROOT
    / "docs/specifications/"
    "Unified_Implementation_Master_Plan_Work_Breakdown_and_Parallel_Agent_"
    "Orchestration_Specification_v0.1.md"
)
INVARIANT_SPEC_PATH = (
    ROOT
    / "docs/specifications/"
    "Unified_Protocol_Invariants_and_Formal_Verification_Specification_v0.1.md"
)
INVARIANT_CATALOG_PATH = ROOT / "security/invariant-catalog.csv"
PHASE8_EXIT_PATH = ROOT / "docs/reviews/phase-8-exit-review.md"
FOUNDATION_CHECK_PATH = ROOT / "scripts/check-foundation.ps1"

BACKLOG_IDS = (
    "UNI-ADR-014",
    "UNI-RESIDUAL-003",
    "UNI-RESIDUAL-004",
    "UNI-SCHEMA-013",
    "UNI-PAYOFF-001",
    "UNI-REFI-001",
    "UNI-REFI-002",
    "UNI-RESTRUCT-001",
    "UNI-RESERVE-001",
    "UNI-INSURANCE-001",
    "UNI-GUARANTEE-001",
    "UNI-RECOVERY-002",
    "UNI-DATA-003",
    "UNI-ACCOUNTING-012",
    "UNI-RECON-004",
    "UNI-LOCAL-003",
    "UNI-SIM-008",
    "UNI-RISK-003",
    "UNI-SEC-014",
    "UNI-REVIEW-012",
)
BOUNDARY_COMPLETE_IDS = {
    "UNI-ADR-014",
    "UNI-RESIDUAL-003",
    "UNI-RESIDUAL-004",
}
SECURITY_REVIEW_ID = "UNI-SEC-014"
EXIT_REVIEW_ID = "UNI-REVIEW-012"
ALLOWED_BACKLOG_STATUSES = {"TODO", "DONE"}

REQUIRED_RISKS = {f"RISK-PHASE9-{index:03d}" for index in range(1, 16)}
REQUIRED_ASSUMPTIONS = {f"ASM-{index:03d}" for index in range(34, 45)}
REQUIRED_INVARIANTS = {
    *(f"INV-ACC-{index:03d}" for index in range(1, 8)),
    *(f"INV-AUTH-{index:03d}" for index in range(1, 10)),
    *(f"INV-LOAN-{index:03d}" for index in range(1, 16)),
    *(f"INV-FUND-{index:03d}" for index in range(1, 12)),
    *(f"INV-INT-{index:03d}" for index in range(1, 13)),
    *(f"INV-COL-{index:03d}" for index in range(1, 13)),
    *(f"INV-LIQ-{index:03d}" for index in range(5, 13)),
    *(f"INV-REFI-{index:03d}" for index in range(1, 9)),
    *(f"INV-INS-{index:03d}" for index in range(1, 10)),
    *(f"REC-{index:03d}" for index in range(1, 9)),
    "LIVE-REFI-001",
}

PROTO_FILENAMES = (
    "refinance.proto",
    "restructuring.proto",
    "protection.proto",
    "recovery.proto",
)
RELEASE_MANIFEST_PATH = "protocol/deployments/local/phase9-release-evidence.json"

BOUNDARY_PATHS = (
    ADR_PATH,
    ARCHITECTURE_PATH,
    DATA_LAYOUTS_PATH,
    BACKLOG_PATH,
    WORKSTREAMS_PATH,
    MASTER_PLAN_PATH,
    INVARIANT_SPEC_PATH,
    INVARIANT_CATALOG_PATH,
    PHASE8_EXIT_PATH,
    FOUNDATION_CHECK_PATH,
)

IMPLEMENTATION_PATHS = (
    ROOT / "services/foundation-ledger/migrations/000013_resolution_core.sql",
    ROOT / "services/foundation-ledger/migrations/000014_protection_recovery.sql",
    ROOT / "services/foundation-ledger/migrations/000015_resolution_accounting.sql",
    ROOT / "services/resolution-coordinator",
    ROOT / "security/reviews/phase-9-internal-review.md",
    ROOT / "protocol/abi/phase9",
    ROOT / "infrastructure/local/resolution/phase9-release-evidence.schema.json",
    ROOT / "docs/architecture/phase-9-local-release-evidence.md",
    ROOT / "tools/check_phase9_release_evidence.py",
    ROOT / "scripts/check-phase9-release-evidence.ps1",
    *(ROOT / "schemas/proto/unified/v1" / filename for filename in PROTO_FILENAMES),
)

EXIT_PATH = ROOT / "docs/reviews/phase-9-exit-review.md"
README_PATH = ROOT / "README.md"

REGISTER_FIELDS = ("owner", "evidence", "expiry", "downstream_impact", "validation")
AUTHORITY_OWNERS = {
    "Program Authority",
    "Protocol Architecture Authority",
    "Security Authority",
    "Accounting and Economic Risk Authority",
    "Release Authority",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"ERROR: {message}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip().lower()


def require_paths(paths: Iterable[Path], label: str) -> None:
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.exists()]
    require(not missing, f"missing {label}: {', '.join(missing)}")


def check_boundary_paths() -> None:
    require_paths(BOUNDARY_PATHS, "Phase 9 boundary paths")


def check_backlog(require_implementation: bool, require_exit: bool) -> None:
    with BACKLOG_PATH.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        require(
            reader.fieldnames == ["id", "workstream", "title", "status", "owner", "acceptance"],
            "Phase 9 backlog header drifted",
        )
        rows = list(reader)

    identifiers = [row["id"] for row in rows]
    require(identifiers == list(BACKLOG_IDS), "Phase 9 backlog IDs or ordering drifted")
    require(len(identifiers) == len(set(identifiers)), "Phase 9 backlog IDs are duplicated")

    by_id = {row["id"]: row for row in rows}
    for identifier, row in by_id.items():
        require(
            row["status"] in ALLOWED_BACKLOG_STATUSES,
            f"{identifier} has unsupported status {row['status']!r}",
        )
        require(row["workstream"].startswith("WS-"), f"{identifier} lacks a workstream")
        require(row["owner"] in AUTHORITY_OWNERS, f"{identifier} has an unknown owner")
        require(bool(row["title"].strip()), f"{identifier} lacks a title")
        require(bool(row["acceptance"].strip()), f"{identifier} lacks acceptance evidence")

    incomplete_boundary = sorted(
        identifier
        for identifier in BOUNDARY_COMPLETE_IDS
        if by_id[identifier]["status"] != "DONE"
    )
    require(
        not incomplete_boundary,
        f"Phase 9 boundary rows must remain DONE: {incomplete_boundary}",
    )

    if by_id[EXIT_REVIEW_ID]["status"] == "DONE":
        incomplete = [row["id"] for row in rows if row["status"] != "DONE"]
        require(not incomplete, "Phase 9 exit cannot be DONE while another row is incomplete")

    if by_id[SECURITY_REVIEW_ID]["status"] == "DONE":
        incomplete_before_review = [
            row["id"]
            for row in rows
            if row["id"] not in {SECURITY_REVIEW_ID, EXIT_REVIEW_ID}
            and row["status"] != "DONE"
        ]
        require(
            not incomplete_before_review,
            "Phase 9 security review cannot close before implementation work: "
            + ", ".join(incomplete_before_review),
        )

    if require_implementation:
        incomplete_implementation = [
            row["id"]
            for row in rows
            if row["id"] != EXIT_REVIEW_ID and row["status"] != "DONE"
        ]
        require(
            not incomplete_implementation,
            "Phase 9 implementation backlog remains open: "
            + ", ".join(incomplete_implementation),
        )

    if require_exit:
        incomplete_exit = [row["id"] for row in rows if row["status"] != "DONE"]
        require(
            not incomplete_exit,
            "Phase 9 exit backlog remains open: " + ", ".join(incomplete_exit),
        )


def declared_ids(text: str, pattern: str) -> set[str]:
    return set(re.findall(pattern, text, flags=re.MULTILINE))


def check_boundary_declarations() -> None:
    adr = read(ADR_PATH)
    risks = declared_ids(adr, r"`(RISK-PHASE9-\d{3})`")
    assumptions = declared_ids(adr, r"`(ASM-\d{3})`")
    require(risks == REQUIRED_RISKS, "Phase 9 boundary risk declarations drifted")
    require(
        REQUIRED_ASSUMPTIONS <= assumptions,
        "Phase 9 boundary assumption declarations are incomplete",
    )
    unexpected_assumptions = {
        identifier
        for identifier in assumptions
        if identifier.startswith("ASM-") and identifier not in REQUIRED_ASSUMPTIONS
    }
    require(
        not unexpected_assumptions,
        "Phase 9 boundary declares unexpected assumptions: "
        + ", ".join(sorted(unexpected_assumptions)),
    )


def section(text: str, heading: str) -> str:
    match = re.search(
        rf"^##\s+{re.escape(heading)}\b(?P<body>.*?)(?=^##\s+|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"ERROR: workstream section {heading} is missing")
    return match.group("body")


def require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    lowered = text.lower()
    missing = [token for token in tokens if token.lower() not in lowered]
    require(not missing, f"{label} is missing: {', '.join(missing)}")


def check_workstream_ownership() -> None:
    workstreams = read(WORKSTREAMS_PATH)
    protocol = section(workstreams, "WS-PROTOCOL")
    ledger = section(workstreams, "WS-LEDGER")
    risk = section(workstreams, "WS-RISK")

    require_tokens(
        protocol,
        (
            "payoff",
            "refinance",
            "lien-handoff",
            "restructuring",
            "funded-protection",
            "guarantee",
            "write-off",
            "subrogation",
            "recovery",
        ),
        "WS-PROTOCOL Phase 9 ownership",
    )
    require_tokens(
        ledger,
        ("Phase 9", "resolution", "protection", "loss", "recovery", "solvency", "reconciliation"),
        "WS-LEDGER Phase 9 ownership",
    )
    require_tokens(
        risk,
        ("payoff-component", "reserve stress haircuts", "modeled-loss"),
        "WS-RISK Phase 9 ownership",
    )

    headings = set(re.findall(r"^##\s+(WS-[A-Z0-9-]+)\b", workstreams, re.MULTILINE))
    with BACKLOG_PATH.open(encoding="utf-8", newline="") as handle:
        referenced = {row["workstream"] for row in csv.DictReader(handle)}
    require(
        referenced <= headings,
        "Phase 9 backlog references undefined workstreams: "
        + ", ".join(sorted(referenced - headings)),
    )


def check_production_prohibitions() -> None:
    adr = normalized(read(ADR_PATH))
    architecture = normalized(read(ARCHITECTURE_PATH))

    require_tokens(
        adr,
        (
            "real reserves",
            "insurance promises",
            "guarantees",
            "legal",
            "production providers",
            "public testnet",
            "mainnet",
            "production keys",
            "hsm/kms",
            "real uft",
            "real fund",
            "cross-chain lien transfer",
            "administrator rescue",
            "arbitrary reserve withdrawal",
            "production solvency",
        ),
        "Phase 9 ADR production prohibitions",
    )
    require_tokens(
        architecture,
        (
            "reject non-loopback providers",
            "containing real value",
            "no real reserve",
            "production credential",
            "public network",
            "actuarial",
            "capital measure",
            "phase 10 cannot treat this milestone as authority",
        ),
        "Phase 9 architecture production boundary",
    )


def check_no_stale_phase17_recovery() -> None:
    suffixes = {".md", ".csv", ".yaml", ".yml"}
    stale: list[str] = []
    for base in (ROOT / "adr", ROOT / "docs", ROOT / "security"):
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in suffixes:
                continue
            for number, line in enumerate(read(path).splitlines(), start=1):
                if re.search(r"\bphase\s+17\b", line, flags=re.IGNORECASE):
                    stale.append(f"{path.relative_to(ROOT)}:{number}")
    require(
        not stale,
        "stale Phase 17 recovery wording remains at " + ", ".join(stale),
    )


def check_boundary_evidence() -> None:
    master = read(MASTER_PLAN_PATH)
    architecture = read(ARCHITECTURE_PATH)
    data_layouts = read(DATA_LAYOUTS_PATH)
    adr = read(ADR_PATH)
    phase8_exit = read(PHASE8_EXIT_PATH)
    foundation_check = read(FOUNDATION_CHECK_PATH)

    require_tokens(
        master,
        (
            "Phase 9 — Refinancing, Restructuring, Insurance, and Recovery",
            "WP-9.1 — Payoff quote engine",
            "WP-9.2 — Refinance coordinator",
            "WP-9.3 — Restructuring controller",
            "WP-9.4 — Insurance manager",
            "WP-9.5 — Recovery manager",
            "Refinancing never creates duplicate senior liens",
            "Failed refinancing returns to a safe state",
            "Restructuring preserves required consent",
            "Insurance claims cannot exceed coverage",
            "Losses and recoveries are not double-counted",
            "Reserve solvency metrics are available",
        ),
        "Phase 9 master-plan evidence",
    )
    require_tokens(
        adr,
        (
            "Status: accepted for synthetic local engineering",
            "chain ID `31337`",
            "UNI-RESIDUAL-003",
            "UNI-RESIDUAL-004",
            "RISK-PHASE9-001",
            "RISK-PHASE9-015",
            "ASM-034",
            "ASM-044",
            "exact release evidence",
            "one-command reset",
            "post-reset absence",
            "crash/restart",
            "separate exit-review PR",
        ),
        "Phase 9 ADR boundary evidence",
    )
    require_tokens(
        architecture,
        (
            "9A — Boundary, schemas, and models",
            "9B — Payoff and refinance",
            "9C — Restructuring and consent",
            "9D — Funded protection",
            "9E — Loss and recovery",
            "9F — Simulations, release, and review",
            "restart",
            "reconciliation",
            "release-evidence",
            "post-reset",
            "INV-ACC-001",
            "INV-ACC-007",
            "INV-AUTH-001",
            "INV-AUTH-009",
            "INV-LOAN-001",
            "INV-LOAN-015",
            "INV-FUND-001",
            "INV-FUND-011",
            "INV-INT-001",
            "INV-INT-012",
            "INV-COL-001",
            "INV-COL-012",
            "INV-LIQ-005",
            "INV-LIQ-012",
            "INV-REFI-001",
            "INV-REFI-008",
            "INV-INS-001",
            "INV-INS-009",
            "REC-001",
            "REC-008",
            "LIVE-REFI-001",
        ),
        "Phase 9 architecture acceptance evidence",
    )
    require_tokens(
        data_layouts,
        (
            "eligible risk-adjusted reserve assets",
            "= floor(",
            "/ 10_000",
            "0 <= stress_haircut_basis_points <= 10_000",
            "modeled_loss_at_target_confidence > 0",
            "canonical pre-claim: floor(64 * 10_000 / 10_000) = 64",
            "claim-specific payment liquidity",
            "beneficiary covered unresolved entitlement",
            "prohibits partial claim transfers",
            "1570 Segregated Product Reserve Asset",
            "each of the 45 fully qualified table names",
            "exact row count",
            "deterministic ordered",
            "content hash",
            "aggregate Phase 9 SQL state hash",
        ),
        "Phase 9 numerical, claim, reserve, and release boundary evidence",
    )
    require_tokens(
        "\n".join((adr, architecture, data_layouts)),
        (*PROTO_FILENAMES, RELEASE_MANIFEST_PATH),
        "Phase 9 additive interface and release-manifest declarations",
    )
    require_tokens(
        phase8_exit,
        (
            "Cancellation authorization expiry and reissue",
            "Authenticated collateral absence and terminalization",
            "Production use requires",
        ),
        "Phase 8 residual carry-forward evidence",
    )
    require(
        "tools/check_phase9.py" in foundation_check.replace("\\", "/"),
        "foundation check does not invoke the Phase 9 checker",
    )

    with INVARIANT_CATALOG_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    catalog_ids = [row["id"] for row in rows]
    require(
        len(catalog_ids) == len(set(catalog_ids)),
        "invariant catalog contains duplicate IDs",
    )
    require(
        REQUIRED_INVARIANTS <= set(catalog_ids),
        "Phase 9 invariant catalog evidence is incomplete: "
        + ", ".join(sorted(REQUIRED_INVARIANTS - set(catalog_ids))),
    )


def register_blocks(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^\s*-\s+id:\s+([A-Z0-9-]+)\s*$", text, re.MULTILINE))
    blocks: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        identifier = match.group(1)
        require(identifier not in blocks, f"register entry {identifier} is duplicated")
        blocks[identifier] = text[match.start() : end]
    return blocks


def field_value(block: str, field: str) -> str:
    match = re.search(rf"^\s+{re.escape(field)}:\s*(.+?)\s*$", block, re.MULTILINE)
    return match.group(1).strip().strip("\"'") if match else ""


def check_register_entry(
    identifier: str,
    block: str,
    *,
    risk: bool,
) -> None:
    for field in REGISTER_FIELDS:
        require(field_value(block, field) != "", f"{identifier} lacks {field}")
    require(
        field_value(block, "owner") in AUTHORITY_OWNERS,
        f"{identifier} has an unknown owner",
    )
    require(
        re.fullmatch(r"\d{4}-\d{2}-\d{2}", field_value(block, "expiry")) is not None,
        f"{identifier} expiry is not an ISO date",
    )
    evidence = field_value(block, "evidence")
    if "://" not in evidence:
        require(
            (ROOT / evidence).exists(),
            f"{identifier} evidence path does not exist: {evidence}",
        )
    if risk:
        require(
            field_value(block, "severity") in {"CRITICAL", "EXISTENTIAL"},
            f"{identifier} must be CRITICAL or EXISTENTIAL",
        )
        require(field_value(block, "title") != "", f"{identifier} lacks title")
        require(
            field_value(block, "status") == "CONTROLLED_LOCAL_ONLY",
            f"{identifier} is not CONTROLLED_LOCAL_ONLY",
        )


def check_implementation_registers() -> None:
    risk_blocks = register_blocks(read(ROOT / "security/risk-register.yaml"))
    assumption_blocks = register_blocks(read(ROOT / "security/assumption-register.yaml"))

    phase9_risks = {
        identifier for identifier in risk_blocks if identifier.startswith("RISK-PHASE9-")
    }
    require(phase9_risks == REQUIRED_RISKS, "Phase 9 implementation risk register drifted")
    missing_assumptions = REQUIRED_ASSUMPTIONS - set(assumption_blocks)
    require(
        not missing_assumptions,
        "Phase 9 implementation assumption register is incomplete: "
        + ", ".join(sorted(missing_assumptions)),
    )

    for identifier in sorted(REQUIRED_RISKS):
        check_register_entry(identifier, risk_blocks[identifier], risk=True)
    for identifier in sorted(REQUIRED_ASSUMPTIONS):
        check_register_entry(identifier, assumption_blocks[identifier], risk=False)


def combined_text(paths: Iterable[Path]) -> str:
    return "\n".join(read(path) for path in paths)


def check_implementation_artifacts() -> None:
    require_paths(IMPLEMENTATION_PATHS, "Phase 9 implementation artifacts")
    check_implementation_registers()

    proto_paths = sorted((ROOT / "schemas/proto/unified/v1").glob("*.proto"))
    proto = combined_text(proto_paths)
    require_tokens(
        proto,
        (
            "PayoffQuote",
            "Refinance",
            "Restructur",
            "PositionSnapshot",
            "Reserve",
            "Coverage",
            "InsuranceClaim",
            "Guarantee",
            "WriteOff",
            "Subrogation",
            "Recovery",
            "Solvency",
            "Reconciliation",
        ),
        "Phase 9 canonical schema",
    )

    solidity_paths = [
        path
        for path in (ROOT / "protocol/src").rglob("*.sol")
        if "crosschain" not in {part.lower() for part in path.parts}
    ]
    solidity = combined_text(solidity_paths)
    contract_patterns = {
        "payoff quote": r"\bcontract\s+\w*Payoff\w*",
        "refinance": r"\bcontract\s+\w*Refinance\w*",
        "lien registry": r"\bcontract\s+\w*Lien\w*",
        "restructuring": r"\bcontract\s+\w*Restructur\w*",
        "reserve vault": r"\bcontract\s+\w*Reserve\w*",
        "insurance or protection": r"\bcontract\s+\w*(?:Insurance|Protection)\w*",
        "guarantee": r"\bcontract\s+\w*Guarantee\w*",
        "recovery": r"\bcontract\s+\w*Recovery\w*",
    }
    missing_contracts = [
        label
        for label, pattern in contract_patterns.items()
        if re.search(pattern, solidity) is None
    ]
    require(
        not missing_contracts,
        "Phase 9 Solidity implementation is incomplete: " + ", ".join(missing_contracts),
    )

    model_paths = sorted(
        (ROOT / "models/foundation_model/src/unified_foundation").glob("*.py")
    )
    model_text = combined_text(model_paths)
    require_tokens(
        model_text,
        (
            "payoff",
            "refinance",
            "restructur",
            "coverage",
            "claim",
            "guarantee",
            "write_off",
            "subrogation",
            "recovery",
        ),
        "Phase 9 independent model",
    )

    abi_files = list((ROOT / "protocol/abi/phase9").glob("*.abi.json"))
    require(bool(abi_files), "Phase 9 ABI snapshot directory is empty")
    phase9_tests = list((ROOT / "protocol/test").glob("*Phase9*.t.sol"))
    require(bool(phase9_tests), "Phase 9 Foundry tests are missing")

    smoke_scripts = [
        path
        for path in (ROOT / "scripts").glob("*phase9*")
        if "smoke" in path.name.lower() and path.suffix.lower() in {".ps1", ".sh"}
    ]
    require(bool(smoke_scripts), "Phase 9 local smoke script is missing")

    workflow = normalized(read(ROOT / ".github/workflows/foundation.yml"))
    require_tokens(
        workflow,
        (
            "phase9",
            "check-phase9-release-evidence",
            "pre-reset",
            "local-reset",
            "post-reset",
        ),
        "Phase 9 live CI evidence",
    )
    reset = normalized(read(ROOT / "scripts/local-reset.ps1"))
    require("phase9" in reset, "local reset does not remove Phase 9 evidence")

    review = normalized(read(ROOT / "security/reviews/phase-9-internal-review.md"))
    require_tokens(
        review,
        (
            "synthetic",
            "local",
            "no unresolved critical or existential",
            "production",
            "not granted",
        ),
        "Phase 9 internal security review",
    )


def check_exit_artifacts() -> None:
    require_paths((EXIT_PATH, README_PATH), "Phase 9 exit artifacts")
    readme = read(README_PATH).replace("\\", "/")
    require(
        "docs/reviews/phase-9-exit-review.md" in readme,
        "README does not link the Phase 9 exit review",
    )
    invocation = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        re.search(
            r"tools/check_phase9\.py\s+--require-exit-complete(?:\s|$)",
            invocation,
        )
        is not None,
        "foundation check does not invoke Phase 9 with --require-exit-complete",
    )
    exit_review = normalized(read(EXIT_PATH))
    require_tokens(
        exit_review,
        (
            "decision: pass",
            "production",
            "not granted",
            "all five",
            "all six",
            "protected",
            "reset",
        ),
        "Phase 9 exit review",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-implementation-complete", action="store_true")
    parser.add_argument("--require-exit-complete", action="store_true")
    args = parser.parse_args()

    require_implementation = (
        args.require_implementation_complete or args.require_exit_complete
    )
    check_boundary_paths()
    check_backlog(require_implementation, args.require_exit_complete)
    check_boundary_declarations()
    check_workstream_ownership()
    check_production_prohibitions()
    check_no_stale_phase17_recovery()
    check_boundary_evidence()

    if require_implementation:
        check_implementation_artifacts()
    if args.require_exit_complete:
        check_exit_artifacts()

    mode = (
        "exit"
        if args.require_exit_complete
        else "implementation"
        if require_implementation
        else "boundary"
    )
    print(f"Phase 9 {mode} checks passed.")


if __name__ == "__main__":
    main()
