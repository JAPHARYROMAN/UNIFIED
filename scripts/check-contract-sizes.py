"""Reject oversized deployable Phase 2 runtime bytecode from Foundry artifacts."""

from __future__ import annotations

import json
from pathlib import Path

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
    "ZeroInterestPolicy",
}


def main() -> None:
    failures: list[str] = []
    checked = 0
    for artifact in OUT.rglob("*.json"):
        if "build-info" in artifact.parts:
            continue
        payload = json.loads(artifact.read_text(encoding="utf-8"))
        contract_name = artifact.stem
        if contract_name in NON_PRODUCTION:
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
