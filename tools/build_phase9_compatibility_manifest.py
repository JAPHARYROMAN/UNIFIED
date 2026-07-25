"""Verify the immutable Phase 9 freeze and layered implementation checkpoints."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from check_phase9_implementation_checkpoints import (
    BASELINE_MANIFEST_PATH,
    baseline_contracts,
    baseline_sources,
    historical_manifest,
    validate_checkpoints,
)
from check_phase9_storage_layouts import PHASE9_CONTRACTS, ROOT, canonical_json

ABI_ROOT = ROOT / "protocol/abi/phase9"
STORAGE_ROOT = ROOT / "protocol/storage-layout/phase9"
MANIFEST_PATH = BASELINE_MANIFEST_PATH
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
    paths = {path.resolve() for source_root in SOURCE_ROOTS for path in source_root.rglob("*.sol")}
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
    """Return the historical manifest; implementation hashes live in checkpoints."""
    return historical_manifest()


def manifest_hash(payload: object | None = None) -> str:
    return sha256_payload(expected_manifest() if payload is None else payload)


def source_set_hash(payload: dict[str, Any] | None = None) -> str:
    manifest = expected_manifest() if payload is None else payload
    return sha256_payload(manifest.get("sources"))


def check_manifest() -> dict[str, Any]:
    manifest = historical_manifest()
    contract_order, _ = baseline_contracts(manifest)
    source_order, _ = baseline_sources(manifest)
    if contract_order != list(PHASE9_CONTRACTS):
        raise SystemExit("Phase 9 historical contract order drifted")
    validate_source_paths(set(source_order))
    validate_checkpoints(manifest=manifest)
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()

    if args.write:
        raise SystemExit(
            "The Phase 9 freeze manifest is immutable; add a reviewed implementation "
            "checkpoint instead."
        )
    manifest = check_manifest()
    print(
        "Phase 9 historical compatibility manifest and implementation checkpoints passed "
        f"({len(PHASE9_CONTRACTS)} contracts, {manifest_hash(manifest)})."
    )


if __name__ == "__main__":
    main()
