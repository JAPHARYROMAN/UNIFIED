from __future__ import annotations

import copy
import hashlib
import json
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

import jsonschema
import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import check_phase9_refinance_linked_modules as linked_checker  # noqa: E402
import verify_phase9_refinance_deployment as verifier  # noqa: E402

JsonObject = dict[str, Any]
CANONICAL_CANDIDATE_BROADCASTER_CHECKSUM = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
EXPECTED_CANONICAL_ANVIL_ACCOUNTS = (
    "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
    "0x70997970c51812dc3a010c7d01b50e0d17dc79c8",
    "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc",
    "0x90f79bf6eb2c4f870365e785982e1f101e93b906",
    "0x15d34aaf54267db7d7c367839aaf71a00a2c6a65",
    "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc",
    "0x976ea74026e726554db657fa54763abd0c3a0aa9",
    "0x14dc79964da2c08b23698b3d3cc7ca32193d9955",
    "0x23618e81e3f5cdf7f54c3d65f7fbc0abf5b21e8f",
    "0xa0ee7a142d267c1f36714e4a8f75612f20a79720",
)
EXPECTED_CANONICAL_ANVIL_ACCOUNT_SET_SHA256 = (
    "sha256:0148b2c691381eeef3248447c4e12089414c4fa3e1214f2c4e8a1b89e51ffdc2"
)


def _address(value: int) -> str:
    return f"0x{value:040x}"


def _hash(value: int) -> str:
    return f"0x{value:064x}"


def _mixed_case_address(value: str) -> str:
    return "0x" + "".join(
        character.upper() if character in "abcdef" and index % 2 == 0 else character
        for index, character in enumerate(value[2:])
    )


def _freeze(value: object) -> object:
    if isinstance(value, dict):
        return tuple(sorted((str(key), _freeze(item)) for key, item in value.items()))
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def _rpc_key(method: str, *params: object) -> tuple[str, tuple[object, ...]]:
    return method, tuple(_freeze(param) for param in params)


class FakeRpc:
    def __init__(self, responses: Mapping[tuple[str, tuple[object, ...]], object]) -> None:
        self.responses = dict(responses)

    def __call__(self, method: str, params: list[object]) -> object:
        key = _rpc_key(method, *params)
        if key not in self.responses:
            raise AssertionError(f"unexpected RPC call: {key}")
        return self.responses[key]


def _placeholder_object(size: int, entries: list[JsonObject]) -> str:
    text = list("60" * size)
    for index, entry in enumerate(entries):
        start = int(entry["start"]) * 2
        text[start : start + 40] = list("__$" + f"{index + 1:034x}" + "$__")
    text[-4:] = list("0000")
    return "".join(text)


def _links(starts: Mapping[str, tuple[int, ...]]) -> list[JsonObject]:
    result: list[JsonObject] = []
    for library, offsets in starts.items():
        result.extend(
            {
                "source": verifier.FORGE_REFINANCE_SOURCE,
                "library": library,
                "start": start,
                "length": 20,
            }
            for start in offsets
        )
    return sorted(result, key=lambda entry: int(entry["start"]))


