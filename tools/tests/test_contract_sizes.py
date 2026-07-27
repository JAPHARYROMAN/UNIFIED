from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "check-contract-sizes.py"


def _load_checker() -> ModuleType:
    spec = importlib.util.spec_from_file_location("check_contract_sizes", SCRIPT)
    if spec is None or spec.loader is None:
        raise AssertionError("could not load contract-size checker")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _artifact(source: str, contract: str, size: int) -> dict[str, object]:
    return {
        "metadata": {
            "settings": {"compilationTarget": {source: contract}},
        },
        "deployedBytecode": {"object": "00" * size},
    }


def _write_artifact(
    out: Path,
    source_name: str,
    contract: str,
    payload: dict[str, object],
) -> None:
    directory = out / source_name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{contract}.json").write_text(json.dumps(payload), encoding="utf-8")


def test_oversized_plain_solidity_test_support_is_excluded_by_source_provenance(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    checker = _load_checker()
    out = tmp_path / "out"
    _write_artifact(
        out,
        "Phase9RefinanceBootstrapHarness.sol",
        "Phase9RefinanceRequestDeployer",
        _artifact(
            "test/Phase9RefinanceBootstrapHarness.sol",
            "Phase9RefinanceRequestDeployer",
            checker.LIMIT + 1,
        ),
    )
    monkeypatch.setattr(checker, "OUT", out)

    checker.main()

    assert "Production contract size check passed (0 artifacts)." in capsys.readouterr().out


def test_same_named_oversized_production_artifact_remains_fatal(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    checker = _load_checker()
    out = tmp_path / "out"
    _write_artifact(
        out,
        "Phase9RefinanceBootstrapHarness.sol",
        "Phase9RefinanceRequestDeployer",
        _artifact(
            "src/Phase9RefinanceBootstrapHarness.sol",
            "Phase9RefinanceRequestDeployer",
            checker.LIMIT + 1,
        ),
    )
    monkeypatch.setattr(checker, "OUT", out)

    with pytest.raises(SystemExit, match="Phase9RefinanceRequestDeployer"):
        checker.main()


@pytest.mark.parametrize(
    ("metadata", "contract_name"),
    [
        (None, "Support"),
        ({}, "Support"),
        ({"settings": {}}, "Support"),
        ({"settings": {"compilationTarget": {}}}, "Support"),
        (
            {
                "settings": {
                    "compilationTarget": {
                        "test/Support.sol": "Support",
                        "src/Production.sol": "Production",
                    }
                }
            },
            "Support",
        ),
        (
            {"settings": {"compilationTarget": {"test/../src/Production.sol": "Production"}}},
            "Production",
        ),
        ({"settings": {"compilationTarget": {"test//Support.sol": "Support"}}}, "Support"),
        ({"settings": {"compilationTarget": {"test/Support": "Support"}}}, "Support"),
        ({"settings": {"compilationTarget": {"test/Support.sol": "Other"}}}, "Support"),
    ],
)
def test_malformed_or_mismatched_target_fails_closed(metadata: object, contract_name: str) -> None:
    checker = _load_checker()
    assert not checker._is_test_support({"metadata": metadata}, contract_name)
