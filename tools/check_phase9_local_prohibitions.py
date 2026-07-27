#!/usr/bin/env python3
"""Fail closed when the Phase 9 topology escapes its synthetic-local boundary."""

from __future__ import annotations

import ast
import re
import urllib.parse
from collections import Counter
from collections.abc import Mapping
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parents[1]

CANONICAL_SETUP_BROADCASTER = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
CANONICAL_CANDIDATE_BROADCASTER = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
CANONICAL_GOVERNANCE_EXECUTOR = "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"
CANONICAL_FIXTURE_ALLOCATOR = "0x90f79bf6eb2c4f870365e785982e1f101e93b906"
CANONICAL_RPC_URL = "http://127.0.0.1:18545"
CANONICAL_RPC_HOST = "127.0.0.1"
CANONICAL_RPC_PORT = 18_545
CANONICAL_TOKEN_NAME = "Unified Phase 9 Local Synthetic Unit"  # noqa: S105 - public identity
CANONICAL_TOKEN_SYMBOL = "P9UNIT"  # noqa: S105 - public symbol
CANONICAL_ACCOUNT_SET_SHA256 = (
    "sha256:19901d67310664f0f09541131dbc6669f2aa9ce4ffdb1cf497d8a7da8d1ba307"
)
ACCEPTANCE_NON_ACTIVATION_SENTENCE = (
    "ADR 0023 additionally permits one preliminary topology checkpoint that cannot "
    "satisfy any `P9R-*` row:"
)
CONTRADICTORY_PRELIMINARY_CHECKPOINT_ASSERTION = re.compile(
    r"\bpreliminary(?:\s+[a-z][a-z-]*){0,3}\s+checkpoint\b"
    r"(?=[^.!?\n]{0,320}\b(?:can|may|does)\s+(?:satisfy|activate)\b)"
    r"(?=[^.!?\n]{0,320}(?:`?P9R-\*`?|\bP9R-[A-Z0-9]+(?:-[A-Z0-9]+)*\b|"
    r"\bP9R\s+rows?\b))",
    re.IGNORECASE,
)

SURFACE_PATHS = (
    ".github/workflows/foundation.yml",
    "docs/architecture/phase-9-refinance-acceptance.md",
    "docs/architecture/phase-9-refinance-deployment-evidence.md",
    "infrastructure/local/phase9-refinance-deployment-candidate.schema.json",
    "infrastructure/local/phase9-refinance-deployment-evidence.schema.json",
    "infrastructure/local/phase9-refinance-deployment-plan.schema.json",
    "protocol/script/DeployPhase9RefinanceLocal.s.sol",
    "protocol/script/PreparePhase9RefinanceLocal.s.sol",
    "protocol/src/token/Phase9LocalSyntheticToken.sol",
    "scripts/check-foundation.ps1",
    "scripts/smoke-phase9-refinance-anvil.ps1",
    "tools/verify_phase9_refinance_deployment.py",
)

EXECUTABLE_PATHS = (
    ".github/workflows/foundation.yml",
    "protocol/script/DeployPhase9RefinanceLocal.s.sol",
    "protocol/script/PreparePhase9RefinanceLocal.s.sol",
    "protocol/src/token/Phase9LocalSyntheticToken.sol",
    "scripts/check-foundation.ps1",
    "scripts/smoke-phase9-refinance-anvil.ps1",
    "tools/verify_phase9_refinance_deployment.py",
)

ALLOWED_RPC_METHODS = frozenset(
    {
        "anvil_reset",
        "anvil_setNonce",
        "eth_accounts",
        "eth_call",
        "eth_chainId",
        "eth_getBlockByHash",
        "eth_getBlockByNumber",
        "eth_getCode",
        "eth_getStorageAt",
        "eth_getTransactionByHash",
        "eth_getTransactionCount",
        "eth_getTransactionReceipt",
        "evm_revert",
        "evm_snapshot",
        "web3_clientVersion",
    }
)

