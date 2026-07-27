"""Phase 9 resolution, protection, and recovery conformance checks."""

from __future__ import annotations

import argparse
import csv
import json
import re
import tomllib
from collections.abc import Iterable
from pathlib import Path
from typing import cast

from build_phase9_compatibility_manifest import (
    MANIFEST_PATH as PHASE9_COMPATIBILITY_MANIFEST_PATH,
)
from build_phase9_compatibility_manifest import (
    check_manifest,
    manifest_hash,
    source_set_hash,
)
from check_abi import ABI_PAIRS
from check_phase9_implementation_checkpoints import (
    CHECKPOINT_PATH as PHASE9_IMPLEMENTATION_CHECKPOINT_PATH,
)
from check_phase9_implementation_checkpoints import activated_signatures, validate_checkpoints
from check_phase9_refinance_linked_modules import LinkedModuleCheckError
from check_phase9_refinance_linked_modules import check_repository as check_refinance_linked_modules

ROOT = Path(__file__).resolve().parents[1]

ADR_PATH = ROOT / "adr/0019-phase-9-resolution-protection-and-recovery-boundary.md"
ACTIVATION_ADR_PATH = ROOT / "adr/0020-phase-9-payoff-authority-and-implementation-activation.md"
REFINANCE_ADR_PATH = ROOT / "adr/0021-phase-9-atomic-refinance-authority-and-activation.md"
FACTORY_BOOTSTRAP_ADR_PATH = (
    ROOT / "adr/0022-phase-9-factory-account-position-bootstrap-semantics.md"
)
REFINANCE_MODULE_ADR_PATH = ROOT / "adr/0023-phase-9-refinance-fixed-module-partition.md"
REFINANCE_ACTIVATION_TOPOLOGY_ADR_PATH = (
    ROOT / "adr/0024-phase-9-refinance-activation-topology-control.md"
)
REFINANCE_EXECUTION_SEMANTICS_ADR_PATH = (
    ROOT / "adr/0025-phase-9-refinance-execution-observation-and-settlement-semantics.md"
)
REFINANCE_REPARTITION_ADR_PATH = (
    ROOT / "adr/0026-phase-9-refinance-execution-module-repartition.md"
)
REFINANCE_PHASE_TICKET_ADR_PATH = (
    ROOT / "adr/0027-phase-9-refinance-phase-ticket-execution-repartition.md"
)
ARCHITECTURE_PATH = ROOT / "docs/architecture/phase-9-resolution-protection-recovery.md"
DATA_LAYOUTS_PATH = ROOT / "docs/architecture/phase-9-data-layouts.md"
REFINANCE_ACCEPTANCE_PATH = ROOT / "docs/architecture/phase-9-refinance-acceptance.md"
REFINANCE_REFERENCE_EVIDENCE_PATH = (
    ROOT / "docs/architecture/phase-9-refinance-reference-evidence.md"
)
REFINANCE_DEPLOYMENT_EVIDENCE_PATH = (
    ROOT / "docs/architecture/phase-9-refinance-deployment-evidence.md"
)
BACKLOG_PATH = ROOT / "docs/backlog/phase-9.csv"
WORKSTREAMS_PATH = ROOT / "docs/ownership/WORKSTREAMS.md"
MASTER_PLAN_PATH = (
    ROOT / "docs/specifications/"
    "Unified_Implementation_Master_Plan_Work_Breakdown_and_Parallel_Agent_"
    "Orchestration_Specification_v0.1.md"
)
INVARIANT_SPEC_PATH = (
    ROOT / "docs/specifications/"
    "Unified_Protocol_Invariants_and_Formal_Verification_Specification_v0.1.md"
)
INVARIANT_CATALOG_PATH = ROOT / "security/invariant-catalog.csv"
PHASE8_EXIT_PATH = ROOT / "docs/reviews/phase-8-exit-review.md"
FOUNDATION_CHECK_PATH = ROOT / "scripts/check-foundation.ps1"
CONTRACT_SIZE_CHECK_PATH = ROOT / "scripts/check-contract-sizes.py"
PROTOCOL_COMPILATION_PATH = ROOT / "protocol/src/ProtocolCompilation.sol"
FOUNDRY_CONFIG_PATH = ROOT / "protocol/foundry.toml"
PHASE9_ABI_PATH = ROOT / "protocol/abi/phase9"
PHASE9_STORAGE_PATH = ROOT / "protocol/storage-layout/phase9"
PHASE9_STORAGE_CHECK_PATH = ROOT / "tools/check_phase9_storage_layouts.py"
PHASE9_DEPLOY_SCRIPT_PATH = ROOT / "protocol/script/DeployPhase9Local.s.sol"
PHASE9_RELEASE_CHECK_PATH = ROOT / "tools/check_phase9_release_evidence.py"
PHASE9_RELEASE_SCHEMA_PATH = (
    ROOT / "infrastructure/local/resolution/phase9-release-evidence.schema.json"
)
PHASE9_RELEASE_DOC_PATH = ROOT / "docs/architecture/phase-9-local-release-evidence.md"
PHASE9_FREEZE_REVIEW_PATH = ROOT / "security/reviews/phase-9-interface-freeze.md"

PHASE9_PRODUCTION_CONTRACTS = (
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
)
PHASE9_CONTRACTS = (*PHASE9_PRODUCTION_CONTRACTS, "Phase9LocalSyntheticToken")
PHASE9_FOUNDRY_WARNING_CODE = 2018
PHASE9_FREEZE_ERROR = "Phase9ImplementationNotFrozen"
PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER = "_phase9FrozenErrorCompatibilityMarker"
REFINANCE_LINKED_MODULE_MARKERS = (
    "library Phase9RefinanceValidationModule",
    "library Phase9RefinanceRequestModule",
    "library Phase9RefinanceLifecycleModule",
    "library Phase9RefinanceExecutionPrepareModule",
    "library Phase9RefinanceExecutionFinalizeModule",
)
REFINANCE_REPARTITION_MANIFEST_START = (
    "<!-- phase9-refinance-repartition-manifest:start -->"
)
REFINANCE_REPARTITION_MANIFEST_END = (
    "<!-- phase9-refinance-repartition-manifest:end -->"
)
REFINANCE_PHASE_TICKET_MANIFEST_START = (
    "<!-- phase9-refinance-phase-ticket-manifest:start -->"
)
REFINANCE_PHASE_TICKET_MANIFEST_END = (
    "<!-- phase9-refinance-phase-ticket-manifest:end -->"
)

_REFINANCE_EXECUTION_PLAN_FIELDS = (
    ("domain", "bytes32", 0, 1),
    ("chainId", "uint256", 1, 1),
    ("coordinator", "address", 2, 1),
    ("refinanceId", "bytes32", 3, 1),
    ("operationId", "bytes32", 4, 1),
    ("executionBlock", "uint64", 5, 1),
    ("executedAt", "uint64", 6, 1),
    ("planSuffixHash", "bytes32", 7, 1),
    ("storedStateVersion", "uint64", 8, 1),
    ("refinanceNonce", "uint64", 9, 1),
    ("quoteId", "bytes32", 10, 1),
    ("consumedDebtStateVersion", "uint64", 11, 1),
    ("consumedQuoteHash", "bytes32", 12, 1),
    ("refinancePolicyHash", "bytes32", 13, 1),
    ("oldLoanId", "bytes32", 14, 1),
    ("newLoanId", "bytes32", 15, 1),
    ("oldAccount", "address", 16, 1),
    ("oldPositionManager", "address", 17, 1),
    ("newAccount", "address", 18, 1),
    ("newPositionManager", "address", 19, 1),
    ("settlementToken", "address", 20, 1),
    ("collateralCount", "uint32", 21, 1),
    ("collateralIdsHash", "bytes32", 22, 1),
    ("replacementTrancheCount", "uint32", 23, 1),
    ("replacementTranchesHash", "bytes32", 24, 1),
    ("replacementPositionCount", "uint32", 25, 1),
    ("replacementPositionsHash", "bytes32", 26, 1),
    ("commitmentCount", "uint32", 27, 1),
    ("fundedCommitmentInventoryHash", "bytes32", 28, 1),
    ("distinctRecipientCount", "uint8", 29, 1),
    ("payoutRecipients", "address[4]", 30, 4),
    ("payoutAmounts", "uint256[4]", 34, 4),
    ("uniqueRecipients", "address[4]", 38, 4),
    ("uniqueExpected", "uint256[4]", 42, 4),
    ("uniqueStartingBalances", "uint256[4]", 46, 4),
    ("firstLegRecipientBefore", "uint256[2]", 50, 2),
    ("firstLegRecipientAfter", "uint256[2]", 52, 2),
    ("firstLegCoordinatorBefore", "uint256[2]", 54, 2),
    ("firstLegCoordinatorAfter", "uint256[2]", 56, 2),
    ("firstLegHashes", "bytes32[2]", 58, 2),
    ("initialTrancheHash", "bytes32", 60, 1),
    ("initialPositionHash", "bytes32", 61, 1),
    ("initialRightsHash", "bytes32", 62, 1),
    ("replacementDebtHash", "bytes32", 63, 1),
    ("componentPayoutHash", "bytes32", 64, 1),
    ("oldDebtStateHash", "bytes32", 65, 1),
    ("oldDebtResultHash", "bytes32", 66, 1),
    ("coordinatorBalanceBeforeAll", "uint256", 67, 1),
)

EXPECTED_REFINANCE_REPARTITION_MANIFEST: dict[str, object] = {
    "schema": "phase9-refinance-repartition-v1",
    "status": "historical-rejected-topology",
    "topology_selected": False,
    "normative_execution_sizes_accepted": False,
    "execution_plan_retained_by_adr0027": True,
    "execution_plan": {
        "name": "ExecutionPlanV1",
        "abi_words": 68,
        "abi_bytes": 2176,
        "domain": "UNIFIED_REFINANCE_EXECUTION_PLAN_V1",
        "suffix_word_start": 8,
        "suffix_word_count": 60,
        "suffix_bytes": 1920,
        "fields": [
            {
                "name": name,
                "abi_type": abi_type,
                "word_start": word_start,
                "word_count": word_count,
            }
            for name, abi_type, word_start, word_count in _REFINANCE_EXECUTION_PLAN_FIELDS
        ],
    },
    "caps": {
        "collateral_count": 16,
        "replacement_tranche_count": 8,
        "replacement_position_count": 32,
        "commitment_count": 32,
        "distinct_recipient_count": 4,
    },
    "hashes": {
        "plan_suffix_hash": (
            "keccak256(raw 1920-byte planBytes suffix at bytes 256..2175 / words 8..67)"
        ),
        "plan_bytes": "abi.encode(ExecutionPlanV1)",
        "plan_hash": "keccak256(planBytes)",
        "replacement_debt_hash": "keccak256(abi.encode(replacementDebt))",
        "funded_commitment_inventory_hash": (
            "keccak256(abi.encode(keccak256(\"UNIFIED_REFINANCE_FUNDED_COMMITMENT_"
            "INVENTORY_V1\"), block.chainid, address(this), refinanceId, "
            "orderedCommitmentIds, orderedFundingCommitmentRecords))"
        ),
    },
    "zero_tail_rules": [
        "uniqueRecipients[i] == address(0) for i >= distinctRecipientCount",
        "uniqueExpected[i] == 0 for i >= distinctRecipientCount",
        "uniqueStartingBalances[i] == 0 for i >= distinctRecipientCount",
    ],
    "modules": [
        {
            "name": "Phase9RefinanceValidationModule",
            "ownership": "request-preflight",
            "entries": ["preflight"],
        },
        {
            "name": "Phase9RefinanceRequestModule",
            "ownership": "request-lock-and-completion",
            "entries": ["begin", "complete"],
        },
        {
            "name": "Phase9RefinanceLifecycleModule",
            "ownership": "funding-cancellation-refund",
            "entries": [
                "recordFundingCommitment",
                "cancelRefinance",
                "refundCommitment",
            ],
        },
        {
            "name": "Phase9RefinanceExecutionPrepareModule",
            "ownership": "execution-replay-validation-midpoint",
            "entries": ["prepareExecution"],
        },
        {
            "name": "Phase9RefinanceExecutionFinalizeModule",
            "ownership": "execution-reresolution-lien-activation-terminal",
            "entries": ["finalizeExecution"],
        },
    ],
    "call_sites": [
        {
            "ordinal": 1,
            "wrapper": "requestRefinance",
            "module": "Phase9RefinanceRequestModule",
            "entry": "begin",
        },
        {
            "ordinal": 2,
            "wrapper": "requestRefinance",
            "module": "Phase9RefinanceValidationModule",
            "entry": "preflight",
        },
        {
            "ordinal": 3,
            "wrapper": "requestRefinance",
            "module": "Phase9RefinanceRequestModule",
            "entry": "complete",
        },
        {
            "ordinal": 4,
            "wrapper": "recordFundingCommitment",
            "module": "Phase9RefinanceLifecycleModule",
            "entry": "recordFundingCommitment",
        },
        {
            "ordinal": 5,
            "wrapper": "executeRefinance",
            "module": "Phase9RefinanceExecutionPrepareModule",
            "entry": "prepareExecution",
        },
        {
            "ordinal": 6,
            "wrapper": "executeRefinance",
            "module": "Phase9RefinanceExecutionFinalizeModule",
            "entry": "finalizeExecution",
        },
        {
            "ordinal": 7,
            "wrapper": "cancelRefinance",
            "module": "Phase9RefinanceLifecycleModule",
            "entry": "cancelRefinance",
        },
        {
            "ordinal": 8,
            "wrapper": "refundCommitment",
            "module": "Phase9RefinanceLifecycleModule",
            "entry": "refundCommitment",
        },
    ],
    "create_order": [
        {"nonce": 1, "artifact": "LienRegistry"},
        {"nonce": 2, "artifact": "CollateralCustodyV2"},
        {"nonce": 3, "artifact": "Phase9LoanAccount"},
        {"nonce": 4, "artifact": "PositionManagerV2"},
        {"nonce": 5, "artifact": "Phase9LoanFactory"},
        {"nonce": 6, "artifact": "Phase9RefinanceValidationModule"},
        {"nonce": 7, "artifact": "Phase9RefinanceRequestModule"},
        {"nonce": 8, "artifact": "Phase9RefinanceLifecycleModule"},
        {"nonce": 9, "artifact": "Phase9RefinanceExecutionPrepareModule"},
        {"nonce": 10, "artifact": "Phase9RefinanceExecutionFinalizeModule"},
        {"nonce": 11, "artifact": "PayoffQuoteEngine"},
        {"nonce": 12, "artifact": "RefinanceCoordinator"},
    ],
    "module_runtime_budget_bytes": 22118,
}

