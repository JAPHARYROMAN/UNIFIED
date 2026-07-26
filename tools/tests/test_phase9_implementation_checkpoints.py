from __future__ import annotations

import copy
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import check_phase9_implementation_checkpoints as checkpoints  # noqa: E402


def storage_payload(contract: str, source: str) -> dict[str, Any]:
    return {
        "compiler": {
            "openzeppelinVersion": "5.6.1",
            "settings": {
                "evmVersion": "prague",
                "optimizer": {"enabled": True, "runs": 200},
                "viaIR": False,
            },
            "settingsHash": "sha256:" + "1" * 64,
            "version": "0.8.36+commit.test",
        },
        "contract": contract,
        "freezeSurface": {
            "functions": [
                {
                    "bodyStatementKinds": ["RevertStatement"],
                    "implemented": True,
                    "kind": "function",
                    "modifiers": [],
                    "name": "mutate",
                    "revertError": "Phase9ImplementationNotFrozen",
                    "stateMutability": "nonpayable",
                    "visibility": "external",
                }
            ],
            "stateVariables": [
                {
                    "constant": False,
                    "immutable": False,
                    "name": "_value",
                    "type": "uint256",
                    "visibility": "private",
                }
            ],
        },
        "linearizedBases": [f"{source}:{contract}"],
        "schemaVersion": 1,
        "source": source,
        "storageLayout": {
            "storage": [
                {
                    "contract": f"{source}:{contract}",
                    "label": "_value",
                    "offset": 0,
                    "slot": "0",
                    "type": "t_uint256",
                }
            ],
            "types": {
                "t_uint256": {
                    "encoding": "inplace",
                    "label": "uint256",
                    "numberOfBytes": "32",
                }
            },
        },
    }


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_git(repository: Path, *arguments: str) -> str:
    git_executable = shutil.which("git")
    assert git_executable is not None
    result = subprocess.run(  # noqa: S603 - test-only argument vector, never a shell command
        (git_executable, *arguments),
        cwd=repository,
        capture_output=True,
        check=False,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def create_candidate_commit(repository: Path, files: dict[str, bytes]) -> str:
    repository.mkdir(parents=True, exist_ok=True)
    run_git(repository, "init", "--quiet")
    run_git(repository, "config", "user.name", "Phase 9 Test")
    run_git(repository, "config", "user.email", "phase9-test@unified.local")
    for relative_path, content in files.items():
        path = repository / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    run_git(repository, "add", "--", *files)
    run_git(repository, "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "candidate")
    return run_git(repository, "rev-parse", "HEAD")


def write_review(entry: dict[str, str], review_path: Path) -> None:
    review_path.write_text(
        "\n".join(
            (
                "Decision: PASS",
                "Architecture review: PASS",
                "Security review: PASS",
                f"Implementation author: {entry['implementationAuthor']}",
                f"Architecture reviewer: {entry['architectureReviewer']}",
                f"Security reviewer: {entry['securityReviewer']}",
                f"Tooling reviewer: {entry['toolingReviewer']}",
                f"Reviewed commit: {entry['reviewedCommit']}",
                entry["contract"],
                entry["backlogId"],
                entry["sourceSha256"],
                entry["sourceSetSha256"],
                entry["dependencyClosureSha256"],
                entry["implementationEvidenceBundleSha256"],
                entry["abiSha256"],
                entry["storageStructuralSha256"],
            )
        )
        + "\n",
        encoding="utf-8",
    )
    entry["reviewSha256"] = checkpoints.sha256_file(review_path)


def fixture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Path]]:
    root = tmp_path
    source_relative = "protocol/src/resolution/Example.sol"
    abi_relative = "protocol/abi/phase9/Example.abi.json"
    storage_relative = "protocol/storage-layout/phase9/Example.storage.json"
    review_relative = "security/reviews/phase-9-example-implementation.md"
    source_path = root / source_relative
    abi_path = root / abi_relative
    storage_path = root / storage_relative
    review_path = root / review_relative
    backlog_path = root / "docs/backlog/phase-9.csv"

    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_text("contract Example { /* implemented */ }\n", encoding="utf-8")
    abi: list[object] = []
    storage = storage_payload("Example", source_relative)
    write_json(abi_path, abi)
    write_json(storage_path, storage)

    monkeypatch.setattr(checkpoints, "ROOT", root)
    monkeypatch.setattr(checkpoints, "BACKLOG_PATH", backlog_path)
    monkeypatch.setattr(checkpoints, "SECURITY_REVIEW_ROOT", review_path.parent)
    monkeypatch.setattr(checkpoints, "SOURCE_ROOTS", (source_path.parent,))
    monkeypatch.setattr(checkpoints, "TOKEN_SOURCE", source_path)
    monkeypatch.setattr(checkpoints, "ACTIVATED_IMPLEMENTATIONS", {"Example": "UNI-EXAMPLE-001"})
    monkeypatch.setattr(
        checkpoints,
        "IMPLEMENTATION_EVIDENCE_PATHS",
        {"Example": (source_relative,)},
    )
    monkeypatch.setattr(checkpoints, "REVIEWED_COMMIT_PROVENANCE_PATHS", ())

    def current_worktree_blobs(
        contract: str, commit: str, relative_paths: tuple[str, ...]
    ) -> dict[str, bytes]:
        assert contract == "Example"
        assert commit == "1" * 40
        return {relative: (root / relative).read_bytes() for relative in relative_paths}

    monkeypatch.setattr(checkpoints, "reviewed_commit_file_bytes", current_worktree_blobs)

    baseline_source_hash = checkpoints.sha256_payload("historical stub source")
    abi_hash = checkpoints.sha256_payload(abi)
    manifest = {
        "contracts": [
            {
                "abiPath": abi_relative,
                "abiSha256": abi_hash,
                "contract": "Example",
                "sourcePath": source_relative,
                "sourceSha256": baseline_source_hash,
                "storagePath": storage_relative,
                "storageSha256": checkpoints.sha256_payload(storage),
            }
        ],
        "schemaVersion": 2,
        "sources": [{"path": source_relative, "sha256": baseline_source_hash}],
    }

    current_source_hash = checkpoints.sha256_file(source_path)
    current_source_set_hash = checkpoints.sha256_payload(
        [{"path": source_relative, "sha256": current_source_hash}]
    )
    entry = {
        "abiSha256": abi_hash,
        "architectureReviewer": "Architecture Reviewer",
        "backlogId": "UNI-EXAMPLE-001",
        "contract": "Example",
        "dependencyClosureSha256": checkpoints.repository_solidity_dependency_hash(source_path),
        "implementationAuthor": "Implementation Author",
        "implementationEvidenceBundleSha256": checkpoints.implementation_evidence_bundle_hash(
            "Example"
        ),
        "reviewPath": review_relative,
        "reviewSha256": "",
        "reviewedCommit": "1" * 40,
        "securityReviewer": "Security Reviewer",
        "sourceSha256": current_source_hash,
        "sourceSetSha256": current_source_set_hash,
        "status": "PASS",
        "storageStructuralSha256": checkpoints.structural_storage_hash(storage),
        "toolingReviewer": "Tooling Reviewer",
    }
    review_path.parent.mkdir(parents=True, exist_ok=True)
    write_review(entry, review_path)
    registry = {
        "baseline": {
            "commit": checkpoints.BASELINE_COMMIT,
            "manifestSha256": checkpoints.BASELINE_MANIFEST_SHA256,
            "rawFreezeArtifactsSha256": checkpoints.BASELINE_RAW_FREEZE_ARTIFACTS_SHA256,
            "sourceSetSha256": checkpoints.BASELINE_SOURCE_SET_SHA256,
        },
        "currentSourceSetSha256": current_source_set_hash,
        "implementations": [entry],
        "schemaVersion": 1,
    }

    backlog_path.parent.mkdir(parents=True, exist_ok=True)
    backlog_path.write_text(
        "id,status\nUNI-ADR-015,DONE\nUNI-EXAMPLE-001,DONE\n",
        encoding="utf-8",
    )
    return (
        manifest,
        registry,
        {
            "abi": abi_path,
            "backlog": backlog_path,
            "review": review_path,
            "source": source_path,
            "storage": storage_path,
        },
    )