EXPECTED_PREPARE_VM_CALLS = Counter(
    {
        "serializeAddress": 11,
        "serializeUint": 1,
        "startBroadcast": 1,
        "stopBroadcast": 1,
        "writeJson": 1,
    }
)
EXPECTED_DEPLOY_VM_CALLS = Counter(
    {
        "getNonce": 2,
        "isContext": 1,
        "load": 1,
        "serializeAddress": 14,
        "serializeBool": 9,
        "serializeBytes32": 3,
        "serializeString": 9,
        "serializeUint": 4,
        "startBroadcast": 1,
        "stopBroadcast": 1,
        "toString": 1,
        "writeJson": 1,
    }
)
EXPECTED_PREPARE_CREATIONS = (
    "RoleManager",
    "LoanRegistry",
    "PolicyRegistry",
    "AssetRegistry",
    "EmergencyController",
    "Phase9LocalSyntheticToken",
)
EXPECTED_DEPLOY_CREATIONS = (
    "LienRegistry",
    "CollateralCustodyV2",
    "Phase9LoanAccount",
    "PositionManagerV2",
    "Phase9LoanFactory",
    "PayoffQuoteEngine",
    "RefinanceCoordinator",
)
EXPECTED_LINKED_MODULE_CREATIONS = (
    "Phase9RefinanceValidationModule",
    "Phase9RefinanceRequestModule",
    "Phase9RefinanceLifecycleModule",
)