EXPECTED_REFINANCE_PHASE_TICKET_SEMANTICS: dict[str, object] = {
    "schema": "phase9-refinance-phase-ticket-repartition-v1",
    "status": "unproven-non-accepted-topology-candidate",
    "topology_selected": False,
    "validation_payload": {
        "name": "ValidationPayloadV1",
        "word_formula": "168 + (33+c+5*t+6*p) + (1+6*n+sum(ceil(codeLen[i]/32)))",
        "caps": {"c": 16, "t": 8, "p": 32, "n": 5},
        "fixed_codes": [
            "PRINCIPAL",
            "ACCRUED_INTEREST",
            "FEE",
            "PENALTY",
            "FEE_PENALTY_CREDIT",
        ],
        "maximum_words": 485,
        "maximum_bytes": 15520,
        "root_offset": "0x20",
        "struct_head_words": 167,
        "struct_head_bytes": "0x14e0",
        "policy_offset_word": 27,
        "policy_offset": "0x14e0",
        "components_offset_word": 52,
        "components_offset_formula": "0x14e0 + 0x20*(33+c+5*t+6*p)",
        "policy_nested_offset_formulas": {
            "collateral": "0x3c0",
            "tranches": "0x3c0+0x20*(1+c)",
            "positions": "tranches+0x20*(1+5*t)",
        },
        "component_element_offset_formula": (
            "0x20*n + 0x20*sum(j=0..i-1)(5+ceil(codeLen[j]/32))"
        ),
        "component_string_offset": "0x80",
        "fixed_code_element_offsets": ["0xa0", "0x160", "0x220", "0x2e0", "0x3a0"],
        "maximum_offsets": {
            "components": "0x3800",
            "collateral": "0x3c0",
            "tranches": "0x5e0",
            "positions": "0xb00",
        },
        "canonical_exact_length_offsets_padding_required": True,
        "canonical_reencode_must_equal_raw_bytes": True,
    },
    "guard": {
        "domain": "UNIFIED_REFINANCE_EXECUTION_GUARD_V1",
        "preimage_words": 18,
        "fields": [
            "domain",
            "block.chainid",
            "address(this)",
            "refinanceId",
            "operationId",
            "oldLoanId",
            "quoteId",
            "FUNDING_ESCROWED",
            "storedStateVersion",
            "refinanceNonce",
            "fundingAmount",
            "acceptedFunding",
            "escrowedUnits",
            "activeLockWord",
            "executionAttempts",
            "terminalEvidenceHash",
            "processedOperation",
            "expiresAt",
        ],
    },
    "pre_payoff_ticket": {
        "domain": "UNIFIED_REFINANCE_PRE_PAYOFF_TICKET_V1",
        "preimage_words": 3,
        "fields": ["domain", "guardHash", "contextHash"],
    },
    "replay_discriminator": {
        "storage_only": True,
        "returns_stored_terminal_result": True,
        "returns_empty_context": True,
        "skips_remaining_execution_calls": 5,
    },
    "proof": {
        "name": "PhaseValidationProofV1",
        "abi_words": 2,
        "abi_bytes": 64,
        "fields": ["phaseFactsHash", "ticketHash"],
        "ticket_preimage_words": 14,
        "ticket_preimage_bytes": 448,
        "ticket_preimage_fields": [
            "ticketDomain",
            "block.chainid",
            "address(this)",
            "refinanceId",
            "operationId",
            "contextHash",
            "planHash",
            "parentHash",
            "executionBlock",
            "executedAt",
            "storedStateVersion",
            "refinanceNonce",
            "quoteId",
            "phaseFactsHash",
        ],
        "domains": {
            "pre_lien_facts": "UNIFIED_REFINANCE_PRE_LIEN_FACTS_V1",
            "pre_lien_ticket": "UNIFIED_REFINANCE_PRE_LIEN_TICKET_V1",
            "pre_finalize_facts": "UNIFIED_REFINANCE_PRE_FINALIZE_FACTS_V1",
            "pre_finalize_ticket": "UNIFIED_REFINANCE_PRE_FINALIZE_TICKET_V1",
        },
        "common_non_action_observations": 11,
        "fresh_context_observation": "phaseCurrentContextHash",
        "fresh_context_preimage_words": 20,
        "fresh_context_preimage_bytes": 640,
        "fresh_context_preimage_fields": [
            "domain",
            "block.chainid",
            "address(this)",
            "refinanceId",
            "operationId",
            "EXECUTING",
            "storedStateVersion",
            "refinanceNonce",
            "fundingAmount",
            "acceptedFunding",
            "escrowedUnits",
            "activeLockWord",
            "executionAttempts",
            "terminalEvidenceHash",
            "terminalResultHash",
            "processedOperation",
            "quoteId",
            "contextHash",
            "collateralCount",
            "collateralIdsHash",
        ],
        "terminal_result_hash_source": "state.terminalResults[refinanceId].resultHash",
        "terminal_result_hash_required_zero": True,
        "phase_facts_exclude_lien_action_data": True,
        "facts_or_ticket_is_action_authority": False,
    },
    "current_guard_reread_entries": [
        "validatePreLien",
        "executeLienBarrier",
        "validatePreFinalize",
        "finalizeExecution",
    ],
    "normative_execution_sizes_accepted": False,
    "normative_execution_remeasurement": "pending",
    "replacement_topology": (
        "pending reproducible normative measurement/repartition and successor ADR"
    ),
}

EXPECTED_QUOTE_PREIMAGE = (
    '"UNIFIED_PAYOFF_QUOTE_V1"',
    "payoff_quote_engine",
    "chainid",
    "loan_id",
    "loan_account",
    "policy_hash",
    "debt_state_version",
    "principal",
    "accrued_interest",
    "fees",
    "penalties",
    "credits",
    "component_beneficiary_hash",
    "net_payoff",
    "settlement_asset_id",
    "settlement_token",
    "settlement_route_hash",
    "issued_at",
    "valid_until",
    "quote_nonce",
)

BACKLOG_IDS = (
    "UNI-ADR-014",
    "UNI-RESIDUAL-003",
    "UNI-RESIDUAL-004",
    "UNI-SCHEMA-013",
    "UNI-ABI-009",
    "UNI-ADR-015",
    "UNI-PAYOFF-001",
    "UNI-ADR-016",
    "UNI-ADR-017",
    "UNI-ADR-018",
    "UNI-ADR-019",
    "UNI-ADR-020",
    "UNI-REFI-001",
    "UNI-REFI-002",
    "UNI-RESTRUCT-001",
    "UNI-RESERVE-001",
    "UNI-INSURANCE-001",
    "UNI-GUARANTEE-001",
    "UNI-RECOVERY-002",
    "UNI-DATA-003",
    "UNI-ACCOUNTING-012",
    "UNI-RECON-004",
    "UNI-LOCAL-003",
    "UNI-SIM-008",
    "UNI-RISK-003",
    "UNI-SEC-014",
    "UNI-REVIEW-012",
)
BOUNDARY_COMPLETE_IDS = {
    "UNI-ADR-014",
    "UNI-RESIDUAL-003",
    "UNI-RESIDUAL-004",
    "UNI-ADR-015",
    "UNI-ADR-016",
    "UNI-ADR-017",
    "UNI-ADR-018",
    "UNI-ADR-019",
    "UNI-ADR-020",
}
SECURITY_REVIEW_ID = "UNI-SEC-014"
EXIT_REVIEW_ID = "UNI-REVIEW-012"
ALLOWED_BACKLOG_STATUSES = {"TODO", "DONE"}

REQUIRED_RISKS = {f"RISK-PHASE9-{index:03d}" for index in range(1, 16)}
REQUIRED_ASSUMPTIONS = {f"ASM-{index:03d}" for index in range(34, 45)}
REFINANCE_ACCEPTANCE_ID_COUNTS = {
    "COMPAT": 3,
    "CHECK": 2,
    "RISK": 1,
    "DEPLOY": 4,
    "BOOT": 5,
    "AUTH": 8,
    "ID": 6,
    "SRC": 6,
    "STATE": 4,
    "VIEW": 1,
    "FUND": 5,
    "EXEC": 9,
    "EXIT": 5,
    "RPL": 4,
    "TIME": 1,
    "FAIL": 4,
    "DON": 4,
    "EVT": 3,
    "INV": 1,
    "FZ": 1,
    "LOCAL": 3,
}
REQUIRED_REFINANCE_ACCEPTANCE_IDS = {
    f"P9R-{family}-{index:03d}"
    for family, count in REFINANCE_ACCEPTANCE_ID_COUNTS.items()
    for index in range(1, count + 1)
}
REQUIRED_INVARIANTS = {
    *(f"INV-ACC-{index:03d}" for index in range(1, 8)),
    *(f"INV-AUTH-{index:03d}" for index in range(1, 10)),
    *(f"INV-LOAN-{index:03d}" for index in range(1, 16)),
    *(f"INV-FUND-{index:03d}" for index in range(1, 12)),
    *(f"INV-INT-{index:03d}" for index in range(1, 13)),
    *(f"INV-COL-{index:03d}" for index in range(1, 13)),
    *(f"INV-LIQ-{index:03d}" for index in range(5, 13)),
    *(f"INV-REFI-{index:03d}" for index in range(1, 9)),
    *(f"INV-INS-{index:03d}" for index in range(1, 10)),
    *(f"REC-{index:03d}" for index in range(1, 9)),
    "LIVE-REFI-001",
}

PROTO_FILENAMES = (
    "refinance.proto",
    "restructuring.proto",
    "protection.proto",
    "recovery.proto",
)
RELEASE_MANIFEST_PATH = "protocol/deployments/local/phase9-release-evidence.json"

BOUNDARY_PATHS = (
    ADR_PATH,
    ACTIVATION_ADR_PATH,
    REFINANCE_ADR_PATH,
    FACTORY_BOOTSTRAP_ADR_PATH,
    REFINANCE_MODULE_ADR_PATH,
    REFINANCE_ACTIVATION_TOPOLOGY_ADR_PATH,
    REFINANCE_EXECUTION_SEMANTICS_ADR_PATH,
    REFINANCE_REPARTITION_ADR_PATH,
    REFINANCE_PHASE_TICKET_ADR_PATH,
    ARCHITECTURE_PATH,
    DATA_LAYOUTS_PATH,
    REFINANCE_ACCEPTANCE_PATH,
    REFINANCE_REFERENCE_EVIDENCE_PATH,
    REFINANCE_DEPLOYMENT_EVIDENCE_PATH,
    BACKLOG_PATH,
    WORKSTREAMS_PATH,
    MASTER_PLAN_PATH,
    INVARIANT_SPEC_PATH,
    INVARIANT_CATALOG_PATH,
    PHASE8_EXIT_PATH,
    FOUNDATION_CHECK_PATH,
)

IMPLEMENTATION_PATHS = (
    ROOT / "services/foundation-ledger/migrations/000013_resolution_core.sql",
    ROOT / "services/foundation-ledger/migrations/000014_protection_recovery.sql",
    ROOT / "services/foundation-ledger/migrations/000015_resolution_accounting.sql",
    ROOT / "services/resolution-coordinator",
    ROOT / "security/reviews/phase-9-internal-review.md",
    PHASE9_ABI_PATH,
    PHASE9_STORAGE_PATH,
    PHASE9_STORAGE_CHECK_PATH,
    PHASE9_DEPLOY_SCRIPT_PATH,
    PHASE9_RELEASE_SCHEMA_PATH,
    PHASE9_RELEASE_DOC_PATH,
    PHASE9_RELEASE_CHECK_PATH,
    ROOT / "scripts/check-phase9-release-evidence.ps1",
    *(ROOT / "schemas/proto/unified/v1" / filename for filename in PROTO_FILENAMES),
)

EXIT_PATH = ROOT / "docs/reviews/phase-9-exit-review.md"
README_PATH = ROOT / "README.md"

REGISTER_FIELDS = ("owner", "evidence", "expiry", "downstream_impact", "validation")
AUTHORITY_OWNERS = {
    "Program Authority",
    "Protocol Architecture Authority",
    "Security Authority",
    "Accounting and Economic Risk Authority",
    "Release Authority",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"ERROR: {message}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip().lower()


def require_paths(paths: Iterable[Path], label: str) -> None:
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.exists()]
    require(not missing, f"missing {label}: {', '.join(missing)}")


def check_boundary_paths() -> None:
    require_paths(BOUNDARY_PATHS, "Phase 9 boundary paths")


def check_backlog(require_implementation: bool, require_exit: bool) -> dict[str, dict[str, str]]:
    with BACKLOG_PATH.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        require(
            reader.fieldnames == ["id", "workstream", "title", "status", "owner", "acceptance"],
            "Phase 9 backlog header drifted",
        )
        rows = list(reader)

    identifiers = [row["id"] for row in rows]
    require(identifiers == list(BACKLOG_IDS), "Phase 9 backlog IDs or ordering drifted")
    require(len(identifiers) == len(set(identifiers)), "Phase 9 backlog IDs are duplicated")

    by_id = {row["id"]: row for row in rows}
    for identifier, row in by_id.items():
        require(
            row["status"] in ALLOWED_BACKLOG_STATUSES,
            f"{identifier} has unsupported status {row['status']!r}",
        )
        require(row["workstream"].startswith("WS-"), f"{identifier} lacks a workstream")
        require(row["owner"] in AUTHORITY_OWNERS, f"{identifier} has an unknown owner")
        require(bool(row["title"].strip()), f"{identifier} lacks a title")
        require(bool(row["acceptance"].strip()), f"{identifier} lacks acceptance evidence")

    incomplete_boundary = sorted(
        identifier for identifier in BOUNDARY_COMPLETE_IDS if by_id[identifier]["status"] != "DONE"
    )
    require(
        not incomplete_boundary,
        f"Phase 9 boundary rows must remain DONE: {incomplete_boundary}",
    )
    check_backlog_precedence(by_id)

    if by_id[EXIT_REVIEW_ID]["status"] == "DONE":
        incomplete = [row["id"] for row in rows if row["status"] != "DONE"]
        require(not incomplete, "Phase 9 exit cannot be DONE while another row is incomplete")

    if by_id[SECURITY_REVIEW_ID]["status"] == "DONE":
        incomplete_before_review = [
            row["id"]
            for row in rows
            if row["id"] not in {SECURITY_REVIEW_ID, EXIT_REVIEW_ID} and row["status"] != "DONE"
        ]
        require(
            not incomplete_before_review,
            "Phase 9 security review cannot close before implementation work: "
            + ", ".join(incomplete_before_review),
        )

    if require_implementation:
        incomplete_implementation = [
            row["id"] for row in rows if row["id"] != EXIT_REVIEW_ID and row["status"] != "DONE"
        ]
        require(
            not incomplete_implementation,
            "Phase 9 implementation backlog remains open: " + ", ".join(incomplete_implementation),
        )

    if require_exit:
        incomplete_exit = [row["id"] for row in rows if row["status"] != "DONE"]
        require(
            not incomplete_exit,
            "Phase 9 exit backlog remains open: " + ", ".join(incomplete_exit),
        )
    return by_id


