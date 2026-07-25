"""Compare deterministic Phase 9 compiler storage layouts with reviewed snapshots."""

from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Mapping
from pathlib import Path
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[1]
ACTUAL_PATH = ROOT / ".cache/solc/phase9-storage-layouts.json"
SNAPSHOT_ROOT = ROOT / "protocol/storage-layout/phase9"

PHASE9_CONTRACTS = (
    "Phase9LoanFactory",
    "Phase9LoanAccount",
    "PayoffQuoteEngine",
    "CollateralCustodyV2",
    "LienRegistry",
    "RefinanceCoordinator",
    "PositionManagerV2",
    "RestructuringController",
    "InsuranceReserveVault",
    "ReservePolicy",
    "InsuranceManager",
    "GuaranteeVault",
    "RecoveryManager",
    "Phase9LocalSyntheticToken",
)
EXPECTED_SETTINGS = {
    "evmVersion": "prague",
    "optimizer": {"enabled": True, "runs": 200},
    "viaIR": False,
}


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is not valid JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"{path.relative_to(ROOT)} must contain a JSON object")
    return cast(dict[str, Any], payload)


def canonical_json(payload: object) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def validate_layout(contract: str, payload: Mapping[str, Any]) -> None:
    if payload.get("schemaVersion") != 1:
        raise SystemExit(f"{contract}: unsupported storage snapshot schema")
    if payload.get("contract") != contract:
        raise SystemExit(f"{contract}: storage snapshot contract name drifted")
    source = payload.get("source")
    if not isinstance(source, str) or not source.startswith("protocol/src/"):
        raise SystemExit(f"{contract}: storage source is not repository-relative")

    compiler = payload.get("compiler")
    if not isinstance(compiler, dict):
        raise SystemExit(f"{contract}: compiler identity is missing")
    if not str(compiler.get("version", "")).startswith("0.8.36+"):
        raise SystemExit(f"{contract}: compiler version is not Solidity 0.8.36")
    if compiler.get("openzeppelinVersion") != "5.6.1":
        raise SystemExit(f"{contract}: OpenZeppelin version drifted")
    settings = compiler.get("settings")
    settings_hash = compiler.get("settingsHash")
    if not isinstance(settings, dict) or not isinstance(settings_hash, str):
        raise SystemExit(f"{contract}: compiler settings evidence is incomplete")
    if settings != EXPECTED_SETTINGS:
        raise SystemExit(f"{contract}: compiler settings drifted from the Phase 9 freeze")
    if re.fullmatch(r"sha256:[0-9a-f]{64}", settings_hash) is None:
        raise SystemExit(f"{contract}: compiler settings hash is malformed")
    expected_settings_hash = "sha256:" + hashlib.sha256(
        canonical_json(settings).encode("utf-8")
    ).hexdigest()
    if settings_hash != expected_settings_hash:
        raise SystemExit(f"{contract}: compiler settings hash does not match settings")

    linearized = payload.get("linearizedBases")
    if not isinstance(linearized, list) or not linearized:
        raise SystemExit(f"{contract}: linearized inheritance evidence is missing")
    if not isinstance(linearized[0], str) or not linearized[0].endswith(f":{contract}"):
        raise SystemExit(f"{contract}: linearized inheritance does not start with the contract")

    storage_layout = payload.get("storageLayout")
    if not isinstance(storage_layout, dict):
        raise SystemExit(f"{contract}: storageLayout is missing")
    storage = storage_layout.get("storage")
    types = storage_layout.get("types")
    if not isinstance(storage, list) or not isinstance(types, dict):
        raise SystemExit(f"{contract}: storageLayout graph is incomplete")
    for entry in storage:
        if not isinstance(entry, dict):
            raise SystemExit(f"{contract}: storage entry is malformed")
        required = {"contract", "label", "offset", "slot", "type"}
        if set(entry) != required:
            raise SystemExit(f"{contract}: storage entry fields drifted")
        type_id = entry["type"]
        if not isinstance(type_id, str) or type_id not in types:
            raise SystemExit(f"{contract}: storage entry references an unknown type ID")
    for type_id, description in types.items():
        if not isinstance(type_id, str) or not isinstance(description, dict):
            raise SystemExit(f"{contract}: storage type graph is malformed")
        for required_field in ("encoding", "label", "numberOfBytes"):
            if required_field not in description:
                raise SystemExit(f"{contract}: storage type {type_id} lacks {required_field}")
        for reference in ("base", "key", "value"):
            target = description.get(reference)
            if target is not None and target not in types:
                raise SystemExit(
                    f"{contract}: storage type {type_id} has unknown {reference} type {target}"
                )
        members = description.get("members", [])
        if not isinstance(members, list):
            raise SystemExit(f"{contract}: storage type {type_id} members are malformed")
        for member in members:
            if not isinstance(member, dict) or member.get("type") not in types:
                raise SystemExit(f"{contract}: storage type {type_id} member graph is invalid")

    freeze_surface = payload.get("freezeSurface")
    if not isinstance(freeze_surface, dict):
        raise SystemExit(f"{contract}: freeze surface evidence is missing")
    functions = freeze_surface.get("functions")
    state_variables = freeze_surface.get("stateVariables")
    if not isinstance(functions, list) or not isinstance(state_variables, list):
        raise SystemExit(f"{contract}: freeze surface evidence is malformed")
    if contract == "Phase9LocalSyntheticToken":
        return
    for variable in state_variables:
        if not isinstance(variable, dict):
            raise SystemExit(f"{contract}: state-variable evidence is malformed")
        if variable.get("visibility") == "public" and not variable.get("constant"):
            raise SystemExit(f"{contract}: non-constant public storage adds an unreviewed getter")
    for function in functions:
        if not isinstance(function, dict):
            raise SystemExit(f"{contract}: function freeze evidence is malformed")
        if function.get("kind") in {"fallback", "receive"}:
            raise SystemExit(f"{contract}: fallback or receive surface is prohibited")
        if (
            function.get("kind") == "function"
            and function.get("visibility") in {"public", "external"}
            and function.get("stateMutability") in {"nonpayable", "payable"}
            and function.get("revertError") != "Phase9ImplementationNotFrozen"
        ):
            raise SystemExit(
                f"{contract}.{function.get('name')}: mutating stub does not revert "
                "Phase9ImplementationNotFrozen"
            )