def _compiled_facts(module_addresses: Mapping[str, str] | None = None) -> JsonObject:
    creation_links = _links(
        {
            linked_checker.LIFECYCLE_MODULE: (1609, 1700, 1829, 1971),
            linked_checker.REQUEST_MODULE: (2020, 2498),
            linked_checker.VALIDATION_MODULE: (2291,),
        }
    )
    runtime_links = _links(
        {
            linked_checker.LIFECYCLE_MODULE: (1178, 1269, 1398, 1540),
            linked_checker.REQUEST_MODULE: (1589, 2067),
            linked_checker.VALIDATION_MODULE: (1860,),
        }
    )
    artifacts: dict[str, JsonObject] = {}
    module_template = bytes.fromhex("73" + "00" * 20 + "30") + b"module-runtime"
    for index, module in enumerate(linked_checker.MODULES, start=1):
        artifacts[module] = {
            "creation": bytes((0x60, index)) + b"module-creation",
            "runtime": module_template + bytes((index,)),
        }
    addresses = dict(
        module_addresses
        or {
            linked_checker.VALIDATION_MODULE: _address(601),
            linked_checker.REQUEST_MODULE: _address(602),
            linked_checker.LIFECYCLE_MODULE: _address(603),
        }
    )
    creation_hex = _placeholder_object(2600, creation_links)
    runtime_hex = _placeholder_object(2200, runtime_links)
    linked_creation = verifier._link_hex(creation_hex, creation_links, addresses)
    linked_runtime = verifier._link_hex(runtime_hex, runtime_links, addresses)
    artifacts[linked_checker.COORDINATOR] = {
        "creation_hex": creation_hex,
        "runtime_hex": runtime_hex,
        "creation_links": creation_links,
        "runtime_links": runtime_links,
        "linked_creation": linked_creation,
        "linked_runtime": linked_runtime,
        "reproduced_creation_executable_hash": verifier._keccak(
            verifier._executable_prefix(linked_creation, "fake creation")
        ),
        "reproduced_runtime_executable_hash": verifier._keccak(
            verifier._executable_prefix(linked_runtime, "fake runtime")
        ),
    }
    for index, contract in enumerate(verifier.FORGE_ARTIFACTS, start=1):
        artifacts[contract] = {
            "creation": bytes((0x61, index)) + b"creation",
            "runtime": bytes((0x62, index)) + b"runtime",
        }
    return {
        "compiler": {
            "solidity": linked_checker.SOLC_VERSION,
            "openzeppelin": linked_checker.OPENZEPPELIN_VERSION,
            "settings": linked_checker.COMPILER_SETTINGS,
            "remappings": [
                ":@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
                ":openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/",
            ],
            "source_set_sha256": "sha256:" + "3" * 64,
            "source_count": 42,
        },
        "artifacts": artifacts,
    }


def _configuration() -> JsonObject:
    policy = _address(105)
    return {
        "loan_registry": _address(101),
        "role_manager": _address(102),
        "settlement_token": _address(103),
        "quote_policy_registry": policy,
        "refinance_policy_registry": policy,
        "amendment_policy_registry": _address(106),
        "protection_policy_registry": _address(107),
        "recovery_policy_registry": _address(108),
        "asset_registry": _address(109),
        "emergency_controller": _address(110),
        "treasury_fee_recipient": _address(111),
        "maximum_quote_validity": 3600,
    }


def _candidate(plan: Mapping[str, Any]) -> JsonObject:
    configuration = plan["configuration"]
    by_key = {row["deployment"]: row for row in plan["transactions"]}
    payload: JsonObject = {
        "schema_version": 1,
        "artifact_type": "PHASE9_REFINANCE_DEPLOYMENT_CANDIDATE",
        "environment": "local",
        "contains_real_value": False,
        "chain_id": 31337,
        "topology_only": True,
        "topology_verified": False,
        "role_grant_performed": False,
        "plan_sha256": plan["plan_sha256"],
        "reset_identity": plan["reset_identity"],
        "source_commit": plan["source_commit"],
        "broadcaster": plan["broadcaster"],
        "latest_nonce_before": "0x0",
        "pending_nonce_before": "0x0",
        "latest_nonce_prepared": "0x1",
        "pending_nonce_prepared": "0x1",
        "starting_nonce": 1,
        "final_nonce": 11,
        "maximum_quote_validity": str(configuration["maximum_quote_validity"]),
        "configuration_hash": plan["configuration_hash"],
        "role_before_absent": True,
        "role_after_absent": True,
        "activation_accepted": False,
        "post_broadcast_verification_required": True,
        "deployment_history_reverted": False,
    }
    for field in verifier.CONFIG_FIELDS - {"maximum_quote_validity"}:
        payload[field] = configuration[field]
    for key, address in plan["addresses"].items():
        payload[f"predicted_{key}"] = _mixed_case_address(address)
        payload[f"actual_{key}"] = _mixed_case_address(address)
        payload[f"{key}_runtime_code_hash"] = by_key[key]["runtime_code_hash"]
    for field in verifier.CONFIG_FIELDS - {"maximum_quote_validity"}:
        payload[field] = _mixed_case_address(payload[field])
    payload["broadcaster"] = CANONICAL_CANDIDATE_BROADCASTER_CHECKSUM
    return payload