REQUIRED_TOKENS: dict[str, tuple[str, ...]] = {
    ".github/workflows/foundation.yml": (
        'version: "v1.7.1"',
        ".cache/foundry-v1.7.1",
        "ItemType SymbolicLink",
        "uv run --frozen python tools/check_phase9_local_prohibitions.py",
        "./scripts/smoke-phase9-refinance-anvil.ps1",
    ),
    "scripts/check-foundation.ps1": ("uv run python tools/check_phase9_local_prohibitions.py",),
    "docs/architecture/phase-9-refinance-acceptance.md": (
        "P9R-LOCAL-001",
        "P9R-LOCAL-002",
        "P9R-LOCAL-003",
    ),
    "docs/architecture/phase-9-refinance-deployment-evidence.md": (
        CANONICAL_CANDIDATE_BROADCASTER,
        "standalone verifier rejects every other broadcaster",
        "do not independently prove signer origin",
        "harness-owned process and recorded invocation",
        "activation_accepted=false",
        "role_grant_performed=false",
        "contains_real_value=false",
    ),
    "infrastructure/local/phase9-refinance-deployment-candidate.schema.json": (
        '"environment": { "const": "local" }',
        '"contains_real_value": { "const": false }',
        '"chain_id": { "const": 31337 }',
        '"activation_accepted": { "const": false }',
        '"broadcaster": { "const": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" }',
    ),
    "infrastructure/local/phase9-refinance-deployment-evidence.schema.json": (
        '"environment": { "const": "local" }',
        '"contains_real_value": { "const": false }',
        '"chain_id": { "const": 31337 }',
        '"activation_accepted": { "const": false }',
        '"private_key_input": { "const": false }',
        CANONICAL_CANDIDATE_BROADCASTER,
        CANONICAL_ACCOUNT_SET_SHA256,
        f'"broadcaster": {{ "const": "{CANONICAL_CANDIDATE_BROADCASTER}" }}',
        '"reset_command": { "const": "pwsh ./scripts/smoke-phase9-refinance-anvil.ps1" }',
        f'"rpc_url": {{ "const": "{CANONICAL_RPC_URL}" }}',
    ),
    "infrastructure/local/phase9-refinance-deployment-plan.schema.json": (
        '"environment": { "const": "local" }',
        '"contains_real_value": { "const": false }',
        '"chain_id": { "const": 31337 }',
        '"activation_accepted": { "const": false }',
        '"private_key_input": { "const": false }',
        CANONICAL_CANDIDATE_BROADCASTER,
        CANONICAL_ACCOUNT_SET_SHA256,
        f'"broadcaster": {{ "const": "{CANONICAL_CANDIDATE_BROADCASTER}" }}',
        '"reset_command": { "const": "pwsh ./scripts/smoke-phase9-refinance-anvil.ps1" }',
    ),
    "protocol/script/DeployPhase9RefinanceLocal.s.sol": (
        "if (block.chainid != 31_337)",
        'keccak256("deployments/local/phase9-refinance-deployment-candidate.json")',
        'vm.serializeBool(key, "contains_real_value", false)',
        'vm.serializeBool(key, "topology_only", true)',
        'vm.serializeBool(key, "role_grant_performed", false)',
        'vm.serializeBool(key, "activation_accepted", false)',
        "type(Phase9LocalSyntheticToken).runtimeCode",
    ),
    "protocol/script/PreparePhase9RefinanceLocal.s.sol": (
        "if (block.chainid != 31_337)",
        "new Phase9LocalSyntheticToken(fixtureAllocator)",
    ),
    "protocol/src/token/Phase9LocalSyntheticToken.sol": (
        "if (block.chainid != 31337)",
        f'ERC20("{CANONICAL_TOKEN_NAME}", "{CANONICAL_TOKEN_SYMBOL}")',
        "_mint(fixtureAllocator, FIXED_SUPPLY_UNITS)",
    ),
    "scripts/smoke-phase9-refinance-anvil.ps1": (
        f"$setupBroadcaster = '{CANONICAL_SETUP_BROADCASTER}'",
        f"$candidateBroadcaster = '{CANONICAL_CANDIDATE_BROADCASTER}'",
        f"$governanceExecutor = '{CANONICAL_GOVERNANCE_EXECUTOR}'",
        f"$fixtureAllocator = '{CANONICAL_FIXTURE_ALLOCATOR}'",
        f"[string]$RpcUrl = '{CANONICAL_RPC_URL}'",
        "if (Test-RpcOccupied)",
        "Start-Process",
        "'--silent', '--host', '127.0.0.1', '--port', [string]$rpc.Port",
        "'--chain-id', '31337'",
        "--sender $candidateBroadcaster --unlocked --broadcast --slow",
        "$evidence.activation_accepted -ne $false",
        "$evidence.role_grant_performed -ne $false",
        "$evidence.contains_real_value -ne $false",
        "$evidence.broadcaster_provenance.private_key_input -ne $false",
        CANONICAL_ACCOUNT_SET_SHA256,
        "Invoke-Rpc 'evm_revert'",
        "Assert-EmptyCode",
    ),
    "tools/verify_phase9_refinance_deployment.py": (
        f'CANONICAL_RPC_URL = "{CANONICAL_RPC_URL}"',
        f'CANONICAL_ANVIL_BROADCASTER = "{CANONICAL_CANDIDATE_BROADCASTER}"',
        '"account_profile": "foundry-default-account-1"',
        '"private_key_input": False',
        "_require_canonical_anvil_accounts(rpc)",
        "CANONICAL_ANVIL_ACCOUNTS",
        '"contains_real_value": False',
        '"activation_accepted": False',
        '"role_grant_performed": False',
        "canonical_rpc_url(rpc_url)",
        "value != CANONICAL_RPC_URL",
        'if rpc("eth_chainId", []) != "0x7a69"',
        '_quantity(transaction.get("value"), f"{key}.value") != 0',
    ),
}

