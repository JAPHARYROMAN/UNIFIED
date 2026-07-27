"""Validate layered Phase 9 implementation checkpoints over the immutable freeze."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import shutil
import subprocess
import tomllib
from copy import deepcopy
from pathlib import Path
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[1]
BASELINE_MANIFEST_PATH = ROOT / "protocol/compatibility/phase9-manifest.json"
CHECKPOINT_PATH = ROOT / "protocol/compatibility/phase9-implementation-checkpoints.json"
BACKLOG_PATH = ROOT / "docs/backlog/phase-9.csv"
SECURITY_REVIEW_ROOT = ROOT / "security/reviews"
BASELINE_REVIEW_PATH = SECURITY_REVIEW_ROOT / "phase-9-interface-freeze.md"

BASELINE_COMMIT = "4f01a5692df92c435ff8893840ebdcca055449f0"
BASELINE_MANIFEST_SHA256 = "sha256:9237acd53b00f5e90d77bbd4f5ce09590ddb750d079c333be4b14d8e7b4238a2"
BASELINE_SOURCE_SET_SHA256 = (
    "sha256:a40ac90f75c52fc7583651d2d57d2a4d82f1899ed673be8b460d17fb7b7425cb"
)
BASELINE_RAW_FREEZE_ARTIFACTS_SHA256 = (
    "sha256:b0d494141f0e229cf9fd542401036cd63ba04de73e2f056c1e89a25253cdb1a3"
)
PAYOFF_ACCEPTED_PACKAGE_SHA256 = (
    "sha256:5c5696120704f77edd5cc7fe256cd745e226cc1b33c1b9c01c7cc8250c185545"
)
SOLC_AST_TYPE_SUFFIX_PATTERN = re.compile(
    r"(t_(?:contract|enum|struct|userDefinedValueType)\([^()]+\))\d+"
)
PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS = (
    ".gitattributes",
    ".github/workflows/foundation.yml",
    ".mise.toml",
    "adr/0020-phase-9-payoff-authority-and-implementation-activation.md",
    "apps/foundation-console/src/index.ts",
    "apps/foundation-console/src/phase9PayoffReferenceGolden.ts",
    "docs/architecture/phase-9-payoff-deployment-evidence.md",
    "docs/architecture/phase-9-payoff-quote-acceptance.md",
    "docs/architecture/phase-9-payoff-reference-evidence.md",
    "infrastructure/local/phase9-payoff-deployment-candidate.schema.json",
    "infrastructure/local/phase9-payoff-deployment-code-hashes.json",
    "infrastructure/local/phase9-payoff-deployment-evidence.schema.json",
    "models/foundation_model/src/unified_foundation/phase9_payoff_reference.py",
    "models/foundation_model/tests/test_phase9_payoff_reference.py",
    "package.json",
    "packages/phase9/typescript/payoffReference.ts",
    "pnpm-lock.yaml",
    "protocol/foundry.toml",
    "protocol/script/DeployPhase9Local.s.sol",
    "protocol/src/ProtocolCompilation.sol",
    "protocol/test/Phase9InterfaceFreeze.t.sol",
    "protocol/test/Phase9PayoffLocalDeploymentEvidence.t.sol",
    "protocol/test/Phase9PayoffQuote.t.sol",
    "protocol/test/Phase9PayoffQuoteAcceptanceMap.sol",
    "protocol/test/Phase9PayoffQuoteDeployment.t.sol",
    "protocol/test/Phase9PayoffQuoteFuzz.t.sol",
    "protocol/test/Phase9PayoffQuoteGolden.t.sol",
    "protocol/test/Phase9PayoffQuoteHarness.sol",
    "protocol/test/Phase9PayoffQuoteInvariants.t.sol",
    "pyproject.toml",
    "scripts/check-contract-sizes.py",
    "scripts/check-foundation.ps1",
    "scripts/prepare-foundry.ps1",
    "tools/check_phase9.py",
    "tools/check_phase9_implementation_checkpoints.py",
    "tools/check_phase9_storage_layouts.py",
    "tools/compile_phase9_storage_layouts.mjs",
    "tools/tests/test_phase9_compatibility.py",
    "tools/tests/test_phase9_implementation_checkpoints.py",
    "tools/tests/test_phase9_payoff_deployment_evidence_schema.py",
    "tools/tests/test_phase9_warning_policy.mjs",
    "tools/tests/test_update_phase9_implementation_checkpoint.py",
    "tools/update_phase9_implementation_checkpoint.py",
    "tools/verify_phase9_payoff_deployment.py",
    "tsconfig.json",
    "uv.lock",
)
HISTORICAL_PAYOFF_ARCHIVE_PATHS = (
    "docs/architecture/phase-9-payoff-deployment-evidence.md",
    "infrastructure/local/phase9-payoff-deployment-candidate.schema.json",
    "infrastructure/local/phase9-payoff-deployment-code-hashes.json",
    "infrastructure/local/phase9-payoff-deployment-evidence.schema.json",
    "protocol/script/DeployPhase9Local.s.sol",
    "protocol/test/Phase9PayoffLocalDeploymentEvidence.t.sol",
    "tools/verify_phase9_payoff_deployment.py",
)
REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS = (
    ".gitattributes",
    ".github/workflows/foundation.yml",
    ".mise.toml",
    "adr/0021-phase-9-atomic-refinance-authority-and-activation.md",
    "adr/0022-phase-9-factory-account-position-bootstrap-semantics.md",
    "adr/0023-phase-9-refinance-fixed-module-partition.md",
    "adr/0024-phase-9-refinance-activation-topology-control.md",
    "docs/architecture/phase-9-data-layouts.md",
    "docs/architecture/phase-9-refinance-acceptance.md",
    "docs/architecture/phase-9-refinance-deployment-evidence.md",
    "docs/architecture/phase-9-refinance-reference-evidence.md",
    "docs/architecture/phase-9-resolution-protection-recovery.md",
    "protocol/foundry.toml",
    "protocol/src/ProtocolCompilation.sol",
    "protocol/test/Phase9InterfaceFreeze.t.sol",
    "protocol/test/Phase9RefinanceBootstrapAcceptanceMap.sol",
    "protocol/test/Phase9RefinanceBootstrapHarness.sol",
    "protocol/test/Phase9RefinanceCustodyLienBootstrap.t.sol",
    "protocol/test/Phase9RefinanceFactoryBootstrap.t.sol",
    "protocol/test/Phase9RefinanceRequest.t.sol",
    "protocol/test/Phase9RefinanceRequestFuzz.t.sol",
    "protocol/test/Phase9RefinanceRequestGolden.t.sol",
    "protocol/test/Phase9RefinanceRequestInvariants.t.sol",
    "scripts/check-contract-sizes.py",
    "scripts/check-foundation.ps1",
    "scripts/prepare-foundry.ps1",
    "tools/check_abi.py",
    "tools/check_phase9.py",
    "tools/check_phase9_implementation_checkpoints.py",
    "tools/check_phase9_local_prohibitions.py",
    "tools/check_phase9_refinance_linked_modules.py",
    "tools/check_phase9_storage_layouts.py",
    "tools/compile_phase9_storage_layouts.mjs",
    "tools/tests/test_phase9_compatibility.py",
    "tools/tests/test_phase9_implementation_checkpoints.py",
    "tools/tests/test_phase9_local_prohibitions.py",
    "tools/tests/test_phase9_refinance_linked_modules.py",
    "tools/tests/test_phase9_warning_policy.mjs",
    "tools/tests/test_update_phase9_implementation_checkpoint.py",
    "tools/update_phase9_implementation_checkpoint.py",
)
IMPLEMENTATION_EVIDENCE_PATHS = {
    "CollateralCustodyV2": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    "LienRegistry": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    "PayoffQuoteEngine": PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS,
    "Phase9LoanAccount": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    "Phase9LoanFactory": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    "PositionManagerV2": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    "RefinanceCoordinator": REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
}

# D1 has exact reviewed artifact names. D2-D4 currently have stage scopes only, so
# emitting the refinance package remains forbidden until those exact paths are added.
IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS = {
    "P9-REFI-001": "D2-D4 exact implementation evidence paths are not frozen",
}

PAYOFF_ACTIVATED_SIGNATURES = (
    "consumeQuote(bytes32,bytes32,uint64,bytes32)",
    "invalidateQuote(bytes32,bytes32)",
    "issueQuote(bytes32,uint64)",
)
REFINANCE_ACTIVATED_SIGNATURES = {
    "Phase9LoanFactory": (
        "createLoan((bytes32,uint64,bytes32,(address,address,address,bytes32,address,address,address,address,address,address,address,address,address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32),bytes32))",
    ),
    "Phase9LoanAccount": (
        "activateReplacementLoan(bytes32,(uint8,uint8,uint64,uint64,uint64,uint64,uint64,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bytes32,bytes32),bytes32)",
        "initialize((address,address,address,bytes32,address,address,address,address,address,address,address,address,address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32),(uint8,uint8,uint64,uint64,uint64,uint64,uint64,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bytes32,bytes32))",
        "recordRefinancePayoff(bytes32,uint256,bytes32)",
    ),
    "CollateralCustodyV2": (
        "recordCustody((bytes32,bytes32,address,address,uint256,uint8,bytes32),bytes32)",
    ),
    "LienRegistry": (
        "beginHandoff(bytes32,bytes32,bytes32,uint64)",
        "completeHandoff(bytes32,bytes32)",
        "registerLien((bytes32,address,address,bytes32,uint256,address,bytes32,uint64,uint8,bytes32,bytes32))",
    ),
    "RefinanceCoordinator": (
        "cancelRefinance(bytes32,bytes32)",
        "executeRefinance(bytes32,bytes32)",
        "recordFundingCommitment((bytes32,bytes32,bytes32,bytes32,address,uint256,uint64,bytes32,uint8,bytes32))",
        "refundCommitment(bytes32,bytes32)",
        "requestRefinance((bytes32,bytes32,bytes32,address,address,address,bytes32,bytes32,uint256,uint256,bytes32,bytes32,uint64,bytes32,bytes32,uint256,uint256,uint256,uint64,uint64,bytes32,uint64,uint8,uint64,uint256,uint32,bytes32))",
    ),
    "PositionManagerV2": (
        "initialize(bytes32,address,address)",
        "issuePosition((bytes32,bytes32,address,uint256,uint256,uint8))",
        "registerTranche((bytes32,uint32,uint256,uint256,bytes32))",
    ),
}
REFINANCE_STATE_TRANSITIONED_EVENT = {
    "anonymous": False,
    "inputs": [
        {"indexed": True, "internalType": "bytes32", "name": "refinanceId", "type": "bytes32"},
        {
            "indexed": True,
            "internalType": "enum Phase9Types.RefinanceState",
            "name": "previousState",
            "type": "uint8",
        },
        {
            "indexed": True,
            "internalType": "enum Phase9Types.RefinanceState",
            "name": "nextState",
            "type": "uint8",
        },
        {"indexed": False, "internalType": "uint64", "name": "stateVersion", "type": "uint64"},
        {"indexed": False, "internalType": "bytes32", "name": "operationId", "type": "bytes32"},
        {"indexed": False, "internalType": "bytes32", "name": "evidenceHash", "type": "bytes32"},
    ],
    "name": "RefinanceStateTransitioned",
    "type": "event",
}
REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR = {
    "inputs": [
        {
            "internalType": "bytes32",
            "name": "commitmentId",
            "type": "bytes32",
        }
    ],
    "name": "UnknownFundingCommitment",
    "type": "error",
}
REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR = {
    "inputs": [
        {
            "internalType": "bytes32",
            "name": "handoffId",
            "type": "bytes32",
        }
    ],
    "name": "UnknownLienHandoff",
    "type": "error",
}
REFINANCE_COORDINATOR_ABI_ADDITIONS = (
    REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR,
    REFINANCE_STATE_TRANSITIONED_EVENT,
)
LIEN_REGISTRY_ABI_ADDITIONS = (REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR,)
REFINANCE_AUXILIARY_SOURCE_OWNERS = (
    ("protocol/src/interfaces/phase9/ILienRegistry.sol", "LienRegistry"),
    (
        "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
        "RefinanceCoordinator",
    ),
)
PACKAGE_AUXILIARY_SOURCE_OWNERS = {
    "P9-REFI-001": REFINANCE_AUXILIARY_SOURCE_OWNERS,
}
ACTIVATION_PACKAGES = {
    "P9-PAYOFF-001": {
        "abiAdditions": {},
        "requiredBacklogIds": ("UNI-ADR-015", "UNI-PAYOFF-001"),
        "contracts": {"PayoffQuoteEngine": PAYOFF_ACTIVATED_SIGNATURES},
    },
    # Provisional only. Absence from the checkpoint registry keeps every signature frozen.
    "P9-REFI-001": {
        "abiAdditions": {
            "LienRegistry": LIEN_REGISTRY_ABI_ADDITIONS,
            "RefinanceCoordinator": REFINANCE_COORDINATOR_ABI_ADDITIONS,
        },
        "requiredBacklogIds": (
            "UNI-ADR-016",
            "UNI-ADR-017",
            "UNI-ADR-018",
            "UNI-ADR-019",
            "UNI-REFI-001",
            "UNI-REFI-002",
        ),
        "contracts": REFINANCE_ACTIVATED_SIGNATURES,
    },
}

# Bind every source that decides checkpoint activation, ABI/storage/schema compatibility,
# generated-schema freshness, warning exemptions, or foundation-gate orchestration.
CONTROL_BUNDLE_PATHS = (
    "buf.gen.yaml",
    "buf.yaml",
    "protocol/foundry.toml",
    "scripts/check-foundation.ps1",
    "scripts/generate.ps1",
    "tools/check_abi.py",
    "tools/check_phase9.py",
    "tools/check_phase9_implementation_checkpoints.py",
    "tools/check_phase9_local_prohibitions.py",
    "tools/check_phase9_refinance_linked_modules.py",
    "tools/check_phase9_schema.py",
    "tools/check_phase9_storage_layouts.py",
    "tools/compile_phase9_storage_layouts.mjs",
    "tools/tests/test_phase9_compatibility.py",
    "tools/tests/test_phase9_implementation_checkpoints.py",
    "tools/tests/test_phase9_local_prohibitions.py",
    "tools/tests/test_phase9_refinance_linked_modules.py",
    "tools/tests/test_phase9_schema.py",
    "tools/tests/test_phase9_warning_policy.mjs",
    "tools/tests/test_update_phase9_implementation_checkpoint.py",
    "tools/update_phase9_implementation_checkpoint.py",
)

# Prepared Foundry dependencies under protocol/lib are intentionally excluded from Git.
# Their exact installed bytes remain covered by dependencyClosureSha256. The candidate
# commit instead binds the pinned package inputs and the only script that materializes
# those bytes, in addition to every repository-tracked source in the closure.
REVIEWED_COMMIT_PROVENANCE_PATHS = (
    ".gitattributes",
    ".github/workflows/foundation.yml",
    ".mise.toml",
    "package.json",
    "pnpm-lock.yaml",
    "protocol/foundry.toml",
    "protocol/src/ProtocolCompilation.sol",
    "pyproject.toml",
    "scripts/check-contract-sizes.py",
    "scripts/prepare-foundry.ps1",
    "tsconfig.json",
    "uv.lock",
)
PREPARED_DEPENDENCY_PREFIXES = ("protocol/lib/",)

SOURCE_ROOTS = (
    ROOT / "protocol/src/interfaces/phase9",
    ROOT / "protocol/src/resolution",
    ROOT / "protocol/src/protection",
    ROOT / "protocol/src/recovery",
)
TOKEN_SOURCE = ROOT / "protocol/src/token/Phase9LocalSyntheticToken.sol"
HASH_PATTERN = re.compile(r"sha256:[0-9a-f]{64}\Z")
BACKLOG_PATTERN = re.compile(r"UNI-[A-Z0-9]+(?:-[A-Z0-9]+)+\Z")

EXPECTED_ROOT_KEYS = {
    "baseline",
    "currentControlBundleSha256",
    "currentSourceSetSha256",
    "packages",
    "schemaVersion",
}
EXPECTED_BASELINE_KEYS = {
    "commit",
    "manifestSha256",
    "rawFreezeArtifactsSha256",
    "sourceSetSha256",
}
EXPECTED_PACKAGE_KEYS = {
    "checkpointId",
    "requiredBacklogIds",
    "review",
    "revisions",
}
EXPECTED_REVIEW_KEYS = {
    "architectureReviewer",
    "implementationAuthor",
    "reviewPath",
    "reviewSha256",
    "reviewedCommit",
    "securityReviewer",
    "status",
    "toolingReviewer",
}
EXPECTED_REVISION_KEYS = {
    "abiSha256",
    "activatedSignatures",
    "contract",
    "dependencyClosureSha256",
    "implementationEvidenceBundleSha256",
    "revision",
    "sourceSha256",
    "sourceSetSha256",
    "storageStructuralSha256",
    "supersedes",
}
EXPECTED_SUPERSEDES_KEYS = {"checkpointId", "revision"}


def canonical_json(payload: object) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def sha256_payload(payload: object) -> str:
    return "sha256:" + hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        content = path.read_bytes()
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    return "sha256:" + hashlib.sha256(content).hexdigest()


def sha256_bytes(content: bytes) -> str:
    return "sha256:" + hashlib.sha256(content).hexdigest()


def canonical_abi_type(parameter: object) -> str:
    if not isinstance(parameter, dict) or not isinstance(parameter.get("type"), str):
        raise SystemExit("Phase 9 ABI contains a malformed parameter")
    parameter_type = cast(str, parameter["type"])
    if not parameter_type.startswith("tuple"):
        return parameter_type
    components = parameter.get("components")
    if not isinstance(components, list):
        raise SystemExit("Phase 9 ABI tuple parameter lacks components")
    suffix = parameter_type[len("tuple") :]
    return "(" + ",".join(canonical_abi_type(component) for component in components) + ")" + suffix


def canonical_mutator_signatures(abi_path: Path) -> tuple[str, ...]:
    payload = read_json(abi_path)
    if not isinstance(payload, list):
        raise SystemExit(f"{abi_path.relative_to(ROOT)} must contain a JSON array")
    signatures: list[str] = []
    for item in payload:
        if (
            not isinstance(item, dict)
            or item.get("type") != "function"
            or item.get("stateMutability") not in {"nonpayable", "payable"}
        ):
            continue
        name = item.get("name")
        inputs = item.get("inputs")
        if not isinstance(name, str) or not isinstance(inputs, list):
            raise SystemExit("Phase 9 ABI contains a malformed mutating function")
        signatures.append(name + "(" + ",".join(canonical_abi_type(item) for item in inputs) + ")")
    if len(signatures) != len(set(signatures)):
        raise SystemExit(f"{abi_path.relative_to(ROOT)} contains duplicate mutator signatures")
    return tuple(sorted(signatures, key=lambda value: value.encode("utf-8")))


def abi_item_identity(item: object) -> str:
    if not isinstance(item, dict) or not isinstance(item.get("type"), str):
        raise SystemExit("Phase 9 ABI contains a malformed item")
    item_type = cast(str, item["type"])
    name = item.get("name", "")
    inputs = item.get("inputs", [])
    if not isinstance(name, str) or not isinstance(inputs, list):
        raise SystemExit("Phase 9 ABI contains a malformed named item")
    signature = name + "(" + ",".join(canonical_abi_type(value) for value in inputs) + ")"
    return item_type + ":" + signature


def abi_sort_key(item: object) -> tuple[int, bytes]:
    if not isinstance(item, dict):
        raise SystemExit("Phase 9 ABI contains a malformed item")
    item_type = item.get("type")
    order = {"constructor": 0, "error": 1, "event": 2, "function": 3}
    if item_type not in order:
        raise SystemExit(f"Phase 9 ABI contains an unsupported item type: {item_type}")
    return order[cast(str, item_type)], abi_item_identity(item).encode("utf-8")


def additive_abi_payload(
    baseline_payload: object, additions: tuple[dict[str, Any], ...]
) -> list[Any]:
    if not isinstance(baseline_payload, list):
        raise SystemExit("Phase 9 baseline ABI must contain a JSON array")
    payload = deepcopy(baseline_payload)
    identities = {abi_item_identity(item) for item in payload}
    if len(identities) != len(payload):
        raise SystemExit("Phase 9 baseline ABI contains duplicate canonical items")
    for addition in additions:
        if addition.get("type") not in {"error", "event"}:
            raise SystemExit("Phase 9 additive ABI allowlist may contain errors and events only")
        identity = abi_item_identity(addition)
        if identity in identities:
            raise SystemExit(f"Phase 9 additive ABI item is duplicated: {identity}")
        identities.add(identity)
        payload.append(deepcopy(addition))
    return sorted(payload, key=abi_sort_key)


def control_bundle_paths() -> list[Path]:
    if len(CONTROL_BUNDLE_PATHS) != len(set(CONTROL_BUNDLE_PATHS)):
        raise SystemExit("Phase 9 control bundle contains duplicate paths")
    if list(CONTROL_BUNDLE_PATHS) != sorted(
        CONTROL_BUNDLE_PATHS, key=lambda value: value.encode("utf-8")
    ):
        raise SystemExit("Phase 9 control bundle paths are not ordinal")
    paths = [ROOT / relative for relative in CONTROL_BUNDLE_PATHS]
    for path in paths:
        if not path.is_file():
            raise SystemExit(
                f"Phase 9 control bundle input is missing: {path.relative_to(ROOT).as_posix()}"
            )
    return paths


def current_control_bundle_hash() -> str:
    paths = control_bundle_paths()
    require_git_clean_worktree_bytes("Phase9ControlBundle", paths)
    return sha256_payload(
        [{"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)} for path in paths]
    )


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is not valid JSON: {exc}") from exc


def validate_foundation_orchestration(path: Path | None = None) -> None:
    """Keep historical payoff verification out of the active foundation gate."""
    foundation_path = ROOT / "scripts/check-foundation.ps1" if path is None else path
    try:
        foundation = foundation_path.read_text(encoding="utf-8").replace("\\", "/")
    except FileNotFoundError as exc:
        raise SystemExit("scripts/check-foundation.ps1 is missing") from exc
    if "verify_phase9_payoff_deployment.py" in foundation:
        raise SystemExit(
            "foundation invokes the historical payoff deployment verifier as a current gate"
        )
    for invocation in (
        "tools/check_phase9.py",
        "tools/check_phase9_implementation_checkpoints.py",
    ):
        if foundation.count(invocation) != 1:
            raise SystemExit(f"foundation current Phase 9 invocation drifted: {invocation}")


def validate_historical_payoff_archive() -> None:
    """Preserve the accessible files whose exact reviewed bytes remain in Git history."""
    evidence_paths = set(PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS)
    for relative in HISTORICAL_PAYOFF_ARCHIVE_PATHS:
        if relative not in evidence_paths:
            raise SystemExit(f"historical payoff evidence path is unbound: {relative}")
        if not (ROOT / relative).is_file():
            raise SystemExit(f"historical payoff evidence path is missing: {relative}")


def historical_manifest() -> dict[str, Any]:
    payload = read_json(BASELINE_MANIFEST_PATH)
    if not isinstance(payload, dict):
        raise SystemExit("Phase 9 baseline manifest must contain a JSON object")
    manifest = cast(dict[str, Any], payload)
    if manifest.get("schemaVersion") != 2:
        raise SystemExit("Phase 9 baseline manifest schema drifted")
    if sha256_payload(manifest) != BASELINE_MANIFEST_SHA256:
        raise SystemExit("Phase 9 baseline manifest identity drifted")
    sources = manifest.get("sources")
    if not isinstance(sources, list) or sha256_payload(sources) != BASELINE_SOURCE_SET_SHA256:
        raise SystemExit("Phase 9 baseline source-set identity drifted")
    verify_raw_freeze_artifacts(manifest)
    return manifest


def normalize_solc_storage_type_id(type_id: str) -> str:
    """Remove only unstable AST IDs from concrete Solidity storage type identifiers."""

    return SOLC_AST_TYPE_SUFFIX_PATTERN.sub(r"\1<ast-id>", type_id)


def normalized_storage_layout(storage_layout: object) -> dict[str, Any]:
    """Normalize AST suffixes across a complete storage type graph, failing on ambiguity."""

    if not isinstance(storage_layout, dict):
        raise SystemExit("Phase 9 storage payload lacks storageLayout")
    raw_storage = storage_layout.get("storage")
    raw_types = storage_layout.get("types")
    if not isinstance(raw_storage, list) or not isinstance(raw_types, dict):
        raise SystemExit("Phase 9 storage payload has an incomplete storageLayout graph")

    normalized_types: dict[str, Any] = {}
    original_type_ids: dict[str, str] = {}
    for raw_type_id, raw_description in raw_types.items():
        if not isinstance(raw_type_id, str) or not isinstance(raw_description, dict):
            raise SystemExit("Phase 9 storage payload has a malformed type graph")
        normalized_type_id = normalize_solc_storage_type_id(raw_type_id)
        previous = original_type_ids.get(normalized_type_id)
        if previous is not None:
            raise SystemExit(
                "Phase 9 storage type normalization collision: "
                f"{previous} and {raw_type_id} normalize to {normalized_type_id}"
            )
        original_type_ids[normalized_type_id] = raw_type_id

        description = deepcopy(raw_description)
        for reference_field in ("base", "key", "value"):
            if reference_field not in description:
                continue
            reference = description[reference_field]
            if not isinstance(reference, str) or reference not in raw_types:
                raise SystemExit(
                    f"Phase 9 storage type {raw_type_id} has an invalid {reference_field} reference"
                )
            description[reference_field] = normalize_solc_storage_type_id(reference)

        if "members" in description:
            members = description["members"]
            if not isinstance(members, list):
                raise SystemExit(f"Phase 9 storage type {raw_type_id} has malformed members")
            normalized_members: list[dict[str, Any]] = []
            for index, raw_member in enumerate(members):
                if not isinstance(raw_member, dict):
                    raise SystemExit(
                        f"Phase 9 storage type {raw_type_id} member {index} is malformed"
                    )
                member_type = raw_member.get("type")
                if not isinstance(member_type, str) or member_type not in raw_types:
                    raise SystemExit(
                        f"Phase 9 storage type {raw_type_id} member {index} has an invalid type"
                    )
                member = deepcopy(raw_member)
                member["type"] = normalize_solc_storage_type_id(member_type)
                normalized_members.append(member)
            description["members"] = normalized_members
        normalized_types[normalized_type_id] = description

    normalized_storage: list[dict[str, Any]] = []
    for index, raw_entry in enumerate(raw_storage):
        if not isinstance(raw_entry, dict):
            raise SystemExit(f"Phase 9 storage entry {index} is malformed")
        entry_type = raw_entry.get("type")
        if not isinstance(entry_type, str) or entry_type not in raw_types:
            raise SystemExit(f"Phase 9 storage entry {index} has an invalid type")
        entry = deepcopy(raw_entry)
        entry["type"] = normalize_solc_storage_type_id(entry_type)
        normalized_storage.append(entry)

    normalized = deepcopy(storage_layout)
    normalized["storage"] = normalized_storage
    normalized["types"] = normalized_types
    return normalized


def normalized_storage_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Normalize type IDs while retaining every other storage and freeze field exactly."""

    normalized = deepcopy(payload)
    normalized["storageLayout"] = normalized_storage_layout(normalized.get("storageLayout"))
    return normalized


