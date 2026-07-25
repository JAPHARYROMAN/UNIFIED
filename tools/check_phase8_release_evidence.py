"""Validate the authoritative Phase 8 local release evidence against live state.

The checked JSON is generated and local-only. It is never an authority for
production configuration. This checker deliberately recomputes Solidity route,
finality-policy, signer-set, lane, and message hashes instead of accepting a
secondary worker commitment as the on-chain identifier.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import urllib.request
from pathlib import Path
from typing import Any, Never, cast
from urllib.parse import urlparse

from Crypto.Hash import keccak
from Crypto.Signature import eddsa
from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import SchemaError

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVIDENCE = ROOT / "protocol/deployments/local/phase8-release-evidence.json"
SCHEMA_PATH = ROOT / "infrastructure/local/cross-chain/phase8-release-evidence.schema.json"
DEPLOYMENT_ROOT = ROOT / "protocol/deployments/local"
CACHE_ROOT = ROOT / ".cache/phase8-release"
DOCKER = shutil.which("docker") or "docker"
GIT = shutil.which("git") or "git"

HEX_20 = re.compile(r"0x[0-9a-f]{40}")
HEX_32 = re.compile(r"0x[0-9a-f]{64}")
SHA256 = re.compile(r"[0-9a-f]{64}")
COMMIT = re.compile(r"[0-9a-f]{40}")
UINT = re.compile(r"0|[1-9][0-9]*")

REQUIRED_ROUTE_PURPOSES = {
    "MINT",
    "REPORT",
    "REPAYMENT",
    "ALTERNATE_REPAYMENT",
    "BRIDGE_EXIT",
    "DISBURSEMENT",
    "COLLATERAL_RELEASE",
}
REQUIRED_ACTIONS = {1, 2, 5, 6, 7, 8, 9, 10}
REQUIRED_REPLAYS = {"MINT", "REPAYMENT", "COLLATERAL_RELEASE"}
MESSAGE_PURPOSE_TO_REGISTRY_PURPOSE = {
    "mint": "MINT",
    "report": "REPORT",
    "repayment": "REPAYMENT",
    "alternate_repayment": "ALTERNATE_REPAYMENT",
    "bridge_exit": "BRIDGE_EXIT",
    "disbursement": "DISBURSEMENT",
    "collateral_release": "COLLATERAL_RELEASE",
}
EXPECTED_MESSAGE_ACTION_PURPOSES = (
    (1, "mint"),
    (5, "report"),
    (2, "report"),
    (6, "disbursement"),
    (7, "report"),
    (8, "repayment"),
    (9, "collateral_release"),
    (10, "report"),
)
REQUIRED_HOME_CONTRACTS = {
    "role_manager",
    "chain_registry",
    "emergency_controller",
    "route_registry",
    "finality_verifier",
    "coordinator",
    "recovery_controller",
    "canonical_uft",
    "loan_registry",
    "bridge_exposure_policy",
    "bridge_hub",
    "loan_account_deployer",
    "loan_factory",
    "loan_policy",
    "loan_account",
}
REQUIRED_SATELLITE_CONTRACTS = {
    "role_manager",
    "chain_registry",
    "emergency_controller",
    "route_registry",
    "finality_verifier",
    "coordinator",
    "recovery_controller",
    "collateral_token",
    "wrapped_uft",
    "satellite_loan_component",
    "satellite_collateral_vault",
    "satellite_settlement_vault",
}
REQUIRED_TABLES = {
    "crosschain.acknowledgements",
    "crosschain.action_projections",
    "crosschain.bridge_backing_snapshots",
    "crosschain.bridge_exposure_policies",
    "crosschain.bridge_exposure_snapshots",
    "crosschain.bridge_locks",
    "crosschain.bridge_reconciliation_differences",
    "crosschain.bridge_reconciliations",
    "crosschain.canonical_burns",
    "crosschain.canonical_releases",
    "crosschain.chain_versions",
    "crosschain.chains",
    "crosschain.collateral_positions",
    "crosschain.collateral_release_authorizations",
    "crosschain.collateral_release_results",
    "crosschain.compensations",
    "crosschain.direct_home_repayment_evidence",
    "crosschain.direct_home_repayment_results",
    "crosschain.disbursement_authorizations",
    "crosschain.disbursement_results",
    "crosschain.execution_results",
    "crosschain.finality_certificates",
    "crosschain.header_observations",
    "crosschain.incidents",
    "crosschain.inbox",
    "crosschain.loan_cancellation_completions",
    "crosschain.loan_cancellation_requests",
    "crosschain.loan_routes",
    "crosschain.message_transitions",
    "crosschain.messages",
    "crosschain.outbox",
    "crosschain.provider_attempts",
    "crosschain.repayment_results",
    "crosschain.recovery_authorizer_sets",
    "crosschain.recovery_requests",
    "crosschain.reorganizations",
    "crosschain.route_versions",
    "crosschain.routes",
    "crosschain.signer_sets",
    "crosschain.source_proofs",
    "crosschain.tombstones",
    "crosschain.wrapped_burns",
    "crosschain.wrapped_mints",
    "ledger.bridge_journal_links",
    "ledger.crosschain_recovery_journal_links",
    "ledger.satellite_custody_links",
    "ledger.satellite_settlement_links",
    "public.journal",
    "public.journal_entry",
}
NEVER_EMPTY_TABLES = {
    "crosschain.acknowledgements",
    "crosschain.action_projections",
    "crosschain.bridge_backing_snapshots",
    "crosschain.bridge_exposure_policies",
    "crosschain.bridge_exposure_snapshots",
    "crosschain.bridge_locks",
    "crosschain.bridge_reconciliations",
    "crosschain.canonical_releases",
    "crosschain.chain_versions",
    "crosschain.chains",
    "crosschain.collateral_positions",
    "crosschain.collateral_release_authorizations",
    "crosschain.collateral_release_results",
    "crosschain.disbursement_authorizations",
    "crosschain.disbursement_results",
    "crosschain.execution_results",
    "crosschain.finality_certificates",
    "crosschain.loan_routes",
    "crosschain.message_transitions",
    "crosschain.messages",
    "crosschain.provider_attempts",
    "crosschain.repayment_results",
    "crosschain.route_versions",
    "crosschain.routes",
    "crosschain.signer_sets",
    "crosschain.source_proofs",
    "crosschain.wrapped_burns",
    "crosschain.wrapped_mints",
    "ledger.bridge_journal_links",
    "ledger.satellite_custody_links",
    "ledger.satellite_settlement_links",
    "public.journal",
    "public.journal_entry",
}
EXPECTED_SIGNERS = [
    "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf",
    "0x6813eb9362372eef6200f3b1dbc3f819671cba69",
    "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
]
SYNTHETIC_PROOF_BOUNDARY = "SYNTHETIC_SIGNED_HEADER_FIXTURE"
AUTHENTICATED_PROOF_BOUNDARY = "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT"
FORBIDDEN_KEY_MARKERS = ("private_key", "mnemonic", "seed", "secret")
SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
SECP256K1_G = (
    0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8,
)


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode()


MAX_HEADER_RLP_BYTES = 64 << 10
MAX_TRANSACTION_BYTES = 1 << 20
MAX_RECEIPT_BYTES = 4 << 20
MAX_PROOF_NODE_BYTES = 1 << 20
MAX_PROOF_NODES = 64
MAX_PROOF_BYTES = 8 << 20
MAX_BLOCK_PROOF_BYTES = 32 << 20
MAX_BLOCK_INPUT_BYTES = 64 << 20
MAX_RECEIPTS_PER_BLOCK = 4096
MAX_RECEIPT_LOGS = 4096
MAX_LOG_TOPICS = 16
MAX_RLP_DEPTH = 64


class RLPValue:
    __slots__ = ("is_list", "items", "payload", "raw")

    def __init__(
        self,
        raw: bytes,
        payload: bytes,
        items: tuple[RLPValue, ...],
        is_list: bool,
    ) -> None:
        self.raw = raw
        self.payload = payload
        self.items = items
        self.is_list = is_list


class EvidenceError(ValueError):
    """Raised when release evidence is missing, inconsistent, or unauthenticated."""


def fail(message: str) -> Never:
    raise EvidenceError(message)


def mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return cast("dict[str, Any]", value)


def sequence(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{label} must be an array")
    return value


def exact_keys(
    value: dict[str, Any],
    required: set[str],
    label: str,
    *,
    allow_extra: bool = False,
) -> None:
    missing = required - value.keys()
    if missing:
        fail(f"{label} is missing fields: {', '.join(sorted(missing))}")
    if not allow_extra:
        extra = value.keys() - required
        if extra:
            fail(f"{label} has unknown fields: {', '.join(sorted(extra))}")


def integer(value: Any, label: str, *, positive: bool = False) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        fail(f"{label} must be an integer")
    if value < (1 if positive else 0):
        fail(f"{label} is outside its allowed range")
    return value


def decimal(value: Any, label: str, *, positive: bool = False) -> int:
    if not isinstance(value, str) or UINT.fullmatch(value) is None:
        fail(f"{label} must be a canonical unsigned decimal string")
    number = int(value)
    if positive and number == 0:
        fail(f"{label} must be positive")
    return number


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or value.strip() != value:
        fail(f"{label} must be a nonempty canonical string")
    return value


def fixed_hex(value: Any, pattern: re.Pattern[str], label: str) -> str:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        fail(f"{label} is not canonical lowercase hex")
    return value


def hex20(value: Any, label: str, *, reject_placeholder: bool = False) -> str:
    result = fixed_hex(value, HEX_20, label)
    raw = bytes.fromhex(result[2:])
    if raw == b"\x00" * 20:
        fail(f"{label} is zero")
    if reject_placeholder and (len(set(raw)) == 1 or int.from_bytes(raw, "big") <= 0xFFFF):
        fail(f"{label} is a placeholder address")
    return result


def hex32(value: Any, label: str) -> str:
    result = fixed_hex(value, HEX_32, label)
    if result == "0x" + ("00" * 32):
        fail(f"{label} is zero")
    return result


def sha256_hex(value: Any, label: str) -> str:
    return fixed_hex(value, SHA256, label)


def hex_bytes(value: Any, label: str, *, allow_empty: bool = False) -> bytes:
    if (
        not isinstance(value, str)
        or not value.startswith("0x")
        or len(value) % 2 != 0
        or re.fullmatch(r"0x[0-9a-f]*", value) is None
    ):
        fail(f"{label} must be canonical lowercase hex bytes")
    result = bytes.fromhex(value[2:])
    if not result and not allow_empty:
        fail(f"{label} must not be empty")
    return result


def reject_secret_material(value: Any, path: str = "release evidence") -> None:
    if isinstance(value, dict):
        for raw_key, child in value.items():
            key = str(raw_key).lower()
            if any(marker in key for marker in FORBIDDEN_KEY_MARKERS):
                fail(f"{path}.{raw_key} contains forbidden secret or signing material")
            if ("signing" in key and "signature" not in key) or key in {
                "raw_key",
                "key_material",
            }:
                fail(f"{path}.{raw_key} contains forbidden raw signing material")
            reject_secret_material(child, f"{path}.{raw_key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_material(child, f"{path}[{index}]")


def schema_type_matches(value: Any, expected: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(expected, False)


def validate_schema_node(
    value: Any,
    schema: dict[str, Any],
    root_schema: dict[str, Any],
    path: str,
) -> None:
    reference = schema.get("$ref")
    if reference is not None:
        if not isinstance(reference, str) or not reference.startswith("#/$defs/"):
            fail(f"{path} schema uses an unsupported reference")
        definition_name = reference.removeprefix("#/$defs/")
        definitions = root_schema.get("$defs", {})
        if definition_name not in definitions:
            fail(f"{path} schema reference {reference} is missing")
        validate_schema_node(value, definitions[definition_name], root_schema, path)
        return

    alternatives = schema.get("oneOf")
    if alternatives is not None:
        matches = 0
        for alternative in alternatives:
            try:
                validate_schema_node(value, alternative, root_schema, path)
            except EvidenceError:
                continue
            matches += 1
        if matches != 1:
            fail(f"{path} must match exactly one schema alternative")
        return

    if "const" in schema and value != schema["const"]:
        fail(f"{path} differs from the schema constant")
    if "enum" in schema and value not in schema["enum"]:
        fail(f"{path} is outside the schema enumeration")
    expected_type = schema.get("type")
    if expected_type is not None and not schema_type_matches(value, expected_type):
        fail(f"{path} does not have schema type {expected_type}")

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        pattern_properties = schema.get("patternProperties", {})
        if not isinstance(pattern_properties, dict):
            fail(f"{path} schema patternProperties must be an object")
        compiled_patterns: list[tuple[re.Pattern[str], dict[str, Any]]] = []
        for raw_pattern, pattern_schema in pattern_properties.items():
            if not isinstance(raw_pattern, str) or not isinstance(pattern_schema, dict):
                fail(f"{path} schema has an invalid pattern property")
            try:
                compiled_patterns.append((re.compile(raw_pattern), pattern_schema))
            except re.error:
                fail(f"{path} schema has an invalid property pattern")
        unknown = {
            key
            for key in value
            if key not in properties
            and not any(pattern.search(key) for pattern, _ in compiled_patterns)
        }
        additional = schema.get("additionalProperties", True)
        if unknown and additional is False:
            fail(f"{path} has schema-unknown fields: {', '.join(sorted(unknown))}")
        missing = set(schema.get("required", [])) - value.keys()
        if missing:
            fail(f"{path} is schema-missing fields: {', '.join(sorted(missing))}")
        if len(value) < schema.get("minProperties", 0):
            fail(f"{path} has too few schema properties")
        maximum = schema.get("maxProperties")
        if maximum is not None and len(value) > maximum:
            fail(f"{path} has too many schema properties")
        for key, child in value.items():
            child_schemas: list[dict[str, Any]] = []
            property_schema = properties.get(key)
            if isinstance(property_schema, dict):
                child_schemas.append(property_schema)
            child_schemas.extend(
                pattern_schema
                for pattern, pattern_schema in compiled_patterns
                if pattern.search(key)
            )
            if not child_schemas and isinstance(additional, dict):
                child_schemas.append(additional)
            for child_schema in child_schemas:
                validate_schema_node(
                    child,
                    child_schema,
                    root_schema,
                    f"{path}.{key}",
                )
    elif isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            fail(f"{path} has too few schema items")
        maximum = schema.get("maxItems")
        if maximum is not None and len(value) > maximum:
            fail(f"{path} has too many schema items")
        if schema.get("uniqueItems") and len(
            {json.dumps(item, sort_keys=True) for item in value}
        ) != len(value):
            fail(f"{path} schema items must be unique")
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, child in enumerate(value):
                validate_schema_node(
                    child,
                    item_schema,
                    root_schema,
                    f"{path}[{index}]",
                )
    elif isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            fail(f"{path} is shorter than the schema minimum")
        pattern = schema.get("pattern")
        if pattern is not None and re.fullmatch(pattern, value) is None:
            fail(f"{path} does not match the schema pattern")
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                fail(f"{path} is not a schema-valid date-time")
            if parsed.tzinfo is None:
                fail(f"{path} schema date-time must have a timezone")
    elif isinstance(value, int) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        if minimum is not None and value < minimum:
            fail(f"{path} is below the schema minimum")


def validate_release_schema(evidence: dict[str, Any]) -> None:
    try:
        schema_raw = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot load frozen Phase 8 release schema: {error}")
    schema = mapping(schema_raw, "release schema")
    try:
        Draft202012Validator.check_schema(schema)
    except SchemaError as error:
        fail(f"frozen Phase 8 release schema is invalid: {error.message}")
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(
        validator.iter_errors(evidence),
        key=lambda error: tuple(str(part) for part in error.absolute_path),
    )
    if errors:
        first = errors[0]
        path = ".".join(str(part) for part in first.absolute_path) or "release evidence"
        fail(f"{path} fails Draft 2020-12 schema validation: {first.message}")
    validate_schema_node(evidence, schema, schema, "release evidence")


def chain_address(
    value: Any,
    label: str,
    expected_domain: str,
    expected_chain_id: int,
) -> str:
    reference = mapping(value, label)
    exact_keys(reference, {"domain", "chain_id", "address"}, label)
    if reference["domain"] != expected_domain or reference["chain_id"] != expected_chain_id:
        fail(f"{label} is not qualified to the expected domain and chain")
    return hex20(reference["address"], f"{label}.address", reject_placeholder=True)


def keccak256(payload: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(payload)
    return digest.digest()


def decode_rlp(encoded: bytes, offset: int = 0, depth: int = 0) -> tuple[RLPValue, int]:
    if depth > MAX_RLP_DEPTH or offset < 0 or offset >= len(encoded):
        fail("authenticated inclusion contains invalid or over-depth RLP")
    start = offset
    prefix = encoded[offset]
    offset += 1
    if prefix <= 0x7F:
        return RLPValue(encoded[start:offset], bytes([prefix]), (), False), offset
    if prefix <= 0xB7:
        length = prefix - 0x80
        end = offset + length
        if end > len(encoded) or (length == 1 and encoded[offset] < 0x80):
            fail("authenticated inclusion contains non-canonical RLP string")
        return RLPValue(encoded[start:end], encoded[offset:end], (), False), end
    if prefix <= 0xBF:
        length_of_length = prefix - 0xB7
        length_end = offset + length_of_length
        if length_end > len(encoded) or encoded[offset] == 0:
            fail("authenticated inclusion contains non-canonical RLP length")
        length = int.from_bytes(encoded[offset:length_end], "big")
        end = length_end + length
        if length < 56 or end > len(encoded):
            fail("authenticated inclusion contains invalid long RLP string")
        return RLPValue(encoded[start:end], encoded[length_end:end], (), False), end
    if prefix <= 0xF7:
        payload_length = prefix - 0xC0
        payload_start = offset
    else:
        length_of_length = prefix - 0xF7
        length_end = offset + length_of_length
        if length_end > len(encoded) or encoded[offset] == 0:
            fail("authenticated inclusion contains non-canonical RLP list length")
        payload_length = int.from_bytes(encoded[offset:length_end], "big")
        if payload_length < 56:
            fail("authenticated inclusion contains non-canonical long RLP list")
        payload_start = length_end
    payload_end = payload_start + payload_length
    if payload_end > len(encoded):
        fail("authenticated inclusion contains truncated RLP list")
    items: list[RLPValue] = []
    cursor = payload_start
    while cursor < payload_end:
        item, cursor = decode_rlp(encoded, cursor, depth + 1)
        items.append(item)
    if cursor != payload_end:
        fail("authenticated inclusion contains malformed RLP list")
    return (
        RLPValue(
            encoded[start:payload_end],
            encoded[payload_start:payload_end],
            tuple(items),
            True,
        ),
        payload_end,
    )


def decode_complete_rlp(encoded: bytes, label: str) -> RLPValue:
    try:
        value, consumed = decode_rlp(encoded)
    except EvidenceError as error:
        fail(f"{label}: {error}")
    if consumed != len(encoded):
        fail(f"{label} has trailing RLP bytes")
    return value


def rlp_uint(value: RLPValue, label: str) -> int:
    if value.is_list or len(value.payload) > 8 or (value.payload and value.payload[0] == 0):
        fail(f"{label} is not a canonical uint64 RLP value")
    return int.from_bytes(value.payload, "big")


def rlp_encode_uint(value: int) -> bytes:
    if value < 0 or value >= 1 << 64:
        fail("transaction index does not fit uint64")
    if value == 0:
        return b"\x80"
    payload = value.to_bytes(8, "big").lstrip(b"\x00")
    if len(payload) == 1 and payload[0] < 0x80:
        return payload
    return bytes([0x80 + len(payload)]) + payload


def parse_evm_header(encoded: bytes, label: str) -> dict[str, Any]:
    if not encoded or len(encoded) > MAX_HEADER_RLP_BYTES:
        fail(f"{label} header RLP is outside the Phase 7C size bound")
    value = decode_complete_rlp(encoded, f"{label} header")
    if not value.is_list or len(value.items) < 12:
        fail(f"{label} is not a canonical EVM header")
    parent, transaction_root, receipt_root = value.items[0], value.items[4], value.items[5]
    if (
        parent.is_list
        or transaction_root.is_list
        or receipt_root.is_list
        or len(parent.payload) != 32
        or len(transaction_root.payload) != 32
        or len(receipt_root.payload) != 32
    ):
        fail(f"{label} EVM header roots are malformed")
    number = rlp_uint(value.items[8], f"{label}.number")
    timestamp = rlp_uint(value.items[11], f"{label}.timestamp")
    if number == 0 or timestamp == 0:
        fail(f"{label} EVM header number/timestamp must be positive")
    return {
        "hash": "0x" + keccak256(encoded).hex(),
        "parent_hash": "0x" + parent.payload.hex(),
        "transactions_root": transaction_root.payload,
        "receipts_root": receipt_root.payload,
        "number": number,
        "timestamp": timestamp,
    }


def verify_authenticated_header(
    raw: dict[str, Any],
    *,
    chain_id: int,
    observer_public_key: str,
    label: str,
) -> tuple[dict[str, Any], int]:
    exact_keys(
        raw,
        {
            "header_rlp",
            "header_observed_at_unix_nanos",
            "header_signature_ed25519",
        },
        label,
    )
    header_rlp = hex_bytes(raw["header_rlp"], f"{label}.header_rlp")
    observed_nanos = decimal(
        raw["header_observed_at_unix_nanos"],
        f"{label}.header_observed_at_unix_nanos",
        positive=True,
    )
    if observed_nanos >= 1 << 64 or chain_id >= 1 << 64:
        fail(f"{label} signing scalar does not fit Phase 7C uint64")
    signature = hex_bytes(
        raw["header_signature_ed25519"],
        f"{label}.header_signature_ed25519",
    )
    if len(signature) != 64:
        fail(f"{label} header signature must be exact Ed25519 length")
    header = parse_evm_header(header_rlp, label)
    if observed_nanos // 1_000_000_000 < header["timestamp"]:
        fail(f"{label} was observed before its EVM timestamp")
    digest = keccak256(
        b"UNIFIED_EVM_HEADER_AUTHORITY_V1\x00"
        + chain_id.to_bytes(8, "big")
        + observed_nanos.to_bytes(8, "big")
        + keccak256(header_rlp)
    )
    public_key = bytes.fromhex(observer_public_key[2:])
    try:
        verifier = eddsa.new(eddsa.import_public_key(public_key), "rfc8032")
        verifier.verify(digest, signature)
    except (ValueError, TypeError) as error:
        fail(f"{label} Phase 7C signed header is invalid: {error}")
    return header, observed_nanos


def bytes_to_nibbles(value: bytes) -> bytes:
    result = bytearray()
    for item in value:
        result.extend((item >> 4, item & 0x0F))
    return bytes(result)


def decode_compact_path(encoded: bytes) -> tuple[bytes, bool] | None:
    nibbles = bytes_to_nibbles(encoded)
    if not nibbles or nibbles[0] > 3:
        return None
    leaf = nibbles[0] >= 2
    odd = nibbles[0] % 2 == 1
    if odd:
        return nibbles[1:], leaf
    if len(nibbles) < 2 or nibbles[1] != 0:
        return None
    return nibbles[2:], leaf


def trie_reference(value: RLPValue) -> bytes | None:
    if value.is_list:
        return value.raw if len(value.raw) < 32 else None
    return value.payload if len(value.payload) == 32 else None


def verify_trie_inclusion(root: bytes, key: bytes, expected: bytes, proof: list[bytes]) -> bool:
    if len(root) != 32 or not proof or len(proof) > MAX_PROOF_NODES:
        return False
    if any(not node or len(node) > MAX_PROOF_NODE_BYTES for node in proof):
        return False
    if sum(map(len, proof)) > MAX_PROOF_BYTES:
        return False
    key_nibbles = bytes_to_nibbles(key)
    reference = root
    position = 0
    for proof_index, encoded_node in enumerate(proof):
        if (
            len(reference) == 32
            and keccak256(encoded_node) != reference
            or len(reference) < 32
            and encoded_node != reference
        ):
            return False
        try:
            node = decode_complete_rlp(encoded_node, "MPT proof node")
        except EvidenceError:
            return False
        if not node.is_list:
            return False
        if len(node.items) == 17:
            if position == len(key_nibbles):
                value = node.items[16]
                return (
                    proof_index == len(proof) - 1
                    and not value.is_list
                    and value.payload == expected
                )
            child_reference = trie_reference(node.items[key_nibbles[position]])
            if child_reference is None:
                return False
            reference = child_reference
            position += 1
        elif len(node.items) == 2:
            path_field = node.items[0]
            if path_field.is_list:
                return False
            decoded_path = decode_compact_path(path_field.payload)
            if decoded_path is None:
                return False
            path, leaf = decoded_path
            if key_nibbles[position : position + len(path)] != path:
                return False
            position += len(path)
            if leaf:
                value = node.items[1]
                return (
                    position == len(key_nibbles)
                    and proof_index == len(proof) - 1
                    and not value.is_list
                    and value.payload == expected
                )
            child_reference = trie_reference(node.items[1])
            if child_reference is None:
                return False
            reference = child_reference
        else:
            return False
    return False


def decode_receipt(encoded: bytes, label: str) -> tuple[bool, list[dict[str, Any]]]:
    if not encoded or len(encoded) > MAX_RECEIPT_BYTES:
        fail(f"{label} receipt RLP is outside the Phase 7C size bound")
    payload = encoded[1:] if 0 < encoded[0] < 0x80 else encoded
    value = decode_complete_rlp(payload, f"{label} receipt")
    if not value.is_list or len(value.items) != 4:
        fail(f"{label} receipt is not a canonical post-Byzantium EVM receipt")
    status_value, cumulative_gas, bloom, logs_value = value.items
    if status_value.is_list or cumulative_gas.is_list:
        fail(f"{label} receipt scalar is malformed")
    if status_value.payload not in {b"", b"\x01"}:
        fail(f"{label} receipt status is not canonical")
    rlp_uint(cumulative_gas, f"{label}.cumulative_gas_used")
    if bloom.is_list or len(bloom.payload) != 256:
        fail(f"{label} receipt bloom is malformed")
    if not logs_value.is_list or len(logs_value.items) > MAX_RECEIPT_LOGS:
        fail(f"{label} receipt logs exceed the Phase 7C bound")
    if status_value.payload == b"" and logs_value.items:
        fail(f"{label} reverted receipt contains logs")
    logs: list[dict[str, Any]] = []
    for log_index, log_value in enumerate(logs_value.items):
        if not log_value.is_list or len(log_value.items) != 3:
            fail(f"{label} receipt log {log_index} is malformed")
        address, topics_value, data = log_value.items
        if (
            address.is_list
            or len(address.payload) != 20
            or not topics_value.is_list
            or len(topics_value.items) > MAX_LOG_TOPICS
            or data.is_list
            or len(data.payload) > MAX_RECEIPT_BYTES
        ):
            fail(f"{label} receipt log {log_index} exceeds canonical bounds")
        topics: list[str] = []
        for topic in topics_value.items:
            if topic.is_list or len(topic.payload) != 32:
                fail(f"{label} receipt log {log_index} has a malformed topic")
            topics.append("0x" + topic.payload.hex())
        logs.append(
            {
                "address": "0x" + address.payload.hex(),
                "topics": topics,
                "data": data.payload,
            }
        )
    return status_value.payload == b"\x01", logs


def phase7c_inclusion_hash(
    header_hash: str,
    transaction_index: int,
    transaction_rlp: bytes,
    transaction_nodes: list[bytes],
    receipt_rlp: bytes,
    receipt_nodes: list[bytes],
) -> str:
    payload = bytearray(b"UNIFIED_EVM_TRANSACTION_RECEIPT_INCLUSION_V1\x00")

    def append_length_prefixed(value: bytes) -> None:
        payload.extend(len(value).to_bytes(8, "big"))
        payload.extend(value)

    append_length_prefixed(header_hash.encode("ascii"))
    payload.extend(transaction_index.to_bytes(8, "big"))
    append_length_prefixed(transaction_rlp)
    for node in transaction_nodes:
        append_length_prefixed(node)
    append_length_prefixed(receipt_rlp)
    for node in receipt_nodes:
        append_length_prefixed(node)
    return "0x" + keccak256(bytes(payload)).hex()


def canonical_object_keccak(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return "0x" + keccak256(encoded).hex()


def check_phase7c_aggregate_bounds(input_bytes: int, proof_bytes: int, label: str) -> None:
    if proof_bytes > MAX_BLOCK_PROOF_BYTES:
        fail(f"{label} aggregate MPT proof bytes exceed the Phase 7C block bound")
    if input_bytes > MAX_BLOCK_INPUT_BYTES:
        fail(f"{label} aggregate authenticated input exceeds the Phase 7C block bound")


def check_authenticated_inclusion(
    inclusion_raw: Any,
    *,
    proof: dict[str, Any],
    chain_id: int,
    observer_public_key: str,
    expected_address: str,
    expected_topics: list[str],
    expected_data: bytes,
    expected_raw_hash: str,
    label: str,
) -> None:
    inclusion = mapping(inclusion_raw, f"{label}.authenticated_inclusion")
    exact_keys(
        inclusion,
        {
            "header_rlp",
            "header_observed_at_unix_nanos",
            "header_signature_ed25519",
            "receipts",
            "confirmation_headers",
        },
        f"{label}.authenticated_inclusion",
    )
    if canonical_object_keccak(inclusion) != expected_raw_hash:
        fail(f"{label} raw evidence object hash is not canonical")
    aggregate_input_bytes = len(hex_bytes(inclusion["header_rlp"], f"{label}.header_rlp")) + len(
        hex_bytes(
            inclusion["header_signature_ed25519"],
            f"{label}.header_signature_ed25519",
        )
    )
    aggregate_proof_bytes = 0
    check_phase7c_aggregate_bounds(
        aggregate_input_bytes,
        aggregate_proof_bytes,
        label,
    )
    header, observed_nanos = verify_authenticated_header(
        {
            "header_rlp": inclusion["header_rlp"],
            "header_observed_at_unix_nanos": inclusion["header_observed_at_unix_nanos"],
            "header_signature_ed25519": inclusion["header_signature_ed25519"],
        },
        chain_id=chain_id,
        observer_public_key=observer_public_key,
        label=f"{label}.source_header",
    )
    if (
        proof["source_block_hash"] != header["hash"]
        or proof["source_block_number"] != header["number"]
        or proof["source_block_timestamp"] != header["timestamp"]
        or bytes.fromhex(proof["receipt_root"][2:]) != header["receipts_root"]
    ):
        fail(f"{label} proof does not bind the authenticated source header")
    receipts = sequence(inclusion["receipts"], f"{label}.receipts")
    if len(receipts) != proof["transaction_index"] + 1 or len(receipts) > MAX_RECEIPTS_PER_BLOCK:
        fail(f"{label} receipt proof set is not prefix-complete")
    global_log_index = 0
    canonical_matches = 0
    target_found = False
    for expected_index, raw_receipt in enumerate(receipts):
        receipt = mapping(raw_receipt, f"{label}.receipts[{expected_index}]")
        exact_keys(
            receipt,
            {
                "transaction_index",
                "transaction_rlp",
                "transaction_proof_nodes",
                "receipt_rlp",
                "receipt_proof_nodes",
            },
            f"{label}.receipts[{expected_index}]",
        )
        transaction_index = integer(
            receipt["transaction_index"],
            f"{label}.receipts[{expected_index}].transaction_index",
        )
        if transaction_index != expected_index:
            fail(f"{label} receipt proof set is not ordered and prefix-complete")
        transaction_rlp = hex_bytes(
            receipt["transaction_rlp"],
            f"{label}.receipts[{expected_index}].transaction_rlp",
        )
        receipt_rlp = hex_bytes(
            receipt["receipt_rlp"],
            f"{label}.receipts[{expected_index}].receipt_rlp",
        )
        if len(transaction_rlp) > MAX_TRANSACTION_BYTES:
            fail(f"{label} transaction RLP exceeds the Phase 7C bound")
        transaction_nodes = [
            hex_bytes(node, f"{label}.transaction_proof_nodes[]")
            for node in sequence(
                receipt["transaction_proof_nodes"],
                f"{label}.transaction_proof_nodes",
            )
        ]
        receipt_nodes = [
            hex_bytes(node, f"{label}.receipt_proof_nodes[]")
            for node in sequence(
                receipt["receipt_proof_nodes"],
                f"{label}.receipt_proof_nodes",
            )
        ]
        aggregate_proof_bytes += sum(map(len, transaction_nodes))
        aggregate_proof_bytes += sum(map(len, receipt_nodes))
        aggregate_input_bytes += len(transaction_rlp) + len(receipt_rlp)
        aggregate_input_bytes += sum(map(len, transaction_nodes))
        aggregate_input_bytes += sum(map(len, receipt_nodes))
        check_phase7c_aggregate_bounds(
            aggregate_input_bytes,
            aggregate_proof_bytes,
            label,
        )
        key = rlp_encode_uint(transaction_index)
        if not verify_trie_inclusion(
            header["transactions_root"],
            key,
            transaction_rlp,
            transaction_nodes,
        ) or not verify_trie_inclusion(
            header["receipts_root"],
            key,
            receipt_rlp,
            receipt_nodes,
        ):
            fail(f"{label} transaction or receipt MPT inclusion is invalid")
        succeeded, logs = decode_receipt(
            receipt_rlp,
            f"{label}.receipts[{expected_index}]",
        )
        if expected_index == proof["transaction_index"]:
            if not succeeded:
                fail(f"{label} authenticated target receipt reverted")
            if "0x" + keccak256(transaction_rlp).hex() != proof["transaction_hash"]:
                fail(f"{label} authenticated transaction hash differs from proof")
            if (
                phase7c_inclusion_hash(
                    header["hash"],
                    transaction_index,
                    transaction_rlp,
                    transaction_nodes,
                    receipt_rlp,
                    receipt_nodes,
                )
                != proof["receipt_proof_hash"]
            ):
                fail(f"{label} Phase 7C inclusion hash differs from proof")
        for receipt_log in logs:
            is_expected = (
                expected_index == proof["transaction_index"]
                and receipt_log["address"] == expected_address
                and receipt_log["topics"] == expected_topics
                and receipt_log["data"] == expected_data
            )
            if is_expected:
                canonical_matches += 1
            if global_log_index == proof["log_index"]:
                target_found = is_expected
            global_log_index += 1
    if canonical_matches != 1 or not target_found:
        fail(f"{label} authenticated receipt lacks one exact canonical event")

    confirmation_headers = sequence(
        inclusion["confirmation_headers"],
        f"{label}.confirmation_headers",
    )
    if len(confirmation_headers) != proof["required_depth"]:
        fail(f"{label} signed confirmation-header depth is not exact")
    previous_header = header
    previous_observed_nanos = observed_nanos
    for index, raw_header in enumerate(confirmation_headers, start=1):
        confirmation_header, confirmation_observed_nanos = verify_authenticated_header(
            mapping(raw_header, f"{label}.confirmation_headers[{index - 1}]"),
            chain_id=chain_id,
            observer_public_key=observer_public_key,
            label=f"{label}.confirmation_headers[{index - 1}]",
        )
        if (
            confirmation_header["parent_hash"] != previous_header["hash"]
            or confirmation_header["number"] != previous_header["number"] + 1
            or confirmation_observed_nanos < previous_observed_nanos
        ):
            fail(f"{label} signed confirmation-header chain is not contiguous")
        previous_header = confirmation_header
        previous_observed_nanos = confirmation_observed_nanos
    if (
        previous_header["hash"] != proof["finality_head_hash"]
        or previous_header["number"] != proof["finality_head_number"]
        or previous_header["number"] != proof["source_block_number"] + proof["required_depth"]
    ):
        fail(f"{label} finality head is not the terminal authenticated header")


def word_uint(value: int, label: str, bits: int = 256) -> bytes:
    if value < 0 or value >= 1 << bits:
        fail(f"{label} does not fit uint{bits}")
    return value.to_bytes(32, "big")


def word_bool(value: Any, label: str) -> bytes:
    if not isinstance(value, bool):
        fail(f"{label} must be a boolean")
    return word_uint(1 if value else 0, label, 8)


def word_address(value: Any, label: str) -> bytes:
    return bytes(12) + bytes.fromhex(hex20(value, label, reject_placeholder=True)[2:])


def word_bytes32(value: Any, label: str) -> bytes:
    return bytes.fromhex(hex32(value, label)[2:])


def encode_string_and_words(domain: str, words: list[bytes]) -> bytes:
    domain_bytes = domain.encode("utf-8")
    offset = word_uint((len(words) + 1) * 32, "dynamic string offset")
    padding = bytes((-len(domain_bytes)) % 32)
    return (
        offset
        + b"".join(words)
        + word_uint(len(domain_bytes), "domain length")
        + domain_bytes
        + padding
    )


def solidity_hash(domain: str, words: list[bytes]) -> str:
    return "0x" + keccak256(encode_string_and_words(domain, words)).hex()


def route_hash(route: dict[str, Any]) -> str:
    words = [
        word_uint(
            integer(route["source_chain_version"], "route.source_chain_version", positive=True),
            "source chain version",
            32,
        ),
        word_uint(
            integer(
                route["destination_chain_version"], "route.destination_chain_version", positive=True
            ),
            "destination chain version",
            32,
        ),
        word_uint(
            integer(route["source_chain_id"], "route.source_chain_id", positive=True),
            "source chain id",
        ),
        word_address(route["source_coordinator"], "route.source_coordinator"),
        word_address(route["source_component"], "route.source_component"),
        word_bytes32(route["source_component_code_hash"], "route.source_component_code_hash"),
        word_uint(
            integer(route["destination_chain_id"], "route.destination_chain_id", positive=True),
            "destination chain id",
        ),
        word_address(route["destination_coordinator"], "route.destination_coordinator"),
        word_address(route["destination_component"], "route.destination_component"),
        word_bytes32(
            route["destination_component_code_hash"], "route.destination_component_code_hash"
        ),
        word_bytes32(route["action_family"], "route.action_family"),
        word_uint(
            integer(route["allowed_actions_bitmap"], "route.allowed_actions_bitmap", positive=True),
            "allowed actions",
            32,
        ),
        word_bytes32(route["adapter_id"], "route.adapter_id"),
        word_bytes32(route["adapter_code_hash"], "route.adapter_code_hash"),
        word_bytes32(route["adapter_set_policy_hash"], "route.adapter_set_policy_hash"),
        word_bytes32(route["source_finality_policy_hash"], "route.source_finality_policy_hash"),
        word_bytes32(
            route["destination_finality_policy_hash"], "route.destination_finality_policy_hash"
        ),
        word_bytes32(route["source_signer_set_hash"], "route.source_signer_set_hash"),
        word_bytes32(route["destination_signer_set_hash"], "route.destination_signer_set_hash"),
        word_uint(
            decimal(route["absolute_cap_units"], "route.absolute_cap_units", positive=True),
            "absolute cap",
        ),
        word_uint(
            decimal(route["chain_cap_units"], "route.chain_cap_units", positive=True), "chain cap"
        ),
        word_uint(
            decimal(route["adapter_cap_units"], "route.adapter_cap_units", positive=True),
            "adapter cap",
        ),
        word_uint(
            integer(route["activated_at"], "route.activated_at", positive=True), "activated at", 64
        ),
    ]
    return solidity_hash("UNIFIED_XCHAIN_ROUTE_V1", words)


def finality_policy_hash(policy: dict[str, Any]) -> str:
    words = [
        word_bool(policy["destination_evidence"], "policy.destination_evidence"),
        word_uint(
            integer(policy["source_chain_id"], "policy.source_chain_id", positive=True),
            "source chain id",
        ),
        word_address(policy["source_coordinator"], "policy.source_coordinator"),
        word_address(policy["source_component"], "policy.source_component"),
        word_uint(
            integer(policy["destination_chain_id"], "policy.destination_chain_id", positive=True),
            "destination chain id",
        ),
        word_address(policy["destination_coordinator"], "policy.destination_coordinator"),
        word_address(policy["destination_component"], "policy.destination_component"),
        word_uint(
            integer(
                policy["evidence_chain_version"], "policy.evidence_chain_version", positive=True
            ),
            "evidence chain version",
            32,
        ),
        word_bytes32(
            policy["evidence_chain_configuration_hash"], "policy.evidence_chain_configuration_hash"
        ),
        word_bytes32(policy["action_family"], "policy.action_family"),
        word_uint(
            integer(
                policy["allowed_actions_bitmap"], "policy.allowed_actions_bitmap", positive=True
            ),
            "allowed actions",
            32,
        ),
        word_uint(
            integer(policy["required_depth"], "policy.required_depth", positive=True),
            "required depth",
            64,
        ),
        word_bytes32(policy["observer_authority_hash"], "policy.observer_authority_hash"),
        word_bytes32(policy["signer_set_hash"], "policy.signer_set_hash"),
        word_uint(
            integer(policy["signer_set_version"], "policy.signer_set_version", positive=True),
            "signer set version",
            32,
        ),
    ]
    return solidity_hash("UNIFIED_SYNTHETIC_FINALITY_POLICY_V1", words)


def signer_set_hash(domain: dict[str, Any]) -> str:
    signer_set = mapping(domain["signer_set"], "domain.signer_set")
    signers = sequence(signer_set["sorted_addresses"], "domain.signer_set.sorted_addresses")
    if len(signers) != 3:
        fail("domain signer set must contain exactly three addresses")
    words = [
        word_bytes32(domain["observer_authority_hash"], "domain.observer_authority_hash"),
        word_uint(
            integer(signer_set["version"], "signer_set.version", positive=True),
            "signer version",
            32,
        ),
        *(word_address(value, "signer_set.sorted_addresses[]") for value in signers),
        word_uint(
            integer(signer_set["threshold"], "signer_set.threshold", positive=True), "threshold", 8
        ),
        word_uint(
            integer(signer_set["valid_from"], "signer_set.valid_from", positive=True),
            "valid from",
            64,
        ),
        word_uint(
            integer(signer_set["valid_until"], "signer_set.valid_until", positive=True),
            "valid until",
            64,
        ),
    ]
    return solidity_hash("UNIFIED_SYNTHETIC_SIGNER_SET_V1", words)


def chain_configuration_hash(domain: dict[str, Any]) -> str:
    contracts = mapping(domain["contracts"], "domain.contracts")
    words = [
        word_uint(integer(domain["chain_id"], "domain.chain_id", positive=True), "chain id"),
        word_uint(
            integer(domain["chain_version"], "domain.chain_version", positive=True),
            "chain version",
            32,
        ),
        word_address(
            mapping(contracts["coordinator"], "coordinator")["address"], "coordinator.address"
        ),
        word_address(
            mapping(contracts["finality_verifier"], "finality_verifier")["address"],
            "finality verifier.address",
        ),
        word_bytes32(domain["observer_authority_hash"], "domain.observer_authority_hash"),
        word_uint(
            integer(domain["activation_block"], "domain.activation_block"), "activation block"
        ),
    ]
    return solidity_hash("UNIFIED_LOCAL_CHAIN_CONFIGURATION_V1", words)


def recovery_authorizer_hash(recovery: dict[str, Any]) -> str:
    signers = sequence(
        recovery["sorted_authorizer_addresses"], "recovery.sorted_authorizer_addresses"
    )
    if len(signers) != 3:
        fail("recovery requires exactly three authorizers")
    words = [
        word_uint(
            integer(
                recovery["authorizer_set_version"], "recovery.authorizer_set_version", positive=True
            ),
            "authorizer version",
            32,
        ),
        word_uint(
            integer(recovery["threshold"], "recovery.threshold", positive=True),
            "recovery threshold",
            8,
        ),
        *(word_address(value, "recovery.sorted_authorizer_addresses[]") for value in signers),
    ]
    return solidity_hash("UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1", words)


def adapter_set_hash(providers: list[Any]) -> str:
    canonical: list[tuple[str, str]] = []
    for index, raw in enumerate(providers):
        provider = mapping(raw, f"providers[{index}]")
        provider_id = text(provider["id"], f"providers[{index}].id")
        authority = text(provider["authority"], f"providers[{index}].authority")
        canonical.append((provider_id, authority))
    canonical.sort()
    words = [word_uint(len(canonical), "provider count", 64)]
    for provider_id, authority in canonical:
        words.extend(
            (
                keccak256(provider_id.encode("utf-8")),
                keccak256(authority.encode("utf-8")),
            )
        )
    return solidity_hash("UNIFIED_LOCAL_ADAPTER_SET_POLICY_V1", words)


def lane_hash(envelope: dict[str, Any], action_family: str) -> str:
    words = [
        word_bytes32(envelope["protocol_id"], "envelope.protocol_id"),
        word_uint(
            integer(envelope["source_chain_id"], "envelope.source_chain_id", positive=True),
            "source chain",
        ),
        word_address(envelope["source_component"], "envelope.source_component"),
        word_uint(
            integer(
                envelope["destination_chain_id"], "envelope.destination_chain_id", positive=True
            ),
            "destination chain",
        ),
        word_address(envelope["destination_component"], "envelope.destination_component"),
        word_bytes32(envelope["aggregate_id"], "envelope.aggregate_id"),
        word_bytes32(action_family, "route.action_family"),
    ]
    return solidity_hash("UNIFIED_XCHAIN_LANE_V1", words)


def message_hash(envelope: dict[str, Any]) -> str:
    words = [
        word_uint(
            integer(envelope["schema_version"], "envelope.schema_version", positive=True),
            "schema version",
            32,
        ),
        word_bytes32(envelope["protocol_id"], "envelope.protocol_id"),
        word_uint(
            integer(envelope["source_chain_id"], "envelope.source_chain_id", positive=True),
            "source chain",
        ),
        word_address(envelope["source_coordinator"], "envelope.source_coordinator"),
        word_address(envelope["source_component"], "envelope.source_component"),
        word_uint(
            integer(
                envelope["destination_chain_id"], "envelope.destination_chain_id", positive=True
            ),
            "destination chain",
        ),
        word_address(envelope["destination_coordinator"], "envelope.destination_coordinator"),
        word_address(envelope["destination_component"], "envelope.destination_component"),
        word_bytes32(envelope["lane_id"], "envelope.lane_id"),
        word_uint(
            integer(envelope["source_nonce"], "envelope.source_nonce", positive=True),
            "source nonce",
            64,
        ),
        word_bytes32(envelope["aggregate_id"], "envelope.aggregate_id"),
        word_uint(
            integer(envelope["action_ordinal"], "envelope.action_ordinal", positive=True),
            "action ordinal",
            8,
        ),
        word_bytes32(envelope["payload_hash"], "envelope.payload_hash"),
        word_uint(
            integer(envelope["created_at"], "envelope.created_at", positive=True), "created at", 64
        ),
        word_uint(
            integer(envelope["expires_at"], "envelope.expires_at", positive=True), "expires at", 64
        ),
        word_bytes32(envelope["route_policy_hash"], "envelope.route_policy_hash"),
        word_bytes32(envelope["adapter_set_policy_hash"], "envelope.adapter_set_policy_hash"),
        word_bytes32(
            envelope["source_finality_policy_hash"], "envelope.source_finality_policy_hash"
        ),
        word_bytes32(
            envelope["destination_finality_policy_hash"],
            "envelope.destination_finality_policy_hash",
        ),
        word_bytes32(envelope["correlation_id"], "envelope.correlation_id"),
        bytes.fromhex(
            fixed_hex(envelope["causation_message_id"], HEX_32, "envelope.causation_message_id")[2:]
        ),
        bytes.fromhex(
            fixed_hex(envelope["superseded_message_id"], HEX_32, "envelope.superseded_message_id")[
                2:
            ]
        ),
    ]
    return solidity_hash("UNIFIED_XCHAIN_MESSAGE_V1", words)


def encode_bytes(value: bytes) -> bytes:
    return word_uint(len(value), "byte length") + value + bytes((-len(value)) % 32)


def envelope_encoding(envelope: dict[str, Any]) -> bytes:
    return b"".join(
        (
            word_uint(envelope["schema_version"], "schema version", 32),
            bytes.fromhex(fixed_hex(envelope["message_id"], HEX_32, "message ID")[2:]),
            word_bytes32(envelope["protocol_id"], "protocol ID"),
            word_uint(envelope["source_chain_id"], "source chain ID"),
            word_address(envelope["source_coordinator"], "source coordinator"),
            word_address(envelope["source_component"], "source component"),
            word_uint(envelope["destination_chain_id"], "destination chain ID"),
            word_address(envelope["destination_coordinator"], "destination coordinator"),
            word_address(envelope["destination_component"], "destination component"),
            word_bytes32(envelope["lane_id"], "lane ID"),
            word_uint(envelope["source_nonce"], "source nonce", 64),
            word_bytes32(envelope["aggregate_id"], "aggregate ID"),
            word_uint(envelope["action_ordinal"], "action ordinal", 8),
            word_bytes32(envelope["payload_hash"], "payload hash"),
            word_uint(envelope["created_at"], "created at", 64),
            word_uint(envelope["expires_at"], "expires at", 64),
            word_bytes32(envelope["route_policy_hash"], "route policy hash"),
            word_bytes32(envelope["adapter_set_policy_hash"], "adapter-set policy hash"),
            word_bytes32(
                envelope["source_finality_policy_hash"],
                "source finality policy hash",
            ),
            word_bytes32(
                envelope["destination_finality_policy_hash"],
                "destination finality policy hash",
            ),
            word_bytes32(envelope["correlation_id"], "correlation ID"),
            bytes.fromhex(
                fixed_hex(
                    envelope["causation_message_id"],
                    HEX_32,
                    "causation message ID",
                )[2:]
            ),
            bytes.fromhex(
                fixed_hex(
                    envelope["superseded_message_id"],
                    HEX_32,
                    "superseded message ID",
                )[2:]
            ),
        )
    )


PROOF_KEYS = {
    "source_block_hash",
    "source_block_number",
    "source_block_timestamp",
    "transaction_hash",
    "transaction_index",
    "receipt_root",
    "receipt_proof_hash",
    "log_index",
    "event_hash",
    "finality_head_hash",
    "finality_head_number",
    "required_depth",
    "header_authority_hash",
    "observer_signed_header_commitment",
    "observer_signature",
    "finality_policy_hash",
}
CERTIFICATE_KEYS = {
    "message_id",
    "source_proof_hash",
    "signer_set_hash",
    "signer_set_version",
    "signatures",
}


def proof_tuple_encoding(proof: dict[str, Any]) -> bytes:
    signature = hex_bytes(proof["observer_signature"], "proof.observer_signature")
    head = b"".join(
        (
            word_bytes32(proof["source_block_hash"], "proof.source_block_hash"),
            word_uint(proof["source_block_number"], "proof.source_block_number", 64),
            word_uint(
                proof["source_block_timestamp"],
                "proof.source_block_timestamp",
                64,
            ),
            word_bytes32(proof["transaction_hash"], "proof.transaction_hash"),
            word_uint(proof["transaction_index"], "proof.transaction_index", 32),
            word_bytes32(proof["receipt_root"], "proof.receipt_root"),
            word_bytes32(proof["receipt_proof_hash"], "proof.receipt_proof_hash"),
            word_uint(proof["log_index"], "proof.log_index", 32),
            word_bytes32(proof["event_hash"], "proof.event_hash"),
            word_bytes32(proof["finality_head_hash"], "proof.finality_head_hash"),
            word_uint(proof["finality_head_number"], "proof.finality_head_number", 64),
            word_uint(proof["required_depth"], "proof.required_depth", 64),
            word_bytes32(proof["header_authority_hash"], "proof.header_authority_hash"),
            word_bytes32(
                proof["observer_signed_header_commitment"],
                "proof.observer_signed_header_commitment",
            ),
            word_uint(16 * 32, "proof signature offset"),
            word_bytes32(proof["finality_policy_hash"], "proof.finality_policy_hash"),
        )
    )
    return head + encode_bytes(signature)


def proof_hash(proof: dict[str, Any]) -> str:
    encoded = word_uint(32, "proof tuple offset") + proof_tuple_encoding(proof)
    return "0x" + keccak256(encoded).hex()


def certificate_tuple_encoding(certificate: dict[str, Any]) -> bytes:
    signatures = [
        hex_bytes(value, "certificate.signatures[]") for value in certificate["signatures"]
    ]
    signature_offsets: list[bytes] = []
    signature_tails: list[bytes] = []
    next_offset = len(signatures) * 32
    for signature in signatures:
        encoded = encode_bytes(signature)
        signature_offsets.append(word_uint(next_offset, "signature offset"))
        signature_tails.append(encoded)
        next_offset += len(encoded)
    signature_array = (
        word_uint(len(signatures), "signature count")
        + b"".join(signature_offsets)
        + b"".join(signature_tails)
    )
    return b"".join(
        (
            word_bytes32(certificate["message_id"], "certificate.message_id"),
            word_bytes32(certificate["source_proof_hash"], "certificate.source_proof_hash"),
            word_bytes32(certificate["signer_set_hash"], "certificate.signer_set_hash"),
            word_uint(
                certificate["signer_set_version"],
                "certificate.signer_set_version",
                32,
            ),
            word_uint(5 * 32, "certificate signatures offset"),
            signature_array,
        )
    )


def certificate_hash(certificate: dict[str, Any]) -> str:
    encoded = word_uint(32, "certificate tuple offset") + certificate_tuple_encoding(certificate)
    return "0x" + keccak256(encoded).hex()


def execute_message_calldata(
    envelope: dict[str, Any],
    payload: bytes,
    proof: dict[str, Any],
    certificate: dict[str, Any],
) -> bytes:
    signature = (
        "executeMessage("
        "(uint32,bytes32,bytes32,uint256,address,address,uint256,address,address,"
        "bytes32,uint64,bytes32,uint8,bytes32,uint64,uint64,bytes32,bytes32,"
        "bytes32,bytes32,bytes32,bytes32,bytes32),"
        "bytes,"
        "(bytes32,uint64,uint64,bytes32,uint32,bytes32,bytes32,uint32,bytes32,"
        "bytes32,uint64,uint64,bytes32,bytes32,bytes,bytes32),"
        "(bytes32,bytes32,bytes32,uint32,bytes[]))"
    )
    envelope_head = envelope_encoding(envelope)
    head_size = len(envelope_head) + (3 * 32)
    payload_tail = encode_bytes(payload)
    proof_tail = proof_tuple_encoding(proof)
    certificate_tail = certificate_tuple_encoding(certificate)
    arguments = b"".join(
        (
            envelope_head,
            word_uint(head_size, "payload offset"),
            word_uint(head_size + len(payload_tail), "proof offset"),
            word_uint(
                head_size + len(payload_tail) + len(proof_tail),
                "certificate offset",
            ),
            payload_tail,
            proof_tail,
            certificate_tail,
        )
    )
    return keccak256(signature.encode("ascii"))[:4] + arguments


def acknowledgement_calldata(
    envelope: dict[str, Any],
    destination_result_hash: str,
    proof: dict[str, Any],
    certificate: dict[str, Any],
) -> bytes:
    signature = (
        "recordAcknowledgement("
        "(uint32,bytes32,bytes32,uint256,address,address,uint256,address,address,"
        "bytes32,uint64,bytes32,uint8,bytes32,uint64,uint64,bytes32,bytes32,"
        "bytes32,bytes32,bytes32,bytes32,bytes32),bytes32,"
        "(bytes32,uint64,uint64,bytes32,uint32,bytes32,bytes32,uint32,bytes32,"
        "bytes32,uint64,uint64,bytes32,bytes32,bytes,bytes32),"
        "(bytes32,bytes32,bytes32,uint32,bytes[]))"
    )
    envelope_head = envelope_encoding(envelope)
    static_head = envelope_head + word_bytes32(destination_result_hash, "destination result hash")
    head_size = len(static_head) + (2 * 32)
    proof_tail = proof_tuple_encoding(proof)
    certificate_tail = certificate_tuple_encoding(certificate)
    arguments = b"".join(
        (
            static_head,
            word_uint(head_size, "ack proof offset"),
            word_uint(head_size + len(proof_tail), "ack certificate offset"),
            proof_tail,
            certificate_tail,
        )
    )
    return keccak256(signature.encode("ascii"))[:4] + arguments


def source_message_event_hash(envelope: dict[str, Any]) -> str:
    words = [
        word_address(envelope["source_coordinator"], "source coordinator"),
        word_bytes32(envelope["message_id"], "message ID"),
        word_bytes32(envelope["lane_id"], "lane ID"),
        word_uint(envelope["source_nonce"], "source nonce", 64),
        word_uint(envelope["action_ordinal"], "action ordinal", 8),
        word_bytes32(envelope["payload_hash"], "payload hash"),
    ]
    return solidity_hash("UNIFIED_MESSAGE_SENT_V1", words)


def observer_header_commitment(proof: dict[str, Any]) -> str:
    words = [
        word_bytes32(proof["source_block_hash"], "proof.source_block_hash"),
        word_uint(proof["source_block_number"], "proof.source_block_number", 64),
        word_uint(proof["source_block_timestamp"], "proof.source_block_timestamp", 64),
        word_bytes32(proof["finality_head_hash"], "proof.finality_head_hash"),
        word_uint(proof["finality_head_number"], "proof.finality_head_number", 64),
        word_uint(proof["required_depth"], "proof.required_depth", 64),
        word_bytes32(proof["header_authority_hash"], "proof.header_authority_hash"),
        word_bytes32(proof["finality_policy_hash"], "proof.finality_policy_hash"),
    ]
    return solidity_hash("UNIFIED_OBSERVER_SIGNED_HEADER_V1", words)


def secp256k1_add(
    left: tuple[int, int] | None,
    right: tuple[int, int] | None,
) -> tuple[int, int] | None:
    if left is None:
        return right
    if right is None:
        return left
    x_left, y_left = left
    x_right, y_right = right
    if x_left == x_right and (y_left + y_right) % SECP256K1_P == 0:
        return None
    if left == right:
        slope = (3 * x_left * x_left) * pow(2 * y_left, -1, SECP256K1_P) % SECP256K1_P
    else:
        slope = (y_right - y_left) * pow(x_right - x_left, -1, SECP256K1_P) % SECP256K1_P
    x_result = (slope * slope - x_left - x_right) % SECP256K1_P
    y_result = (slope * (x_left - x_result) - y_left) % SECP256K1_P
    return x_result, y_result


def secp256k1_mul(
    scalar: int,
    point: tuple[int, int] | None,
) -> tuple[int, int] | None:
    result: tuple[int, int] | None = None
    addend = point
    while scalar:
        if scalar & 1:
            result = secp256k1_add(result, addend)
        addend = secp256k1_add(addend, addend)
        scalar >>= 1
    return result


def recover_signer(digest: bytes, signature: bytes) -> str:
    if len(signature) != 65:
        fail("certificate signature must contain r, s, and v")
    r = int.from_bytes(signature[:32], "big")
    s = int.from_bytes(signature[32:64], "big")
    recovery_id = signature[64] - 27
    if not 0 < r < SECP256K1_N or not 0 < s <= SECP256K1_N // 2 or recovery_id not in {0, 1}:
        fail("certificate signature is outside canonical secp256k1 bounds")
    x_coordinate = r
    alpha = (pow(x_coordinate, 3, SECP256K1_P) + 7) % SECP256K1_P
    y_coordinate = pow(alpha, (SECP256K1_P + 1) // 4, SECP256K1_P)
    if y_coordinate % 2 != recovery_id:
        y_coordinate = SECP256K1_P - y_coordinate
    point_r = (x_coordinate, y_coordinate)
    if secp256k1_mul(SECP256K1_N, point_r) is not None:
        fail("certificate signature recovery point is invalid")
    message_number = int.from_bytes(digest, "big")
    inverse_r = pow(r, -1, SECP256K1_N)
    negative_message_point = secp256k1_mul((-message_number) % SECP256K1_N, SECP256K1_G)
    public_key = secp256k1_mul(
        inverse_r,
        secp256k1_add(secp256k1_mul(s, point_r), negative_message_point),
    )
    if public_key is None:
        fail("certificate signature recovered the point at infinity")
    public_bytes = public_key[0].to_bytes(32, "big") + public_key[1].to_bytes(32, "big")
    return "0x" + keccak256(public_bytes)[-20:].hex()


def check_proof_certificate(
    proof_raw: Any,
    certificate_raw: Any,
    *,
    label: str,
    expected_domain: dict[str, Any],
    verifier_domain: dict[str, Any],
    expected_message_id: str,
    expected_event_hash: str,
    expected_policy_hash: str,
) -> tuple[str, str]:
    proof = mapping(proof_raw, f"{label}.proof")
    certificate = mapping(certificate_raw, f"{label}.certificate")
    exact_keys(proof, PROOF_KEYS, f"{label}.proof")
    exact_keys(certificate, CERTIFICATE_KEYS, f"{label}.certificate")
    for field in (
        "source_block_hash",
        "transaction_hash",
        "receipt_root",
        "receipt_proof_hash",
        "event_hash",
        "finality_head_hash",
        "header_authority_hash",
        "observer_signed_header_commitment",
        "finality_policy_hash",
    ):
        hex32(proof[field], f"{label}.proof.{field}")
    for field in (
        "source_block_number",
        "source_block_timestamp",
        "transaction_index",
        "log_index",
        "finality_head_number",
        "required_depth",
    ):
        integer(
            proof[field],
            f"{label}.proof.{field}",
            positive=field
            not in {
                "transaction_index",
                "log_index",
            },
        )
    if (
        proof["event_hash"] != expected_event_hash
        or proof["finality_policy_hash"] != expected_policy_hash
        or proof["header_authority_hash"] != expected_domain["observer_authority_hash"]
        or proof["required_depth"] != expected_domain["confirmation_depth"]
        or proof["finality_head_number"] < proof["source_block_number"] + proof["required_depth"]
    ):
        fail(f"{label} synthetic proof diverges from the exact event/trust policy")
    commitment = observer_header_commitment(proof)
    if proof["observer_signed_header_commitment"] != commitment:
        fail(f"{label} observer header commitment is not canonical")
    signature = hex_bytes(proof["observer_signature"], f"{label}.observer_signature")
    if len(signature) != 64:
        fail(f"{label} observer signature must be exact Ed25519 length")
    public_key = bytes.fromhex(expected_domain["observer_public_key_ed25519"][2:])
    try:
        verifier = eddsa.new(eddsa.import_public_key(public_key), "rfc8032")
        verifier.verify(bytes.fromhex(commitment[2:]), signature)
    except (ValueError, TypeError) as error:
        fail(f"{label} observer signature is not valid Ed25519 evidence: {error}")

    computed_proof_hash = proof_hash(proof)
    signatures = sequence(certificate["signatures"], f"{label}.certificate.signatures")
    if len(signatures) not in {2, 3}:
        fail(f"{label} certificate must have two or three signatures")
    if any(
        len(hex_bytes(value, f"{label}.certificate.signatures[]")) != 65 for value in signatures
    ):
        fail(f"{label} certificate contains a non-canonical ECDSA signature")
    if (
        certificate["message_id"] != expected_message_id
        or certificate["source_proof_hash"] != computed_proof_hash
        or certificate["signer_set_hash"] != expected_domain["signer_set"]["hash"]
        or certificate["signer_set_version"] != expected_domain["signer_set"]["version"]
    ):
        fail(f"{label} certificate diverges from the exact proof/signer set")
    digest = solidity_hash(
        "UNIFIED_SYNTHETIC_FINALITY_V1",
        [
            word_uint(verifier_domain["chain_id"], "verification chain ID"),
            word_address(
                verifier_domain["contracts"]["finality_verifier"]["address"],
                "verification finality verifier",
            ),
            word_bytes32(expected_message_id, "message ID"),
            word_bytes32(computed_proof_hash, "source proof hash"),
            word_bytes32(certificate["signer_set_hash"], "signer-set hash"),
            word_uint(certificate["signer_set_version"], "signer-set version", 32),
        ],
    )
    recovered = {
        recover_signer(bytes.fromhex(digest[2:]), hex_bytes(value, "signature"))
        for value in signatures
    }
    if len(recovered & set(expected_domain["signer_set"]["sorted_addresses"])) < 2:
        fail(f"{label} certificate does not contain a distinct canonical 2-of-3 quorum")
    return computed_proof_hash, certificate_hash(certificate)


def deployment_flow_sha256(evidence: dict[str, Any]) -> str:
    committed = {
        "protocol_id": evidence["protocol_id"],
        "proof_boundary": evidence["proof_boundary"],
        "domains": evidence["domains"],
        "routes": evidence["routes"],
        "exposure_policy": evidence["exposure_policy"],
        "recovery": evidence["recovery"],
        "providers": evidence["providers"],
        "flow": evidence["flow"],
    }
    encoded = json.dumps(
        committed,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def local_rpc_url(value: Any, label: str) -> str:
    result = text(value, label)
    parsed = urlparse(result)
    if (
        parsed.scheme != "http"
        or parsed.username is not None
        or parsed.query
        or parsed.fragment
        or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
    ):
        fail(f"{label} must be a credential-free loopback HTTP URL")
    return result


class RPC:
    def __init__(self, url: str) -> None:
        self.url = url
        self.counter = 0

    def call(self, method: str, params: list[Any]) -> Any:
        self.counter += 1
        payload = json.dumps(
            {"jsonrpc": "2.0", "id": self.counter, "method": method, "params": params}
        ).encode("utf-8")
        request = urllib.request.Request(  # noqa: S310
            self.url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310
                result = json.loads(response.read())
        except Exception as error:  # pragma: no cover - exact network error varies
            fail(f"RPC {method} failed at {self.url}: {error}")
        if "error" in result:
            fail(f"RPC {method} failed at {self.url}: {result['error']}")
        return result.get("result")

    def eth_call(self, address: str, signature: str, arguments: bytes = b"") -> bytes:
        selector = keccak256(signature.encode("ascii"))[:4]
        result = self.call(
            "eth_call",
            [{"to": address, "data": "0x" + (selector + arguments).hex()}, "latest"],
        )
        if not isinstance(result, str) or not result.startswith("0x"):
            fail(f"eth_call {signature} returned invalid data")
        return bytes.fromhex(result[2:])


def validate_contract(
    name: str,
    raw: Any,
    rpc: RPC,
    live_addresses: set[str],
) -> dict[str, Any]:
    contract = mapping(raw, f"contract {name}")
    base_fields = {
        "address",
        "runtime_code_hash",
        "abi_path",
        "abi_sha256",
        "deployment_kind",
        "deployment_tx_hash",
        "deployment_block_number",
    }
    deployment_kind = contract.get("deployment_kind")
    if deployment_kind == "CREATE_TRANSACTION":
        exact_keys(contract, base_fields, f"contract {name}")
    elif deployment_kind == "INTERNAL_CREATE2":
        exact_keys(contract, base_fields | {"creation_event"}, f"contract {name}")
        if name != "loan_account":
            fail("only the frozen loan_account may use INTERNAL_CREATE2")
    else:
        fail(f"contract {name}.deployment_kind is not supported")
    address = hex20(contract["address"], f"contract {name}.address", reject_placeholder=True)
    if address in live_addresses:
        fail(f"duplicate contract address in one domain: {address}")
    live_addresses.add(address)
    expected_code_hash = hex32(contract["runtime_code_hash"], f"contract {name}.runtime_code_hash")
    abi_path = (ROOT / text(contract["abi_path"], f"contract {name}.abi_path")).resolve()
    try:
        abi_path.relative_to(ROOT)
    except ValueError:
        fail(f"contract {name}.abi_path escapes the repository")
    if not abi_path.is_file() or "protocol/abi/" not in abi_path.as_posix():
        fail(f"contract {name} ABI snapshot is missing or outside protocol/abi")
    expected_abi_sha = sha256_hex(contract["abi_sha256"], f"contract {name}.abi_sha256")
    actual_abi_sha = hashlib.sha256(abi_path.read_bytes()).hexdigest()
    if expected_abi_sha != actual_abi_sha:
        fail(f"contract {name} ABI snapshot hash does not match")
    transaction_hash = hex32(contract["deployment_tx_hash"], f"contract {name}.deployment_tx_hash")
    block_number = integer(
        contract["deployment_block_number"],
        f"contract {name}.deployment_block_number",
        positive=True,
    )

    code = rpc.call("eth_getCode", [address, "latest"])
    if not isinstance(code, str) or not code.startswith("0x") or len(code) <= 2:
        fail(f"contract {name} has no live runtime code")
    actual_code_hash = "0x" + keccak256(bytes.fromhex(code[2:])).hex()
    if actual_code_hash != expected_code_hash:
        fail(f"contract {name} live runtime code hash differs from the manifest")
    receipt = rpc.call("eth_getTransactionReceipt", [transaction_hash])
    if not isinstance(receipt, dict) or receipt.get("status") != "0x1":
        fail(f"contract {name} deployment receipt is absent or reverted")
    if int(receipt.get("blockNumber", "0x0"), 16) != block_number:
        fail(f"contract {name} deployment block differs")
    if deployment_kind == "CREATE_TRANSACTION":
        receipt_address = receipt.get("contractAddress")
        if not isinstance(receipt_address, str) or receipt_address.lower() != address:
            fail(f"contract {name} deployment receipt address differs")
    else:
        if receipt.get("contractAddress") is not None:
            fail(f"contract {name} internal CREATE2 receipt unexpectedly has an address")
        event = mapping(contract["creation_event"], f"contract {name}.creation_event")
        exact_keys(
            event,
            {
                "emitter",
                "signature",
                "topic0",
                "indexed_id",
                "indexed_id_topic_position",
                "indexed_address_topic_position",
            },
            f"contract {name}.creation_event",
        )
        emitter = hex20(
            event["emitter"],
            f"contract {name}.creation_event.emitter",
            reject_placeholder=True,
        )
        signature = text(event["signature"], f"contract {name}.creation_event.signature")
        if signature != "CrossChainLoanCreated(bytes32,address,address,address,bytes32)":
            fail("loan_account creation event signature is not canonical")
        topic0 = hex32(event["topic0"], f"contract {name}.creation_event.topic0")
        expected_topic0 = "0x" + keccak256(signature.encode("ascii")).hex()
        if topic0 != expected_topic0:
            fail("loan_account creation event topic is not canonical")
        indexed_id = hex32(event["indexed_id"], f"contract {name}.creation_event.indexed_id")
        id_position = integer(
            event["indexed_id_topic_position"],
            f"contract {name}.creation_event.indexed_id_topic_position",
            positive=True,
        )
        address_position = integer(
            event["indexed_address_topic_position"],
            f"contract {name}.creation_event.indexed_address_topic_position",
            positive=True,
        )
        if id_position != 1 or address_position != 2:
            fail("loan_account creation event uses the wrong indexed topic positions")
        padded_address = "0x" + ("00" * 12) + address[2:]
        matching = [
            log
            for log in receipt.get("logs", [])
            if log.get("address", "").lower() == emitter
            and len(log.get("topics", [])) > address_position
            and log["topics"][0].lower() == topic0
            and log["topics"][id_position].lower() == indexed_id
            and log["topics"][address_position].lower() == padded_address
        ]
        if len(matching) != 1:
            fail("loan_account factory receipt lacks one canonical creation event")
    return contract


def check_domain(
    name: str,
    raw: Any,
    expected_chain_id: int,
) -> tuple[dict[str, Any], RPC]:
    domain = mapping(raw, f"domains.{name}")
    required = {
        "chain_id",
        "chain_version",
        "rpc_url",
        "genesis_hash",
        "configuration_hash",
        "activation_block",
        "activation_timestamp",
        "registry_status",
        "observer_fixture",
        "observer_public_key_ed25519",
        "observer_authority_hash",
        "confirmation_depth",
        "signer_set",
        "contracts",
        "registry_bindings",
        "finality_policies",
    }
    exact_keys(domain, required, f"domains.{name}")
    if integer(domain["chain_id"], f"domains.{name}.chain_id") != expected_chain_id:
        fail(f"domains.{name} has the wrong local chain ID")
    if integer(domain["chain_version"], f"domains.{name}.chain_version", positive=True) != 1:
        fail(f"domains.{name} chain version must be one")
    rpc = RPC(local_rpc_url(domain["rpc_url"], f"domains.{name}.rpc_url"))
    chain_id = rpc.call("eth_chainId", [])
    if not isinstance(chain_id, str) or int(chain_id, 16) != expected_chain_id:
        fail(f"domains.{name} live RPC has the wrong chain ID")
    genesis = rpc.call("eth_getBlockByNumber", ["0x0", False])
    expected_genesis = hex32(domain["genesis_hash"], f"domains.{name}.genesis_hash")
    if not isinstance(genesis, dict) or genesis.get("hash", "").lower() != expected_genesis:
        fail(f"domains.{name} genesis hash differs from the live RPC")
    integer(domain["activation_block"], f"domains.{name}.activation_block")
    integer(
        domain["activation_timestamp"],
        f"domains.{name}.activation_timestamp",
        positive=True,
    )
    if domain["registry_status"] != "ACTIVE":
        fail(f"domains.{name} registry status must be ACTIVE")
    text(domain["observer_fixture"], f"domains.{name}.observer_fixture")
    fixed_hex(
        domain["observer_public_key_ed25519"],
        HEX_32,
        f"domains.{name}.observer_public_key_ed25519",
    )
    hex32(domain["observer_authority_hash"], f"domains.{name}.observer_authority_hash")
    integer(domain["confirmation_depth"], f"domains.{name}.confirmation_depth", positive=True)

    signer_set = mapping(domain["signer_set"], f"domains.{name}.signer_set")
    exact_keys(
        signer_set,
        {"version", "hash", "threshold", "valid_from", "valid_until", "sorted_addresses"},
        f"domains.{name}.signer_set",
    )
    if integer(signer_set["version"], "signer_set.version", positive=True) != 1:
        fail(f"domains.{name} signer-set version must be one")
    if integer(signer_set["threshold"], "signer_set.threshold", positive=True) != 2:
        fail(f"domains.{name} signer-set threshold must be two")
    if sequence(signer_set["sorted_addresses"], "signer_set.sorted_addresses") != EXPECTED_SIGNERS:
        fail(f"domains.{name} signer addresses are not the frozen local set")
    if integer(signer_set["valid_until"], "signer_set.valid_until", positive=True) <= integer(
        signer_set["valid_from"], "signer_set.valid_from", positive=True
    ):
        fail(f"domains.{name} signer-set validity is empty")
    if signer_set_hash(domain) != hex32(signer_set["hash"], "signer_set.hash"):
        fail(f"domains.{name} signer-set hash is not the Solidity hash")

    required_contracts = REQUIRED_HOME_CONTRACTS if name == "home" else REQUIRED_SATELLITE_CONTRACTS
    contracts = mapping(domain["contracts"], f"domains.{name}.contracts")
    if not required_contracts <= contracts.keys():
        fail(f"domains.{name} is missing required deployed contracts")
    live_addresses: set[str] = set()
    for contract_name, contract in contracts.items():
        validate_contract(contract_name, contract, rpc, live_addresses)

    configuration = hex32(domain["configuration_hash"], f"domains.{name}.configuration_hash")
    if configuration != chain_configuration_hash(domain):
        fail(f"domains.{name} configuration hash is not the canonical local commitment")

    bindings = mapping(domain["registry_bindings"], f"domains.{name}.registry_bindings")
    exact_keys(
        bindings,
        {"route_registry_chain_registry", "finality_verifier_chain_registry"},
        f"domains.{name}.registry_bindings",
    )
    chain_registry = contracts["chain_registry"]["address"]
    for field in ("route_registry_chain_registry", "finality_verifier_chain_registry"):
        if (
            hex20(
                bindings[field],
                f"domains.{name}.registry_bindings.{field}",
                reject_placeholder=True,
            )
            != chain_registry
        ):
            fail(f"domains.{name} {field} does not bind the deployed chain registry")
    for contract_name in ("route_registry", "finality_verifier"):
        result = rpc.eth_call(contracts[contract_name]["address"], "chainRegistry()")
        if len(result) != 32 or "0x" + result[-20:].hex() != chain_registry:
            fail(f"domains.{name} live {contract_name} has the wrong chain registry")
    return domain, rpc


def check_live_trust_registrations(
    domains: dict[str, dict[str, Any]],
    rpcs: dict[str, RPC],
) -> None:
    for registry_domain, rpc in rpcs.items():
        registry_address = domains[registry_domain]["contracts"]["chain_registry"]["address"]
        verifier_address = domains[registry_domain]["contracts"]["finality_verifier"]["address"]
        for target_name, target in domains.items():
            chain_result = rpc.eth_call(
                registry_address,
                "chainVersion(uint256,uint32)",
                word_uint(target["chain_id"], "registered chain ID")
                + word_uint(target["chain_version"], "registered chain version", 32),
            )
            if len(chain_result) != 10 * 32:
                fail(
                    f"{registry_domain} ChainRegistry returned an invalid "
                    f"{target_name} chain record"
                )
            words = [chain_result[index : index + 32] for index in range(0, len(chain_result), 32)]
            expected_words = [
                word_uint(target["chain_id"], "chain ID"),
                word_uint(target["chain_version"], "chain version", 32),
                word_address(target["contracts"]["coordinator"]["address"], "coordinator"),
                word_address(
                    target["contracts"]["finality_verifier"]["address"],
                    "finality verifier",
                ),
                word_bytes32(
                    target["contracts"]["coordinator"]["runtime_code_hash"],
                    "coordinator code hash",
                ),
                word_bytes32(
                    target["contracts"]["finality_verifier"]["runtime_code_hash"],
                    "verifier code hash",
                ),
                word_bytes32(target["configuration_hash"], "configuration hash"),
                word_uint(target["activation_timestamp"], "activation timestamp", 64),
                word_uint(0, "deprecated timestamp", 64),
                word_uint(1, "active registry status", 8),
            ]
            if words != expected_words:
                fail(
                    f"{registry_domain} ChainRegistry {target_name} record "
                    "differs from the manifest"
                )

            signer_set = target["signer_set"]
            signer_result = rpc.eth_call(
                verifier_address,
                "signerSetRecord(bytes32)",
                word_bytes32(signer_set["hash"], "signer-set hash"),
            )
            if len(signer_result) != 9 * 32:
                fail(
                    f"{registry_domain} verifier returned an invalid "
                    f"{target_name} signer-set record"
                )
            signer_words = [
                signer_result[index : index + 32] for index in range(0, len(signer_result), 32)
            ]
            expected_signer_words = [
                word_bytes32(signer_set["hash"], "signer-set hash"),
                word_bytes32(target["observer_authority_hash"], "observer authority hash"),
                word_uint(signer_set["version"], "signer-set version", 32),
                *(
                    word_address(address, "signer-set address")
                    for address in signer_set["sorted_addresses"]
                ),
                word_uint(signer_set["valid_from"], "signer-set valid from", 64),
                word_uint(signer_set["valid_until"], "signer-set valid until", 64),
                word_bool(True, "signer-set active"),
            ]
            if signer_words != expected_signer_words:
                fail(
                    f"{registry_domain} verifier {target_name} signer set differs from the manifest"
                )


ROUTE_KEYS = {
    "purpose",
    "version",
    "route_policy_hash",
    "source_domain",
    "destination_domain",
    "source_chain_version",
    "destination_chain_version",
    "source_chain_id",
    "source_coordinator",
    "source_component",
    "source_component_code_hash",
    "destination_chain_id",
    "destination_coordinator",
    "destination_component",
    "destination_component_code_hash",
    "action_family",
    "allowed_actions_bitmap",
    "adapter_id",
    "adapter_code_hash",
    "adapter_set_policy_hash",
    "source_finality_policy_hash",
    "destination_finality_policy_hash",
    "source_signer_set_hash",
    "destination_signer_set_hash",
    "absolute_cap_units",
    "chain_cap_units",
    "adapter_cap_units",
    "activated_at",
    "home_registration_tx_hash",
    "home_registration_block_number",
    "satellite_registration_tx_hash",
    "satellite_registration_block_number",
    "home_registry_hash",
    "satellite_registry_hash",
}

POLICY_KEYS = {
    "route_purpose",
    "policy_hash",
    "destination_evidence",
    "source_chain_id",
    "source_coordinator",
    "source_component",
    "destination_chain_id",
    "destination_coordinator",
    "destination_component",
    "evidence_chain_version",
    "evidence_chain_configuration_hash",
    "action_family",
    "allowed_actions_bitmap",
    "required_depth",
    "observer_authority_hash",
    "signer_set_hash",
    "signer_set_version",
}


def route_live_words(route: dict[str, Any]) -> list[bytes]:
    return [
        word_uint(integer(route["source_chain_version"], "source chain version"), "", 32),
        word_uint(integer(route["destination_chain_version"], "destination chain version"), "", 32),
        word_uint(integer(route["source_chain_id"], "source chain id"), ""),
        word_address(route["source_coordinator"], "source coordinator"),
        word_address(route["source_component"], "source component"),
        word_bytes32(route["source_component_code_hash"], "source component code hash"),
        word_uint(integer(route["destination_chain_id"], "destination chain id"), ""),
        word_address(route["destination_coordinator"], "destination coordinator"),
        word_address(route["destination_component"], "destination component"),
        word_bytes32(route["destination_component_code_hash"], "destination component code hash"),
        word_bytes32(route["action_family"], "action family"),
        word_uint(integer(route["allowed_actions_bitmap"], "allowed actions"), "", 32),
        word_bytes32(route["adapter_id"], "adapter id"),
        word_bytes32(route["adapter_code_hash"], "adapter code hash"),
        word_bytes32(route["adapter_set_policy_hash"], "adapter-set policy hash"),
        word_bytes32(route["source_finality_policy_hash"], "source finality policy hash"),
        word_bytes32(route["destination_finality_policy_hash"], "destination finality policy hash"),
        word_bytes32(route["source_signer_set_hash"], "source signer set hash"),
        word_bytes32(route["destination_signer_set_hash"], "destination signer set hash"),
        word_uint(decimal(route["absolute_cap_units"], "absolute cap"), ""),
        word_uint(decimal(route["chain_cap_units"], "chain cap"), ""),
        word_uint(decimal(route["adapter_cap_units"], "adapter cap"), ""),
        word_uint(integer(route["activated_at"], "activated at"), "", 64),
    ]


def check_routes_and_policies(
    evidence: dict[str, Any],
    domains: dict[str, dict[str, Any]],
    rpcs: dict[str, RPC],
) -> dict[str, dict[str, Any]]:
    routes = sequence(evidence["routes"], "routes")
    route_map: dict[str, dict[str, Any]] = {}
    expected_adapter_set = adapter_set_hash(sequence(evidence["providers"], "providers"))
    for index, raw in enumerate(routes):
        route = mapping(raw, f"routes[{index}]")
        exact_keys(route, ROUTE_KEYS, f"routes[{index}]")
        purpose = text(route["purpose"], f"routes[{index}].purpose")
        if purpose in route_map:
            fail(f"duplicate route purpose {purpose}")
        route_map[purpose] = route
        if integer(route["version"], f"routes[{index}].version", positive=True) != 1:
            fail(f"route {purpose} version must be one")
        source_name = text(route["source_domain"], f"route {purpose}.source_domain")
        destination_name = text(route["destination_domain"], f"route {purpose}.destination_domain")
        if {source_name, destination_name} != {"home", "satellite"}:
            fail(f"route {purpose} must connect the two local domains")
        source = domains[source_name]
        destination = domains[destination_name]
        if (
            route["source_chain_id"] != source["chain_id"]
            or route["destination_chain_id"] != destination["chain_id"]
            or route["source_chain_version"] != source["chain_version"]
            or route["destination_chain_version"] != destination["chain_version"]
            or route["source_coordinator"] != source["contracts"]["coordinator"]["address"]
            or route["destination_coordinator"]
            != destination["contracts"]["coordinator"]["address"]
        ):
            fail(f"route {purpose} domain identities diverge from deployment")
        if route["source_component"] not in {
            value["address"] for value in source["contracts"].values()
        } or route["destination_component"] not in {
            value["address"] for value in destination["contracts"].values()
        }:
            fail(f"route {purpose} component is not a deployed domain contract")
        if route["adapter_set_policy_hash"] != expected_adapter_set:
            fail(f"route {purpose} adapter-set commitment is not canonical")
        computed = route_hash(route)
        for field in ("route_policy_hash", "home_registry_hash", "satellite_registry_hash"):
            if hex32(route[field], f"route {purpose}.{field}") != computed:
                fail(f"route {purpose} {field} is not the Solidity RouteConfig hash")
        expected_words = [word_bytes32(computed, "route hash"), *route_live_words(route)]
        for domain_name in ("home", "satellite"):
            registry = domains[domain_name]["contracts"]["route_registry"]["address"]
            transaction_hash = hex32(
                route[f"{domain_name}_registration_tx_hash"],
                f"route {purpose}.{domain_name}_registration_tx_hash",
            )
            block_number = integer(
                route[f"{domain_name}_registration_block_number"],
                f"route {purpose}.{domain_name}_registration_block_number",
                positive=True,
            )
            receipt = rpcs[domain_name].call("eth_getTransactionReceipt", [transaction_hash])
            if (
                not isinstance(receipt, dict)
                or receipt.get("status") != "0x1"
                or int(receipt.get("blockNumber", "0x0"), 16) != block_number
            ):
                fail(f"route {purpose} registration receipt differs on {domain_name}")
            route_event_topic = (
                "0x"
                + keccak256(
                    b"RouteRegistered(bytes32,uint256,uint256,address,address,bytes32,uint32)"
                ).hex()
            )
            matching_registration = [
                log
                for log in receipt.get("logs", [])
                if log.get("address", "").lower() == registry
                and len(log.get("topics", [])) == 4
                and log["topics"][0].lower() == route_event_topic
                and log["topics"][1].lower() == computed
                and log["topics"][2].lower()
                == "0x" + word_uint(route["source_chain_id"], "source chain").hex()
                and log["topics"][3].lower()
                == "0x" + word_uint(route["destination_chain_id"], "destination chain").hex()
            ]
            if len(matching_registration) != 1:
                fail(f"route {purpose} lacks one canonical registration event on {domain_name}")
            result = rpcs[domain_name].eth_call(
                registry, "route(bytes32)", word_bytes32(computed, "route hash")
            )
            if len(result) != 27 * 32:
                fail(f"route {purpose} has invalid live registry encoding on {domain_name}")
            words = [result[offset : offset + 32] for offset in range(0, len(result), 32)]
            if words[:24] != expected_words:
                fail(f"route {purpose} live RouteConfig differs on {domain_name}")
            if (
                int.from_bytes(words[24], "big") != 0
                or int.from_bytes(words[25], "big") != 0
                or int.from_bytes(words[26], "big") != 1
            ):
                fail(f"route {purpose} is deprecated, paused, or inactive on {domain_name}")
    if set(route_map) != REQUIRED_ROUTE_PURPOSES:
        fail("complete seven-route Phase 8 policy set is not present")

    policy_maps: dict[str, dict[tuple[str, bool], dict[str, Any]]] = {}
    for domain_name, domain in domains.items():
        policies = sequence(domain["finality_policies"], f"domains.{domain_name}.finality_policies")
        policy_map: dict[tuple[str, bool], dict[str, Any]] = {}
        for index, raw in enumerate(policies):
            policy = mapping(raw, f"{domain_name}.finality_policies[{index}]")
            exact_keys(policy, POLICY_KEYS, f"{domain_name}.finality_policies[{index}]")
            purpose = text(policy["route_purpose"], "policy.route_purpose")
            destination_evidence = policy["destination_evidence"]
            if not isinstance(destination_evidence, bool):
                fail("policy.destination_evidence must be boolean")
            key = (purpose, destination_evidence)
            if key in policy_map:
                fail(f"duplicate {domain_name} finality policy {key}")
            if purpose not in route_map:
                fail(f"finality policy references unknown route {purpose}")
            route = route_map[purpose]
            for field in (
                "source_chain_id",
                "source_coordinator",
                "source_component",
                "destination_chain_id",
                "destination_coordinator",
                "destination_component",
                "action_family",
                "allowed_actions_bitmap",
            ):
                if policy[field] != route[field]:
                    fail(f"{domain_name} {purpose} finality policy {field} diverges")
            evidence_domain = (
                domains[route["destination_domain"]]
                if destination_evidence
                else domains[route["source_domain"]]
            )
            if (
                policy["evidence_chain_version"] != evidence_domain["chain_version"]
                or policy["evidence_chain_configuration_hash"]
                != evidence_domain["configuration_hash"]
                or policy["required_depth"] != evidence_domain["confirmation_depth"]
                or policy["observer_authority_hash"] != evidence_domain["observer_authority_hash"]
                or policy["signer_set_hash"] != evidence_domain["signer_set"]["hash"]
                or policy["signer_set_version"] != evidence_domain["signer_set"]["version"]
            ):
                fail(f"{domain_name} {purpose} finality trust diverges from evidence domain")
            computed = finality_policy_hash(policy)
            if hex32(policy["policy_hash"], "policy.policy_hash") != computed:
                fail(f"{domain_name} {purpose} policy hash is not Solidity FinalityPolicyConfig")
            route_field = (
                "destination_finality_policy_hash"
                if destination_evidence
                else "source_finality_policy_hash"
            )
            if route[route_field] != computed:
                fail(f"{domain_name} {purpose} policy is not pinned by its route")
            verifier = domain["contracts"]["finality_verifier"]["address"]
            result = rpcs[domain_name].eth_call(
                verifier, "finalityPolicy(bytes32)", word_bytes32(computed, "policy hash")
            )
            expected = [
                word_bool(policy["destination_evidence"], "destination evidence"),
                word_uint(policy["source_chain_id"], "source chain"),
                word_address(policy["source_coordinator"], "source coordinator"),
                word_address(policy["source_component"], "source component"),
                word_uint(policy["destination_chain_id"], "destination chain"),
                word_address(policy["destination_coordinator"], "destination coordinator"),
                word_address(policy["destination_component"], "destination component"),
                word_uint(policy["evidence_chain_version"], "evidence version", 32),
                word_bytes32(policy["evidence_chain_configuration_hash"], "evidence configuration"),
                word_bytes32(policy["action_family"], "action family"),
                word_uint(policy["allowed_actions_bitmap"], "action bitmap", 32),
                word_uint(policy["required_depth"], "required depth", 64),
                word_bytes32(policy["observer_authority_hash"], "observer authority"),
                word_bytes32(policy["signer_set_hash"], "signer set"),
                word_uint(policy["signer_set_version"], "signer version", 32),
            ]
            if result != b"".join(expected):
                fail(f"{domain_name} {purpose} live finality policy differs")
            policy_map[key] = policy
        if set(policy_map) != {
            (purpose, destination)
            for purpose in REQUIRED_ROUTE_PURPOSES
            for destination in (False, True)
        }:
            fail(f"{domain_name} does not contain both finality policies for all routes")
        policy_maps[domain_name] = policy_map
    if policy_maps["home"] != policy_maps["satellite"]:
        fail("home and satellite finality policy registrations differ")
    return route_map


def canonical_exposure_policy_hash(exposure: dict[str, Any]) -> str:
    return solidity_hash(
        "UNIFIED_BRIDGE_EXPOSURE_POLICY_V1",
        [
            word_uint(
                decimal(
                    exposure["circulating_supply_reference_units"],
                    "circulating supply reference",
                    positive=True,
                ),
                "circulating supply reference",
            ),
            word_bytes32(
                exposure["circulating_supply_evidence_hash"],
                "circulating supply evidence hash",
            ),
            *(
                word_uint(
                    decimal(exposure[field], field, positive=True),
                    field,
                )
                for field in (
                    "route_absolute_cap_units",
                    "chain_absolute_cap_units",
                    "adapter_absolute_cap_units",
                    "aggregate_absolute_cap_units",
                )
            ),
            word_uint(
                exposure["route_percentage_ceiling_basis_points"],
                "route percentage ceiling",
                16,
            ),
            word_uint(
                exposure["aggregate_percentage_ceiling_basis_points"],
                "aggregate percentage ceiling",
                16,
            ),
            word_uint(exposure["activation_delay"], "activation delay", 64),
            word_uint(exposure["active_from"], "active from", 64),
        ],
    )


def check_exposure_policy(
    evidence: dict[str, Any],
    domains: dict[str, dict[str, Any]],
    rpcs: dict[str, RPC],
    routes: dict[str, dict[str, Any]],
) -> None:
    exposure = mapping(evidence["exposure_policy"], "exposure_policy")
    exact_keys(
        exposure,
        {
            "policy_version",
            "policy_hash",
            "circulating_supply_reference_units",
            "circulating_supply_evidence_hash",
            "route_absolute_cap_units",
            "chain_absolute_cap_units",
            "adapter_absolute_cap_units",
            "aggregate_absolute_cap_units",
            "route_percentage_ceiling_basis_points",
            "aggregate_percentage_ceiling_basis_points",
            "activation_delay",
            "active_from",
        },
        "exposure_policy",
    )
    if (
        integer(exposure["policy_version"], "exposure policy version", positive=True) != 1
        or integer(
            exposure["route_percentage_ceiling_basis_points"],
            "route percentage ceiling",
            positive=True,
        )
        != 500
        or integer(
            exposure["aggregate_percentage_ceiling_basis_points"],
            "aggregate percentage ceiling",
            positive=True,
        )
        != 1500
        or integer(exposure["activation_delay"], "activation delay") != 0
    ):
        fail("exposure policy does not use the frozen initial local limits")
    numeric_fields = (
        "circulating_supply_reference_units",
        "route_absolute_cap_units",
        "chain_absolute_cap_units",
        "adapter_absolute_cap_units",
        "aggregate_absolute_cap_units",
    )
    units = {
        field: decimal(exposure[field], f"exposure_policy.{field}", positive=True)
        for field in numeric_fields
    }
    evidence_hash = hex32(
        exposure["circulating_supply_evidence_hash"],
        "circulating supply evidence hash",
    )
    active_from = integer(exposure["active_from"], "exposure active from", positive=True)
    words = [
        word_uint(units["circulating_supply_reference_units"], "supply reference"),
        word_bytes32(evidence_hash, "supply evidence hash"),
        word_uint(units["route_absolute_cap_units"], "route cap"),
        word_uint(units["chain_absolute_cap_units"], "chain cap"),
        word_uint(units["adapter_absolute_cap_units"], "adapter cap"),
        word_uint(units["aggregate_absolute_cap_units"], "aggregate cap"),
        word_uint(
            exposure["route_percentage_ceiling_basis_points"],
            "route percentage ceiling",
            16,
        ),
        word_uint(
            exposure["aggregate_percentage_ceiling_basis_points"],
            "aggregate percentage ceiling",
            16,
        ),
        word_uint(exposure["activation_delay"], "activation delay", 64),
        word_uint(active_from, "active from", 64),
    ]
    policy_hash = canonical_exposure_policy_hash(exposure)
    if hex32(exposure["policy_hash"], "exposure policy hash") != policy_hash:
        fail("exposure policy hash is not Solidity-canonical")
    mint = routes["MINT"]
    if (
        mint["version"] != exposure["policy_version"]
        or mint["absolute_cap_units"] != exposure["route_absolute_cap_units"]
        or mint["chain_cap_units"] != exposure["chain_absolute_cap_units"]
        or mint["adapter_cap_units"] != exposure["adapter_absolute_cap_units"]
        or mint["activated_at"] != active_from
    ):
        fail("MINT route differs from the exact deployed exposure policy")
    home = domains["home"]
    rpc = rpcs["home"]
    policy_contract = home["contracts"]["bridge_exposure_policy"]["address"]
    live_policy = rpc.eth_call(
        policy_contract,
        "policy(bytes32)",
        word_bytes32(policy_hash, "exposure policy hash"),
    )
    if live_policy != b"".join(words):
        fail("manifest exposure policy differs from the live home contract")
    active_policy = rpc.eth_call(
        policy_contract,
        "activePolicyForRoute(bytes32)",
        word_bytes32(mint["route_policy_hash"], "MINT route hash"),
    )
    if active_policy != word_bytes32(policy_hash, "exposure policy hash"):
        fail("MINT route does not use the declared live exposure policy")
    canonical_token = home["contracts"]["canonical_uft"]["address"]
    live_max_supply = rpc.eth_call(canonical_token, "MAX_SUPPLY()")
    if live_max_supply != word_uint(
        units["circulating_supply_reference_units"],
        "circulating supply reference",
    ):
        fail("circulating supply reference differs from live canonical MAX_SUPPLY")


def check_providers_and_recovery(
    evidence: dict[str, Any],
    domains: dict[str, dict[str, Any]],
    rpcs: dict[str, RPC],
) -> None:
    providers = sequence(evidence["providers"], "providers")
    if len(providers) != 2:
        fail("exactly two local transport providers are required")
    identities: list[str] = []
    for index, raw in enumerate(providers):
        provider = mapping(raw, f"providers[{index}]")
        exact_keys(provider, {"id", "url", "authority"}, f"providers[{index}]")
        identities.append(text(provider["id"], f"providers[{index}].id"))
        local_rpc_url(provider["url"], f"providers[{index}].url")
        if provider["authority"] != "TRANSPORT_ONLY":
            fail("providers cannot assert execution or finality authority")
    if identities != ["mock-bridge-provider-a", "mock-bridge-provider-b"]:
        fail("provider identity/order drifted")

    recovery = mapping(evidence["recovery"], "recovery")
    exact_keys(
        recovery,
        {
            "action",
            "threshold",
            "authorizer_set_version",
            "authorizer_set_hash",
            "sorted_authorizer_addresses",
        },
        "recovery",
    )
    if (
        recovery["action"] != "TOMBSTONE_THEN_COMPENSATE"
        or recovery["threshold"] != 2
        or recovery["authorizer_set_version"] != 1
        or recovery["sorted_authorizer_addresses"] != EXPECTED_SIGNERS
    ):
        fail("recovery policy differs from the frozen local authority")
    if recovery_authorizer_hash(recovery) != hex32(
        recovery["authorizer_set_hash"], "recovery.authorizer_set_hash"
    ):
        fail("recovery authorizer-set hash is not the Solidity hash")
    for domain_name, domain in domains.items():
        controller = domain["contracts"]["recovery_controller"]["address"]
        rpc = rpcs[domain_name]
        expected_calls = {
            "AUTHORIZER_SET_VERSION()": word_uint(1, "authorizer version", 32),
            "RECOVERY_THRESHOLD()": word_uint(2, "recovery threshold", 8),
            "authorizerSetHash()": word_bytes32(
                recovery["authorizer_set_hash"], "authorizer-set hash"
            ),
            "coordinator()": word_address(
                domain["contracts"]["coordinator"]["address"], "coordinator"
            ),
            "routeRegistry()": word_address(
                domain["contracts"]["route_registry"]["address"], "route registry"
            ),
            "finalityVerifier()": word_address(
                domain["contracts"]["finality_verifier"]["address"],
                "finality verifier",
            ),
        }
        for signature, expected in expected_calls.items():
            if rpc.eth_call(controller, signature) != expected:
                fail(f"{domain_name} recovery controller {signature} differs from the manifest")
        for index, address in enumerate(recovery["sorted_authorizer_addresses"]):
            if rpc.eth_call(
                controller,
                "recoverySigners(uint256)",
                word_uint(index, "recovery signer index"),
            ) != word_address(address, "recovery signer"):
                fail(f"{domain_name} recovery signer {index} differs from manifest")


ENVELOPE_KEYS = {
    "schema_version",
    "message_id",
    "protocol_id",
    "source_chain_id",
    "source_coordinator",
    "source_component",
    "destination_chain_id",
    "destination_coordinator",
    "destination_component",
    "lane_id",
    "source_nonce",
    "aggregate_id",
    "action_ordinal",
    "payload_hash",
    "created_at",
    "expires_at",
    "route_policy_hash",
    "adapter_set_policy_hash",
    "source_finality_policy_hash",
    "destination_finality_policy_hash",
    "correlation_id",
    "causation_message_id",
    "superseded_message_id",
}
SOURCE_KEYS = {
    "chain_id",
    "transaction_hash",
    "block_hash",
    "block_number",
    "transaction_index",
    "log_index",
    "raw_evidence_object_hash",
    "proof_id",
    "proof_hash",
    "certificate_id",
    "certificate_hash",
    "proof",
    "certificate",
    "authenticated_inclusion",
}
DESTINATION_KEYS = {
    "chain_id",
    "transaction_hash",
    "block_hash",
    "block_number",
    "transaction_index",
    "log_index",
    "result_hash",
}
ACK_KEYS = {
    "transaction_hash",
    "block_hash",
    "block_number",
    "transaction_index",
    "log_index",
    "commitment",
    "finalized",
    "proof_id",
    "proof_hash",
    "certificate_id",
    "certificate_hash",
    "raw_evidence_object_hash",
    "proof",
    "certificate",
    "authenticated_inclusion",
}


def check_receipt_event(
    rpc: RPC,
    transaction_hash: str,
    expected_address: str,
    expected_topic0: str,
    message_id: str,
    block_hash: str,
    block_number: int,
    log_index: int | None = None,
    expected_topics: list[str] | None = None,
    expected_data: bytes | None = None,
) -> dict[str, Any]:
    receipt = rpc.call("eth_getTransactionReceipt", [transaction_hash])
    if not isinstance(receipt, dict) or receipt.get("status") != "0x1":
        fail(f"flow transaction {transaction_hash} is absent or reverted")
    if (
        receipt.get("blockHash", "").lower() != block_hash
        or int(receipt.get("blockNumber", "0x0"), 16) != block_number
    ):
        fail(f"flow transaction {transaction_hash} block identity differs")
    matching = []
    for log in receipt.get("logs", []):
        topics = log.get("topics", [])
        if (
            log.get("address", "").lower() == expected_address
            and len(topics) >= 2
            and topics[0].lower() == expected_topic0
            and topics[1].lower() == message_id
        ):
            matching.append(log)
    if len(matching) != 1:
        fail(f"flow transaction {transaction_hash} lacks one exact canonical message event")
    if (
        expected_topics is not None
        and [topic.lower() for topic in matching[0].get("topics", [])] != expected_topics
    ):
        fail(f"flow transaction {transaction_hash} canonical event topics differ")
    if (
        expected_data is not None
        and matching[0].get("data", "").lower() != "0x" + expected_data.hex()
    ):
        fail(f"flow transaction {transaction_hash} canonical event data differs")
    if log_index is not None and int(matching[0].get("logIndex", "0x0"), 16) != log_index:
        fail(f"flow transaction {transaction_hash} log index differs")
    return cast("dict[str, Any]", receipt)


def check_provider_attempt_path(
    raw_attempts: Any,
    *,
    sequence_number: int,
    message_id: str,
    payload_hash: str,
    source_proof_hash: str,
) -> tuple[int, bool]:
    attempts = sequence(raw_attempts, "message.provider_attempts")
    expected_attempts = (
        [
            ("mock-bridge-provider-a", 1, "FAILED", True),
            ("mock-bridge-provider-b", 2, "DELIVERED", False),
        ]
        if sequence_number == 1
        else [("mock-bridge-provider-a", 1, "DELIVERED", False)]
    )
    actual_attempts: list[tuple[Any, Any, Any, Any]] = []
    for attempt_index, raw_attempt in enumerate(attempts):
        attempt = mapping(raw_attempt, f"provider_attempts[{attempt_index}]")
        exact_keys(
            attempt,
            {
                "provider_id",
                "attempt_number",
                "status",
                "retryable",
                "message_id",
                "payload_hash",
                "source_proof_hash",
                "transport_receipt_hash",
            },
            f"provider_attempts[{attempt_index}]",
        )
        if (
            attempt["message_id"] != message_id
            or attempt["payload_hash"] != payload_hash
            or attempt["source_proof_hash"] != source_proof_hash
        ):
            fail("provider attempt changed immutable delivery content")
        hex32(
            attempt["transport_receipt_hash"],
            f"provider_attempts[{attempt_index}].transport_receipt_hash",
        )
        actual_attempts.append(
            (
                attempt["provider_id"],
                attempt["attempt_number"],
                attempt["status"],
                attempt["retryable"],
            )
        )
    if actual_attempts != expected_attempts:
        fail("provider attempts differ from the exact observed failover path")
    return len(attempts), sequence_number == 1


def registry_purpose_for_message(purpose: str) -> str:
    registry_purpose = MESSAGE_PURPOSE_TO_REGISTRY_PURPOSE.get(purpose)
    if registry_purpose is None:
        fail(f"message route purpose is outside the exact lowercase vocabulary: {purpose}")
    return registry_purpose


def check_canonical_message_step(index: int, purpose: str, action: int) -> None:
    if index < 0 or index >= len(EXPECTED_MESSAGE_ACTION_PURPOSES):
        fail("flow contains a message outside the canonical eight-message sequence")
    expected_action, expected_purpose = EXPECTED_MESSAGE_ACTION_PURPOSES[index]
    if action != expected_action or purpose != expected_purpose:
        fail(f"flow message {index + 1} action/route order is not canonical")


def check_flow(
    evidence: dict[str, Any],
    domains: dict[str, dict[str, Any]],
    rpcs: dict[str, RPC],
    routes: dict[str, dict[str, Any]],
) -> None:
    flow = mapping(evidence["flow"], "flow")
    required = {
        "loan_id",
        "loan_account",
        "funding_lock_id",
        "collateral_id",
        "principal_units",
        "collateral_units",
        "canonical_asset",
        "wrapped_asset",
        "collateral_asset",
        "messages",
        "replays",
        "final_state",
    }
    exact_keys(flow, required, "flow")
    for field in ("loan_id", "funding_lock_id", "collateral_id"):
        hex32(flow[field], f"flow.{field}")
    loan_account = chain_address(flow["loan_account"], "flow.loan_account", "home", 31337)
    if loan_account != domains["home"]["contracts"]["loan_account"]["address"]:
        fail("flow.loan_account differs from the home deployment record")
    principal = decimal(flow["principal_units"], "flow.principal_units", positive=True)
    collateral = decimal(flow["collateral_units"], "flow.collateral_units", positive=True)
    asset_expectations = {
        "canonical_asset": (
            "home",
            31337,
            domains["home"]["contracts"]["canonical_uft"]["address"],
        ),
        "wrapped_asset": (
            "satellite",
            31338,
            domains["satellite"]["contracts"]["wrapped_uft"]["address"],
        ),
        "collateral_asset": (
            "satellite",
            31338,
            domains["satellite"]["contracts"]["collateral_token"]["address"],
        ),
    }
    for field, (domain_name, chain_id, expected_address) in asset_expectations.items():
        actual = chain_address(flow[field], f"flow.{field}", domain_name, chain_id)
        if actual != expected_address:
            fail(f"flow.{field} differs from the deployed contract")

    messages = sequence(flow["messages"], "flow.messages")
    if len(messages) != len(EXPECTED_MESSAGE_ACTION_PURPOSES):
        fail("flow does not contain the exact canonical eight-message sequence")
    actions: set[int] = set()
    message_routes: dict[str, dict[str, Any]] = {}
    destination_receipts: dict[int, dict[str, Any]] = {}
    prior_sequence = 0
    failover_seen = False
    provider_attempt_count = 0
    sent_topic = (
        "0x"
        + keccak256(
            b"MessageSent(bytes32,bytes32,uint64,bytes32,uint8,bytes32,uint256,address)"
        ).hex()
    )
    executed_topic = (
        "0x" + keccak256(b"MessageExecuted(bytes32,bytes32,uint64,address,bytes32)").hex()
    )
    acknowledged_topic = "0x" + keccak256(b"MessageAcknowledged(bytes32,bytes32,bytes32)").hex()
    for index, raw in enumerate(messages):
        message = mapping(raw, f"flow.messages[{index}]")
        exact_keys(
            message,
            {
                "sequence",
                "route_purpose",
                "envelope",
                "payload",
                "source",
                "provider_attempts",
                "destination",
                "acknowledgement",
                "source_final",
                "destination_executed",
            },
            f"flow.messages[{index}]",
        )
        sequence_number = integer(message["sequence"], "message.sequence", positive=True)
        if sequence_number != prior_sequence + 1:
            fail("flow message sequence is not contiguous")
        prior_sequence = sequence_number
        purpose = text(message["route_purpose"], "message.route_purpose")
        registry_purpose = registry_purpose_for_message(purpose)
        if registry_purpose not in routes:
            fail(f"flow message references unknown route purpose {purpose}")
        route = routes[registry_purpose]
        source_domain_name = route["source_domain"]
        destination_domain_name = route["destination_domain"]
        envelope = mapping(message["envelope"], "message.envelope")
        exact_keys(envelope, ENVELOPE_KEYS, "message.envelope")
        payload = hex_bytes(message["payload"], "message.payload")
        if "0x" + keccak256(payload).hex() != envelope["payload_hash"]:
            fail("flow payload does not match the exact envelope payload hash")
        action = integer(envelope["action_ordinal"], "envelope.action_ordinal", positive=True)
        check_canonical_message_step(index, purpose, action)
        actions.add(action)
        if envelope["protocol_id"] != evidence["protocol_id"]:
            fail("flow envelope protocol ID differs from deployment")
        for field in (
            "source_chain_id",
            "source_coordinator",
            "source_component",
            "destination_chain_id",
            "destination_coordinator",
            "destination_component",
            "route_policy_hash",
            "adapter_set_policy_hash",
            "source_finality_policy_hash",
            "destination_finality_policy_hash",
        ):
            route_field = field
            if envelope[field] != route[route_field]:
                fail(f"flow envelope {field} differs from its Solidity route")
        if envelope["created_at"] >= envelope["expires_at"]:
            fail("flow envelope expiry is not after creation")
        for signer_domain in (
            domains[source_domain_name],
            domains[destination_domain_name],
        ):
            signer_set = signer_domain["signer_set"]
            if (
                envelope["created_at"] < signer_set["valid_from"]
                or envelope["expires_at"] > signer_set["valid_until"]
            ):
                fail("flow envelope falls outside a bound signer-set validity window")
        if lane_hash(envelope, route["action_family"]) != envelope["lane_id"]:
            fail("flow envelope lane ID is not canonical")
        computed_message_id = message_hash(envelope)
        if computed_message_id != hex32(envelope["message_id"], "envelope.message_id"):
            fail("flow message ID is not the canonical Solidity digest")
        message_routes[computed_message_id] = route

        source = mapping(message["source"], "message.source")
        exact_keys(source, SOURCE_KEYS, "message.source")
        if source["chain_id"] != route["source_chain_id"]:
            fail("flow source chain differs from route")
        source_tx = hex32(source["transaction_hash"], "message.source.transaction_hash")
        source_block_hash = hex32(source["block_hash"], "message.source.block_hash")
        source_block = integer(source["block_number"], "message.source.block_number", positive=True)
        source_index = integer(source["transaction_index"], "message.source.transaction_index")
        source_log = integer(source["log_index"], "message.source.log_index")
        for field in (
            "raw_evidence_object_hash",
            "proof_hash",
            "certificate_hash",
        ):
            hex32(source[field], f"message.source.{field}")
        text(source["proof_id"], "message.source.proof_id")
        text(source["certificate_id"], "message.source.certificate_id")
        receipt = check_receipt_event(
            rpcs[source_domain_name],
            source_tx,
            route["source_coordinator"],
            sent_topic,
            computed_message_id,
            source_block_hash,
            source_block,
            source_log,
            expected_topics=[
                sent_topic,
                computed_message_id,
                envelope["lane_id"],
                "0x" + word_uint(envelope["source_nonce"], "source nonce", 64).hex(),
            ],
            expected_data=b"".join(
                [
                    word_bytes32(envelope["aggregate_id"], "aggregate ID"),
                    word_uint(envelope["action_ordinal"], "action ordinal", 8),
                    word_bytes32(envelope["payload_hash"], "payload hash"),
                    word_uint(
                        envelope["destination_chain_id"],
                        "destination chain ID",
                    ),
                    word_address(
                        envelope["destination_component"],
                        "destination component",
                    ),
                ]
            ),
        )
        if int(receipt.get("transactionIndex", "0x0"), 16) != source_index:
            fail("flow source transaction index differs")
        expected_event_hash = source_message_event_hash(envelope)
        source_proof_hash, source_certificate_hash = check_proof_certificate(
            source["proof"],
            source["certificate"],
            label=f"message {sequence_number} source",
            expected_domain=domains[source_domain_name],
            verifier_domain=domains[destination_domain_name],
            expected_message_id=computed_message_id,
            expected_event_hash=expected_event_hash,
            expected_policy_hash=envelope["source_finality_policy_hash"],
        )
        if (
            source_proof_hash != source["proof_hash"]
            or source_certificate_hash != source["certificate_hash"]
        ):
            fail("source proof/certificate hashes do not match their exact public bytes")
        source_proof = mapping(source["proof"], "message.source.proof")
        if (
            source_proof["transaction_hash"] != source_tx
            or source_proof["source_block_hash"] != source_block_hash
            or source_proof["source_block_number"] != source_block
            or source_proof["transaction_index"] != source_index
            or source_proof["log_index"] != source_log
        ):
            fail("authenticated source proof identity differs from the live source receipt")
        check_authenticated_inclusion(
            source["authenticated_inclusion"],
            proof=source_proof,
            chain_id=source["chain_id"],
            observer_public_key=domains[source_domain_name]["observer_public_key_ed25519"],
            expected_address=route["source_coordinator"],
            expected_topics=[
                sent_topic,
                computed_message_id,
                envelope["lane_id"],
                "0x" + word_uint(envelope["source_nonce"], "source nonce", 64).hex(),
            ],
            expected_data=b"".join(
                [
                    word_bytes32(envelope["aggregate_id"], "aggregate ID"),
                    word_uint(envelope["action_ordinal"], "action ordinal", 8),
                    word_bytes32(envelope["payload_hash"], "payload hash"),
                    word_uint(
                        envelope["destination_chain_id"],
                        "destination chain ID",
                    ),
                    word_address(
                        envelope["destination_component"],
                        "destination component",
                    ),
                ]
            ),
            expected_raw_hash=source["raw_evidence_object_hash"],
            label=f"message {sequence_number} source",
        )

        attempt_count, observed_failover = check_provider_attempt_path(
            message["provider_attempts"],
            sequence_number=sequence_number,
            message_id=computed_message_id,
            payload_hash=envelope["payload_hash"],
            source_proof_hash=source["proof_hash"],
        )
        provider_attempt_count += attempt_count
        failover_seen = failover_seen or observed_failover

        destination = mapping(message["destination"], "message.destination")
        exact_keys(destination, DESTINATION_KEYS, "message.destination")
        if destination["chain_id"] != route["destination_chain_id"]:
            fail("flow destination chain differs from route")
        destination_tx = hex32(
            destination["transaction_hash"], "message.destination.transaction_hash"
        )
        destination_block_hash = hex32(destination["block_hash"], "message.destination.block_hash")
        destination_block = integer(
            destination["block_number"], "message.destination.block_number", positive=True
        )
        destination_index = integer(
            destination["transaction_index"],
            "message.destination.transaction_index",
        )
        destination_log = integer(destination["log_index"], "message.destination.log_index")
        destination_result_hash = hex32(
            destination["result_hash"], "message.destination.result_hash"
        )
        destination_receipts[action] = check_receipt_event(
            rpcs[destination_domain_name],
            destination_tx,
            route["destination_coordinator"],
            executed_topic,
            computed_message_id,
            destination_block_hash,
            destination_block,
            destination_log,
            expected_topics=[
                executed_topic,
                computed_message_id,
                envelope["lane_id"],
                "0x" + word_uint(envelope["source_nonce"], "source nonce", 64).hex(),
            ],
            expected_data=b"".join(
                [
                    word_address(
                        envelope["destination_component"],
                        "destination component",
                    ),
                    word_bytes32(destination_result_hash, "destination result hash"),
                ]
            ),
        )
        if (
            int(destination_receipts[action].get("transactionIndex", "0x0"), 16)
            != destination_index
        ):
            fail("flow destination transaction index differs")
        destination_transaction = rpcs[destination_domain_name].call(
            "eth_getTransactionByHash", [destination_tx]
        )
        expected_execution_input = (
            "0x"
            + execute_message_calldata(
                envelope,
                payload,
                mapping(source["proof"], "source.proof"),
                mapping(source["certificate"], "source.certificate"),
            ).hex()
        )
        if (
            not isinstance(destination_transaction, dict)
            or destination_transaction.get("input", "").lower() != expected_execution_input
        ):
            fail("destination transaction calldata differs from the exact public evidence")
        live_result = rpcs[destination_domain_name].eth_call(
            route["destination_coordinator"],
            "executionResult(bytes32)",
            bytes.fromhex(computed_message_id[2:]),
        )
        if len(live_result) != 32 or "0x" + live_result.hex() != destination_result_hash:
            fail("destination executionResult differs from release evidence")

        acknowledgement = mapping(message["acknowledgement"], "message.acknowledgement")
        exact_keys(acknowledgement, ACK_KEYS, "message.acknowledgement")
        if acknowledgement["finalized"] is not True:
            fail("flow acknowledgement is not final")
        acknowledgement_tx = hex32(
            acknowledgement["transaction_hash"], "acknowledgement.transaction_hash"
        )
        acknowledgement_block_hash = hex32(
            acknowledgement["block_hash"], "acknowledgement.block_hash"
        )
        acknowledgement_block = integer(
            acknowledgement["block_number"],
            "acknowledgement.block_number",
            positive=True,
        )
        acknowledgement_index = integer(
            acknowledgement["transaction_index"],
            "acknowledgement.transaction_index",
        )
        acknowledgement_log = integer(acknowledgement["log_index"], "acknowledgement.log_index")
        acknowledgement_commitment = hex32(
            acknowledgement["commitment"], "acknowledgement.commitment"
        )
        raw_acknowledgement_hash = hex32(
            acknowledgement["raw_evidence_object_hash"],
            "acknowledgement.raw_evidence_object_hash",
        )
        ack_receipt = rpcs[source_domain_name].call(
            "eth_getTransactionReceipt", [acknowledgement_tx]
        )
        if not isinstance(ack_receipt, dict) or ack_receipt.get("status") != "0x1":
            fail("acknowledgement transaction is absent or reverted")
        if (
            ack_receipt.get("blockHash", "").lower() != acknowledgement_block_hash
            or int(ack_receipt.get("blockNumber", "0x0"), 16) != acknowledgement_block
            or int(ack_receipt.get("transactionIndex", "0x0"), 16) != acknowledgement_index
        ):
            fail("acknowledgement transaction block identity differs")
        matching_ack = False
        for log in ack_receipt.get("logs", []):
            topics = log.get("topics", [])
            if (
                log.get("address", "").lower() == route["source_coordinator"]
                and len(topics) == 4
                and topics[0].lower() == acknowledged_topic
                and topics[1].lower() == computed_message_id
                and topics[2].lower() == destination_result_hash
                and topics[3].lower() == acknowledgement_commitment
                and log.get("data", "").lower() == "0x"
            ):
                if int(log.get("logIndex", "0x0"), 16) != acknowledgement_log:
                    fail("acknowledgement event log index differs")
                matching_ack = True
        if not matching_ack:
            fail("acknowledgement receipt lacks the exact canonical commitment")
        live_ack = rpcs[source_domain_name].eth_call(
            route["source_coordinator"],
            "acknowledgementCommitment(bytes32)",
            bytes.fromhex(computed_message_id[2:]),
        )
        if len(live_ack) != 32 or "0x" + live_ack.hex() != acknowledgement_commitment:
            fail("source acknowledgement commitment differs from release evidence")
        acknowledgement_proof_hash, acknowledgement_certificate_hash = check_proof_certificate(
            acknowledgement["proof"],
            acknowledgement["certificate"],
            label=f"message {sequence_number} acknowledgement",
            expected_domain=domains[destination_domain_name],
            verifier_domain=domains[source_domain_name],
            expected_message_id=computed_message_id,
            expected_event_hash=acknowledgement_commitment,
            expected_policy_hash=envelope["destination_finality_policy_hash"],
        )
        if (
            acknowledgement_proof_hash != acknowledgement["proof_hash"]
            or acknowledgement_certificate_hash != acknowledgement["certificate_hash"]
        ):
            fail("acknowledgement proof/certificate hashes do not match their exact public bytes")
        acknowledgement_proof = mapping(
            acknowledgement["proof"],
            "message.acknowledgement.proof",
        )
        if (
            acknowledgement_proof["transaction_hash"] != destination_tx
            or acknowledgement_proof["source_block_hash"] != destination_block_hash
            or acknowledgement_proof["source_block_number"] != destination_block
            or acknowledgement_proof["transaction_index"] != destination_index
            or acknowledgement_proof["log_index"] != destination_log
        ):
            fail(
                "authenticated acknowledgement proof identity differs from "
                "the live destination receipt"
            )
        check_authenticated_inclusion(
            acknowledgement["authenticated_inclusion"],
            proof=acknowledgement_proof,
            chain_id=destination["chain_id"],
            observer_public_key=domains[destination_domain_name]["observer_public_key_ed25519"],
            expected_address=route["destination_coordinator"],
            expected_topics=[
                executed_topic,
                computed_message_id,
                envelope["lane_id"],
                "0x" + word_uint(envelope["source_nonce"], "source nonce", 64).hex(),
            ],
            expected_data=b"".join(
                [
                    word_address(
                        envelope["destination_component"],
                        "destination component",
                    ),
                    word_bytes32(destination_result_hash, "destination result hash"),
                ]
            ),
            expected_raw_hash=raw_acknowledgement_hash,
            label=f"message {sequence_number} acknowledgement",
        )
        acknowledgement_transaction = rpcs[source_domain_name].call(
            "eth_getTransactionByHash", [acknowledgement_tx]
        )
        expected_ack_input = (
            "0x"
            + acknowledgement_calldata(
                envelope,
                destination_result_hash,
                mapping(acknowledgement["proof"], "acknowledgement.proof"),
                mapping(acknowledgement["certificate"], "acknowledgement.certificate"),
            ).hex()
        )
        if (
            not isinstance(acknowledgement_transaction, dict)
            or acknowledgement_transaction.get("input", "").lower() != expected_ack_input
        ):
            fail("acknowledgement calldata differs from the exact public evidence")
        if message["source_final"] is not True or message["destination_executed"] is not True:
            fail("flow message is not final and executed")

    if not REQUIRED_ACTIONS <= actions:
        fail("flow is missing one or more required action ordinals")
    if not failover_seen:
        fail("flow has no exact provider-A to provider-B failover")
    if provider_attempt_count != 9:
        fail("flow does not contain exactly nine observed provider attempts")

    replays = sequence(flow["replays"], "flow.replays")
    purposes: set[str] = set()
    for index, raw in enumerate(replays):
        replay = mapping(raw, f"flow.replays[{index}]")
        exact_keys(
            replay,
            {
                "purpose",
                "message_id",
                "destination_chain_id",
                "transaction_hash",
                "block_hash",
                "block_number",
                "original_result_hash",
                "replay_result_hash",
                "economic_effect_delta_units",
                "duplicate_prevented",
            },
            f"flow.replays[{index}]",
        )
        purpose = text(replay["purpose"], "replay.purpose")
        purposes.add(purpose)
        message_id = hex32(replay["message_id"], "replay.message_id")
        if message_id not in message_routes:
            fail(f"{purpose} replay references a message outside this flow")
        route = message_routes[message_id]
        destination_domain = route["destination_domain"]
        if replay["destination_chain_id"] != route["destination_chain_id"]:
            fail(f"{purpose} replay destination chain differs from its route")
        transaction_hash = hex32(replay["transaction_hash"], f"{purpose} replay.transaction_hash")
        block_hash = hex32(replay["block_hash"], f"{purpose} replay.block_hash")
        block_number = integer(
            replay["block_number"], f"{purpose} replay.block_number", positive=True
        )
        receipt = rpcs[destination_domain].call("eth_getTransactionReceipt", [transaction_hash])
        if (
            not isinstance(receipt, dict)
            or receipt.get("status") != "0x1"
            or receipt.get("blockHash", "").lower() != block_hash
            or int(receipt.get("blockNumber", "0x0"), 16) != block_number
        ):
            fail(f"{purpose} replay transaction receipt differs")
        economic_addresses = {
            contract["address"]
            for contract in domains[destination_domain]["contracts"].values()
            if contract["address"] != route["destination_coordinator"]
        }
        for log in receipt.get("logs", []):
            topics = log.get("topics", [])
            if log.get("address", "").lower() in economic_addresses or (
                log.get("address", "").lower() == route["destination_coordinator"]
                and topics
                and topics[0].lower() == executed_topic
            ):
                fail(f"{purpose} replay emitted another economic or execution event")
        original = hex32(replay["original_result_hash"], "replay.original_result_hash")
        if original != hex32(replay["replay_result_hash"], "replay.replay_result_hash"):
            fail(f"{purpose} replay changed its result")
        live_result = rpcs[destination_domain].eth_call(
            route["destination_coordinator"],
            "executionResult(bytes32)",
            bytes.fromhex(message_id[2:]),
        )
        if len(live_result) != 32 or "0x" + live_result.hex() != original:
            fail(f"{purpose} replay result differs from canonical live execution")
        if (
            replay["economic_effect_delta_units"] != "0"
            or replay["duplicate_prevented"] is not True
        ):
            fail(f"{purpose} replay repeated an economic effect")
    if not REQUIRED_REPLAYS <= purposes:
        fail("flow lacks mint, repayment, or collateral-release replay evidence")

    final_state = mapping(flow["final_state"], "flow.final_state")
    exact_keys(
        final_state,
        {
            "loan_state",
            "outstanding_principal_units",
            "bridge_backing_units",
            "loan_backing_units",
            "wrapped_supply_units",
            "route_exposure_units",
            "aggregate_exposure_units",
            "settlement_vault_units",
            "collateral_vault_units",
            "collateral_released",
            "borrower_received_principal_units",
            "lender_received_repayment_units",
            "duplicate_economic_effects",
        },
        "flow.final_state",
    )
    if final_state["loan_state"] != "CLOSED" or final_state["collateral_released"] is not True:
        fail("flow did not close the loan and release collateral")
    for field in (
        "outstanding_principal_units",
        "bridge_backing_units",
        "loan_backing_units",
        "wrapped_supply_units",
        "route_exposure_units",
        "aggregate_exposure_units",
        "settlement_vault_units",
        "collateral_vault_units",
        "duplicate_economic_effects",
    ):
        if final_state[field] != "0":
            fail(f"flow final {field} is not zero")
    if final_state["borrower_received_principal_units"] != str(principal):
        fail("borrower did not receive the exact principal")
    if final_state["lender_received_repayment_units"] != str(principal):
        fail("lender did not receive the exact repayment")
    if collateral <= 0:
        fail("collateral fixture is not positive")

    home_rpc = rpcs["home"]
    satellite_rpc = rpcs["satellite"]
    home_contracts = domains["home"]["contracts"]
    satellite_contracts = domains["satellite"]["contracts"]
    loan_id_word = word_bytes32(flow["loan_id"], "flow.loan_id")

    def live_word(rpc: RPC, address: str, signature: str, arguments: bytes = b"") -> bytes:
        result = rpc.eth_call(address, signature, arguments)
        if len(result) != 32:
            fail(f"live state call {signature} returned an invalid value")
        return result

    loan_address = home_contracts["loan_account"]["address"]
    if int.from_bytes(live_word(home_rpc, loan_address, "state()"), "big") != 4:
        fail("live loan account state is not CLOSED")
    if int.from_bytes(live_word(home_rpc, loan_address, "outstandingPrincipal()"), "big") != 0:
        fail("live loan principal is not zero")
    if int.from_bytes(live_word(home_rpc, loan_address, "collateralReleased()"), "big") != 1:
        fail("live loan account has not recorded collateral release")

    hub = home_contracts["bridge_hub"]["address"]
    if int.from_bytes(live_word(home_rpc, hub, "totalBridgeBacking()"), "big") != 0:
        fail("live bridge backing is not zero")
    if int.from_bytes(live_word(home_rpc, hub, "loanBacking(bytes32)", loan_id_word), "big") != 0:
        fail("live loan backing is not zero")
    for purpose, route in routes.items():
        route_backing = live_word(
            home_rpc,
            hub,
            "routeBacking(bytes32)",
            word_bytes32(route["route_policy_hash"], f"{purpose} route hash"),
        )
        if int.from_bytes(route_backing, "big") != 0:
            fail(f"live {purpose} route exposure is not zero")

    wrapped = satellite_contracts["wrapped_uft"]["address"]
    settlement_vault = satellite_contracts["satellite_settlement_vault"]["address"]
    collateral_token = satellite_contracts["collateral_token"]["address"]
    collateral_vault = satellite_contracts["satellite_collateral_vault"]["address"]
    if int.from_bytes(live_word(satellite_rpc, wrapped, "totalSupply()"), "big") != 0:
        fail("live wrapped UFT supply is not zero")
    if (
        int.from_bytes(
            live_word(
                satellite_rpc,
                wrapped,
                "balanceOf(address)",
                word_address(settlement_vault, "settlement vault"),
            ),
            "big",
        )
        != 0
    ):
        fail("live settlement-vault wrapped UFT balance is not zero")
    if (
        int.from_bytes(
            live_word(
                satellite_rpc,
                collateral_token,
                "balanceOf(address)",
                word_address(collateral_vault, "collateral vault"),
            ),
            "big",
        )
        != 0
    ):
        fail("live collateral-vault token balance is not zero")
    collateral_record = satellite_rpc.eth_call(
        collateral_vault, "collateralRecord(bytes32)", loan_id_word
    )
    if len(collateral_record) != 9 * 32:
        fail("live collateral record has an invalid encoding")
    collateral_words = [
        collateral_record[index : index + 32] for index in range(0, len(collateral_record), 32)
    ]
    if (
        collateral_words[0] != loan_id_word
        or collateral_words[1] != word_bytes32(flow["collateral_id"], "collateral ID")
        or int.from_bytes(collateral_words[6], "big") != collateral
        or int.from_bytes(collateral_words[8], "big") != 2
    ):
        fail("live collateral position is not the exact released flow position")

    disbursed_topic = "0x" + keccak256(b"SatelliteFundingDisbursed(bytes32,bytes32,uint256)").hex()
    disbursement_logs = [
        log
        for log in destination_receipts[6].get("logs", [])
        if log.get("address", "").lower() == settlement_vault
        and len(log.get("topics", [])) == 3
        and log["topics"][0].lower() == disbursed_topic
        and log["topics"][1].lower() == flow["loan_id"]
        and log["topics"][2].lower() == flow["funding_lock_id"]
        and int(log.get("data", "0x0"), 16) == principal
    ]
    if len(disbursement_logs) != 1:
        fail("live execution lacks one exact borrower disbursement event")

    lender_word = live_word(home_rpc, loan_address, "lender()")
    released_topic = (
        "0x" + keccak256(b"CanonicalUFTReleased(bytes32,bytes32,address,uint256)").hex()
    )
    repayment_logs = [
        log
        for log in destination_receipts[8].get("logs", [])
        if log.get("address", "").lower() == hub
        and len(log.get("topics", [])) == 4
        and log["topics"][0].lower() == released_topic
        and log["topics"][2].lower() == flow["loan_id"]
        and bytes.fromhex(log["topics"][3][2:]) == lender_word
        and int(log.get("data", "0x0"), 16) == principal
    ]
    if len(repayment_logs) != 1:
        fail("live execution lacks one exact lender repayment event")


def postgres_container() -> str:
    completed = subprocess.run(  # noqa: S603,S607
        [
            DOCKER,
            "ps",
            "--quiet",
            "--filter",
            "label=com.unified.environment=local",
            "--filter",
            "label=com.docker.compose.service=postgres",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    containers = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if completed.returncode != 0 or len(containers) != 1:
        fail("exactly one labeled local PostgreSQL container must be running")
    return containers[0]


def postgres_lines(container: str, sql: str) -> list[str]:
    completed = subprocess.run(  # noqa: S603,S607
        [
            DOCKER,
            "exec",
            container,
            "psql",
            "--no-psqlrc",
            "--tuples-only",
            "--no-align",
            "--set",
            "ON_ERROR_STOP=1",
            "--username",
            "unified_local",
            "--dbname",
            "unified_local",
            "--command",
            sql,
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        fail(f"live PostgreSQL evidence query failed: {completed.stderr.strip()}")
    return [line for line in completed.stdout.splitlines() if line]


def canonical_rows_sha256(
    rows: list[Any] | dict[str, dict[str, Any]],
) -> str:
    encoded = json.dumps(
        rows,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def decode_postgres_json_hex(value: str, label: str) -> Any:
    try:
        encoded = bytes.fromhex(value)
        return json.loads(encoded.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} returned non-JSON evidence: {error}")


def live_table_evidence(container: str, table_name: str) -> tuple[int, str]:
    if table_name not in REQUIRED_TABLES:
        fail(f"live SQL table {table_name} is not in the frozen allow-list")
    primary_key_query = (  # noqa: S608 -- table is a frozen allow-listed identifier
        "SELECT string_agg(format('%I', attribute.attname), ',' ORDER BY key.ordinality) "  # noqa: S608
        "FROM pg_index AS idx "
        "CROSS JOIN LATERAL unnest(idx.indkey) WITH ORDINALITY "
        "AS key(attnum, ordinality) "
        "JOIN pg_attribute AS attribute "
        "ON attribute.attrelid = idx.indrelid AND attribute.attnum = key.attnum "
        f"WHERE idx.indrelid = '{table_name}'::regclass AND idx.indisprimary;"
    )
    primary_key_lines = postgres_lines(container, primary_key_query)
    if len(primary_key_lines) != 1 or not primary_key_lines[0]:
        fail(f"live SQL table {table_name} has no canonical primary-key order")
    rows_query = (  # noqa: S608 -- table and PK identifiers are allow-listed/introspected
        "SELECT encode(convert_to(to_jsonb(record)::text, 'UTF8'), 'hex') "  # noqa: S608
        f"FROM {table_name} AS record ORDER BY {primary_key_lines[0]};"
    )
    rows = [
        decode_postgres_json_hex(raw, f"live SQL table {table_name}")
        for raw in postgres_lines(container, rows_query)
    ]
    return len(rows), canonical_rows_sha256(rows)


def check_live_public_evidence(
    container: str,
    *,
    message_id: str,
    chain_id: int,
    proof_id: str,
    certificate_id: str,
    proof_hash_value: str,
    certificate_hash_value: str,
    proof: dict[str, Any],
    certificate: dict[str, Any],
) -> None:
    quoted_proof_id = proof_id.replace("'", "''")
    proof_rows = postgres_lines(
        container,
        "SELECT json_build_object("  # noqa: S608
        "'message_id', '0x' || encode(message_id, 'hex'), "
        "'chain_id', chain_id::text, "
        "'transaction_hash', '0x' || encode(transaction_hash, 'hex'), "
        "'transaction_index', transaction_index::text, "
        "'log_index', log_index::text, "
        "'block_number', block_number::text, "
        "'block_hash', '0x' || encode(block_hash, 'hex'), "
        "'receipt_root', '0x' || encode(receipts_root, 'hex'), "
        "'receipt_proof_hash', '0x' || encode(inclusion_proof_hash, 'hex'), "
        "'event_hash', '0x' || encode(event_hash, 'hex'), "
        "'finality_head_number', finality_head_number::text, "
        "'finality_head_hash', '0x' || encode(finality_head_hash, 'hex'), "
        "'required_depth', confirmation_depth::text, "
        "'finality_policy_hash', '0x' || encode(finality_policy_hash, 'hex'), "
        "'header_authority_hash', '0x' || encode(observer_authority_hash, 'hex'), "
        "'observer_signed_header_commitment', "
        "'0x' || encode(observer_signed_header_commitment, 'hex'), "
        "'observer_signature', '0x' || encode(observer_signature, 'hex'), "
        "'proof_hash', '0x' || encode(proof_hash, 'hex'))::text "
        "FROM crosschain.source_proofs WHERE proof_id = "
        f"'{quoted_proof_id}';",  # noqa: S608 -- quoted identifier is evidence data
    )
    if len(proof_rows) != 1:
        fail(f"live PostgreSQL proof {proof_id} is missing or duplicated")
    try:
        live_proof = json.loads(proof_rows[0])
    except json.JSONDecodeError as error:
        fail(f"live PostgreSQL proof {proof_id} is invalid JSON: {error}")
    expected_proof = {
        "message_id": message_id,
        "chain_id": str(chain_id),
        "transaction_hash": proof["transaction_hash"],
        "transaction_index": str(proof["transaction_index"]),
        "log_index": str(proof["log_index"]),
        "block_number": str(proof["source_block_number"]),
        "block_hash": proof["source_block_hash"],
        "receipt_root": proof["receipt_root"],
        "receipt_proof_hash": proof["receipt_proof_hash"],
        "event_hash": proof["event_hash"],
        "finality_head_number": str(proof["finality_head_number"]),
        "finality_head_hash": proof["finality_head_hash"],
        "required_depth": str(proof["required_depth"]),
        "finality_policy_hash": proof["finality_policy_hash"],
        "header_authority_hash": proof["header_authority_hash"],
        "observer_signed_header_commitment": proof["observer_signed_header_commitment"],
        "observer_signature": proof["observer_signature"],
        "proof_hash": proof_hash_value,
    }
    if live_proof != expected_proof:
        fail(f"live PostgreSQL proof {proof_id} differs from EVM calldata")

    quoted_certificate_id = certificate_id.replace("'", "''")
    certificate_rows = postgres_lines(
        container,
        "SELECT json_build_object("  # noqa: S608
        "'message_id', '0x' || encode(message_id, 'hex'), "
        "'proof_id', proof_id, "
        "'signer_set_hash', '0x' || encode(signer_set_hash, 'hex'), "
        "'signer_set_version', signer_set_version::text, "
        "'signature_count', signature_count, "
        "'certificate_hash', '0x' || encode(certificate_hash, 'hex'))::text "
        "FROM crosschain.finality_certificates WHERE certificate_id = "
        f"'{quoted_certificate_id}';",  # noqa: S608 -- quoted ID is evidence data
    )
    if len(certificate_rows) != 1:
        fail(f"live PostgreSQL certificate {certificate_id} is missing or duplicated")
    try:
        live_certificate = json.loads(certificate_rows[0])
    except json.JSONDecodeError as error:
        fail(f"live PostgreSQL certificate {certificate_id} is invalid JSON: {error}")
    expected_certificate = {
        "message_id": message_id,
        "proof_id": proof_id,
        "signer_set_hash": certificate["signer_set_hash"],
        "signer_set_version": str(certificate["signer_set_version"]),
        "signature_count": len(certificate["signatures"]),
        "certificate_hash": certificate_hash_value,
    }
    if live_certificate != expected_certificate:
        fail(f"live PostgreSQL certificate {certificate_id} differs from EVM calldata")


def check_object_store_evidence(raw: Any, messages: list[Any]) -> None:
    object_store = mapping(raw, "durable.object_store")
    exact_keys(
        object_store,
        {
            "bucket",
            "object_count",
            "object_set_sha256",
            "rehydrated",
            "objects",
        },
        "durable.object_store",
    )
    if (
        object_store["bucket"] != "crosschain-evidence"
        or object_store["object_count"] != 16
        or object_store["rehydrated"] is not True
    ):
        fail("authenticated inclusion objects were not exactly rehydrated")
    declared_objects = mapping(
        object_store["objects"],
        "durable.object_store.objects",
    )
    expected_objects: dict[str, dict[str, Any]] = {}
    for message in messages:
        message_record = mapping(message, "flow message")
        envelope = mapping(message_record["envelope"], "flow message envelope")
        message_id = hex32(envelope["message_id"], "message ID")[2:]
        for kind, raw_evidence_record in (
            ("source", message_record["source"]),
            ("acknowledgement", message_record["acknowledgement"]),
        ):
            evidence_record = mapping(raw_evidence_record, f"flow message {kind}")
            inclusion_bytes = canonical_json(evidence_record["authenticated_inclusion"])
            inclusion_hash = "0x" + keccak256(inclusion_bytes).hex()
            if inclusion_hash != evidence_record["raw_evidence_object_hash"]:
                fail("authenticated inclusion object hash differs from exact bytes")
            key = f"phase8/authenticated-inclusion/v1/{message_id}/{kind}/{inclusion_hash[2:]}.json"
            expected_objects[key] = {
                "keccak256": inclusion_hash,
                "size_bytes": len(inclusion_bytes),
            }
    if declared_objects != expected_objects:
        fail("durable object-store evidence differs from exact authenticated inclusions")
    if (
        sha256_hex(
            object_store["object_set_sha256"],
            "durable.object_store.object_set_sha256",
        )
        != hashlib.sha256(canonical_json(expected_objects)).hexdigest()
    ):
        fail("durable authenticated object-set commitment is not canonical")


def check_durable(evidence: dict[str, Any]) -> None:
    durable = mapping(evidence["durable"], "durable")
    exact_keys(
        durable,
        {
            "input_deployment_flow_sha256",
            "sql",
            "ledger",
            "object_store",
            "restart",
            "reconciliation",
            "state_parity",
        },
        "durable",
    )
    if (
        sha256_hex(
            durable["input_deployment_flow_sha256"],
            "durable.input_deployment_flow_sha256",
        )
        != evidence["deployment_flow_sha256"]
    ):
        fail("durable worker did not consume the frozen deployment/flow commitment")
    sql = mapping(durable["sql"], "durable.sql")
    exact_keys(sql, {"state_sha256", "allowed_empty_tables", "tables"}, "durable.sql")
    sha256_hex(sql["state_sha256"], "durable.sql.state_sha256")
    allowed_empty = set(sequence(sql["allowed_empty_tables"], "allowed_empty_tables"))
    if not allowed_empty <= REQUIRED_TABLES or allowed_empty & NEVER_EMPTY_TABLES:
        fail("durable SQL allowed-empty table set is invalid")
    tables = mapping(sql["tables"], "durable.sql.tables")
    if set(tables) != REQUIRED_TABLES:
        fail("durable SQL table evidence is incomplete or unexpected")
    container = postgres_container()
    for message in evidence["flow"]["messages"]:
        envelope = message["envelope"]
        source = message["source"]
        check_live_public_evidence(
            container,
            message_id=envelope["message_id"],
            chain_id=source["chain_id"],
            proof_id=source["proof_id"],
            certificate_id=source["certificate_id"],
            proof_hash_value=source["proof_hash"],
            certificate_hash_value=source["certificate_hash"],
            proof=source["proof"],
            certificate=source["certificate"],
        )
        acknowledgement = message["acknowledgement"]
        check_live_public_evidence(
            container,
            message_id=envelope["message_id"],
            chain_id=message["destination"]["chain_id"],
            proof_id=acknowledgement["proof_id"],
            certificate_id=acknowledgement["certificate_id"],
            proof_hash_value=acknowledgement["proof_hash"],
            certificate_hash_value=acknowledgement["certificate_hash"],
            proof=acknowledgement["proof"],
            certificate=acknowledgement["certificate"],
        )
    canonical_table_evidence: dict[str, dict[str, Any]] = {}
    for table_name, raw in tables.items():
        record = mapping(raw, f"durable.sql.tables.{table_name}")
        exact_keys(record, {"row_count", "ordered_sha256"}, f"table {table_name}")
        count = integer(record["row_count"], f"table {table_name}.row_count")
        sha256_hex(record["ordered_sha256"], f"table {table_name}.ordered_sha256")
        if count == 0 and table_name not in allowed_empty:
            fail(f"required durable table {table_name} is empty")
        live_count, live_sha256 = live_table_evidence(container, table_name)
        if count != live_count or record["ordered_sha256"] != live_sha256:
            fail(f"durable SQL table {table_name} differs from live PostgreSQL")
        canonical_table_evidence[table_name] = {
            "ordered_sha256": live_sha256,
            "row_count": live_count,
        }
    if sql["state_sha256"] != canonical_rows_sha256(canonical_table_evidence):
        fail("durable SQL state hash is not the canonical live table commitment")

    ledger = mapping(durable["ledger"], "durable.ledger")
    exact_keys(
        ledger,
        {
            "journal_set_sha256",
            "journal_count",
            "entry_count",
            "total_debits_units",
            "total_credits_units",
            "balanced",
        },
        "durable.ledger",
    )
    sha256_hex(ledger["journal_set_sha256"], "durable.ledger.journal_set_sha256")
    integer(ledger["journal_count"], "durable.ledger.journal_count", positive=True)
    integer(ledger["entry_count"], "durable.ledger.entry_count", positive=True)
    debits = decimal(
        ledger["total_debits_units"], "durable.ledger.total_debits_units", positive=True
    )
    credits = decimal(
        ledger["total_credits_units"], "durable.ledger.total_credits_units", positive=True
    )
    if ledger["balanced"] is not True or debits != credits:
        fail("durable Phase 8 journals are not exactly balanced")
    journal_union = (
        "SELECT journal_id FROM ledger.bridge_journal_links "
        "UNION SELECT journal_id FROM ledger.satellite_custody_links "
        "UNION SELECT journal_id FROM ledger.satellite_settlement_links "
        "UNION SELECT journal_id FROM ledger.crosschain_recovery_journal_links"
    )
    ledger_totals = postgres_lines(
        container,
        "WITH phase_journals AS ("
        + journal_union
        + ") SELECT count(DISTINCT journal.journal_id)::text || '|' "
        "|| count(entry.*)::text || '|' "
        "|| COALESCE(sum(entry.units) FILTER (WHERE entry.side = 'DEBIT'), 0)::text "
        "|| '|' || COALESCE(sum(entry.units) FILTER "
        "(WHERE entry.side = 'CREDIT'), 0)::text "
        "FROM phase_journals JOIN public.journal AS journal USING (journal_id) "
        "JOIN public.journal_entry AS entry USING (journal_id);",
    )
    if len(ledger_totals) != 1:
        fail("live PostgreSQL ledger totals are unavailable")
    try:
        live_journals, live_entries, live_debits, live_credits = (
            int(value) for value in ledger_totals[0].split("|")
        )
    except ValueError:
        fail("live PostgreSQL ledger totals are malformed")
    if (
        live_journals != ledger["journal_count"]
        or live_entries != ledger["entry_count"]
        or live_debits != debits
        or live_credits != credits
        or live_debits != live_credits
    ):
        fail("durable ledger totals differ from live PostgreSQL")
    journal_rows_query = (  # noqa: S608 -- query is a fixed release-gate projection
        "COPY (WITH phase_journals AS ("  # noqa: S608
        + journal_union
        + ") SELECT row_to_json(record)::text FROM ("
        "SELECT to_jsonb(journal) AS journal, "
        "(SELECT COALESCE(jsonb_agg(to_jsonb(entry) ORDER BY entry.line_number), '[]') "
        "FROM public.journal_entry AS entry "
        "WHERE entry.journal_id = journal.journal_id) AS entries "
        "FROM phase_journals JOIN public.journal AS journal USING (journal_id) "
        "ORDER BY journal.journal_id) AS record) TO STDOUT;"
    )
    journal_rows = [json.loads(line) for line in postgres_lines(container, journal_rows_query)]
    if ledger["journal_set_sha256"] != canonical_rows_sha256(journal_rows):
        fail("durable journal-set hash differs from live PostgreSQL")

    check_object_store_evidence(
        durable["object_store"],
        sequence(evidence["flow"]["messages"], "flow.messages"),
    )

    restart = mapping(durable["restart"], "durable.restart")
    exact_keys(
        restart,
        {
            "pre_state_sha256",
            "post_state_sha256",
            "rehydrated",
            "duplicate_prevented",
            "provider_delivery_count_before",
            "provider_delivery_count_after",
        },
        "durable.restart",
    )
    before = sha256_hex(restart["pre_state_sha256"], "restart.pre_state_sha256")
    after = sha256_hex(restart["post_state_sha256"], "restart.post_state_sha256")
    before_count = integer(
        restart["provider_delivery_count_before"], "restart.provider_delivery_count_before"
    )
    after_count = integer(
        restart["provider_delivery_count_after"], "restart.provider_delivery_count_after"
    )
    if (
        before != after
        or before_count == 0
        or before_count != after_count
        or restart["rehydrated"] is not True
        or restart["duplicate_prevented"] is not True
    ):
        fail("durable restart changed state or repeated delivery")

    reconciliation = mapping(durable["reconciliation"], "durable.reconciliation")
    exact_keys(
        reconciliation,
        {"run_id", "evidence_hash", "status", "difference_count"},
        "durable.reconciliation",
    )
    text(reconciliation["run_id"], "reconciliation.run_id")
    hex32(reconciliation["evidence_hash"], "reconciliation.evidence_hash")
    if reconciliation["status"] != "MATCHED" or reconciliation["difference_count"] != 0:
        fail("durable reconciliation is not an exact match")
    reconciliation_live = postgres_lines(
        container,
        "SELECT reconciliation.status || '|' || count(difference.*)::text "
        "FROM crosschain.bridge_reconciliations AS reconciliation "
        "LEFT JOIN crosschain.bridge_reconciliation_differences AS difference "
        "USING (run_id) "
        "WHERE reconciliation.run_id = "
        + "'"
        + reconciliation["run_id"].replace("'", "''")
        + "' GROUP BY reconciliation.status;",
    )
    if reconciliation_live != ["MATCHED|0"]:
        fail("durable reconciliation differs from live PostgreSQL")

    parity = mapping(durable["state_parity"], "durable.state_parity")
    exact_keys(
        parity,
        {
            "evm_snapshot_hash",
            "sql_snapshot_hash",
            "ledger_snapshot_hash",
            "comparison_hash",
            "status",
            "difference_count",
        },
        "durable.state_parity",
    )
    for field in (
        "evm_snapshot_hash",
        "sql_snapshot_hash",
        "ledger_snapshot_hash",
        "comparison_hash",
    ):
        hex32(parity[field], f"state_parity.{field}")
    if parity["status"] != "MATCHED" or parity["difference_count"] != 0:
        fail("EVM, SQL, and ledger state parity is not exact")


def docker_count(resource: str, label: str) -> int:
    command = ["docker", resource, "ls", "--quiet", "--filter", f"label={label}"]
    if resource == "container":
        command = ["docker", "ps", "--all", "--quiet", "--filter", f"label={label}"]
    completed = subprocess.run(  # noqa: S603,S607
        command,
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        fail(f"cannot inspect Docker {resource} resources: {completed.stderr.strip()}")
    return len([line for line in completed.stdout.splitlines() if line.strip()])


def check_reset_plan(evidence: dict[str, Any]) -> None:
    reset = mapping(evidence["reset"], "reset")
    exact_keys(
        reset,
        {
            "command",
            "required_before",
            "expected_after",
            "remove_deployment_directory",
            "remove_cache_directory",
        },
        "reset",
    )
    if reset["command"] != "pwsh ./scripts/local-reset.ps1":
        fail("reset command is not the bounded repository command")
    required_before = mapping(reset["required_before"], "reset.required_before")
    expected_after = mapping(reset["expected_after"], "reset.expected_after")
    count_fields = {
        "labeled_containers",
        "labeled_volumes",
        "labeled_networks",
        "deployment_artifacts",
    }
    exact_keys(required_before, count_fields, "reset.required_before")
    exact_keys(expected_after, count_fields, "reset.expected_after")
    for field in count_fields:
        integer(required_before[field], f"reset.required_before.{field}", positive=True)
        if expected_after[field] != 0:
            fail(f"reset.expected_after.{field} must be zero")
    if (
        reset["remove_deployment_directory"] is not True
        or reset["remove_cache_directory"] is not True
    ):
        fail("reset must remove deployment and release-cache directories")
    label = "com.unified.environment=local"
    if docker_count("container", label) < required_before["labeled_containers"]:
        fail("pre-reset topology has too few labeled containers")
    if docker_count("volume", label) < required_before["labeled_volumes"]:
        fail("pre-reset topology has too few labeled volumes")
    if docker_count("network", label) < required_before["labeled_networks"]:
        fail("pre-reset topology has too few labeled networks")
    artifacts = list(DEPLOYMENT_ROOT.glob("*.json")) if DEPLOYMENT_ROOT.is_dir() else []
    if len(artifacts) < required_before["deployment_artifacts"]:
        fail("pre-reset deployment evidence is absent")


def check_post_reset() -> None:
    label = "com.unified.environment=local"
    for resource in ("container", "volume", "network"):
        if docker_count(resource, label) != 0:
            fail(f"post-reset {resource} resources remain")
    if DEPLOYMENT_ROOT.exists():
        fail("post-reset protocol/deployments/local still exists")
    if CACHE_ROOT.exists():
        fail("post-reset .cache/phase8-release still exists")
    print("Phase 8 post-reset evidence passed: no local topology or generated manifest remains.")


def check_validation_summary(evidence: dict[str, Any]) -> None:
    validation = mapping(evidence["validation"], "validation")
    required = {
        "deployment_complete",
        "rpc_code_verified",
        "trust_consistent",
        "synthetic_boundary_explicit",
        "authenticated_inclusion_verified",
        "solidity_hashes_recomputed",
        "full_flow_complete",
        "replay_complete",
        "restart_complete",
        "journals_balanced",
        "reconciliation_matched",
        "state_parity_matched",
    }
    exact_keys(validation, required, "validation")
    if any(validation[field] is not True for field in required):
        fail("one or more Phase 8 release validation summaries are not true")


def check_pre_reset(path: Path) -> None:
    if not path.is_file():
        fail(f"authoritative Phase 8 release evidence is missing: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot parse Phase 8 release evidence: {error}")
    evidence = mapping(payload, "release evidence")
    if evidence.get("proof_boundary") == SYNTHETIC_PROOF_BOUNDARY:
        fail(
            "Phase 8 release is NOT READY: synthetic signed-header fixtures do not "
            "satisfy ADR 0018 authenticated transaction/receipt MPT inclusion"
        )
    validate_release_schema(evidence)
    required = {
        "schema_version",
        "artifact_type",
        "environment",
        "contains_real_value",
        "run_id",
        "protocol_id",
        "proof_boundary",
        "generated_at",
        "source_commit",
        "deployment_flow_sha256",
        "domains",
        "routes",
        "exposure_policy",
        "recovery",
        "providers",
        "flow",
        "durable",
        "reset",
        "validation",
    }
    exact_keys(evidence, required, "release evidence")
    if (
        evidence["schema_version"] != 1
        or evidence["artifact_type"] != "PHASE8_RELEASE_EVIDENCE"
        or evidence["environment"] != "local"
        or evidence["contains_real_value"] is not False
    ):
        fail("release evidence is not the frozen local release schema")
    if evidence["proof_boundary"] != AUTHENTICATED_PROOF_BOUNDARY:
        fail("release evidence has an unsupported proof authority boundary")
    text(evidence["run_id"], "run_id")
    hex32(evidence["protocol_id"], "protocol_id")
    generated_at = text(evidence["generated_at"], "generated_at")
    try:
        timestamp = datetime.datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
    except ValueError:
        fail("generated_at must be an RFC 3339 timestamp")
    if timestamp.tzinfo is None:
        fail("generated_at must include an explicit timezone")
    source_commit = fixed_hex(evidence["source_commit"], COMMIT, "source_commit")
    git_head = subprocess.run(  # noqa: S603,S607
        [GIT, "rev-parse", "HEAD"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if git_head.returncode != 0 or git_head.stdout.strip().lower() != source_commit:
        fail("source_commit does not equal the checked-out Git HEAD")
    dirty = subprocess.run(  # noqa: S603,S607
        [GIT, "status", "--porcelain", "--untracked-files=no"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if dirty.returncode != 0 or dirty.stdout.strip():
        fail("release validation requires a clean tracked Git worktree")
    declared_commitment = sha256_hex(evidence["deployment_flow_sha256"], "deployment_flow_sha256")
    if declared_commitment != deployment_flow_sha256(evidence):
        fail("deployment_flow_sha256 does not bind the canonical deployment and flow")
    reject_secret_material(evidence)
    serialized = json.dumps(evidence, sort_keys=True).lower()
    if any(marker in serialized for marker in ("mainnet", "testnet", "infura", "alchemy")):
        fail("release evidence contains a public-network marker")

    domains_raw = mapping(evidence["domains"], "domains")
    exact_keys(domains_raw, {"home", "satellite"}, "domains")
    home, home_rpc = check_domain("home", domains_raw["home"], 31337)
    satellite, satellite_rpc = check_domain("satellite", domains_raw["satellite"], 31338)
    if (
        home["observer_public_key_ed25519"] == satellite["observer_public_key_ed25519"]
        or home["observer_authority_hash"] == satellite["observer_authority_hash"]
        or home["configuration_hash"] == satellite["configuration_hash"]
        or home["signer_set"]["hash"] == satellite["signer_set"]["hash"]
    ):
        fail("home and satellite trust authorities are not distinct")
    domains = {"home": home, "satellite": satellite}
    rpcs = {"home": home_rpc, "satellite": satellite_rpc}

    check_live_trust_registrations(domains, rpcs)
    check_providers_and_recovery(evidence, domains, rpcs)
    routes = check_routes_and_policies(evidence, domains, rpcs)
    check_exposure_policy(evidence, domains, rpcs, routes)
    check_flow(evidence, domains, rpcs, routes)
    check_durable(evidence)
    check_reset_plan(evidence)
    check_validation_summary(evidence)
    print(
        "Phase 8 pre-reset release evidence passed: live deployment, Solidity hashes, "
        "full flow, replay, durable restart, journals, and reconciliation are exact."
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    parser.add_argument("--stage", choices=("pre-reset", "post-reset"), default="pre-reset")
    args = parser.parse_args()
    try:
        if args.stage == "post-reset":
            check_post_reset()
        else:
            evidence_path = args.evidence.resolve()
            try:
                evidence_path.relative_to(ROOT)
            except ValueError:
                fail("release evidence path must remain inside the workspace")
            check_pre_reset(evidence_path)
    except EvidenceError as error:
        raise SystemExit(f"ERROR: {error}") from error


if __name__ == "__main__":
    main()
