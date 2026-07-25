"""Create a deterministic reviewed Phase 9 implementation checkpoint entry."""

from __future__ import annotations

import argparse
import json
from typing import Any, cast

from check_phase9_implementation_checkpoints import (
    CHECKPOINT_PATH,
    ROOT,
    baseline_contracts,
    checkpoint_payload,
    current_reviewed_source_set_hash,
    historical_manifest,
    read_json,
    sha256_file,
    structural_storage_hash,
    validate_checkpoints,
    validate_review_path,
)


def candidate_entry(
    contract: str, backlog_id: str, review_path: str, manifest: dict[str, Any]
) -> dict[str, str]:
    contract_order, contracts = baseline_contracts(manifest)
    if contract not in contracts or contract == "Phase9LocalSyntheticToken":
        raise SystemExit(f"{contract} is not a checkpoint-eligible Phase 9 contract")
    baseline = contracts[contract]
    storage = read_json(ROOT / baseline["storagePath"])
    if not isinstance(storage, dict):
        raise SystemExit(f"{contract}: baseline storage snapshot is malformed")
    review = validate_review_path(review_path)
    source_set_hash = current_reviewed_source_set_hash(manifest)
    entry = {
        "abiSha256": baseline["abiSha256"],
        "backlogId": backlog_id,
        "contract": contract,
        "reviewPath": review.relative_to(ROOT).as_posix(),
        "reviewSha256": sha256_file(review),
        "sourceSha256": sha256_file(ROOT / baseline["sourcePath"]),
        "sourceSetSha256": source_set_hash,
        "status": "PASS",
        "storageStructuralSha256": structural_storage_hash(cast(dict[str, Any], storage)),
    }
    if contract_order.index(contract) >= contract_order.index("Phase9LocalSyntheticToken"):
        raise SystemExit(f"{contract} is not a production implementation contract")
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
    parser.add_argument("--review-path", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    manifest = historical_manifest()
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
