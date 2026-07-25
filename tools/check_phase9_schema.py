#!/usr/bin/env python3
"""Enforce the exact Phase 9 descriptor and generated-artifact boundary."""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from google.protobuf import descriptor_pb2  # type: ignore[import-untyped]

PROJECT_ROOT = Path(__file__).resolve().parents[1]
PROTO_ROOT = PROJECT_ROOT / "schemas" / "proto"
BASELINE_ROOT = PROJECT_ROOT / "schemas" / "baseline" / "v0.1"
GO_PACKAGE = "github.com/unified-finance/unified/packages/generated/go/unified/v1;unifiedv1"
DEPENDENCIES = ("google/protobuf/timestamp.proto", "unified/v1/types.proto")


class SchemaError(RuntimeError):
    """The Phase 9 schema boundary does not match the frozen specification."""


@dataclass(frozen=True)
class ExpectedFile:
    descriptor_sha256: str
    enums: tuple[str, ...]
    messages: tuple[str, ...]
    field_count: int


EXPECTED_FILES: dict[str, ExpectedFile] = {
    "unified/v1/refinance.proto": ExpectedFile(
        "968bf59cba37cfdcd0cbd3443a6f355e914fba92db90c5f333b64ce64248ee0c",
        (
            "PayoffComponentKind",
            "PayoffQuoteState",
            "RefinanceState",
            "FundingCommitmentState",
            "LienHandoffState",
        ),
        (
            "CanonicalDebtSnapshot",
            "PayoffComponent",
            "PayoffQuote",
            "RefinanceRequest",
            "RefinanceFundingCommitment",
            "CollateralLienHandoff",
            "RefinanceExecutionEvidence",
            "RefinanceRefundEvidence",
        ),
        96,
    ),
    "unified/v1/restructuring.proto": ExpectedFile(
        "1ead9a5a075a4c7f5b24db77cc4f54ba61cd37450677ceca7711a8e8b8d23594",
        ("RestructuringState", "RestructuringVoteChoice"),
        (
            "PositionRightSnapshot",
            "PositionRight",
            "RestructuringProposal",
            "RestructuringVote",
            "BorrowerRestructuringConsent",
            "LoanAmendment",
            "RestructuringExecutionEvidence",
        ),
        81,
    ),
    "unified/v1/protection.proto": ExpectedFile(
        "0f9baf3a70da92abb9a1defe55186596be1fe6db7e2be52394a0900483fff510",
        ("ReservePolicyState", "CoverageState", "PremiumState", "InsuranceClaimState"),
        (
            "ReservePolicyVersion",
            "ReserveBalanceSnapshot",
            "ReserveSolvencySnapshot",
            "LoanCoverage",
            "PremiumEvidence",
            "InsuranceClaim",
            "ClaimDecision",
            "ClaimPayment",
        ),
        113,
    ),
    "unified/v1/recovery.proto": ExpectedFile(
        "f46447cc43ae1b00eb208458c41e7ecd078049953ad1685b9e79f72c971f9191",
        (
            "GuaranteeState",
            "RecoveryCaseState",
            "RecoverySourceType",
            "RecoverySourceState",
            "RecoveryEntitlementKind",
        ),
        (
            "Guarantee",
            "RecoveryCase",
            "RecoverySourceEvidence",
            "RecoveryEntitlement",
            "RecoveryAllocation",
            "WriteOffEvidence",
            "RecoveryReconciliationEvidence",
        ),
        90,
    ),
}

EXPECTED_GENERATED = tuple(
    path
    for stem in ("refinance", "restructuring", "protection", "recovery")
    for path in (
        f"packages/generated/go/unified/v1/{stem}.pb.go",
        f"packages/generated/typescript/unified/v1/{stem}_pb.ts",
        f"packages/generated/python/unified/v1/{stem}_pb2.py",
    )
)


def descriptor_set_from_buf() -> descriptor_pb2.FileDescriptorSet:
    buf = shutil.which("buf")
    if buf is None:
        raise SchemaError("buf is required for the Phase 9 descriptor check")
    completed = subprocess.run(  # noqa: S603
        [buf, "build", "--as-file-descriptor-set", "-o", "-"],
        cwd=PROJECT_ROOT,
        check=True,
        capture_output=True,
    )
    descriptor_set = descriptor_pb2.FileDescriptorSet()
    descriptor_set.ParseFromString(completed.stdout)
    return descriptor_set


def _descriptor_hash(file_descriptor: descriptor_pb2.FileDescriptorProto) -> str:
    normalized = descriptor_pb2.FileDescriptorProto()
    normalized.CopyFrom(file_descriptor)
    normalized.ClearField("source_code_info")
    return hashlib.sha256(normalized.SerializeToString(deterministic=True)).hexdigest()