def test_valid_reviewed_checkpoint_passes(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    assert set(checkpoints.validate_checkpoints(manifest=manifest, registry=registry)) == {
        "Example"
    }


def test_fabricated_existing_like_reviewed_commit_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repository"
    create_candidate_commit(repository, {"evidence.txt": b"reviewed\n"})
    monkeypatch.setattr(checkpoints, "ROOT", repository)

    with pytest.raises(SystemExit, match="reviewed commit does not exist"):
        checkpoints.reviewed_commit_file_bytes(
            "Example",
            "f" * 40,
            ("evidence.txt",),
        )


def test_evidence_drift_after_candidate_commit_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repository"
    relative = "docs/architecture/evidence.md"
    commit = create_candidate_commit(repository, {relative: b"reviewed evidence\n"})
    evidence = repository / relative
    evidence.write_bytes(b"drift after candidate\n")
    monkeypatch.setattr(checkpoints, "ROOT", repository)

    with pytest.raises(SystemExit, match="reviewed input differs from reviewed commit"):
        checkpoints.validate_reviewed_commit_paths("Example", commit, [evidence])


def test_post_candidate_review_backlog_and_checkpoint_files_may_differ(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repository"
    source_relative = "protocol/src/resolution/Example.sol"
    commit = create_candidate_commit(
        repository,
        {source_relative: b"contract Example { /* candidate */ }\n"},
    )
    monkeypatch.setattr(checkpoints, "ROOT", repository)
    monkeypatch.setattr(
        checkpoints,
        "IMPLEMENTATION_EVIDENCE_PATHS",
        {"Example": (source_relative,)},
    )
    monkeypatch.setattr(checkpoints, "REVIEWED_COMMIT_PROVENANCE_PATHS", ())
    manifest: dict[str, Any] = {
        "sources": [{"path": source_relative, "sha256": "sha256:" + "0" * 64}]
    }
    source = repository / source_relative
    required = checkpoints.reviewed_commit_required_paths("Example", manifest, source)

    post_candidate_paths = (
        repository / "security/reviews/phase-9-example.md",
        repository / "docs/backlog/phase-9.csv",
        repository / "protocol/compatibility/phase9-implementation-checkpoints.json",
    )
    for path in post_candidate_paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("post-candidate state\n", encoding="utf-8")

    assert required == [source]
    checkpoints.validate_reviewed_commit_paths("Example", commit, required)


def test_source_change_without_checkpoint_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    registry["implementations"] = []
    baseline_source_set = manifest.get("sources")
    assert isinstance(baseline_source_set, list)
    registry["currentSourceSetSha256"] = checkpoints.sha256_payload(baseline_source_set)
    paths["source"].write_text("contract Example { /* unreviewed */ }\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="without an exact implementation checkpoint"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_extra_phase9_contract_is_rejected(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    (paths["source"].parent / "Unexpected.sol").write_text(
        "contract Unexpected {}\n", encoding="utf-8"
    )
    with pytest.raises(SystemExit, match="unexpected="):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_nested_extra_phase9_contract_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    nested = paths["source"].parent / "nested" / "Unexpected.sol"
    nested.parent.mkdir()
    nested.write_text("contract Unexpected {}\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="unexpected="):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    "source",
    (
        'string constant X = "x//"; import "../risk/PayoffLogic.sol";',
        'string constant X = "x/* not a comment */"; import "../risk/PayoffLogic.sol";',
        'string constant X = "escaped \\" //"; import "../risk/PayoffLogic.sol";',
        'string constant X = "escaped \\" /* */"; import "../risk/PayoffLogic.sol";',
        'string constant X = "import \\"../risk/Fake.sol\\"; //"; '
        'import "../risk/PayoffLogic.sol";',
    ),
)
def test_solidity_import_lexer_does_not_treat_string_markers_as_comments(source: str) -> None:
    assert checkpoints.solidity_imports_from_source(source) == ("../risk/PayoffLogic.sol",)


@pytest.mark.parametrize("line_end", ("\n", "\r", "\r\n"))
def test_solidity_import_lexer_handles_every_line_ending(line_end: str) -> None:
    source = f'// hidden text{line_end}import "../risk/PayoffLogic.sol";'
    assert checkpoints.solidity_imports_from_source(source) == ("../risk/PayoffLogic.sol",)


def test_dependency_paths_use_explicit_ordinal_utf8_order(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    paths = [
        tmp_path / "protocol/src/risk/aHelper.sol",
        tmp_path / "protocol/src/risk/_Helper.sol",
        tmp_path / "protocol/src/risk/ZHelper.sol",
        tmp_path / "protocol/src/risk/AHelper.sol",
    ]
    assert [
        path.relative_to(tmp_path).as_posix()
        for path in sorted(paths, key=checkpoints.ordinal_utf8_path_key)
    ] == [
        "protocol/src/risk/AHelper.sol",
        "protocol/src/risk/ZHelper.sol",
        "protocol/src/risk/_Helper.sol",
        "protocol/src/risk/aHelper.sol",
    ]


def test_foundation_prepares_remapped_sources_before_phase9_checkpoint_checks() -> None:
    foundation_check = (ROOT / "scripts/check-foundation.ps1").read_text(encoding="utf-8")
    preparation = "pwsh ./scripts/prepare-foundry.ps1"
    checkpoint_check = "uv run python tools/check_phase9_implementation_checkpoints.py"
    assert foundation_check.count(preparation) == 1
    assert foundation_check.index(preparation) < foundation_check.index(checkpoint_check)


def external_helper_checkpoint(
    manifest: dict[str, Any], registry: dict[str, Any], paths: dict[str, Path]
) -> Path:
    helper = paths["source"].parent.parent / "risk" / "PayoffLogic.sol"
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text(
        "library PayoffLogic { function value() internal pure returns (uint256) { return 1; } }\n"
    )
    paths["source"].write_text(
        'import { PayoffLogic } from "../risk/PayoffLogic.sol";\n'
        "contract Example { function value() external pure returns (uint256) { "
        "return PayoffLogic.value(); } }\n",
        encoding="utf-8",
    )
    entry = registry["implementations"][0]
    entry["sourceSha256"] = checkpoints.sha256_file(paths["source"])
    source_set = [{"path": manifest["sources"][0]["path"], "sha256": entry["sourceSha256"]}]
    entry["sourceSetSha256"] = checkpoints.sha256_payload(source_set)
    registry["currentSourceSetSha256"] = entry["sourceSetSha256"]
    entry["implementationEvidenceBundleSha256"] = checkpoints.implementation_evidence_bundle_hash(
        "Example"
    )
    return helper


def test_external_helper_import_requires_dependency_closure_refresh(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    external_helper_checkpoint(manifest, registry, paths)
    write_review(registry["implementations"][0], paths["review"])
    with pytest.raises(SystemExit, match="dependency closure hash is stale"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_external_helper_only_mutation_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    helper = external_helper_checkpoint(manifest, registry, paths)
    entry = registry["implementations"][0]
    entry["dependencyClosureSha256"] = checkpoints.repository_solidity_dependency_hash(
        paths["source"]
    )
    write_review(entry, paths["review"])
    checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    helper.write_text(helper.read_text(encoding="utf-8").replace("return 1", "return 2"))
    with pytest.raises(SystemExit, match="dependency closure hash is stale"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_remapped_recursive_dependency_mutation_changes_closure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    foundry_config = tmp_path / "protocol/foundry.toml"
    foundry_config.parent.mkdir(parents=True)
    foundry_config.write_text(
        '[profile.default]\nremappings = ["@vendor/=lib/vendor/contracts/"]\n',
        encoding="utf-8",
    )
    source = tmp_path / "protocol/src/resolution/Example.sol"
    source.parent.mkdir(parents=True)
    source.write_text(
        'import { Library } from "@vendor/Library.sol";\ncontract Example {}\n',
        encoding="utf-8",
    )
    library = tmp_path / "protocol/lib/vendor/contracts/Library.sol"
    nested = library.parent / "Nested.sol"
    library.parent.mkdir(parents=True)
    library.write_text(
        'import { Nested } from "./Nested.sol";\nlibrary Library {}\n', encoding="utf-8"
    )
    nested.write_text(
        "library Nested { function value() internal pure returns (uint256) { return 1; } }\n",
        encoding="utf-8",
    )

    paths = [
        path.relative_to(tmp_path).as_posix()
        for path in checkpoints.repository_solidity_dependency_paths(source)
    ]
    assert paths == [
        "protocol/lib/vendor/contracts/Library.sol",
        "protocol/lib/vendor/contracts/Nested.sol",
        "protocol/src/resolution/Example.sol",
    ]
    original = checkpoints.repository_solidity_dependency_hash(source)
    nested.write_text(
        nested.read_text(encoding="utf-8").replace("return 1", "return 2"),
        encoding="utf-8",
    )
    assert checkpoints.repository_solidity_dependency_hash(source) != original


@pytest.mark.parametrize("import_path", ("@vendor/Missing.sol", "@unmapped/Missing.sol"))
def test_unresolved_nonrelative_or_remapped_import_fails_closed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, import_path: str
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    foundry_config = tmp_path / "protocol/foundry.toml"
    foundry_config.parent.mkdir(parents=True)
    foundry_config.write_text(
        '[profile.default]\nremappings = ["@vendor/=lib/vendor/contracts/"]\n',
        encoding="utf-8",
    )
    (tmp_path / "protocol/lib/vendor/contracts").mkdir(parents=True)
    source = tmp_path / "protocol/src/resolution/Example.sol"
    source.parent.mkdir(parents=True)
    source.write_text(f'import "{import_path}";\ncontract Example {{}}\n', encoding="utf-8")

    with pytest.raises(SystemExit, match="unresolved non-relative import"):
        checkpoints.repository_solidity_dependency_paths(source)


def test_payoff_implementation_evidence_bundle_paths_are_exact_and_cycle_free() -> None:
    paths = checkpoints.PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS
    assert list(paths) == sorted(paths, key=lambda path: path.encode("utf-8"))
    assert len(paths) == len(set(paths))
    assert {
        "protocol/script/DeployPhase9Local.s.sol",
        "tools/verify_phase9_payoff_deployment.py",
        "infrastructure/local/phase9-payoff-deployment-candidate.schema.json",
        "infrastructure/local/phase9-payoff-deployment-evidence.schema.json",
        "infrastructure/local/phase9-payoff-deployment-code-hashes.json",
        "protocol/test/Phase9PayoffQuoteAcceptanceMap.sol",
        "models/foundation_model/src/unified_foundation/phase9_payoff_reference.py",
        "packages/phase9/typescript/payoffReference.ts",
        "tools/check_phase9_implementation_checkpoints.py",
        "tools/compile_phase9_storage_layouts.mjs",
    }.issubset(paths)
    assert not any(
        path.startswith("security/reviews/")
        or path == "protocol/compatibility/phase9-implementation-checkpoints.json"
        or path == "docs/backlog/phase-9.csv"
        for path in paths
    )


def test_every_payoff_implementation_evidence_path_is_material_to_bundle_hash(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    for relative_path in checkpoints.PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS:
        path = tmp_path / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"evidence:{relative_path}\n", encoding="utf-8")
    baseline = checkpoints.implementation_evidence_bundle_hash("PayoffQuoteEngine")

    for relative_path in checkpoints.PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS:
        path = tmp_path / relative_path
        original = path.read_bytes()
        path.write_bytes(original + b"mutation\n")
        assert checkpoints.implementation_evidence_bundle_hash("PayoffQuoteEngine") != baseline
        path.write_bytes(original)


def test_missing_payoff_implementation_evidence_fails_closed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    first = checkpoints.PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS[0]
    monkeypatch.setattr(
        checkpoints,
        "IMPLEMENTATION_EVIDENCE_PATHS",
        {"PayoffQuoteEngine": (first,)},
    )
    with pytest.raises(SystemExit, match="implementation evidence is missing"):
        checkpoints.implementation_evidence_bundle_hash("PayoffQuoteEngine")


def test_wrong_backlog_or_unopened_contract_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    registry["implementations"][0]["backlogId"] = "UNI-WRONG-001"
    with pytest.raises(SystemExit, match="backlog substitution"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    registry["implementations"][0]["backlogId"] = "UNI-EXAMPLE-001"
    monkeypatch.setattr(checkpoints, "ACTIVATED_IMPLEMENTATIONS", {})
    with pytest.raises(SystemExit, match="not activated"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize("target", ("entry", "aggregate"))
def test_stale_or_tampered_current_source_set_hash_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, target: str
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    if target == "entry":
        registry["implementations"][0]["sourceSetSha256"] = "sha256:" + "0" * 64
        message = "source-set checkpoint is stale"
    else:
        registry["currentSourceSetSha256"] = "sha256:" + "0" * 64
        message = "current implementation source-set hash is stale"
    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    ("target", "message"),
    (("abi", "ABI snapshot"), ("storage", "storage payload|storage snapshot")),
)
def test_abi_or_storage_snapshot_drift_is_rejected(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    target: str,
    message: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    write_json(paths[target], {"tampered": True})
    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_checkpoint_baseline_identity_drift_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    registry["baseline"]["commit"] = "0" * 40
    with pytest.raises(SystemExit, match="baseline identity drifted"):
        checkpoints.validate_checkpoints(
            manifest=manifest,
            registry=registry,
            verify_current=False,
            verify_reviews=False,
            verify_backlog=False,
        )


@pytest.mark.parametrize(
    ("mutation", "message"),
    (
        (lambda registry, paths: registry["implementations"][0].update(status="PENDING"), "status"),
        (
            lambda registry, paths: registry["implementations"][0].update(
                reviewSha256="sha256:" + "0" * 64
            ),
            "review hash",
        ),
        (
            lambda registry, paths: paths["backlog"].write_text(
                "id,status\nUNI-ADR-015,DONE\nUNI-EXAMPLE-001,TODO\n",
                encoding="utf-8",
            ),
            "not DONE",
        ),
    ),
)
def test_review_status_hash_or_backlog_mismatch_is_rejected(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    mutation: Any,
    message: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    mutation(registry, paths)
    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_review_content_must_bind_pass_status_and_exact_hashes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    paths["review"].write_text("Decision: PENDING\n", encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])
    with pytest.raises(SystemExit, match="visible canonical Decision: PASS"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    ("label", "status"),
    [
        (label, status)
        for label in ("Decision", "Architecture review", "Security review")
        for status in ("FAIL", "PENDING", "BLOCKED")
    ],
)
def test_each_nonpass_review_decision_is_rejected_even_when_pass_appears_in_prose(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    label: str,
    status: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    content = (
        paths["review"].read_text(encoding="utf-8").replace(f"{label}: PASS", f"{label}: {status}")
    )
    content += f"Historical quoted text said {label}: PASS, but it is not authoritative.\n"
    paths["review"].write_text(content, encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match=rf"visible canonical {label}: PASS"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    ("label", "duplicate_status"),
    [
        (label, status)
        for label in ("Decision", "Architecture review", "Security review")
        for status in ("PASS", "FAIL", "PENDING", "BLOCKED")
    ],
)
def test_duplicate_or_contradictory_top_level_review_decisions_are_rejected(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    label: str,
    duplicate_status: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    with paths["review"].open("a", encoding="utf-8") as handle:
        handle.write(f"{label}: {duplicate_status}\n")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match=rf"visible canonical {label}: PASS"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize("prefix", ("> ", "- ", "    ", "Body text: "))
def test_non_top_level_pass_text_cannot_approve_a_review(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, prefix: str
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    content = (
        paths["review"]
        .read_text(encoding="utf-8")
        .replace("Decision: PASS", f"{prefix}Decision: PASS")
    )
    paths["review"].write_text(content, encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match="visible canonical Decision: PASS"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_fenced_pass_text_cannot_approve_a_review(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    content = (
        paths["review"]
        .read_text(encoding="utf-8")
        .replace("Decision: PASS", "```text\nDecision: PASS\n```")
    )
    paths["review"].write_text(content, encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match="visible canonical Decision: PASS"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    "contradiction",
    (
        "# Decision: FAIL",
        "- Decision: PENDING",
        "> Decision: BLOCKED",
        "```text\nDecision: FAIL\n```",
        "<!-- Decision: FAIL -->",
        "<!-- Decision: FAIL",
        "Historical prose says Decision: FAIL and is contradictory.",
        "Historical prose says Decision is FAIL and is contradictory.",
        "Decision - FAIL",
        "Decision = BLOCKED",
    ),
)
def test_any_hidden_or_prose_status_occurrence_rejects_an_otherwise_valid_review(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    contradiction: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    with paths["review"].open("a", encoding="utf-8") as handle:
        handle.write(contradiction + "\n")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match="no other Decision status occurrence"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    ("field", "replacement", "message"),
    (
        ("Implementation author", "", "visible canonical Implementation author field"),
        ("Architecture reviewer", "Implementation Author", "must all be distinct"),
        ("Security reviewer", "Architecture Reviewer", "must all be distinct"),
        ("Tooling reviewer", "Security Reviewer", "must all be distinct"),
        ("Reviewed commit", "A" * 40, "exact lowercase 40-hex"),
        ("Reviewed commit", "1" * 39, "exact lowercase 40-hex"),
    ),
)
def test_review_identity_and_commit_fields_fail_closed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    field: str,
    replacement: str,
    message: str,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    content = paths["review"].read_text(encoding="utf-8")
    content = re.sub(rf"^{re.escape(field)}:.*$", f"{field}: {replacement}", content, flags=re.M)
    paths["review"].write_text(content, encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_checkpoint_identity_must_match_review_metadata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    registry["implementations"][0]["toolingReviewer"] = "Substituted Reviewer"
    with pytest.raises(SystemExit, match="implementation review toolingReviewer mismatch"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    "wrapper",
    (
        lambda field: f"```text\n{field}\n```\n",
        lambda field: f"<!-- {field} -->\n",
        lambda field: f"<!-- {field}\n",
    ),
)
def test_hidden_review_metadata_cannot_satisfy_required_fields(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    wrapper: Any,
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    field = "Tooling reviewer: Tooling Reviewer"
    content = paths["review"].read_text(encoding="utf-8").replace(f"{field}\n", "")
    paths["review"].write_text(content + wrapper(field), encoding="utf-8")
    registry["implementations"][0]["reviewSha256"] = checkpoints.sha256_file(paths["review"])
    with pytest.raises(SystemExit, match="visible canonical Tooling reviewer field"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_structural_storage_ignores_bodies_but_not_variables_or_slots() -> None:
    baseline = storage_payload("Example", "protocol/src/resolution/Example.sol")
    implemented = copy.deepcopy(baseline)
    implemented["freezeSurface"]["functions"][0]["bodyStatementKinds"] = [
        "VariableDeclarationStatement",
        "ExpressionStatement",
    ]
    implemented["freezeSurface"]["functions"][0]["revertError"] = None
    assert checkpoints.structural_storage_hash(implemented) == checkpoints.structural_storage_hash(
        baseline
    )

    variable_drift = copy.deepcopy(implemented)
    variable_drift["freezeSurface"]["stateVariables"][0]["type"] = "uint64"
    assert checkpoints.structural_storage_hash(
        variable_drift
    ) != checkpoints.structural_storage_hash(baseline)

    slot_drift = copy.deepcopy(implemented)
    slot_drift["storageLayout"]["storage"][0]["slot"] = "1"
    assert checkpoints.structural_storage_hash(slot_drift) != checkpoints.structural_storage_hash(
        baseline
    )


def test_historical_manifest_identity_drift_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "phase9-manifest.json"
    payload = {"contracts": [], "schemaVersion": 2, "sources": []}
    write_json(path, payload)
    monkeypatch.setattr(checkpoints, "BASELINE_MANIFEST_PATH", path)
    monkeypatch.setattr(
        checkpoints, "BASELINE_MANIFEST_SHA256", checkpoints.sha256_payload(payload)
    )
    monkeypatch.setattr(
        checkpoints, "BASELINE_SOURCE_SET_SHA256", checkpoints.sha256_payload(payload["sources"])
    )
    monkeypatch.setattr(checkpoints, "verify_raw_freeze_artifacts", lambda manifest: None)
    assert checkpoints.historical_manifest() == payload

    payload["schemaVersion"] = 3
    write_json(path, payload)
    with pytest.raises(SystemExit, match="schema drifted|identity drifted"):
        checkpoints.historical_manifest()


@pytest.mark.parametrize("target", ("manifest", "abi", "storage", "review"))
def test_raw_freeze_identity_rejects_formatting_only_drift(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, target: str
) -> None:
    manifest, _, paths = fixture(tmp_path, monkeypatch)
    manifest_path = tmp_path / "protocol/compatibility/phase9-manifest.json"
    write_json(manifest_path, manifest)
    monkeypatch.setattr(checkpoints, "BASELINE_MANIFEST_PATH", manifest_path)
    monkeypatch.setattr(checkpoints, "BASELINE_REVIEW_PATH", paths["review"])
    expected = checkpoints.raw_freeze_artifacts_hash(manifest)
    targets = {
        "manifest": manifest_path,
        "abi": paths["abi"],
        "storage": paths["storage"],
        "review": paths["review"],
    }
    path = targets[target]
    if path.suffix == ".json":
        content = path.read_text(encoding="utf-8")
        payload = json.loads(content)
        path.write_text(" " + content, encoding="utf-8")
        assert json.loads(path.read_text(encoding="utf-8")) == payload
    else:
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    monkeypatch.setattr(checkpoints, "BASELINE_RAW_FREEZE_ARTIFACTS_SHA256", expected)
    with pytest.raises(SystemExit, match="artifact bytes drifted"):
        checkpoints.verify_raw_freeze_artifacts(manifest)