def _fixture(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    commit = "1" * 40
    monkeypatch.setattr(
        verifier,
        "_compiler_facts",
        lambda root=ROOT, module_addresses=None: _compiled_facts(module_addresses),
    )
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: (commit, True))
    plan: JsonObject = verifier.build_plan(
        _configuration(),
        verifier.CANONICAL_ANVIL_BROADCASTER,
        _hash(2),
        generated_at="2026-07-27T12:00:00Z",
        pre_broadcast_block={"number": "0x5", "hash": _hash(5)},
    )
    candidate = _candidate(plan)
    inputs, runtimes, dependency_runtimes = verifier._expected_inputs(plan)
    transactions: list[JsonObject] = []
    receipts: list[JsonObject] = []
    responses: dict[tuple[str, tuple[object, ...]], object] = {
        _rpc_key("eth_accounts"): list(verifier.CANONICAL_ANVIL_ACCOUNTS),
        _rpc_key("eth_chainId"): "0x7a69",
        _rpc_key("eth_getBlockByNumber", "0x0", False): {
            "number": "0x0",
            "hash": _hash(2),
        },
        _rpc_key("eth_getBlockByHash", _hash(5), False): {
            "number": "0x5",
            "hash": _hash(5),
        },
        _rpc_key("eth_getBlockByNumber", "0x5", False): {
            "number": "0x5",
            "hash": _hash(5),
        },
        _rpc_key("eth_getTransactionCount", plan["broadcaster"], "latest"): "0xb",
        _rpc_key("eth_getTransactionCount", plan["broadcaster"], "pending"): "0xb",
    }
    prepared_reference = verifier._block_reference(_hash(5))
    responses[_rpc_key("eth_getCode", plan["broadcaster"], prepared_reference)] = "0x"
    for field in verifier.CODE_DEPENDENCY_FIELDS:
        dependency_runtime = dependency_runtimes[field]
        responses[
            _rpc_key(
                "eth_getCode",
                plan["configuration"][field],
                prepared_reference,
            )
        ] = "0x" + dependency_runtime.hex()
    for row in plan["transactions"]:
        ordinal = int(row["ordinal"])
        key = str(row["deployment"])
        tx_hash = _hash(1000 + ordinal)
        block_hash = _hash(2000 + ordinal)
        transaction = {
            "from": plan["broadcaster"],
            "to": None,
            "nonce": hex(ordinal),
            "chainId": "0x7a69",
            "value": "0x0",
            "input": "0x" + inputs[key].hex(),
        }
        receipt = {
            "transactionHash": tx_hash,
            "status": "0x1",
            "contractAddress": row["predicted_address"],
            "blockHash": block_hash,
            "blockNumber": hex(100 + ordinal),
            "from": plan["broadcaster"],
            "to": None,
            "logs": [],
        }
        transactions.append(
            {
                "hash": tx_hash,
                "transactionType": "CREATE",
                "contractName": row["contract"],
                "contractAddress": row["predicted_address"],
                "transaction": transaction,
            }
        )
        receipts.append(copy.deepcopy(receipt))
        rpc_transaction = copy.deepcopy(transaction)
        rpc_transaction["hash"] = tx_hash
        responses[_rpc_key("eth_getTransactionByHash", tx_hash)] = rpc_transaction
        responses[_rpc_key("eth_getTransactionReceipt", tx_hash)] = receipt
        responses[
            _rpc_key(
                "eth_getCode",
                row["predicted_address"],
                verifier._block_reference(block_hash),
            )
        ] = "0x" + runtimes[key].hex()
    final_reference = verifier._block_reference(_hash(2010))
    for expectation in plan["storage_expectations"]:
        responses[
            _rpc_key(
                "eth_getStorageAt",
                plan["addresses"][expectation["deployment"]],
                hex(expectation["slot"]),
                final_reference,
            )
        ] = expectation["value"]
    role_manager = plan["configuration"]["role_manager"]
    role_suffix = verifier.LOAN_FACTORY_ROLE + verifier._word_address(
        plan["addresses"]["phase9_loan_factory"]
    )
    for block_hash in (_hash(5), _hash(2010)):
        reference = verifier._block_reference(block_hash)
        responses[_rpc_key("eth_getCode", role_manager, reference)] = (
            "0x" + dependency_runtimes["role_manager"].hex()
        )
        for selector in (verifier.ROLE_EXPIRY_SELECTOR, verifier.HAS_ROLE_SELECTOR):
            responses[
                _rpc_key(
                    "eth_call",
                    {
                        "to": role_manager,
                        "data": "0x" + (selector + role_suffix).hex(),
                    },
                    reference,
                )
            ] = "0x" + "00" * 32
    return {
        "plan": plan,
        "candidate": candidate,
        "broadcast": {"chain": 31337, "transactions": transactions, "receipts": receipts},
        "responses": responses,
    }


