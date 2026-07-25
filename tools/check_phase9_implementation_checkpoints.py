"""Validate layered Phase 9 implementation checkpoints over the immutable freeze."""

from __future__ import annotations

import csv
import hashlib
import json
import re
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
ACTIVATION_BACKLOG_ID = "UNI-ADR-015"
ACTIVATED_IMPLEMENTATIONS = {"PayoffQuoteEngine": "UNI-PAYOFF-001"}

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
    "currentSourceSetSha256",
    "implementations",
    "schemaVersion",
}
EXPECTED_BASELINE_KEYS = {
    "commit",
    "manifestSha256",
    "rawFreezeArtifactsSha256",
    "sourceSetSha256",
}
EXPECTED_ENTRY_KEYS = {
    "abiSha256",
    "backlogId",
    "contract",
    "dependencyClosureSha256",
    "reviewPath",
    "reviewSha256",
    "sourceSha256",
    "sourceSetSha256",
    "status",
    "storageStructuralSha256",
}


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


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is not valid JSON: {exc}") from exc


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


def structural_storage_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Remove function-body evidence while retaining every storage-relevant field."""
    structural = deepcopy(payload)
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


def solidity_imports(path: Path) -> tuple[str, ...]:
    try:
        source = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source = re.sub(r"//[^\r\n]*", "", source)
    pattern = re.compile(
        r"\bimport\s+(?:[^;]*?\s+from\s+)?[\"'](?P<path>[^\"']+)[\"']"
        r"(?:\s+as\s+[A-Za-z_]\w*)?\s*;",
        flags=re.DOTALL,
    )
    return tuple(match.group("path") for match in pattern.finditer(source))


def repository_import_path(source_path: Path, import_path: str) -> Path | None:
    candidates = (
        (source_path.parent / import_path,)
        if import_path.startswith(".")
        else (ROOT / import_path, ROOT / "protocol/src" / import_path)
    )
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
    if import_path.startswith((".", "protocol/", "src/")):
        raise SystemExit(
            f"{source_path.relative_to(ROOT)} has an unresolved repository import: {import_path}"
        )
    return None


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
            if dependency is not None and dependency not in observed:
                pending.append(dependency)
    return sorted(observed, key=lambda path: path.relative_to(ROOT).as_posix())


def repository_solidity_dependency_hash(source_path: Path) -> str:
    payload = [
        {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)}
        for path in repository_solidity_dependency_paths(source_path)
    ]
    return sha256_payload(payload)


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


def normalized_review(path: Path) -> str:
    try:
        content = path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    return re.sub(r"\s+", " ", content).strip().lower()


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
    if set(registry) != EXPECTED_ROOT_KEYS or registry.get("schemaVersion") != 1:
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
    if not isinstance(registry.get("implementations"), list):
        raise SystemExit("Phase 9 implementation checkpoints must be a JSON array")
    current_source_set_hash = registry.get("currentSourceSetSha256")
    if (
        not isinstance(current_source_set_hash, str)
        or HASH_PATTERN.fullmatch(current_source_set_hash) is None
    ):
        raise SystemExit("Phase 9 current implementation source-set hash is malformed")
    return registry


def validate_checkpoints(
    *,
    manifest: dict[str, Any] | None = None,
    registry: dict[str, Any] | None = None,
    verify_current: bool = True,
    verify_reviews: bool = True,
    verify_backlog: bool = True,
) -> dict[str, dict[str, str]]:
    baseline = historical_manifest() if manifest is None else manifest
    checkpoints = checkpoint_payload() if registry is None else registry
    if set(checkpoints) != EXPECTED_ROOT_KEYS or checkpoints.get("schemaVersion") != 1:
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
    raw_entries = checkpoints.get("implementations")
    if not isinstance(raw_entries, list):
        raise SystemExit("Phase 9 implementation checkpoints must be a JSON array")

    entries: dict[str, dict[str, str]] = {}
    observed_order: list[str] = []
    effective_sources = dict(sources)
    statuses = backlog_statuses() if verify_backlog else {}
    if raw_entries and verify_backlog and statuses.get(ACTIVATION_BACKLOG_ID) != "DONE":
        raise SystemExit(f"{ACTIVATION_BACKLOG_ID} must be DONE before implementation checkpoints")

    for raw_entry in raw_entries:
        if not isinstance(raw_entry, dict) or set(raw_entry) != EXPECTED_ENTRY_KEYS:
            raise SystemExit("Phase 9 implementation checkpoint fields drifted")
        if not all(isinstance(value, str) for value in raw_entry.values()):
            raise SystemExit("Phase 9 implementation checkpoint values must be strings")
        entry = cast(dict[str, str], raw_entry)
        contract = entry["contract"]
        if contract not in production_order:
            raise SystemExit(
                f"Phase 9 implementation checkpoint names an unknown contract: {contract}"
            )
        if contract not in ACTIVATED_IMPLEMENTATIONS:
            raise SystemExit(f"{contract}: implementation checkpoint is not activated")
        if contract in entries:
            raise SystemExit(f"Phase 9 implementation checkpoint is duplicated: {contract}")
        observed_order.append(contract)
        entries[contract] = entry

        backlog_id = entry["backlogId"]
        if BACKLOG_PATTERN.fullmatch(backlog_id) is None:
            raise SystemExit(f"{contract}: implementation checkpoint backlog ID is malformed")
        if entry["status"] != "PASS":
            raise SystemExit(f"{contract}: implementation checkpoint status is not PASS")
        if backlog_id != ACTIVATED_IMPLEMENTATIONS[contract]:
            raise SystemExit(f"{contract}: implementation checkpoint backlog substitution")
        for field in (
            "abiSha256",
            "dependencyClosureSha256",
            "reviewSha256",
            "sourceSha256",
            "sourceSetSha256",
            "storageStructuralSha256",
        ):
            if HASH_PATTERN.fullmatch(entry[field]) is None:
                raise SystemExit(f"{contract}: implementation checkpoint {field} is malformed")

        contract_baseline = contracts[contract]
        if entry["abiSha256"] != contract_baseline["abiSha256"]:
            raise SystemExit(f"{contract}: implementation ABI differs from the freeze baseline")
        baseline_source_hash = sources[contract_baseline["sourcePath"]]
        if entry["sourceSha256"] == baseline_source_hash:
            raise SystemExit(f"{contract}: checkpoint does not activate an implementation change")
        effective_sources[contract_baseline["sourcePath"]] = entry["sourceSha256"]
        expected_checkpoint_source_set = ordered_source_set_hash(source_order, effective_sources)
        if entry["sourceSetSha256"] != expected_checkpoint_source_set:
            raise SystemExit(f"{contract}: implementation source-set checkpoint is stale")
        storage_payload = read_json(ROOT / contract_baseline["storagePath"])
        if not isinstance(storage_payload, dict):
            raise SystemExit(f"{contract}: baseline storage snapshot is malformed")
        expected_structural_hash = structural_storage_hash(cast(dict[str, Any], storage_payload))
        if entry["storageStructuralSha256"] != expected_structural_hash:
            raise SystemExit(f"{contract}: implementation storage differs from the freeze baseline")

        if verify_backlog and statuses.get(backlog_id) != "DONE":
            raise SystemExit(f"{contract}: checkpoint backlog {backlog_id} is not DONE")

        source_path = ROOT / contract_baseline["sourcePath"]
        if verify_current:
            if sha256_file(source_path) != entry["sourceSha256"]:
                raise SystemExit(f"{contract}: reviewed implementation source hash is stale")
            if repository_solidity_dependency_hash(source_path) != entry["dependencyClosureSha256"]:
                raise SystemExit(f"{contract}: reviewed Solidity dependency closure hash is stale")

        if verify_reviews:
            review_path = validate_review_path(entry["reviewPath"])
            if sha256_file(review_path) != entry["reviewSha256"]:
                raise SystemExit(f"{contract}: implementation review hash is stale")
            review = normalized_review(review_path)
            required_tokens = (
                "decision: pass",
                "architecture review: pass",
                "security review: pass",
                contract.lower(),
                backlog_id.lower(),
                entry["sourceSha256"],
                entry["sourceSetSha256"],
                entry["dependencyClosureSha256"],
                entry["abiSha256"],
                entry["storageStructuralSha256"],
            )
            if any(token.lower() not in review for token in required_tokens):
                raise SystemExit(f"{contract}: implementation review status or hashes mismatch")

    expected_entry_order = [name for name in production_order if name in entries]
    if observed_order != expected_entry_order:
        raise SystemExit("Phase 9 implementation checkpoints are not in baseline contract order")

    expected_current_source_set = ordered_source_set_hash(source_order, effective_sources)
    if checkpoints.get("currentSourceSetSha256") != expected_current_source_set:
        raise SystemExit("Phase 9 current implementation source-set hash is stale")

    if verify_current:
        actual_paths = current_source_paths()
        expected_paths = set(source_order)
        if actual_paths != expected_paths:
            raise SystemExit(
                "Phase 9 reviewed Solidity source set drifted; missing="
                + ",".join(sorted(expected_paths - actual_paths))
                + "; unexpected="
                + ",".join(sorted(actual_paths - expected_paths))
            )
        implemented_paths = {
            contracts[contract]["sourcePath"]: entry["sourceSha256"]
            for contract, entry in entries.items()
        }
        for relative_source in source_order:
            expected_hash = implemented_paths.get(relative_source, sources[relative_source])
            if sha256_file(ROOT / relative_source) != expected_hash:
                raise SystemExit(
                    f"{relative_source}: source changed without an exact implementation checkpoint"
                )

        if current_reviewed_source_set_hash(baseline) != expected_current_source_set:
            raise SystemExit("Phase 9 current reviewed source-set aggregate is stale")

        for contract, contract_baseline in contracts.items():
            abi_payload = read_json(ROOT / contract_baseline["abiPath"])
            if sha256_payload(abi_payload) != contract_baseline["abiSha256"]:
                raise SystemExit(f"{contract}: ABI snapshot drifted from the freeze baseline")
            storage_payload = read_json(ROOT / contract_baseline["storagePath"])
            if sha256_payload(storage_payload) != contract_baseline["storageSha256"]:
                raise SystemExit(f"{contract}: storage snapshot drifted from the freeze baseline")

    return entries


def implemented_contracts() -> set[str]:
    return set(validate_checkpoints())


def main() -> None:
    entries = validate_checkpoints()
    print(
        "Phase 9 implementation checkpoints passed "
        f"({len(entries)} implemented contracts; baseline {BASELINE_MANIFEST_SHA256})."
    )


if __name__ == "__main__":
    main()