def check_backlog_precedence(by_id: dict[str, dict[str, str]]) -> None:
    schema_done = by_id["UNI-SCHEMA-013"]["status"] == "DONE"
    abi_done = by_id["UNI-ABI-009"]["status"] == "DONE"
    require(
        not abi_done or schema_done,
        "UNI-SCHEMA-013 must be DONE before UNI-ABI-009 can be DONE",
    )

    abi_index = BACKLOG_IDS.index("UNI-ABI-009")
    later_done = [
        identifier
        for identifier in BACKLOG_IDS[abi_index + 1 :]
        if by_id[identifier]["status"] == "DONE"
    ]
    require(
        abi_done or not later_done,
        "UNI-ABI-009 must be DONE before later Phase 9 work can be DONE: " + ", ".join(later_done),
    )

    activation_done = by_id["UNI-ADR-015"]["status"] == "DONE"
    activation_index = BACKLOG_IDS.index("UNI-ADR-015")
    implementation_done = [
        identifier
        for identifier in BACKLOG_IDS[activation_index + 1 :]
        if by_id[identifier]["status"] == "DONE"
    ]
    require(
        activation_done or not implementation_done,
        "UNI-ADR-015 must be DONE before Phase 9 implementation work can be DONE: "
        + ", ".join(implementation_done),
    )

    refinance_activation_done = by_id["UNI-ADR-016"]["status"] == "DONE"
    refinance_bootstrap_done = by_id["UNI-ADR-017"]["status"] == "DONE"
    refinance_module_candidate_done = by_id["UNI-ADR-018"]["status"] == "DONE"
    refinance_activation_topology_done = by_id["UNI-ADR-019"]["status"] == "DONE"
    refinance_execution_semantics_done = by_id["UNI-ADR-020"]["status"] == "DONE"
    refinance_done = [
        identifier
        for identifier in ("UNI-REFI-001", "UNI-REFI-002")
        if by_id[identifier]["status"] == "DONE"
    ]
    require(
        refinance_activation_done or not refinance_done,
        "UNI-ADR-016 must be DONE before either Phase 9 refinance row can be DONE: "
        + ", ".join(refinance_done),
    )
    require(
        refinance_bootstrap_done or not refinance_done,
        "UNI-ADR-017 must be DONE before either Phase 9 refinance row can be DONE: "
        + ", ".join(refinance_done),
    )
    require(
        refinance_module_candidate_done or not refinance_done,
        "UNI-ADR-018 must be DONE before either Phase 9 refinance row can be DONE: "
        + ", ".join(refinance_done),
    )
    require(
        refinance_activation_topology_done or not refinance_done,
        "UNI-ADR-019 must be DONE before either Phase 9 refinance row can be DONE: "
        + ", ".join(refinance_done),
    )
    require(
        refinance_execution_semantics_done or not refinance_done,
        "UNI-ADR-020 must be DONE before either Phase 9 refinance row can be DONE: "
        + ", ".join(refinance_done),
    )


def check_refinance_checkpoint_precedence(
    by_id: dict[str, dict[str, str]], checkpoint_packages: Iterable[dict[str, object]]
) -> None:
    refinance_packages = [
        package for package in checkpoint_packages if package.get("checkpointId") == "P9-REFI-001"
    ]
    require(
        len(refinance_packages) <= 1,
        "P9-REFI-001 checkpoint package is duplicated",
    )
    if not refinance_packages:
        return
    raw_required = refinance_packages[0].get("requiredBacklogIds")
    require(
        isinstance(raw_required, list) and all(isinstance(value, str) for value in raw_required),
        "P9-REFI-001 required backlog IDs are malformed",
    )
    required_backlog_ids = cast(list[str], raw_required)
    expected_required_backlog_ids = [
        "UNI-ADR-016",
        "UNI-ADR-017",
        "UNI-ADR-018",
        "UNI-ADR-019",
        "UNI-ADR-020",
        "UNI-REFI-001",
        "UNI-REFI-002",
    ]
    require(
        required_backlog_ids == expected_required_backlog_ids,
        "P9-REFI-001 requiredBacklogIds must exactly bind UNI-ADR-016 through "
        "UNI-ADR-020 and both bundled refinance rows",
    )
    for identifier in expected_required_backlog_ids[:5]:
        require(
            by_id[identifier]["status"] == "DONE",
            f"P9-REFI-001 cannot exist before {identifier} is DONE",
        )
    incomplete = [
        identifier
        for identifier in ("UNI-REFI-001", "UNI-REFI-002")
        if by_id[identifier]["status"] != "DONE"
    ]
    require(
        not incomplete,
        "P9-REFI-001 cannot exist before the bundled refinance rows are DONE: "
        + ", ".join(incomplete),
    )


def declared_ids(text: str, pattern: str) -> set[str]:
    return set(re.findall(pattern, text, flags=re.MULTILINE))


def check_boundary_declarations() -> None:
    adr = read(ADR_PATH)
    risks = declared_ids(adr, r"`(RISK-PHASE9-\d{3})`")
    assumptions = declared_ids(adr, r"`(ASM-\d{3})`")
    require(risks == REQUIRED_RISKS, "Phase 9 boundary risk declarations drifted")
    require(
        REQUIRED_ASSUMPTIONS <= assumptions,
        "Phase 9 boundary assumption declarations are incomplete",
    )
    unexpected_assumptions = {
        identifier
        for identifier in assumptions
        if identifier.startswith("ASM-") and identifier not in REQUIRED_ASSUMPTIONS
    }
    require(
        not unexpected_assumptions,
        "Phase 9 boundary declares unexpected assumptions: "
        + ", ".join(sorted(unexpected_assumptions)),
    )