FORBIDDEN_EXECUTABLE_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "private-key, mnemonic, keystore, hardware-wallet, or cloud-KMS input",
        re.compile(
            r"--(?:private-key|mnemonic|keystore|ledger|trezor|aws)|"
            r"(?:env:|environ\[|getenv\()[^\n]*(?:private.?key|mnemonic|keystore|kms|hsm)",
            re.IGNORECASE,
        ),
    ),
    (
        "fork, public network, or production provider",
        re.compile(
            r"--fork-url|\b(?:mainnet|sepolia|holesky|infura|alchemy|quicknode|ankr)\b",
            re.IGNORECASE,
        ),
    ),
    (
        "production asset symbol or real-value opt-in",
        re.compile(
            r"\b(?:USDC|USDT|DAI|PYUSD|WETH|WBTC)\b|"
            r"contains_real_value[\"']?\s*[:=]\s*true",
            re.IGNORECASE,
        ),
    ),
    (
        "privileged send, encoded role mutation, or activation acceptance",
        re.compile(
            r"\b(?:grantRole|revokeRole|setRoleAdmin)\s*\(|"
            r"\b(?:eth|personal)_send(?:Raw)?Transaction\b|"
            r"\b(?:anvil|hardhat)_(?:impersonateAccount|setBalance|setCode|setStorageAt)\b|"
            r"(?:^|[\s;&|])cast\s+(?:mktx|publish|send)\b|"
            r"&\s*\$cast\s+(?:mktx|publish|send)\b|"
            r"abi\.encodeWith(?:Selector|Signature)\s*\(|"
            r"\b(?:call|delegatecall|staticcall)\s*\(|"
            r"\b(?:2f2ff15d|f2efd809|d547741f|1e4e0091)\b|"
            r"activation_accepted[\"']?\s*[:=]\s*true|"
            r"serializeBool\([^\n]*\"activation_accepted\"[^\n]*true",
            re.IGNORECASE | re.MULTILINE,
        ),
    ),
)

URL_PATTERN = re.compile(r"https?://[^\s'\"<>(){}]+", re.IGNORECASE)
POWERSHELL_RPC_CALL = re.compile(r"\bInvoke-Rpc\b\s+([^\s\)]+)")
POWERSHELL_CAST_CALL = re.compile(r"&\s*\$cast\s+([^\s\)]+)", re.IGNORECASE)


class ProhibitionError(RuntimeError):
    """Raised when the synthetic-local topology boundary is weakened."""


def _fail(message: str) -> NoReturn:
    raise ProhibitionError(message)


def load_surface(root: Path = ROOT) -> dict[str, str]:
    surface: dict[str, str] = {}
    for relative in SURFACE_PATHS:
        path = root / relative
        if not path.is_file():
            _fail(f"Phase 9 local prohibition surface is missing: {relative}")
        surface[relative] = path.read_text(encoding="utf-8")
    return surface


def _check_executable_urls(executable: str) -> None:
    for match in URL_PATTERN.finditer(executable):
        candidate = match.group(0).rstrip(".,;")
        try:
            parsed = urllib.parse.urlsplit(candidate)
            port = parsed.port
        except ValueError:
            _fail(f"Phase 9 executable surface contains a malformed provider URL: {candidate!r}")
        if (
            candidate != CANONICAL_RPC_URL
            or parsed.scheme != "http"
            or parsed.hostname != CANONICAL_RPC_HOST
            or port != CANONICAL_RPC_PORT
            or parsed.username is not None
            or parsed.password is not None
            or parsed.path != ""
            or parsed.query
            or parsed.fragment
        ):
            _fail(f"Phase 9 executable surface contains a noncanonical provider URL: {candidate!r}")


def _check_python_rpc_calls(source: str) -> None:
    try:
        tree = ast.parse(source)
    except SyntaxError as error:
        _fail(f"Phase 9 verifier Python source is not parseable: {error}")
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Name) or node.func.id != "rpc":
            continue
        if not node.args or not isinstance(node.args[0], ast.Constant):
            _fail("Phase 9 verifier RPC method must be a static string literal")
        method = node.args[0].value
        if not isinstance(method, str) or method not in ALLOWED_RPC_METHODS:
            _fail(f"Phase 9 verifier RPC method is not allowed: {method!r}")


