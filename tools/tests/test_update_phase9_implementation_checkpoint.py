from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import update_phase9_implementation_checkpoint as updater  # noqa: E402


def _manifest() -> dict[str, Any]:
    abi = json.loads(
        (ROOT / "protocol/abi/phase9/PayoffQuoteEngine.abi.json").read_text(encoding="utf-8")
    )
    return {
        "contracts": [
            {
                "abiPath": "protocol/abi/phase9/PayoffQuoteEngine.abi.json",
                "abiSha256": updater.sha256_payload(abi),
                "contract": "PayoffQuoteEngine",
                "sourcePath": "protocol/src/resolution/PayoffQuoteEngine.sol",
                "sourceSha256": "sha256:" + "b" * 64,
                "storagePath": "protocol/storage-layout/phase9/PayoffQuoteEngine.storage.json",
                "storageSha256": "sha256:" + "c" * 64,
            },
            {
                "abiPath": "protocol/abi/phase9/Phase9LocalSyntheticToken.abi.json",
                "abiSha256": "sha256:" + "d" * 64,
                "contract": "Phase9LocalSyntheticToken",
                "sourcePath": "protocol/src/token/Phase9LocalSyntheticToken.sol",
                "sourceSha256": "sha256:" + "e" * 64,
                "storagePath": (
                    "protocol/storage-layout/phase9/Phase9LocalSyntheticToken.storage.json"
                ),
                "storageSha256": "sha256:" + "f" * 64,
            },
        ]
    }


def _registry() -> dict[str, Any]:
    return {"packages": []}


def _candidate_mocks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(updater, "validate_checkpoints", lambda **_kwargs: {})
    monkeypatch.setattr(updater, "sha256_file", lambda _path: "sha256:" + "1" * 64)
    monkeypatch.setattr(
        updater,
        "repository_solidity_dependency_hash",
        lambda _path: "sha256:" + "2" * 64,
    )
    monkeypatch.setattr(
        updater,
        "current_reviewed_source_set_hash",
        lambda _manifest: "sha256:" + "3" * 64,
    )
    monkeypatch.setattr(
        updater,
        "current_compatible_storage_hash",
        lambda _contract: "sha256:" + "4" * 64,
    )
    monkeypatch.setattr(
        updater,
        "implementation_evidence_bundle_hash",
        lambda _contract: "sha256:" + "5" * 64,
    )


def test_candidate_evidence_prepares_package_without_review_or_pass_status(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _candidate_mocks(monkeypatch)
    evidence = updater.candidate_evidence("P9-PAYOFF-001", _manifest(), registry=_registry())

    assert evidence["checkpointId"] == "P9-PAYOFF-001"
    assert evidence["requiredBacklogIds"] == ["UNI-ADR-015", "UNI-PAYOFF-001"]
    assert "review" not in evidence
    [revision] = evidence["revisions"]
    assert revision["activatedSignatures"] == [
        "consumeQuote(bytes32,bytes32,uint64,bytes32)",
        "invalidateQuote(bytes32,bytes32)",
        "issueQuote(bytes32,uint64)",
    ]
    assert revision["revision"] == 1
    assert revision["supersedes"] is None
    assert revision["dependencyClosureSha256"] == "sha256:" + "2" * 64
    assert revision["implementationEvidenceBundleSha256"] == "sha256:" + "5" * 64
    assert revision["sourceSha256"] == "sha256:" + "1" * 64
    assert revision["sourceSetSha256"] == "sha256:" + "3" * 64
    assert revision["storageStructuralSha256"] == "sha256:" + "4" * 64


def test_candidate_package_binds_structured_review_metadata(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    review = ROOT / "security/reviews/phase-9-payoff-quote-engine.md"
    evidence = {
        "checkpointId": "P9-PAYOFF-001",
        "requiredBacklogIds": ["UNI-ADR-015", "UNI-PAYOFF-001"],
        "revisions": [],
    }
    metadata = {
        "implementationAuthor": "Implementation Author",
        "architectureReviewer": "Architecture Reviewer",
        "securityReviewer": "Security Reviewer",
        "toolingReviewer": "Tooling Reviewer",
        "reviewedCommit": "1" * 40,
    }
    monkeypatch.setattr(updater, "candidate_evidence", lambda *_args, **_kwargs: evidence)
    monkeypatch.setattr(updater, "validate_review_path", lambda _path: review)
    monkeypatch.setattr(updater, "review_content", lambda _path: "review")
    monkeypatch.setattr(
        updater, "require_unambiguous_review_pass", lambda _package, _content: metadata
    )
    monkeypatch.setattr(updater, "sha256_file", lambda _path: "sha256:" + "1" * 64)

    checkpoint_package = updater.candidate_package(
        "P9-PAYOFF-001",
        "security/reviews/phase-9-payoff-quote-engine.md",
        _manifest(),
        registry=_registry(),
    )
    assert checkpoint_package == {
        **evidence,
        "review": {
            **metadata,
            "reviewPath": "security/reviews/phase-9-payoff-quote-engine.md",
            "reviewSha256": "sha256:" + "1" * 64,
            "status": "PASS",
        },
    }


def test_candidate_evidence_rejects_unactivated_package() -> None:
    with pytest.raises(SystemExit, match="package is not activated"):
        updater.candidate_evidence("P9-WRONG-001", _manifest(), registry=_registry())


def test_refinance_candidate_preflight_rejects_incomplete_d2_d4_closure_before_work(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    manifest = _manifest()

    def bomb(*_args: object, **_kwargs: object) -> object:
        raise AssertionError("candidate hashing/storage work ran before evidence-path preflight")

    for name in (
        "additive_abi_payload",
        "baseline_contracts",
        "current_compatible_storage_hash",
        "current_reviewed_source_set_hash",
        "implementation_evidence_bundle_hash",
        "read_json",
        "repository_solidity_dependency_hash",
        "sha256_file",
        "sha256_payload",
        "validate_checkpoints",
    ):
        monkeypatch.setattr(updater, name, bomb)

    expected = (
        "P9-REFI-001: implementation evidence closure is incomplete: "
        "D2-D4 exact implementation evidence paths are not frozen"
    )
    with pytest.raises(SystemExit) as failure:
        updater.candidate_evidence("P9-REFI-001", manifest, registry=_registry())
    assert str(failure.value) == expected


def test_candidate_generation_allows_dirty_sources_but_requires_current_storage(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    observed: list[bool] = []

    def validate(**kwargs: Any) -> dict[str, dict[str, Any]]:
        observed.append(kwargs["verify_current"])
        return {}

    _candidate_mocks(monkeypatch)
    monkeypatch.setattr(updater, "validate_checkpoints", validate)
    updater.candidate_evidence("P9-PAYOFF-001", _manifest(), registry=_registry())
    assert observed == [False]

    def reject_storage(_contract: str) -> str:
        raise SystemExit("compiled storage evidence is stale")

    monkeypatch.setattr(updater, "current_compatible_storage_hash", reject_storage)
    with pytest.raises(SystemExit, match="compiled storage evidence is stale"):
        updater.candidate_evidence("P9-PAYOFF-001", _manifest(), registry=_registry())
