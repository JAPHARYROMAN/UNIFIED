from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import check_phase9_local_prohibitions as checker  # noqa: E402


def _surface() -> dict[str, str]:
    return checker.load_surface(ROOT)


def test_current_phase9_topology_prohibition_surface_passes() -> None:
    checker.check_surface(_surface())


@pytest.mark.parametrize(
    ("relative", "old", "new"),
    [
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            f"[string]$RpcUrl = '{checker.CANONICAL_RPC_URL}'",
            "[string]$RpcUrl = 'https://mainnet.infura.io/v3/example'",
        ),
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            f"$candidateBroadcaster = '{checker.CANONICAL_CANDIDATE_BROADCASTER}'",
            "$candidateBroadcaster = '0x0000000000000000000000000000000000000500'",
        ),
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            "'--chain-id', '31337'",
            "'--chain-id', '1'",
        ),
        (
            "protocol/src/token/Phase9LocalSyntheticToken.sol",
            "if (block.chainid != 31337)",
            "if (block.chainid != 1)",
        ),
        (
            "infrastructure/local/phase9-refinance-deployment-evidence.schema.json",
            '"contains_real_value": { "const": false }',
            '"contains_real_value": { "const": true }',
        ),
        (
            "tools/verify_phase9_refinance_deployment.py",
            f'CANONICAL_ANVIL_BROADCASTER = "{checker.CANONICAL_CANDIDATE_BROADCASTER}"',
            'CANONICAL_ANVIL_BROADCASTER = "0x0000000000000000000000000000000000000500"',
        ),
        (
            ".github/workflows/foundation.yml",
            "run: ./scripts/smoke-phase9-refinance-anvil.ps1",
            "run: echo topology-smoke-disabled",
        ),
        (
            "scripts/check-foundation.ps1",
            "uv run python tools/check_phase9_local_prohibitions.py",
            "Write-Output 'Phase 9 prohibition scan disabled'",
        ),
        (
            "docs/architecture/phase-9-refinance-deployment-evidence.md",
            "standalone verifier rejects every other broadcaster",
            "standalone verifier accepts other broadcasters",
        ),
        (
            "docs/architecture/phase-9-refinance-deployment-evidence.md",
            "do not independently prove signer origin",
            "prove signer origin",
        ),
        (
            "docs/architecture/phase-9-refinance-acceptance.md",
            "preliminary topology checkpoint that cannot satisfy",
            "preliminary topology checkpoint that can satisfy",
        ),
        (
            "docs/architecture/phase-9-refinance-acceptance.md",
            "any `P9R-*` row:",
            "any `P9R-*` row before final review:",
        ),
        (
            "docs/architecture/phase-9-refinance-acceptance.md",
            "any `P9R-*` row:",
            "any `P9R-*` row;",
        ),
    ],
)
def test_local_boundary_mutations_fail_closed(relative: str, old: str, new: str) -> None:
    surface = copy.deepcopy(_surface())
    assert old in surface[relative]
    surface[relative] = surface[relative].replace(old, new, 1)
    with pytest.raises(checker.ProhibitionError):
        checker.check_surface(surface)


@pytest.mark.parametrize("modal", ["can", "may", "does"])
@pytest.mark.parametrize("verb", ["satisfy", "activate"])
@pytest.mark.parametrize(
    "target",
    ["the `P9R-LOCAL-001` row", "any `P9R-*` row", "any P9R row"],
)
def test_contradictory_preliminary_checkpoint_p9r_assertions_fail_closed(
    modal: str, verb: str, target: str
) -> None:
    surface = copy.deepcopy(_surface())
    acceptance = "docs/architecture/phase-9-refinance-acceptance.md"
    assert checker.ACCEPTANCE_NON_ACTIVATION_SENTENCE in " ".join(
        surface[acceptance].split()
    )
    surface[acceptance] += (
        f"\nThe preliminary topology checkpoint {modal} {verb} {target}.\n"
    )
    with pytest.raises(checker.ProhibitionError, match="contradictory preliminary-checkpoint"):
        checker.check_surface(surface)


def test_future_activation_grade_d4_prose_is_not_a_preliminary_checkpoint_conflict() -> None:
    surface = copy.deepcopy(_surface())
    surface["docs/architecture/phase-9-refinance-acceptance.md"] += (
        "\nA future activation-grade D4 checkpoint may satisfy the `P9R-LOCAL-001` row "
        "only after every authoritative gate passes.\n"
    )
    checker.check_surface(surface)


@pytest.mark.parametrize(
    "injection",
    [
        "\n--private-key 0x" + "11" * 32,
        "\n--fork-url https://mainnet.example.invalid",
        "\nsettlement_asset = USDC",
        "\nsettlement_asset = PYUSD",
        "\ngrantRole(LOAN_FACTORY_ROLE, candidate)",
    ],
)
def test_forbidden_provider_key_asset_and_authority_inputs_fail(injection: str) -> None:
    surface = copy.deepcopy(_surface())
    relative = "scripts/smoke-phase9-refinance-anvil.ps1"
    surface[relative] += injection
    with pytest.raises(checker.ProhibitionError, match="prohibited"):
        checker.check_surface(surface)


