from __future__ import annotations

import copy
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

import jsonschema
import pytest
from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import verify_phase9_payoff_deployment as verifier  # noqa: E402

CANDIDATE_SCHEMA = ROOT / "infrastructure/local/phase9-payoff-deployment-candidate.schema.json"
EVIDENCE_SCHEMA = ROOT / "infrastructure/local/phase9-payoff-deployment-evidence.schema.json"


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _runtime_hash(code: bytes) -> str:
    digest = keccak.new(digest_bits=256)
    digest.update(code)
    return "0x" + digest.hexdigest()


def _address(number: int) -> str:
    return f"0x{number:040x}"


def _topic_address(address: str) -> str:
    return "0x" + "00" * 12 + address[2:]


class FakeRpc:
    def __init__(self, responses: dict[tuple[str, tuple[object, ...]], object]) -> None:
        self.responses = responses

    def __call__(self, method: str, params: list[object]) -> object:
        key = (method, tuple(params))
        if key not in self.responses:
            raise AssertionError(f"unexpected RPC call: {key}")
        return self.responses[key]


def deployment_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    pair = _address(1)
    token = _address(2)
    engine = verifier._create_address(pair, 1)
    coordinator = verifier._create_address(pair, 2)
    sender = _address(3)
    token_hash = "0x" + "11" * 32
    pair_hash = "0x" + "22" * 32
    token_block_hash = "0x" + "33" * 32
    pair_block_hash = "0x" + "44" * 32
    token_block = 10
    pair_block = 11
    codes = {
        "token": bytes.fromhex("60006000"),
        "engine": bytes.fromhex("60016001"),
        "coordinator": bytes.fromhex("60026002"),
        "pair": bytes.fromhex("60036003"),
    }
    creation_codes = {
        name: bytes((0x60 + index,)) + code
        for index, (name, code) in enumerate(codes.items())
    }

    artifact_paths: dict[str, str] = {}
    pins_contracts: dict[str, dict[str, object]] = {}
    for name, code in codes.items():
        relative = verifier.REVIEWED_ARTIFACT_PATHS[name]
        artifact_paths[name] = relative
        compilation_target = verifier.REVIEWED_COMPILATION_TARGETS[name]
        source_relative = next(iter(compilation_target))
        source_path = tmp_path / "protocol" / source_relative
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source_bytes = f"// {name} fixture source\n".encode()
        source_path.write_bytes(source_bytes)
        _write_json(
            tmp_path / relative,
            {
                "bytecode": {"object": "0x" + creation_codes[name].hex()},
                "deployedBytecode": {"object": "0x" + code.hex()},
                "metadata": {
                    "compiler": {"version": "0.8.36+commit.fixture"},
                    "settings": {
                        "optimizer": {"enabled": True, "runs": 200},
                        "evmVersion": "prague",
                        "compilationTarget": compilation_target,
                    },
                    "sources": {
                        source_relative: {"keccak256": _runtime_hash(source_bytes)}
                    },
                },
            },
        )
        pins_contracts[name] = {
            "artifactPath": relative,
            "creationBytes": len(creation_codes[name]),
            "creationCodeHash": _runtime_hash(creation_codes[name]),
            "runtimeBytes": len(code),
            "runtimeCodeHash": _runtime_hash(code),
        }
    pins_path = tmp_path / verifier.PIN_MANIFEST_RELATIVE
    _write_json(
        pins_path,
        {
            "schemaVersion": 1,
            "compiler": verifier.REVIEWED_COMPILER,
            "contracts": pins_contracts,
        },
    )
    pin_manifest_sha256 = verifier._sha256_file(pins_path)
    monkeypatch.setattr(verifier, "REVIEWED_PIN_MANIFEST_SHA256", pin_manifest_sha256)
    evidence_schema = json.loads(EVIDENCE_SCHEMA.read_text(encoding="utf-8"))
    evidence_schema["properties"]["pin_manifest_sha256"]["const"] = pin_manifest_sha256
    _write_json(tmp_path / verifier.EVIDENCE_SCHEMA_RELATIVE, evidence_schema)

    candidate: dict[str, object] = {
        "schema_version": 1,
        "artifact_type": "PHASE9_PAYOFF_DEPLOYMENT_CANDIDATE",
        "environment": "local",
        "contains_real_value": False,
        "chain_id": 31337,
        "activation_accepted": False,
        "post_broadcast_verification_required": True,
        "deployment_history_reverted": False,
        "pair_deployer": pair,
        "engine_create_nonce": 1,
        "loan_registry": _address(10),
        "phase9_loan_factory": _address(11),
        "quote_policy_registry": _address(12),
        "lien_registry": _address(13),
        "asset_registry": _address(14),
        "refinance_policy_registry": _address(15),
        "emergency_controller": _address(16),
        "treasury_fee_recipient": _address(17),
        "fixture_allocator": _address(18),
        "maximum_quote_validity": "3600",
        "settlement_token": token,
        "predicted_engine": engine,
        "predicted_coordinator": coordinator,
        "expected_token_runtime_code_hash": pins_contracts["token"]["runtimeCodeHash"],
        "expected_engine_runtime_code_hash": pins_contracts["engine"]["runtimeCodeHash"],
        "expected_coordinator_runtime_code_hash": pins_contracts["coordinator"][
            "runtimeCodeHash"
        ],
        "expected_pair_runtime_code_hash": pins_contracts["pair"]["runtimeCodeHash"],
    }
    facts = verifier._candidate_facts(
        {
            **candidate,
            "configuration_hash": "0x" + "01" * 32,
            "engine_constructor_args_hash": "0x" + "02" * 32,
            "coordinator_constructor_args_hash": "0x" + "03" * 32,
            "deployment_call_hash": "0x" + "04" * 32,
        }
    )
    candidate["configuration_hash"] = verifier._configuration_hash(facts)
    facts["configuration_hash"] = candidate["configuration_hash"]
    candidate["engine_constructor_args_hash"] = verifier._engine_args_hash(facts)
    facts["engine_constructor_args_hash"] = candidate["engine_constructor_args_hash"]
    candidate["coordinator_constructor_args_hash"] = verifier._coordinator_args_hash(facts)
    facts["coordinator_constructor_args_hash"] = candidate["coordinator_constructor_args_hash"]
    candidate["deployment_call_hash"] = verifier._deployment_call_hash(facts)
    candidate_path = tmp_path / verifier.CANDIDATE_RELATIVE
    _write_json(candidate_path, candidate)
    loaded_pins = verifier.load_reviewed_hashes(pins_path, tmp_path)
    token_input, pair_input = verifier._expected_creation_inputs(facts, loaded_pins)

    token_receipt: dict[str, object] = {
        "transactionHash": token_hash,
        "status": "0x1",
        "contractAddress": token,
        "blockHash": token_block_hash,
        "blockNumber": hex(token_block),
        "from": sender,
        "to": None,
        "logs": [],
    }
    pair_receipt: dict[str, object] = {
        "transactionHash": pair_hash,
        "status": "0x1",
        "contractAddress": pair,
        "blockHash": pair_block_hash,
        "blockNumber": hex(pair_block),
        "from": sender,
        "to": None,
        "logs": [
            {
                "address": pair,
                "topics": [
                    verifier.PAIR_EVENT_TOPIC,
                    _topic_address(pair),
                    _topic_address(engine),
                    _topic_address(coordinator),
                ],
                "data": "0x" + f"{1:064x}",
            }
        ],
    }
    broadcast = {
        "chain": 31337,
        "transactions": [
            {
                "hash": token_hash,
                "transactionType": "CREATE",
                "contractName": "Phase9LocalSyntheticToken",
                "contractAddress": token,
                "transaction": {
                    "from": sender,
                    "to": None,
                    "nonce": "0x5",
                    "input": token_input,
                    "value": "0x0",
                    "chainId": "0x7a69",
                },
            },
            {
                "hash": pair_hash,
                "transactionType": "CREATE",
                "contractName": "Phase9PayoffPairDeployer",
                "contractAddress": pair,
                "transaction": {
                    "from": sender,
                    "to": None,
                    "nonce": "0x6",
                    "input": pair_input,
                    "value": "0x0",
                    "chainId": "0x7a69",
                },
            },
        ],
        "receipts": [token_receipt, pair_receipt],
    }
    broadcast_path = tmp_path / verifier.BROADCAST_RELATIVE
    _write_json(broadcast_path, broadcast)

    responses: dict[tuple[str, tuple[object, ...]], object] = {
        ("eth_chainId", ()): "0x7a69"
    }
    for tx_hash_value, nonce, creation_input, block_hash, block_number, receipt in (
        (token_hash, "0x5", token_input, token_block_hash, token_block, token_receipt),
        (pair_hash, "0x6", pair_input, pair_block_hash, pair_block, pair_receipt),
    ):
        responses[("eth_getTransactionByHash", (tx_hash_value,))] = {
            "hash": tx_hash_value,
            "from": sender,
            "to": None,
            "nonce": nonce,
            "input": creation_input,
            "value": "0x0",
            "chainId": "0x7a69",
            "blockHash": block_hash,
            "blockNumber": hex(block_number),
        }
        responses[("eth_getTransactionReceipt", (tx_hash_value,))] = receipt
    for name, address in (
        ("token", token),
        ("pair", pair),
        ("engine", engine),
        ("coordinator", coordinator),
    ):
        responses[("eth_getCode", (address, hex(pair_block)))] = "0x" + codes[name].hex()
    expected_engine, expected_coordinator = verifier._expected_storage(facts)
    for slot, value in enumerate(expected_engine):
        responses[("eth_getStorageAt", (engine, hex(slot), hex(pair_block)))] = value
    for slot, value in enumerate(expected_coordinator):
        responses[("eth_getStorageAt", (coordinator, hex(slot), hex(pair_block)))] = value
    return {
        "candidate": candidate,
        "candidate_path": candidate_path,
        "broadcast": broadcast,
        "broadcast_path": broadcast_path,
        "pins_path": pins_path,
        "responses": responses,
        "rpc": FakeRpc(responses),
        "root": tmp_path,
        "pair": pair,
        "engine": engine,
        "coordinator": coordinator,
    }


