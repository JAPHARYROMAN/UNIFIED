from __future__ import annotations

import copy
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, cast

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


def write_review(checkpoint_package: dict[str, Any], review_path: Path) -> None:
    review = checkpoint_package["review"]
    revision = checkpoint_package["revisions"][0]
    review_path.write_text(
        "\n".join(
            (
                "Decision: PASS",
                "Architecture review: PASS",
                "Security review: PASS",
                f"Implementation author: {review['implementationAuthor']}",
                f"Architecture reviewer: {review['architectureReviewer']}",
                f"Security reviewer: {review['securityReviewer']}",
                f"Tooling reviewer: {review['toolingReviewer']}",
                f"Reviewed commit: {review['reviewedCommit']}",
                checkpoint_package["checkpointId"],
                *checkpoint_package["requiredBacklogIds"],
                revision["contract"],
                *revision["activatedSignatures"],
                revision["sourceSha256"],
                revision["sourceSetSha256"],
                revision["dependencyClosureSha256"],
                revision["implementationEvidenceBundleSha256"],
                revision["abiSha256"],
                revision["storageStructuralSha256"],
            )
        )
        + "\n",
        encoding="utf-8",
    )
    review["reviewSha256"] = checkpoints.sha256_file(review_path)


def fixture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Path]]:
    root = tmp_path
    source_relative = "protocol/src/resolution/Example.sol"
    abi_relative = "protocol/abi/phase9/Example.abi.json"
    storage_relative = "protocol/storage-layout/phase9/Example.storage.json"
    review_relative = "security/reviews/phase-9-example-implementation.md"
    control_relative = "tools/checkpoint-control.py"
    source_path = root / source_relative
    abi_path = root / abi_relative
    storage_path = root / storage_relative
    review_path = root / review_relative
    backlog_path = root / "docs/backlog/phase-9.csv"

    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_text("contract Example { /* implemented */ }\n", encoding="utf-8")
    control_path = root / control_relative
    control_path.parent.mkdir(parents=True, exist_ok=True)
    control_path.write_text("# checkpoint control\n", encoding="utf-8")
    abi: list[object] = [
        {
            "inputs": [],
            "name": "mutate",
            "outputs": [],
            "stateMutability": "nonpayable",
            "type": "function",
        }
    ]
    storage = storage_payload("Example", source_relative)
    write_json(abi_path, abi)
    write_json(storage_path, storage)

    monkeypatch.setattr(checkpoints, "ROOT", root)
    monkeypatch.setattr(checkpoints, "BACKLOG_PATH", backlog_path)
    monkeypatch.setattr(checkpoints, "SECURITY_REVIEW_ROOT", review_path.parent)
    monkeypatch.setattr(checkpoints, "SOURCE_ROOTS", (source_path.parent,))
    monkeypatch.setattr(checkpoints, "TOKEN_SOURCE", source_path)
    monkeypatch.setattr(
        checkpoints,
        "ACTIVATION_PACKAGES",
        {
            "P9-EXAMPLE-001": {
                "abiAdditions": {},
                "contracts": {"Example": ("mutate()",)},
                "requiredBacklogIds": ("UNI-ADR-015", "UNI-EXAMPLE-001"),
            }
        },
    )
    monkeypatch.setattr(
        checkpoints,
        "IMPLEMENTATION_EVIDENCE_PATHS",
        {"Example": (source_relative,)},
    )
    monkeypatch.setattr(checkpoints, "REVIEWED_COMMIT_PROVENANCE_PATHS", ())
    monkeypatch.setattr(checkpoints, "CONTROL_BUNDLE_PATHS", (control_relative,))
    monkeypatch.setattr(
        checkpoints, "require_git_clean_worktree_bytes", lambda contract, paths: None
    )

    def current_worktree_blobs(
        contract: str, commit: str, relative_paths: tuple[str, ...]
    ) -> dict[str, bytes]:
        assert contract in {"Example", "P9-EXAMPLE-001"}
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
    revision: dict[str, Any] = {
        "abiSha256": abi_hash,
        "activatedSignatures": ["mutate()"],
        "contract": "Example",
        "dependencyClosureSha256": checkpoints.repository_solidity_dependency_hash(source_path),
        "implementationEvidenceBundleSha256": checkpoints.implementation_evidence_bundle_hash(
            "Example"
        ),
        "revision": 1,
        "sourceSha256": current_source_hash,
        "sourceSetSha256": current_source_set_hash,
        "storageStructuralSha256": checkpoints.structural_storage_hash(storage),
        "supersedes": None,
    }
    checkpoint_package: dict[str, Any] = {
        "checkpointId": "P9-EXAMPLE-001",
        "requiredBacklogIds": ["UNI-ADR-015", "UNI-EXAMPLE-001"],
        "review": {
            "architectureReviewer": "Architecture Reviewer",
            "implementationAuthor": "Implementation Author",
            "reviewPath": review_relative,
            "reviewSha256": "",
            "reviewedCommit": "1" * 40,
            "securityReviewer": "Security Reviewer",
            "status": "PASS",
            "toolingReviewer": "Tooling Reviewer",
        },
        "revisions": [revision],
    }
    review_path.parent.mkdir(parents=True, exist_ok=True)
    write_review(checkpoint_package, review_path)
    registry = {
        "baseline": {
            "commit": checkpoints.BASELINE_COMMIT,
            "manifestSha256": checkpoints.BASELINE_MANIFEST_SHA256,
            "rawFreezeArtifactsSha256": checkpoints.BASELINE_RAW_FREEZE_ARTIFACTS_SHA256,
            "sourceSetSha256": checkpoints.BASELINE_SOURCE_SET_SHA256,
        },
        "currentControlBundleSha256": checkpoints.current_control_bundle_hash(),
        "currentSourceSetSha256": current_source_set_hash,
        "packages": [checkpoint_package],
        "schemaVersion": 2,
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


def auxiliary_fixture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Path], bytes]:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    source_relative = cast(str, manifest["contracts"][0]["sourcePath"])
    auxiliary_relative = "protocol/src/resolution/IExample.sol"
    auxiliary_path = tmp_path / auxiliary_relative
    historical_auxiliary = b"interface IExample { /* historical */ }\n"
    auxiliary_path.write_bytes(b"interface IExample { function helper() external; }\n")
    paths["source"].write_text(
        'import { IExample } from "./IExample.sol";\n'
        "contract Example is IExample { /* implemented */ "
        "function helper() external {} }\n",
        encoding="utf-8",
    )
    manifest["sources"].append(
        {
            "path": auxiliary_relative,
            "sha256": checkpoints.sha256_bytes(historical_auxiliary),
        }
    )
    monkeypatch.setattr(
        checkpoints,
        "PACKAGE_AUXILIARY_SOURCE_OWNERS",
        {"P9-EXAMPLE-001": ((auxiliary_relative, "Example"),)},
    )

    revision = registry["packages"][0]["revisions"][0]
    revision["sourceSha256"] = checkpoints.sha256_file(paths["source"])
    revision["dependencyClosureSha256"] = checkpoints.repository_solidity_dependency_hash(
        paths["source"]
    )
    revision["implementationEvidenceBundleSha256"] = (
        checkpoints.implementation_evidence_bundle_hash("Example")
    )
    current_sources = {
        source_relative: revision["sourceSha256"],
        auxiliary_relative: checkpoints.sha256_file(auxiliary_path),
    }
    source_set = checkpoints.sha256_payload(
        [
            {"path": source["path"], "sha256": current_sources[source["path"]]}
            for source in manifest["sources"]
        ]
    )
    revision["sourceSetSha256"] = source_set
    registry["currentSourceSetSha256"] = source_set
    write_review(registry["packages"][0], paths["review"])
    paths["auxiliary"] = auxiliary_path
    return manifest, registry, paths, historical_auxiliary