def section(text: str, heading: str) -> str:
    match = re.search(
        rf"^##\s+{re.escape(heading)}\b(?P<body>.*?)(?=^##\s+|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"ERROR: workstream section {heading} is missing")
    return match.group("body")


def require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    lowered = text.lower()
    missing = [token for token in tokens if token.lower() not in lowered]
    require(not missing, f"{label} is missing: {', '.join(missing)}")


def parse_embedded_json_manifest(
    document: str,
    start_marker: str,
    end_marker: str,
    label: str,
) -> dict[str, object]:
    require(
        document.count(start_marker) == 1,
        f"{label} must have exactly one start marker",
    )
    require(
        document.count(end_marker) == 1,
        f"{label} must have exactly one end marker",
    )
    start = document.index(start_marker)
    end = document.index(end_marker)
    require(start < end, f"{label} markers are out of order")
    fenced = document[start + len(start_marker) : end]
    match = re.fullmatch(r"\s*```json\s*(?P<payload>.*?)\s*```\s*", fenced, re.DOTALL)
    require(match is not None, f"{label} must be one JSON code fence")

    def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate key {key}")
            result[key] = value
        return result

    try:
        parsed = json.loads(match.group("payload"), object_pairs_hook=reject_duplicate_keys)
    except (json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"ERROR: {label} is invalid JSON: {exc}") from exc
    require(isinstance(parsed, dict), f"{label} root must be an object")
    return cast(dict[str, object], parsed)


def parse_refinance_repartition_manifest(document: str) -> dict[str, object]:
    return parse_embedded_json_manifest(
        document,
        REFINANCE_REPARTITION_MANIFEST_START,
        REFINANCE_REPARTITION_MANIFEST_END,
        "Phase 9 refinance repartition manifest",
    )


def parse_refinance_phase_ticket_manifest(document: str) -> dict[str, object]:
    return parse_embedded_json_manifest(
        document,
        REFINANCE_PHASE_TICKET_MANIFEST_START,
        REFINANCE_PHASE_TICKET_MANIFEST_END,
        "Phase 9 refinance phase-ticket manifest",
    )


def validate_refinance_repartition_manifest(document: str) -> None:
    manifest = parse_refinance_repartition_manifest(document)
    plan = manifest.get("execution_plan")
    require(
        isinstance(plan, dict),
        "Phase 9 refinance repartition manifest execution_plan must be an object",
    )
    fields = plan.get("fields")
    require(
        isinstance(fields, list),
        "Phase 9 refinance repartition manifest fields must be an array",
    )

    cursor = 0
    for index, raw_field in enumerate(fields):
        require(
            isinstance(raw_field, dict),
            f"Phase 9 refinance repartition manifest field {index} must be an object",
        )
        field = cast(dict[str, object], raw_field)
        name = field.get("name")
        abi_type = field.get("abi_type")
        word_start = field.get("word_start")
        word_count = field.get("word_count")
        require(
            isinstance(name, str) and isinstance(abi_type, str),
            f"Phase 9 refinance repartition manifest field {index} identity is malformed",
        )
        require(
            isinstance(word_start, int)
            and not isinstance(word_start, bool)
            and isinstance(word_count, int)
            and not isinstance(word_count, bool),
            f"Phase 9 refinance repartition manifest field {name} range is malformed",
        )
        require(
            word_start == cursor and word_count > 0,
            f"Phase 9 refinance repartition manifest field {name} range is not contiguous",
        )
        static_array = re.search(r"\[(\d+)\]$", abi_type)
        expected_words = int(static_array.group(1)) if static_array else 1
        require(
            word_count == expected_words,
            f"Phase 9 refinance repartition manifest field {name} ABI width drifted",
        )
        cursor += word_count

    require(
        cursor == 68,
        "Phase 9 refinance repartition manifest fields must occupy exactly 68 words",
    )
    require(
        plan.get("abi_words") == cursor and plan.get("abi_bytes") == cursor * 32,
        "Phase 9 refinance repartition manifest ABI size must be 68 words / 2176 bytes",
    )
    suffix_word_start = plan.get("suffix_word_start")
    suffix_word_count = plan.get("suffix_word_count")
    require(
        suffix_word_start == 8
        and suffix_word_count == cursor - suffix_word_start
        and plan.get("suffix_bytes") == suffix_word_count * 32,
        "Phase 9 refinance repartition manifest suffix must be words 8..67 / 1920 bytes",
    )

    modules = manifest.get("modules")
    call_sites = manifest.get("call_sites")
    create_order = manifest.get("create_order")
    require(
        isinstance(modules, list) and len(modules) == 5,
        "Phase 9 refinance repartition manifest must own exactly five modules",
    )
    require(
        isinstance(call_sites, list)
        and len(call_sites) == 8
        and all(
            isinstance(call_site, dict) and call_site.get("ordinal") == ordinal
            for ordinal, call_site in enumerate(call_sites, start=1)
        ),
        "Phase 9 refinance repartition manifest must order exactly eight call sites",
    )
    require(
        isinstance(create_order, list)
        and len(create_order) == 12
        and all(
            isinstance(creation, dict) and creation.get("nonce") == nonce
            for nonce, creation in enumerate(create_order, start=1)
        ),
        "Phase 9 refinance repartition manifest must order CREATE nonces 1 through 12",
    )
    require(
        manifest.get("module_runtime_budget_bytes") == 22118,
        "Phase 9 refinance repartition manifest module budget must be 22118 bytes",
    )

    actual = json.dumps(manifest, ensure_ascii=False, separators=(",", ":"))
    expected = json.dumps(
        EXPECTED_REFINANCE_REPARTITION_MANIFEST,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    require(
        actual == expected,
        "Phase 9 refinance repartition manifest content or ordering drifted",
    )


def validate_refinance_phase_ticket_manifest(document: str) -> None:
    manifest = parse_refinance_phase_ticket_manifest(document)
    label = "Phase 9 refinance phase-ticket manifest"

    for key, expected_value in EXPECTED_REFINANCE_PHASE_TICKET_SEMANTICS.items():
        actual = json.dumps(
            manifest.get(key),
            ensure_ascii=False,
            separators=(",", ":"),
        )
        expected = json.dumps(
            expected_value,
            ensure_ascii=False,
            separators=(",", ":"),
        )
        require(actual == expected, f"{label} semantic field {key} drifted")

    require(
        not {"modules", "call_sites", "create_order", "coordinator"} & manifest.keys(),
        f"{label} must not publish an operative selected topology",
    )

    payload = cast(dict[str, object], manifest["validation_payload"])
    caps = cast(dict[str, object], payload["caps"])
    fixed_codes = cast(list[str], payload["fixed_codes"])
    code_words = sum((len(code.encode("utf-8")) + 31) // 32 for code in fixed_codes)
    maximum_words = (
        168
        + (
            33
            + cast(int, caps["c"])
            + 5 * cast(int, caps["t"])
            + 6 * cast(int, caps["p"])
        )
        + (1 + 6 * cast(int, caps["n"]) + code_words)
    )
    require(
        maximum_words == payload["maximum_words"]
        and maximum_words * 32 == payload["maximum_bytes"],
        f"{label} ValidationPayloadV1 maximum arithmetic drifted",
    )
    require(
        cast(int, payload["struct_head_words"]) * 32
        == int(cast(str, payload["struct_head_bytes"]), 16),
        f"{label} ValidationPayloadV1 struct-head size drifted",
    )

    guard = cast(dict[str, object], manifest["guard"])
    require(
        guard["preimage_words"] == len(cast(list[object], guard["fields"])) == 18,
        f"{label} execution guard must contain exactly 18 words",
    )
    pre_payoff_ticket = cast(dict[str, object], manifest["pre_payoff_ticket"])
    require(
        pre_payoff_ticket["preimage_words"]
        == len(cast(list[object], pre_payoff_ticket["fields"]))
        == 3,
        f"{label} pre-payoff ticket must contain exactly 3 words",
    )

    proof = cast(dict[str, object], manifest["proof"])
    require(
        proof["abi_words"] == len(cast(list[object], proof["fields"])) == 2
        and proof["abi_bytes"] == 64,
        f"{label} phase proof must contain exactly 2 ABI words / 64 bytes",
    )
    require(
        proof["ticket_preimage_words"]
        == len(cast(list[object], proof["ticket_preimage_fields"]))
        == 14
        and proof["ticket_preimage_bytes"] == 448,
        f"{label} phase ticket must contain exactly 14 words / 448 bytes",
    )
    require(
        len(cast(dict[str, object], proof["domains"])) == 4,
        f"{label} phase proof must bind exactly four domains",
    )
    require(
        proof["fresh_context_preimage_words"]
        == len(cast(list[object], proof["fresh_context_preimage_fields"]))
        == 20
        and proof["fresh_context_preimage_bytes"] == 640,
        f"{label} fresh current-context receipt must contain exactly 20 words / 640 bytes",
    )
    require_tokens(
        document,
        ('keccak256("UNIFIED_REFINANCE_PHASE_CURRENT_CONTEXT_V1")',),
        f"{label} fresh current-context receipt",
    )


def require_abi_encode_formula(
    text: str,
    name: str,
    expected_body: str,
    label: str,
) -> None:
    matches = re.findall(
        rf"\b{re.escape(name)}\s*=\s*keccak256\(abi\.encode\((.*?)\)\)",
        text,
        flags=re.DOTALL,
    )
    require(len(matches) == 1, f"{label} must declare exactly one {name} formula")
    require(
        normalized(matches[0]) == normalized(expected_body),
        f"{label} {name} formula drifted",
    )


def check_refinance_boundary_evidence() -> None:
    refinance_adr = read(REFINANCE_ADR_PATH)
    factory_bootstrap_adr = read(FACTORY_BOOTSTRAP_ADR_PATH)
    refinance_module_adr = read(REFINANCE_MODULE_ADR_PATH)
    refinance_activation_topology_adr = read(REFINANCE_ACTIVATION_TOPOLOGY_ADR_PATH)
    refinance_execution_semantics_adr = read(REFINANCE_EXECUTION_SEMANTICS_ADR_PATH)
    refinance_repartition_adr = read(REFINANCE_REPARTITION_ADR_PATH)
    refinance_phase_ticket_adr = read(REFINANCE_PHASE_TICKET_ADR_PATH)
    acceptance = read(REFINANCE_ACCEPTANCE_PATH)
    reference = read(REFINANCE_REFERENCE_EVIDENCE_PATH)
    deployment = read(REFINANCE_DEPLOYMENT_EVIDENCE_PATH)
    data_layouts = read(DATA_LAYOUTS_PATH)

    validate_refinance_repartition_manifest(refinance_repartition_adr)
    validate_refinance_phase_ticket_manifest(refinance_phase_ticket_adr)

    forbidden_execute_replay_claims = (
        "on both first execution and exact terminal replay",
        "on both first execution and replay",
        "first execution and exact terminal replay recompute",
        "first execution and replay recompute",
        "exact replay recomputes the id",
        "execute replay requires the recomputed id",
        "replay recomputes the operation id",
        "replay recomputes the execute operation id",
        "terminal replay recomputes `execute_operation_id`",
        "terminal replay recomputes the execute operation id",
        "terminal replay reads the quote",
    )
    for label, document in (
        ("atomic-refinance ADR", refinance_adr),
        ("D3 execution-semantics ADR", refinance_execution_semantics_adr),
        ("refinance reference evidence", reference),
        ("refinance acceptance", acceptance),
        ("Phase 9 architecture", read(ARCHITECTURE_PATH)),
        ("Phase 9 backlog", read(BACKLOG_PATH)),
    ):
        normalized_document = normalized(document)
        stale = [
            claim for claim in forbidden_execute_replay_claims if claim in normalized_document
        ]
        require(
            not stale,
            f"{label} contains forbidden superseded execute-replay claim: {', '.join(stale)}",
        )

    require_tokens(
        normalized(factory_bootstrap_adr),
        (
            "status: accepted for synthetic local specification and implementation review",
            "work item: `uni-adr-017`",
            "compares the complete stored and supplied `loancreationrequest` values",
            "an exact replay must branch before `loanregistry.registerloan`",
            "account-before-manager order is mandatory",
            "the only settlement asset id is the direct, non-hashed mapping",
            "every checkpoint series has at most one entry per block",
            "this decision does not expand adr 0021's method allowlist",
        ),
        "Phase 9 factory/account/position bootstrap semantic boundary",
    )
    require_tokens(
        normalized(refinance_module_adr),
        (
            "status: accepted historical candidate architecture; replacement topology "
            "selection pending",
            "work item: `uni-adr-018`",
            "adr 0026 first replaced, and adr 0027 rejects, this adr's operative "
            "three-library, seven-call, ten-create, nonce-10 coordinator, and "
            "lifecycle-execution ownership controls",
            "phase9refinancevalidationmodule",
            "phase9refinancerequestmodule",
            "phase9refinancelifecyclemodule",
            "contains exactly seven compiler-generated fixed-library call sites",
            "revised ten-create deployment order",
            "nonce 10: the fully linked `refinancecoordinator(...)`",
            "no module may contain a compiler link reference or delegate again",
            "it does not activate any method",
        ),
        "Phase 9 refinance fixed-module candidate boundary",
    )
    require_tokens(
        normalized(refinance_activation_topology_adr),
        (
            "status: accepted for synthetic-local activation-topology specification; "
            "implementation activation pending",
            "work item: `uni-adr-019`",
            "explicit nonce preconditioning is selected",
            "the candidate broadcaster does not deploy `rolemanager`",
            "supersedes only adr 0021 section 18's statement that the refinance graph "
            "broadcaster is also the governance executor",
            "all four identities are nonzero and pairwise distinct",
            "`0x70997970c51812dc3a010c7d01b50e0d17dc79c8`",
            "`0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc`",
            "not caller-supplied private-key, mnemonic, keystore, hardware-wallet, or kms inputs",
            "exactly one successful `anvil_setnonce(candidatebroadcaster, 0x1)` call",
            "1. `lienregistry`; 2. `collateralcustodyv2`; 3. `phase9loanaccount` "
            "implementation; 4. `positionmanagerv2` implementation; 5. "
            "`phase9loanfactory`; 6. `phase9refinancevalidationmodule`; 7. "
            "`phase9refinancerequestmodule`; 8. `phase9refinancelifecyclemodule`; 9. "
            "`payoffquoteengine`; and 10. the fully linked `refinancecoordinator`.",
            "verification precedes the only role grant",
            "only after the verification in section 4",
            "rolemanager.grantrole(",
            "protocolroles.loan_factory_role",
            "the sender is the constructor-bound governance executor",
            "rolegranted(loan_factory_role, phase9loanfactory, type(uint64).max, "
            "governanceexecutor)` log",
            "roleexpiry(loan_factory_role, phase9loanfactory) == type(uint64).max",
            "no role-admin change, second grant, revocation, or other state-changing "
            "transaction occurred",
            "the grant is the last activation-topology transaction",
            "`p9-refi-001` remains absent",
            "requires bounded reset to the exact genesis identity",
            "reset evidence must prove candidate and governance nonces return to zero, "
            "every prerequisite and graph address has empty code, the role grant and all "
            "logs disappear, the exact genesis hash is restored, generated sensitive "
            "configuration is removed, and the disposable anvil process stops.",
        ),
        "Phase 9 refinance activation-topology control",
    )
    require_tokens(
        normalized(refinance_execution_semantics_adr),
        (
            "status: accepted for synthetic-local specification freeze; D3 remains closed",
            "Acceptance of this ADR is documentation-only",
            "`UNI-REFI-001`, `UNI-REFI-002`, every D1-D4 activation gate, and "
            "`P9-REFI-001` remain closed",
            "execution_block = uint64(block.number)",
            '"UNIFIED_REFINANCE_OLD_TRANCHE_EXECUTION_SNAPSHOT_V1"',
            '"UNIFIED_REFINANCE_OLD_POSITION_EXECUTION_SNAPSHOT_V1"',
            '"UNIFIED_REFINANCE_OLD_RIGHTS_EXECUTION_SNAPSHOT_V1"',
            "After old-debt payoff and again before terminal persistence",
            "Execution has exactly four ordered payout legs",
            "must equal neither the refinance coordinator nor the settlement-token address",
            "strictly increasing unsigned-`uint160` order",
            "coordinator_balance_before_all - coordinator_balance_after_all == funding_amount",
            "does not increment `stateVersion`",
            "`FUNDING_ESCROWED -> COMPLETED`",
            "Only first execution reads the stored quote",
            "never recomputes the execute operation ID from a debt version",
            "captures exactly one `executed_at = uint64(block.timestamp)`",
            "The record key and stored `refinanceId` must identify the same nonzero refinance",
            "terminal result must identify that refinance, be `COMPLETED`, have a nonzero event ID",
            "The reconstructed ID must be nonzero and equal the stored event ID",
            "zero dependency calls, writes, transfers, counters, or logs",
            "call `beginHandoff` for every collateral",
            "verify that every old lien is `HANDOFF_PENDING`",
            "call `completeHandoff` for every handoff",
            "verify that every lien is `ACTIVE` for the successor loan",
            "During that window the coordinator makes only calls to the canonical lien registry",
            "This ADR completes only `UNI-ADR-020`",
            "D3 logic may open only after the complete bundled implementation",
        ),
        "Phase 9 D3 execution-semantics boundary",
    )
    require_tokens(
        normalized(refinance_repartition_adr),
        (
            "status: rejected for topology by adr 0027; retained as historical "
            "repartition evidence",
            "f408d159a8fbf8cbde9197e71456cf817d2c101f23e64c5abb10d7abdf4abc76",
            "complete lifecycle prototype | 40,375 | 40,427 | 15,799 bytes over",
            "funding, cancellation, and refund | 19,273 | 19,325 | 5,303 bytes under",
            "execution only | 26,547 | 26,599 | 1,971 bytes over",
            "phase9refinanceexecutionpreparemodule",
            "phase9refinanceexecutionfinalizemodule",
            "exactly eight compiler-generated fixed-library call sites",
            "all-static abi tuple of exactly 68 words and exactly 2,176 bytes",
            'keccak256("unified_refinance_execution_plan_v1")',
            "plansuffixhash = keccak256(raw 1920-byte planbytes suffix from byte 256 "
            "through byte 2175)",
            "the suffix is exactly the contiguous abi words 8 through 67",
            "the full `planhash` is domain-bound by word 0 and binds word 7's suffix hash",
            "replacementdebthash = keccak256(abi.encode(replacementdebt))",
            'keccak256("unified_refinance_funded_commitment_inventory_v1")',
            "an internal, transaction-local transport binding, not a protocol "
            "event/result preimage",
            "current stored `executing`, the unchanged active old-loan lock, full "
            "attributed escrow equal to accepted funding, execution attempt zero, "
            "terminal evidence zero, and an unprocessed matching operation id",
            "it forwards the identical byte string and hash to finalization",
            "does not decode a dynamic tail, rewrite a word, catch a prepare/finalize "
            "revert, or perform an external call between the two modules",
            "re-resolves and re-hashes the canonical quote, policy, accounts, managers, "
            "asset, collateral, replacement, commitment, payout, public snapshot, and "
            "old-debt facts before the first finalization effect",
            "each rejected-candidate execution module had a hard planning budget of "
            "22,118 runtime bytes",
            "exactly twelve consecutive zero-value top-level `create` transactions",
            "nonce 12: the fully linked `refinancecoordinator`",
            "`0xca03dc4665a8c3603cb4fd5ce71af9649dc00d44`",
            "latest and pending candidate nonces at 13 (`0x0d`)",
            "the historical priority-zero plan required storage-only replay before "
            "dependencies, "
            "no catch around either execution-module call, no external/caller-authored/"
            "persisted plan, full rollback under injected failure at every boundary",
            "its priority-one plan required mutation of every plan word, fixed-array "
            "tail, count/hash pair, and ordering rule",
            "does not make the current oversized prototype deployable",
        ),
        "Phase 9 refinance execution-module repartition boundary",
    )

    actual_acceptance_ids = set(
        re.findall(r"\b(P9R-[A-Z]+-\d{3})\b", acceptance, flags=re.MULTILINE)
    )
    require(
        actual_acceptance_ids == REQUIRED_REFINANCE_ACCEPTANCE_IDS,
        "Phase 9 refinance acceptance IDs drifted: "
        f"missing={sorted(REQUIRED_REFINANCE_ACCEPTANCE_IDS - actual_acceptance_ids)} "
        f"unexpected={sorted(actual_acceptance_ids - REQUIRED_REFINANCE_ACCEPTANCE_IDS)}",
    )
    require(
        len(REQUIRED_REFINANCE_ACCEPTANCE_IDS) == 80,
        "Phase 9 refinance acceptance-ID inventory must contain exactly 80 IDs",
    )

    custody_operation_body = """
      "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_V1",
      chainid,
      refinance_coordinator,
      bootstrap_id,
      old_loan_id,
      collateral_custody,
      collateral_id
    """
    require_abi_encode_formula(
        refinance_adr,
        "bootstrap_custody_operation_id",
        custody_operation_body,
        "Phase 9 atomic-refinance semantic boundary",
    )
    require_abi_encode_formula(
        reference,
        "bootstrap_custody_operation_id",
        custody_operation_body,
        "Phase 9 refinance reference evidence",
    )
    require_abi_encode_formula(
        refinance_adr,
        "custody_identity_hash",
        """
          "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
          chainid,
          collateral_custody,
          asset_registry,
          bootstrap_custody_operation_id,
          collateral_id,
          asset_id,
          token,
          token_runtime_code_hash,
          token_decimals,
          true, // exactBalanceDelta
          borrower,
          quantity
        """,
        "Phase 9 atomic-refinance semantic boundary",
    )
    require_abi_encode_formula(
        reference,
        "custody_identity_hash",
        """
          "UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1",
          chainid,
          collateral_custody,
          asset_registry,
          bootstrap_custody_operation_id,
          collateral_id,
          asset_id,
          collateral_token,
          collateral_token_runtime_code_hash,
          collateral_token_decimals,
          true, // exactBalanceDelta
          borrower,
          quantity
        """,
        "Phase 9 refinance reference evidence",
    )

    require_abi_encode_formula(
        refinance_adr,
        "replayed_execution_event_id",
        """
          "UNIFIED_REFINANCE_EXECUTION_EVENT_V1",
          chainid,
          coordinator,
          refinance_id,
          stored_refinance.quoteId,
          supplied_operation_id,
          uint32(1),
          stored_terminal_result.recordedAt
        """,
        "Phase 9 atomic-refinance semantic boundary",
    )
    require_abi_encode_formula(
        reference,
        "replayed_execution_event_id",
        """
          "UNIFIED_REFINANCE_EXECUTION_EVENT_V1",
          chainid,
          refinance_coordinator,
          refinance_id,
          stored_refinance.quoteId,
          supplied_operation_id,
          uint32(1),
          stored_terminal_result.recordedAt
        """,
        "Phase 9 refinance reference evidence",
    )
    require_abi_encode_formula(
        reference,
        "borrower_cancel_replay_id",
        """
          "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
          chainid, refinance_coordinator, refinance_id, cancellation_prior_version,
          stored_refinance.expiresAt, uint8(1)
        """,
        "Phase 9 refinance reference evidence",
    )
    require_abi_encode_formula(
        reference,
        "expiry_cancel_replay_id",
        """
          "UNIFIED_REFINANCE_CANCEL_OPERATION_V1",
          chainid, refinance_coordinator, refinance_id, cancellation_prior_version,
          stored_refinance.expiresAt, uint8(2)
        """,
        "Phase 9 refinance reference evidence",
    )

    require_tokens(
        normalized(refinance_adr),
        (
            "requestRefinance` is the borrower's direct on-chain acceptance",
            "ACCEPTED --first successful funding commitment--> FUNDING_ESCROWED",
            "FUNDING_ESCROWED --additional partial funding--> FUNDING_ESCROWED",
            "FUNDING_ESCROWED --borrower cancellation or expiry before execution--> REFUNDABLE",
            "exact `newLoanNonce == refinanceNonce` checks",
            "it is not a separately stored counter",
            "CAPABILITY_PHASE9_REFINANCE_REQUEST = "
            'keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST")',
            "CAPABILITY_PHASE9_REFINANCE_FUNDING = "
            'keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING")',
            "After the local old-loan lock is acquired and before any "
            "resolver/bootstrap/quote effect, request acceptance calls `emergencyState` "
            "with the request capability",
            "Funding first classifies an existing commitment ID: exact replay returns inert "
            "and changed reuse conflicts without an emergency lookup. Only a first new "
            "commitment checks the funding capability",
            "Execute, cancel, expiry, and refund do not consult either capability",
            "authenticates `msg.sender` as the coordinator resolved from its immutable "
            "lien registry",
            "custody_identity_hash = keccak256(abi.encode( "
            '"UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1", chainid, '
            "collateral_custody, asset_registry, bootstrap_custody_operation_id, "
            "collateral_id",
            "reconstructs this identity from the operation ID and record/resolver facts",
            "Reuse of an operation ID with a changed record, or use of an alternate "
            "operation ID for an existing collateral record, conflicts",
            "Only `bootstrap_custody_operation_id` is carried by a frozen selector",
            "activation, tranche, position, and lien operation IDs are deterministic "
            "reference/evidence correlation hashes only",
            "must not pretend to receive, invert, store as processed, authorize with, or "
            "reject by those hashes",
            "newPrincipal == fundingAmount",
            "recognized escrow liability == escrowedUnits(refinanceId)",
            "An unsolicited surplus",
            "is excluded from refinance and ledger reconciliation",
            "Terminal execution replay classification occurs before every first-execution",
            "stored terminal result identifies the same refinance ID, has state `COMPLETED`",
            "The reconstructed ID must be nonzero",
            "reverts `RefinanceReplayConflict`",
            "cancellation_prior_version = stored_refinance.stateVersion - refunded_count - 1",
            "`CANCELLED` and `EXPIRED` require the canonical empty inventory",
            "`REFUNDABLE` and `REFUNDED` require length `1..32`",
            "whose `commitmentId` equals that vector ID, whose `refinanceId` equals the "
            "current refinance",
            "`NONE`, `CONSUMED`, or any other state conflicts",
            "count/version inconsistency, checked underflow",
            "stored `REFUNDABLE` or `REFUNDED` reconstructs both reason-1 and reason-2 "
            "candidate IDs",
            "never relies on `current stateVersion - 1` alone",
            "block.chainid == 31337",
            "It does not activate a successful Solidity business path",
            "Phase9ImplementationNotFrozen()",
        ),
        "Phase 9 atomic-refinance semantic boundary",
    )
    require_tokens(
        normalized(acceptance),
        (
            "new_position_manager",
            "with 0, 19, 20, 21, and 32 bytes",
            "Only exactly 20 bytes is structurally admissible",
            "Only the nonzero address equal to the factory-salt prediction",
            "Length, nonzero, prediction, and resolver equality checks occur before "
            "refinance-ID reconstruction",
            "attributed escrow reaches zero",
            "unrelated token surplus is excluded",
            "newPrincipal == fundingAmount",
            "Additional partial funding remains",
            "including operation-ID-bound custody identity and equal refinance/new-loan nonce",
            "only custody's passed operation ID is contract-authoritative while "
            "activation/tranche/position/lien operation hashes are correlation evidence",
            "Only the matching capability stops a new request or first commitment",
            "exact funding replay remains inert, changed reuse still conflicts",
            "neither pause can alter accepted facts, redirect value, sweep donations, or "
            "block execute/cancel/expiry/refund",
            "Coordinator recomputes the operation ID and custody binds it into identity",
            "exact same-operation/record replay is inert, changed/alternate reuse conflicts",
            "REFUNDABLE",
            "chain-31337",
            "synthetic-local",
            "No execution topology is selected",
            "No module may link or delegate again",
            "the non-accepted ADR-0027 15-CREATE graph and the existing ten- and "
            "twelve-CREATE plans and observations cannot be relabeled",
            "unchanged all-static 68-word/2,176-byte `ExecutionPlanV1`",
            "Every dispatch rehashes unchanged payload and plan bytes",
            "the existing prerequisite backlog rows, both refinance implementation rows, "
            "ADR 0027 semantic gates, a measured successor topology",
            "accepted specification, architecture, and topology controls alone activate nothing",
            "explicit nonce precondition, pairwise-distinct authorities, "
            "verification-before-grant order",
            "It does not authorize a successful Solidity refinance path",
            "provisional `EXECUTING` consumes no version/attempt and cannot terminal-replay",
            "one direct `FUNDING_ESCROWED -> COMPLETED` increment with attempt one",
            "begin-all, verify-all-pending, complete-all, verify-all-active",
            "all four leg hashes exist",
            "distinct recipients sorted by increasing `uint160`",
            "one exact `uint64(block.number)`",
            "Effect-free pre-payoff validation produces the exact payload and guard",
            "each fresh phase proof binds only non-action observations plus the exact "
            "20-word current `EXECUTING` context receipt",
            "The complete stored terminal tuple must match",
            "reconstructs a nonzero execution-event ID from the exact domain",
            "makes zero dependency calls, writes, transfers, counter changes, and logs",
            "cancellation_prior_version = stored_refinance.stateVersion - refunded_count - 1",
            "duplicate/over-cap IDs",
            "commitment ID or refinance identity",
            "`NONE`/`CONSUMED`/other commitment state",
            "prior-version underflow",
            "`CANCELLED`/`EXPIRED` require an empty commitment inventory",
            "`REFUNDABLE`/`REFUNDED` require `1..32` unique IDs",
            "only `FUNDED` or `REFUNDED`",
            "permits only reason 1 for `CANCELLED`, only reason 2 for `EXPIRED`",
            "Every inventory, identity, state, count, arithmetic, candidate, or operation "
            "mismatch reverts",
            "provisional `EXECUTING` emits none",
            "exact validation payload, 68-word plan, two-word proof",
            "consumed-quote component binding",
            "typed replacement hashes",
            "one captured `executed_at` is reused in event ID terminal hash and terminal storage",
            "zero/coordinator/settlement-token recipients fail before effects; all four leg "
            "hashes exist; each immediate recipient/coordinator delta is exact",
        ),
        "Phase 9 refinance acceptance semantics",
    )
    require_tokens(
        normalized(reference),
        (
            "new_position_manager",
            "exactly 20 bytes",
            "replacement new-loan nonce is not another stored counter",
            "it exactly equals the low-63-bit per-old-loan `refinance_nonce`",
            "CAPABILITY_PHASE9_REFINANCE_REQUEST = "
            'keccak256("CAPABILITY_PHASE9_REFINANCE_REQUEST")',
            "CAPABILITY_PHASE9_REFINANCE_FUNDING = "
            'keccak256("CAPABILITY_PHASE9_REFINANCE_FUNDING")',
            "custody authenticates that coordinator, reconstructs "
            "`CustodyRecord.identityHash` from the passed operation ID",
            "custody_identity_hash = keccak256(abi.encode( "
            '"UNIFIED_PHASE9_BOOTSTRAP_CUSTODY_IDENTITY_V1", chainid, '
            "collateral_custody, asset_registry, bootstrap_custody_operation_id, "
            "collateral_id",
            "Exact same-operation/same-record replay proves attributable "
            "custody/aggregate/lien state without another transfer",
            "changed-record or alternate-operation reuse conflicts",
            "Only `bootstrap_custody_operation_id` is passed through a frozen contract "
            "selector and acts as an on-chain replay/identity key",
            "activation, tranche, position, and lien operation IDs are deterministic "
            "model/event-correlation values only",
            "must not treat those correlation hashes as contract authority or processed storage",
            "attributed_escrow_*` is scoped to the refinance",
            "Unsolicited surplus is excluded from every liability",
            "fixed compiler-linked request `begin` dispatch",
            "before any resolver, token, registry, factory, quote-engine, provider, or other "
            "effect-capable dependency interaction",
            "consumed_quote_debt_state_version",
            "never from the old account's current post-payoff version",
            '"UNIFIED_REFINANCE_OLD_TRANCHE_EXECUTION_SNAPSHOT_V1"',
            '"UNIFIED_REFINANCE_OLD_POSITION_EXECUTION_SNAPSHOT_V1"',
            '"UNIFIED_REFINANCE_OLD_RIGHTS_EXECUTION_SNAPSHOT_V1"',
            '"UNIFIED_REFINANCE_PAYOUT_LEG_DELTA_V1"',
            "distinct payout_recipients sorted by increasing uint160",
            '"UNIFIED_REFINANCE_LIEN_PENDING_OBSERVATION_V1"',
            '"UNIFIED_REFINANCE_LIEN_ACTIVE_OBSERVATION_V1"',
            "begin-all, verify-all-pending, complete-all, then verify-all-active",
            "provisional `EXECUTING` consumes neither a version nor an execution attempt",
            "IPayoffQuoteEngineV2.PayoffComponentV2[] exact_quote_components",
            "recomputed_component_beneficiary_hash == consumed_quote.componentBeneficiaryHash",
            "recomputed_component_beneficiary_hash == accepted_record.componentBeneficiaryHash",
            "Phase9Types.DebtState replacement_debt",
            "bytes32 replacement_debt_hash = keccak256(abi.encode(replacement_debt))",
            "bytes32 replacement_tranches_hash = keccak256(abi.encode(replacement_tranches))",
            "bytes32 replacement_positions_hash = keccak256(abi.encode(replacement_positions))",
            "captures `executed_at = uint64(block.timestamp)` exactly once",
            "unequal to the settlement-token address before quote consumption or balance change",
            "exactly 68 static ABI words and 2,176 bytes",
            'execution_plan_domain = keccak256("UNIFIED_REFINANCE_EXECUTION_PLAN_V1")',
            "plan_suffix_hash = keccak256(raw 1920-byte execution_plan_bytes suffix at "
            "bytes 256..2175)",
            "len(execution_plan_bytes) = 2176",
            "replacement_debt_hash = keccak256(abi.encode(replacement_debt))",
            'keccak256("UNIFIED_REFINANCE_FUNDED_COMMITMENT_INVENTORY_V1")',
            "not a protocol event/result preimage and creates no new evidence preimage",
            "forwards identical bytes with no catch or intervening call or effect between "
            "a validator and consumer",
            "Exact replay returns from `prepareExecution` before any dependency read, "
            "returns empty context, and invokes none of the other five execution stages",
            "Execute replay validates the complete stored terminal tuple",
            "require stored_terminal_result.executionEventId != bytes32(0)",
            "require replayed_execution_event_id != bytes32(0)",
            "Cancel replay uses a bounded refunded-commitment count",
            "cancellation_prior_version = stored_refinance.stateVersion - refunded_count - 1",
            "`CANCELLED` and `EXPIRED` require the canonical empty inventory",
            "`REFUNDABLE` and `REFUNDED` require length `1..32`",
            "`commitmentId == vector_id`, `refinanceId == refinance_id`",
            "`NONE`, `CONSUMED`, or any other state conflicts",
            "count/version inconsistency, checked underflow",
            "processed cross-domain/other-refinance ID reverts `RefinanceReplayConflict`",
        ),
        "Phase 9 refinance reference evidence",
    )
    require_tokens(
        normalized(data_layouts),
        (
            "authenticates `msg.sender` as the coordinator resolved from that registry",
            "reconstructs the bootstrap-bound custody identity from the passed operation "
            "ID and canonical facts",
            "marks the operation processed, records `HELD`, and increases checked `total "
            "exact custody` before calling `transferFrom`",
            "Any transfer or delta failure rolls back those effects",
            "Exact same-operation/same-record replay validates record plus attributable "
            "holdings/aggregate without a second transfer",
            "changed-record reuse of that operation ID or an alternate operation ID for "
            "existing collateral conflicts",
        ),
        "Phase 9 refinance data-layout custody semantics",
    )
    require_tokens(
        normalized(deployment),
        (
            "chain ID is exactly `31337`",
            "disposable synthetic-local evidence only",
            "no future deployment topology is selected",
            "The non-accepted ADR 0027 measurement candidate",
            "unproven-candidate measurement evidence only",
            "module size is activation-grade",
            "A successor ADR must independently freeze and reproduce its library/call/"
            "CREATE order",
            "Production Solidity, the deployment script, plan schema, smoke harness, "
            "verifier fixtures, expected hashes, and current candidate files deliberately "
            "remain unchanged",
            "cannot satisfy a `P9R-DEPLOY-*` row",
            "module runtime self-patch offsets",
            "does not authorize a deployment",
            "change either backlog row from `TODO`",
            "ADR 0024 activation-grade extension",
            "that grant is the last activation-topology transaction",
            "insufficient to activate any method or checkpoint",
        ),
        "Phase 9 refinance deployment evidence",
    )

    refinance_proto = read(ROOT / "schemas/proto/unified/v1/refinance.proto")
    require(
        re.search(
            r"\bbytes\s+new_position_manager\s*=\s*24\s*;",
            refinance_proto,
        )
        is not None,
        "RefinanceRequest.new_position_manager must remain additive bytes field 24",
    )


def quote_preimage(text: str, label: str) -> tuple[str, ...]:
    match = re.search(
        r"quote_id\s*=\s*keccak256\s*\(\s*abi\.encode\s*\((?P<fields>.*?)\)\s*\)",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit(f"ERROR: {label} payoff quote preimage is not parseable")
    fields = tuple(field.strip() for field in match.group("fields").split(",") if field.strip())
    aliases = {
        "address(this)": "payoff_quote_engine",
        "interest": "accrued_interest",
    }
    return tuple(aliases.get(field, field) for field in fields)


def adr_quote_preimage(text: str) -> tuple[str, ...]:
    match = re.search(
        r"The quote preimage binds:\s*```text\s*(?P<fields>.*?)```",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit("ERROR: Phase 9 ADR payoff quote preimage is not parseable")
    aliases = {
        "payoff quote engine address": "payoff_quote_engine",
        "chain ID": "chainid",
        "loan ID": "loan_id",
        "loan account address": "loan_account",
        "quote policy hash": "policy_hash",
        "debt state version": "debt_state_version",
        "accrued interest": "accrued_interest",
        "canonical component-beneficiary vector": "component_beneficiary_hash",
        "net payoff amount": "net_payoff",
        "settlement asset ID": "settlement_asset_id",
        "settlement token address": "settlement_token",
        "settlement route hash": "settlement_route_hash",
        "issued at": "issued_at",
        "valid until": "valid_until",
        "quote nonce": "quote_nonce",
    }
    return tuple(
        aliases.get(field, field)
        for field in (line.strip() for line in match.group("fields").splitlines())
        if field
    )


def check_quote_preimage_order(adr: str, architecture: str, data_layouts: str) -> None:
    adr_fields = adr_quote_preimage(adr)
    architecture_fields = quote_preimage(architecture, "Phase 9 architecture")
    data_layout_fields = quote_preimage(data_layouts, "Phase 9 data layouts")
    require(
        adr_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 ADR payoff quote preimage ordering drifted",
    )
    require(
        architecture_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 architecture payoff quote preimage ordering drifted",
    )
    require(
        data_layout_fields == EXPECTED_QUOTE_PREIMAGE,
        "Phase 9 data-layout payoff quote preimage ordering drifted",
    )


def check_workstream_ownership() -> None:
    workstreams = read(WORKSTREAMS_PATH)
    protocol = section(workstreams, "WS-PROTOCOL")
    ledger = section(workstreams, "WS-LEDGER")
    risk = section(workstreams, "WS-RISK")

    require_tokens(
        protocol,
        (
            "payoff",
            "refinance",
            "lien-handoff",
            "restructuring",
            "funded-protection",
            "guarantee",
            "write-off",
            "subrogation",
            "recovery",
        ),
        "WS-PROTOCOL Phase 9 ownership",
    )
    require_tokens(
        ledger,
        ("Phase 9", "resolution", "protection", "loss", "recovery", "solvency", "reconciliation"),
        "WS-LEDGER Phase 9 ownership",
    )
    require_tokens(
        risk,
        ("payoff-component", "reserve stress haircuts", "modeled-loss"),
        "WS-RISK Phase 9 ownership",
    )

    headings = set(re.findall(r"^##\s+(WS-[A-Z0-9-]+)\b", workstreams, re.MULTILINE))
    with BACKLOG_PATH.open(encoding="utf-8", newline="") as handle:
        referenced = {row["workstream"] for row in csv.DictReader(handle)}
    require(
        referenced <= headings,
        "Phase 9 backlog references undefined workstreams: "
        + ", ".join(sorted(referenced - headings)),
    )


def check_production_prohibitions() -> None:
    adr = normalized(read(ADR_PATH))
    architecture = normalized(read(ARCHITECTURE_PATH))

    require_tokens(
        adr,
        (
            "real reserves",
            "insurance promises",
            "guarantees",
            "legal",
            "production providers",
            "public testnet",
            "mainnet",
            "production keys",
            "hsm/kms",
            "real uft",
            "real fund",
            "cross-chain lien transfer",
            "administrator rescue",
            "arbitrary reserve withdrawal",
            "production solvency",
        ),
        "Phase 9 ADR production prohibitions",
    )
    require_tokens(
        architecture,
        (
            "reject non-loopback providers",
            "containing real value",
            "no real reserve",
            "production credential",
            "public network",
            "actuarial",
            "capital measure",
            "phase 10 cannot treat this milestone as authority",
        ),
        "Phase 9 architecture production boundary",
    )


def check_no_stale_phase17_recovery() -> None:
    suffixes = {".md", ".csv", ".yaml", ".yml"}
    stale: list[str] = []
    for base in (ROOT / "adr", ROOT / "docs", ROOT / "security"):
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in suffixes:
                continue
            for number, line in enumerate(read(path).splitlines(), start=1):
                if re.search(r"\bphase\s+17\b", line, flags=re.IGNORECASE):
                    stale.append(f"{path.relative_to(ROOT)}:{number}")
    require(
        not stale,
        "stale Phase 17 recovery wording remains at " + ", ".join(stale),
    )


def check_boundary_evidence() -> None:
    master = read(MASTER_PLAN_PATH)
    architecture = read(ARCHITECTURE_PATH)
    data_layouts = read(DATA_LAYOUTS_PATH)
    adr = read(ADR_PATH)
    phase8_exit = read(PHASE8_EXIT_PATH)
    foundation_check = read(FOUNDATION_CHECK_PATH)

    require_tokens(
        normalized(master),
        (
            "Phase 9 — Refinancing, Restructuring, Insurance, and Recovery",
            "WP-9.1 — Payoff quote engine",
            "WP-9.2 — Refinance coordinator",
            "WP-9.3 — Restructuring controller",
            "WP-9.4 — Insurance manager",
            "WP-9.5 — Recovery manager",
            "Refinancing never creates duplicate senior liens",
            "Failed refinancing returns to a safe state",
            "Restructuring preserves required consent",
            "Insurance claims cannot exceed coverage",
            "Losses and recoveries are not double-counted",
            "Reserve solvency metrics are available",
        ),
        "Phase 9 master-plan evidence",
    )
    require_tokens(
        normalized(adr),
        (
            "Status: accepted for synthetic local engineering",
            "chain ID `31337`",
            "UNI-RESIDUAL-003",
            "UNI-RESIDUAL-004",
            "RISK-PHASE9-001",
            "RISK-PHASE9-015",
            "ASM-034",
            "ASM-044",
            "exact release evidence",
            "one-command reset",
            "post-reset absence",
            "crash/restart",
            "separate exit-review PR",
            "exact typed Phase 9 contract ABI",
            "storage-layout",
            "compilation-root",
            "deterministic snapshot",
            "Phase9LocalSyntheticToken",
            "deployed only on Anvil",
            "is included in",
            "removed with all Phase 9 state by reset",
        ),
        "Phase 9 ADR boundary evidence",
    )
    require_tokens(
        normalized(architecture),
        (
            "9A — Boundary, schemas, and models",
            "9B — Payoff and refinance",
            "9C — Restructuring and consent",
            "9D — Funded protection",
            "9E — Loss and recovery",
            "9F — Simulations, release, and review",
            "restart",
            "reconciliation",
            "release-evidence",
            "post-reset",
            "INV-ACC-001",
            "INV-ACC-007",
            "INV-AUTH-001",
            "INV-AUTH-009",
            "INV-LOAN-001",
            "INV-LOAN-015",
            "INV-FUND-001",
            "INV-FUND-011",
            "INV-INT-001",
            "INV-INT-012",
            "INV-COL-001",
            "INV-COL-012",
            "INV-LIQ-005",
            "INV-LIQ-012",
            "INV-REFI-001",
            "INV-REFI-008",
            "INV-INS-001",
            "INV-INS-009",
            "REC-001",
            "REC-008",
            "LIVE-REFI-001",
            "ProtocolCompilation.sol",
            "imports every Phase 9 contract",
            "scripts/check-foundation.ps1",
            "formats",
            "src/interfaces/phase9",
            "src/resolution",
            "src/protection",
            "src/recovery",
            "tests, and scripts",
            "tools/check_abi.py",
            "explicit compiled/snapshot pairs",
            "protocol/storage-layout/phase9/<Contract>.storage.json",
            "A dedicated checker compares",
            "ABI and storage checkers run from",
            "Phase9LocalSyntheticToken",
            "Golden vectors prove the exact quote preimage order",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "neutral fixture labels only",
            "currency denomination",
            "USD or other fiat peg",
            "redemption",
            "backing",
            "exchange rate",
            "market value",
            "payment claim",
            "legal tender status",
            "provider obligation",
            "Contract-size checking sees every deployable Phase 9 runtime",
        ),
        "Phase 9 architecture acceptance evidence",
    )
    require_tokens(
        normalized(data_layouts),
        (
            "eligible risk-adjusted reserve assets",
            "= floor(",
            "/ 10_000",
            "0 <= stress_haircut_basis_points <= 10_000",
            "modeled_loss_at_target_confidence > 0",
            "canonical pre-claim: floor(64 * 10_000 / 10_000) = 64",
            "claim-specific payment liquidity",
            "beneficiary covered unresolved entitlement",
            "prohibits partial claim transfers",
            "1570 Segregated Product Reserve Asset",
            "each of the 45 fully qualified table names",
            "exact row count",
            "deterministic ordered",
            "content hash",
            "aggregate Phase 9 SQL state hash",
            "capture compiler storage-layout artifacts",
            "fail ABI/storage checks",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "neutral fixture labels",
            "currency denomination",
            "fiat or USD peg",
            "redemption",
            "backing",
            "exchange rate",
            "market value",
            "payment claim",
            "legal tender status",
            "provider obligation",
        ),
        "Phase 9 numerical, claim, reserve, and release boundary evidence",
    )
    require_tokens(
        "\n".join((adr, architecture, data_layouts)),
        (*PROTO_FILENAMES, RELEASE_MANIFEST_PATH),
        "Phase 9 additive interface and release-manifest declarations",
    )
    require_tokens(
        normalized(phase8_exit),
        (
            "Cancellation authorization expiry and reissue",
            "Authenticated collateral absence and terminalization",
            "Production use requires",
        ),
        "Phase 8 residual carry-forward evidence",
    )
    require(
        "tools/check_phase9.py" in foundation_check.replace("\\", "/"),
        "foundation check does not invoke the Phase 9 checker",
    )
    check_quote_preimage_order(adr, architecture, data_layouts)
    check_refinance_boundary_evidence()

    with INVARIANT_CATALOG_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    catalog_ids = [row["id"] for row in rows]
    require(
        len(catalog_ids) == len(set(catalog_ids)),
        "invariant catalog contains duplicate IDs",
    )
    require(
        REQUIRED_INVARIANTS <= set(catalog_ids),
        "Phase 9 invariant catalog evidence is incomplete: "
        + ", ".join(sorted(REQUIRED_INVARIANTS - set(catalog_ids))),
    )


def register_blocks(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^\s*-\s+id:\s+([A-Z0-9-]+)\s*$", text, re.MULTILINE))
    blocks: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        identifier = match.group(1)
        require(identifier not in blocks, f"register entry {identifier} is duplicated")
        blocks[identifier] = text[match.start() : end]
    return blocks


def field_value(block: str, field: str) -> str:
    match = re.search(rf"^\s+{re.escape(field)}:\s*(.+?)\s*$", block, re.MULTILINE)
    return match.group(1).strip().strip("\"'") if match else ""


def check_register_entry(
    identifier: str,
    block: str,
    *,
    risk: bool,
) -> None:
    for field in REGISTER_FIELDS:
        require(field_value(block, field) != "", f"{identifier} lacks {field}")
    require(
        field_value(block, "owner") in AUTHORITY_OWNERS,
        f"{identifier} has an unknown owner",
    )
    require(
        re.fullmatch(r"\d{4}-\d{2}-\d{2}", field_value(block, "expiry")) is not None,
        f"{identifier} expiry is not an ISO date",
    )
    evidence = field_value(block, "evidence")
    if "://" not in evidence:
        require(
            (ROOT / evidence).exists(),
            f"{identifier} evidence path does not exist: {evidence}",
        )
    if risk:
        require(
            field_value(block, "severity") in {"CRITICAL", "EXISTENTIAL"},
            f"{identifier} must be CRITICAL or EXISTENTIAL",
        )
        require(field_value(block, "title") != "", f"{identifier} lacks title")
        require(
            field_value(block, "status") == "CONTROLLED_LOCAL_ONLY",
            f"{identifier} is not CONTROLLED_LOCAL_ONLY",
        )


def check_implementation_registers() -> None:
    risk_blocks = register_blocks(read(ROOT / "security/risk-register.yaml"))
    assumption_blocks = register_blocks(read(ROOT / "security/assumption-register.yaml"))

    phase9_risks = {
        identifier for identifier in risk_blocks if identifier.startswith("RISK-PHASE9-")
    }
    require(phase9_risks == REQUIRED_RISKS, "Phase 9 implementation risk register drifted")
    missing_assumptions = REQUIRED_ASSUMPTIONS - set(assumption_blocks)
    require(
        not missing_assumptions,
        "Phase 9 implementation assumption register is incomplete: "
        + ", ".join(sorted(missing_assumptions)),
    )

    for identifier in sorted(REQUIRED_RISKS):
        check_register_entry(identifier, risk_blocks[identifier], risk=True)
    for identifier in sorted(REQUIRED_ASSUMPTIONS):
        check_register_entry(identifier, assumption_blocks[identifier], risk=False)


def combined_text(paths: Iterable[Path]) -> str:
    return "\n".join(read(path) for path in paths)


def strip_solidity_comments(text: str) -> str:
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.DOTALL)


def protocol_compilation_imports() -> dict[str, Path]:
    require_paths((PROTOCOL_COMPILATION_PATH,), "protocol compilation root")
    imports: dict[str, Path] = {}
    for match in re.finditer(
        r'import\s*\{(?P<symbols>[^}]+)\}\s*from\s*"(?P<path>[^"]+)"\s*;',
        read(PROTOCOL_COMPILATION_PATH),
        flags=re.DOTALL,
    ):
        source_path = (PROTOCOL_COMPILATION_PATH.parent / match.group("path")).resolve()
        for declaration in match.group("symbols").split(","):
            contract = declaration.strip().split()[0]
            require(contract not in imports, f"duplicate compilation import for {contract}")
            imports[contract] = source_path
    return imports


def is_phase9_source_path(path: Path) -> bool:
    try:
        relative = path.relative_to(ROOT / "protocol/src")
    except ValueError:
        return True
    return (
        relative.parts[0].lower() in {"resolution", "protection", "recovery"}
        or (
            len(relative.parts) >= 2
            and relative.parts[0].lower() == "interfaces"
            and relative.parts[1].lower() == "phase9"
        )
        or "phase9" in relative.stem.lower()
    )


def phase9_candidate_source_files() -> list[Path]:
    return sorted(
        path.resolve()
        for path in (ROOT / "protocol/src").rglob("*.sol")
        if is_phase9_source_path(path.resolve())
    )


def phase9_source_declarations() -> dict[str, list[Path]]:
    declarations: dict[str, list[Path]] = {}
    for path in (ROOT / "protocol/src").rglob("*.sol"):
        source = strip_solidity_comments(read(path))
        contracts = [
            match.group("contract")
            for match in re.finditer(
                r"\b(?P<abstract>abstract\s+)?contract\s+(?P<contract>[A-Za-z_]\w*)",
                source,
            )
            if match.group("abstract") is None
        ]
        if not contracts:
            continue
        if is_phase9_source_path(path) or set(contracts) & set(PHASE9_CONTRACTS):
            for contract in contracts:
                declarations.setdefault(contract, []).append(path.resolve())
    return declarations


def phase9_freeze_started() -> bool:
    imports = protocol_compilation_imports()
    has_phase9_import = any(
        contract in PHASE9_CONTRACTS or is_phase9_source_path(source_path)
        for contract, source_path in imports.items()
    )
    return (
        has_phase9_import
        or bool(phase9_candidate_source_files())
        or bool(phase9_source_declarations())
    )


def phase9_compilation_imports() -> dict[str, Path]:
    imports = protocol_compilation_imports()
    declarations = phase9_source_declarations()
    expected_contracts = set(PHASE9_CONTRACTS)
    actual_contracts = set(declarations)
    require(
        actual_contracts == expected_contracts,
        "Phase 9 production source set drifted; missing="
        + ",".join(sorted(expected_contracts - actual_contracts))
        + "; unexpected="
        + ",".join(sorted(actual_contracts - expected_contracts)),
    )
    duplicate_sources = sorted(
        contract for contract, paths in declarations.items() if len(paths) != 1
    )
    require(
        not duplicate_sources,
        "Phase 9 contracts have duplicate source declarations: " + ", ".join(duplicate_sources),
    )

    phase9_imports = {
        contract: source_path
        for contract, source_path in imports.items()
        if contract in expected_contracts or is_phase9_source_path(source_path)
    }
    missing = sorted(expected_contracts - set(phase9_imports))
    unexpected = sorted(set(phase9_imports) - expected_contracts)
    require(
        not missing and not unexpected,
        "ProtocolCompilation.sol Phase 9 import set drifted; missing="
        + ",".join(missing)
        + "; unexpected="
        + ",".join(unexpected),
    )
    for contract in PHASE9_CONTRACTS:
        source_path = phase9_imports[contract]
        require(source_path.is_file(), f"Phase 9 source import is missing for {contract}")
        try:
            source_path.relative_to(ROOT / "protocol/src")
        except ValueError:
            require(False, f"Phase 9 source import escapes protocol/src: {contract}")
        require(
            declarations[contract] == [source_path],
            f"{contract} compilation import does not match its unique source declaration",
        )
    return phase9_imports


def check_phase9_abi_pairs(imports: dict[str, Path]) -> None:
    phase9_pairs = {
        contract: pair for contract, pair in ABI_PAIRS.items() if pair[1].parent == PHASE9_ABI_PATH
    }
    expected_contracts = set(PHASE9_CONTRACTS)
    actual_contracts = set(phase9_pairs)
    require(
        actual_contracts == expected_contracts,
        "tools/check_abi.py Phase 9 pair set drifted; missing="
        + ",".join(sorted(expected_contracts - actual_contracts))
        + "; unexpected="
        + ",".join(sorted(actual_contracts - expected_contracts)),
    )

    for contract in PHASE9_CONTRACTS:
        compiled_path, baseline_path = phase9_pairs[contract]
        source_stem = (
            imports[contract].relative_to(ROOT).with_suffix("").as_posix().replace("/", "_")
        )
        expected_compiled_path = ROOT / ".cache/solc" / f"{source_stem}_sol_{contract}.abi"
        expected_baseline_path = PHASE9_ABI_PATH / f"{contract}.abi.json"
        require(
            compiled_path == expected_compiled_path,
            f"{contract} compiled ABI pair does not match its compilation import",
        )
        require(
            baseline_path == expected_baseline_path,
            f"{contract} ABI pair does not use its exact Phase 9 snapshot",
        )
        require_paths((baseline_path,), f"{contract} reviewed ABI snapshot")


def check_phase9_storage_layouts() -> None:
    require_paths((PHASE9_STORAGE_CHECK_PATH,), "Phase 9 storage-layout checker")
    expected_snapshots = {
        PHASE9_STORAGE_PATH / f"{contract}.storage.json" for contract in PHASE9_CONTRACTS
    }
    require_paths(expected_snapshots, "Phase 9 storage-layout snapshots")
    for snapshot_path in sorted(expected_snapshots):
        snapshot = json.loads(read(snapshot_path))
        require(
            isinstance(snapshot, dict) and bool(snapshot),
            f"Phase 9 storage-layout snapshot is empty: {snapshot_path.name}",
        )

    checker = read(PHASE9_STORAGE_CHECK_PATH)
    require_tokens(
        checker,
        (
            "protocol/storage-layout/phase9",
            "storageLayout",
            "compiler",
            "settings",
            "linearized",
            "slot",
            "offset",
            "encoding",
            "sort_keys",
            *PHASE9_CONTRACTS,
        ),
        "Phase 9 deterministic storage-layout checker",
    )
    require(
        re.search(r"sort_keys\s*=\s*True", checker) is not None,
        "Phase 9 storage-layout checker does not canonicalize snapshot key order",
    )
    foundation_check = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        "tools/check_phase9_storage_layouts.py" in foundation_check,
        "foundation check does not invoke the Phase 9 storage-layout checker",
    )


def check_phase9_formatting_scope(imports: dict[str, Path]) -> None:
    foundation_check = read(FOUNDATION_CHECK_PATH)
    match = re.search(
        r"forge\s+fmt\s+--check(?P<scope>.*?)(?=\n\s*forge\s+test\b)",
        foundation_check,
        flags=re.DOTALL,
    )
    if match is None:
        raise SystemExit("ERROR: foundation Solidity formatting command is not parseable")
    scopes = {token.replace("\\", "/") for token in match.group("scope").replace("`", " ").split()}
    phase9_sources = set(imports.values()) | set(phase9_candidate_source_files())
    uncovered: list[str] = []
    for source_path in sorted(phase9_sources):
        relative_source = source_path.relative_to(ROOT / "protocol").as_posix()
        if not any(
            relative_source == scope or relative_source.startswith(scope.rstrip("/") + "/")
            for scope in scopes
        ):
            uncovered.append(relative_source)
    require(
        not uncovered,
        "Solidity formatting scope excludes Phase 9 sources: " + ", ".join(uncovered),
    )


def check_phase9_contract_size_coverage() -> None:
    require_paths((CONTRACT_SIZE_CHECK_PATH,), "contract-size checker")
    checker = read(CONTRACT_SIZE_CHECK_PATH)
    require_tokens(
        checker,
        ("protocol", "out", "*.json", "deployedBytecode", "24_576"),
        "generic production contract-size checker",
    )
    excluded_match = re.search(
        r"NON_PRODUCTION\s*=\s*\{(?P<contracts>.*?)\}",
        checker,
        flags=re.DOTALL,
    )
    if excluded_match is None:
        raise SystemExit("ERROR: contract-size exclusion set is not parseable")
    excluded = set(re.findall(r'["\']([A-Za-z_]\w*)["\']', excluded_match.group("contracts")))
    wrongly_excluded = sorted(set(PHASE9_CONTRACTS) & excluded)
    require(
        not wrongly_excluded,
        "Phase 9 deployable contracts are excluded from size checking: "
        + ", ".join(wrongly_excluded),
    )
    foundation_check = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        "scripts/check-contract-sizes.py" in foundation_check,
        "foundation check does not invoke production contract-size checking",
    )


def check_phase9_local_token_source(imports: dict[str, Path]) -> None:
    token_source = strip_solidity_comments(read(imports["Phase9LocalSyntheticToken"]))
    require_tokens(
        token_source,
        (
            "contract Phase9LocalSyntheticToken",
            "ERC20",
            "Unified Phase 9 Local Synthetic Unit",
            "P9UNIT",
            "FIXED_SUPPLY_UNITS",
            "1_000_000_000_000_000",
            "InvalidLocalChain",
            "InvalidFixtureAllocator",
        ),
        "Phase 9 local synthetic token implementation",
    )
    inheritance_match = re.search(
        r"contract\s+Phase9LocalSyntheticToken\s+is\s+(?P<bases>[^\{]+)\{",
        token_source,
    )
    if inheritance_match is None:
        raise SystemExit("ERROR: Phase9LocalSyntheticToken inheritance is not parseable")
    bases = {base.strip() for base in inheritance_match.group("bases").split(",")}
    require(
        "ERC20" in bases and bases <= {"ERC20", "IPhase9LocalSyntheticToken"},
        "Phase9LocalSyntheticToken has prohibited inheritance: " + ", ".join(sorted(bases)),
    )
    require(
        re.search(r"constructor\s*\(\s*address\s+fixtureAllocator\s*\)", token_source) is not None,
        "Phase9LocalSyntheticToken constructor signature drifted",
    )
    require(
        re.search(
            r'ERC20\s*\(\s*"Unified Phase 9 Local Synthetic Unit"\s*,\s*"P9UNIT"\s*\)',
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken metadata is not the neutral frozen fixture metadata",
    )
    require(
        re.search(
            r"uint256\s+public\s+constant\s+(?:override\s+)?"
            r"FIXED_SUPPLY_UNITS\s*=\s*"
            r"1_000_000_000_000_000\s*;",
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken fixed supply declaration drifted",
    )
    require(
        re.search(r"block\.chainid\s*!=\s*31337", token_source) is not None,
        "Phase9LocalSyntheticToken does not reject non-local chains",
    )
    require(
        re.search(r"fixtureAllocator\s*==\s*address\s*\(\s*0\s*\)", token_source) is not None,
        "Phase9LocalSyntheticToken does not reject the zero fixture allocator",
    )
    decimals_match = re.search(
        r"function\s+decimals\s*\(\s*\)\s+public\s+(?:pure|view)\s+override"
        r"(?:\s*\([^)]*\))?\s+"
        r"returns\s*\(\s*uint8\s*\)\s*\{\s*return\s+6\s*;\s*\}",
        token_source,
    )
    require(decimals_match is not None, "Phase9LocalSyntheticToken decimals drifted")
    require(
        token_source.count("_mint(") == 1
        and re.search(
            r"_mint\s*\(\s*fixtureAllocator\s*,\s*FIXED_SUPPLY_UNITS\s*\)",
            token_source,
        )
        is not None,
        "Phase9LocalSyntheticToken must mint the fixed supply exactly once",
    )
    require(
        token_source.lower().count("mint") == 1
        and "burn" not in token_source.lower()
        and "role" not in token_source.lower(),
        "Phase9LocalSyntheticToken exposes mint, burn, or role semantics",
    )
    exposed_functions = set(
        re.findall(
            r"function\s+([A-Za-z_]\w*)\s*\([^)]*\)[^{;]*(?:public|external)",
            token_source,
        )
    )
    require(
        exposed_functions == {"decimals"},
        "Phase9LocalSyntheticToken exposes unexpected functions: "
        + ", ".join(sorted(exposed_functions - {"decimals"})),
    )
    require(
        token_source.count("constructor") == 1
        and len(re.findall(r"\bpublic\b", token_source)) == 2
        and re.search(r"\bexternal\b", token_source) is None,
        "Phase9LocalSyntheticToken exposes state or behavior beyond the frozen ABI",
    )
    prohibited_code = (
        "Phase8LocalSyntheticToken",
        "WrappedUFT",
        "UnifiedToken",
        "AccessControl",
        "Ownable",
        "Pausable",
        "ERC20Burnable",
        "ERC20Permit",
        "UUPS",
        "_burn(",
        "admin",
        "owner",
        "operator",
        "USD",
        "fiat",
        "peg",
        "redeem",
        "backing",
        "exchangeRate",
        "marketValue",
        "paymentClaim",
        "legalTender",
        "providerObligation",
    )
    present = [token for token in prohibited_code if token.lower() in token_source.lower()]
    compact_code = re.sub(r"[^a-z0-9]", "", token_source.lower())
    prohibited_value_semantics = (
        "denomination",
        "fiat",
        "usdpeg",
        "redemption",
        "backing",
        "exchangerate",
        "marketvalue",
        "paymentclaim",
        "legaltender",
        "providerobligation",
    )
    present.extend(
        token
        for token in prohibited_value_semantics
        if token in compact_code and token not in present
    )
    require(
        not present,
        "Phase9LocalSyntheticToken contains prohibited authority or value semantics: "
        + ", ".join(present),
    )


def solidity_function_bodies(source: str) -> list[tuple[str, str]]:
    functions: list[tuple[str, str]] = []
    for match in re.finditer(r"\bfunction\b(?P<header>[^;{]+)\{", source, re.DOTALL):
        depth = 1
        cursor = match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
            cursor += 1
        require(depth == 0, "Phase 9 Solidity function body is not parseable")
        functions.append((match.group("header"), source[match.end() : cursor - 1]))
    return functions


def solidity_definition_bodies(source: str) -> list[tuple[str, str, str]]:
    """Return top-level contract/library bodies for owner-scoped ABI inspection."""

    definitions: list[tuple[str, str, str]] = []
    pattern = re.compile(
        r"\b(?P<kind>contract|library)\s+(?P<name>[A-Za-z_]\w*)[^;{]*\{",
        re.DOTALL,
    )
    for match in pattern.finditer(source):
        depth = 1
        cursor = match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
            cursor += 1
        require(depth == 0, "Phase 9 Solidity definition body is not parseable")
        definitions.append(
            (
                match.group("kind"),
                match.group("name"),
                source[match.end() : cursor - 1],
            )
        )
    return definitions


def is_exact_freeze_revert(body: str) -> bool:
    return (
        re.fullmatch(
            rf"\s*revert\s+{PHASE9_FREEZE_ERROR}\s*\(\s*\)\s*;\s*",
            body,
        )
        is not None
    )


def check_implemented_freeze_abi_compatibility(contract: str, source: str) -> None:
    """Allow the frozen error ABI entry without leaving a callable freeze path."""
    if PHASE9_FREEZE_ERROR not in source:
        require(
            PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER not in source,
            f"{contract} retains the freeze ABI marker without the frozen error",
        )
        return

    exact_import = re.compile(
        rf"import\s*\{{\s*{PHASE9_FREEZE_ERROR}\s*\}}\s*from\s*"
        r'"\.\./interfaces/phase9/Phase9Errors\.sol"\s*;'
    )
    require(
        len(exact_import.findall(source)) == 1,
        f"{contract} freeze ABI compatibility import is not exact",
    )

    marker_functions: list[tuple[str, str]] = []
    other_functions: list[tuple[str, str]] = []
    for header, body in solidity_function_bodies(source):
        function_name = re.match(r"\s*([A-Za-z_]\w*)", header)
        name = function_name.group(1) if function_name else "<unknown>"
        if name == PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER:
            marker_functions.append((header, body))
        else:
            other_functions.append((header, body))

    require(
        len(marker_functions) == 1,
        f"{contract} must contain exactly one named freeze ABI compatibility marker",
    )
    marker_header, marker_body = marker_functions[0]
    require(
        re.fullmatch(
            rf"\s*{PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER}\s*\(\s*\)\s+private\s+pure\s*",
            marker_header,
        )
        is not None,
        f"{contract} freeze ABI compatibility marker must be exactly private pure",
    )
    require(
        is_exact_freeze_revert(marker_body),
        f"{contract} freeze ABI compatibility marker body is not exact",
    )

    impossible_guard = re.compile(
        rf"if\s*\(\s*msg\.data\.length\s*==\s*0\s*\)\s*"
        rf"{PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER}\s*\(\s*\)\s*;"
    )
    guard_count = 0
    for header, body in other_functions:
        body_without_guards, count = impossible_guard.subn("", body)
        if count:
            header_words = set(re.findall(r"[A-Za-z_]\w*", header))
            require(
                bool({"public", "external"} & header_words)
                and not bool({"view", "pure"} & header_words),
                f"{contract} freeze ABI compatibility guard is outside a mutating ABI entrypoint",
            )
            guard_count += count
        require(
            PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER not in body_without_guards,
            f"{contract} contains a reachable freeze ABI marker path",
        )
        require(
            PHASE9_FREEZE_ERROR not in body_without_guards,
            f"{contract} retains fail-closed freeze behavior after activation",
        )

    require(
        guard_count == 1,
        f"{contract} must contain exactly one unreachable freeze ABI compatibility guard",
    )
    require(
        len(re.findall(rf"\b{PHASE9_FREEZE_ERROR}\b", source)) == 2,
        f"{contract} contains a freeze error use outside the exact ABI compatibility marker",
    )
    require(
        len(re.findall(rf"\b{PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER}\b", source)) == 2,
        f"{contract} contains a freeze ABI marker use outside the exact unreachable guard",
    )


def activated_function_names(
    contract: str,
    mutator_names: set[str],
    activation: set[str] | dict[str, frozenset[str]] | None,
) -> set[str]:
    if activation is None:
        return set()
    if isinstance(activation, set):
        return set(mutator_names) if contract in activation else set()

    signatures = activation.get(contract, frozenset())
    names: list[str] = []
    for signature in signatures:
        require(
            re.fullmatch(r"[A-Za-z_]\w*\(.*\)", signature) is not None,
            f"{contract} has a malformed activated signature: {signature}",
        )
        names.append(signature.partition("(")[0])
    require(
        len(names) == len(set(names)),
        f"{contract} has overloaded activated mutators that require AST-level disambiguation",
    )
    activated_names = set(names)
    require(
        activated_names <= mutator_names,
        f"{contract} checkpoint activates unknown mutators: "
        + ", ".join(sorted(activated_names - mutator_names)),
    )
    return activated_names


def phase9_public_mutators(source: str, contract: str | None = None) -> list[tuple[str, str]]:
    scope = source
    if contract is not None:
        # The compiler-AST linked-module gate proves the exact public library signatures
        # and the one-to-one lifecycle wrapper call graph. This ABI freeze pass must inspect
        # only the named contract definition; otherwise an exact public library/wrapper pair
        # is misclassified as a Solidity overload.
        owned_definitions = [
            body
            for kind, name, body in solidity_definition_bodies(source)
            if kind == "contract" and name == contract
        ]
        require(
            len(owned_definitions) == 1,
            f"{contract} contract definition inventory drifted",
        )
        scope = owned_definitions[0]

    mutators: list[tuple[str, str]] = []
    for header, body in solidity_function_bodies(scope):
        header_words = set(re.findall(r"[A-Za-z_]\w*", header))
        if not ({"public", "external"} & header_words) or {"view", "pure"} & header_words:
            continue
        function_name = re.match(r"\s*([A-Za-z_]\w*)", header)
        if function_name is None:
            raise SystemExit("ERROR: Phase 9 mutating function name is not parseable")
        mutators.append((function_name.group(1), body))
    names = [name for name, _body in mutators]
    require(
        len(names) == len(set(names)),
        "Phase 9 overloaded mutators require AST-level signature matching",
    )
    return mutators


def check_phase9_stub_sources(
    imports: dict[str, Path],
    implemented: set[str] | dict[str, frozenset[str]] | None = None,
) -> None:
    forbidden = ("delegatecall", "selfdestruct", "Phase8")
    for contract in PHASE9_PRODUCTION_CONTRACTS:
        source = strip_solidity_comments(read(imports[contract]))
        require_tokens(source, (f"contract {contract}",), f"{contract} Phase 9 source")
        linked_candidate = contract == "RefinanceCoordinator" and (
            "assembly" in source.lower()
            or any(marker in source for marker in REFINANCE_LINKED_MODULE_MARKERS)
        )
        if linked_candidate:
            require(
                all(marker in source for marker in REFINANCE_LINKED_MODULE_MARKERS),
                "RefinanceCoordinator has an incomplete ADR 0023 fixed-module candidate",
            )
            try:
                check_refinance_linked_modules()
            except LinkedModuleCheckError as error:
                raise SystemExit(
                    "RefinanceCoordinator ADR 0023 linked-module check failed: " + str(error)
                ) from error
        mutators = phase9_public_mutators(source, contract)
        mutator_names = {name for name, _body in mutators}
        activated_names = activated_function_names(contract, mutator_names, implemented)
        fully_activated = bool(mutator_names) and activated_names == mutator_names
        if not activated_names:
            require_tokens(
                source,
                (PHASE9_FREEZE_ERROR,),
                f"{contract} freeze stub",
            )
        elif fully_activated:
            check_implemented_freeze_abi_compatibility(contract, source)
        source_forbidden = forbidden if linked_candidate else (*forbidden, "assembly")
        present = [token for token in source_forbidden if token.lower() in source.lower()]
        require(
            not present,
            f"{contract} contains prohibited freeze-stub mechanisms: {', '.join(present)}",
        )
        require(
            re.search(r"\b(?:fallback|receive)\s*\(", source) is None,
            f"{contract} exposes a fallback or receive function",
        )
        for label, body in mutators:
            if label in activated_names:
                require(
                    not is_exact_freeze_revert(body),
                    f"{contract}.{label} retains exact freeze behavior after activation",
                )
                if not fully_activated:
                    require(
                        PHASE9_FREEZE_ERROR not in body
                        and PHASE9_FREEZE_ABI_COMPATIBILITY_MARKER not in body,
                        f"{contract}.{label} retains a reachable freeze path after activation",
                    )
            else:
                require(
                    is_exact_freeze_revert(body),
                    f"{contract}.{label} has a successful or non-canonical mutating stub path",
                )


def check_phase9_foundry_warning_policy(
    imports: dict[str, Path],
    config: dict[str, object] | None = None,
    implemented: set[str] | dict[str, frozenset[str]] | None = None,
) -> None:
    if config is None:
        with FOUNDRY_CONFIG_PATH.open("rb") as handle:
            config = cast(dict[str, object], tomllib.load(handle))

    profile = config.get("profile")
    require(isinstance(profile, dict), "Foundry config has no profile table")
    profile_table = cast(dict[str, object], profile)
    default = profile_table.get("default")
    require(isinstance(default, dict), "Foundry config has no default profile")
    default_table = cast(dict[str, object], default)

    require(
        default_table.get("deny") == "warnings",
        "Foundry must continue to deny all non-exempt compiler warnings",
    )
    global_codes = default_table.get("ignored_error_codes", [])
    require(isinstance(global_codes, list), "Foundry global warning policy is malformed")
    global_code_list = cast(list[object], global_codes)
    normalized_global_codes = {str(code).strip().lower() for code in global_code_list}
    require(
        not normalized_global_codes.intersection({"2018", "func-mutability"}),
        "Foundry warning 2018 must not be ignored globally",
    )
    broad_paths = default_table.get("ignored_warnings_from", [])
    require(
        isinstance(broad_paths, list) and not broad_paths,
        "Foundry broad path warning ignores are prohibited for Phase 9",
    )

    raw_entries = default_table.get("ignored_error_codes_from", [])
    require(
        isinstance(raw_entries, list),
        "Foundry path-scoped warning policy is malformed",
    )
    raw_entry_list = cast(list[object], raw_entries)
    actual: set[tuple[str, tuple[str, ...]]] = set()
    for entry in raw_entry_list:
        require(
            isinstance(entry, list) and len(entry) == 2,
            "Foundry path-scoped warning entry is malformed",
        )
        entry_items = cast(list[object], entry)
        source_path, codes = entry_items
        require(
            isinstance(source_path, str) and isinstance(codes, list),
            "Foundry path-scoped warning entry has invalid types",
        )
        normalized_path = cast(str, source_path).replace("\\", "/").removeprefix("./")
        normalized_codes = tuple(str(code).strip().lower() for code in cast(list[object], codes))
        actual.add((normalized_path, normalized_codes))
    require(
        len(actual) == len(raw_entry_list),
        "Foundry path-scoped warning policy contains duplicate entries",
    )

    protocol_root = ROOT / "protocol"
    contracts_requiring_warning = set()
    for contract in PHASE9_PRODUCTION_CONTRACTS:
        source = strip_solidity_comments(read(imports[contract]))
        mutator_names = {name for name, _body in phase9_public_mutators(source, contract)}
        active_names = activated_function_names(contract, mutator_names, implemented)
        if active_names != mutator_names:
            contracts_requiring_warning.add(contract)
    expected = {
        (
            imports[contract].relative_to(protocol_root).as_posix(),
            (str(PHASE9_FOUNDRY_WARNING_CODE),),
        )
        for contract in PHASE9_PRODUCTION_CONTRACTS
        if contract in contracts_requiring_warning
    }
    missing = expected - actual
    unexpected = actual - expected
    require(
        not missing and not unexpected,
        "Foundry Phase 9 warning exception set drifted: "
        f"missing={sorted(missing)} unexpected={sorted(unexpected)}",
    )


def check_phase9_compatibility_review() -> None:
    require_paths(
        (
            PHASE9_COMPATIBILITY_MANIFEST_PATH,
            PHASE9_IMPLEMENTATION_CHECKPOINT_PATH,
            PHASE9_FREEZE_REVIEW_PATH,
        ),
        "Phase 9 compatibility manifest, implementation checkpoints, and freeze review",
    )
    manifest = check_manifest()
    review = normalized(read(PHASE9_FREEZE_REVIEW_PATH))
    require_tokens(
        review,
        (
            "decision: pass",
            "architecture review: pass",
            "security review: pass",
            manifest_hash(manifest),
            source_set_hash(manifest),
        ),
        "Phase 9 interface-freeze review",
    )
    contracts = manifest.get("contracts")
    if not isinstance(contracts, list):
        raise SystemExit("ERROR: Phase 9 compatibility manifest contracts are malformed")
    for entry in contracts:
        if not isinstance(entry, dict):
            raise SystemExit("ERROR: Phase 9 compatibility manifest entry is malformed")
        require_tokens(
            review,
            (
                str(entry.get("contract", "")),
                str(entry.get("abiSha256", "")),
                str(entry.get("sourceSha256", "")),
                str(entry.get("storageSha256", "")),
            ),
            "Phase 9 interface-freeze review hash table",
        )


def check_phase9_local_token_evidence(smoke_scripts: list[Path]) -> None:
    deploy_script = read(PHASE9_DEPLOY_SCRIPT_PATH)
    require_tokens(
        deploy_script,
        (
            "contract DeployPhase9Local",
            "new Phase9LocalSyntheticToken",
            "block.chainid",
            "31337",
        ),
        "Phase 9 local token deployment",
    )

    smoke = combined_text(smoke_scripts)
    require_tokens(
        smoke,
        (
            "DeployPhase9Local",
            "Phase9LocalSyntheticToken",
            "check-phase9-release-evidence",
        ),
        "Phase 9 local smoke token evidence",
    )

    reset = read(ROOT / "scripts/local-reset.ps1")
    require_tokens(
        reset,
        ("phase9", "Phase9LocalSyntheticToken", "phase9-release-evidence"),
        "Phase 9 local reset token cleanup",
    )

    release_checker = read(PHASE9_RELEASE_CHECK_PATH)
    require_tokens(
        release_checker,
        (
            "Phase9LocalSyntheticToken",
            RELEASE_MANIFEST_PATH,
            "eth_getCode",
            "balanceOf",
            "totalSupply",
        ),
        "Phase 9 release-evidence token validation",
    )
    release_declarations = combined_text((PHASE9_RELEASE_SCHEMA_PATH, PHASE9_RELEASE_DOC_PATH))
    require_tokens(
        release_declarations,
        ("Phase9LocalSyntheticToken", RELEASE_MANIFEST_PATH, "post-reset"),
        "Phase 9 release-evidence token declarations",
    )


def check_pre_code_freeze(by_id: dict[str, dict[str, str]]) -> None:
    freeze_started = phase9_freeze_started()
    abi_done = by_id["UNI-ABI-009"]["status"] == "DONE"
    if freeze_started:
        require(
            abi_done,
            "UNI-ABI-009 must be DONE when any Phase 9 Solidity source or "
            "ProtocolCompilation import exists",
        )
    if not abi_done and not freeze_started:
        return

    imports = phase9_compilation_imports()
    checkpoints = validate_checkpoints()
    checkpoint_payload = json.loads(read(PHASE9_IMPLEMENTATION_CHECKPOINT_PATH))
    raw_packages = checkpoint_payload.get("packages")
    require(
        isinstance(raw_packages, list)
        and all(isinstance(package, dict) for package in raw_packages),
        "Phase 9 checkpoint packages are malformed",
    )
    check_refinance_checkpoint_precedence(
        by_id,
        cast(list[dict[str, object]], raw_packages),
    )
    activation = activated_signatures()
    require(
        set(activation) == set(checkpoints),
        "Phase 9 activated-signature contracts differ from validated checkpoints",
    )
    check_phase9_abi_pairs(imports)
    check_phase9_storage_layouts()
    check_phase9_formatting_scope(imports)
    check_phase9_contract_size_coverage()
    check_phase9_stub_sources(imports, activation)
    check_phase9_foundry_warning_policy(imports, implemented=activation)
    check_phase9_local_token_source(imports)
    check_phase9_compatibility_review()


def check_implementation_artifacts() -> None:
    require_paths(IMPLEMENTATION_PATHS, "Phase 9 implementation artifacts")
    check_implementation_registers()

    proto_paths = sorted((ROOT / "schemas/proto/unified/v1").glob("*.proto"))
    proto = combined_text(proto_paths)
    require_tokens(
        proto,
        (
            "PayoffQuote",
            "Refinance",
            "Restructur",
            "PositionSnapshot",
            "Reserve",
            "Coverage",
            "InsuranceClaim",
            "Guarantee",
            "WriteOff",
            "Subrogation",
            "Recovery",
            "Solvency",
            "Reconciliation",
        ),
        "Phase 9 canonical schema",
    )

    solidity_paths = [
        path
        for path in (ROOT / "protocol/src").rglob("*.sol")
        if "crosschain" not in {part.lower() for part in path.parts}
    ]
    solidity = combined_text(solidity_paths)
    contract_patterns = {
        "payoff quote": r"\bcontract\s+\w*Payoff\w*",
        "refinance": r"\bcontract\s+\w*Refinance\w*",
        "lien registry": r"\bcontract\s+\w*Lien\w*",
        "restructuring": r"\bcontract\s+\w*Restructur\w*",
        "reserve vault": r"\bcontract\s+\w*Reserve\w*",
        "insurance or protection": r"\bcontract\s+\w*(?:Insurance|Protection)\w*",
        "guarantee": r"\bcontract\s+\w*Guarantee\w*",
        "recovery": r"\bcontract\s+\w*Recovery\w*",
    }
    missing_contracts = [
        label
        for label, pattern in contract_patterns.items()
        if re.search(pattern, solidity) is None
    ]
    require(
        not missing_contracts,
        "Phase 9 Solidity implementation is incomplete: " + ", ".join(missing_contracts),
    )

    model_paths = sorted((ROOT / "models/foundation_model/src/unified_foundation").glob("*.py"))
    model_text = combined_text(model_paths)
    require_tokens(
        model_text,
        (
            "payoff",
            "refinance",
            "restructur",
            "coverage",
            "claim",
            "guarantee",
            "write_off",
            "subrogation",
            "recovery",
        ),
        "Phase 9 independent model",
    )

    phase9_tests = list((ROOT / "protocol/test").glob("*Phase9*.t.sol"))
    require(bool(phase9_tests), "Phase 9 Foundry tests are missing")

    smoke_scripts = [
        path
        for path in (ROOT / "scripts").glob("*phase9*")
        if "smoke" in path.name.lower() and path.suffix.lower() in {".ps1", ".sh"}
    ]
    require(bool(smoke_scripts), "Phase 9 local smoke script is missing")
    check_phase9_local_token_evidence(smoke_scripts)

    workflow = normalized(read(ROOT / ".github/workflows/foundation.yml"))
    require_tokens(
        workflow,
        (
            "phase9",
            "check-phase9-release-evidence",
            "pre-reset",
            "local-reset",
            "post-reset",
        ),
        "Phase 9 live CI evidence",
    )
    review = normalized(read(ROOT / "security/reviews/phase-9-internal-review.md"))
    require_tokens(
        review,
        (
            "synthetic",
            "local",
            "no unresolved critical or existential",
            "production",
            "not granted",
        ),
        "Phase 9 internal security review",
    )


def check_exit_artifacts() -> None:
    require_paths((EXIT_PATH, README_PATH), "Phase 9 exit artifacts")
    readme = read(README_PATH).replace("\\", "/")
    require(
        "docs/reviews/phase-9-exit-review.md" in readme,
        "README does not link the Phase 9 exit review",
    )
    invocation = read(FOUNDATION_CHECK_PATH).replace("\\", "/")
    require(
        re.search(
            r"tools/check_phase9\.py\s+--require-exit-complete(?:\s|$)",
            invocation,
        )
        is not None,
        "foundation check does not invoke Phase 9 with --require-exit-complete",
    )
    exit_review = normalized(read(EXIT_PATH))
    require_tokens(
        exit_review,
        (
            "decision: pass",
            "production",
            "not granted",
            "all five",
            "all six",
            "protected",
            "reset",
        ),
        "Phase 9 exit review",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-implementation-complete", action="store_true")
    parser.add_argument("--require-exit-complete", action="store_true")
    args = parser.parse_args()

    require_implementation = args.require_implementation_complete or args.require_exit_complete
    check_boundary_paths()
    backlog = check_backlog(require_implementation, args.require_exit_complete)
    check_boundary_declarations()
    check_workstream_ownership()
    check_production_prohibitions()
    check_no_stale_phase17_recovery()
    check_boundary_evidence()
    check_pre_code_freeze(backlog)

    if require_implementation:
        check_implementation_artifacts()
    if args.require_exit_complete:
        check_exit_artifacts()

    mode = (
        "exit"
        if args.require_exit_complete
        else "implementation"
        if require_implementation
        else "boundary"
    )
    print(f"Phase 9 {mode} checks passed.")


if __name__ == "__main__":
    main()
