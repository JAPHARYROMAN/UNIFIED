"""Reject forbidden privileged Solidity surfaces from reviewed milestones."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "protocol" / "src"
FORBIDDEN = {
    r"\bfunction\s+mint\s*\(": "UFT or asset mint path",
    r"\bselfdestruct\s*\(": "selfdestruct",
    r"\bdelegatecall\s*\(": "delegatecall",
    r"\btx\.origin\b": "tx.origin authorization",
}


def main() -> None:
    failures: list[str] = []
    genesis_token = SOURCE_ROOT / "token" / "UnifiedToken.sol"
    wrapped_token = SOURCE_ROOT / "crosschain" / "WrappedUFT.sol"
    local_synthetic_token = SOURCE_ROOT / "crosschain" / "Phase8LocalSyntheticToken.sol"
    phase9_local_synthetic_token = (
        SOURCE_ROOT / "token" / "Phase9LocalSyntheticToken.sol"
    )
    reviewed_issuance = {
        genesis_token,
        wrapped_token,
        local_synthetic_token,
        phase9_local_synthetic_token,
    }
    for path in SOURCE_ROOT.rglob("*.sol"):
        source = path.read_text(encoding="utf-8")
        for pattern, label in FORBIDDEN.items():
            if re.search(pattern, source, flags=re.IGNORECASE):
                failures.append(f"{path.relative_to(ROOT)}: forbidden {label}")
        if "_mint(" in source and path not in reviewed_issuance:
            failures.append(
                f"{path.relative_to(ROOT)}: issuance primitive outside reviewed token surfaces"
            )
    if genesis_token.is_file():
        mint_calls = genesis_token.read_text(encoding="utf-8").count("_mint(")
        if mint_calls != 1:
            failures.append(
                "protocol/src/token/UnifiedToken.sol: expected exactly one "
                "constructor-reachable issuance primitive"
            )
    if wrapped_token.is_file():
        wrapped_source = wrapped_token.read_text(encoding="utf-8")
        if wrapped_source.count("_mint(") != 2:
            failures.append(
                "protocol/src/crosschain/WrappedUFT.sol: expected exactly two "
                "reviewed issuance primitives (coordinator mint and recovery remint)"
            )
        required_guards = [
            "function handleCrossChainMessage(",
            "msg.sender != address(coordinator)",
            "ACTION_HOME_UFT_MINT_AUTHORIZED",
            "function compensateMessage(",
            "msg.sender != recoveryController",
            "record.state != BurnRecoveryState.BURNED",
            "record.state = BurnRecoveryState.COMPENSATED",
            "_mint(record.account, record.amount)",
        ]
        if any(guard not in wrapped_source for guard in required_guards):
            failures.append(
                "protocol/src/crosschain/WrappedUFT.sol: reviewed issuance guards changed"
            )
    if local_synthetic_token.is_file():
        local_synthetic_source = local_synthetic_token.read_text(encoding="utf-8")
        if (
            local_synthetic_source.count("_mint(") != 1
            or "uint256 public constant MAX_SUPPLY = 1_000_000 ether;"
            not in local_synthetic_source
            or "_mint(msg.sender, MAX_SUPPLY);" not in local_synthetic_source
        ):
            failures.append(
                "protocol/src/crosschain/Phase8LocalSyntheticToken.sol: reviewed "
                "constructor-only synthetic issuance changed"
            )
    if phase9_local_synthetic_token.is_file():
        phase9_local_synthetic_source = phase9_local_synthetic_token.read_text(
            encoding="utf-8"
        )
        phase9_local_synthetic_compact = " ".join(
            phase9_local_synthetic_source.split()
        )
        required_phase9_fixture = (
            "constructor(address fixtureAllocator)",
            'ERC20("Unified Phase 9 Local Synthetic Unit", "P9UNIT")',
            "block.chainid != 31337",
            "fixtureAllocator == address(0)",
            "uint256 public constant FIXED_SUPPLY_UNITS = "
            "1_000_000_000_000_000;",
            "_mint(fixtureAllocator, FIXED_SUPPLY_UNITS);",
        )
        if (
            phase9_local_synthetic_source.count("_mint(") != 1
            or any(
                token not in phase9_local_synthetic_compact
                for token in required_phase9_fixture
            )
        ):
            failures.append(
                "protocol/src/token/Phase9LocalSyntheticToken.sol: reviewed "
                "chain-31337 constructor-only synthetic issuance changed"
            )
    if failures:
        raise SystemExit("\n".join(failures))
    print("Privileged Solidity surface check passed.")


if __name__ == "__main__":
    main()
