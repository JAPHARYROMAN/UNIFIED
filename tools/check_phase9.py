"""Phase 9 resolution, protection, and recovery conformance checks."""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections.abc import Iterable
from pathlib import Path

from check_abi import ABI_PAIRS

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
CONTRACT_SIZE_CHECK_PATH = ROOT / "scripts/check-contract-sizes.py"
PROTOCOL_COMPILATION_PATH = ROOT / "protocol/src/ProtocolCompilation.sol"
PHASE9_ABI_PATH = ROOT / "protocol/abi/phase9"
PHASE9_STORAGE_PATH = ROOT / "protocol/storage-layout/phase9"
PHASE9_STORAGE_CHECK_PATH = ROOT / "tools/check_phase9_storage_layouts.py"
PHASE9_DEPLOY_SCRIPT_PATH = ROOT / "protocol/script/DeployPhase9Local.s.sol"
PHASE9_RELEASE_CHECK_PATH = ROOT / "tools/check_phase9_release_evidence.py"
PHASE9_RELEASE_SCHEMA_PATH = (
    ROOT / "infrastructure/local/resolution/phase9-release-evidence.schema.json"
)
PHASE9_RELEASE_DOC_PATH = ROOT / "docs/architecture/phase-9-local-release-evidence.md"

PHASE9_PRODUCTION_CONTRACTS = (
    "Phase9LoanFactory",
    "Phase9LoanAccount",
    "PayoffQuoteEngine",
    "CollateralCustodyV2",
    "LienRegistry",
    "RefinanceCoordinator",
    "PositionManagerV2",
    "RestructuringController",
    "InsuranceReserveVault",
    "ReservePolicy",
    "InsuranceManager",
    "GuaranteeVault",
    "RecoveryManager",
)
PHASE9_CONTRACTS = (*PHASE9_PRODUCTION_CONTRACTS, "Phase9LocalSyntheticToken")

EXPECTED_QUOTE_PREIMAGE = (
    '"UNIFIED_PAYOFF_QUOTE_V1"',
    "payoff_quote_engine",
    "chainid",
    "loan_id",
    "loan_account",
    "policy_hash",
    "debt_state_version",
    "principal",
    "accrued_interest",
    "fees",
    "penalties",
    "credits",
    "component_beneficiary_hash",
    "net_payoff",
    "settlement_asset_id",
    "settlement_token",
    "settlement_route_hash",
    "issued_at",
    "valid_until",
    "quote_nonce",
)