def _check_powershell_rpc_calls(source: str) -> None:
    for line in source.splitlines():
        stripped = line.strip()
        if not stripped or stripped.lower().startswith("function invoke-rpc"):
            continue
        if "Invoke-Rpc" not in line:
            continue
        match = POWERSHELL_RPC_CALL.search(line)
        if match is None:
            _fail(f"Phase 9 harness RPC invocation is not statically parseable: {stripped!r}")
        raw_method = match.group(1)
        if (
            len(raw_method) < 2
            or raw_method[0] not in {'"', "'"}
            or raw_method[-1] != raw_method[0]
        ):
            _fail(f"Phase 9 harness RPC method must be a static string literal: {raw_method!r}")
        method = raw_method[1:-1]
        if method not in ALLOWED_RPC_METHODS:
            _fail(f"Phase 9 harness RPC method is not allowed: {method!r}")


def _check_foundry_commands(source: str) -> None:
    cast_primitives = [match.group(1).lower() for match in POWERSHELL_CAST_CALL.finditer(source)]
    if Counter(cast_primitives) != Counter({"@arguments": 1, "chain-id": 1, "compute-address": 1}):
        _fail(f"Phase 9 harness cast command primitives drifted: {cast_primitives}")

    forge_invocations = re.findall(r"&\s*\$forge\s+([^\s`]+)", source, flags=re.IGNORECASE)
    if [primitive.lower() for primitive in forge_invocations] != ["script", "script"]:
        _fail(f"Phase 9 harness forge command primitives drifted: {forge_invocations}")


def _check_host_arguments(executable: str) -> None:
    host_values = [
        *(
            match.group(1)
            for match in re.finditer(r"['\"]--host['\"]\s*,\s*['\"]([^'\"]+)['\"]", executable)
        ),
        *(
            match.group(1)
            for match in re.finditer(
                r"(?<!['\"])--host(?:=|\s+)(?:['\"])?([^\s'\"`,]+)", executable
            )
        ),
    ]
    if host_values != [CANONICAL_RPC_HOST]:
        _fail(f"Phase 9 harness Anvil host arguments drifted: {host_values}")


def _vm_call_counts(source: str) -> Counter[str]:
    return Counter(re.findall(r"\bvm\.([A-Za-z_][A-Za-z0-9_]*)", source))


def _check_solidity_primitives(surface: Mapping[str, str]) -> None:
    prepare = surface["protocol/script/PreparePhase9RefinanceLocal.s.sol"]
    deploy = surface["protocol/script/DeployPhase9RefinanceLocal.s.sol"]
    token = surface["protocol/src/token/Phase9LocalSyntheticToken.sol"]

    prepare_vm_calls = _vm_call_counts(prepare)
    deploy_vm_calls = _vm_call_counts(deploy)
    if prepare_vm_calls != EXPECTED_PREPARE_VM_CALLS:
        _fail(f"Phase 9 prerequisite VM primitive set drifted: {prepare_vm_calls}")
    if deploy_vm_calls != EXPECTED_DEPLOY_VM_CALLS:
        _fail(f"Phase 9 topology VM primitive set drifted: {deploy_vm_calls}")

    prepare_creations = tuple(re.findall(r"\bnew\s+([A-Za-z_][A-Za-z0-9_]*)", prepare))
    deploy_creations = tuple(re.findall(r"\bnew\s+([A-Za-z_][A-Za-z0-9_]*)", deploy))
    linked_creations = tuple(
        re.findall(
            r"_deployModule\(\s*type\(([A-Za-z_][A-Za-z0-9_]*)\)\.creationCode\s*\)",
            deploy,
        )
    )
    if prepare_creations != EXPECTED_PREPARE_CREATIONS:
        _fail(f"Phase 9 prerequisite contract creation set drifted: {prepare_creations}")
    if deploy_creations != EXPECTED_DEPLOY_CREATIONS:
        _fail(f"Phase 9 topology contract creation set drifted: {deploy_creations}")
    if linked_creations != EXPECTED_LINKED_MODULE_CREATIONS:
        _fail(f"Phase 9 linked-module creation set drifted: {linked_creations}")
    if len(re.findall(r"\bcreate\s*\(", deploy)) != 1 or re.search(r"\bcreate2\s*\(", deploy):
        _fail("Phase 9 topology assembly CREATE primitive drifted")

    erc20_identities = re.findall(r"ERC20\(\s*\"([^\"]+)\"\s*,\s*\"([^\"]+)\"\s*\)", token)
    if erc20_identities != [(CANONICAL_TOKEN_NAME, CANONICAL_TOKEN_SYMBOL)]:
        _fail(f"Phase 9 settlement-token identity drifted: {erc20_identities}")
    mint_calls = re.findall(r"\b_mint\s*\(([^;]+)\);", token)
    if mint_calls != ["fixtureAllocator, FIXED_SUPPLY_UNITS"]:
        _fail(f"Phase 9 settlement-token mint primitive drifted: {mint_calls}")
    if prepare.count('vm.serializeAddress(key, "settlement_token", address(settlementToken))') != 1:
        _fail("Phase 9 prerequisite settlement-token serialization drifted")
    verifier = surface["tools/verify_phase9_refinance_deployment.py"]
    if verifier.count('"settlement_token": "Phase9LocalSyntheticToken"') != 1:
        _fail("Phase 9 verifier settlement-token type binding drifted")