def _verify(fixture: Mapping[str, Any]) -> JsonObject:
    return verifier.verify(
        fixture["plan"],
        fixture["candidate"],
        fixture["broadcast"],
        FakeRpc(fixture["responses"]),
        rpc_url=verifier.CANONICAL_RPC_URL,
    )


def test_canonical_anvil_account_profile_and_digest_match_independent_literals() -> None:
    assert verifier.CANONICAL_ANVIL_ACCOUNTS == EXPECTED_CANONICAL_ANVIL_ACCOUNTS
    serialized = json.dumps(
        EXPECTED_CANONICAL_ANVIL_ACCOUNTS,
        separators=(",", ":"),
    ).encode("utf-8")
    independently_derived_digest = "sha256:" + hashlib.sha256(serialized).hexdigest()
    assert independently_derived_digest == EXPECTED_CANONICAL_ANVIL_ACCOUNT_SET_SHA256
    assert verifier.CANONICAL_ANVIL_ACCOUNT_SET_SHA256 == independently_derived_digest

    for schema_relative in (
        verifier.PLAN_SCHEMA_RELATIVE,
        verifier.EVIDENCE_SCHEMA_RELATIVE,
    ):
        schema = verifier._read_json(ROOT / schema_relative)
        account_set = schema["$defs"]["broadcasterProvenance"]["properties"]["account_set_sha256"]
        assert account_set["const"] == EXPECTED_CANONICAL_ANVIL_ACCOUNT_SET_SHA256