BACKLOG_IDS = (
    "UNI-ADR-014",
    "UNI-RESIDUAL-003",
    "UNI-RESIDUAL-004",
    "UNI-SCHEMA-013",
    "UNI-ABI-009",
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
    PHASE9_ABI_PATH,
    PHASE9_STORAGE_PATH,
    PHASE9_STORAGE_CHECK_PATH,
    PHASE9_DEPLOY_SCRIPT_PATH,
    PHASE9_RELEASE_SCHEMA_PATH,
    PHASE9_RELEASE_DOC_PATH,
    PHASE9_RELEASE_CHECK_PATH,
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


def check_backlog(
    require_implementation: bool, require_exit: bool
) -> dict[str, dict[str, str]]:
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
    check_backlog_precedence(by_id)

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
    return by_id


def check_backlog_precedence(by_id: dict[str, dict[str, str]]) -> None:
    schema_done = by_id["UNI-SCHEMA-013"]["status"] == "DONE"
    abi_done = by_id["UNI-ABI-009"]["status"] == "DONE"
    require(
        not abi_done or schema_done,
        "UNI-SCHEMA-013 must be DONE before UNI-ABI-009 can be DONE",
    )

    abi_index = BACKLOG_IDS.index("UNI-ABI-009")
    later_done = [
        identifier
        for identifier in BACKLOG_IDS[abi_index + 1 :]
        if by_id[identifier]["status"] == "DONE"
    ]
    require(
        abi_done or not later_done,
        "UNI-ABI-009 must be DONE before later Phase 9 work can be DONE: "
        + ", ".join(later_done),
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


def quote_preimage(text: str, label: str) -> tuple[str, ...]:
    match = re.search(
        r"quote_id\s*=\s*keccak256\s*\(\s*abi\.encode\s*\((?P<fields>.*?)\)\s*\)",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"ERROR: {label} payoff quote preimage is not parseable")
    fields = tuple(
        field.strip()
        for field in match.group("fields").split(",")
        if field.strip()
    )
    aliases = {
        "address(this)": "payoff_quote_engine",
        "interest": "accrued_interest",
    }
    return tuple(aliases.get(field, field) for field in fields)


def adr_quote_preimage(text: str) -> tuple[str, ...]:
    match = re.search(
        r"The quote preimage binds:\s*```text\s*(?P<fields>.*?)```",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit("ERROR: Phase 9 ADR payoff quote preimage is not parseable")
    aliases = {
        "payoff quote engine address": "payoff_quote_engine",
        "chain ID": "chainid",
        "loan ID": "loan_id",
        "loan account address": "loan_account",
        "quote policy hash": "policy_hash",
        "debt state version": "debt_state_version",
        "accrued interest": "accrued_interest",
        "canonical component-beneficiary vector": "component_beneficiary_hash",
        "net payoff amount": "net_payoff",
        "settlement asset ID": "settlement_asset_id",
        "settlement token address": "settlement_token",
        "settlement route hash": "settlement_route_hash",
        "issued at": "issued_at",
        "valid until": "valid_until",
        "quote nonce": "quote_nonce",
    }
    return tuple(
        aliases.get(field, field)
        for field in (line.strip() for line in match.group("fields").splitlines())
        if field
    )


def check_quote_preimage_order(adr: str, architecture: str, data_layouts: str) -> None:
    adr_fields = adr_quote_preimage(adr)
    architecture_fields = quote_preimage(architecture, "Phase 9 architecture")
    data_layout_fields = quote_preimage(data_layouts, "Phase 9 data layouts")
    require(
        adr_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 ADR payoff quote preimage ordering drifted",
    )
    require(
        architecture_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 architecture payoff quote preimage ordering drifted",
    )
    require(
        data_layout_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 data-layout payoff quote preimage ordering drifted",
    )


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
        normalized(master),
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
        normalized(adr),
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
            "exact typed Phase 9 contract ABI",
            "storage-layout",
            "compilation-root",
            "deterministic snapshot",
            "Phase9LocalSyntheticToken",
            "deployed only on Anvil",
            "is included in",
            "removed with all Phase 9 state by reset",
        ),
        "Phase 9 ADR boundary evidence",
    )
    require_tokens(
        normalized(architecture),
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
            "ProtocolCompilation.sol",
            "imports every Phase 9 contract",
            "scripts/check-foundation.ps1",
            "formats",
            "src/interfaces/phase9",
            "src/resolution",
            "src/protection",
            "src/recovery",
            "tests, and scripts",
            "tools/check_abi.py",
            "explicit compiled/snapshot pairs",
            "protocol/storage-layout/phase9/<Contract>.storage.json",
            "A dedicated checker compares",
            "ABI and storage checkers run from",
            "Phase9LocalSyntheticToken",
            "Golden vectors prove the exact quote preimage order",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "neutral fixture labels only",
            "currency denomination",
            "USD or other fiat peg",
            "redemption",
            "backing",
            "exchange rate",
            "market value",
            "payment claim",
            "legal tender status",
            "provider obligation",
            "Contract-size checking sees every deployable Phase 9 runtime",
        ),
        "Phase 9 architecture acceptance evidence",
    )
    require_tokens(
        normalized(data_layouts),
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
            "capture compiler storage-layout artifacts",
            "fail ABI/storage checks",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "neutral fixture labels",
            "currency denomination",
            "fiat or USD peg",
            "redemption",
            "backing",
            "exchange rate",
            "market value",
            "payment claim",
            "legal tender status",
            "provider obligation",
        ),
        "Phase 9 numerical, claim, reserve, and release boundary evidence",
    )
    require_tokens(
        "\n".join((adr, architecture, data_layouts)),
        (*PROTO_FILENAMES, RELEASE_MANIFEST_PATH),
        "Phase 9 additive interface and release-manifest declarations",
    )
    require_tokens(
        normalized(phase8_exit),
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
    check_quote_preimage_order(adr, architecture, data_layouts)

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


def strip_solidity_comments(text: str) -> str:
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.DOTALL)