def test_valid_reviewed_checkpoint_passes(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    assert set(checkpoints.validate_checkpoints(manifest=manifest, registry=registry)) == {
        "Example"
    }


def test_stale_current_control_bundle_hash_is_rejected_directly(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    registry["currentControlBundleSha256"] = "sha256:" + "9" * 64
    with pytest.raises(SystemExit, match="current control-bundle hash is stale"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_accepted_payoff_package_pin_rejects_historical_dependency_mutation() -> None:
    registry = checkpoints.checkpoint_payload()
    payoff_package = cast(dict[str, Any], cast(list[object], registry["packages"])[0])
    assert checkpoints.sha256_payload(payoff_package) == checkpoints.PAYOFF_ACCEPTED_PACKAGE_SHA256
    payoff_revision = cast(dict[str, Any], cast(list[object], payoff_package["revisions"])[0])
    payoff_revision["dependencyClosureSha256"] = "sha256:" + "9" * 64

    with pytest.raises(SystemExit, match="P9-PAYOFF-001: accepted package identity drifted"):
        checkpoints.validate_checkpoints(
            manifest=checkpoints.historical_manifest(),
            registry=registry,
            verify_current=False,
            verify_reviews=False,
            verify_backlog=False,
        )


def test_exact_refinance_coordinator_additions_are_allowed_and_any_drift_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    event = copy.deepcopy(checkpoints.REFINANCE_STATE_TRANSITIONED_EVENT)
    funding_error = copy.deepcopy(checkpoints.REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR)
    additions = (funding_error, event)
    assert additions == checkpoints.REFINANCE_COORDINATOR_ABI_ADDITIONS
    checkpoints.ACTIVATION_PACKAGES["P9-EXAMPLE-001"]["abiAdditions"] = {"Example": additions}
    abi = json.loads(paths["abi"].read_text(encoding="utf-8"))
    revision = registry["packages"][0]["revisions"][0]
    revision["abiSha256"] = checkpoints.sha256_payload(
        checkpoints.additive_abi_payload(abi, additions)
    )
    write_review(registry["packages"][0], paths["review"])
    checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    substituted = copy.deepcopy(event)
    substituted_inputs = cast(list[dict[str, Any]], substituted["inputs"])
    substituted_inputs[3]["indexed"] = True
    revision["abiSha256"] = checkpoints.sha256_payload(
        checkpoints.additive_abi_payload(abi, (funding_error, substituted))
    )
    write_review(registry["packages"][0], paths["review"])
    with pytest.raises(SystemExit, match="ABI differs from the additive allowlist"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    substituted_error = copy.deepcopy(funding_error)
    substituted_error_inputs = cast(list[dict[str, Any]], substituted_error["inputs"])
    substituted_error_inputs[0]["name"] = "fundingId"
    revision["abiSha256"] = checkpoints.sha256_payload(
        checkpoints.additive_abi_payload(abi, (substituted_error, event))
    )
    write_review(registry["packages"][0], paths["review"])
    with pytest.raises(SystemExit, match="ABI differs from the additive allowlist"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    with pytest.raises(SystemExit, match="errors and events only"):
        checkpoints.additive_abi_payload(
            abi,
            (
                {
                    "inputs": [],
                    "name": "unauthorizedSelector",
                    "outputs": [],
                    "stateMutability": "nonpayable",
                    "type": "function",
                },
            ),
        )


def test_exact_lien_registry_addition_is_allowed_and_any_drift_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    handoff_error = copy.deepcopy(checkpoints.REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR)
    additions = (handoff_error,)
    assert additions == checkpoints.LIEN_REGISTRY_ABI_ADDITIONS
    checkpoints.ACTIVATION_PACKAGES["P9-EXAMPLE-001"]["abiAdditions"] = {"Example": additions}
    abi = json.loads(paths["abi"].read_text(encoding="utf-8"))
    revision = registry["packages"][0]["revisions"][0]
    revision["abiSha256"] = checkpoints.sha256_payload(
        checkpoints.additive_abi_payload(abi, additions)
    )
    write_review(registry["packages"][0], paths["review"])
    checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    substituted = copy.deepcopy(handoff_error)
    substituted_inputs = cast(list[dict[str, Any]], substituted["inputs"])
    substituted_inputs[0]["name"] = "lienHandoffId"
    revision["abiSha256"] = checkpoints.sha256_payload(
        checkpoints.additive_abi_payload(abi, (substituted,))
    )
    write_review(registry["packages"][0], paths["review"])
    with pytest.raises(SystemExit, match="ABI differs from the additive allowlist"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_refinance_additions_are_owned_by_their_exact_contracts() -> None:
    additions = checkpoints.ACTIVATION_PACKAGES["P9-REFI-001"]["abiAdditions"]
    assert additions == {
        "LienRegistry": checkpoints.LIEN_REGISTRY_ABI_ADDITIONS,
        "RefinanceCoordinator": checkpoints.REFINANCE_COORDINATOR_ABI_ADDITIONS,
    }
    assert checkpoints.REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR not in additions[
        "RefinanceCoordinator"
    ]
    assert checkpoints.REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR not in additions[
        "LienRegistry"
    ]
    assert checkpoints.ACTIVATION_PACKAGES["P9-REFI-001"]["requiredBacklogIds"] == (
        "UNI-ADR-016",
        "UNI-ADR-017",
        "UNI-ADR-018",
        "UNI-REFI-001",
        "UNI-REFI-002",
    )


def test_refinance_auxiliary_sources_have_exact_owners_and_order() -> None:
    assert checkpoints.REFINANCE_AUXILIARY_SOURCE_OWNERS == (
        ("protocol/src/interfaces/phase9/ILienRegistry.sol", "LienRegistry"),
        (
            "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
            "RefinanceCoordinator",
        ),
    )
    assert checkpoints.PACKAGE_AUXILIARY_SOURCE_OWNERS == {
        "P9-REFI-001": checkpoints.REFINANCE_AUXILIARY_SOURCE_OWNERS
    }
    assert "P9-PAYOFF-001" not in checkpoints.PACKAGE_AUXILIARY_SOURCE_OWNERS


def test_control_bundle_paths_are_ordinal_and_include_abi_ownership_checker() -> None:
    assert list(checkpoints.CONTROL_BUNDLE_PATHS) == sorted(
        checkpoints.CONTROL_BUNDLE_PATHS,
        key=lambda path: path.encode("utf-8"),
    )
    assert checkpoints.CONTROL_BUNDLE_PATHS.count("tools/check_abi.py") == 1
    assert (
        checkpoints.CONTROL_BUNDLE_PATHS.count(
            "tools/check_phase9_refinance_linked_modules.py"
        )
        == 1
    )
    assert (
        checkpoints.CONTROL_BUNDLE_PATHS.count(
            "tools/tests/test_phase9_refinance_linked_modules.py"
        )
        == 1
    )


def test_later_revision_requires_exact_supersession_and_monotonic_activation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    source_relative = cast(str, manifest["sources"][0]["path"])
    first_source = paths["source"].read_bytes()
    second_source = b"contract Example { /* revision 2 */ }\n"
    second_hash = checkpoints.sha256_bytes(second_source)
    second_source_set = checkpoints.sha256_payload(
        [{"path": source_relative, "sha256": second_hash}]
    )
    second_revision = copy.deepcopy(registry["packages"][0]["revisions"][0])
    second_revision.update(
        {
            "implementationEvidenceBundleSha256": second_source_set,
            "revision": 2,
            "sourceSetSha256": second_source_set,
            "sourceSha256": second_hash,
            "supersedes": {"checkpointId": "P9-EXAMPLE-001", "revision": 1},
        }
    )
    second_review_path = paths["review"].parent / "phase-9-example-second.md"
    second_package: dict[str, Any] = {
        "checkpointId": "P9-EXAMPLE-002",
        "requiredBacklogIds": ["UNI-EXAMPLE-002"],
        "review": {
            "architectureReviewer": "Architecture Reviewer 2",
            "implementationAuthor": "Implementation Author 2",
            "reviewPath": second_review_path.relative_to(tmp_path).as_posix(),
            "reviewSha256": "",
            "reviewedCommit": "2" * 40,
            "securityReviewer": "Security Reviewer 2",
            "status": "PASS",
            "toolingReviewer": "Tooling Reviewer 2",
        },
        "revisions": [second_revision],
    }
    checkpoints.ACTIVATION_PACKAGES["P9-EXAMPLE-002"] = {
        "abiAdditions": {},
        "contracts": {"Example": ("mutate()",)},
        "requiredBacklogIds": ("UNI-EXAMPLE-002",),
    }
    write_review(second_package, second_review_path)
    registry["packages"].append(second_package)
    registry["currentSourceSetSha256"] = second_source_set
    with paths["backlog"].open("a", encoding="utf-8") as handle:
        handle.write("UNI-EXAMPLE-002,DONE\n")

    def committed_blobs(
        _label: str, commit: str, relative_paths: tuple[str, ...]
    ) -> dict[str, bytes]:
        source = second_source if commit == "2" * 40 else first_source
        return {relative: source for relative in relative_paths}

    monkeypatch.setattr(checkpoints, "reviewed_commit_file_bytes", committed_blobs)
    checkpoints.validate_checkpoints(manifest=manifest, registry=registry, verify_current=False)

    second_revision["supersedes"] = {"checkpointId": "P9-WRONG-001", "revision": 1}
    with pytest.raises(SystemExit, match="supersession chain drifted"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry, verify_current=False)
    second_revision["supersedes"] = {"checkpointId": "P9-EXAMPLE-001", "revision": 1}
    second_revision["activatedSignatures"] = []
    checkpoints.ACTIVATION_PACKAGES["P9-EXAMPLE-002"]["contracts"] = {"Example": ()}
    with pytest.raises(SystemExit, match="activation is not monotonic"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry, verify_current=False)


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


def test_git_clean_lf_and_candidate_blob_bytes_must_match_exactly(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    repository = tmp_path / "repository"
    attributes = b"* text=auto eol=lf\n*.ps1 text eol=lf\n"
    script_relative = "scripts/check.ps1"
    script_lf = b"$ErrorActionPreference = 'Stop'\nWrite-Output 'ok'\n"
    commit = create_candidate_commit(
        repository,
        {".gitattributes": attributes, script_relative: script_lf},
    )
    monkeypatch.setattr(checkpoints, "ROOT", repository)
    paths = [repository / ".gitattributes", repository / script_relative]

    checkpoints.require_git_clean_worktree_bytes("Example", paths)
    checkpoints.validate_reviewed_commit_paths("Example", commit, paths)

    script = repository / script_relative
    script.write_bytes(script_lf.replace(b"\n", b"\r\n"))
    with pytest.raises(SystemExit, match="Git-clean canonical bytes"):
        checkpoints.require_git_clean_worktree_bytes("Example", paths)
    with pytest.raises(SystemExit, match="reviewed input differs from reviewed commit"):
        checkpoints.validate_reviewed_commit_paths("Example", commit, paths)


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
    registry["packages"] = []
    baseline_source_set = manifest.get("sources")
    assert isinstance(baseline_source_set, list)
    registry["currentSourceSetSha256"] = checkpoints.sha256_payload(baseline_source_set)
    paths["source"].write_text("contract Example { /* unreviewed */ }\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="without an exact implementation checkpoint"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_auxiliary_source_checkpoint_updates_effective_source_set_without_schema_drift(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _paths, _historical = auxiliary_fixture(tmp_path, monkeypatch)
    checkpoint_package = registry["packages"][0]
    assert set(checkpoint_package) == checkpoints.EXPECTED_PACKAGE_KEYS
    assert set(checkpoint_package["revisions"][0]) == checkpoints.EXPECTED_REVISION_KEYS
    assert "auxiliarySources" not in checkpoint_package
    assert set(checkpoints.validate_checkpoints(manifest=manifest, registry=registry)) == {
        "Example"
    }


def test_undeclared_auxiliary_source_change_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _paths, _historical = auxiliary_fixture(tmp_path, monkeypatch)
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", {})
    with pytest.raises(SystemExit, match="reviewed Git source set is inconsistent"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_auxiliary_source_must_change_from_its_effective_predecessor(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths, historical = auxiliary_fixture(tmp_path, monkeypatch)
    canonical_read = checkpoints.reviewed_commit_file_bytes
    auxiliary_relative = paths["auxiliary"].relative_to(tmp_path).as_posix()

    def historical_auxiliary_blob(
        label: str, commit: str, relative_paths: tuple[str, ...]
    ) -> dict[str, bytes]:
        blobs = canonical_read(label, commit, relative_paths)
        if auxiliary_relative in blobs:
            blobs[auxiliary_relative] = historical
        return blobs

    monkeypatch.setattr(
        checkpoints,
        "reviewed_commit_file_bytes",
        historical_auxiliary_blob,
    )
    with pytest.raises(SystemExit, match="auxiliary source does not change"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_post_checkpoint_auxiliary_source_mutation_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths, _historical = auxiliary_fixture(tmp_path, monkeypatch)
    committed = {
        source["path"]: (tmp_path / source["path"]).read_bytes() for source in manifest["sources"]
    }

    def committed_blobs(
        _label: str, _commit: str, relative_paths: tuple[str, ...]
    ) -> dict[str, bytes]:
        return {relative: committed[relative] for relative in relative_paths}

    monkeypatch.setattr(checkpoints, "reviewed_commit_file_bytes", committed_blobs)
    checkpoints.validate_checkpoints(manifest=manifest, registry=registry)
    paths["auxiliary"].write_text("interface IExample { /* drift */ }\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="without an exact implementation checkpoint"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_auxiliary_source_ownership_validation_fails_closed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source_relative = "protocol/src/resolution/Example.sol"
    auxiliary_a = "protocol/src/interfaces/phase9/IAuxiliary.sol"
    auxiliary_z = "protocol/src/interfaces/phase9/ZAuxiliary.sol"
    source_path = tmp_path / source_relative
    source_path.parent.mkdir(parents=True)
    source_path.write_text("contract Example {}\n", encoding="utf-8")
    for relative in (auxiliary_a, auxiliary_z):
        path = tmp_path / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("interface Auxiliary {}\n", encoding="utf-8")

    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    dependencies = [tmp_path / source_relative, tmp_path / auxiliary_a, tmp_path / auxiliary_z]
    monkeypatch.setattr(
        checkpoints,
        "repository_solidity_dependency_paths",
        lambda _source: dependencies,
    )
    source_order = [source_relative, auxiliary_a, auxiliary_z]
    contracts = {"Example": {"sourcePath": source_relative}}
    activated: dict[str, tuple[str, ...]] = {"Example": ("mutate()",)}

    monkeypatch.setattr(
        checkpoints,
        "PACKAGE_AUXILIARY_SOURCE_OWNERS",
        {"P9-EXAMPLE-001": ((auxiliary_a, "Example"), (auxiliary_z, "Example"))},
    )
    assert checkpoints.package_auxiliary_source_owners(
        "P9-EXAMPLE-001", source_order, contracts, activated
    ) == ((auxiliary_a, "Example"), (auxiliary_z, "Example"))

    malformed = {"P9-EXAMPLE-001": [(auxiliary_a, "Example")]}
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", malformed)
    with pytest.raises(SystemExit, match="ownership is malformed"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    duplicate = {"P9-EXAMPLE-001": ((auxiliary_a, "Example"), (auxiliary_a, "Example"))}
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", duplicate)
    with pytest.raises(SystemExit, match="path is duplicated"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    unsorted = {"P9-EXAMPLE-001": ((auxiliary_z, "Example"), (auxiliary_a, "Example"))}
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", unsorted)
    with pytest.raises(SystemExit, match="paths are not ordinal"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    nonbaseline = {
        "P9-EXAMPLE-001": (("protocol/src/interfaces/phase9/IMissing.sol", "Example"),)
    }
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", nonbaseline)
    with pytest.raises(SystemExit, match="not in the baseline"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    overlap = {"P9-EXAMPLE-001": ((source_relative, "Example"),)}
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", overlap)
    with pytest.raises(SystemExit, match="overlaps an activated contract"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    wrong_owner = {"P9-EXAMPLE-001": ((auxiliary_a, "Other"),)}
    monkeypatch.setattr(checkpoints, "PACKAGE_AUXILIARY_SOURCE_OWNERS", wrong_owner)
    with pytest.raises(SystemExit, match="owner is not activated"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )

    monkeypatch.setattr(
        checkpoints,
        "PACKAGE_AUXILIARY_SOURCE_OWNERS",
        {"P9-EXAMPLE-001": ((auxiliary_a, "Example"),)},
    )
    monkeypatch.setattr(
        checkpoints,
        "repository_solidity_dependency_paths",
        lambda _source: [tmp_path / source_relative],
    )
    with pytest.raises(SystemExit, match="is not a dependency of Example"):
        checkpoints.package_auxiliary_source_owners(
            "P9-EXAMPLE-001", source_order, contracts, activated
        )


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
    entry = registry["packages"][0]["revisions"][0]
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
    write_review(registry["packages"][0], paths["review"])
    with pytest.raises(SystemExit, match="dependency closure hash is stale"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_external_helper_only_mutation_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, paths = fixture(tmp_path, monkeypatch)
    helper = external_helper_checkpoint(manifest, registry, paths)
    entry = registry["packages"][0]["revisions"][0]
    entry["dependencyClosureSha256"] = checkpoints.repository_solidity_dependency_hash(
        paths["source"]
    )
    write_review(registry["packages"][0], paths["review"])
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
        ".gitattributes",
        ".github/workflows/foundation.yml",
        ".mise.toml",
        "package.json",
        "pnpm-lock.yaml",
        "protocol/foundry.toml",
        "protocol/script/DeployPhase9Local.s.sol",
        "protocol/src/ProtocolCompilation.sol",
        "tools/verify_phase9_payoff_deployment.py",
        "infrastructure/local/phase9-payoff-deployment-candidate.schema.json",
        "infrastructure/local/phase9-payoff-deployment-evidence.schema.json",
        "infrastructure/local/phase9-payoff-deployment-code-hashes.json",
        "protocol/test/Phase9PayoffQuoteAcceptanceMap.sol",
        "models/foundation_model/src/unified_foundation/phase9_payoff_reference.py",
        "packages/phase9/typescript/payoffReference.ts",
        "pyproject.toml",
        "scripts/check-contract-sizes.py",
        "scripts/check-foundation.ps1",
        "scripts/prepare-foundry.ps1",
        "tsconfig.json",
        "uv.lock",
        "tools/check_phase9_implementation_checkpoints.py",
        "tools/compile_phase9_storage_layouts.mjs",
    }.issubset(paths)
    assert not any(
        path.startswith("security/reviews/")
        or path == "protocol/compatibility/phase9-implementation-checkpoints.json"
        or path == "docs/backlog/phase-9.csv"
        for path in paths
    )


def test_refinance_d1_evidence_paths_are_exact_shared_and_fail_closed() -> None:
    paths = checkpoints.REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS
    assert list(paths) == sorted(paths, key=lambda path: path.encode("utf-8"))
    assert len(paths) == len(set(paths))
    assert {
        "adr/0021-phase-9-atomic-refinance-authority-and-activation.md",
        "adr/0022-phase-9-factory-account-position-bootstrap-semantics.md",
        "adr/0023-phase-9-refinance-fixed-module-partition.md",
        "docs/architecture/phase-9-refinance-acceptance.md",
        "protocol/test/Phase9RefinanceBootstrapAcceptanceMap.sol",
        "protocol/test/Phase9RefinanceBootstrapHarness.sol",
        "protocol/test/Phase9RefinanceCustodyLienBootstrap.t.sol",
        "protocol/test/Phase9RefinanceFactoryBootstrap.t.sol",
        "protocol/test/Phase9RefinanceRequest.t.sol",
        "protocol/test/Phase9RefinanceRequestFuzz.t.sol",
        "protocol/test/Phase9RefinanceRequestGolden.t.sol",
        "protocol/test/Phase9RefinanceRequestInvariants.t.sol",
        "tools/check_phase9_refinance_linked_modules.py",
        "tools/tests/test_phase9_refinance_linked_modules.py",
    }.issubset(paths)
    refinance_contracts = checkpoints.ACTIVATION_PACKAGES["P9-REFI-001"]["contracts"]
    assert all(
        checkpoints.IMPLEMENTATION_EVIDENCE_PATHS[contract] is paths
        for contract in refinance_contracts
    )
    assert checkpoints.IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS == {
        "P9-REFI-001": "D2-D4 exact implementation evidence paths are not frozen"
    }


def test_refinance_package_cannot_activate_with_only_d1_evidence() -> None:
    registry = checkpoints.checkpoint_payload()
    registry["packages"].append(
        {
            "checkpointId": "P9-REFI-001",
            "requiredBacklogIds": [
                "UNI-ADR-016",
                "UNI-ADR-017",
                "UNI-ADR-018",
                "UNI-REFI-001",
                "UNI-REFI-002",
            ],
            "review": {},
            "revisions": [],
        }
    )
    with pytest.raises(SystemExit, match="D2-D4 exact implementation evidence paths"):
        checkpoints.validate_checkpoints(
            manifest=checkpoints.historical_manifest(),
            registry=registry,
            verify_current=False,
            verify_reviews=False,
            verify_backlog=False,
        )


def test_every_payoff_implementation_evidence_path_is_material_to_bundle_hash(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checkpoints, "ROOT", tmp_path)
    monkeypatch.setattr(
        checkpoints, "require_git_clean_worktree_bytes", lambda contract, paths: None
    )
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
    registry["packages"][0]["requiredBacklogIds"] = ["UNI-WRONG-001"]
    with pytest.raises(SystemExit, match="required backlog IDs drifted"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)

    registry["packages"][0]["requiredBacklogIds"] = ["UNI-ADR-015", "UNI-EXAMPLE-001"]
    monkeypatch.setattr(checkpoints, "ACTIVATION_PACKAGES", {})
    with pytest.raises(SystemExit, match="not activated"):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize("target", ("entry", "aggregate"))
def test_stale_or_tampered_current_source_set_hash_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, target: str
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    if target == "entry":
        registry["packages"][0]["revisions"][0]["sourceSetSha256"] = "sha256:" + "0" * 64
        message = "source-set checkpoint is stale"
    else:
        registry["currentSourceSetSha256"] = "sha256:" + "0" * 64
        message = "current implementation source-set hash is stale"
    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


@pytest.mark.parametrize(
    ("target", "message"),
    (("abi", "ABI|JSON array"), ("storage", "storage payload|storage snapshot")),
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
        (
            lambda registry, paths: registry["packages"][0]["review"].update(status="PENDING"),
            "status",
        ),
        (
            lambda registry, paths: registry["packages"][0]["review"].update(
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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])
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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])

    with pytest.raises(SystemExit, match=message):
        checkpoints.validate_checkpoints(manifest=manifest, registry=registry)


def test_checkpoint_identity_must_match_review_metadata(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    manifest, registry, _ = fixture(tmp_path, monkeypatch)
    registry["packages"][0]["review"]["toolingReviewer"] = "Substituted Reviewer"
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
    registry["packages"][0]["review"]["reviewSha256"] = checkpoints.sha256_file(paths["review"])
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


def ast_numbered_storage_payload(contract_id: int, enum_id: int, struct_id: int) -> dict[str, Any]:
    payload = storage_payload("Example", "protocol/src/resolution/Example.sol")
    contract_type = f"t_contract(IRegistry){contract_id}"
    enum_type = f"t_enum(State){enum_id}"
    struct_type = f"t_struct(Item){struct_id}_storage"
    array_type = f"t_array({struct_type})dyn_storage"
    mapping_type = f"t_mapping({contract_type},{array_type})"
    payload["storageLayout"] = {
        "storage": [
            {
                "contract": "protocol/src/resolution/Example.sol:Example",
                "label": "_items",
                "offset": 0,
                "slot": "0",
                "type": mapping_type,
            }
        ],
        "types": {
            contract_type: {
                "encoding": "inplace",
                "label": "contract IRegistry",
                "numberOfBytes": "20",
            },
            enum_type: {
                "encoding": "inplace",
                "label": "enum IExample.State",
                "numberOfBytes": "1",
            },
            struct_type: {
                "encoding": "inplace",
                "label": "struct IExample.Item",
                "members": [
                    {
                        "contract": "protocol/src/resolution/Example.sol:Example",
                        "label": "state",
                        "offset": 0,
                        "slot": "0",
                        "type": enum_type,
                    },
                    {
                        "contract": "protocol/src/resolution/Example.sol:Example",
                        "label": "registry",
                        "offset": 1,
                        "slot": "0",
                        "type": contract_type,
                    },
                ],
                "numberOfBytes": "32",
            },
            array_type: {
                "base": struct_type,
                "encoding": "dynamic_array",
                "label": "struct IExample.Item[]",
                "numberOfBytes": "32",
            },
            mapping_type: {
                "encoding": "mapping",
                "key": contract_type,
                "label": "mapping(contract IRegistry => struct IExample.Item[])",
                "numberOfBytes": "32",
                "value": array_type,
            },
        },
    }
    return payload


def test_structural_storage_normalizes_only_solc_ast_type_suffixes_across_graph() -> None:
    baseline = ast_numbered_storage_payload(101, 102, 103)
    renumbered = ast_numbered_storage_payload(901, 902, 903)

    assert checkpoints.structural_storage_hash(baseline) == checkpoints.structural_storage_hash(
        renumbered
    )
    layout = checkpoints.structural_storage_payload(baseline)["storageLayout"]
    full_payload = checkpoints.normalized_storage_payload(baseline)
    mapping_type = (
        "t_mapping(t_contract(IRegistry)<ast-id>,"
        "t_array(t_struct(Item)<ast-id>_storage)dyn_storage)"
    )
    assert layout["storage"][0]["type"] == mapping_type
    assert layout["storage"][0]["label"] == "_items"
    assert layout["storage"][0]["offset"] == 0
    assert layout["storage"][0]["slot"] == "0"
    assert mapping_type in layout["types"]
    assert layout["types"][mapping_type]["key"] == "t_contract(IRegistry)<ast-id>"
    assert layout["types"][mapping_type]["value"] == (
        "t_array(t_struct(Item)<ast-id>_storage)dyn_storage"
    )
    assert layout["types"][layout["types"][mapping_type]["value"]]["base"] == (
        "t_struct(Item)<ast-id>_storage"
    )
    assert layout["types"]["t_struct(Item)<ast-id>_storage"]["members"][0]["type"] == (
        "t_enum(State)<ast-id>"
    )
    assert layout["types"]["t_struct(Item)<ast-id>_storage"]["members"][0]["label"] == ("state")
    assert full_payload["freezeSurface"] == baseline["freezeSurface"]
    assert checkpoints.normalize_solc_storage_type_id("t_array(t_address)3_storage") == (
        "t_array(t_address)3_storage"
    )

    concrete_label_drift = copy.deepcopy(renumbered)
    concrete_label_drift["storageLayout"]["types"]["t_struct(Item)903_storage"]["label"] = (
        "struct OtherNamespace.Item"
    )
    assert checkpoints.structural_storage_hash(
        concrete_label_drift
    ) != checkpoints.structural_storage_hash(baseline)

    member_order_drift = copy.deepcopy(renumbered)
    member_order_drift["storageLayout"]["types"]["t_struct(Item)903_storage"]["members"].reverse()
    assert checkpoints.structural_storage_hash(
        member_order_drift
    ) != checkpoints.structural_storage_hash(baseline)


def test_structural_storage_type_normalization_collision_fails_closed() -> None:
    payload = ast_numbered_storage_payload(101, 102, 103)
    payload["storageLayout"]["types"]["t_struct(Item)104_storage"] = copy.deepcopy(
        payload["storageLayout"]["types"]["t_struct(Item)103_storage"]
    )
    with pytest.raises(SystemExit, match="storage type normalization collision"):
        checkpoints.structural_storage_hash(payload)


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