def test_valid_topology_is_non_activating_and_schema_valid(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fixture = _fixture(monkeypatch)
    evidence = _verify(fixture)

    assert evidence["artifact_type"] == "PHASE9_REFINANCE_TOPOLOGY_EVIDENCE"
    assert evidence["topology_only"] is True
    assert evidence["topology_verified"] is True
    assert evidence["activation_accepted"] is False
    assert evidence["role_grant_performed"] is False
    assert evidence["broadcaster_provenance"] == verifier.CANONICAL_BROADCASTER_PROVENANCE
    assert evidence["nonce_transcript"]["latest_final"] == "0xb"
    assert any(character.isupper() for character in fixture["candidate"]["broadcaster"])
    assert evidence["reset_command"] == "pwsh ./scripts/smoke-phase9-refinance-anvil.ps1"
    for schema_path in (
        verifier.PLAN_SCHEMA_RELATIVE,
        verifier.CANDIDATE_SCHEMA_RELATIVE,
        verifier.EVIDENCE_SCHEMA_RELATIVE,
    ):
        schema = verifier._read_json(ROOT / schema_path)
        jsonschema.Draft202012Validator.check_schema(schema)


@pytest.mark.parametrize(
    ("artifact_key", "schema_relative", "field", "value"),
    [
        (
            "plan",
            verifier.PLAN_SCHEMA_RELATIVE,
            "broadcaster",
            _address(9999),
        ),
        (
            "candidate",
            verifier.CANDIDATE_SCHEMA_RELATIVE,
            "broadcaster",
            _mixed_case_address(_address(9999)),
        ),
        (
            "evidence",
            verifier.EVIDENCE_SCHEMA_RELATIVE,
            "broadcaster",
            _address(9999),
        ),
        (
            "plan",
            verifier.PLAN_SCHEMA_RELATIVE,
            "reset_command",
            "do-nothing",
        ),
        (
            "evidence",
            verifier.EVIDENCE_SCHEMA_RELATIVE,
            "reset_command",
            "do-nothing",
        ),
        (
            "evidence",
            verifier.EVIDENCE_SCHEMA_RELATIVE,
            "rpc_url",
            "http://localhost:18545",
        ),
    ],
)
def test_artifact_schemas_pin_local_broadcaster_rpc_and_reset_command(
    monkeypatch: pytest.MonkeyPatch,
    artifact_key: str,
    schema_relative: Path,
    field: str,
    value: object,
) -> None:
    fixture = _fixture(monkeypatch)
    artifacts = {
        "plan": fixture["plan"],
        "candidate": fixture["candidate"],
        "evidence": _verify(fixture),
    }
    payload = copy.deepcopy(artifacts[artifact_key])
    payload[field] = value
    with pytest.raises(verifier.VerificationError, match="does not satisfy schema"):
        verifier._validate_schema(
            payload,
            ROOT / schema_relative,
            artifact_key,
        )


def test_plan_pins_ten_creates_links_self_patch_and_limits(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    plan = _fixture(monkeypatch)["plan"]
    assert [row["nonce"] for row in plan["transactions"]] == list(range(1, 11))
    assert all(row["sender"] == plan["broadcaster"] for row in plan["transactions"])
    assert all(row["value"] == 0 for row in plan["transactions"])
    assert [row["deployment"] for row in plan["transactions"]][5:10] == [
        "validation_module",
        "request_module",
        "lifecycle_module",
        "payoff_quote_engine",
        "refinance_coordinator",
    ]
    assert [entry["start"] for entry in plan["coordinator_links"]["creation"]["entries"]] == [
        1609,
        1700,
        1829,
        1971,
        2020,
        2291,
        2498,
    ]
    assert [entry["start"] for entry in plan["coordinator_links"]["runtime"]["entries"]] == [
        1178,
        1269,
        1398,
        1540,
        1589,
        1860,
        2067,
    ]
    assert all(module["self_patch_offset"] == 1 for module in plan["modules"].values())
    assert all(module["self_patch_length"] == 20 for module in plan["modules"].values())
    assert all(row["runtime_bytes"] <= 24_576 for row in plan["transactions"])
    assert all(row["initcode_bytes"] <= 49_152 for row in plan["transactions"])
    factory_storage = {
        row["slot"]: row["value"]
        for row in plan["storage_expectations"]
        if row["deployment"] == "phase9_loan_factory"
    }
    assert set(factory_storage) == set(range(8))
    assert int(factory_storage[7], 16) >> 160 == 1
    assert int(factory_storage[7], 16) & ((1 << 160) - 1) == int(
        plan["configuration"]["recovery_policy_registry"], 16
    )


@pytest.mark.parametrize(
    ("mutation", "message"),
    [
        ("extra_transaction", "exactly ten transactions"),
        ("reordered_receipts", "receipt mismatch"),
        ("wrong_nonce", "broadcast transaction mismatch"),
        ("wrong_input", "broadcast transaction mismatch"),
        ("rpc_hash", "RPC transaction hash mismatch"),
        ("rpc_sender", "RPC transaction sender mismatch"),
        ("rpc_target", "RPC transaction target mismatch"),
        ("rpc_nonce", "RPC transaction nonce mismatch"),
        ("rpc_chain", "RPC transaction chain mismatch"),
        ("rpc_value", "RPC transaction value mismatch"),
        ("anvil_account_profile", "canonical freshly spawned Anvil fixture profile"),
        ("rpc_input", "RPC transaction input mismatch"),
        ("wrong_runtime", "deployed runtime mismatch"),
        ("wrong_storage", "constructor storage mismatch"),
        ("wrong_final_nonce", "final latest and pending nonces"),
        ("role_granted", "role must remain absent"),
        ("role_log", "forbidden role"),
        ("pre_block_substitution", "no longer canonical"),
        ("candidate_substitution", "candidate does not exactly bind"),
        ("candidate_unknown_field", "does not satisfy schema"),
        ("broadcaster_provenance", "does not satisfy schema"),
        ("reset_substitution", "reset_identity does not match"),
        ("missing_dependency_code", "must contain code before broadcast"),
        ("wrong_dependency_runtime", "asset_registry runtime does not match"),
        ("wrong_token_runtime", "settlement_token runtime does not match"),
    ],
)
def test_rpc_and_candidate_mutations_fail_closed(
    monkeypatch: pytest.MonkeyPatch, mutation: str, message: str
) -> None:
    fixture = _fixture(monkeypatch)
    if mutation == "extra_transaction":
        fixture["broadcast"]["transactions"].append(
            copy.deepcopy(fixture["broadcast"]["transactions"][-1])
        )
    elif mutation == "reordered_receipts":
        fixture["broadcast"]["receipts"][0], fixture["broadcast"]["receipts"][1] = (
            fixture["broadcast"]["receipts"][1],
            fixture["broadcast"]["receipts"][0],
        )
    elif mutation == "wrong_nonce":
        fixture["broadcast"]["transactions"][4]["transaction"]["nonce"] = "0x6"
    elif mutation == "wrong_input":
        fixture["broadcast"]["transactions"][9]["transaction"]["input"] = "0x00"
    elif mutation.startswith("rpc_"):
        tx_hash = fixture["broadcast"]["transactions"][2]["hash"]
        rpc_transaction = fixture["responses"][_rpc_key("eth_getTransactionByHash", tx_hash)]
        field_values = {
            "rpc_hash": ("hash", _hash(9999)),
            "rpc_sender": ("from", _address(9999)),
            "rpc_target": ("to", _address(9998)),
            "rpc_nonce": ("nonce", "0x4"),
            "rpc_chain": ("chainId", "0x1"),
            "rpc_value": ("value", "0x1"),
            "rpc_input": ("input", "0x6000"),
        }
        field, value = field_values[mutation]
        rpc_transaction[field] = value
    elif mutation == "anvil_account_profile":
        fixture["responses"][_rpc_key("eth_accounts")][1] = _address(9999)
    elif mutation == "wrong_runtime":
        row = fixture["plan"]["transactions"][5]
        fixture["responses"][
            _rpc_key(
                "eth_getCode",
                row["predicted_address"],
                verifier._block_reference(_hash(2006)),
            )
        ] = "0x6000"
    elif mutation == "wrong_storage":
        expectation = fixture["plan"]["storage_expectations"][0]
        fixture["responses"][
            _rpc_key(
                "eth_getStorageAt",
                fixture["plan"]["addresses"][expectation["deployment"]],
                hex(expectation["slot"]),
                verifier._block_reference(_hash(2010)),
            )
        ] = "0x" + "00" * 32
    elif mutation == "wrong_final_nonce":
        fixture["responses"][
            _rpc_key("eth_getTransactionCount", fixture["plan"]["broadcaster"], "latest")
        ] = "0xa"
    elif mutation == "role_granted":
        role_manager = fixture["plan"]["configuration"]["role_manager"]
        suffix = verifier.LOAN_FACTORY_ROLE + verifier._word_address(
            fixture["plan"]["addresses"]["phase9_loan_factory"]
        )
        fixture["responses"][
            _rpc_key(
                "eth_call",
                {
                    "to": role_manager,
                    "data": "0x" + (verifier.HAS_ROLE_SELECTOR + suffix).hex(),
                },
                verifier._block_reference(_hash(2010)),
            )
        ] = "0x" + f"{1:064x}"
    elif mutation == "role_log":
        tx_hash = fixture["broadcast"]["transactions"][0]["hash"]
        fixture["responses"][_rpc_key("eth_getTransactionReceipt", tx_hash)]["logs"] = [
            {"topics": [next(iter(verifier.ROLE_EVENT_TOPICS))]}
        ]
    elif mutation == "pre_block_substitution":
        fixture["responses"][_rpc_key("eth_getBlockByHash", _hash(5), False)]["hash"] = _hash(6)
    elif mutation == "candidate_substitution":
        fixture["candidate"]["source_commit"] = "2" * 40
    elif mutation == "candidate_unknown_field":
        fixture["candidate"]["unexpected_authority"] = True
    elif mutation == "broadcaster_provenance":
        fixture["plan"]["broadcaster_provenance"]["private_key_input"] = True
    elif mutation == "reset_substitution":
        fixture["responses"][_rpc_key("eth_getBlockByNumber", "0x0", False)]["hash"] = _hash(3)
    elif mutation == "missing_dependency_code":
        fixture["responses"][
            _rpc_key(
                "eth_getCode",
                fixture["plan"]["configuration"]["asset_registry"],
                verifier._block_reference(_hash(5)),
            )
        ] = "0x"
    elif mutation == "wrong_dependency_runtime":
        fixture["responses"][
            _rpc_key(
                "eth_getCode",
                fixture["plan"]["configuration"]["asset_registry"],
                verifier._block_reference(_hash(5)),
            )
        ] = "0x6000"
    else:
        fixture["responses"][
            _rpc_key(
                "eth_getCode",
                fixture["plan"]["configuration"]["settlement_token"],
                verifier._block_reference(_hash(5)),
            )
        ] = "0x6000"

    with pytest.raises(verifier.VerificationError, match=message):
        _verify(fixture)


@pytest.mark.parametrize("account_index", [8, 9])
def test_either_corrected_tail_account_mutation_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
    account_index: int,
) -> None:
    fixture = _fixture(monkeypatch)
    accounts = fixture["responses"][_rpc_key("eth_accounts")]
    assert accounts[account_index] == EXPECTED_CANONICAL_ANVIL_ACCOUNTS[account_index]
    accounts[account_index] = _address(9_000 + account_index)

    with pytest.raises(
        verifier.VerificationError,
        match="canonical freshly spawned Anvil fixture profile",
    ):
        _verify(fixture)


def test_plan_or_compiler_link_drift_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    fixture = _fixture(monkeypatch)
    fixture["plan"]["coordinator_links"]["runtime"]["entries"][0]["start"] += 1
    with pytest.raises(verifier.VerificationError, match="stale or noncanonical"):
        _verify(fixture)


def test_noncanonical_broadcaster_provenance_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, True))
    with pytest.raises(verifier.VerificationError, match="canonical freshly spawned Anvil"):
        verifier.build_plan(
            _configuration(),
            _address(500),
            _hash(2),
            generated_at="2026-07-27T12:00:00Z",
        )