def _verify_fixture(
    fixture: dict[str, Any], *, rpc_url: str = "http://127.0.0.1:8545"
) -> dict[str, object]:
    return verifier.verify(
        fixture["candidate_path"],
        fixture["broadcast_path"],
        fixture["pins_path"],
        fixture["rpc"],
        rpc_url=rpc_url,
        root=fixture["root"],
    )


def test_actual_post_broadcast_verifier_is_only_accepted_writer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    accepted = verifier.verify(
        fixture["candidate_path"],
        fixture["broadcast_path"],
        fixture["pins_path"],
        fixture["rpc"],
        root=fixture["root"],
    )
    candidate_schema = json.loads(CANDIDATE_SCHEMA.read_text(encoding="utf-8"))
    accepted_schema = json.loads(
        (tmp_path / verifier.EVIDENCE_SCHEMA_RELATIVE).read_text(encoding="utf-8")
    )
    jsonschema.Draft202012Validator.check_schema(candidate_schema)
    jsonschema.Draft202012Validator.check_schema(accepted_schema)
    jsonschema.validate(fixture["candidate"], candidate_schema)
    jsonschema.validate(accepted, accepted_schema)
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(fixture["candidate"], accepted_schema)
    script = (ROOT / "protocol/script/DeployPhase9Local.s.sol").read_text(encoding="utf-8")
    assert 'serializeBool(key, "activation_accepted", true)' not in script
    assert accepted["settlement_token_deployment_tx_hash"] != verifier.ZERO_HASH
    assert accepted["pair_deployment_tx_hash"] != verifier.ZERO_HASH