def protocol_compilation_imports() -> dict[str, Path]:
    require_paths((PROTOCOL_COMPILATION_PATH,), "protocol compilation root")
    imports: dict[str, Path] = {}
    for match in re.finditer(
        r'import\s*\{(?P<symbols>[^}]+)\}\s*from\s*"(?P<path>[^"]+)"\s*;',
        read(PROTOCOL_COMPILATION_PATH),
        flags=re.DOTALL,
    ):
        source_path = (PROTOCOL_COMPILATION_PATH.parent / match.group("path")).resolve()
        for declaration in match.group("symbols").split(","):
            contract = declaration.strip().split()[0]
            require(contract not in imports, f"duplicate compilation import for {contract}")
            imports[contract] = source_path
    return imports


def is_phase9_source_path(path: Path) -> bool:
    try:
        relative = path.relative_to(ROOT / "protocol/src")
    except ValueError:
        return True
    return (
        relative.parts[0].lower() in {"resolution", "protection", "recovery"}
        or (
            len(relative.parts) >= 2
            and relative.parts[0].lower() == "interfaces"
            and relative.parts[1].lower() == "phase9"
        )
        or "phase9" in relative.stem.lower()
    )


def phase9_candidate_source_files() -> list[Path]:
    return sorted(
        path.resolve()
        for path in (ROOT / "protocol/src").rglob("*.sol")
        if is_phase9_source_path(path.resolve())
    )


def phase9_source_declarations() -> dict[str, list[Path]]:
    declarations: dict[str, list[Path]] = {}
    for path in (ROOT / "protocol/src").rglob("*.sol"):
        source = strip_solidity_comments(read(path))
        contracts = [
            match.group("contract")
            for match in re.finditer(
                r"\b(?P<abstract>abstract\s+)?contract\s+(?P<contract>[A-Za-z_]\w*)",
                source,
            )
            if match.group("abstract") is None
        ]
        if not contracts:
            continue
        if is_phase9_source_path(path) or set(contracts) & set(PHASE9_CONTRACTS):
            for contract in contracts:
                declarations.setdefault(contract, []).append(path.resolve())
    return declarations


def phase9_freeze_started() -> bool:
    imports = protocol_compilation_imports()
    has_phase9_import = any(
        contract in PHASE9_CONTRACTS or is_phase9_source_path(source_path)
        for contract, source_path in imports.items()
    )
    return (
        has_phase9_import
        or bool(phase9_candidate_source_files())
        or bool(phase9_source_declarations())
    )


def phase9_compilation_imports() -> dict[str, Path]:
    imports = protocol_compilation_imports()
    declarations = phase9_source_declarations()
    expected_contracts = set(PHASE9_CONTRACTS)
    actual_contracts = set(declarations)
    require(
        actual_contracts == expected_contracts,
        "Phase 9 production source set drifted; missing="
        + ",".join(sorted(expected_contracts - actual_contracts))
        + "; unexpected="
        + ",".join(sorted(actual_contracts - expected_contracts)),
    )
    duplicate_sources = sorted(
        contract for contract, paths in declarations.items() if len(paths) != 1
    )
    require(
        not duplicate_sources,
        "Phase 9 contracts have duplicate source declarations: "
        + ", ".join(duplicate_sources),
    )

    phase9_imports = {
        contract: source_path
        for contract, source_path in imports.items()
        if contract in expected_contracts or is_phase9_source_path(source_path)
    }
    missing = sorted(expected_contracts - set(phase9_imports))
    unexpected = sorted(set(phase9_imports) - expected_contracts)
    require(
        not missing and not unexpected,
        "ProtocolCompilation.sol Phase 9 import set drifted; missing="
        + ",".join(missing)
        + "; unexpected="
        + ",".join(unexpected),
    )
    for contract in PHASE9_CONTRACTS:
        source_path = phase9_imports[contract]
        require(source_path.is_file(), f"Phase 9 source import is missing for {contract}")
        try:
            source_path.relative_to(ROOT / "protocol/src")
        except ValueError:
            require(False, f"Phase 9 source import escapes protocol/src: {contract}")
        require(
            declarations[contract] == [source_path],
            f"{contract} compilation import does not match its unique source declaration",
        )
    return phase9_imports