def test_dirty_worktree_and_bad_module_self_patch_reject(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, False))
    monkeypatch.setattr(
        verifier,
        "_compiler_facts",
        lambda root=ROOT, module_addresses=None: _compiled_facts(module_addresses),
    )
    with pytest.raises(verifier.VerificationError, match="worktree changes"):
        verifier.build_plan(
            _configuration(),
            verifier.CANONICAL_ANVIL_BROADCASTER,
            _hash(2),
            generated_at="2026-07-27T12:00:00Z",
        )

    facts = _compiled_facts()
    artifacts = facts["artifacts"]
    artifacts[linked_checker.VALIDATION_MODULE]["runtime"] = b"not-self-patching"
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, True))
    monkeypatch.setattr(verifier, "_compiler_facts", lambda root=ROOT, module_addresses=None: facts)
    with pytest.raises(verifier.VerificationError, match="self-patch template drifted"):
        verifier.build_plan(
            _configuration(),
            verifier.CANONICAL_ANVIL_BROADCASTER,
            _hash(2),
            generated_at="2026-07-27T12:00:00Z",
        )


def test_distinct_quote_and_refinance_policies_reject(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    configuration = _configuration()
    configuration["refinance_policy_registry"] = _address(112)
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, True))
    with pytest.raises(verifier.VerificationError, match="must equal"):
        verifier.build_plan(
            configuration,
            verifier.CANONICAL_ANVIL_BROADCASTER,
            _hash(2),
            generated_at="2026-07-27T12:00:00Z",
        )