def test_dry_run_or_self_accepted_candidate_cannot_activate(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    dry_run = tmp_path / "dry-run/broadcast.json"
    _write_json(dry_run, fixture["broadcast"])
    with pytest.raises(verifier.VerificationError, match="broadcast input must be"):
        verifier.verify(
            fixture["candidate_path"],
            dry_run,
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )
    candidate = copy.deepcopy(fixture["candidate"])
    candidate["activation_accepted"] = True
    _write_json(fixture["candidate_path"], candidate)
    with pytest.raises(verifier.VerificationError, match="never be activation accepted"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    candidate = copy.deepcopy(fixture["candidate"])
    candidate["maximum_quote_validity"] = 3600
    _write_json(fixture["candidate_path"], candidate)
    with pytest.raises(verifier.VerificationError, match="canonical base-10"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    candidate = copy.deepcopy(fixture["candidate"])
    candidate["maximum_quote_validity"] = str(1 << 64)
    _write_json(fixture["candidate_path"], candidate)
    with pytest.raises(verifier.VerificationError, match="out of uint64 range"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    candidate = copy.deepcopy(fixture["candidate"])
    candidate["unreviewed_override"] = True
    _write_json(fixture["candidate_path"], candidate)
    with pytest.raises(verifier.VerificationError, match="candidate fields are invalid"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )


def test_receipt_and_event_substitution_reject(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["transactions"][1]["transaction"]["input"] = "0x6000"
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="creation input mismatch"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["transactions"][1]["hash"] = "0x" + "88" * 32
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="receipts must exactly match"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["receipts"][1]["blockHash"] = "0x" + "99" * 32
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="blockHash mismatch"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )

    _write_json(fixture["broadcast_path"], fixture["broadcast"])
    pair_hash = fixture["broadcast"]["transactions"][1]["hash"]
    receipt_key = ("eth_getTransactionReceipt", (pair_hash,))
    receipt = copy.deepcopy(fixture["responses"][receipt_key])
    receipt["logs"][0]["topics"][2] = _topic_address(_address(99))
    fixture["responses"][receipt_key] = receipt
    with pytest.raises(verifier.VerificationError, match="binding mismatch"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )


def test_matched_expected_observed_code_substitution_still_rejects_reviewed_pin(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    substituted_code = bytes.fromhex("60096009")
    substituted_hash = _runtime_hash(substituted_code)
    candidate = copy.deepcopy(fixture["candidate"])
    candidate["expected_pair_runtime_code_hash"] = substituted_hash
    _write_json(fixture["candidate_path"], candidate)
    block = fixture["broadcast"]["receipts"][1]["blockNumber"]
    fixture["responses"][("eth_getCode", (fixture["pair"], block))] = (
        "0x" + substituted_code.hex()
    )
    with pytest.raises(verifier.VerificationError, match="reviewed compiled artifacts"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )


def test_raw_storage_substitution_rejects_and_rejection_requires_bounded_reset(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    block = fixture["broadcast"]["receipts"][1]["blockNumber"]
    fixture["responses"][("eth_getStorageAt", (fixture["engine"], "0x3", block))] = (
        "0x" + "00" * 32
    )
    with pytest.raises(verifier.VerificationError, match="engine constructor storage"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            fixture["pins_path"],
            fixture["rpc"],
            root=fixture["root"],
        )
    rejection = verifier.rejection_payload("fixture mismatch")
    assert rejection["activation_accepted"] is False
    assert rejection["bounded_local_reset_required"] is True
    assert rejection["deployment_history_reverted"] is False


@pytest.mark.parametrize(
    "rpc_url",
    [
        "https://127.0.0.1:8545",
        "http://192.168.1.2:8545",
        "http://0.0.0.0:8545",
        "http://localtest.me:8545",
        "http://user@127.0.0.1:8545",
        "http://127.0.0.1:8545?token=secret",
        "http://127.0.0.1:8545#fragment",
        "http://127.0.0.1",
        "http://127.0.0.1:8545/rpc",
    ],
)
def test_rpc_url_rejects_nonliteral_nonloopback_or_credentialed_values(rpc_url: str) -> None:
    with pytest.raises(verifier.VerificationError):
        verifier.canonical_rpc_url(rpc_url)


def test_http_rpc_disables_proxies_and_rejects_redirects() -> None:
    rpc = verifier.HttpRpc("http://127.0.0.1:8545")
    assert isinstance(rpc._proxy_handler, urllib.request.ProxyHandler)
    assert getattr(rpc._proxy_handler, "proxies") == {}
    assert type(rpc._redirect_handler) is verifier._RejectRpcRedirects
    request = urllib.request.Request(
        "http://127.0.0.1:8545", data=b"{}", method="POST"
    )
    with pytest.raises(verifier.VerificationError, match="redirects are forbidden"):
        rpc._redirect_handler.redirect_request(
            request,
            None,
            302,
            "Found",
            {},
            "https://rpc.example.invalid/",
        )


def test_rpc_url_and_chain_id_are_canonicalized_and_bound(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    assert verifier.canonical_rpc_url("http://LOCALHOST:8545/") == "http://localhost:8545"
    assert verifier.canonical_rpc_url("http://[::1]:8545") == "http://[::1]:8545"
    fixture = deployment_fixture(tmp_path, monkeypatch)
    fixture["responses"][("eth_chainId", ())] = "0x07a69"
    with pytest.raises(verifier.VerificationError, match="canonical 0x7a69"):
        _verify_fixture(fixture)


def test_broadcast_requires_exact_two_ordered_creates_and_receipts(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)

    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["transactions"].append(copy.deepcopy(broadcast["transactions"][1]))
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="exactly two deployment transactions"):
        _verify_fixture(fixture)

    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["transactions"].reverse()
    broadcast["receipts"].reverse()
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="ordered token then pair"):
        _verify_fixture(fixture)

    broadcast = copy.deepcopy(fixture["broadcast"])
    broadcast["receipts"].append(copy.deepcopy(broadcast["receipts"][1]))
    _write_json(fixture["broadcast_path"], broadcast)
    with pytest.raises(verifier.VerificationError, match="exactly two deployment receipts"):
        _verify_fixture(fixture)


def test_rpc_transaction_receipt_and_block_identity_are_bound(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    pair_hash = fixture["broadcast"]["transactions"][1]["hash"]
    receipt_key = ("eth_getTransactionReceipt", (pair_hash,))
    transaction_key = ("eth_getTransactionByHash", (pair_hash,))
    original_receipt = copy.deepcopy(fixture["responses"][receipt_key])
    original_transaction = copy.deepcopy(fixture["responses"][transaction_key])

    substituted_receipt = copy.deepcopy(original_receipt)
    substituted_receipt["transactionHash"] = "0x" + "aa" * 32
    fixture["responses"][receipt_key] = substituted_receipt
    with pytest.raises(verifier.VerificationError, match="receipt transaction hash mismatch"):
        _verify_fixture(fixture)

    fixture["responses"][receipt_key] = original_receipt
    substituted_transaction = copy.deepcopy(original_transaction)
    substituted_transaction["blockHash"] = "0x" + "bb" * 32
    fixture["responses"][transaction_key] = substituted_transaction
    with pytest.raises(verifier.VerificationError, match="transaction/receipt block hash mismatch"):
        _verify_fixture(fixture)


def test_pin_manifest_path_and_matched_manifest_artifact_substitution_reject(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    alternate_pins = tmp_path / "alternate-pins.json"
    _write_json(alternate_pins, json.loads(fixture["pins_path"].read_text(encoding="utf-8")))
    with pytest.raises(verifier.VerificationError, match="pin manifest must be"):
        verifier.verify(
            fixture["candidate_path"],
            fixture["broadcast_path"],
            alternate_pins,
            fixture["rpc"],
            root=fixture["root"],
        )

    pair_artifact_path = tmp_path / verifier.REVIEWED_ARTIFACT_PATHS["pair"]
    pair_artifact = json.loads(pair_artifact_path.read_text(encoding="utf-8"))
    substituted_creation = bytes.fromhex("60106010")
    substituted_runtime = bytes.fromhex("60116011")
    pair_artifact["bytecode"]["object"] = "0x" + substituted_creation.hex()
    pair_artifact["deployedBytecode"]["object"] = "0x" + substituted_runtime.hex()
    _write_json(pair_artifact_path, pair_artifact)
    manifest = json.loads(fixture["pins_path"].read_text(encoding="utf-8"))
    manifest["contracts"]["pair"].update(
        {
            "creationBytes": len(substituted_creation),
            "creationCodeHash": _runtime_hash(substituted_creation),
            "runtimeBytes": len(substituted_runtime),
            "runtimeCodeHash": _runtime_hash(substituted_runtime),
        }
    )
    _write_json(fixture["pins_path"], manifest)
    with pytest.raises(verifier.VerificationError, match="reviewed SHA-256"):
        _verify_fixture(fixture)


def test_pin_check_rejects_stale_sources_and_wrong_compiler_settings(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    source_relative = next(iter(verifier.REVIEWED_COMPILATION_TARGETS["engine"]))
    source_path = tmp_path / "protocol" / source_relative
    original_source = source_path.read_bytes()
    source_path.write_bytes(original_source + b"// stale\n")
    with pytest.raises(verifier.VerificationError, match="compiled artifact is stale"):
        verifier.load_reviewed_hashes(fixture["pins_path"], fixture["root"])

    source_path.write_bytes(original_source)
    artifact_path = tmp_path / verifier.REVIEWED_ARTIFACT_PATHS["engine"]
    artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
    artifact["metadata"]["settings"]["optimizer"]["runs"] = 1
    _write_json(artifact_path, artifact)
    with pytest.raises(verifier.VerificationError, match="compiler settings"):
        verifier.load_reviewed_hashes(fixture["pins_path"], fixture["root"])


@pytest.mark.parametrize(
    "artifact_path",
    ["../outside.json", "C:/outside.json", "protocol/out/../outside.json"],
)
def test_artifact_paths_reject_absolute_or_traversal(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    artifact_path: str,
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    manifest = json.loads(fixture["pins_path"].read_text(encoding="utf-8"))
    manifest["contracts"]["pair"]["artifactPath"] = artifact_path
    _write_json(fixture["pins_path"], manifest)
    monkeypatch.setattr(
        verifier, "REVIEWED_PIN_MANIFEST_SHA256", verifier._sha256_file(fixture["pins_path"])
    )
    with pytest.raises(verifier.VerificationError, match="artifactPath is invalid"):
        verifier.load_reviewed_hashes(fixture["pins_path"], fixture["root"])


def test_symlinked_artifact_path_rejects(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    artifact_path = (tmp_path / verifier.REVIEWED_ARTIFACT_PATHS["pair"]).absolute()
    original_is_symlink = Path.is_symlink

    def reports_reviewed_artifact_as_symlink(path: Path) -> bool:
        return path.absolute() == artifact_path or original_is_symlink(path)

    monkeypatch.setattr(Path, "is_symlink", reports_reviewed_artifact_as_symlink)
    with pytest.raises(verifier.VerificationError, match="symlinked path components"):
        verifier.load_reviewed_hashes(fixture["pins_path"], fixture["root"])


@pytest.mark.parametrize("value", [True, -1, "0x00", "0xA", "01", "-1", "0X1"])
def test_quantities_reject_bool_negative_and_noncanonical_forms(value: object) -> None:
    with pytest.raises(verifier.VerificationError):
        verifier._quantity(value, "fixture quantity")


def test_duplicate_json_and_out_of_scope_output_reject_without_deletion(tmp_path: Path) -> None:
    duplicate = tmp_path / "duplicate.json"
    duplicate.write_text('{"chain":31337,"chain":1}', encoding="utf-8")
    with pytest.raises(verifier.VerificationError, match="duplicate JSON key"):
        verifier._read_json(duplicate)

    repository = tmp_path / "repository"
    repository.mkdir()
    outside = tmp_path / "do-not-delete.json"
    outside.write_text("preserve", encoding="utf-8")
    with pytest.raises(verifier.VerificationError, match="must remain inside"):
        verifier._canonical_repo_file(
            outside,
            verifier.ACCEPTED_RELATIVE,
            repository,
            "accepted output",
            must_exist=False,
        )
    assert outside.read_text(encoding="utf-8") == "preserve"


def test_final_accepted_payload_must_validate_against_reviewed_schema(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    accepted = _verify_fixture(fixture)
    assert accepted["rpc_url"] == "http://127.0.0.1:8545"
    assert accepted["rpc_chain_id"] == "0x7a69"
    assert accepted["pin_manifest_sha256"] == verifier.REVIEWED_PIN_MANIFEST_SHA256
    invalid = dict(accepted)
    invalid["rpc_url"] = "http://192.168.1.2:8545"
    with pytest.raises(verifier.VerificationError, match="does not satisfy schema"):
        verifier.validate_accepted_evidence(invalid, fixture["root"])


def test_cli_pin_only_mode_is_network_free_and_out_of_scope_output_survives(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fixture = deployment_fixture(tmp_path, monkeypatch)
    monkeypatch.setattr(verifier, "ROOT", tmp_path)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "verify_phase9_payoff_deployment.py",
            "--check-pins",
            "--pins",
            str(fixture["pins_path"]),
        ],
    )
    assert verifier.main() == 0

    outside = tmp_path.parent / f"{tmp_path.name}-preserve.json"
    outside.write_text("preserve", encoding="utf-8")
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "verify_phase9_payoff_deployment.py",
            "--candidate",
            str(fixture["candidate_path"]),
            "--broadcast",
            str(fixture["broadcast_path"]),
            "--rpc-url",
            "http://127.0.0.1:8545",
            "--pins",
            str(fixture["pins_path"]),
            "--output",
            str(outside),
            "--rejection-output",
            str(tmp_path / verifier.REJECTION_RELATIVE),
        ],
    )
    assert verifier.main() == 1
    assert outside.read_text(encoding="utf-8") == "preserve"