def check_phase9_abi_pairs(imports: dict[str, Path]) -> None:
    phase9_pairs = {
        contract: pair
        for contract, pair in ABI_PAIRS.items()
        if pair[1].parent == PHASE9_ABI_PATH
    }
    expected_contracts = set(PHASE9_CONTRACTS)
    actual_contracts = set(phase9_pairs)
    require(
        actual_contracts == expected_contracts,
        "tools/check_abi.py Phase 9 pair set drifted; missing="
        + ",".join(sorted(expected_contracts - actual_contracts))
        + "; unexpected="
        + ",".join(sorted(actual_contracts - expected_contracts)),
    )

    for contract in PHASE9_CONTRACTS:
        compiled_path, baseline_path = phase9_pairs[contract]
        source_stem = (
            imports[contract]
            .relative_to(ROOT)
            .with_suffix("")
            .as_posix()
            .replace("/", "_")
        )
        expected_compiled_path = (
            ROOT / ".cache/solc" / f"{source_stem}_sol_{contract}.abi"
        )
        expected_baseline_path = PHASE9_ABI_PATH / f"{contract}.abi.json"
        require(
            compiled_path == expected_compiled_path,
            f"{contract} compiled ABI pair does not match its compilation import",
        )
        require(
            baseline_path == expected_baseline_path,
            f"{contract} ABI pair does not use its exact Phase 9 snapshot",
        )
        require_paths((baseline_path,), f"{contract} reviewed ABI snapshot")


def check_phase9_storage_layouts() -> None:
    require_paths((PHASE9_STORAGE_CHECK_PATH,), "Phase 9 storage-layout checker")
    expected_snapshots = {
        PHASE9_STORAGE_PATH / f"{contract}.storage.json"
        for contract in PHASE9_CONTRACTS
    }
    require_paths(expected_snapshots, "Phase 9 storage-layout snapshots")
    for snapshot_path in sorted(expected_snapshots):
        snapshot = json.loads(read(snapshot_path))
        require(
            isinstance(snapshot, dict) and bool(snapshot),
            f"Phase 9 storage-layout snapshot is empty: {snapshot_path.name}",
        )

    checker = read(PHASE9_STORAGE_CHECK_PATH)
    require_tokens(
        checker,
        (
            "protocol/storage-layout/phase9",
            "storageLayout",
            "compiler",
            "settings",
            "linearized",
            "slot",
            "offset",
            "encoding",
            "sort_keys",
            *PHASE9_CONTRACTS,
        ),
        "Phase 9 deterministic storage-layout checker",
    )
    require(
        re.search(r"sort_keys\s*=\s*True", checker) is not None,
        "Phase 9 storage-layout checker does not canonicalize snapshot key order",
    )
    foundation_check = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        "tools/check_phase9_storage_layouts.py" in foundation_check,
        "foundation check does not invoke the Phase 9 storage-layout checker",
    )


def check_phase9_formatting_scope(imports: dict[str, Path]) -> None:
    foundation_check = read(FOUNDATION_CHECK_PATH)
    match = re.search(
        r"forge\s+fmt\s+--check(?P<scope>.*?)(?=\n\s*forge\s+test\b)",
        foundation_check,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit("ERROR: foundation Solidity formatting command is not parseable")
    scopes = {
        token.replace("\\", "/")
        for token in match.group("scope").replace("`", " ").split()
    }
    phase9_sources = set(imports.values()) | set(phase9_candidate_source_files())
    uncovered: list[str] = []
    for source_path in sorted(phase9_sources):
        relative_source = source_path.relative_to(ROOT / "protocol").as_posix()
        if not any(
            relative_source == scope or relative_source.startswith(scope.rstrip("/") + "/")
            for scope in scopes
        ):
            uncovered.append(relative_source)
    require(
        not uncovered,
        "Solidity formatting scope excludes Phase 9 sources: " + ", ".join(uncovered),
    )


def check_phase9_contract_size_coverage() -> None:
    require_paths((CONTRACT_SIZE_CHECK_PATH,), "contract-size checker")
    checker = read(CONTRACT_SIZE_CHECK_PATH)
    require_tokens(
        checker,
        ("protocol", "out", "*.json", "deployedBytecode", "24_576"),
        "generic production contract-size checker",
    )
    excluded_match = re.search(
        r"NON_PRODUCTION\s*=\s*\{(?P<contracts>.*?)\}",
        checker,
        flags=re.DOTALL,
    )
    if excluded_match is None:
        raise SystemExit("ERROR: contract-size exclusion set is not parseable")
    excluded = set(re.findall(r'["\']([A-Za-z_]\w*)["\']', excluded_match.group("contracts")))
    wrongly_excluded = sorted(set(PHASE9_CONTRACTS) & excluded)
    require(
        not wrongly_excluded,
        "Phase 9 deployable contracts are excluded from size checking: "
        + ", ".join(wrongly_excluded),
    )
    foundation_check = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        "scripts/check-contract-sizes.py" in foundation_check,
        "foundation check does not invoke production contract-size checking",
    )


