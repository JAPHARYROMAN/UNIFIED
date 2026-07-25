from __future__ import annotations

import copy
import hashlib
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import build_phase9_compatibility_manifest as manifest  # noqa: E402
import check_phase9 as phase9  # noqa: E402
import check_phase9_storage_layouts as storage  # noqa: E402
import check_privileged_surface as privileged_surface  # noqa: E402


def sample_layout(contract: str = "Phase9LoanFactory") -> dict[str, Any]:
    settings = {
        "evmVersion": "prague",
        "optimizer": {"enabled": True, "runs": 200},
        "viaIR": False,
    }
    settings_hash = "sha256:" + hashlib.sha256(
        storage.canonical_json(settings).encode("utf-8")
    ).hexdigest()
    return {
        "compiler": {
            "openzeppelinVersion": "5.6.1",
            "settings": settings,
            "settingsHash": settings_hash,
            "version": "0.8.36+commit.12345678",
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
        "linearizedBases": [f"protocol/src/resolution/{contract}.sol:{contract}"],
        "schemaVersion": 1,
        "source": f"protocol/src/resolution/{contract}.sol",
        "storageLayout": {
            "storage": [
                {
                    "contract": f"protocol/src/resolution/{contract}.sol:{contract}",
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


def test_valid_storage_layout_passes() -> None:
    storage.validate_layout("Phase9LoanFactory", sample_layout())


@pytest.mark.parametrize(
    ("mutation", "message"),
    (
        (lambda payload: payload["compiler"].update(settingsHash="sha256:" + "0" * 64), "hash"),
        (
            lambda payload: payload["freezeSurface"]["stateVariables"][0].update(
                visibility="public"
            ),
            "public storage",
        ),
        (
            lambda payload: payload["freezeSurface"]["functions"][0].update(
                revertError=None
            ),
            "does not revert",
        ),
        (lambda payload: payload["storageLayout"].update(types={}), "unknown type ID"),
    ),
)
def test_storage_layout_negative_gates(mutation: Any, message: str) -> None:
    payload = sample_layout()
    mutation(payload)
    with pytest.raises(SystemExit, match=message):
        storage.validate_layout("Phase9LoanFactory", payload)


def test_storage_layout_rejects_self_consistent_but_wrong_compiler_settings() -> None:
    payload = sample_layout()
    payload["compiler"]["settings"]["optimizer"]["runs"] = 201
    payload["compiler"]["settingsHash"] = "sha256:" + hashlib.sha256(
        storage.canonical_json(payload["compiler"]["settings"]).encode("utf-8")
    ).hexdigest()
    with pytest.raises(SystemExit, match="compiler settings drifted"):
        storage.validate_layout("Phase9LoanFactory", payload)


def test_storage_comparison_detects_reordering_and_retyping() -> None:
    expected = sample_layout()
    actual = copy.deepcopy(expected)
    actual["storageLayout"]["storage"][0]["type"] = "t_uint64"
    assert ".type" in (storage.first_difference(expected, actual) or "")

    expected_list = [expected, {"contract": "second"}]
    actual_list = list(reversed(expected_list))
    assert "$[0]" in (storage.first_difference(expected_list, actual_list) or "")


def test_backlog_dependency_order_is_fail_closed() -> None:
    rows = {identifier: {"status": "TODO"} for identifier in phase9.BACKLOG_IDS}
    for identifier in phase9.BOUNDARY_COMPLETE_IDS:
        rows[identifier]["status"] = "DONE"
    phase9.check_backlog_precedence(rows)

    abi_before_schema = copy.deepcopy(rows)
    abi_before_schema["UNI-ABI-009"]["status"] = "DONE"
    with pytest.raises(SystemExit, match="UNI-SCHEMA-013"):
        phase9.check_backlog_precedence(abi_before_schema)

    implementation_before_abi = copy.deepcopy(rows)
    implementation_before_abi["UNI-PAYOFF-001"]["status"] = "DONE"
    with pytest.raises(SystemExit, match="UNI-ABI-009"):
        phase9.check_backlog_precedence(implementation_before_abi)


@pytest.mark.parametrize(
    "relative",
    (
        "protocol/src/resolution/OnlyInterface.sol",
        "protocol/src/protection/OnlyLibrary.sol",
        "protocol/src/recovery/Unimported.sol",
        "protocol/src/interfaces/phase9/IFixture.sol",
        "protocol/src/token/Phase9Unexpected.sol",
    ),
)
def test_phase9_source_paths_activate_freeze(relative: str) -> None:
    assert phase9.is_phase9_source_path(ROOT / relative)


def test_mutating_stub_source_must_be_exact_revert() -> None:
    accepted = """
    function mutate(bytes32) external returns (bytes32) {
        revert Phase9ImplementationNotFrozen();
    }
    """
    rejected = """
    function mutate(bytes32) external returns (bytes32) {
        return bytes32(0);
    }
    """
    assert phase9.is_exact_freeze_revert(phase9.solidity_function_bodies(accepted)[0][1])
    assert not phase9.is_exact_freeze_revert(phase9.solidity_function_bodies(rejected)[0][1])


def test_manifest_hash_is_semantic_and_deterministic() -> None:
    left = {"b": [2, 1], "a": {"z": True}}
    right = {"a": {"z": True}, "b": [2, 1]}
    assert manifest.sha256_payload(left) == manifest.sha256_payload(right)
    assert manifest.sha256_payload(left) != manifest.sha256_payload(
        {"b": [1, 2], "a": {"z": True}}
    )


def test_manifest_hash_binds_the_complete_reviewed_source_set() -> None:
    payload = manifest.expected_manifest()
    sources = payload["sources"]
    assert isinstance(sources, list)
    assert len(sources) == 32
    assert all(set(source) == {"path", "sha256"} for source in sources)
    assert all(str(source["path"]).endswith(".sol") for source in sources)

    tampered = copy.deepcopy(payload)
    tampered["sources"][0]["sha256"] = "sha256:" + "0" * 64
    assert manifest.manifest_hash(tampered) != manifest.manifest_hash(payload)
    assert manifest.source_set_hash(tampered) != manifest.source_set_hash(payload)


@pytest.mark.parametrize(
    ("paths", "message"),
    (
        (set(manifest.EXPECTED_SOURCE_PATHS[1:]), "missing="),
        (
            {*manifest.EXPECTED_SOURCE_PATHS, "protocol/src/resolution/Unexpected.sol"},
            "unexpected=",
        ),
    ),
)
def test_manifest_rejects_source_set_addition_or_removal(
    paths: set[str], message: str
) -> None:
    with pytest.raises(SystemExit, match=message):
        manifest.validate_source_paths(paths)


def test_privileged_surface_allows_only_exact_phase9_constructor_mint(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    source_root = tmp_path / "protocol" / "src"
    token_path = source_root / "token" / "Phase9LocalSyntheticToken.sol"
    token_path.parent.mkdir(parents=True)
    valid_source = """
contract Phase9LocalSyntheticToken is ERC20 {
    uint256 public constant FIXED_SUPPLY_UNITS =
        1_000_000_000_000_000;

    constructor(address fixtureAllocator)
        ERC20("Unified Phase 9 Local Synthetic Unit", "P9UNIT")
    {
        if (block.chainid != 31337) revert InvalidLocalChain(block.chainid);
        if (fixtureAllocator == address(0)) revert InvalidFixtureAllocator();
        _mint(fixtureAllocator, FIXED_SUPPLY_UNITS);
    }
}
"""
    token_path.write_text(valid_source, encoding="utf-8")
    monkeypatch.setattr(privileged_surface, "SOURCE_ROOT", source_root)

    privileged_surface.main()

    token_path.write_text(
        valid_source.replace(
            "_mint(fixtureAllocator, FIXED_SUPPLY_UNITS);",
            "_mint(msg.sender, FIXED_SUPPLY_UNITS);",
        ),
        encoding="utf-8",
    )
    with pytest.raises(SystemExit, match="constructor-only synthetic issuance changed"):
        privileged_surface.main()
