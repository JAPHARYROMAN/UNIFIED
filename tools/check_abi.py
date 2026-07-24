"""Compare the compiled foundation ABI with its reviewed snapshot."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ABI_PAIRS = {
    "FoundationProbe": (
        ROOT / ".cache" / "solc" / "protocol_src_FoundationProbe_sol_FoundationProbe.abi",
        ROOT / "protocol" / "abi" / "FoundationProbe.abi.json",
    ),
    "AllocationVault": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_token_AllocationVault_sol_AllocationVault.abi",
        ROOT / "protocol" / "abi" / "phase2" / "AllocationVault.abi.json",
    ),
    "AssetRegistry": (
        ROOT / ".cache" / "solc" / "protocol_src_kernel_AssetRegistry_sol_AssetRegistry.abi",
        ROOT / "protocol" / "abi" / "phase2" / "AssetRegistry.abi.json",
    ),
    "EmergencyController": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_kernel_EmergencyController_sol_EmergencyController.abi",
        ROOT / "protocol" / "abi" / "phase2" / "EmergencyController.abi.json",
    ),
    "LoanFactory": (
        ROOT / ".cache" / "solc" / "protocol_src_kernel_LoanFactory_sol_LoanFactory.abi",
        ROOT / "protocol" / "abi" / "phase2" / "LoanFactory.abi.json",
    ),
    "LoanRegistry": (
        ROOT / ".cache" / "solc" / "protocol_src_kernel_LoanRegistry_sol_LoanRegistry.abi",
        ROOT / "protocol" / "abi" / "phase2" / "LoanRegistry.abi.json",
    ),
    "PolicyRegistry": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_kernel_PolicyRegistry_sol_PolicyRegistry.abi",
        ROOT / "protocol" / "abi" / "phase2" / "PolicyRegistry.abi.json",
    ),
    "ProtocolFeeRouter": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_token_ProtocolFeeRouter_sol_ProtocolFeeRouter.abi",
        ROOT / "protocol" / "abi" / "phase2" / "ProtocolFeeRouter.abi.json",
    ),
    "RoleManager": (
        ROOT / ".cache" / "solc" / "protocol_src_kernel_RoleManager_sol_RoleManager.abi",
        ROOT / "protocol" / "abi" / "phase2" / "RoleManager.abi.json",
    ),
    "UFTBurner": (
        ROOT / ".cache" / "solc" / "protocol_src_token_UFTBurner_sol_UFTBurner.abi",
        ROOT / "protocol" / "abi" / "phase2" / "UFTBurner.abi.json",
    ),
    "UnifiedProtocol": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_kernel_UnifiedProtocol_sol_UnifiedProtocol.abi",
        ROOT / "protocol" / "abi" / "phase2" / "UnifiedProtocol.abi.json",
    ),
    "UnifiedToken": (
        ROOT / ".cache" / "solc" / "protocol_src_token_UnifiedToken_sol_UnifiedToken.abi",
        ROOT / "protocol" / "abi" / "phase2" / "UnifiedToken.abi.json",
    ),
    "VersionedLoanAccount": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_kernel_VersionedLoanAccount_sol_VersionedLoanAccount.abi",
        ROOT / "protocol" / "abi" / "phase2" / "VersionedLoanAccount.abi.json",
    ),
    "VestingPoolVault": (
        ROOT
        / ".cache"
        / "solc"
        / "protocol_src_token_VestingPoolVault_sol_VestingPoolVault.abi",
        ROOT / "protocol" / "abi" / "phase2" / "VestingPoolVault.abi.json",
    ),
    "CoreLoanAccount": (
        ROOT / ".cache" / "solc" / "protocol_src_loan_CoreLoanAccount_sol_CoreLoanAccount.abi",
        ROOT / "protocol" / "abi" / "phase3" / "CoreLoanAccount.abi.json",
    ),
    "CoreLoanFactory": (
        ROOT / ".cache" / "solc" / "protocol_src_loan_CoreLoanFactory_sol_CoreLoanFactory.abi",
        ROOT / "protocol" / "abi" / "phase3" / "CoreLoanFactory.abi.json",
    ),
    "FundingManager": (
        ROOT / ".cache" / "solc" / "protocol_src_loan_FundingManager_sol_FundingManager.abi",
        ROOT / "protocol" / "abi" / "phase3" / "FundingManager.abi.json",
    ),
    "OfferManager": (
        ROOT / ".cache" / "solc" / "protocol_src_loan_OfferManager_sol_OfferManager.abi",
        ROOT / "protocol" / "abi" / "phase3" / "OfferManager.abi.json",
    ),
    "TenderRegistry": (
        ROOT / ".cache" / "solc" / "protocol_src_loan_TenderRegistry_sol_TenderRegistry.abi",
        ROOT / "protocol" / "abi" / "phase3" / "TenderRegistry.abi.json",
    ),
}


def main() -> None:
    failures: list[str] = []
    for contract, (compiled_path, baseline_path) in ABI_PAIRS.items():
        if not compiled_path.is_file():
            failures.append(f"{contract}: compiled ABI is missing")
            continue
        if not baseline_path.is_file():
            failures.append(f"{contract}: reviewed ABI baseline is missing")
            continue
        compiled = json.loads(compiled_path.read_text(encoding="utf-8"))
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        if compiled != baseline:
            failures.append(f"{contract}: ABI differs from reviewed baseline")
    if failures:
        raise SystemExit(
            "\n".join(failures)
            + "\nReview compatibility and update snapshots through an ADR."
        )
    print(f"ABI compatibility check passed ({len(ABI_PAIRS)} contracts).")


if __name__ == "__main__":
    main()
