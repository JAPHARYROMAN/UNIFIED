from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any, cast

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import build_phase9_compatibility_manifest as manifest  # noqa: E402
import check_abi as abi  # noqa: E402
import check_phase9 as phase9  # noqa: E402
import check_phase9_implementation_checkpoints as checkpoints  # noqa: E402
import check_phase9_storage_layouts as storage  # noqa: E402
import check_privileged_surface as privileged_surface  # noqa: E402


def foundry_config() -> dict[str, Any]:
    with (ROOT / "protocol/foundry.toml").open("rb") as handle:
        return tomllib.load(handle)


def sample_layout(contract: str = "Phase9LoanFactory") -> dict[str, Any]:
    settings = {
        "evmVersion": "prague",
        "optimizer": {"enabled": True, "runs": 200},
        "viaIR": False,
    }
    settings_hash = (
        "sha256:" + hashlib.sha256(storage.canonical_json(settings).encode("utf-8")).hexdigest()
    )
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
            lambda payload: payload["freezeSurface"]["functions"][0].update(revertError=None),
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
    payload["compiler"]["settingsHash"] = (
        "sha256:"
        + hashlib.sha256(
            storage.canonical_json(payload["compiler"]["settings"]).encode("utf-8")
        ).hexdigest()
    )
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


def test_compiled_storage_artifact_requires_exact_fresh_dependency_closure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    artifact_path = tmp_path / "phase9-storage-layouts.json"
    dependency_hash = "sha256:" + "1" * 64
    artifact = {
        "compilationDependencyClosureSha256": dependency_hash,
        "contracts": {"Phase9LoanFactory": sample_layout()},
        "schemaVersion": 2,
    }
    artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
    monkeypatch.setattr(storage, "ACTUAL_PATH", artifact_path)
    monkeypatch.setattr(storage, "PHASE9_CONTRACTS", ("Phase9LoanFactory",))
    monkeypatch.setattr(
        storage, "repository_solidity_dependency_hash", lambda _path: dependency_hash
    )

    assert set(storage.load_actual_layouts()) == {"Phase9LoanFactory"}

    monkeypatch.setattr(
        storage,
        "repository_solidity_dependency_hash",
        lambda _path: "sha256:" + "2" * 64,
    )
    with pytest.raises(SystemExit, match="artifact is stale"):
        storage.load_actual_layouts()

    artifact.pop("compilationDependencyClosureSha256")
    artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
    with pytest.raises(SystemExit, match="unsupported schema"):
        storage.load_actual_layouts()


