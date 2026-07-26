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
ACTIVATION_BACKLOG_ID = "UNI-ADR-015"
ACTIVATED_IMPLEMENTATIONS = {"PayoffQuoteEngine": "UNI-PAYOFF-001"}
PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS = (
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
    "packages/phase9/typescript/payoffReference.ts",
    "protocol/foundry.toml",
    "protocol/script/DeployPhase9Local.s.sol",
    "protocol/test/Phase9InterfaceFreeze.t.sol",
    "protocol/test/Phase9PayoffLocalDeploymentEvidence.t.sol",
    "protocol/test/Phase9PayoffQuote.t.sol",
    "protocol/test/Phase9PayoffQuoteAcceptanceMap.sol",
    "protocol/test/Phase9PayoffQuoteDeployment.t.sol",
    "protocol/test/Phase9PayoffQuoteFuzz.t.sol",
    "protocol/test/Phase9PayoffQuoteGolden.t.sol",
    "protocol/test/Phase9PayoffQuoteHarness.sol",
    "protocol/test/Phase9PayoffQuoteInvariants.t.sol",
    "scripts/check-foundation.ps1",
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
)
IMPLEMENTATION_EVIDENCE_PATHS = {
    "PayoffQuoteEngine": PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS,
}

# Prepared Foundry dependencies under protocol/lib are intentionally excluded from Git.
# Their exact installed bytes remain covered by dependencyClosureSha256. The candidate
# commit instead binds the pinned package inputs and the only script that materializes
# those bytes, in addition to every repository-tracked source in the closure.
REVIEWED_COMMIT_PROVENANCE_PATHS = (
    "package.json",
    "pnpm-lock.yaml",
    "protocol/foundry.toml",
    "scripts/prepare-foundry.ps1",
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
    "architectureReviewer",
    "backlogId",
    "contract",
    "dependencyClosureSha256",
    "implementationAuthor",
    "implementationEvidenceBundleSha256",
    "reviewPath",
    "reviewSha256",
    "reviewedCommit",
    "securityReviewer",
    "sourceSha256",
    "sourceSetSha256",
    "status",
    "storageStructuralSha256",
    "toolingReviewer",
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
    payload = [
        {"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)}
        for path in implementation_evidence_bundle_paths(contract)
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
                f"{contract}: reviewed commit input is missing: "
                f"{path.relative_to(ROOT).as_posix()}"
            )
    return sorted(paths, key=ordinal_utf8_path_key)


def run_git_bytes(arguments: tuple[str, ...]) -> subprocess.CompletedProcess[bytes]:
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
        )
    except OSError as exc:
        raise SystemExit("Git is required to validate the reviewed implementation commit") from exc


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
            raise SystemExit(
                f"{contract}: reviewed commit lacks required path: {relative_path}"
            )
        blobs[relative_path] = result.stdout
    return blobs


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
            "implementationEvidenceBundleSha256",
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
            if (
                implementation_evidence_bundle_hash(contract)
                != entry["implementationEvidenceBundleSha256"]
            ):
                raise SystemExit(f"{contract}: implementation evidence bundle hash is stale")

        if verify_reviews:
            review_path = validate_review_path(entry["reviewPath"])
            if sha256_file(review_path) != entry["reviewSha256"]:
                raise SystemExit(f"{contract}: implementation review hash is stale")
            content = review_content(review_path)
            metadata = require_unambiguous_review_pass(contract, content)
            for field, value in metadata.items():
                if entry[field] != value:
                    raise SystemExit(f"{contract}: implementation review {field} mismatch")
            review = normalized_review(content)
            required_tokens = (
                contract.lower(),
                backlog_id.lower(),
                entry["sourceSha256"],
                entry["sourceSetSha256"],
                entry["dependencyClosureSha256"],
                entry["implementationEvidenceBundleSha256"],
                entry["abiSha256"],
                entry["storageStructuralSha256"],
            )
            if any(token.lower() not in review for token in required_tokens):
                raise SystemExit(f"{contract}: implementation review status or hashes mismatch")
            if verify_current:
                validate_reviewed_commit_binding(
                    contract,
                    entry["reviewedCommit"],
                    baseline,
                    source_path,
                )

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