def validate_descriptor_set(descriptor_set: descriptor_pb2.FileDescriptorSet) -> None:
    phase9 = {item.name: item for item in descriptor_set.file if item.name in EXPECTED_FILES}
    if set(phase9) != set(EXPECTED_FILES):
        raise SchemaError(
            f"Phase 9 descriptors differ: expected {sorted(EXPECTED_FILES)}, got {sorted(phase9)}"
        )

    for name, expected in EXPECTED_FILES.items():
        descriptor = phase9[name]
        if descriptor.package != "unified.v1" or descriptor.syntax != "proto3":
            raise SchemaError(f"{name}: package or syntax differs from the frozen descriptor")
        if tuple(descriptor.dependency) != DEPENDENCIES:
            raise SchemaError(f"{name}: imports differ from the frozen descriptor")
        if descriptor.options.go_package != GO_PACKAGE:
            raise SchemaError(f"{name}: go_package differs from the frozen descriptor")
        enum_names = tuple(item.name for item in descriptor.enum_type)
        message_names = tuple(item.name for item in descriptor.message_type)
        field_count = sum(len(item.field) for item in descriptor.message_type)
        if enum_names != expected.enums:
            raise SchemaError(f"{name}: enum declaration names/order differ")
        if message_names != expected.messages or field_count != expected.field_count:
            raise SchemaError(f"{name}: message declarations or field count differ")
        actual_hash = _descriptor_hash(descriptor)
        if actual_hash != expected.descriptor_sha256:
            raise SchemaError(
                f"{name}: exact descriptor differs ({actual_hash} != "
                f"{expected.descriptor_sha256})"
            )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_sources_and_generated_outputs() -> None:
    for descriptor_name in EXPECTED_FILES:
        source = PROTO_ROOT / descriptor_name
        if not source.is_file():
            raise SchemaError(f"missing Phase 9 source: {source.relative_to(PROJECT_ROOT)}")
        baseline = BASELINE_ROOT / descriptor_name
        if baseline.exists():
            raise SchemaError(
                f"Phase 9 source leaked into immutable v0.1 baseline: {descriptor_name}"
            )

    for generated in EXPECTED_GENERATED:
        if not (PROJECT_ROOT / generated).is_file():
            raise SchemaError(f"missing generated Phase 9 binding: {generated}")

    foundation_types = PROJECT_ROOT / "protocol" / "src" / "generated" / "FoundationTypes.sol"
    if not foundation_types.is_file():
        raise SchemaError("missing generated Solidity FoundationTypes.sol")
    solidity = foundation_types.read_text(encoding="utf-8")
    for expected in EXPECTED_FILES.values():
        for enum_name in expected.enums:
            if f"enum {enum_name} {{" not in solidity:
                raise SchemaError(f"FoundationTypes.sol lacks enum {enum_name}")
        for message_name in expected.messages:
            if f"struct {message_name} {{" not in solidity:
                raise SchemaError(f"FoundationTypes.sol lacks struct {message_name}")

    manifest_path = PROJECT_ROOT / "packages" / "generated" / "manifest.json"
    raw_manifest: Any = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(raw_manifest, dict) or raw_manifest.get("version") != 1:
        raise SchemaError("generated manifest version is invalid")
    raw_files = raw_manifest.get("files")
    if not isinstance(raw_files, list):
        raise SchemaError("generated manifest files must be a list")
    manifest: dict[str, str] = {}
    for raw_entry in raw_files:
        if not isinstance(raw_entry, dict):
            raise SchemaError("generated manifest entry must be an object")
        path = raw_entry.get("path")
        digest = raw_entry.get("sha256")
        if not isinstance(path, str) or not isinstance(digest, str):
            raise SchemaError("generated manifest path/hash must be strings")
        if path in manifest:
            raise SchemaError(f"generated manifest has duplicate path: {path}")
        manifest[path] = digest
    required = (*EXPECTED_GENERATED, "protocol/src/generated/FoundationTypes.sol")
    for generated in required:
        if generated not in manifest:
            raise SchemaError(f"generated manifest lacks {generated}")
    for generated, recorded_hash in manifest.items():
        artifact = PROJECT_ROOT / generated
        if not artifact.is_file():
            raise SchemaError(f"generated manifest points to missing file: {generated}")
        if _sha256(artifact) != recorded_hash:
            raise SchemaError(f"generated manifest hash is stale: {generated}")


def run_checks() -> None:
    validate_descriptor_set(descriptor_set_from_buf())
    validate_sources_and_generated_outputs()


def main() -> int:
    try:
        run_checks()
    except (SchemaError, subprocess.CalledProcessError) as error:
        print(f"Phase 9 schema check failed: {error}", file=sys.stderr)
        return 1
    print("Phase 9 exact descriptor and generated-artifact checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