def test_reset_identity_must_be_block_hash(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, True))
    with pytest.raises(verifier.VerificationError, match="block-zero hash"):
        verifier.build_plan(
            _configuration(),
            verifier.CANONICAL_ANVIL_BROADCASTER,
            "sha256:" + "2" * 64,
            generated_at="2026-07-27T12:00:00Z",
        )


def test_build_plan_rejects_noncanonical_reset_command(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(verifier, "_git_identity", lambda root=ROOT: ("1" * 40, True))
    with pytest.raises(verifier.VerificationError, match="canonical command"):
        verifier.build_plan(
            _configuration(),
            verifier.CANONICAL_ANVIL_BROADCASTER,
            _hash(2),
            generated_at="2026-07-27T12:00:00Z",
            reset_command="do-nothing",
        )


def test_immutable_runtime_words_are_patched_exactly() -> None:
    template = b"\x60" + bytes(32) + b"\x61" + bytes(32) + b"\x62"
    word = verifier._word_address(_address(777))
    patched = verifier._patch_immutable_words(template, [1, 34], word)
    assert patched == b"\x60" + word + b"\x61" + word + b"\x62"
    with pytest.raises(verifier.VerificationError, match="placeholder drifted"):
        verifier._patch_immutable_words(patched, [1], word)


def test_canonical_path_rejects_parent_reparse(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    root = tmp_path / "repo"
    target = root / verifier.PLAN_RELATIVE
    target.parent.mkdir(parents=True)
    target.write_text("{}", encoding="utf-8")
    monkeypatch.setattr(verifier, "ROOT", root)
    monkeypatch.setattr(verifier, "_path_is_reparse", lambda path: path == root)
    with pytest.raises(verifier.VerificationError, match="symlink or reparse point"):
        verifier._canonical_output(target, verifier.PLAN_RELATIVE, must_exist=True)


@pytest.mark.parametrize(
    "url",
    [
        "https://127.0.0.1:18545",
        "http://192.168.1.2:18545",
        "http://user:pass@127.0.0.1:18545",
        "http://127.0.0.1:18545/rpc",
        "http://127.0.0.1:18545/",
        "http://127.0.0.1:18546",
        "http://localhost:18545",
        "http://[::1]:18545",
        "http://127.0.0.1.evil:18545",
    ],
)
def test_rpc_boundary_rejects_noncanonical_urls(url: str) -> None:
    with pytest.raises(verifier.VerificationError):
        verifier.canonical_rpc_url(url)


def test_rpc_boundary_accepts_only_the_canonical_url() -> None:
    assert verifier.canonical_rpc_url(verifier.CANONICAL_RPC_URL) == verifier.CANONICAL_RPC_URL
