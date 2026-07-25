from __future__ import annotations

import copy
import json
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
        "backlogId": "UNI-EXAMPLE-001",
        "contract": "Example",
        "reviewPath": review_relative,
        "reviewSha256": "",
        "sourceSha256": current_source_hash,
        "sourceSetSha256": current_source_set_hash,
        "status": "PASS",
        "storageStructuralSha256": checkpoints.structural_storage_hash(storage),
    }
    review_path.parent.mkdir(parents=True, exist_ok=True)
    review_path.write_text(
        "\n".join(
            (
                "Decision: PASS",
                "Architecture review: PASS",
                "Security review: PASS",
                "Example",
                "UNI-EXAMPLE-001",
                entry["sourceSha256"],
                entry["sourceSetSha256"],
                entry["abiSha256"],
                entry["storageStructuralSha256"],
            )
        )
        + "\n",
        encoding="utf-8",
    )
    entry["reviewSha256"] = checkpoints.sha256_file(review_path)
    registry = {
        "baseline": {
            "commit": checkpoints.BASELINE_COMMIT,
            "manifestSha256": checkpoints.BASELINE_MANIFEST_SHA256,
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
    monkeypatch.setattr(checkpoints, "ROOT", root)
    monkeypatch.setattr(checkpoints, "BACKLOG_PATH", backlog_path)
    monkeypatch.setattr(checkpoints, "SECURITY_REVIEW_ROOT", review_path.parent)
    monkeypatch.setattr(checkpoints, "SOURCE_ROOTS", (source_path.parent,))
    monkeypatch.setattr(checkpoints, "TOKEN_SOURCE", source_path)
    monkeypatch.setattr(checkpoints, "ACTIVATED_IMPLEMENTATIONS", {"Example": "UNI-EXAMPLE-001"})
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
    with pytest.raises(SystemExit, match="review status or hashes mismatch"):
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
    assert checkpoints.historical_manifest() == payload

    payload["schemaVersion"] = 3
    write_json(path, payload)
    with pytest.raises(SystemExit, match="schema drifted|identity drifted"):
        checkpoints.historical_manifest()