def structural_storage_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Retain exact storage evidence while excluding functions and unstable AST suffixes."""

    structural = normalized_storage_payload(payload)
    freeze_surface = structural.get("freezeSurface")
    if not isinstance(freeze_surface, dict):
        raise SystemExit("Phase 9 storage payload lacks freezeSurface")
    state_variables = freeze_surface.get("stateVariables")
    if not isinstance(state_variables, list):
        raise SystemExit("Phase 9 storage payload lacks freezeSurface state variables")
    structural["freezeSurface"] = {"stateVariables": state_variables}
    return structural


def structural_storage_hash(payload: dict[str, Any]) -> str:
    return sha256_payload(structural_storage_payload(payload))


def baseline_contracts(manifest: dict[str, Any]) -> tuple[list[str], dict[str, dict[str, str]]]:
    raw_contracts = manifest.get("contracts")
    if not isinstance(raw_contracts, list):
        raise SystemExit("Phase 9 baseline manifest contracts are malformed")
    order: list[str] = []
    contracts: dict[str, dict[str, str]] = {}
    for raw_entry in raw_contracts:
        if not isinstance(raw_entry, dict):
            raise SystemExit("Phase 9 baseline manifest contract entry is malformed")
        required = {
            "abiPath",
            "abiSha256",
            "contract",
            "sourcePath",
            "sourceSha256",
            "storagePath",
            "storageSha256",
        }
        if set(raw_entry) != required or not all(
            isinstance(raw_entry[field], str) for field in required
        ):
            raise SystemExit("Phase 9 baseline manifest contract fields drifted")
        entry = cast(dict[str, str], raw_entry)
        contract = entry["contract"]
        if contract in contracts:
            raise SystemExit(f"Phase 9 baseline contract is duplicated: {contract}")
        order.append(contract)
        contracts[contract] = entry
    return order, contracts


def baseline_sources(manifest: dict[str, Any]) -> tuple[list[str], dict[str, str]]:
    raw_sources = manifest.get("sources")
    if not isinstance(raw_sources, list):
        raise SystemExit("Phase 9 baseline manifest sources are malformed")
    order: list[str] = []
    sources: dict[str, str] = {}
    for raw_source in raw_sources:
        if (
            not isinstance(raw_source, dict)
            or set(raw_source) != {"path", "sha256"}
            or not isinstance(raw_source["path"], str)
            or not isinstance(raw_source["sha256"], str)
        ):
            raise SystemExit("Phase 9 baseline source entry is malformed")
        path = raw_source["path"]
        digest = raw_source["sha256"]
        if path in sources or HASH_PATTERN.fullmatch(digest) is None:
            raise SystemExit(f"Phase 9 baseline source entry drifted: {path}")
        order.append(path)
        sources[path] = digest
    return order, sources


def package_auxiliary_source_owners(
    checkpoint_id: str,
    source_order: list[str],
    contracts: dict[str, dict[str, str]],
    activated_contracts: dict[str, tuple[str, ...]],
) -> tuple[tuple[str, str], ...]:
    """Return the exact reviewed non-contract sources owned by an activation package."""

    raw_entries = PACKAGE_AUXILIARY_SOURCE_OWNERS.get(checkpoint_id, ())
    if not isinstance(raw_entries, tuple) or any(
        not isinstance(entry, tuple)
        or len(entry) != 2
        or not all(isinstance(value, str) for value in entry)
        for entry in raw_entries
    ):
        raise SystemExit(f"{checkpoint_id}: auxiliary source ownership is malformed")

    entries = cast(tuple[tuple[str, str], ...], raw_entries)
    paths = [path for path, _owner in entries]
    if len(paths) != len(set(paths)):
        raise SystemExit(f"{checkpoint_id}: auxiliary source path is duplicated")
    if paths != sorted(paths, key=lambda value: value.encode("utf-8")):
        raise SystemExit(f"{checkpoint_id}: auxiliary source paths are not ordinal")

    baseline_paths = set(source_order)
    activated_source_paths = {
        contracts[contract]["sourcePath"]
        for contract in activated_contracts
        if contract in contracts
    }
    dependency_paths_by_owner: dict[str, set[str]] = {}
    for path, owner in entries:
        if path not in baseline_paths:
            raise SystemExit(f"{checkpoint_id}: auxiliary source is not in the baseline: {path}")
        if path in activated_source_paths:
            raise SystemExit(
                f"{checkpoint_id}: auxiliary source overlaps an activated contract: {path}"
            )
        if owner not in activated_contracts or owner not in contracts:
            raise SystemExit(f"{checkpoint_id}: auxiliary source owner is not activated: {owner}")
        dependencies = dependency_paths_by_owner.get(owner)
        if dependencies is None:
            source_path = ROOT / contracts[owner]["sourcePath"]
            dependencies = {
                dependency.relative_to(ROOT).as_posix()
                for dependency in repository_solidity_dependency_paths(source_path)
            }
            dependency_paths_by_owner[owner] = dependencies
        if path not in dependencies:
            raise SystemExit(
                f"{checkpoint_id}: auxiliary source is not a dependency of {owner}: {path}"
            )
    return entries


def raw_freeze_artifact_paths(manifest: dict[str, Any]) -> list[Path]:
    """Return every historical freeze artifact in deterministic repository-relative order."""
    _, contracts = baseline_contracts(manifest)
    expected_abis = {ROOT / entry["abiPath"] for entry in contracts.values()}
    expected_storage = {ROOT / entry["storagePath"] for entry in contracts.values()}
    actual_abis = set((ROOT / "protocol/abi/phase9").glob("*.json"))
    actual_storage = set((ROOT / "protocol/storage-layout/phase9").glob("*.json"))
    if actual_abis != expected_abis:
        raise SystemExit("Phase 9 historical ABI snapshot file set drifted")
    if actual_storage != expected_storage:
        raise SystemExit("Phase 9 historical storage snapshot file set drifted")
    paths = {
        BASELINE_MANIFEST_PATH,
        BASELINE_REVIEW_PATH,
        *expected_abis,
        *expected_storage,
    }
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def raw_freeze_artifacts_hash(manifest: dict[str, Any]) -> str:
    payload = [
        {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)}
        for path in raw_freeze_artifact_paths(manifest)
    ]
    return sha256_payload(payload)


def verify_raw_freeze_artifacts(manifest: dict[str, Any]) -> None:
    if raw_freeze_artifacts_hash(manifest) != BASELINE_RAW_FREEZE_ARTIFACTS_SHA256:
        raise SystemExit("Phase 9 historical freeze artifact bytes drifted")


def solidity_identifier_character(character: str) -> bool:
    return character.isascii() and (character.isalnum() or character in "_$")


def skip_solidity_comment(source: str, index: int) -> int | None:
    if source.startswith("//", index):
        line_ends = [
            position
            for marker in ("\r", "\n")
            if (position := source.find(marker, index + 2)) != -1
        ]
        if not line_ends:
            return len(source)
        end = min(line_ends)
        return end + 2 if source.startswith("\r\n", end) else end + 1
    if source.startswith("/*", index):
        end = source.find("*/", index + 2)
        if end == -1:
            raise SystemExit("Solidity dependency source has an unterminated block comment")
        return end + 2
    return None


def read_solidity_string(source: str, index: int) -> tuple[str, int]:
    quote = source[index]
    cursor = index + 1
    characters: list[str] = []
    while cursor < len(source):
        character = source[cursor]
        if character == "\\":
            if cursor + 1 >= len(source):
                raise SystemExit("Solidity dependency source has an unterminated string escape")
            characters.extend((character, source[cursor + 1]))
            cursor += 2
            continue
        if character == quote:
            return "".join(characters), cursor + 1
        characters.append(character)
        cursor += 1
    raise SystemExit("Solidity dependency source has an unterminated string")


def read_solidity_import(source: str, index: int) -> tuple[str, int]:
    cursor = index
    import_path: str | None = None
    while cursor < len(source):
        comment_end = skip_solidity_comment(source, cursor)
        if comment_end is not None:
            cursor = comment_end
            continue
        character = source[cursor]
        if character in "\"'":
            value, cursor = read_solidity_string(source, cursor)
            if import_path is not None:
                raise SystemExit("Solidity import directive contains multiple string literals")
            if "\\" in value:
                raise SystemExit("Escaped Solidity import paths are not supported")
            import_path = value
            continue
        if character == ";":
            if import_path is None:
                raise SystemExit("Solidity import directive lacks a path")
            return import_path, cursor + 1
        cursor += 1
    raise SystemExit("Solidity import directive is unterminated")


def solidity_imports_from_source(source: str) -> tuple[str, ...]:
    imports: list[str] = []
    cursor = 0
    while cursor < len(source):
        comment_end = skip_solidity_comment(source, cursor)
        if comment_end is not None:
            cursor = comment_end
            continue
        character = source[cursor]
        if character in "\"'":
            _, cursor = read_solidity_string(source, cursor)
            continue
        if solidity_identifier_character(character):
            start = cursor
            while cursor < len(source) and solidity_identifier_character(source[cursor]):
                cursor += 1
            if source[start:cursor] == "import":
                import_path, cursor = read_solidity_import(source, cursor)
                imports.append(import_path)
            continue
        cursor += 1
    return tuple(imports)


def solidity_imports(path: Path) -> tuple[str, ...]:
    try:
        source = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    return solidity_imports_from_source(source)


def ordinal_utf8_path_key(path: Path) -> bytes:
    return path.relative_to(ROOT).as_posix().encode("utf-8")


def implementation_evidence_bundle_paths(contract: str) -> list[Path]:
    relative_paths = IMPLEMENTATION_EVIDENCE_PATHS.get(contract)
    if relative_paths is None:
        raise SystemExit(f"{contract}: implementation evidence bundle is not activated")
    if len(set(relative_paths)) != len(relative_paths):
        raise SystemExit(f"{contract}: implementation evidence bundle contains duplicate paths")
    encoded_paths = [path.encode("utf-8") for path in relative_paths]
    if encoded_paths != sorted(encoded_paths):
        raise SystemExit(f"{contract}: implementation evidence bundle paths are not ordinal")
    paths: list[Path] = []
    for relative_path in relative_paths:
        path = (ROOT / relative_path).resolve()
        try:
            path.relative_to(ROOT.resolve())
        except ValueError:
            raise SystemExit(
                f"{contract}: implementation evidence path is outside the repository: "
                f"{relative_path}"
            ) from None
        if not path.is_file():
            raise SystemExit(f"{contract}: implementation evidence is missing: {relative_path}")
        paths.append(path)
    return paths


def implementation_evidence_bundle_hash(contract: str) -> str:
    paths = implementation_evidence_bundle_paths(contract)
    require_git_clean_worktree_bytes(contract, paths)
    payload = [
        {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)} for path in paths
    ]
    return sha256_payload(payload)


def foundry_remappings() -> tuple[tuple[str, Path], ...]:
    config_path = ROOT / "protocol/foundry.toml"
    try:
        with config_path.open("rb") as handle:
            config = tomllib.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit("protocol/foundry.toml is missing") from exc
    profile = config.get("profile")
    default = profile.get("default") if isinstance(profile, dict) else None
    raw_remappings = default.get("remappings") if isinstance(default, dict) else None
    if not isinstance(raw_remappings, list):
        raise SystemExit("Foundry remappings are missing or malformed")

    parsed: dict[str, Path] = {}
    for raw_remapping in raw_remappings:
        if not isinstance(raw_remapping, str):
            raise SystemExit("Foundry remapping entry is not a string")
        prefix, separator, target = raw_remapping.partition("=")
        if separator != "=" or not prefix or not target or prefix in parsed:
            raise SystemExit(f"Foundry remapping entry is malformed: {raw_remapping}")
        target_path = (config_path.parent / target).resolve()
        try:
            target_path.relative_to(ROOT.resolve())
        except ValueError:
            raise SystemExit(
                f"Foundry remapping target is outside the repository: {raw_remapping}"
            ) from None
        parsed[prefix] = target_path
    return tuple(sorted(parsed.items(), key=lambda item: (-len(item[0]), item[0].encode("utf-8"))))


def repository_import_path(source_path: Path, import_path: str) -> Path:
    candidates: tuple[Path, ...]
    if import_path.startswith("."):
        candidates = (source_path.parent / import_path,)
    else:
        matching_remappings = [
            (prefix, target)
            for prefix, target in foundry_remappings()
            if import_path.startswith(prefix)
        ]
        if matching_remappings:
            prefix, target = matching_remappings[0]
            if not target.is_dir():
                raise SystemExit(
                    f"Prepared Foundry remapping target is missing: {target.relative_to(ROOT)}"
                )
            candidates = (target / import_path[len(prefix) :],)
        else:
            candidates = (ROOT / import_path, ROOT / "protocol/src" / import_path)
    for candidate in candidates:
        resolved = candidate.resolve()
        try:
            resolved.relative_to(ROOT.resolve())
        except ValueError:
            if import_path.startswith("."):
                raise SystemExit(
                    f"{source_path.relative_to(ROOT)} imports outside the repository: {import_path}"
                ) from None
            continue
        if resolved.is_file():
            if resolved.suffix.lower() != ".sol":
                raise SystemExit(
                    f"{source_path.relative_to(ROOT)} imports a non-Solidity repository file: "
                    f"{import_path}"
                )
            return resolved
    import_kind = (
        "repository" if import_path.startswith((".", "protocol/", "src/")) else "non-relative"
    )
    raise SystemExit(
        f"{source_path.relative_to(ROOT)} has an unresolved {import_kind} import: {import_path}"
    )


def repository_solidity_dependency_paths(source_path: Path) -> list[Path]:
    root_source = source_path.resolve()
    try:
        root_source.relative_to(ROOT.resolve())
    except ValueError as exc:
        raise SystemExit("Phase 9 implementation source is outside the repository") from exc
    pending = [root_source]
    observed: set[Path] = set()
    while pending:
        current = pending.pop()
        if current in observed:
            continue
        observed.add(current)
        for import_path in solidity_imports(current):
            dependency = repository_import_path(current, import_path)
            if dependency not in observed:
                pending.append(dependency)
    return sorted(observed, key=ordinal_utf8_path_key)


def repository_solidity_dependency_hash(source_path: Path) -> str:
    payload = [
        {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)}
        for path in repository_solidity_dependency_paths(source_path)
    ]
    return sha256_payload(payload)


def reviewed_commit_required_paths(
    contract: str, manifest: dict[str, Any], source_path: Path
) -> list[Path]:
    """Return every current file that the cited implementation commit must contain."""

    source_order, _ = baseline_sources(manifest)
    paths = set(implementation_evidence_bundle_paths(contract))
    paths.update(ROOT / relative for relative in source_order)
    for dependency in repository_solidity_dependency_paths(source_path):
        relative = dependency.relative_to(ROOT).as_posix()
        if not relative.startswith(PREPARED_DEPENDENCY_PREFIXES):
            paths.add(dependency)
    paths.update(ROOT / relative for relative in REVIEWED_COMMIT_PROVENANCE_PATHS)

    for path in paths:
        try:
            path.relative_to(ROOT)
        except ValueError:
            raise SystemExit(
                f"{contract}: reviewed commit path is outside the repository: {path}"
            ) from None
        if not path.is_file():
            raise SystemExit(
                f"{contract}: reviewed commit input is missing: {path.relative_to(ROOT).as_posix()}"
            )
    return sorted(paths, key=ordinal_utf8_path_key)


def run_git_bytes(
    arguments: tuple[str, ...], *, input_bytes: bytes | None = None
) -> subprocess.CompletedProcess[bytes]:
    """Run a read-only Git object query from the repository root."""

    git_executable = shutil.which("git")
    if git_executable is None:
        raise SystemExit("Git is required to validate the reviewed implementation commit")
    try:
        return subprocess.run(  # noqa: S603 - argument vector is never evaluated by a shell
            (git_executable, *arguments),
            cwd=ROOT,
            capture_output=True,
            check=False,
            input=input_bytes,
        )
    except OSError as exc:
        raise SystemExit("Git is required to validate the reviewed implementation commit") from exc


def git_hash_paths(contract: str, relative_paths: tuple[str, ...], *, clean: bool) -> list[str]:
    """Hash a path set in one Git process, with or without clean filters."""

    if any("\n" in path or "\r" in path for path in relative_paths):
        raise SystemExit(f"{contract}: reviewed input path contains a line break")
    arguments = ["hash-object", "--stdin-paths"]
    if not clean:
        arguments.append("--no-filters")
    path_input = ("\n".join(relative_paths) + "\n").encode("utf-8")
    result = run_git_bytes(tuple(arguments), input_bytes=path_input)
    digests = result.stdout.decode("ascii", errors="replace").splitlines()
    if (
        result.returncode != 0
        or len(digests) != len(relative_paths)
        or any(re.fullmatch(r"[0-9a-f]{40}", digest) is None for digest in digests)
    ):
        raise SystemExit(f"{contract}: Git cannot hash reviewed input paths")
    return digests


def require_git_clean_worktree_bytes(contract: str, paths: list[Path]) -> None:
    """Reject worktree bytes that Git clean filters would rewrite before committing."""

    relative_paths = tuple(path.relative_to(ROOT).as_posix() for path in paths)
    raw_digests = git_hash_paths(contract, relative_paths, clean=False)
    clean_digests = git_hash_paths(contract, relative_paths, clean=True)
    for relative_path, raw_digest, clean_digest in zip(
        relative_paths, raw_digests, clean_digests, strict=True
    ):
        if raw_digest != clean_digest:
            raise SystemExit(
                f"{contract}: worktree bytes differ from Git-clean canonical bytes: {relative_path}"
            )


def reviewed_commit_file_bytes(
    contract: str, commit: str, relative_paths: tuple[str, ...]
) -> dict[str, bytes]:
    """Read required blobs from an exact commit, failing closed on any missing object."""

    commit_result = run_git_bytes(("cat-file", "-e", f"{commit}^{{commit}}"))
    if commit_result.returncode != 0:
        raise SystemExit(f"{contract}: reviewed commit does not exist: {commit}")

    blobs: dict[str, bytes] = {}
    for relative_path in relative_paths:
        result = run_git_bytes(("cat-file", "blob", f"{commit}:{relative_path}"))
        if result.returncode != 0:
            raise SystemExit(f"{contract}: reviewed commit lacks required path: {relative_path}")
        blobs[relative_path] = result.stdout
    return blobs


def historical_source_set_hash(contract: str, commit: str, manifest: dict[str, Any]) -> str:
    source_order, _ = baseline_sources(manifest)
    blobs = reviewed_commit_file_bytes(contract, commit, tuple(source_order))
    return sha256_payload(
        [{"path": relative, "sha256": sha256_bytes(blobs[relative])} for relative in source_order]
    )


def historical_evidence_bundle_hash(contract: str, commit: str) -> str:
    relative_paths = IMPLEMENTATION_EVIDENCE_PATHS.get(contract)
    if relative_paths is None:
        raise SystemExit(f"{contract}: implementation evidence bundle is not activated")
    if len(relative_paths) != len(set(relative_paths)):
        raise SystemExit(f"{contract}: implementation evidence bundle contains duplicate paths")
    if list(relative_paths) != sorted(relative_paths, key=lambda value: value.encode("utf-8")):
        raise SystemExit(f"{contract}: implementation evidence bundle paths are not ordinal")
    blobs = reviewed_commit_file_bytes(contract, commit, relative_paths)
    return sha256_payload(
        [{"path": relative, "sha256": sha256_bytes(blobs[relative])} for relative in relative_paths]
    )


def validate_reviewed_commit_paths(contract: str, commit: str, paths: list[Path]) -> None:
    """Prove current path bytes are byte-identical to blobs in the cited commit."""

    relative_paths = tuple(path.relative_to(ROOT).as_posix() for path in paths)
    committed = reviewed_commit_file_bytes(contract, commit, relative_paths)
    for path, relative_path in zip(paths, relative_paths, strict=True):
        if path.read_bytes() != committed[relative_path]:
            raise SystemExit(
                f"{contract}: reviewed input differs from reviewed commit: {relative_path}"
            )


def validate_reviewed_commit_binding(
    contract: str, commit: str, manifest: dict[str, Any], source_path: Path
) -> None:
    """Bind every reviewed current input to the exact cited candidate commit."""

    validate_reviewed_commit_paths(
        contract,
        commit,
        reviewed_commit_required_paths(contract, manifest, source_path),
    )


def ordered_source_set_hash(order: list[str], sources: dict[str, str]) -> str:
    return sha256_payload([{"path": path, "sha256": sources[path]} for path in order])


def current_reviewed_source_set_hash(manifest: dict[str, Any] | None = None) -> str:
    baseline = historical_manifest() if manifest is None else manifest
    order, _ = baseline_sources(baseline)
    return sha256_payload([{"path": path, "sha256": sha256_file(ROOT / path)} for path in order])


def current_source_paths() -> set[str]:
    paths = {path.resolve() for source_root in SOURCE_ROOTS for path in source_root.rglob("*.sol")}
    paths.add(TOKEN_SOURCE.resolve())
    return {path.relative_to(ROOT).as_posix() for path in paths}


def backlog_statuses() -> dict[str, str]:
    try:
        with BACKLOG_PATH.open(encoding="utf-8", newline="") as handle:
            rows = list(csv.DictReader(handle))
    except FileNotFoundError as exc:
        raise SystemExit("docs/backlog/phase-9.csv is missing") from exc
    result: dict[str, str] = {}
    for row in rows:
        identifier = row.get("id", "")
        status = row.get("status", "")
        if identifier in result:
            raise SystemExit(f"Phase 9 backlog identifier is duplicated: {identifier}")
        result[identifier] = status
    return result


def review_content(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc


def normalized_review(content: str) -> str:
    return re.sub(r"\s+", " ", content).strip().lower()


def review_field_occurrences(content: str, label: str) -> int:
    return len(
        re.findall(
            rf"\b{re.escape(label)}[ \t*_`]*:",
            content,
            flags=re.IGNORECASE,
        )
    )


def review_status_occurrences(content: str, label: str) -> int:
    field_pattern = re.compile(
        rf"\b{re.escape(label)}[ \t*_`]*:",
        flags=re.IGNORECASE,
    )
    prose_pattern = re.compile(
        rf"\b{re.escape(label)}\b[ \t*_`]*(?:[-=][ \t*_`]*|"
        rf"[ \t]+(?:is|was|remains)[ \t]+)(?:PASS|FAIL|PENDING|BLOCKED)\b",
        flags=re.IGNORECASE,
    )
    spans = {
        match.span()
        for pattern in (field_pattern, prose_pattern)
        for match in pattern.finditer(content)
    }
    return len(spans)


def visible_review_lines(content: str) -> tuple[str, ...]:
    lines: list[str] = []
    fence: str | None = None
    in_html_comment = False
    for line in content.splitlines():
        if in_html_comment:
            if "-->" in line:
                in_html_comment = False
            continue
        if "<!--" in line:
            if "-->" not in line.split("<!--", 1)[1]:
                in_html_comment = True
            continue
        fence_match = re.match(r"^[ \t]{0,3}(?P<marker>`{3,}|~{3,})", line)
        if fence_match is not None:
            marker = fence_match.group("marker")[0]
            if fence is None:
                fence = marker
            elif fence == marker:
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return tuple(lines)


def require_unambiguous_review_pass(contract: str, content: str) -> dict[str, str]:
    visible_lines = visible_review_lines(content)
    for label in ("Decision", "Architecture review", "Security review"):
        canonical = f"{label}: PASS"
        if visible_lines.count(canonical) != 1 or review_status_occurrences(content, label) != 1:
            raise SystemExit(
                f"{contract}: implementation review must contain exactly one visible canonical "
                f"{canonical} and no other {label} status occurrence"
            )

    metadata: dict[str, str] = {}
    fields = (
        ("Implementation author", "implementationAuthor"),
        ("Architecture reviewer", "architectureReviewer"),
        ("Security reviewer", "securityReviewer"),
        ("Tooling reviewer", "toolingReviewer"),
        ("Reviewed commit", "reviewedCommit"),
    )
    for label, entry_field in fields:
        pattern = re.compile(rf"{re.escape(label)}: (?P<value>\S(?:.*\S)?)")
        matches = [
            match.group("value")
            for line in visible_lines
            if (match := pattern.fullmatch(line)) is not None
        ]
        if len(matches) != 1 or review_field_occurrences(content, label) != 1:
            raise SystemExit(
                f"{contract}: implementation review must contain exactly one visible canonical "
                f"{label} field"
            )
        metadata[entry_field] = matches[0]

    identities = (
        metadata["implementationAuthor"],
        metadata["architectureReviewer"],
        metadata["securityReviewer"],
        metadata["toolingReviewer"],
    )
    if len({identity.casefold() for identity in identities}) != len(identities):
        raise SystemExit(f"{contract}: implementation author and reviewers must all be distinct")
    if re.fullmatch(r"[0-9a-f]{40}", metadata["reviewedCommit"]) is None:
        raise SystemExit(f"{contract}: reviewed commit must be exact lowercase 40-hex")
    return metadata


def validate_review_path(relative: str) -> Path:
    candidate = (ROOT / relative).resolve()
    review_root = SECURITY_REVIEW_ROOT.resolve()
    if (
        not relative.replace("\\", "/").startswith("security/reviews/")
        or candidate.suffix.lower() != ".md"
        or candidate.parent != review_root
    ):
        raise SystemExit("Phase 9 implementation review path is outside security/reviews")
    return candidate


def checkpoint_payload() -> dict[str, Any]:
    payload = read_json(CHECKPOINT_PATH)
    if not isinstance(payload, dict):
        raise SystemExit("Phase 9 implementation checkpoint registry must be a JSON object")
    registry = cast(dict[str, Any], payload)
    if set(registry) != EXPECTED_ROOT_KEYS or registry.get("schemaVersion") != 2:
        raise SystemExit("Phase 9 implementation checkpoint registry schema drifted")
    baseline = registry.get("baseline")
    if not isinstance(baseline, dict) or set(baseline) != EXPECTED_BASELINE_KEYS:
        raise SystemExit("Phase 9 implementation checkpoint baseline is malformed")
    expected_baseline = {
        "commit": BASELINE_COMMIT,
        "manifestSha256": BASELINE_MANIFEST_SHA256,
        "rawFreezeArtifactsSha256": BASELINE_RAW_FREEZE_ARTIFACTS_SHA256,
        "sourceSetSha256": BASELINE_SOURCE_SET_SHA256,
    }
    if baseline != expected_baseline:
        raise SystemExit("Phase 9 implementation checkpoint baseline identity drifted")
    if not isinstance(registry.get("packages"), list):
        raise SystemExit("Phase 9 checkpoint packages must be a JSON array")
    for field in ("currentControlBundleSha256", "currentSourceSetSha256"):
        value = registry.get(field)
        if not isinstance(value, str) or HASH_PATTERN.fullmatch(value) is None:
            raise SystemExit(f"Phase 9 {field} is malformed")
    return registry


def validate_checkpoints(
    *,
    manifest: dict[str, Any] | None = None,
    registry: dict[str, Any] | None = None,
    verify_current: bool = True,
    verify_reviews: bool = True,
    verify_backlog: bool = True,
) -> dict[str, dict[str, Any]]:
    baseline = historical_manifest() if manifest is None else manifest
    checkpoints = checkpoint_payload() if registry is None else registry
    if set(checkpoints) != EXPECTED_ROOT_KEYS or checkpoints.get("schemaVersion") != 2:
        raise SystemExit("Phase 9 implementation checkpoint registry schema drifted")
    expected_baseline = {
        "commit": BASELINE_COMMIT,
        "manifestSha256": BASELINE_MANIFEST_SHA256,
        "rawFreezeArtifactsSha256": BASELINE_RAW_FREEZE_ARTIFACTS_SHA256,
        "sourceSetSha256": BASELINE_SOURCE_SET_SHA256,
    }
    if checkpoints.get("baseline") != expected_baseline:
        raise SystemExit("Phase 9 implementation checkpoint baseline identity drifted")

    contract_order, contracts = baseline_contracts(baseline)
    source_order, sources = baseline_sources(baseline)
    production_order = [name for name in contract_order if name != "Phase9LocalSyntheticToken"]
    raw_packages = checkpoints.get("packages")
    if not isinstance(raw_packages, list):
        raise SystemExit("Phase 9 checkpoint packages must be a JSON array")

    latest_revisions: dict[str, dict[str, Any]] = {}
    latest_origins: dict[str, tuple[str, int]] = {}
    observed_packages: list[str] = []
    effective_sources = dict(sources)
    effective_abis = {
        contract: read_json(ROOT / contract_entry["abiPath"])
        for contract, contract_entry in contracts.items()
    }
    statuses = backlog_statuses() if verify_backlog else {}
    for raw_package in raw_packages:
        if not isinstance(raw_package, dict) or set(raw_package) != EXPECTED_PACKAGE_KEYS:
            raise SystemExit("Phase 9 checkpoint package fields drifted")
        checkpoint_id = raw_package.get("checkpointId")
        if not isinstance(checkpoint_id, str) or checkpoint_id not in ACTIVATION_PACKAGES:
            raise SystemExit("Phase 9 checkpoint package is not activated")
        if checkpoint_id in observed_packages:
            raise SystemExit(f"Phase 9 checkpoint package is duplicated: {checkpoint_id}")
        observed_packages.append(checkpoint_id)
        package_definition = ACTIVATION_PACKAGES[checkpoint_id]

        closure_limitation = IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS.get(checkpoint_id)
        if closure_limitation is not None:
            raise SystemExit(
                f"{checkpoint_id}: implementation evidence closure is incomplete: "
                f"{closure_limitation}"
            )

        if (
            checkpoint_id == "P9-PAYOFF-001"
            and sha256_payload(raw_package) != PAYOFF_ACCEPTED_PACKAGE_SHA256
        ):
            raise SystemExit("P9-PAYOFF-001: accepted package identity drifted")

        required_backlogs = raw_package.get("requiredBacklogIds")
        expected_backlogs = package_definition["requiredBacklogIds"]
        if not isinstance(required_backlogs, list) or tuple(required_backlogs) != expected_backlogs:
            raise SystemExit(f"{checkpoint_id}: required backlog IDs drifted")
        if any(
            not isinstance(identifier, str) or BACKLOG_PATTERN.fullmatch(identifier) is None
            for identifier in required_backlogs
        ):
            raise SystemExit(f"{checkpoint_id}: required backlog ID is malformed")
        if verify_backlog:
            incomplete = [
                identifier for identifier in required_backlogs if statuses.get(identifier) != "DONE"
            ]
            if incomplete:
                raise SystemExit(
                    f"{checkpoint_id}: required checkpoint backlogs are not DONE: {incomplete}"
                )

        review = raw_package.get("review")
        if (
            not isinstance(review, dict)
            or set(review) != EXPECTED_REVIEW_KEYS
            or not all(isinstance(value, str) for value in review.values())
        ):
            raise SystemExit(f"{checkpoint_id}: review identity fields drifted")
        if review["status"] != "PASS" or HASH_PATTERN.fullmatch(review["reviewSha256"]) is None:
            raise SystemExit(f"{checkpoint_id}: review status or hash is malformed")
        identities = (
            review["implementationAuthor"],
            review["architectureReviewer"],
            review["securityReviewer"],
            review["toolingReviewer"],
        )
        if any(not identity.strip() for identity in identities) or len(
            {identity.casefold() for identity in identities}
        ) != len(identities):
            raise SystemExit(
                f"{checkpoint_id}: implementation author and reviewers must be distinct"
            )
        reviewed_commit = review["reviewedCommit"]
        if re.fullmatch(r"[0-9a-f]{40}", reviewed_commit) is None:
            raise SystemExit(f"{checkpoint_id}: reviewed commit must be exact lowercase 40-hex")

        raw_revisions = raw_package.get("revisions")
        expected_contracts = cast(dict[str, tuple[str, ...]], package_definition["contracts"])
        auxiliary_source_owners = package_auxiliary_source_owners(
            checkpoint_id,
            source_order,
            contracts,
            expected_contracts,
        )
        abi_additions = cast(
            dict[str, tuple[dict[str, Any], ...]], package_definition["abiAdditions"]
        )
        if not set(abi_additions) <= set(expected_contracts):
            raise SystemExit(f"{checkpoint_id}: ABI addition names an unactivated contract")
        if not isinstance(raw_revisions, list) or not raw_revisions:
            raise SystemExit(f"{checkpoint_id}: contract revisions are missing")
        package_contracts: list[str] = []
        package_revisions: list[dict[str, Any]] = []
        package_sources = dict(effective_sources)
        package_abis = dict(effective_abis)
        for raw_revision in raw_revisions:
            if not isinstance(raw_revision, dict) or set(raw_revision) != EXPECTED_REVISION_KEYS:
                raise SystemExit(f"{checkpoint_id}: contract revision fields drifted")
            revision = cast(dict[str, Any], raw_revision)
            contract = revision.get("contract")
            if not isinstance(contract, str) or contract not in production_order:
                raise SystemExit(f"{checkpoint_id}: contract revision names an unknown contract")
            if contract not in expected_contracts or contract in package_contracts:
                raise SystemExit(f"{checkpoint_id}: contract revision set drifted: {contract}")
            package_contracts.append(contract)
            package_revisions.append(revision)

            activated = revision.get("activatedSignatures")
            expected_activated = expected_contracts[contract]
            if not isinstance(activated, list) or tuple(activated) != expected_activated:
                raise SystemExit(f"{checkpoint_id}/{contract}: activated signature set drifted")
            canonical_mutators = canonical_mutator_signatures(ROOT / contracts[contract]["abiPath"])
            if not set(activated) <= set(canonical_mutators):
                raise SystemExit(
                    f"{checkpoint_id}/{contract}: activated signature is not canonical"
                )

            prior = latest_revisions.get(contract)
            expected_revision = 1 if prior is None else cast(int, prior["revision"]) + 1
            if revision.get("revision") != expected_revision:
                raise SystemExit(f"{checkpoint_id}/{contract}: revision is not monotonic")
            supersedes = revision.get("supersedes")
            if prior is None:
                if supersedes is not None:
                    raise SystemExit(f"{checkpoint_id}/{contract}: first revision cannot supersede")
            else:
                previous_checkpoint, previous_revision = latest_origins[contract]
                expected_supersedes = {
                    "checkpointId": previous_checkpoint,
                    "revision": previous_revision,
                }
                if supersedes != expected_supersedes:
                    raise SystemExit(f"{checkpoint_id}/{contract}: supersession chain drifted")
                if not set(cast(list[str], prior["activatedSignatures"])) <= set(activated):
                    raise SystemExit(f"{checkpoint_id}/{contract}: activation is not monotonic")

            for field in (
                "abiSha256",
                "dependencyClosureSha256",
                "implementationEvidenceBundleSha256",
                "sourceSha256",
                "sourceSetSha256",
                "storageStructuralSha256",
            ):
                value = revision.get(field)
                if not isinstance(value, str) or HASH_PATTERN.fullmatch(value) is None:
                    raise SystemExit(f"{checkpoint_id}/{contract}: {field} is malformed")

            contract_baseline = contracts[contract]
            expected_abi = additive_abi_payload(
                effective_abis[contract], abi_additions.get(contract, ())
            )
            expected_abi_hash = sha256_payload(expected_abi)
            if revision["abiSha256"] != expected_abi_hash:
                raise SystemExit(
                    f"{checkpoint_id}/{contract}: ABI differs from the additive allowlist"
                )
            package_abis[contract] = expected_abi
            source_relative = contract_baseline["sourcePath"]
            if revision["sourceSha256"] == effective_sources[source_relative]:
                raise SystemExit(f"{checkpoint_id}/{contract}: revision does not change source")
            committed_source = reviewed_commit_file_bytes(
                contract, reviewed_commit, (source_relative,)
            )[source_relative]
            if sha256_bytes(committed_source) != revision["sourceSha256"]:
                raise SystemExit(
                    f"{checkpoint_id}/{contract}: source hash differs from reviewed Git blob"
                )
            if (
                historical_evidence_bundle_hash(contract, reviewed_commit)
                != revision["implementationEvidenceBundleSha256"]
            ):
                raise SystemExit(
                    f"{checkpoint_id}/{contract}: evidence hash differs from reviewed Git blobs"
                )

            storage_payload = read_json(ROOT / contract_baseline["storagePath"])
            if not isinstance(storage_payload, dict):
                raise SystemExit(f"{contract}: baseline storage snapshot is malformed")
            expected_storage_hash = structural_storage_hash(cast(dict[str, Any], storage_payload))
            if revision["storageStructuralSha256"] != expected_storage_hash:
                raise SystemExit(
                    f"{checkpoint_id}/{contract}: storage differs from the freeze baseline"
                )
            package_sources[source_relative] = cast(str, revision["sourceSha256"])

        auxiliary_paths = tuple(path for path, _owner in auxiliary_source_owners)
        if auxiliary_paths:
            committed_auxiliary_sources = reviewed_commit_file_bytes(
                checkpoint_id,
                reviewed_commit,
                auxiliary_paths,
            )
            for auxiliary_path in auxiliary_paths:
                auxiliary_hash = sha256_bytes(committed_auxiliary_sources[auxiliary_path])
                if auxiliary_hash == effective_sources[auxiliary_path]:
                    raise SystemExit(
                        f"{checkpoint_id}: auxiliary source does not change: {auxiliary_path}"
                    )
                package_sources[auxiliary_path] = auxiliary_hash

        expected_contract_order = [name for name in production_order if name in expected_contracts]
        if package_contracts != expected_contract_order:
            raise SystemExit(f"{checkpoint_id}: contract revisions are not in baseline order")
        expected_package_source_set = ordered_source_set_hash(source_order, package_sources)
        historical_package_source_set = historical_source_set_hash(
            checkpoint_id, reviewed_commit, baseline
        )
        if historical_package_source_set != expected_package_source_set:
            raise SystemExit(f"{checkpoint_id}: reviewed Git source set is inconsistent")
        for revision in package_revisions:
            if revision["sourceSetSha256"] != expected_package_source_set:
                raise SystemExit(
                    f"{checkpoint_id}/{revision['contract']}: source-set checkpoint is stale"
                )

        if verify_reviews:
            review_path = validate_review_path(cast(str, review["reviewPath"]))
            if sha256_file(review_path) != review["reviewSha256"]:
                raise SystemExit(f"{checkpoint_id}: implementation review hash is stale")
            content = review_content(review_path)
            metadata = require_unambiguous_review_pass(checkpoint_id, content)
            for field, value in metadata.items():
                if review[field] != value:
                    raise SystemExit(f"{checkpoint_id}: implementation review {field} mismatch")
            normalized = normalized_review(content)
            historical_payoff = checkpoint_id == "P9-PAYOFF-001"
            required_tokens: list[str] = (
                [] if historical_payoff else [checkpoint_id, *required_backlogs]
            )
            for revision in package_revisions:
                required_tokens.extend(
                    (
                        cast(str, revision["contract"]),
                        "UNI-PAYOFF-001" if historical_payoff else "",
                        *(
                            []
                            if historical_payoff
                            else cast(list[str], revision["activatedSignatures"])
                        ),
                        cast(str, revision["sourceSha256"]),
                        cast(str, revision["sourceSetSha256"]),
                        cast(str, revision["dependencyClosureSha256"]),
                        cast(str, revision["implementationEvidenceBundleSha256"]),
                        cast(str, revision["abiSha256"]),
                        cast(str, revision["storageStructuralSha256"]),
                    )
                )
            if any(token and token.lower() not in normalized for token in required_tokens):
                raise SystemExit(
                    f"{checkpoint_id}: implementation review status or hashes mismatch"
                )

        effective_sources = package_sources
        effective_abis = package_abis
        for revision in package_revisions:
            contract = cast(str, revision["contract"])
            latest_revisions[contract] = revision
            latest_origins[contract] = (checkpoint_id, cast(int, revision["revision"]))

    expected_package_order = [
        checkpoint_id for checkpoint_id in ACTIVATION_PACKAGES if checkpoint_id in observed_packages
    ]
    if observed_packages != expected_package_order:
        raise SystemExit("Phase 9 checkpoint packages are not in canonical order")

    expected_current_source_set = ordered_source_set_hash(source_order, effective_sources)
    if checkpoints.get("currentSourceSetSha256") != expected_current_source_set:
        raise SystemExit("Phase 9 current implementation source-set hash is stale")

    if verify_current:
        if checkpoints.get("currentControlBundleSha256") != current_control_bundle_hash():
            raise SystemExit("Phase 9 current control-bundle hash is stale")
        actual_paths = current_source_paths()
        expected_paths = set(source_order)
        if actual_paths != expected_paths:
            raise SystemExit(
                "Phase 9 reviewed Solidity source set drifted; missing="
                + ",".join(sorted(expected_paths - actual_paths))
                + "; unexpected="
                + ",".join(sorted(actual_paths - expected_paths))
            )
        for relative_source in source_order:
            expected_hash = effective_sources[relative_source]
            if sha256_file(ROOT / relative_source) != expected_hash:
                raise SystemExit(
                    f"{relative_source}: source changed without an exact implementation checkpoint"
                )

        if current_reviewed_source_set_hash(baseline) != expected_current_source_set:
            raise SystemExit("Phase 9 current reviewed source-set aggregate is stale")

        for contract, revision in latest_revisions.items():
            source_path = ROOT / contracts[contract]["sourcePath"]
            if sha256_file(source_path) != revision["sourceSha256"]:
                raise SystemExit(f"{contract}: latest reviewed implementation source hash is stale")
            if (
                repository_solidity_dependency_hash(source_path)
                != revision["dependencyClosureSha256"]
            ):
                raise SystemExit(f"{contract}: reviewed Solidity dependency closure hash is stale")

        for contract, contract_baseline in contracts.items():
            abi_payload = read_json(ROOT / contract_baseline["abiPath"])
            if sha256_payload(abi_payload) != contract_baseline["abiSha256"]:
                raise SystemExit(f"{contract}: ABI snapshot drifted from the freeze baseline")
            storage_payload = read_json(ROOT / contract_baseline["storagePath"])
            if sha256_payload(storage_payload) != contract_baseline["storageSha256"]:
                raise SystemExit(f"{contract}: storage snapshot drifted from the freeze baseline")

    return latest_revisions


def implemented_contracts() -> set[str]:
    return set(validate_checkpoints())


def activated_signatures() -> dict[str, frozenset[str]]:
    return {
        contract: frozenset(cast(list[str], revision["activatedSignatures"]))
        for contract, revision in validate_checkpoints().items()
    }


def main() -> None:
    validate_foundation_orchestration()
    validate_historical_payoff_archive()
    entries = validate_checkpoints()
    print(
        "Phase 9 implementation checkpoints passed "
        f"({len(entries)} implemented contracts; baseline {BASELINE_MANIFEST_SHA256})."
    )


if __name__ == "__main__":
    main()