@pytest.mark.parametrize(
    "url",
    [
        "https://127.0.0.1:18545",
        "http://127.0.0.1:18546",
        "http://127.0.0.1.evil:18545",
        "http://localhost:18545",
        "http://[::1]:18545",
        "http://user@127.0.0.1:18545",
        "http://127.0.0.1:18545/rpc",
        "http://127.0.0.1:18545?fork=mainnet",
        "http://127.0.0.1:notaport",
        "http://127.0.0.1:18545:",
    ],
)
def test_noncanonical_url_literals_fail_exact_parsing(url: str) -> None:
    surface = copy.deepcopy(_surface())
    surface[".github/workflows/foundation.yml"] += f"\n      - run: curl {url}\n"
    with pytest.raises(checker.ProhibitionError, match="provider URL|prohibited"):
        checker.check_surface(surface)


def test_workflow_commands_are_part_of_executable_scanning() -> None:
    surface = copy.deepcopy(_surface())
    surface[".github/workflows/foundation.yml"] += (
        "\n      - run: cast send --rpc-url http://127.0.0.1:18545 "
        "0x0000000000000000000000000000000000000001 0xf2efd809\n"
    )
    with pytest.raises(checker.ProhibitionError, match="privileged send"):
        checker.check_surface(surface)


@pytest.mark.parametrize(
    ("relative", "injection", "message"),
    [
        (
            "tools/verify_phase9_refinance_deployment.py",
            "\nrpc(method, [])\n",
            "static string literal",
        ),
        (
            "tools/verify_phase9_refinance_deployment.py",
            '\nrpc("eth_sendTransaction", [])\n',
            "privileged send|not allowed",
        ),
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            "\nInvoke-Rpc $privilegedMethod @()\n",
            "static string literal",
        ),
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            "\n& $cast send $roleManager --data 0xf2efd809 --unlocked\n",
            "privileged send",
        ),
        (
            "scripts/smoke-phase9-refinance-anvil.ps1",
            "\n& $anvil --host 0.0.0.0 --port 18545\n",
            "host arguments",
        ),
        (
            "protocol/script/DeployPhase9RefinanceLocal.s.sol",
            '\n// encoded grant bypass\naddress(configuration.roleManager).call(hex"f2efd809");\n',
            "privileged send",
        ),
        (
            "protocol/script/DeployPhase9RefinanceLocal.s.sol",
            "\n// dynamic encoded grant bypass\n"
            "roleTarget.call(abi.encode(grantSelector, role, account));\n",
            "privileged send",
        ),
        (
            "protocol/script/DeployPhase9RefinanceLocal.s.sol",
            "\nvm.deal(configuration.broadcaster, 1 ether);\n",
            "VM primitive set",
        ),
    ],
)
def test_unapproved_privileged_primitives_fail_closed(
    relative: str, injection: str, message: str
) -> None:
    surface = copy.deepcopy(_surface())
    surface[relative] += injection
    with pytest.raises(checker.ProhibitionError, match=message):
        checker.check_surface(surface)


@pytest.mark.parametrize(
    ("relative", "old", "new"),
    [
        (
            "protocol/src/token/Phase9LocalSyntheticToken.sol",
            'ERC20("Unified Phase 9 Local Synthetic Unit", "P9UNIT")',
            'ERC20("PayPal USD", "PYUSD")',
        ),
        (
            "protocol/src/token/Phase9LocalSyntheticToken.sol",
            "_mint(fixtureAllocator, FIXED_SUPPLY_UNITS);",
            "_mint(fixtureAllocator, FIXED_SUPPLY_UNITS);\n_mint(msg.sender, 1);",
        ),
        (
            "protocol/script/PreparePhase9RefinanceLocal.s.sol",
            "Phase9LocalSyntheticToken settlementToken = "
            "new Phase9LocalSyntheticToken(fixtureAllocator);",
            "Phase9LocalSyntheticToken settlementToken = "
            "new Phase9LocalSyntheticToken(fixtureAllocator);\n"
            "        ProductionToken shadowAsset = new ProductionToken();",
        ),
        (
            "tools/verify_phase9_refinance_deployment.py",
            '"settlement_token": "Phase9LocalSyntheticToken"',
            '"settlement_token": "ExternalAsset"',
        ),
    ],
)
def test_only_canonical_local_token_identity_and_creation_are_allowed(
    relative: str, old: str, new: str
) -> None:
    surface = copy.deepcopy(_surface())
    assert old in surface[relative]
    surface[relative] = surface[relative].replace(old, new, 1)
    with pytest.raises(checker.ProhibitionError):
        checker.check_surface(surface)