def test_checked_implementation_hash_loads_and_compares_in_implemented_mode(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    layout = sample_layout("PayoffQuoteEngine")
    observed: list[tuple[str, set[str]]] = []

    def load(implemented: set[str] | None = None) -> dict[str, dict[str, Any]]:
        observed.append(("load", set() if implemented is None else implemented))
        return {"PayoffQuoteEngine": layout}

    def compare(
        _actual: dict[str, dict[str, Any]], implemented: set[str] | None = None
    ) -> None:
        observed.append(("compare", set() if implemented is None else implemented))

    monkeypatch.setattr(storage, "load_actual_layouts", load)
    monkeypatch.setattr(storage, "check_snapshots", compare)
    expected = checkpoints.structural_storage_hash(layout)

    assert storage.checked_implementation_storage_hash("PayoffQuoteEngine") == expected
    assert observed == [
        ("load", {"PayoffQuoteEngine"}),
        ("compare", {"PayoffQuoteEngine"}),
    ]


def test_backlog_dependency_order_is_fail_closed() -> None:
    rows = {identifier: {"status": "TODO"} for identifier in phase9.BACKLOG_IDS}
    for identifier in phase9.BOUNDARY_COMPLETE_IDS:
        rows[identifier]["status"] = "DONE"
    rows["UNI-SCHEMA-013"]["status"] = "DONE"
    rows["UNI-ABI-009"]["status"] = "DONE"
    phase9.check_backlog_precedence(rows)

    abi_before_schema = copy.deepcopy(rows)
    abi_before_schema["UNI-SCHEMA-013"]["status"] = "TODO"
    with pytest.raises(SystemExit, match="UNI-SCHEMA-013"):
        phase9.check_backlog_precedence(abi_before_schema)

    implementation_before_abi = copy.deepcopy(rows)
    implementation_before_abi["UNI-ABI-009"]["status"] = "TODO"
    implementation_before_abi["UNI-PAYOFF-001"]["status"] = "DONE"
    with pytest.raises(SystemExit, match="UNI-ABI-009"):
        phase9.check_backlog_precedence(implementation_before_abi)

    implementation_before_activation = copy.deepcopy(rows)
    implementation_before_activation["UNI-ADR-015"]["status"] = "TODO"
    implementation_before_activation["UNI-PAYOFF-001"]["status"] = "DONE"
    with pytest.raises(SystemExit, match="UNI-ADR-015"):
        phase9.check_backlog_precedence(implementation_before_activation)

    for refinance_id in ("UNI-REFI-001", "UNI-REFI-002"):
        for required_adr in ("UNI-ADR-016", "UNI-ADR-017"):
            refinance_before_activation = copy.deepcopy(rows)
            refinance_before_activation[required_adr]["status"] = "TODO"
            refinance_before_activation[refinance_id]["status"] = "DONE"
            with pytest.raises(SystemExit, match=required_adr):
                phase9.check_backlog_precedence(refinance_before_activation)


def test_refinance_activation_row_and_acceptance_inventory_are_exact() -> None:
    refinance_index = phase9.BACKLOG_IDS.index("UNI-REFI-001")
    assert phase9.BACKLOG_IDS[refinance_index - 2 : refinance_index] == (
        "UNI-ADR-016",
        "UNI-ADR-017",
    )
    assert {"UNI-ADR-016", "UNI-ADR-017"}.issubset(phase9.BOUNDARY_COMPLETE_IDS)
    assert phase9.FACTORY_BOOTSTRAP_ADR_PATH in phase9.BOUNDARY_PATHS
    assert len(phase9.REQUIRED_REFINANCE_ACCEPTANCE_IDS) == 80
    assert "P9R-COMPAT-003" in phase9.REQUIRED_REFINANCE_ACCEPTANCE_IDS
    assert "P9R-DON-004" in phase9.REQUIRED_REFINANCE_ACCEPTANCE_IDS
    assert "P9R-EVT-003" in phase9.REQUIRED_REFINANCE_ACCEPTANCE_IDS
    assert "P9R-LOCAL-003" in phase9.REQUIRED_REFINANCE_ACCEPTANCE_IDS


def test_refinance_boundary_evidence_is_exact() -> None:
    phase9.check_refinance_boundary_evidence()


@pytest.mark.parametrize(
    ("path", "target", "replacement", "message"),
    (
        (
            phase9.FACTORY_BOOTSTRAP_ADR_PATH,
            "Work item: `UNI-ADR-017`",
            "Work item: `UNI-ADR-999`",
            "factory/account/position bootstrap semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "exact `newLoanNonce == refinanceNonce` checks",
            "exact `newLoanNonce != refinanceNonce` checks",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "it is not a separately stored counter",
            "it is a separately stored counter",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            'keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST")',
            'keccak256("CAPABILITY_PHASE9_REQUEST")',
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            'keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING")',
            'keccak256("CAPABILITY_PHASE9_FUNDING")',
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "After the local old-loan lock is acquired and before any resolver/bootstrap/quote\n"
            "effect, request acceptance calls `emergencyState` with the request capability",
            "Before the local old-loan lock is acquired, request acceptance calls "
            "`emergencyState` with the request capability",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "exact replay returns inert and changed reuse conflicts without an\n"
            "emergency lookup. Only a first new commitment checks the funding capability",
            "exact replay consults the pause before classification",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "Execute, cancel, expiry, and refund do not\nconsult either capability",
            "Execute, cancel, expiry, and refund consult either capability",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "authenticates `msg.sender` as the coordinator resolved\n"
            "from its immutable lien registry",
            "authenticates `msg.sender` as the borrower",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "reconstructs this identity from the operation ID and record/resolver facts",
            "reconstructs this identity from record/resolver facts",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "asset_registry,\n  bootstrap_custody_operation_id,\n  collateral_id,",
            "asset_registry,\n  bootstrap_id,\n  collateral_id,",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "chainid, refinance_coordinator, bootstrap_id, old_loan_id,\n"
            "  collateral_custody, collateral_id",
            "chainid, refinance_coordinator, bootstrap_id,\n"
            "  collateral_custody, collateral_id",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "Reuse of an operation ID with a changed record, or use of an\n"
            "alternate operation ID for an existing collateral record, conflicts",
            "Changed-record operation-ID reuse is accepted",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "Only `bootstrap_custody_operation_id` is carried by a frozen selector",
            "Only `bootstrap_activation_operation_id` is carried by a frozen selector",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ADR_PATH,
            "activation, tranche, position,\nand lien operation IDs are deterministic "
            "reference/evidence correlation hashes only",
            "activation, tranche, position, and lien operation IDs are contract authority",
            "atomic-refinance semantic boundary",
        ),
        (
            phase9.REFINANCE_ACCEPTANCE_PATH,
            "exact funding replay remains inert, changed reuse still conflicts",
            "exact funding replay is paused before classification",
            "refinance acceptance semantics",
        ),
        (
            phase9.REFINANCE_REFERENCE_EVIDENCE_PATH,
            "Only `bootstrap_custody_operation_id` is passed through a frozen contract selector",
            "",
            "refinance reference evidence",
        ),
        (
            phase9.REFINANCE_REFERENCE_EVIDENCE_PATH,
            "asset_registry,\n  bootstrap_custody_operation_id,\n  collateral_id,",
            "asset_registry,\n  bootstrap_id,\n  collateral_id,",
            "refinance reference evidence",
        ),
        (
            phase9.REFINANCE_REFERENCE_EVIDENCE_PATH,
            "  bootstrap_id,\n  old_loan_id,\n  collateral_custody,",
            "  bootstrap_id,\n  collateral_custody,",
            "refinance reference evidence",
        ),
        (
            phase9.DATA_LAYOUTS_PATH,
            "marks the operation processed, records `HELD`, and increases\n"
            "checked `total exact custody` before calling `transferFrom`",
            "calls `transferFrom` before recording custody state",
            "refinance data-layout custody semantics",
        ),
    ),
)
def test_refinance_stage0_semantic_corrections_fail_closed(
    monkeypatch: pytest.MonkeyPatch,
    path: Path,
    target: str,
    replacement: str,
    message: str,
) -> None:
    canonical_read = phase9.read

    def mutated_read(candidate: Path) -> str:
        text = canonical_read(candidate)
        if candidate != path:
            return text
        assert target in text
        return text.replace(target, replacement, 1)

    monkeypatch.setattr(phase9, "read", mutated_read)
    with pytest.raises(SystemExit, match=message):
        phase9.check_refinance_boundary_evidence()


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


def implemented_abi_compatibility_fixture(extra_body: str = "") -> str:
    return f'''
import {{ Phase9ImplementationNotFrozen }} from "../interfaces/phase9/Phase9Errors.sol";

contract Example {{
    function mutate() external {{
        if (msg.data.length == 0) _phase9FrozenErrorCompatibilityMarker();
        {extra_body}
    }}

    function _phase9FrozenErrorCompatibilityMarker() private pure {{
        revert Phase9ImplementationNotFrozen();
    }}
}}
'''


def test_activated_contract_allows_only_exact_unreachable_freeze_abi_marker() -> None:
    phase9.check_implemented_freeze_abi_compatibility(
        "Example", implemented_abi_compatibility_fixture()
    )
    phase9.check_phase9_stub_sources(
        phase9.protocol_compilation_imports(),
        implemented={"PayoffQuoteEngine"},
    )


def test_activated_contract_rejects_exact_freeze_behavior_on_public_mutator() -> None:
    source = implemented_abi_compatibility_fixture(
        "revert Phase9ImplementationNotFrozen();"
    )
    with pytest.raises(SystemExit, match="retains fail-closed freeze behavior"):
        phase9.check_implemented_freeze_abi_compatibility("Example", source)


@pytest.mark.parametrize(
    "replacement",
    (
        "_phase9FrozenErrorCompatibilityMarker();",
        "if (msg.data.length > 0) _phase9FrozenErrorCompatibilityMarker();",
        "if (msg.sender != address(0)) _phase9FrozenErrorCompatibilityMarker();",
    ),
)
def test_activated_contract_rejects_reachable_freeze_marker_paths(replacement: str) -> None:
    source = implemented_abi_compatibility_fixture().replace(
        "if (msg.data.length == 0) _phase9FrozenErrorCompatibilityMarker();",
        replacement,
    )
    with pytest.raises(SystemExit, match="reachable freeze ABI marker path"):
        phase9.check_implemented_freeze_abi_compatibility("Example", source)


@pytest.mark.parametrize(
    ("mutation", "message"),
    (
        (
            lambda source: source.replace("private pure", "internal pure"),
            "must be exactly private pure",
        ),
        (
            lambda source: source.replace(
                "revert Phase9ImplementationNotFrozen();",
                "if (false) revert Phase9ImplementationNotFrozen();",
            ),
            "marker body is not exact",
        ),
        (
            lambda source: source.replace(
                "_phase9FrozenErrorCompatibilityMarker() private pure",
                "_renamedCompatibilityMarker() private pure",
            ),
            "exactly one named freeze ABI compatibility marker",
        ),
    ),
)
def test_activated_contract_rejects_malformed_freeze_abi_marker(
    mutation: Any, message: str
) -> None:
    with pytest.raises(SystemExit, match=message):
        phase9.check_implemented_freeze_abi_compatibility(
            "Example", mutation(implemented_abi_compatibility_fixture())
        )


def test_nonimplemented_stub_checks_remain_fail_closed(tmp_path: Path) -> None:
    imports = phase9.protocol_compilation_imports()
    factory_source = imports["Phase9LoanFactory"].read_text(encoding="utf-8")
    mutated_source = factory_source.replace(
        "revert Phase9ImplementationNotFrozen();",
        "if (false) revert Phase9ImplementationNotFrozen();",
        1,
    )
    mutated_path = tmp_path / "Phase9LoanFactory.sol"
    mutated_path.write_text(mutated_source, encoding="utf-8")
    imports["Phase9LoanFactory"] = mutated_path

    with pytest.raises(SystemExit, match="successful or non-canonical mutating stub path"):
        phase9.check_phase9_stub_sources(imports, implemented={"PayoffQuoteEngine"})


def test_method_level_activation_keeps_unopened_mutators_frozen(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = """
    contract Example {
        function opened() external { uint256 value = 1; value; }
        function closed() external { revert Phase9ImplementationNotFrozen(); }
    }
    """
    path = tmp_path / "Example.sol"
    path.write_text(source, encoding="utf-8")
    monkeypatch.setattr(phase9, "PHASE9_PRODUCTION_CONTRACTS", ("Example",))

    phase9.check_phase9_stub_sources(
        {"Example": path},
        {"Example": frozenset({"opened()"})},
    )

    path.write_text(
        source.replace(
            "uint256 value = 1; value;",
            "revert Phase9ImplementationNotFrozen();",
        ),
        encoding="utf-8",
    )
    with pytest.raises(SystemExit, match="opened retains exact freeze behavior"):
        phase9.check_phase9_stub_sources(
            {"Example": path},
            {"Example": frozenset({"opened()"})},
        )


def test_payoff_quote_engine_compiled_abi_remains_historical(tmp_path: Path) -> None:
    pnpm = shutil.which("pnpm")
    assert pnpm is not None, "pnpm is required to compile the Phase 9 historical ABI gate"
    subprocess.run(  # noqa: S603 - executable is resolved from the controlled toolchain PATH
        [
            pnpm,
            "exec",
            "solcjs",
            "--base-path",
            str(ROOT),
            "--include-path",
            str(ROOT / "node_modules"),
            "--abi",
            "-o",
            str(tmp_path),
            str(ROOT / "protocol/src/resolution/PayoffQuoteEngine.sol"),
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    compiled_path = tmp_path / "protocol_src_resolution_PayoffQuoteEngine_sol_PayoffQuoteEngine.abi"
    baseline_path = ROOT / "protocol/abi/phase9/PayoffQuoteEngine.abi.json"
    assert json.loads(compiled_path.read_text(encoding="utf-8")) == json.loads(
        baseline_path.read_text(encoding="utf-8")
    )


def test_phase9_abi_checker_uses_baselines_until_package_activation() -> None:
    expected = abi.phase9_expected_abis()
    for contract, (_compiled_path, baseline_path) in abi.ABI_PAIRS.items():
        if contract in abi._PHASE9_CONTRACT_SOURCES:
            assert expected[contract] == json.loads(baseline_path.read_text(encoding="utf-8"))


def test_phase9_abi_checker_applies_only_full_refinance_package_additions(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(abi, "validate_checkpoints", lambda **_kwargs: {})
    refinance_contracts = cast(
        dict[str, tuple[str, ...]],
        checkpoints.ACTIVATION_PACKAGES["P9-REFI-001"]["contracts"],
    )
    registry = {
        "packages": [
            {
                "checkpointId": "P9-REFI-001",
                "revisions": [{"contract": contract} for contract in refinance_contracts],
            }
        ]
    }
    expected = abi.phase9_expected_abis(registry)

    for contract in refinance_contracts:
        baseline_path = abi.ABI_PAIRS[contract][1]
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        additions = cast(
            dict[str, tuple[dict[str, Any], ...]],
            checkpoints.ACTIVATION_PACKAGES["P9-REFI-001"]["abiAdditions"],
        ).get(contract, ())
        assert expected[contract] == checkpoints.additive_abi_payload(baseline, additions)

    coordinator_abi = cast(list[dict[str, Any]], expected["RefinanceCoordinator"])
    lien_abi = cast(list[dict[str, Any]], expected["LienRegistry"])
    coordinator_names = {item.get("name") for item in coordinator_abi}
    lien_names = {item.get("name") for item in lien_abi}
    assert {"RefinanceStateTransitioned", "UnknownFundingCommitment"} <= coordinator_names
    assert "UnknownLienHandoff" in lien_names
    assert "UnknownUnauthorizedRecord" not in coordinator_names | lien_names


def test_phase9_foundry_warning_policy_is_exact() -> None:
    phase9.check_phase9_foundry_warning_policy(
        phase9.protocol_compilation_imports(),
        foundry_config(),
        implemented={"PayoffQuoteEngine"},
    )


@pytest.mark.parametrize("mutation", ("expansion", "removal", "global", "broad"))
def test_phase9_foundry_warning_policy_rejects_scope_drift(mutation: str) -> None:
    config = copy.deepcopy(foundry_config())
    default = config["profile"]["default"]
    entries = default["ignored_error_codes_from"]
    if mutation == "expansion":
        entries.append(["src/resolution/Unrelated.sol", [2018]])
        message = "exception set drifted"
    elif mutation == "removal":
        entries.pop()
        message = "exception set drifted"
    elif mutation == "global":
        default["ignored_error_codes"].append(2018)
        message = "must not be ignored globally"
    else:
        default["ignored_warnings_from"] = ["src/resolution"]
        message = "broad path warning ignores"

    with pytest.raises(SystemExit, match=message):
        phase9.check_phase9_foundry_warning_policy(
            phase9.protocol_compilation_imports(),
            config,
            implemented={"PayoffQuoteEngine"},
        )


def test_implemented_contract_cannot_retain_a_broad_warning_exemption() -> None:
    config = copy.deepcopy(foundry_config())
    config["profile"]["default"]["ignored_error_codes_from"].append(
        ["src/resolution/PayoffQuoteEngine.sol", [2018]]
    )
    with pytest.raises(SystemExit, match="exception set drifted"):
        phase9.check_phase9_foundry_warning_policy(
            phase9.protocol_compilation_imports(),
            config,
            implemented={"PayoffQuoteEngine"},
        )


def test_manifest_hash_is_semantic_and_deterministic() -> None:
    left = {"b": [2, 1], "a": {"z": True}}
    right = {"a": {"z": True}, "b": [2, 1]}
    assert manifest.sha256_payload(left) == manifest.sha256_payload(right)
    assert manifest.sha256_payload(left) != manifest.sha256_payload({"b": [1, 2], "a": {"z": True}})


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
def test_manifest_rejects_source_set_addition_or_removal(paths: set[str], message: str) -> None:
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
