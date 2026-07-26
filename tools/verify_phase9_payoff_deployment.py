from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any, NoReturn, TypedDict

import jsonschema
from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[1]
PIN_MANIFEST_RELATIVE = Path("infrastructure/local/phase9-payoff-deployment-code-hashes.json")
CANDIDATE_RELATIVE = Path("protocol/deployments/local/phase9-payoff-deployment-candidate.json")
BROADCAST_RELATIVE = Path("protocol/broadcast/DeployPhase9Local.s.sol/31337/run-latest.json")
ACCEPTED_RELATIVE = Path("protocol/deployments/local/phase9-payoff-deployment-evidence.json")
REJECTION_RELATIVE = Path("protocol/deployments/local/phase9-payoff-deployment-rejection.json")
EVIDENCE_SCHEMA_RELATIVE = Path(
    "infrastructure/local/phase9-payoff-deployment-evidence.schema.json"
)
DEFAULT_PINS = ROOT / PIN_MANIFEST_RELATIVE
REVIEWED_PIN_MANIFEST_SHA256 = (
    "sha256:c2486f4fbb36ae30c1b75be4f0b7b48da340f9c2c0c542458aa0ce135f92ff0d"
)
REVIEWED_ARTIFACT_PATHS = {
    "token": "protocol/out/Phase9LocalSyntheticToken.sol/Phase9LocalSyntheticToken.json",
    "engine": "protocol/out/PayoffQuoteEngine.sol/PayoffQuoteEngine.json",
    "coordinator": "protocol/out/RefinanceCoordinator.sol/RefinanceCoordinator.json",
    "pair": "protocol/out/DeployPhase9Local.s.sol/Phase9PayoffPairDeployer.json",
}
REVIEWED_COMPILATION_TARGETS = {
    "token": {"src/token/Phase9LocalSyntheticToken.sol": "Phase9LocalSyntheticToken"},
    "engine": {"src/resolution/PayoffQuoteEngine.sol": "PayoffQuoteEngine"},
    "coordinator": {"src/resolution/RefinanceCoordinator.sol": "RefinanceCoordinator"},
    "pair": {"script/DeployPhase9Local.s.sol": "Phase9PayoffPairDeployer"},
}
REVIEWED_COMPILER = {
    "solidity": "0.8.36",
    "optimizerEnabled": True,
    "optimizerRuns": 200,
    "evmVersion": "prague",
    "foundry": "1.7.1",
    "openzeppelin": "5.6.1",
}
RpcCall = Callable[[str, list[object]], object]


class DeploymentIdentity(TypedDict):
    txHash: str
    inputHash: str
    sender: str
    nonce: int
    blockHash: str
    blockNumber: int
    receipt: Mapping[str, Any]

ZERO_HASH = "0x" + "00" * 32
PAIR_EVENT_SIGNATURE = "PayoffPairDeployed(address,address,address,uint64)"
PAIR_EVENT_TOPIC = ""
RESET_COMMAND = "pwsh ./scripts/local-reset.ps1"
CANDIDATE_FIELDS = frozenset(
    {
        "schema_version",
        "artifact_type",
        "environment",
        "contains_real_value",
        "chain_id",
        "activation_accepted",
        "post_broadcast_verification_required",
        "deployment_history_reverted",
        "pair_deployer",
        "engine_create_nonce",
        "loan_registry",
        "phase9_loan_factory",
        "quote_policy_registry",
        "lien_registry",
        "asset_registry",
        "refinance_policy_registry",
        "emergency_controller",
        "treasury_fee_recipient",
        "fixture_allocator",
        "maximum_quote_validity",
        "settlement_token",
        "predicted_engine",
        "predicted_coordinator",
        "configuration_hash",
        "engine_constructor_args_hash",
        "coordinator_constructor_args_hash",
        "deployment_call_hash",
        "expected_token_runtime_code_hash",
        "expected_engine_runtime_code_hash",
        "expected_coordinator_runtime_code_hash",
        "expected_pair_runtime_code_hash",
    }
)


class VerificationError(ValueError):
    pass


class _RejectRpcRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> NoReturn:
        del req, fp, code, msg, headers, newurl
        _fail("RPC redirects are forbidden")


