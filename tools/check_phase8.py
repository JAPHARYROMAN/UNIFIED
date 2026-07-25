"""Phase 8 cross-chain architecture and local-safety conformance checks."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

from Crypto.Hash import keccak
from sign_phase8_observer import key_for

ROOT = Path(__file__).resolve().parents[1]
PHASE8_RELEASE_MANIFEST = "protocol/deployments/local/phase8-release-evidence.json"

REQUIRED_RISKS = {f"RISK-PHASE8-{index:03d}" for index in range(1, 11)}
REQUIRED_ASSUMPTIONS = {f"ASM-{index:03d}" for index in range(26, 34)}
REQUIRED_BACKLOG = {
    "UNI-ADR-013",
    "UNI-LOCAL-002",
    "UNI-POLICY-007",
    "UNI-BRIDGE-001",
    "UNI-BRIDGE-002",
    "UNI-INDEX-006",
    "UNI-SCHEMA-012",
    "UNI-RISK-002",
    "UNI-UFT-005",
    "UNI-BRIDGE-003",
    "UNI-DATA-002",
    "UNI-ACCOUNTING-011",
    "UNI-RECON-003",
    "UNI-LOAN-003",
    "UNI-COLLATERAL-009",
    "UNI-SATELLITE-001",
    "UNI-SIM-007",
    "UNI-SEC-013",
    "UNI-REVIEW-011",
}
REQUIRED_PATHS = (
    "schemas/proto/unified/v1/crosschain.proto",
    "protocol/src/crosschain/CrossChainTypes.sol",
    "protocol/src/crosschain/ChainRegistry.sol",
    "protocol/src/crosschain/RouteRegistry.sol",
    "protocol/src/crosschain/SyntheticFinalityVerifier.sol",
    "protocol/src/crosschain/CrossChainCoordinator.sol",
    "protocol/src/crosschain/CrossChainRecoveryController.sol",
    "protocol/src/crosschain/BridgeExposurePolicy.sol",
    "protocol/src/crosschain/UFTBridgeHub.sol",
    "protocol/src/crosschain/WrappedUFT.sol",
    "protocol/src/crosschain/CrossChainLoanFactory.sol",
    "protocol/src/crosschain/CrossChainLoanAccount.sol",
    "protocol/src/crosschain/CrossChainLoanAccountDeployer.sol",
    "protocol/src/crosschain/Phase8LocalSyntheticToken.sol",
    "protocol/src/crosschain/SatelliteLoanComponent.sol",
    "protocol/src/crosschain/SatelliteCollateralVault.sol",
    "protocol/src/crosschain/SatelliteSettlementVault.sol",
    "protocol/script/DeployPhase8Local.s.sol",
    "protocol/test/Phase8CrossChainCore.t.sol",
    "protocol/test/Phase8CrossChainFlow.t.sol",
    "protocol/test/Phase8CrossChainFuzz.t.sol",
    "protocol/test/Phase8CrossChainInvariants.t.sol",
    "protocol/test/Phase8CrossChainRecoveryOrdering.t.sol",
    "services/cross-chain-coordinator/message/digest.go",
    "services/cross-chain-coordinator/message/registry.go",
    "services/cross-chain-coordinator/provider/provider.go",
    "services/cross-chain-coordinator/recovery/recovery.go",
    "services/cross-chain-coordinator/store/store.go",
    "services/cross-chain-coordinator/store/sql.go",
    "services/cross-chain-coordinator/store/sql_integration_test.go",
    "services/cross-chain-coordinator/reconciliation/reconciliation.go",
    "services/cross-chain-coordinator/cmd/local-worker/main.go",
    "services/cross-chain-coordinator/cmd/local-worker/worker.go",
    "services/cross-chain-coordinator/cmd/local-worker/manifest.go",
    "services/cross-chain-coordinator/cmd/local-worker/manifest_import.go",
    "services/cross-chain-coordinator/cmd/local-worker/manifest_durable.go",
    "services/cross-chain-coordinator/cmd/local-worker/worker_integration_test.go",
    "services/cross-chain-coordinator/cmd/server/main.go",
    "services/chain-indexer/crosschain/projector.go",
    "services/chain-indexer/crosschain/projector_test.go",
    "services/chain-indexer/cmd/verify-phase8-inclusion/main.go",
    "services/chain-indexer/projection/evmproof_evidence_test.go",
    "services/foundation-ledger/migrations/000010_crosschain_messages.sql",
    "services/foundation-ledger/migrations/000011_satellite_loan_accounting.sql",
    "services/foundation-ledger/migrations/000012_wrapped_uft.sql",
    "services/foundation-ledger/migrations/tests/000010_000012_crosschain_foundation_test.sql",
    "models/foundation_model/src/unified_foundation/cross_chain.py",
    "models/foundation_model/src/unified_foundation/cross_chain_codec.py",
    "models/foundation_model/tests/test_cross_chain.py",
    "models/foundation_model/tests/test_cross_chain_codec.py",
    "packages/crosschain/typescript/codec.ts",
    "packages/generated/go/unified/v1/crosschain.pb.go",
    "packages/generated/python/unified/v1/crosschain_pb2.py",
    "packages/generated/typescript/unified/v1/crosschain_pb.ts",
    "infrastructure/local/cross-chain/domains.json",
    "infrastructure/local/cross-chain/circulating-supply-reference.json",
    "infrastructure/local/cross-chain/phase8-release-evidence.schema.json",
    "docs/architecture/phase-8-local-release-evidence.md",
    "tools/assemble_phase8_release_evidence.py",
    "tools/build_phase8_anvil_inclusion.py",
    "tools/check_phase8_evm_evidence.py",
    "tools/check_phase8_release_evidence.py",
    "tools/run_phase8_authenticated_flow.py",
    "tools/sign_phase8_observer.py",
    "tests/test_phase8_anvil_inclusion.py",
    "scripts/check-phase8-release-evidence.ps1",
    "scripts/local-reset.ps1",
    "scripts/test-local-reset.ps1",
    "scripts/smoke-phase8-anvil.ps1",
    "scripts/smoke-phase8-anvil.sh",
)
IMPLEMENTATION_COMPLETE_REQUIRED_PATHS = (
    "docs/reviews/phase-8-exit-review.md",
)
REQUIRED_PHASE8_ABIS = {
    "BridgeExposurePolicy.abi.json",
    "ChainRegistry.abi.json",
    "CrossChainCoordinator.abi.json",
    "CrossChainLoanAccount.abi.json",
    "CrossChainLoanAccountDeployer.abi.json",
    "CrossChainLoanFactory.abi.json",
    "CrossChainLoanPolicy.abi.json",
    "CrossChainRecoveryController.abi.json",
    "RouteRegistry.abi.json",
    "SatelliteCollateralVault.abi.json",
    "SatelliteLoanComponent.abi.json",
    "SatelliteSettlementVault.abi.json",
    "SyntheticFinalityVerifier.abi.json",
    "Phase8LocalSyntheticToken.abi.json",
    "UFTBridgeHub.abi.json",
    "WrappedUFT.abi.json",
}
EXPECTED_LOCAL_SIGNERS = [
    "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf",
    "0x6813eb9362372eef6200f3b1dbc3f819671cba69",
    "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
]
EXPECTED_ROUTE_PURPOSES = [
    "mint",
    "report",
    "repayment",
    "alternate_repayment",
    "bridge_exit",
    "disbursement",
    "collateral_release",
]
DYNAMIC_AUTHORITY_FIELDS = {
    "adapter_set_policy_hash",
    "authorizer_set_hash",
    "configuration_hash",
    "coordinator_address",
    "cross_chain_policy_hash",
    "finality_policy_hash",
    "finality_verifier_address",
    "observer_authority_hash",
    "observer_public_key_ed25519",
    "route_id",
    "route_policy_hash",
    "signer_set_hash",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"ERROR: {message}")


def check_paths() -> None:
    missing = [relative for relative in REQUIRED_PATHS if not (ROOT / relative).is_file()]
    require(not missing, f"missing Phase 8 implementation paths: {', '.join(missing)}")
    abi_root = ROOT / "protocol/abi/phase8"
    actual_abis = {path.name for path in abi_root.glob("*.abi.json")}
    require(
        actual_abis == REQUIRED_PHASE8_ABIS,
        "Phase 8 reviewed ABI snapshots are incomplete or unexpected",
    )


def check_registers() -> None:
    risk_text = (ROOT / "security/risk-register.yaml").read_text(encoding="utf-8")
    assumption_text = (ROOT / "security/assumption-register.yaml").read_text(encoding="utf-8")
    risks = set(re.findall(r"^\s+- id:\s+(RISK-PHASE8-\d{3})$", risk_text, re.MULTILINE))
    assumptions = set(re.findall(r"^\s+- id:\s+(ASM-\d{3})$", assumption_text, re.MULTILINE))
    require(risks == REQUIRED_RISKS, "Phase 8 risk register IDs are incomplete or unexpected")
    require(
        REQUIRED_ASSUMPTIONS <= assumptions,
        "Phase 8 assumption register IDs are incomplete",
    )


def check_backlog(require_complete: bool) -> None:
    with (ROOT / "docs/backlog/phase-8.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    identifiers = [row["id"] for row in rows]
    require(len(identifiers) == len(set(identifiers)), "Phase 8 backlog IDs are duplicated")
    require(set(identifiers) == REQUIRED_BACKLOG, "Phase 8 backlog IDs drifted")
    if require_complete:
        incomplete = [
            row["id"] for row in rows if row["status"] != "DONE"
        ]
        require(not incomplete, f"Phase 8 implementation backlog remains open: {incomplete}")
        missing_reviews = [
            relative
            for relative in IMPLEMENTATION_COMPLETE_REQUIRED_PATHS
            if not (ROOT / relative).is_file()
        ]
        require(
            not missing_reviews,
            f"Phase 8 implementation-complete review paths are missing: {missing_reviews}",
        )


def derived_observer_identity(domain: str) -> tuple[str, str]:
    public_key = key_for(domain).public_key().export_key(format="raw")
    digest = keccak.new(digest_bits=256, data=public_key).hexdigest()
    return "0x" + public_key.hex(), "0x" + digest


def collect_object_keys(value: object) -> set[str]:
    if isinstance(value, dict):
        keys = set(value)
        for nested in value.values():
            keys.update(collect_object_keys(nested))
        return keys
    if isinstance(value, list):
        nested_keys: set[str] = set()
        for nested in value:
            nested_keys.update(collect_object_keys(nested))
        return nested_keys
    return set()


def check_local_config() -> None:
    config_path = ROOT / "infrastructure/local/cross-chain/domains.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    require(
        config.get("schema_version") == 1
        and config.get("artifact_role") == "NON_AUTHORITATIVE_LOCAL_FIXTURE_INPUTS"
        and config.get("runtime_authority") == PHASE8_RELEASE_MANIFEST
        and config.get("environment") == "local"
        and config.get("contains_real_value") is False,
        "Phase 8 domain configuration is not explicitly local and synthetic",
    )
    shadow_authority = collect_object_keys(config) & DYNAMIC_AUTHORITY_FIELDS
    require(
        not shadow_authority,
        "Phase 8 fixture config must not contain deployment-derived authority: "
        + ", ".join(sorted(shadow_authority)),
    )
    require(
        config["home"]["chain_id"] == 31337 and config["satellite"]["chain_id"] == 31338,
        "Phase 8 local chain IDs drifted",
    )
    require(
        config["home"]["observer_fixture"] != config["satellite"]["observer_fixture"],
        "Phase 8 local domains must use distinct observer fixtures",
    )
    observer_identities: dict[str, tuple[str, str]] = {}
    for domain in ("home", "satellite"):
        require(
            config[domain].get("observer_domain") == domain
            and config[domain].get("confirmation_depth") == 12,
            f"Phase 8 {domain} observer fixture inputs drifted",
        )
        observer_identities[domain] = derived_observer_identity(domain)
    require(
        observer_identities["home"] != observer_identities["satellite"],
        "Phase 8 observer helper derived duplicate domain identities",
    )
    require(
        observer_identities["home"][1] != observer_identities["satellite"][1],
        "Phase 8 observer helper derived duplicate authority hashes",
    )
    require(
        config["finality"]["threshold"] == 2 and config["finality"]["signer_count"] == 3,
        "Phase 8 local threshold must remain two of three",
    )
    require(
        config["finality"].get("sorted_signer_addresses") == EXPECTED_LOCAL_SIGNERS,
        "Phase 8 finality signer order or addresses drifted",
    )
    require(
        config["recovery"].get("action") == "TOMBSTONE_THEN_COMPENSATE"
        and config["recovery"].get("threshold") == 2
        and config["recovery"].get("authorizer_set_version") == 1
        and config["recovery"].get("sorted_authorizer_addresses")
        == EXPECTED_LOCAL_SIGNERS,
        "Phase 8 recovery fixture inputs drifted",
    )
    require(
        config["route_inputs"].get("required_purposes") == EXPECTED_ROUTE_PURPOSES,
        "Phase 8 local route fixture purposes drifted",
    )
    providers = config["providers"]
    require(
        [
            (provider.get("id"), provider.get("authority"))
            for provider in providers
        ]
        == [
            ("mock-bridge-provider-a", "TRANSPORT_ONLY"),
            ("mock-bridge-provider-b", "TRANSPORT_ONLY"),
        ],
        "Phase 8 requires two distinct transport-only providers",
    )
    exposure = config["exposure"]
    require(
        exposure["route_cap_bps"] == 500
        and exposure["aggregate_cap_bps"] == 1500
        and exposure["conversion_numerator"] == exposure["conversion_denominator"] == 1,
        "Phase 8 local cap or one-to-one conversion fixture drifted",
    )
    evidence_path = ROOT / exposure["evidence_path"]
    require(evidence_path.is_file(), "frozen circulating-supply evidence is missing")
    digest = hashlib.sha256(evidence_path.read_bytes()).hexdigest()
    require(digest == exposure["evidence_sha256"], "frozen supply evidence hash mismatch")
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    require(
        evidence["contains_real_value"] is False
        and evidence["authority"] == "SYNTHETIC_FIXTURE_ONLY"
        and evidence["circulating_supply_reference_units"]
        == exposure["circulating_supply_reference_units"],
        "frozen supply evidence disagrees with the active local fixture",
    )
    serialized = json.dumps(config).lower()
    require(
        not any(marker in serialized for marker in ("mainnet", "testnet", "infura", "alchemy")),
        "production or public-network endpoint marker found in Phase 8 local config",
    )
    deployment = (ROOT / "protocol/script/DeployPhase8Local.s.sol").read_text(
        encoding="utf-8"
    )
    wrappers = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in ("scripts/smoke-phase8-anvil.ps1", "scripts/smoke-phase8-anvil.sh")
    )
    require(
        "keccak256(abi.encodePacked(_observerPublicKey(chainId)))" in deployment,
        "Phase 8 deployment no longer derives observer authority from its public key",
    )
    for domain, (public_key, _) in observer_identities.items():
        require(
            public_key[2:] in deployment.lower() and public_key in wrappers.lower(),
            f"Phase 8 {domain} observer identity is not derived consistently",
        )


def check_topology_and_authority() -> None:
    compose = (ROOT / "infrastructure/local/compose.yaml").read_text(encoding="utf-8")
    for service in (
        "home-anvil:",
        "satellite-anvil:",
        "mock-bridge-provider-a:",
        "mock-bridge-provider-b:",
    ):
        require(service in compose, f"local topology is missing {service}")

    proto = (ROOT / "schemas/proto/unified/v1/crosschain.proto").read_text(encoding="utf-8")
    for token in (
        "enum CrossChainActionType",
        "enum CrossChainMessageState",
        "message CrossChainMessageEnvelope",
        "message CrossChainSourceEventProof",
        "message CrossChainSignerSet",
        "source_signer_set_version",
        "destination_signer_set_version",
        "message CrossChainReorganizationEvidence",
        "orphaned_source_proof",
        "affected_orphaned_source_proofs",
        "affected_orphaned_event_evidence_hashes",
        "affected_orphaned_finality_certificates",
        "replacement_observer_signed_header_commitment",
        "detected_head_observer_signed_header_commitment",
        "orphaned_finality_certificate",
        "observer_signature",
        "observer_signed_header_commitment",
        "oneof typed_action",
    ):
        require(token in proto, f"canonical Phase 8 schema is missing {token}")
    for field in (
        "source_signer_set_version",
        "destination_signer_set_version",
        "signer_set_version",
    ):
        require(
            re.search(rf"\buint32\s+{field}\s*=", proto) is not None,
            f"canonical Phase 8 schema must encode {field} as uint32",
        )

    digest_go = (
        ROOT / "services/cross-chain-coordinator/message/digest.go"
    ).read_text(encoding="utf-8")
    require(
        'const domainTag = "UNIFIED_XCHAIN_MESSAGE_V1"' in digest_go
        and "uintWord(uint64(envelope.GetActionType()))" in digest_go,
        "Go message digest no longer uses the canonical domain and numeric action ordinal",
    )

    solidity = (ROOT / "protocol/src/crosschain/CrossChainTypes.sol").read_text(
        encoding="utf-8"
    )
    require(
        (
            '"UNIFIED_XCHAIN_MESSAGE_V1"' in solidity
            or "0x554e49464945445f58434841494e5f4d4553534147455f563100000000000000"
            in solidity
        )
        and "enum CrossChainActionType" in solidity
        and "envelope.actionType" in solidity,
        "Solidity message digest no longer uses the canonical numeric action vocabulary",
    )

    typescript = (ROOT / "packages/crosschain/typescript/codec.ts").read_text(
        encoding="utf-8"
    )
    python = (
        ROOT
        / "models/foundation_model/src/unified_foundation/cross_chain_codec.py"
    ).read_text(encoding="utf-8")
    for implementation, label in ((typescript, "TypeScript"), (python, "Python")):
        require(
            "UNIFIED_XCHAIN_MESSAGE_V1" in implementation
            and "UNIFIED_SYNTHETIC_FINALITY_V1" in implementation,
            f"{label} cross-chain golden codec domains drifted",
        )

    migration = (
        ROOT / "services/foundation-ledger/migrations/000010_crosschain_messages.sql"
    ).read_text(encoding="utf-8")
    for token in (
        "unified_crosschain_runtime NOLOGIN",
        "unified_crosschain_observer NOLOGIN",
        "unified_crosschain_finality_attester",
        "unified_crosschain_recovery_verifier",
        "unified_crosschain_reorganization_verifier",
        "BETWEEN 1 AND 4294967295",
        "CREATE FUNCTION crosschain.record_header_observation",
        "CREATE FUNCTION crosschain.record_reorganization",
        "orphaned_proof_ids text[] NOT NULL",
        "orphaned_certificate_ids text[] NOT NULL",
        "proof.observer_authority_hash =",
        "proof.finality_policy_hash =",
        "execution.destination_proof_id =",
        "transition.evidence_hash =",
        "'crosschain-incident:'",
        "compensation_payload_hash",
        "disputed transition requires exact authenticated reorganization",
    ):
        require(
            token in migration,
            f"durable authenticated reorganization boundary is missing {token}",
        )

    satellite_migration = (
        ROOT
        / "services/foundation-ledger/migrations/000011_satellite_loan_accounting.sql"
    ).read_text(encoding="utf-8")
    bridge_migration = (
        ROOT / "services/foundation-ledger/migrations/000012_wrapped_uft.sql"
    ).read_text(encoding="utf-8")
    sql_fixture = (
        ROOT
        / "services/foundation-ledger/migrations/tests"
        / "000010_000012_crosschain_foundation_test.sql"
    ).read_text(encoding="utf-8")
    for token in (
        "CREATE TABLE crosschain.action_projections",
        "CREATE FUNCTION crosschain.record_action_projection",
        "CREATE FUNCTION crosschain.post_balanced_journal",
        "public.journal_entry",
        "public.journal_balance",
        "CREATE FUNCTION crosschain.post_compensation_journals",
        "ledger.crosschain_recovery_journal_links",
        "FOR UPDATE",
    ):
        require(
            token in migration,
            f"authenticated atomic accounting boundary is missing {token}",
        )
    for token in (
        "unified_home_accounting_runtime",
        "CREATE TABLE crosschain.direct_home_repayment_evidence",
        "CREATE FUNCTION crosschain.record_direct_home_repayment_evidence",
        "direct repayment lacks immutable authenticated home evidence",
        "ledger.satellite_settlement_links",
        "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crosschain FROM PUBLIC",
    ):
        require(
            token in satellite_migration,
            f"satellite accounting authority boundary is missing {token}",
        )
    for token in (
        "CREATE UNIQUE INDEX one_active_bridge_exposure_policy",
        "status NOT IN ('SETTLED', 'COMPENSATED')",
        "CREATE FUNCTION crosschain.commit_remote_repayment",
        "remote repayment disagrees with immutable canonical release",
        "CREATE FUNCTION crosschain.post_bridge_journal",
        "current_run crosschain.bridge_reconciliations",
        "FOR UPDATE",
        "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA crosschain FROM PUBLIC",
    ):
        require(
            token in bridge_migration,
            f"bridge accounting or serialization boundary is missing {token}",
        )
    for token in (
        "changed caller economics were accepted",
        "commit without canonical action projection was accepted",
        "partially disposed exposure bypassed cap",
        "disputed exposure bypassed cap",
        "difference was inserted after reconciliation close",
        "Phase 8 journal is missing its exact balanced pair",
        "accounting authority or role-grant boundary is invalid",
    ):
        require(
            token in sql_fixture,
            f"Phase 8 negative SQL/accounting fixture is missing {token}",
        )

    projector = (
        ROOT / "services/chain-indexer/crosschain/projector.go"
    ).read_text(encoding="utf-8")
    for token in (
        "AffectedOrphanedSourceProofs",
        "AffectedOrphanedFinalityCertificates",
        "BindRoute",
        '"crosschain-incident:%x"',
    ):
        require(token in projector, f"authenticated projector boundary is missing {token}")
    projector_tests = (
        ROOT / "services/chain-indexer/crosschain/projector_test.go"
    ).read_text(encoding="utf-8")
    require(
        "2b23865344c586ba7ce8a044071eeb04fcc271ab63efe549016de06b1bc9a006"
        in projector_tests,
        "multi-message reorganization digest golden drifted",
    )

    recovery = (
        ROOT / "services/cross-chain-coordinator/recovery/recovery.go"
    ).read_text(encoding="utf-8")
    for token in (
        "OriginalActionPayload",
        "CompensationPayload",
        "AssetAmountCommitment",
        "decodeCompensationPayload",
        "canonicalApprovals",
    ):
        require(token in recovery, f"recovery economics or replay binding is missing {token}")

    registry = (
        ROOT / "services/cross-chain-coordinator/message/registry.go"
    ).read_text(encoding="utf-8")
    require(
        "IsReportAction" in registry and "!IsReportAction(envelope.GetActionType())" in registry,
        "report-action expiry semantics drifted from the protocol",
    )


def check_release_controls() -> None:
    workflow = (ROOT / ".github/workflows/foundation.yml").read_text(encoding="utf-8")
    for token in (
        'version: "v1.7.1"',
        'python-version: "3.12.6"',
        'version: "0.11.15"',
        "uv sync --frozen",
        "scripts/smoke-phase8-anvil.sh",
        "scripts/check-phase8-release-evidence.ps1",
        "-Stage post-reset",
        "scripts/prepare-foundry.ps1",
    ):
        require(token in workflow, f"Phase 8 CI release control is missing {token}")

    foundation_check = (ROOT / "scripts/check-foundation.ps1").read_text(encoding="utf-8")
    for token in (
        "uv run pytest -q tests",
        "uv run mypy --strict models/foundation_model/src tools scripts tests",
    ):
        require(
            token in foundation_check,
            f"Phase 8 Python conformance gate is missing {token}",
        )

    abi_check = (ROOT / "tools/check_abi.py").read_text(encoding="utf-8")
    require(
        'ROOT / "protocol" / "abi" / "phase8"' in abi_check
        and "WrappedUFT" in abi_check
        and "CrossChainCoordinator" in abi_check,
        "Phase 8 ABI compatibility snapshots are not enforced",
    )

    release_path = PHASE8_RELEASE_MANIFEST
    manifest_pipeline = {
        "assembler": ROOT / "tools/assemble_phase8_release_evidence.py",
        "worker": ROOT
        / "services/cross-chain-coordinator/cmd/local-worker/manifest.go",
        "validator": ROOT / "tools/check_phase8_release_evidence.py",
        "wrapper": ROOT / "scripts/check-phase8-release-evidence.ps1",
        "reset": ROOT / "scripts/local-reset.ps1",
        "reset-test": ROOT / "scripts/test-local-reset.ps1",
    }
    for label, path in manifest_pipeline.items():
        text = path.read_text(encoding="utf-8").replace("\\", "/")
        if label in {"assembler", "worker", "validator"}:
            require(
                release_path in text,
                f"Phase 8 {label} is not pinned to the sole release manifest",
            )
        else:
            require(
                "phase8-release-evidence.json" in text
                or "protocol/deployments/local" in text,
                f"Phase 8 {label} does not control the release-manifest lifecycle",
            )
    assembler = manifest_pipeline["assembler"].read_text(encoding="utf-8")
    require(
        "phase8-live-blueprint.json" in assembler
        and "phase8-authenticated-flow.json" in assembler
        and "phase8-release-evidence.json" in assembler,
        "Phase 8 assembler does not bind deploy-only/live evidence to the sole manifest",
    )
    require(
        "phase8-evm-evidence.json" not in assembler,
        "Phase 8 assembler must not retain the synthetic-flow raw artifact fallback",
    )
    wrapper_specific = {
        "scripts/smoke-phase8-anvil.ps1": "scripts/check-phase8-release-evidence.ps1",
        "scripts/smoke-phase8-anvil.sh": "tools/check_phase8_release_evidence.py",
    }
    for wrapper_name, validator_token in wrapper_specific.items():
        wrapper = (ROOT / wrapper_name).read_text(encoding="utf-8")
        for token in (
            "runDeployOnly",
            "run_phase8_authenticated_flow.py",
            "verify-phase8-inclusion",
            "--provider-a-url",
            "--provider-b-url",
            "assemble_phase8_release_evidence.py",
            validator_token,
        ):
            require(
                token in wrapper,
                f"Phase 8 authenticated smoke wrapper {wrapper_name} is missing {token}",
            )

    privileged_check = (
        ROOT / "tools/check_privileged_surface.py"
    ).read_text(encoding="utf-8")
    require(
        "recovery remint" in privileged_check
        and "_mint(record.account, record.amount)" in privileged_check,
        "privileged-surface check does not bind the recovery remint",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-implementation-complete", action="store_true")
    args = parser.parse_args()
    check_paths()
    check_registers()
    check_backlog(args.require_implementation_complete)
    check_local_config()
    check_topology_and_authority()
    check_release_controls()
    print("Phase 8 architecture and local-safety checks passed.")


if __name__ == "__main__":
    main()