def check_surface(surface: Mapping[str, str]) -> None:
    if set(surface) != set(SURFACE_PATHS):
        missing = sorted(set(SURFACE_PATHS) - set(surface))
        unexpected = sorted(set(surface) - set(SURFACE_PATHS))
        _fail(f"Phase 9 prohibition surface drifted: missing={missing}; unexpected={unexpected}")

    for relative, tokens in REQUIRED_TOKENS.items():
        text = surface[relative]
        missing = [token for token in tokens if token not in text]
        if missing:
            _fail(f"{relative} lost local-only control(s): {', '.join(missing)}")

    normalized_acceptance = re.sub(
        r"\s+",
        " ",
        surface["docs/architecture/phase-9-refinance-acceptance.md"],
    ).strip()
    if ACCEPTANCE_NON_ACTIVATION_SENTENCE not in normalized_acceptance:
        _fail(
            "Phase 9 acceptance lost the exact normalized preliminary-topology "
            "non-activation sentence"
        )
    contradiction = CONTRADICTORY_PRELIMINARY_CHECKPOINT_ASSERTION.search(
        normalized_acceptance
    )
    if contradiction is not None:
        _fail(
            "Phase 9 acceptance contains a contradictory preliminary-checkpoint "
            f"P9R assertion: {contradiction.group(0)!r}"
        )

    executable = "\n".join(surface[relative] for relative in EXECUTABLE_PATHS)
    for label, pattern in FORBIDDEN_EXECUTABLE_PATTERNS:
        match = pattern.search(executable)
        if match is not None:
            _fail(f"Phase 9 executable surface contains prohibited {label}: {match.group(0)!r}")

    _check_executable_urls(executable)
    _check_host_arguments(executable)
    _check_python_rpc_calls(surface["tools/verify_phase9_refinance_deployment.py"])
    smoke = surface["scripts/smoke-phase9-refinance-anvil.ps1"]
    _check_powershell_rpc_calls(smoke)
    _check_foundry_commands(smoke)
    _check_solidity_primitives(surface)


def check_repository(root: Path = ROOT) -> None:
    check_surface(load_surface(root))


def main() -> None:
    try:
        check_repository()
    except ProhibitionError as error:
        raise SystemExit(f"ERROR: {error}") from error
    print(
        "Phase 9 synthetic-local topology prechecks and prohibition guards passed; all P9R "
        "rows remain unsatisfied, with no role grant, activation, production authority, or "
        "real value granted."
    )


if __name__ == "__main__":
    main()
