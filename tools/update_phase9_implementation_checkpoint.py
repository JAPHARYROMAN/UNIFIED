"""Create a deterministic reviewed Phase 9 package checkpoint."""

from __future__ import annotations

import argparse
import json
from typing import Any, cast

from check_phase9_implementation_checkpoints import (
    ACTIVATION_PACKAGES,
    CHECKPOINT_PATH,
    IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS,
    IMPLEMENTATION_EVIDENCE_PATHS,
    ROOT,
    additive_abi_payload,
    baseline_contracts,
    checkpoint_payload,
    current_control_bundle_hash,
    current_reviewed_source_set_hash,
    historical_manifest,
    implementation_evidence_bundle_hash,
    read_json,
    repository_solidity_dependency_hash,
    require_unambiguous_review_pass,
    review_content,
    sha256_file,
    validate_checkpoints,
    validate_review_path,
)
from check_phase9_implementation_checkpoints import sha256_payload as sha256_payload


def current_compatible_storage_hash(contract: str) -> str:
    """Load the storage checker lazily to avoid its checkpoint-module import cycle."""

    from check_phase9_storage_layouts import checked_implementation_storage_hash

    return checked_implementation_storage_hash(contract)


def require_frozen_implementation_evidence_paths(checkpoint_id: str) -> None:
    """Reject candidates until every activated contract has an explicit evidence closure."""

    definition = ACTIVATION_PACKAGES.get(checkpoint_id)
    if definition is None:
        raise SystemExit(f"{checkpoint_id}: Phase 9 package is not activated")
    contracts = cast(dict[str, tuple[str, ...]], definition["contracts"])
    unfrozen = [
        contract for contract in contracts if not IMPLEMENTATION_EVIDENCE_PATHS.get(contract)
    ]
    if unfrozen:
        raise SystemExit(
            f"{checkpoint_id}: implementation evidence paths are not frozen for: "
            + ", ".join(unfrozen)
        )
    closure_limitation = IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS.get(checkpoint_id)
    if closure_limitation is not None:
        raise SystemExit(
            f"{checkpoint_id}: implementation evidence closure is incomplete: "
            f"{closure_limitation}"
        )


