"""Build or verify the reviewed Phase 9 ABI/storage compatibility hash manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, cast

from check_phase9_storage_layouts import PHASE9_CONTRACTS, ROOT, canonical_json

ABI_ROOT = ROOT / "protocol/abi/phase9"
STORAGE_ROOT = ROOT / "protocol/storage-layout/phase9"
MANIFEST_PATH = ROOT / "protocol/compatibility/phase9-manifest.json"
SOURCE_ROOTS = (
    ROOT / "protocol/src/interfaces/phase9",
    ROOT / "protocol/src/resolution",
    ROOT / "protocol/src/protection",
    ROOT / "protocol/src/recovery",
)
TOKEN_SOURCE = ROOT / "protocol/src/token/Phase9LocalSyntheticToken.sol"
EXPECTED_SOURCE_PATHS = (
    "protocol/src/interfaces/phase9/ICollateralCustodyV2.sol",
    "protocol/src/interfaces/phase9/IGuaranteeVault.sol",
    "protocol/src/interfaces/phase9/IInsuranceManager.sol",
    "protocol/src/interfaces/phase9/IInsuranceReserveVault.sol",
    "protocol/src/interfaces/phase9/ILienRegistry.sol",
    "protocol/src/interfaces/phase9/IPayoffQuoteEngineV2.sol",
    "protocol/src/interfaces/phase9/IPhase9LoanAccount.sol",
    "protocol/src/interfaces/phase9/IPhase9LoanFactory.sol",
    "protocol/src/interfaces/phase9/IPhase9LocalSyntheticToken.sol",
    "protocol/src/interfaces/phase9/IPositionManagerV2.sol",
    "protocol/src/interfaces/phase9/IRecoveryManager.sol",
    "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
    "protocol/src/interfaces/phase9/IReservePolicy.sol",
    "protocol/src/interfaces/phase9/IRestructuringController.sol",
    "protocol/src/interfaces/phase9/Phase9Errors.sol",
    "protocol/src/protection/InsuranceManager.sol",
    "protocol/src/protection/InsuranceReserveVault.sol",
    "protocol/src/protection/Phase9ProtectionTypes.sol",
    "protocol/src/protection/ReservePolicy.sol",
    "protocol/src/recovery/GuaranteeVault.sol",
    "protocol/src/recovery/Phase9RecoveryTypes.sol",
    "protocol/src/recovery/RecoveryManager.sol",
    "protocol/src/resolution/CollateralCustodyV2.sol",
    "protocol/src/resolution/LienRegistry.sol",
    "protocol/src/resolution/PayoffQuoteEngine.sol",
    "protocol/src/resolution/Phase9LoanAccount.sol",
    "protocol/src/resolution/Phase9LoanFactory.sol",
    "protocol/src/resolution/Phase9Types.sol",
    "protocol/src/resolution/PositionManagerV2.sol",
    "protocol/src/resolution/RefinanceCoordinator.sol",
    "protocol/src/resolution/RestructuringController.sol",
    "protocol/src/token/Phase9LocalSyntheticToken.sol",
)


def read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is not valid JSON: {exc}") from exc


def sha256_payload(payload: object) -> str:
    return "sha256:" + hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    try:
        content = path.read_bytes()
    except FileNotFoundError as exc:
        raise SystemExit(f"{path.relative_to(ROOT)} is missing") from exc
    return "sha256:" + hashlib.sha256(content).hexdigest()


def validate_source_paths(paths: set[str]) -> None:
    expected = set(EXPECTED_SOURCE_PATHS)
    if paths != expected:
        raise SystemExit(
            "Phase 9 reviewed Solidity source set drifted; missing="
            + ",".join(sorted(expected - paths))
            + "; unexpected="
            + ",".join(sorted(paths - expected))
        )


def expected_sources() -> list[dict[str, str]]:
    paths = {
        path.resolve()
        for source_root in SOURCE_ROOTS
        for path in source_root.glob("*.sol")
    }
    paths.add(TOKEN_SOURCE.resolve())
    relative_paths = {path.relative_to(ROOT).as_posix() for path in paths}
    validate_source_paths(relative_paths)
    return [
        {
            "path": relative_path,
            "sha256": sha256_file(ROOT / relative_path),
        }
        for relative_path in EXPECTED_SOURCE_PATHS
    ]


def expected_manifest() -> dict[str, Any]:
    contracts: list[dict[str, str]] = []
    for contract in PHASE9_CONTRACTS:
        abi_path = ABI_ROOT / f"{contract}.abi.json"
        storage_path = STORAGE_ROOT / f"{contract}.storage.json"
        abi = read_json(abi_path)
        storage = read_json(storage_path)
        if not isinstance(abi, list):
            raise SystemExit(f"{abi_path.relative_to(ROOT)} must contain a JSON ABI array")
        if not isinstance(storage, dict):
            raise SystemExit(f"{storage_path.relative_to(ROOT)} must contain a JSON object")
        source = storage.get("source")
        if not isinstance(source, str):
            raise SystemExit(f"{storage_path.relative_to(ROOT)} lacks its Solidity source")
        source_path = ROOT / source
        if not source_path.is_file():
            raise SystemExit(f"{source} is missing")
        contracts.append(
            {
                "abiPath": abi_path.relative_to(ROOT).as_posix(),
                "abiSha256": sha256_payload(abi),
                "contract": contract,
                "sourcePath": source,
                "sourceSha256": sha256_file(source_path),
                "storagePath": storage_path.relative_to(ROOT).as_posix(),
                "storageSha256": sha256_payload(storage),
            }
        )
    return {
        "contracts": contracts,
        "schemaVersion": 2,
        "sources": expected_sources(),
    }


def manifest_hash(payload: object | None = None) -> str:
    return sha256_payload(expected_manifest() if payload is None else payload)


def source_set_hash(payload: dict[str, Any] | None = None) -> str:
    manifest = expected_manifest() if payload is None else payload
    return sha256_payload(manifest.get("sources"))


def check_manifest() -> dict[str, Any]:
    expected = expected_manifest()
    actual = read_json(MANIFEST_PATH)
    if not isinstance(actual, dict):
        raise SystemExit("Phase 9 compatibility manifest must contain a JSON object")
    typed_actual = cast(dict[str, Any], actual)
    if typed_actual != expected:
        raise SystemExit(
            "Phase 9 compatibility manifest is stale; regenerate only after compatibility review."
        )
    return typed_actual


def main() -> None:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()

    expected = expected_manifest()
    if args.write:
        MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST_PATH.write_text(
            json.dumps(expected, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"Phase 9 compatibility manifest written ({len(PHASE9_CONTRACTS)} contracts).")
        return
    check_manifest()
    print(
        "Phase 9 compatibility manifest passed "
        f"({len(PHASE9_CONTRACTS)} contracts, {manifest_hash(expected)})."
    )


if __name__ == "__main__":
    main()