def _keccak(data: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(data)
    return digest.digest()


PAIR_EVENT_TOPIC = "0x" + _keccak(PAIR_EVENT_SIGNATURE.encode()).hex()


def _fail(message: str) -> NoReturn:
    raise VerificationError(message)


def _parse_json(data: str | bytes, label: str) -> object:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                _fail(f"{label} contains duplicate JSON key {key!r}")
            result[key] = value
        return result

    return json.loads(data, object_pairs_hook=reject_duplicates)


def _read_json(path: Path) -> dict[str, Any]:
    payload = _parse_json(path.read_text(encoding="utf-8"), str(path))
    if not isinstance(payload, dict):
        _fail(f"{path} must contain a JSON object")
    return payload


def _write_json(path: Path, payload: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("x", encoding="utf-8") as output:
        output.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def _sha256_file(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _reject_symlink_components(path: Path, root: Path, label: str) -> None:
    root_absolute = root.absolute()
    path_absolute = path.absolute()
    try:
        relative = path_absolute.relative_to(root_absolute)
    except ValueError as exc:
        raise VerificationError(f"{label} must remain inside the repository") from exc
    current = root_absolute
    for part in relative.parts:
        current /= part
        if current.is_symlink():
            _fail(f"{label} must not use symlinked path components")


def _canonical_repo_file(
    path: Path,
    expected_relative: Path,
    root: Path,
    label: str,
    *,
    must_exist: bool,
) -> Path:
    root = root.resolve(strict=True)
    expected = root / expected_relative
    supplied = path if path.is_absolute() else root / path
    if any(part == ".." for part in path.parts):
        _fail(f"{label} must not contain traversal")
    _reject_symlink_components(supplied, root, label)
    if must_exist:
        resolved = supplied.resolve(strict=True)
        expected_resolved = expected.resolve(strict=True)
    else:
        resolved = supplied.resolve(strict=False)
        expected_resolved = expected.resolve(strict=False)
    if resolved != expected_resolved:
        _fail(f"{label} must be {expected_relative.as_posix()}")
    return expected_resolved


def canonical_rpc_url(url: str) -> str:
    if not isinstance(url, str) or not url or url != url.strip():
        _fail("RPC URL must be a nonempty literal URL")
    if "?" in url or "#" in url:
        _fail("RPC URL must not contain a query or fragment")
    try:
        parsed = urllib.parse.urlsplit(url)
        port = parsed.port
    except ValueError as exc:
        raise VerificationError("RPC URL has an invalid port or host") from exc
    if parsed.scheme != "http":
        _fail("RPC URL must use loopback HTTP")
    if parsed.username is not None or parsed.password is not None:
        _fail("RPC URL must not contain credentials")
    if parsed.path not in {"", "/"}:
        _fail("RPC URL must not contain an RPC path")
    if parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        _fail("RPC URL host must be literal loopback")
    if port is None:
        _fail("RPC URL must contain an explicit port")
    if port == 0:
        _fail("RPC URL port must be between 1 and 65535")
    host = "[::1]" if parsed.hostname == "::1" else parsed.hostname
    return f"http://{host}:{port}"


def _hex(value: object, byte_length: int, label: str) -> str:
    if not isinstance(value, str) or not value.startswith("0x"):
        _fail(f"{label} must be 0x-prefixed hex")
    body = value[2:]
    if len(body) != byte_length * 2:
        _fail(f"{label} must be {byte_length} bytes")
    try:
        bytes.fromhex(body)
    except ValueError as exc:
        raise VerificationError(f"{label} contains non-hex characters") from exc
    return "0x" + body.lower()


def _address(value: object, label: str) -> str:
    result = _hex(value, 20, label)
    if result == "0x" + "00" * 20:
        _fail(f"{label} must be nonzero")
    return result


def _hash(value: object, label: str, *, nonzero: bool = True) -> str:
    result = _hex(value, 32, label)
    if nonzero and result == ZERO_HASH:
        _fail(f"{label} must be nonzero")
    return result


def _hex_blob(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.startswith("0x"):
        _fail(f"{label} must be 0x-prefixed hex")
    body = value[2:]
    if len(body) % 2 != 0:
        _fail(f"{label} must contain whole bytes")
    try:
        bytes.fromhex(body)
    except ValueError as exc:
        raise VerificationError(f"{label} contains non-hex characters") from exc
    return "0x" + body.lower()


def _quantity(value: object, label: str) -> int:
    if type(value) is int:
        if value < 0:
            _fail(f"{label} must be nonnegative")
        return value
    if not isinstance(value, str):
        _fail(f"{label} must be an integer or hex quantity")
    if value == "0x0":
        return 0
    if value.startswith("0x"):
        body = value[2:]
        if (
            not body
            or body.startswith("0")
            or any(character not in "0123456789abcdef" for character in body)
        ):
            _fail(f"{label} is not a canonical hex quantity")
        return int(body, 16)
    if value == "0":
        return 0
    if not value or value.startswith("0") or not value.isascii() or not value.isdecimal():
        _fail(f"{label} is not a canonical decimal quantity")
    return int(value, 10)


def _word_address(value: str) -> bytes:
    return bytes(12) + bytes.fromhex(value[2:])


def _word_uint(value: int) -> bytes:
    if value < 0 or value >= 1 << 256:
        _fail("ABI integer is out of range")
    return value.to_bytes(32, "big")


def _word_hash(value: str) -> bytes:
    return bytes.fromhex(_hash(value, "ABI bytes32", nonzero=False)[2:])


def _fact_int(facts: Mapping[str, object], field: str) -> int:
    value = facts[field]
    if not isinstance(value, int):
        _fail(f"{field} must be an integer")
    return value


def _abi_hash(domain: str, words: list[bytes]) -> str:
    return "0x" + _keccak(_keccak(domain.encode()) + b"".join(words)).hex()


def _create_address(deployer: str, nonce: int) -> str:
    if nonce < 1 or nonce > 0x7F:
        _fail("only single-byte nonzero CREATE nonces are supported")
    encoded = bytes((0xD6, 0x94)) + bytes.fromhex(deployer[2:]) + bytes((nonce,))
    return "0x" + _keccak(encoded)[12:].hex()


def _candidate_facts(candidate: Mapping[str, Any]) -> dict[str, object]:
    if set(candidate) != CANDIDATE_FIELDS:
        missing = sorted(CANDIDATE_FIELDS - set(candidate))
        extra = sorted(set(candidate) - CANDIDATE_FIELDS)
        _fail(f"candidate fields are invalid (missing={missing}, extra={extra})")
    if type(candidate.get("schema_version")) is not int or candidate["schema_version"] != 1:
        _fail("candidate schema_version must be one")
    if candidate.get("artifact_type") != "PHASE9_PAYOFF_DEPLOYMENT_CANDIDATE":
        _fail("candidate artifact_type is invalid")
    if candidate.get("environment") != "local" or candidate.get("contains_real_value") is not False:
        _fail("candidate is not local non-value evidence")
    if candidate.get("activation_accepted") is not False:
        _fail("a deployment candidate can never be activation accepted")
    if candidate.get("post_broadcast_verification_required") is not True:
        _fail("candidate must require post-broadcast verification")
    if candidate.get("deployment_history_reverted") is not False:
        _fail("candidate must not claim deployment history was reverted")
    if type(candidate.get("chain_id")) is not int or candidate["chain_id"] != 31337:
        _fail("candidate chain must be 31337")
    if (
        type(candidate.get("engine_create_nonce")) is not int
        or candidate["engine_create_nonce"] != 1
    ):
        _fail("engine CREATE nonce must be one")

    address_fields = (
        "pair_deployer",
        "loan_registry",
        "phase9_loan_factory",
        "quote_policy_registry",
        "lien_registry",
        "asset_registry",
        "refinance_policy_registry",
        "emergency_controller",
        "treasury_fee_recipient",
        "fixture_allocator",
        "settlement_token",
        "predicted_engine",
        "predicted_coordinator",
    )
    facts: dict[str, object] = {
        field: _address(candidate.get(field), field) for field in address_fields
    }
    validity_value = candidate.get("maximum_quote_validity")
    if (
        not isinstance(validity_value, str)
        or not validity_value.isascii()
        or not validity_value.isdecimal()
        or validity_value.startswith("0")
    ):
        _fail("maximum_quote_validity must be a canonical base-10 decimal string")
    validity = _quantity(validity_value, "maximum_quote_validity")
    if validity < 1 or validity >= 1 << 64:
        _fail("maximum_quote_validity is out of uint64 range")
    facts["maximum_quote_validity"] = validity
    for field in (
        "configuration_hash",
        "engine_constructor_args_hash",
        "coordinator_constructor_args_hash",
        "deployment_call_hash",
        "expected_token_runtime_code_hash",
        "expected_engine_runtime_code_hash",
        "expected_coordinator_runtime_code_hash",
        "expected_pair_runtime_code_hash",
    ):
        facts[field] = _hash(candidate.get(field), field)
    return facts


def _configuration_hash(facts: Mapping[str, object]) -> str:
    return _abi_hash(
        "UNIFIED_PHASE9_PAYOFF_DEPLOYMENT_CONFIGURATION_V1",
        [
            _word_uint(31337),
            *[
                _word_address(str(facts[field]))
                for field in (
                    "loan_registry",
                    "phase9_loan_factory",
                    "quote_policy_registry",
                    "lien_registry",
                    "asset_registry",
                    "refinance_policy_registry",
                    "emergency_controller",
                    "treasury_fee_recipient",
                    "fixture_allocator",
                )
            ],
            _word_uint(_fact_int(facts, "maximum_quote_validity")),
            _word_address(str(facts["settlement_token"])),
        ],
    )


def _engine_args_hash(facts: Mapping[str, object]) -> str:
    return _abi_hash(
        "UNIFIED_PHASE9_PAYOFF_ENGINE_CONSTRUCTOR_ARGS_V1",
        [
            _word_address(str(facts["loan_registry"])),
            _word_address(str(facts["quote_policy_registry"])),
            _word_uint(_fact_int(facts, "maximum_quote_validity")),
            _word_address(str(facts["phase9_loan_factory"])),
            _word_address(str(facts["predicted_coordinator"])),
        ],
    )


def _coordinator_args_hash(facts: Mapping[str, object]) -> str:
    return _abi_hash(
        "UNIFIED_PHASE9_REFINANCE_COORDINATOR_CONSTRUCTOR_ARGS_V1",
        [
            _word_address(str(facts["loan_registry"])),
            _word_address(str(facts["phase9_loan_factory"])),
            _word_address(str(facts["predicted_engine"])),
            _word_address(str(facts["lien_registry"])),
            _word_address(str(facts["asset_registry"])),
            _word_address(str(facts["refinance_policy_registry"])),
            _word_address(str(facts["emergency_controller"])),
            _word_address(str(facts["treasury_fee_recipient"])),
            _word_address(str(facts["settlement_token"])),
        ],
    )


def _deployment_call_hash(facts: Mapping[str, object]) -> str:
    return _abi_hash(
        "UNIFIED_PHASE9_PAYOFF_DEPLOYMENT_CALL_V1",
        [
            _word_uint(31337),
            _word_address(str(facts["pair_deployer"])),
            _word_uint(1),
            _word_address(str(facts["predicted_engine"])),
            _word_address(str(facts["predicted_coordinator"])),
            _word_hash(str(facts["configuration_hash"])),
            _word_hash(str(facts["engine_constructor_args_hash"])),
            _word_hash(str(facts["coordinator_constructor_args_hash"])),
        ],
    )


def _artifact_codes(artifact_path: Path, root: Path, name: str) -> tuple[str, int, str, int]:
    artifact = _read_json(artifact_path)
    metadata = artifact.get("metadata")
    if not isinstance(metadata, dict):
        _fail(f"{artifact_path} has no compiler metadata")
    compiler = metadata.get("compiler")
    settings = metadata.get("settings")
    if not isinstance(compiler, dict) or not isinstance(settings, dict):
        _fail(f"{artifact_path} compiler metadata is malformed")
    compiler_version = compiler.get("version")
    if not isinstance(compiler_version, str) or compiler_version.split("+", 1)[0] != "0.8.36":
        _fail(f"{artifact_path} was not compiled with Solidity 0.8.36")
    optimizer = settings.get("optimizer")
    if (
        not isinstance(optimizer, dict)
        or optimizer.get("enabled") is not True
        or optimizer.get("runs") != 200
        or settings.get("evmVersion") != "prague"
        or settings.get("compilationTarget") != REVIEWED_COMPILATION_TARGETS[name]
    ):
        _fail(f"{artifact_path} compiler settings do not match the reviewed profile")
    sources = metadata.get("sources")
    if not isinstance(sources, dict) or not sources:
        _fail(f"{artifact_path} has no compiler source manifest")
    for source_relative, source_metadata in sources.items():
        if (
            not isinstance(source_relative, str)
            or not isinstance(source_metadata, dict)
            or Path(source_relative).is_absolute()
            or "\\" in source_relative
            or ".." in Path(source_relative).parts
        ):
            _fail(f"{artifact_path} contains an invalid compiler source path")
        source_path = _canonical_repo_file(
            root / "protocol" / source_relative,
            Path("protocol") / source_relative,
            root,
            f"compiler source {source_relative}",
            must_exist=True,
        )
        expected_source_hash = _hash(
            source_metadata.get("keccak256"), f"compiler source {source_relative} hash"
        )
        actual_source_hash = "0x" + _keccak(source_path.read_bytes()).hex()
        if actual_source_hash != expected_source_hash:
            _fail(f"compiled artifact is stale for source {source_relative}")
    creation = artifact.get("bytecode")
    deployed = artifact.get("deployedBytecode")
    if not isinstance(creation, dict) or not isinstance(deployed, dict):
        _fail(f"{artifact_path} has no creation or deployed bytecode")
    creation_hex = _hex_blob(creation.get("object"), f"{artifact_path} creation bytecode")
    runtime_hex = _hex_blob(deployed.get("object"), f"{artifact_path} deployed bytecode")
    creation_code = bytes.fromhex(creation_hex[2:])
    runtime_code = bytes.fromhex(runtime_hex[2:])
    if not creation_code or not runtime_code:
        _fail(f"{artifact_path} bytecode is empty")
    return (
        "0x" + _keccak(runtime_code).hex(),
        len(runtime_code),
        "0x" + _keccak(creation_code).hex(),
        len(creation_code),
    )


def load_reviewed_hashes(pins_path: Path, root: Path = ROOT) -> dict[str, dict[str, object]]:
    root = root.resolve(strict=True)
    pins_path = _canonical_repo_file(
        pins_path, PIN_MANIFEST_RELATIVE, root, "pin manifest", must_exist=True
    )
    manifest_sha256 = _sha256_file(pins_path)
    if manifest_sha256 != REVIEWED_PIN_MANIFEST_SHA256:
        _fail("canonical pin manifest does not match the reviewed SHA-256")
    pins = _read_json(pins_path)
    contracts = pins.get("contracts")
    if (
        pins.get("schemaVersion") != 1
        or pins.get("compiler") != REVIEWED_COMPILER
        or not isinstance(contracts, dict)
        or set(contracts) != set(REVIEWED_ARTIFACT_PATHS)
    ):
        _fail("reviewed code-hash pins are malformed")
    result: dict[str, dict[str, object]] = {}
    for name in ("token", "engine", "coordinator", "pair"):
        entry = contracts.get(name)
        if not isinstance(entry, dict):
            _fail(f"reviewed code-hash pin is missing {name}")
        artifact_relative = entry.get("artifactPath")
        if (
            not isinstance(artifact_relative, str)
            or artifact_relative != REVIEWED_ARTIFACT_PATHS[name]
            or Path(artifact_relative).is_absolute()
            or "\\" in artifact_relative
            or ".." in Path(artifact_relative).parts
        ):
            _fail(f"reviewed {name} artifactPath is invalid")
        artifact_path = _canonical_repo_file(
            root / artifact_relative,
            Path(REVIEWED_ARTIFACT_PATHS[name]),
            root,
            f"reviewed {name} artifact",
            must_exist=True,
        )
        actual_hash, actual_bytes, actual_creation_hash, actual_creation_bytes = _artifact_codes(
            artifact_path, root, name
        )
        pinned_hash = _hash(entry.get("runtimeCodeHash"), f"pins.{name}.runtimeCodeHash")
        pinned_bytes = _quantity(entry.get("runtimeBytes"), f"pins.{name}.runtimeBytes")
        pinned_creation_hash = _hash(
            entry.get("creationCodeHash"), f"pins.{name}.creationCodeHash"
        )
        pinned_creation_bytes = _quantity(
            entry.get("creationBytes"), f"pins.{name}.creationBytes"
        )
        if actual_hash != pinned_hash or actual_bytes != pinned_bytes:
            _fail(f"reviewed {name} pin does not match the compiled artifact")
        if (
            actual_creation_hash != pinned_creation_hash
            or actual_creation_bytes != pinned_creation_bytes
        ):
            _fail(f"reviewed {name} creation pin does not match the compiled artifact")
        artifact = _read_json(artifact_path)
        creation = artifact["bytecode"]
        result[name] = {
            "artifactPath": artifact_relative,
            "runtimeCodeHash": pinned_hash,
            "runtimeBytes": pinned_bytes,
            "creationCodeHash": pinned_creation_hash,
            "creationBytes": pinned_creation_bytes,
            "creationCode": _hex_blob(
                creation["object"], f"{artifact_relative} creation bytecode"
            ),
        }
    result["_manifest"] = {"sha256": manifest_sha256}
    return result


def _transaction(artifact: Mapping[str, Any], contract_name: str) -> Mapping[str, Any]:
    transactions = artifact.get("transactions")
    if not isinstance(transactions, list):
        _fail("broadcast artifact has no transactions array")
    matches = [
        item
        for item in transactions
        if isinstance(item, dict) and item.get("contractName") == contract_name
    ]
    if len(matches) != 1:
        _fail(f"broadcast must contain exactly one {contract_name} transaction")
    return matches[0]


def _validate_broadcast_shape(artifact: Mapping[str, Any]) -> None:
    transactions = artifact.get("transactions")
    receipts = artifact.get("receipts")
    if not isinstance(transactions, list) or len(transactions) != 2:
        _fail("broadcast must contain exactly two deployment transactions")
    if not isinstance(receipts, list) or len(receipts) != 2:
        _fail("broadcast must contain exactly two deployment receipts")
    expected_names = ["Phase9LocalSyntheticToken", "Phase9PayoffPairDeployer"]
    transaction_hashes: list[str] = []
    for index, expected_name in enumerate(expected_names):
        transaction = transactions[index]
        if (
            not isinstance(transaction, dict)
            or transaction.get("contractName") != expected_name
            or transaction.get("transactionType") != "CREATE"
        ):
            _fail("broadcast CREATE transactions must be ordered token then pair")
        transaction_hashes.append(_hash(transaction.get("hash"), f"transactions[{index}].hash"))
    receipt_hashes: list[str] = []
    for index, receipt in enumerate(receipts):
        if not isinstance(receipt, dict):
            _fail("broadcast receipts must be JSON objects")
        receipt_hashes.append(
            _hash(receipt.get("transactionHash"), f"receipts[{index}].transactionHash")
        )
    if receipt_hashes != transaction_hashes:
        _fail("broadcast receipts must exactly match the two ordered CREATE transactions")


def _receipt(artifact: Mapping[str, Any], tx_hash: str) -> Mapping[str, Any]:
    receipts = artifact.get("receipts")
    if not isinstance(receipts, list):
        _fail("broadcast artifact has no receipts array")
    matches = [
        item
        for item in receipts
        if isinstance(item, dict)
        and _hash(item.get("transactionHash"), "receipt.transactionHash") == tx_hash
    ]
    if len(matches) != 1:
        _fail(f"broadcast must contain exactly one receipt for {tx_hash}")
    return matches[0]


def _rpc_transaction(rpc: RpcCall, tx_hash: str) -> Mapping[str, Any]:
    result = rpc("eth_getTransactionByHash", [tx_hash])
    if not isinstance(result, dict):
        _fail(f"RPC has no transaction {tx_hash}")
    return result


def _rpc_receipt(rpc: RpcCall, tx_hash: str) -> Mapping[str, Any]:
    result = rpc("eth_getTransactionReceipt", [tx_hash])
    if not isinstance(result, dict):
        _fail(f"RPC has no receipt {tx_hash}")
    return result


def _checked_deployment(
    broadcast: Mapping[str, Any],
    rpc: RpcCall,
    contract_name: str,
    expected_address: str,
    expected_input: str,
) -> DeploymentIdentity:
    entry = _transaction(broadcast, contract_name)
    tx_hash = _hash(entry.get("hash"), f"{contract_name}.hash")
    if entry.get("transactionType") != "CREATE":
        _fail(f"{contract_name} must be a CREATE transaction")
    broadcast_address = _address(
        entry.get("contractAddress"), f"{contract_name}.contractAddress"
    )
    if broadcast_address != expected_address:
        _fail(f"{contract_name} broadcast address mismatch")
    transaction = entry.get("transaction")
    if not isinstance(transaction, dict):
        _fail(f"{contract_name} broadcast transaction payload is missing")
    sender = _address(transaction.get("from"), f"{contract_name}.from")
    nonce = _quantity(transaction.get("nonce"), f"{contract_name}.nonce")
    if _quantity(transaction.get("chainId"), f"{contract_name}.chainId") != 31337:
        _fail(f"{contract_name} broadcast transaction chain mismatch")
    broadcast_input = _hex_blob(transaction.get("input"), f"{contract_name}.input")
    if broadcast_input != expected_input:
        _fail(f"{contract_name} broadcast creation input mismatch")
    if _quantity(transaction.get("value"), f"{contract_name}.value") != 0:
        _fail(f"{contract_name} broadcast transaction value must be zero")

    broadcast_receipt = _receipt(broadcast, tx_hash)
    rpc_tx = _rpc_transaction(rpc, tx_hash)
    rpc_receipt = _rpc_receipt(rpc, tx_hash)
    if _hash(rpc_tx.get("hash"), "RPC transaction hash") != tx_hash:
        _fail(f"{contract_name} RPC transaction hash mismatch")
    if _address(rpc_tx.get("from"), "RPC transaction sender") != sender:
        _fail(f"{contract_name} RPC sender mismatch")
    if _quantity(rpc_tx.get("nonce"), "RPC transaction nonce") != nonce:
        _fail(f"{contract_name} RPC nonce mismatch")
    if _quantity(rpc_tx.get("chainId"), "RPC transaction chainId") != 31337:
        _fail(f"{contract_name} RPC transaction chain mismatch")
    if rpc_tx.get("to") is not None:
        _fail(f"{contract_name} RPC transaction is not contract creation")
    if _hex_blob(rpc_tx.get("input"), "RPC transaction input") != expected_input:
        _fail(f"{contract_name} RPC creation input mismatch")
    if _quantity(rpc_tx.get("value"), "RPC transaction value") != 0:
        _fail(f"{contract_name} RPC transaction value must be zero")
    if _hash(rpc_receipt.get("transactionHash"), "RPC receipt transactionHash") != tx_hash:
        _fail(f"{contract_name} RPC receipt transaction hash mismatch")
    if _quantity(rpc_receipt.get("status"), "RPC receipt status") != 1:
        _fail(f"{contract_name} deployment receipt did not succeed")
    block_hash = _hash(rpc_receipt.get("blockHash"), "RPC receipt blockHash")
    block_number = _quantity(rpc_receipt.get("blockNumber"), "RPC receipt blockNumber")
    if _hash(rpc_tx.get("blockHash"), "RPC transaction blockHash") != block_hash:
        _fail(f"{contract_name} RPC transaction/receipt block hash mismatch")
    if _quantity(rpc_tx.get("blockNumber"), "RPC transaction blockNumber") != block_number:
        _fail(f"{contract_name} RPC transaction/receipt block number mismatch")
    receipt_address = _address(
        rpc_receipt.get("contractAddress"), "RPC receipt contractAddress"
    )
    if receipt_address != expected_address:
        _fail(f"{contract_name} RPC receipt address mismatch")
    if _address(rpc_receipt.get("from"), "RPC receipt sender") != sender:
        _fail(f"{contract_name} RPC receipt sender mismatch")
    if rpc_receipt.get("to") is not None:
        _fail(f"{contract_name} RPC receipt is not contract creation")
    for field, expected in (
        ("transactionHash", tx_hash),
        ("blockHash", block_hash),
    ):
        if _hash(broadcast_receipt.get(field), f"broadcast receipt {field}") != expected:
            _fail(f"{contract_name} broadcast/RPC receipt {field} mismatch")
    if _quantity(broadcast_receipt.get("status"), "broadcast receipt status") != 1:
        _fail(f"{contract_name} broadcast receipt did not succeed")
    if (
        _address(broadcast_receipt.get("contractAddress"), "broadcast receipt contractAddress")
        != expected_address
    ):
        _fail(f"{contract_name} broadcast/RPC receipt contract address mismatch")
    broadcast_block_number = _quantity(
        broadcast_receipt.get("blockNumber"), "broadcast receipt blockNumber"
    )
    if broadcast_block_number != block_number:
        _fail(f"{contract_name} broadcast/RPC block number mismatch")
    return {
        "txHash": tx_hash,
        "inputHash": "0x" + _keccak(bytes.fromhex(expected_input[2:])).hex(),
        "sender": sender,
        "nonce": nonce,
        "blockHash": block_hash,
        "blockNumber": block_number,
        "receipt": rpc_receipt,
    }


def _rpc_code(rpc: RpcCall, address: str, block: int, label: str) -> tuple[str, int]:
    result = rpc("eth_getCode", [address, hex(block)])
    if not isinstance(result, str) or not result.startswith("0x"):
        _fail(f"RPC code response for {label} is invalid")
    code = bytes.fromhex(result[2:])
    if not code:
        _fail(f"RPC code for {label} is empty")
    return "0x" + _keccak(code).hex(), len(code)


def _storage(rpc: RpcCall, address: str, slot: int, block: int) -> str:
    value = rpc("eth_getStorageAt", [address, hex(slot), hex(block)])
    return _hash(value, f"storage {address}[{slot}]", nonzero=False)


def _expected_storage(facts: Mapping[str, object]) -> tuple[list[str], list[str]]:
    def address_word(field: str) -> str:
        return "0x" + _word_address(str(facts[field])).hex()

    policy = int(str(facts["quote_policy_registry"]), 16)
    packed = policy | (_fact_int(facts, "maximum_quote_validity") << 160)
    engine = [
        address_word("loan_registry"),
        "0x" + packed.to_bytes(32, "big").hex(),
        address_word("phase9_loan_factory"),
        address_word("predicted_coordinator"),
    ]
    coordinator = [
        address_word("loan_registry"),
        address_word("phase9_loan_factory"),
        address_word("predicted_engine"),
        address_word("lien_registry"),
        address_word("asset_registry"),
        address_word("refinance_policy_registry"),
        address_word("emergency_controller"),
        address_word("treasury_fee_recipient"),
        address_word("settlement_token"),
    ]
    return engine, coordinator


def _verify_event(receipt: Mapping[str, Any], facts: Mapping[str, object]) -> dict[str, object]:
    logs = receipt.get("logs")
    if not isinstance(logs, list):
        _fail("pair receipt has no logs")
    matches: list[Mapping[str, Any]] = []
    for item in logs:
        if not isinstance(item, dict) or not isinstance(item.get("topics"), list):
            continue
        topics = item["topics"]
        if topics and str(topics[0]).lower() == PAIR_EVENT_TOPIC:
            matches.append(item)
    if len(matches) != 1:
        _fail("pair receipt must contain exactly one PayoffPairDeployed event")
    log = matches[0]
    if _address(log.get("address"), "pair event emitter") != facts["pair_deployer"]:
        _fail("pair event emitter mismatch")
    topics = log["topics"]
    if len(topics) != 4:
        _fail("PayoffPairDeployed indexed topics are malformed")
    decoded = ["0x" + _hash(topic, "event topic", nonzero=False)[-40:] for topic in topics[1:]]
    expected = [facts["pair_deployer"], facts["predicted_engine"], facts["predicted_coordinator"]]
    if decoded != expected:
        _fail("PayoffPairDeployed binding mismatch")
    event_data = _hash(
        log.get("data"), "PayoffPairDeployed engine nonce", nonzero=False
    )
    if int(event_data, 16) != 1:
        _fail("PayoffPairDeployed engine CREATE nonce mismatch")
    return {"topic0": PAIR_EVENT_TOPIC, "emitter": facts["pair_deployer"], "engineCreateNonce": 1}


def _expected_creation_inputs(
    facts: Mapping[str, object], pins: Mapping[str, Mapping[str, object]]
) -> tuple[str, str]:
    token_args = _word_address(str(facts["fixture_allocator"]))
    pair_args = b"".join(
        [
            *[
                _word_address(str(facts[field]))
                for field in (
                    "loan_registry",
                    "phase9_loan_factory",
                    "quote_policy_registry",
                    "lien_registry",
                    "asset_registry",
                    "refinance_policy_registry",
                    "emergency_controller",
                    "treasury_fee_recipient",
                    "fixture_allocator",
                )
            ],
            _word_uint(_fact_int(facts, "maximum_quote_validity")),
            _word_address(str(facts["settlement_token"])),
        ]
    )
    return (
        str(pins["token"]["creationCode"]) + token_args.hex(),
        str(pins["pair"]["creationCode"]) + pair_args.hex(),
    )


def validate_accepted_evidence(payload: Mapping[str, object], root: Path = ROOT) -> None:
    schema_path = _canonical_repo_file(
        root / EVIDENCE_SCHEMA_RELATIVE,
        EVIDENCE_SCHEMA_RELATIVE,
        root,
        "accepted evidence schema",
        must_exist=True,
    )
    schema = _read_json(schema_path)
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
    except jsonschema.SchemaError as exc:
        raise VerificationError("accepted evidence schema is invalid") from exc
    errors = sorted(
        jsonschema.Draft202012Validator(schema).iter_errors(payload),
        key=lambda error: tuple(str(part) for part in error.absolute_path),
    )
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        _fail(f"accepted evidence does not satisfy schema at {location}: {first.message}")


def verify(
    candidate_path: Path,
    broadcast_path: Path,
    pins_path: Path,
    rpc: RpcCall,
    *,
    rpc_url: str = "http://127.0.0.1:8545",
    root: Path = ROOT,
) -> dict[str, object]:
    canonical_url = canonical_rpc_url(rpc_url)
    rpc_chain_id = rpc("eth_chainId", [])
    if rpc_chain_id != "0x7a69":
        _fail("RPC eth_chainId must be canonical 0x7a69 (31337)")
    candidate_path = _canonical_repo_file(
        candidate_path, CANDIDATE_RELATIVE, root, "candidate input", must_exist=True
    )
    broadcast_path = _canonical_repo_file(
        broadcast_path, BROADCAST_RELATIVE, root, "broadcast input", must_exist=True
    )
    if "dry-run" in {part.lower() for part in broadcast_path.parts}:
        _fail("dry-run broadcast artifacts cannot authorize activation")
    candidate = _read_json(candidate_path)
    facts = _candidate_facts(candidate)
    pins = load_reviewed_hashes(pins_path, root)

    engine = _create_address(str(facts["pair_deployer"]), 1)
    coordinator = _create_address(str(facts["pair_deployer"]), 2)
    if engine != facts["predicted_engine"] or coordinator != facts["predicted_coordinator"]:
        _fail("candidate CREATE predictions are invalid")
    recomputed = {
        "configuration_hash": _configuration_hash(facts),
        "engine_constructor_args_hash": _engine_args_hash(facts),
        "coordinator_constructor_args_hash": _coordinator_args_hash(facts),
    }
    for field, value in recomputed.items():
        if facts[field] != value:
            _fail(f"candidate {field} is invalid")
        facts[field] = value
    call_hash = _deployment_call_hash(facts)
    if facts["deployment_call_hash"] != call_hash:
        _fail("candidate deployment_call_hash is invalid")
    for candidate_field, pin_name in (
        ("expected_token_runtime_code_hash", "token"),
        ("expected_engine_runtime_code_hash", "engine"),
        ("expected_coordinator_runtime_code_hash", "coordinator"),
        ("expected_pair_runtime_code_hash", "pair"),
    ):
        if facts[candidate_field] != pins[pin_name]["runtimeCodeHash"]:
            _fail(f"candidate {candidate_field} does not match reviewed compiled artifacts")

    broadcast = _read_json(broadcast_path)
    if _quantity(broadcast.get("chain"), "broadcast.chain") != 31337:
        _fail("broadcast chain must be 31337")
    _validate_broadcast_shape(broadcast)
    token_input, pair_input = _expected_creation_inputs(facts, pins)
    token_tx = _checked_deployment(
        broadcast,
        rpc,
        "Phase9LocalSyntheticToken",
        str(facts["settlement_token"]),
        token_input,
    )
    pair_tx = _checked_deployment(
        broadcast,
        rpc,
        "Phase9PayoffPairDeployer",
        str(facts["pair_deployer"]),
        pair_input,
    )
    if token_tx["sender"] != pair_tx["sender"] or pair_tx["nonce"] != token_tx["nonce"] + 1:
        _fail("token and pair must be consecutive CREATE transactions from one sender")
    event = _verify_event(pair_tx["receipt"], facts)
    block = pair_tx["blockNumber"]

    observed_hashes: dict[str, str] = {}
    observed_bytes: dict[str, int] = {}
    for name, address in (
        ("token", str(facts["settlement_token"])),
        ("pair", str(facts["pair_deployer"])),
        ("engine", str(facts["predicted_engine"])),
        ("coordinator", str(facts["predicted_coordinator"])),
    ):
        observed_hashes[name], observed_bytes[name] = _rpc_code(rpc, address, block, name)
        if (
            observed_hashes[name] != pins[name]["runtimeCodeHash"]
            or observed_bytes[name] != pins[name]["runtimeBytes"]
        ):
            _fail(f"live {name} code does not match reviewed compiled artifacts")

    expected_engine_slots, expected_coordinator_slots = _expected_storage(facts)
    engine_slots = [_storage(rpc, engine, slot, block) for slot in range(4)]
    coordinator_slots = [_storage(rpc, coordinator, slot, block) for slot in range(9)]
    if engine_slots != expected_engine_slots:
        _fail("live payoff engine constructor storage mismatch")
    if coordinator_slots != expected_coordinator_slots:
        _fail("live refinance coordinator constructor storage mismatch")

    token_args_hash = _abi_hash(
        "UNIFIED_PHASE9_LOCAL_TOKEN_CONSTRUCTOR_ARGS_V1",
        [_word_address(str(facts["fixture_allocator"]))],
    )
    pair_args_hash = _abi_hash(
        "UNIFIED_PHASE9_PAYOFF_PAIR_CONSTRUCTOR_CONTENT_V1",
        [
            _word_hash(str(facts["configuration_hash"])),
            _word_address(str(facts["settlement_token"])),
            _word_hash(str(facts["engine_constructor_args_hash"])),
            _word_hash(str(facts["coordinator_constructor_args_hash"])),
        ],
    )
    normalized_candidate: dict[str, object] = dict(candidate)
    for field, fact_value in facts.items():
        normalized_candidate[field] = (
            str(fact_value) if field == "maximum_quote_validity" else fact_value
        )
    accepted: dict[str, object] = {
        **normalized_candidate,
        "artifact_type": "PHASE9_PAYOFF_DEPLOYMENT_EVIDENCE",
        "rpc_url": canonical_url,
        "rpc_chain_id": "0x7a69",
        "pin_manifest_sha256": pins["_manifest"]["sha256"],
        "activation_accepted": True,
        "post_broadcast_verification_required": False,
        "post_broadcast_verified": True,
        "bounded_local_reset_required": False,
        "deployment_history_reverted": False,
        "reset_command": RESET_COMMAND,
        "settlement_token_deployment_tx_hash": token_tx["txHash"],
        "pair_deployment_tx_hash": pair_tx["txHash"],
        "settlement_token_creation_input_hash": token_tx["inputHash"],
        "pair_creation_input_hash": pair_tx["inputHash"],
        "deployment_sender": pair_tx["sender"],
        "settlement_token_deployment_nonce": token_tx["nonce"],
        "pair_deployment_nonce": pair_tx["nonce"],
        "settlement_token_receipt_status": 1,
        "settlement_token_receipt_block_hash": token_tx["blockHash"],
        "settlement_token_receipt_block_number": token_tx["blockNumber"],
        "pair_receipt_status": 1,
        "pair_receipt_block_hash": pair_tx["blockHash"],
        "pair_receipt_block_number": pair_tx["blockNumber"],
        "event_topic0": event["topic0"],
        "event_emitter": event["emitter"],
        "event_engine_create_nonce": event["engineCreateNonce"],
        "token_constructor_args_hash": token_args_hash,
        "pair_constructor_content_hash": pair_args_hash,
        "broadcast_artifact_sha256": "sha256:"
        + hashlib.sha256(broadcast_path.read_bytes()).hexdigest(),
    }
    for name in ("token", "pair", "engine", "coordinator"):
        accepted[f"reviewed_{name}_runtime_code_hash"] = pins[name]["runtimeCodeHash"]
        accepted[f"observed_{name}_runtime_code_hash"] = observed_hashes[name]
        accepted[f"reviewed_{name}_creation_code_hash"] = pins[name]["creationCodeHash"]
    for index, value in enumerate(engine_slots):
        accepted[f"engine_slot_{index}"] = value
    for index, value in enumerate(coordinator_slots):
        accepted[f"coordinator_slot_{index}"] = value
    content = json.dumps(accepted, sort_keys=True, separators=(",", ":")).encode()
    accepted["verification_content_sha256"] = "sha256:" + hashlib.sha256(content).hexdigest()
    validate_accepted_evidence(accepted, root)
    return accepted


class HttpRpc:
    def __init__(self, url: str) -> None:
        self.url = canonical_rpc_url(url)
        self.request_id = 0
        self._proxy_handler = urllib.request.ProxyHandler({})
        self._redirect_handler = _RejectRpcRedirects()
        self.opener = urllib.request.build_opener(
            self._proxy_handler,
            self._redirect_handler,
        )

    def __call__(self, method: str, params: list[object]) -> object:
        self.request_id += 1
        body = json.dumps(
            {"jsonrpc": "2.0", "id": self.request_id, "method": method, "params": params}
        ).encode()
        request = urllib.request.Request(  # noqa: S310
            self.url, data=body, headers={"Content-Type": "application/json"}, method="POST"
        )
        with self.opener.open(request, timeout=10) as response:  # noqa: S310
            payload = _parse_json(response.read(), f"RPC {method} response")
        if not isinstance(payload, dict) or payload.get("error") is not None:
            _fail(f"RPC {method} failed: {payload}")
        return payload.get("result")


def rejection_payload(reason: str) -> dict[str, object]:
    return {
        "schema_version": 1,
        "artifact_type": "PHASE9_PAYOFF_DEPLOYMENT_REJECTION",
        "environment": "local",
        "contains_real_value": False,
        "activation_accepted": False,
        "bounded_local_reset_required": True,
        "deployment_history_reverted": False,
        "reset_command": RESET_COMMAND,
        "reason": reason,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify completed Phase 9 payoff broadcasts and live local RPC state."
    )
    parser.add_argument("--check-pins", action="store_true")
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--broadcast", type=Path)
    parser.add_argument("--rpc-url")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pins", type=Path, default=DEFAULT_PINS)
    parser.add_argument("--rejection-output", type=Path)
    args = parser.parse_args()

    if args.check_pins:
        if any(
            value is not None
            for value in (
                args.candidate,
                args.broadcast,
                args.rpc_url,
                args.output,
                args.rejection_output,
            )
        ):
            parser.error("--check-pins cannot be combined with activation arguments")
        try:
            pins = load_reviewed_hashes(args.pins, ROOT)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"Phase 9 payoff deployment pin check failed: {exc}", file=sys.stderr)
            return 1
        print(f"Phase 9 payoff deployment pins verified: {pins['_manifest']['sha256']}")
        return 0

    missing = [
        flag
        for flag, value in (
            ("--candidate", args.candidate),
            ("--broadcast", args.broadcast),
            ("--rpc-url", args.rpc_url),
            ("--output", args.output),
            ("--rejection-output", args.rejection_output),
        )
        if value is None
    ]
    if missing:
        parser.error(f"activation mode requires {', '.join(missing)}")
    try:
        candidate_path = _canonical_repo_file(
            args.candidate, CANDIDATE_RELATIVE, ROOT, "candidate input", must_exist=True
        )
        broadcast_path = _canonical_repo_file(
            args.broadcast, BROADCAST_RELATIVE, ROOT, "broadcast input", must_exist=True
        )
        output_path = _canonical_repo_file(
            args.output, ACCEPTED_RELATIVE, ROOT, "accepted output", must_exist=False
        )
        rejection_path = _canonical_repo_file(
            args.rejection_output,
            REJECTION_RELATIVE,
            ROOT,
            "rejection output",
            must_exist=False,
        )
        pins_path = _canonical_repo_file(
            args.pins, PIN_MANIFEST_RELATIVE, ROOT, "pin manifest", must_exist=True
        )
        if output_path.exists() and not output_path.is_file():
            _fail("accepted output target must be a regular file")
        if rejection_path.exists() and not rejection_path.is_file():
            _fail("rejection output target must be a regular file")
        rpc_url = canonical_rpc_url(args.rpc_url)
    except (OSError, ValueError) as exc:
        print(f"Phase 9 payoff deployment verification failed: {exc}", file=sys.stderr)
        return 1
    try:
        accepted = verify(
            candidate_path,
            broadcast_path,
            pins_path,
            HttpRpc(rpc_url),
            rpc_url=rpc_url,
        )
        validate_accepted_evidence(accepted, ROOT)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        if output_path.exists():
            output_path.unlink()
        _write_json(rejection_path, rejection_payload(str(exc)))
        print(f"Phase 9 payoff deployment verification failed: {exc}", file=sys.stderr)
        return 1
    _write_json(output_path, accepted)
    print(f"Phase 9 payoff deployment evidence accepted: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
