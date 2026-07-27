"""Reject oversized production runtime bytecode from all Foundry artifacts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "protocol" / "out"
LIMIT = 24_576
NON_PRODUCTION = {
    "DeployPhase2",
    "DeployPhase3",
    "DeployPhase4A",
    "DeployPhase4B1",
    "DeployPhase4B2",
    "DeployPhase5",
    "DeployPhase6A",
    "DeployPhase6B",
    "DeployPhase7C",
    "DeployPhase8Local",
    "FoundationProbeTest",
    "FeeSettlementToken",
    "Phase2KernelTest",
    "Phase3CoreLoanTest",
    "Phase4RiskEnginesTest",
    "Phase4CollateralTest",
    "Phase4LiquidationTest",
    "Phase5SyndicateTest",
    "Phase6IdentityTest",
    "Phase6UnderwrittenLoanTest",
    "Phase7CanonicalSettlementTest",
    "Phase8CrossChainCoreTest",
    "Phase8CrossChainFlowTest",
    "Phase8CrossChainFuzzTest",
    "Phase8CrossChainInvariantTest",
    "Phase8CrossChainRecoveryOrderingTest",
    "UFTSupplyInvariantTest",
    "BurnHandler",
    "TestSettlementToken",
    "TestPolicy",
    "TestOracleAdapter",
    "CollateralDebt",
    "CollateralLoanRegistry",
    "CollateralTest1155",
    "CollateralTestNFT",
    "CollateralTestToken",
    "LiquidationDebt",
    "LiquidationLoanRegistry",
    "LiquidationNFT",
    "LiquidationOracleAdapter",
    "LiquidationToken",
    "SyndicateTestPolicy",
    "SyndicateTestToken",
    "ExposureFactoryHarness",
    "ExposureTestLoan",
    "Phase6BSettlementToken",
    "Phase6BUnderwrittenPolicy",
    "Phase6BZeroInterestPolicy",
    "Phase7SettlementToken",
    "Phase8BridgeInvariantHandler",
    "Phase8CollateralInvariantHandler",
    "Phase8CoreReceiver",
    "Phase8CoreUFT",
    "Phase8FlowToken",
    "Phase8FuzzUFT",
    "Phase8InvariantCollateralComponent",
    "Phase8InvariantCoordinator",
    "Phase8InvariantRecovery",
    "Phase8InvariantToken",
    "Phase8LocalSyntheticToken",
    "Phase8MaliciousWrappedSource",
    "Phase8OrderingHub",
    "Phase8OrderingRegistry",
    "Phase8OrderingRouter",
    "Phase8OrderingToken",
    "ZeroInterestPolicy",
}


def _is_test_support(payload: dict[str, Any], contract_name: str) -> bool:
    """Identify compiler artifacts whose exact compilation target is under test/."""
    metadata = payload.get("metadata")
    if not isinstance(metadata, dict):
        return False
    settings = metadata.get("settings")
    if not isinstance(settings, dict):
        return False
    target = settings.get("compilationTarget")
    if not isinstance(target, dict) or len(target) != 1:
        return False
    source, target_contract = next(iter(target.items()))
    if not isinstance(source, str) or target_contract != contract_name:
        return False
    parts = source.split("/")
    return (
        len(parts) > 1
        and parts[0] == "test"
        and all(part not in {"", ".", ".."} for part in parts)
        and parts[-1].endswith(".sol")
    )


def main() -> None:
    failures: list[str] = []
    checked = 0
    for artifact in OUT.rglob("*.json"):
        if "build-info" in artifact.parts or artifact.parent.name.endswith((".t.sol", ".s.sol")):
            continue
        payload = json.loads(artifact.read_text(encoding="utf-8"))
        contract_name = artifact.stem
        if contract_name in NON_PRODUCTION or _is_test_support(payload, contract_name):
            continue
        deployed = payload.get("deployedBytecode", {}).get("object", "")
        if not deployed:
            continue
        if deployed.startswith("0x"):
            deployed = deployed[2:]
        size = len(deployed) // 2
        checked += 1
        if size > LIMIT:
            failures.append(f"{contract_name}: {size} bytes exceeds {LIMIT}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Production contract size check passed ({checked} artifacts).")


if __name__ == "__main__":
    main()