def candidate_revisions(
    checkpoint_id: str,
    manifest: dict[str, Any],
    *,
    registry: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Prepare exact contract-revision evidence without claiming review approval."""

    definition = ACTIVATION_PACKAGES.get(checkpoint_id)
    if definition is None:
        raise SystemExit(f"{checkpoint_id}: Phase 9 package is not activated")
    require_frozen_implementation_evidence_paths(checkpoint_id)
    checkpoint_registry = checkpoint_payload() if registry is None else registry
    latest = validate_checkpoints(
        manifest=manifest,
        registry=checkpoint_registry,
        # Candidate generation must work before the implementation commit exists.
        # Final registry validation below still requires current byte-for-byte integrity.
        verify_current=False,
        verify_reviews=True,
        verify_backlog=True,
    )
    _, contracts = baseline_contracts(manifest)
    current_source_set = current_reviewed_source_set_hash(manifest)
    revisions: list[dict[str, Any]] = []
    for contract, signatures in cast(dict[str, tuple[str, ...]], definition["contracts"]).items():
        if contract not in contracts or contract == "Phase9LocalSyntheticToken":
            raise SystemExit(f"{contract} is not a checkpoint-eligible Phase 9 contract")
        baseline = contracts[contract]
        current_abi = read_json(ROOT / baseline["abiPath"])
        for existing_package in cast(list[dict[str, Any]], checkpoint_registry["packages"]):
            existing_definition = ACTIVATION_PACKAGES[cast(str, existing_package["checkpointId"])]
            existing_additions = cast(
                dict[str, tuple[dict[str, Any], ...]], existing_definition["abiAdditions"]
            )
            current_abi = additive_abi_payload(current_abi, existing_additions.get(contract, ()))
        candidate_additions = cast(
            dict[str, tuple[dict[str, Any], ...]], definition["abiAdditions"]
        )
        current_abi = additive_abi_payload(current_abi, candidate_additions.get(contract, ()))
        prior = latest.get(contract)
        prior_revision = 0 if prior is None else cast(int, prior["revision"])
        prior_origin: dict[str, Any] | None = None
        if prior is not None:
            for package in cast(list[dict[str, Any]], checkpoint_registry["packages"]):
                for candidate in cast(list[dict[str, Any]], package["revisions"]):
                    if candidate is prior:
                        prior_origin = {
                            "checkpointId": package["checkpointId"],
                            "revision": prior_revision,
                        }
                        break
        revisions.append(
            {
                "abiSha256": sha256_payload(current_abi),
                "activatedSignatures": list(signatures),
                "contract": contract,
                "dependencyClosureSha256": repository_solidity_dependency_hash(
                    ROOT / baseline["sourcePath"]
                ),
                "implementationEvidenceBundleSha256": implementation_evidence_bundle_hash(contract),
                "revision": prior_revision + 1,
                "sourceSha256": sha256_file(ROOT / baseline["sourcePath"]),
                "sourceSetSha256": current_source_set,
                "storageStructuralSha256": current_compatible_storage_hash(contract),
                "supersedes": prior_origin,
            }
        )
    return revisions


def candidate_evidence(
    checkpoint_id: str,
    manifest: dict[str, Any],
    *,
    registry: dict[str, Any] | None = None,
) -> dict[str, Any]:
    definition = ACTIVATION_PACKAGES.get(checkpoint_id)
    if definition is None:
        raise SystemExit(f"{checkpoint_id}: Phase 9 package is not activated")
    return {
        "checkpointId": checkpoint_id,
        "requiredBacklogIds": list(cast(tuple[str, ...], definition["requiredBacklogIds"])),
        "revisions": candidate_revisions(
            checkpoint_id,
            manifest,
            registry=registry,
        ),
    }


def candidate_package(
    checkpoint_id: str,
    review_path: str,
    manifest: dict[str, Any],
    *,
    registry: dict[str, Any] | None = None,
) -> dict[str, Any]:
    evidence = candidate_evidence(checkpoint_id, manifest, registry=registry)
    review = validate_review_path(review_path)
    metadata = require_unambiguous_review_pass(checkpoint_id, review_content(review))
    return {
        **evidence,
        "review": {
            **metadata,
            "reviewPath": review.relative_to(ROOT).as_posix(),
            "reviewSha256": sha256_file(review),
            "status": "PASS",
        },
    }


def updated_registry(checkpoint_package: dict[str, Any]) -> dict[str, Any]:
    registry = checkpoint_payload()
    raw_packages = registry["packages"]
    if not isinstance(raw_packages, list):
        raise SystemExit("Phase 9 checkpoint package list is malformed")
    if any(
        isinstance(existing, dict)
        and existing.get("checkpointId") == checkpoint_package["checkpointId"]
        for existing in raw_packages
    ):
        raise SystemExit(f"{checkpoint_package['checkpointId']}: checkpoint package already exists")
    raw_packages.append(checkpoint_package)
    revisions = cast(list[dict[str, Any]], checkpoint_package["revisions"])
    registry["currentSourceSetSha256"] = revisions[0]["sourceSetSha256"]
    registry["currentControlBundleSha256"] = current_control_bundle_hash()
    return registry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint-id", required=True)
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
                candidate_evidence(args.checkpoint_id, manifest),
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
        return
    if args.review_path is None:
        parser.error("--review-path is required unless --evidence-only is used")
    checkpoint_package = candidate_package(args.checkpoint_id, args.review_path, manifest)
    registry = updated_registry(checkpoint_package)
    validate_checkpoints(manifest=manifest, registry=registry)
    rendered = json.dumps(registry, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.write:
        CHECKPOINT_PATH.write_text(rendered, encoding="utf-8")
        print(f"Phase 9 checkpoint package written: {args.checkpoint_id}.")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