def load_actual_layouts() -> dict[str, dict[str, Any]]:
    artifact = read_json(ACTUAL_PATH)
    if artifact.get("schemaVersion") != 1 or not isinstance(artifact.get("contracts"), dict):
        raise SystemExit("compiled Phase 9 storage artifact has an unsupported schema")
    contracts = cast(dict[str, Any], artifact["contracts"])
    expected = set(PHASE9_CONTRACTS)
    actual = set(contracts)
    if actual != expected:
        raise SystemExit(
            "compiled Phase 9 storage contract set drifted; missing="
            + ",".join(sorted(expected - actual))
            + "; unexpected="
            + ",".join(sorted(actual - expected))
        )
    result: dict[str, dict[str, Any]] = {}
    for contract in PHASE9_CONTRACTS:
        payload = contracts[contract]
        if not isinstance(payload, dict):
            raise SystemExit(f"{contract}: compiled storage payload is malformed")
        typed_payload = cast(dict[str, Any], payload)
        validate_layout(contract, typed_payload)
        result[contract] = typed_payload
    return result


def first_difference(expected: object, actual: object, path: str = "$") -> str | None:
    if type(expected) is not type(actual):
        return f"{path}: type {type(expected).__name__} != {type(actual).__name__}"
    if isinstance(expected, dict) and isinstance(actual, dict):
        expected_keys = set(expected)
        actual_keys = set(actual)
        if expected_keys != actual_keys:
            return (
                f"{path}: missing={sorted(expected_keys - actual_keys)}, "
                f"unexpected={sorted(actual_keys - expected_keys)}"
            )
        for key in sorted(expected_keys):
            difference = first_difference(expected[key], actual[key], f"{path}.{key}")
            if difference is not None:
                return difference
        return None
    if isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            return f"{path}: length {len(expected)} != {len(actual)}"
        for index, (expected_item, actual_item) in enumerate(zip(expected, actual, strict=True)):
            difference = first_difference(expected_item, actual_item, f"{path}[{index}]")
            if difference is not None:
                return difference
        return None
    if expected != actual:
        return f"{path}: {expected!r} != {actual!r}"
    return None


def check_snapshots(actual_layouts: Mapping[str, Mapping[str, Any]]) -> None:
    expected_names = {f"{contract}.storage.json" for contract in PHASE9_CONTRACTS}
    actual_names = (
        {path.name for path in SNAPSHOT_ROOT.glob("*.json")} if SNAPSHOT_ROOT.is_dir() else set()
    )
    if actual_names != expected_names:
        raise SystemExit(
            "Phase 9 storage snapshot file set drifted; missing="
            + ",".join(sorted(expected_names - actual_names))
            + "; unexpected="
            + ",".join(sorted(actual_names - expected_names))
        )
    failures: list[str] = []
    for contract in PHASE9_CONTRACTS:
        snapshot = read_json(SNAPSHOT_ROOT / f"{contract}.storage.json")
        validate_layout(contract, snapshot)
        difference = first_difference(snapshot, actual_layouts[contract])
        if difference is not None:
            failures.append(f"{contract}: {difference}")
    if failures:
        raise SystemExit(
            "\n".join(failures)
            + "\nReview compatibility and update snapshots through the Phase 9 freeze review."
        )


def main() -> None:
    actual_layouts = load_actual_layouts()
    check_snapshots(actual_layouts)
    print(f"Phase 9 storage-layout compatibility passed ({len(PHASE9_CONTRACTS)} contracts).")


if __name__ == "__main__":
    main()
