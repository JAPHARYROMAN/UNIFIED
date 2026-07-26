from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import update_phase9_implementation_checkpoint as updater  # noqa: E402


def _manifest() -> dict[str, Any]:
    return {
        "contracts": [
            {
                "abiPath": "protocol/abi/phase9/PayoffQuoteEngine.abi.json",
                "abiSha256": "sha256:" + "a" * 64,
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


def test_candidate_evidence_prepares_hashes_without_review_or_pass_status(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
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

    evidence = updater.candidate_evidence("PayoffQuoteEngine", "UNI-PAYOFF-001", _manifest())

    assert evidence == {
        "abiSha256": "sha256:" + "a" * 64,
        "backlogId": "UNI-PAYOFF-001",
        "contract": "PayoffQuoteEngine",
        "dependencyClosureSha256": "sha256:" + "2" * 64,
        "implementationEvidenceBundleSha256": "sha256:" + "5" * 64,
        "sourceSha256": "sha256:" + "1" * 64,
        "sourceSetSha256": "sha256:" + "3" * 64,
        "storageStructuralSha256": "sha256:" + "4" * 64,
    }
    assert "status" not in evidence
    assert "reviewPath" not in evidence
    assert "reviewSha256" not in evidence


def test_candidate_entry_binds_structured_review_metadata(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    review = ROOT / "security/reviews/phase-9-payoff-quote-engine.md"
    evidence = {
        "abiSha256": "sha256:" + "a" * 64,
        "backlogId": "UNI-PAYOFF-001",
        "contract": "PayoffQuoteEngine",
        "dependencyClosureSha256": "sha256:" + "b" * 64,
        "implementationEvidenceBundleSha256": "sha256:" + "c" * 64,
        "sourceSha256": "sha256:" + "d" * 64,
        "sourceSetSha256": "sha256:" + "e" * 64,
        "storageStructuralSha256": "sha256:" + "f" * 64,
    }
    metadata = {
        "implementationAuthor": "Implementation Author",
        "architectureReviewer": "Architecture Reviewer",
        "securityReviewer": "Security Reviewer",
        "toolingReviewer": "Tooling Reviewer",
        "reviewedCommit": "1" * 40,
    }
    monkeypatch.setattr(updater, "candidate_evidence", lambda *_args: evidence)
    monkeypatch.setattr(updater, "validate_review_path", lambda _path: review)
    monkeypatch.setattr(updater, "review_content", lambda _path: "review")
    monkeypatch.setattr(
        updater, "require_unambiguous_review_pass", lambda _contract, _content: metadata
    )
    monkeypatch.setattr(updater, "sha256_file", lambda _path: "sha256:" + "1" * 64)

    entry = updater.candidate_entry(
        "PayoffQuoteEngine",
        "UNI-PAYOFF-001",
        "security/reviews/phase-9-payoff-quote-engine.md",
        _manifest(),
    )
    assert entry == {
        **evidence,
        **metadata,
        "reviewPath": "security/reviews/phase-9-payoff-quote-engine.md",
        "reviewSha256": "sha256:" + "1" * 64,
        "status": "PASS",
    }


def test_candidate_evidence_rejects_backlog_substitution() -> None:
    with pytest.raises(SystemExit, match="backlog substitution"):
        updater.candidate_evidence("PayoffQuoteEngine", "UNI-REFI-001", _manifest())


def test_candidate_evidence_and_entry_fail_closed_on_current_storage_check(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def reject_storage(_contract: str) -> str:
        raise SystemExit("compiled storage evidence is stale")

    monkeypatch.setattr(updater, "current_compatible_storage_hash", reject_storage)
    with pytest.raises(SystemExit, match="compiled storage evidence is stale"):
        updater.candidate_evidence("PayoffQuoteEngine", "UNI-PAYOFF-001", _manifest())
    with pytest.raises(SystemExit, match="compiled storage evidence is stale"):
        updater.candidate_entry(
            "PayoffQuoteEngine",
            "UNI-PAYOFF-001",
            "security/reviews/phase-9-payoff-quote-engine.md",
            _manifest(),
        )