def check_phase9_local_token_source(imports: dict[str, Path]) -> None:
    token_source = strip_solidity_comments(read(imports["Phase9LocalSyntheticToken"]))
    require_tokens(
        token_source,
        (
            "contract Phase9LocalSyntheticToken",
            "ERC20",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "FIXED_SUPPLY_UNITS",
            "1_000_000_000_000_000",
            "InvalidLocalChain",
            "InvalidFixtureAllocator",
        ),
        "Phase 9 local synthetic token implementation",
    )
    inheritance_match = re.search(
        r"contract\s+Phase9LocalSyntheticToken\s+is\s+(?P<bases>[^\{]+)\{",
        token_source,
    )
    if inheritance_match is None:
        raise SystemExit("ERROR: Phase9LocalSyntheticToken inheritance is not parseable")
    bases = {base.strip() for base in inheritance_match.group("bases").split(",")}
    require(
        "ERC20" in bases
        and bases <= {"ERC20", "IPhase9LocalSyntheticToken"},
        "Phase9LocalSyntheticToken has prohibited inheritance: "
        + ", ".join(sorted(bases)),
    )
    require(
        re.search(
            r"constructor\s*\(\s*address\s+fixtureAllocator\s*\)", token_source
        )
        is not None,
        "Phase9LocalSyntheticToken constructor signature drifted",
    )
    require(
        re.search(
            r'ERC20\s*\(\s*"Unified Phase 9 Local Synthetic Unit"\s*,\s*"P9UNIT"\s*\)',
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken metadata is not the neutral frozen fixture metadata",
    )
    require(
        re.search(
            r"uint256\s+public\s+constant\s+FIXED_SUPPLY_UNITS\s*=\s*"
            r"1_000_000_000_000_000\s*;",
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken fixed supply declaration drifted",
    )
    require(
        re.search(r"block\.chainid\s*!=\s*31337", token_source) is not None,
        "Phase9LocalSyntheticToken does not reject non-local chains",
    )
    require(
        re.search(r"fixtureAllocator\s*==\s*address\s*\(\s*0\s*\)", token_source)
        is not None,
        "Phase9LocalSyntheticToken does not reject the zero fixture allocator",
    )
    decimals_match = re.search(
        r"function\s+decimals\s*\(\s*\)\s+public\s+(?:pure|view)\s+override\s+"
        r"returns\s*\(\s*uint8\s*\)\s*\{\s*return\s+6\s*;\s*\}",
        token_source,
    )
    require(decimals_match is not None, "Phase9LocalSyntheticToken decimals drifted")
    require(
        token_source.count("_mint(") == 1
        and re.search(
            r"_mint\s*\(\s*fixtureAllocator\s*,\s*FIXED_SUPPLY_UNITS\s*\)",
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken must mint the fixed supply exactly once",
    )
    require(
        token_source.lower().count("mint") == 1
        and "burn" not in token_source.lower()
        and "role" not in token_source.lower(),
        "Phase9LocalSyntheticToken exposes mint, burn, or role semantics",
    )
    exposed_functions = set(
        re.findall(
            r"function\s+([A-Za-z_]\w*)\s*\([^)]*\)[^{;]*(?:public|external)",
            token_source,
        )
    )
    require(
        exposed_functions == {"decimals"},
        "Phase9LocalSyntheticToken exposes unexpected functions: "
        + ", ".join(sorted(exposed_functions - {"decimals"})),
    )
    require(
        token_source.count("constructor") == 1
        and len(re.findall(r"\bpublic\b", token_source)) == 2
        and re.search(r"\bexternal\b", token_source) is None,
        "Phase9LocalSyntheticToken exposes state or behavior beyond the frozen ABI",
    )
    prohibited_code = (
        "Phase8LocalSyntheticToken",
        "WrappedUFT",
        "UnifiedToken",
        "AccessControl",
        "Ownable",
        "Pausable",
        "ERC20Burnable",
        "ERC20Permit",
        "UUPS",
        "_burn(",
        "admin",
        "owner",
        "operator",
        "USD",
        "fiat",
        "peg",
        "redeem",
        "backing",
        "exchangeRate",
        "marketValue",
        "paymentClaim",
        "legalTender",
        "providerObligation",
    )
    present = [token for token in prohibited_code if token.lower() in token_source.lower()]
    compact_code = re.sub(r"[^a-z0-9]", "", token_source.lower())
    prohibited_value_semantics = (
        "denomination",
        "fiat",
        "usdpeg",
        "redemption",
        "backing",
        "exchangerate",
        "marketvalue",
        "paymentclaim",
        "legaltender",
        "providerobligation",
    )
    present.extend(
        token
        for token in prohibited_value_semantics
        if token in compact_code and token not in present
    )
    require(
        not present,
        "Phase9LocalSyntheticToken contains prohibited authority or value semantics: "
        + ", ".join(present),
    )


def check_phase9_local_token_evidence(smoke_scripts: list[Path]) -> None:
    deploy_script = read(PHASE9_DEPLOY_SCRIPT_PATH)
    require_tokens(
        deploy_script,
        (
            "contract DeployPhase9Local",
            "new Phase9LocalSyntheticToken",
            "block.chainid",
            "31337",
        ),
        "Phase 9 local token deployment",
    )

    smoke = combined_text(smoke_scripts)
    require_tokens(
        smoke,
        (
            "DeployPhase9Local",
            "Phase9LocalSyntheticToken",
            "check-phase9-release-evidence",
        ),
        "Phase 9 local smoke token evidence",
    )

    reset = read(ROOT / "scripts/local-reset.ps1")
    require_tokens(
        reset,
        ("phase9", "Phase9LocalSyntheticToken", "phase9-release-evidence"),
        "Phase 9 local reset token cleanup",
    )

    release_checker = read(PHASE9_RELEASE_CHECK_PATH)
    require_tokens(
        release_checker,
        (
            "Phase9LocalSyntheticToken",
            RELEASE_MANIFEST_PATH,
            "eth_getCode",
            "balanceOf",
            "totalSupply",
        ),
        "Phase 9 release-evidence token validation",
    )
    release_declarations = combined_text(
        (PHASE9_RELEASE_SCHEMA_PATH, PHASE9_RELEASE_DOC_PATH)
    )
    require_tokens(
        release_declarations,
        ("Phase9LocalSyntheticToken", RELEASE_MANIFEST_PATH, "post-reset"),
        "Phase 9 release-evidence token declarations",
    )


def check_pre_code_freeze(by_id: dict[str, dict[str, str]]) -> None:
    freeze_started = phase9_freeze_started()
    abi_done = by_id["UNI-ABI-009"]["status"] == "DONE"
    if freeze_started:
        require(
            abi_done,
            "UNI-ABI-009 must be DONE when any Phase 9 Solidity source or "
            "ProtocolCompilation import exists",
        )
    if not abi_done and not freeze_started:
        return

    imports = phase9_compilation_imports()
    check_phase9_abi_pairs(imports)
    check_phase9_storage_layouts()
    check_phase9_formatting_scope(imports)
    check_phase9_contract_size_coverage()
    check_phase9_local_token_source(imports)


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

    phase9_tests = list((ROOT / "protocol/test").glob("*Phase9*.t.sol"))
    require(bool(phase9_tests), "Phase 9 Foundry tests are missing")

    smoke_scripts = [
        path
        for path in (ROOT / "scripts").glob("*phase9*")
        if "smoke" in path.name.lower() and path.suffix.lower() in {".ps1", ".sh"}
    ]
    require(bool(smoke_scripts), "Phase 9 local smoke script is missing")
    check_phase9_local_token_evidence(smoke_scripts)

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
    backlog = check_backlog(require_implementation, args.require_exit_complete)
    check_boundary_declarations()
    check_workstream_ownership()
    check_production_prohibitions()
    check_no_stale_phase17_recovery()
    check_boundary_evidence()
    check_pre_code_freeze(backlog)

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
