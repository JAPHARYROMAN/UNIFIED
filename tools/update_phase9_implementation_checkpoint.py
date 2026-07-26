"""Create a deterministic reviewed Phase 9 implementation checkpoint entry."""

from __future__ import annotations

import argparse
import json
from typing import Any, cast

from check_phase9_implementation_checkpoints import (
    ACTIVATED_IMPLEMENTATIONS,
    CHECKPOINT_PATH,
    ROOT,
    baseline_contracts,
    checkpoint_payload,
    current_reviewed_source_set_hash,
    historical_manifest,
    implementation_evidence_bundle_hash,
    repository_solidity_dependency_hash,
    require_unambiguous_review_pass,
    review_content,
    sha256_file,
    validate_checkpoints,
    validate_review_path,
)


def current_compatible_storage_hash(contract: str) -> str:
    """Load the storage checker lazily to avoid its checkpoint-module import cycle."""

    from check_phase9_storage_layouts import checked_implementation_storage_hash

    return checked_implementation_storage_hash(contract)


def candidate_evidence(contract: str, backlog_id: str, manifest: dict[str, Any]) -> dict[str, str]:
    """Prepare exact hashes for review without claiming that review has passed."""

    contract_order, contracts = baseline_contracts(manifest)
    if contract not in contracts or contract == "Phase9LocalSyntheticToken":
        raise SystemExit(f"{contract} is not a checkpoint-eligible Phase 9 contract")
    if ACTIVATED_IMPLEMENTATIONS.get(contract) != backlog_id:
        raise SystemExit(f"{contract}: implementation checkpoint backlog substitution")
    baseline = contracts[contract]
    storage_hash = current_compatible_storage_hash(contract)
    evidence = {
        "abiSha256": baseline["abiSha256"],
        "backlogId": backlog_id,
        "contract": contract,
        "dependencyClosureSha256": repository_solidity_dependency_hash(
            ROOT / baseline["sourcePath"]
        ),
        "implementationEvidenceBundleSha256": implementation_evidence_bundle_hash(contract),
        "sourceSha256": sha256_file(ROOT / baseline["sourcePath"]),
        "sourceSetSha256": current_reviewed_source_set_hash(manifest),
        "storageStructuralSha256": storage_hash,
    }
    if contract_order.index(contract) >= contract_order.index("Phase9LocalSyntheticToken"):
        raise SystemExit(f"{contract} is not a production implementation contract")
    return evidence


def candidate_entry(
    contract: str, backlog_id: str, review_path: str, manifest: dict[str, Any]
) -> dict[str, str]:
    evidence = candidate_evidence(contract, backlog_id, manifest)
    review = validate_review_path(review_path)
    metadata = require_unambiguous_review_pass(contract, review_content(review))
    entry = {
        **evidence,
        **metadata,
        "reviewPath": review.relative_to(ROOT).as_posix(),
        "reviewSha256": sha256_file(review),
        "status": "PASS",
    }
    return entry


def updated_registry(entry: dict[str, str], manifest: dict[str, Any]) -> dict[str, Any]:
    registry = checkpoint_payload()
    raw_entries = registry["implementations"]
    if not isinstance(raw_entries, list):
        raise SystemExit("Phase 9 implementation checkpoint list is malformed")
    entries = [
        cast(dict[str, str], existing)
        for existing in raw_entries
        if isinstance(existing, dict) and existing.get("contract") != entry["contract"]
    ]
    entries.append(entry)
    contract_order, _ = baseline_contracts(manifest)
    entries.sort(key=lambda item: contract_order.index(item["contract"]))
    registry["implementations"] = entries
    registry["currentSourceSetSha256"] = entry["sourceSetSha256"]
    return registry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--backlog-id", required=True)
    parser.add_argument("--review-path")
    parser.add_argument("--evidence-only", action="store_true")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    manifest = historical_manifest()
    if args.evidence_only:
        if args.review_path is not None or args.write:
            parser.error("--evidence-only cannot be combined with --review-path or --write")
        print(
            json.dumps(
                candidate_evidence(args.contract, args.backlog_id, manifest),
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
        return
    if args.review_path is None:
        parser.error("--review-path is required unless --evidence-only is used")
    entry = candidate_entry(args.contract, args.backlog_id, args.review_path, manifest)
    registry = updated_registry(entry, manifest)
    validate_checkpoints(manifest=manifest, registry=registry)
    rendered = json.dumps(registry, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.write:
        CHECKPOINT_PATH.write_text(rendered, encoding="utf-8")
        print(f"Phase 9 implementation checkpoint written for {args.contract}.")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
