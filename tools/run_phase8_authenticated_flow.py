"""Drive the Phase 8 local flow through authenticated live Anvil evidence.

This is the single platform-neutral core used by the PowerShell and Bash smoke
wrappers.  It never accepts or emits private key material: transactions use
Anvil's unlocked local fixture accounts, Ed25519 operations use the dedicated
local observer helper, and the fixed 2-of-3 local certificate fixture is signed
in-process.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import http.client
import json
import os
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NoReturn, cast
from urllib.parse import urlparse

from build_phase8_anvil_inclusion import (
    LocalRPC,
    canonical_hex,
    decode_hex,
    keccak256,
    observer_helper,
    quantity,
    require_list,
    require_object,
)
from build_phase8_anvil_inclusion import (
    build as build_authenticated_inclusion,
)

ROOT = Path(__file__).resolve().parents[1]
BOUNDARY = "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT"
MESSAGE_SENT_TOPIC = canonical_hex(
    keccak256(b"MessageSent(bytes32,bytes32,uint64,bytes32,uint8,bytes32,uint256,address)")
)
MESSAGE_EXECUTED_TOPIC = canonical_hex(
    keccak256(b"MessageExecuted(bytes32,bytes32,uint64,address,bytes32)")
)
MESSAGE_ACKNOWLEDGED_TOPIC = canonical_hex(
    keccak256(b"MessageAcknowledged(bytes32,bytes32,bytes32)")
)
ZERO32 = "0x" + "00" * 32
SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
SECP256K1_G = (
    0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
    0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8,
)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def provider_endpoint(base_url: str, path: str) -> tuple[str, int, str]:
    parsed = urlparse(base_url)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "::1", "localhost"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        fail("mock provider endpoint must be unauthenticated loopback HTTP")
    try:
        port = parsed.port
    except ValueError:
        fail("mock provider endpoint has an invalid port")
    if port is None or not 1 <= port <= 65_535:
        fail("mock provider endpoint must include a valid port")
    base_path = parsed.path.rstrip("/")
    return parsed.hostname, port, base_path + path


def post_provider_observation(
    base_url: str,
    path: str,
    expected_provider: str,
    body: dict[str, Any],
) -> tuple[int, dict[str, Any]]:
    host, port, endpoint = provider_endpoint(base_url, path)
    encoded = json.dumps(body, separators=(",", ":"), sort_keys=True).encode("utf-8")
    connection = http.client.HTTPConnection(host, port, timeout=10)
    try:
        connection.request(
            "POST",
            endpoint,
            body=encoded,
            headers={"Content-Type": "application/json"},
        )
        response = connection.getresponse()
        payload = response.read(65_537)
    except (OSError, TimeoutError, http.client.HTTPException) as error:
        fail(f"{expected_provider} transport request failed: {error}")
    finally:
        connection.close()
    if len(payload) > 65_536:
        fail(f"{expected_provider} returned an oversized transport receipt")
    try:
        observation = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail(f"{expected_provider} transport response is not canonical JSON")
    if not isinstance(observation, dict):
        fail(f"{expected_provider} transport response must be an object")
    if (
        observation.get("provider") != expected_provider
        or observation.get("authority") != "TRANSPORT_ONLY"
        or observation.get("contains_real_value") is not False
    ):
        fail(f"{expected_provider} asserted a forbidden identity, authority, or value")
    return response.status, cast(dict[str, Any], observation)


def observed_provider_attempts(
    sequence: int,
    provider_a_url: str,
    provider_b_url: str,
    message_id: str,
    envelope: dict[str, Any],
    source_proof: dict[str, Any],
    source_proof_hash: str,
) -> list[dict[str, Any]]:
    serialized_envelope = envelope_encoding(envelope)
    serialized_source_proof = word_uint(32) + proof_tuple_encoding(source_proof)
    if canonical_hex(keccak256(serialized_source_proof)) != source_proof_hash:
        fail("provider source proof serialization differs from its exact hash")
    request_body: dict[str, Any] = {
        "message_id": message_id.removeprefix("0x"),
        "envelope": base64.b64encode(serialized_envelope).decode("ascii"),
        "envelope_hash": keccak256(serialized_envelope).hex(),
        "source_proof": base64.b64encode(serialized_source_proof).decode("ascii"),
        "proof_hash": source_proof_hash.removeprefix("0x"),
        "payload_hash": cast(str, envelope["payload_hash"]).removeprefix("0x"),
        "contains_real_value": False,
    }

    providers = [
        (
            "mock-bridge-provider-a",
            provider_a_url,
            "/v1/faults/retryable" if sequence == 1 else "/v1/messages",
        )
    ]
    if sequence == 1:
        providers.append(("mock-bridge-provider-b", provider_b_url, "/v1/messages"))

    attempts: list[dict[str, Any]] = []
    for attempt_number, (provider_id, base_url, path) in enumerate(providers, start=1):
        status_code, response = post_provider_observation(
            base_url,
            path,
            provider_id,
            request_body,
        )
        if status_code == 503:
            if provider_id != "mock-bridge-provider-a" or response.get("retryable") is not True:
                fail("retryable provider failure response is not the approved local fixture")
            status = "FAILED"
            retryable = True
        elif 200 <= status_code < 300:
            if response.get("delivery_status") != "ACCEPTED" or response.get("retryable") is True:
                fail(f"{provider_id} returned a non-delivery transport receipt")
            status = "DELIVERED"
            retryable = False
        else:
            fail(f"{provider_id} returned unexpected transport status {status_code}")
        transport_receipt_hash = canonical_hex(
            keccak256(
                json.dumps(
                    {"status_code": status_code, "body": response},
                    separators=(",", ":"),
                    sort_keys=True,
                ).encode("utf-8")
            )
        )
        attempts.append(
            {
                "provider_id": cast(str, response["provider"]),
                "attempt_number": attempt_number,
                "status": status,
                "retryable": retryable,
                "transport_receipt_hash": transport_receipt_hash,
                "message_id": message_id,
                "payload_hash": envelope["payload_hash"],
                "source_proof_hash": source_proof_hash,
            }
        )
    if attempts[-1]["status"] != "DELIVERED":
        fail("mock provider sequence did not end in observed delivery")
    return attempts


def word_uint(value: int) -> bytes:
    if value < 0 or value >= 1 << 256:
        fail("ABI integer is outside uint256")
    return value.to_bytes(32, "big")


def word_hex(value: str, width: int) -> bytes:
    decoded = decode_hex(value.lower(), "ABI hex", width)
    return decoded.rjust(32, b"\x00")


def word_address(value: str) -> bytes:
    return word_hex(value, 20)


def word_bytes32(value: str) -> bytes:
    return word_hex(value, 32)


def encode_bytes(value: bytes) -> bytes:
    padding = (-len(value)) % 32
    return word_uint(len(value)) + value + (b"\x00" * padding)


def selector(signature: str) -> bytes:
    return keccak256(signature.encode("ascii"))[:4]


def solidity_hash(domain: str, words: list[bytes]) -> str:
    encoded_domain = domain.encode("ascii")
    head = word_uint((len(words) + 1) * 32) + b"".join(words)
    return canonical_hex(keccak256(head + encode_bytes(encoded_domain)))


def point_add(
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
        slope = (
            (y_right - y_left)
            * pow((x_right - x_left) % SECP256K1_P, -1, SECP256K1_P)
            % SECP256K1_P
        )
    x_result = (slope * slope - x_left - x_right) % SECP256K1_P
    y_result = (slope * (x_left - x_result) - y_left) % SECP256K1_P
    return x_result, y_result


def point_mul(scalar: int, point: tuple[int, int]) -> tuple[int, int] | None:
    result: tuple[int, int] | None = None
    addend: tuple[int, int] | None = point
    while scalar:
        if scalar & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        scalar >>= 1
    return result


def fixture_ecdsa_signature(fixture_index: int, digest: bytes) -> bytes:
    """Return canonical r||s||v for the fixed Anvil fixture signer.

    The only supported fixture indices are the first two deterministic Anvil
    accounts (private scalars 1 and 2).  They are selected internally and are
    never accepted from command-line arguments or written to evidence.
    """

    if fixture_index not in {1, 2} or len(digest) != 32:
        fail("invalid local certificate signing request")
    private_scalar = fixture_index
    value = int.from_bytes(digest, "big")
    key_bytes = private_scalar.to_bytes(32, "big")
    digest_bytes = value.to_bytes(32, "big")
    counter = 0
    while True:
        # RFC 6979 section 3.2 with SHA-256.
        v = b"\x01" * 32
        k_state = b"\x00" * 32
        k_state = hmac.new(
            k_state,
            v + b"\x00" + key_bytes + digest_bytes,
            hashlib.sha256,
        ).digest()
        v = hmac.new(k_state, v, hashlib.sha256).digest()
        k_state = hmac.new(
            k_state,
            v + b"\x01" + key_bytes + digest_bytes,
            hashlib.sha256,
        ).digest()
        v = hmac.new(k_state, v, hashlib.sha256).digest()
        for _ in range(counter + 1):
            v = hmac.new(k_state, v, hashlib.sha256).digest()
        nonce = int.from_bytes(v, "big")
        if 0 < nonce < SECP256K1_N:
            point = point_mul(nonce, SECP256K1_G)
            if point is not None:
                r_value = point[0] % SECP256K1_N
                if r_value:
                    s_value = (
                        pow(nonce, -1, SECP256K1_N)
                        * (value + r_value * private_scalar)
                        % SECP256K1_N
                    )
                    if s_value:
                        recovery = point[1] & 1
                        if s_value > SECP256K1_N // 2:
                            s_value = SECP256K1_N - s_value
                            recovery ^= 1
                        return (
                            r_value.to_bytes(32, "big")
                            + s_value.to_bytes(32, "big")
                            + bytes([27 + recovery])
                        )
        counter += 1


def proof_tuple_encoding(proof: dict[str, Any]) -> bytes:
    signature = decode_hex(proof["observer_signature"], "observer signature", 64)
    return b"".join(
        [
            word_bytes32(proof["source_block_hash"]),
            word_uint(proof["source_block_number"]),
            word_uint(proof["source_block_timestamp"]),
            word_bytes32(proof["transaction_hash"]),
            word_uint(proof["transaction_index"]),
            word_bytes32(proof["receipt_root"]),
            word_bytes32(proof["receipt_proof_hash"]),
            word_uint(proof["log_index"]),
            word_bytes32(proof["event_hash"]),
            word_bytes32(proof["finality_head_hash"]),
            word_uint(proof["finality_head_number"]),
            word_uint(proof["required_depth"]),
            word_bytes32(proof["header_authority_hash"]),
            word_bytes32(proof["observer_signed_header_commitment"]),
            word_uint(16 * 32),
            word_bytes32(proof["finality_policy_hash"]),
            encode_bytes(signature),
        ]
    )


def proof_hash(proof: dict[str, Any]) -> str:
    return canonical_hex(keccak256(word_uint(32) + proof_tuple_encoding(proof)))


def certificate_tuple_encoding(certificate: dict[str, Any]) -> bytes:
    signatures = [
        decode_hex(item, "certificate signature", 65) for item in certificate["signatures"]
    ]
    offsets: list[bytes] = []
    tails: list[bytes] = []
    next_offset = len(signatures) * 32
    for signature in signatures:
        encoded = encode_bytes(signature)
        offsets.append(word_uint(next_offset))
        tails.append(encoded)
        next_offset += len(encoded)
    signature_array = word_uint(len(signatures)) + b"".join(offsets) + b"".join(tails)
    return b"".join(
        [
            word_bytes32(certificate["message_id"]),
            word_bytes32(certificate["source_proof_hash"]),
            word_bytes32(certificate["signer_set_hash"]),
            word_uint(certificate["signer_set_version"]),
            word_uint(5 * 32),
            signature_array,
        ]
    )


def certificate_hash(certificate: dict[str, Any]) -> str:
    return canonical_hex(keccak256(word_uint(32) + certificate_tuple_encoding(certificate)))


ENVELOPE_KEYS = (
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
)
ENVELOPE_KINDS = (
    "uint",
    "bytes32",
    "bytes32",
    "uint",
    "address",
    "address",
    "uint",
    "address",
    "address",
    "bytes32",
    "uint",
    "bytes32",
    "uint",
    "bytes32",
    "uint",
    "uint",
    "bytes32",
    "bytes32",
    "bytes32",
    "bytes32",
    "bytes32",
    "bytes32",
    "bytes32",
)


def envelope_encoding(envelope: dict[str, Any]) -> bytes:
    words: list[bytes] = []
    for key, kind in zip(ENVELOPE_KEYS, ENVELOPE_KINDS, strict=True):
        value = envelope[key]
        if kind == "uint":
            words.append(word_uint(cast(int, value)))
        elif kind == "address":
            words.append(word_address(cast(str, value)))
        else:
            words.append(word_bytes32(cast(str, value)))
    return b"".join(words)


def decode_envelope(encoded: bytes) -> dict[str, Any]:
    if len(encoded) != 23 * 32:
        fail("messageEnvelope returned a non-canonical static tuple")
    result: dict[str, Any] = {}
    for index, (key, kind) in enumerate(zip(ENVELOPE_KEYS, ENVELOPE_KINDS, strict=True)):
        word = encoded[index * 32 : (index + 1) * 32]
        if kind == "uint":
            result[key] = int.from_bytes(word, "big")
        elif kind == "address":
            if word[:12] != b"\x00" * 12:
                fail(f"message envelope address {key} is non-canonical")
            result[key] = canonical_hex(word[12:])
        else:
            result[key] = canonical_hex(word)
    return result


def execute_calldata(
    envelope: dict[str, Any],
    payload: bytes,
    proof: dict[str, Any],
    certificate: dict[str, Any],
) -> bytes:
    function_signature = (
        "executeMessage("
        "(uint32,bytes32,bytes32,uint256,address,address,uint256,address,address,"
        "bytes32,uint64,bytes32,uint8,bytes32,uint64,uint64,bytes32,bytes32,"
        "bytes32,bytes32,bytes32,bytes32,bytes32),bytes,"
        "(bytes32,uint64,uint64,bytes32,uint32,bytes32,bytes32,uint32,bytes32,"
        "bytes32,uint64,uint64,bytes32,bytes32,bytes,bytes32),"
        "(bytes32,bytes32,bytes32,uint32,bytes[]))"
    )
    envelope_head = envelope_encoding(envelope)
    payload_tail = encode_bytes(payload)
    proof_tail = proof_tuple_encoding(proof)
    certificate_tail = certificate_tuple_encoding(certificate)
    head_size = len(envelope_head) + 3 * 32
    head = b"".join(
        [
            envelope_head,
            word_uint(head_size),
            word_uint(head_size + len(payload_tail)),
            word_uint(head_size + len(payload_tail) + len(proof_tail)),
        ]
    )
    return selector(function_signature) + head + payload_tail + proof_tail + certificate_tail


def acknowledgement_calldata(
    envelope: dict[str, Any],
    result_hash: str,
    proof: dict[str, Any],
    certificate: dict[str, Any],
) -> bytes:
    function_signature = (
        "recordAcknowledgement("
        "(uint32,bytes32,bytes32,uint256,address,address,uint256,address,address,"
        "bytes32,uint64,bytes32,uint8,bytes32,uint64,uint64,bytes32,bytes32,"
        "bytes32,bytes32,bytes32,bytes32,bytes32),bytes32,"
        "(bytes32,uint64,uint64,bytes32,uint32,bytes32,bytes32,uint32,bytes32,"
        "bytes32,uint64,uint64,bytes32,bytes32,bytes,bytes32),"
        "(bytes32,bytes32,bytes32,uint32,bytes[]))"
    )
    envelope_head = envelope_encoding(envelope)
    proof_tail = proof_tuple_encoding(proof)
    certificate_tail = certificate_tuple_encoding(certificate)
    head_size = len(envelope_head) + 3 * 32
    head = b"".join(
        [
            envelope_head,
            word_bytes32(result_hash),
            word_uint(head_size),
            word_uint(head_size + len(proof_tail)),
        ]
    )
    return selector(function_signature) + head + proof_tail + certificate_tail


@dataclass(frozen=True)
class Domain:
    name: str
    chain_id: int
    rpc_url: str
    rpc: LocalRPC
    coordinator: str
    verifier: str
    signer_set_hash: str
    observer_public_key: str
    observer_authority_hash: str


class FlowDriver:
    def __init__(self, args: argparse.Namespace, blueprint: dict[str, Any]) -> None:
        self.args = args
        self.blueprint = blueprint
        home_public = observer_helper("public", "home")
        satellite_public = observer_helper("public", "satellite")
        self.home = Domain(
            "home",
            31_337,
            args.home_rpc,
            LocalRPC(args.home_rpc),
            self.address("home_coordinator"),
            self.address("home_finality_verifier"),
            self.hex32("home_signer_set_hash"),
            home_public,
            canonical_hex(keccak256(decode_hex(home_public, "home observer key", 32))),
        )
        self.satellite = Domain(
            "satellite",
            31_338,
            args.satellite_rpc,
            LocalRPC(args.satellite_rpc),
            self.address("satellite_coordinator"),
            self.address("satellite_finality_verifier"),
            self.hex32("satellite_signer_set_hash"),
            satellite_public,
            canonical_hex(keccak256(decode_hex(satellite_public, "satellite observer key", 32))),
        )
        if quantity(self.home.rpc.call("eth_chainId", []), "home chain ID") != 31_337:
            fail("home RPC chain ID differs from blueprint")
        if quantity(self.satellite.rpc.call("eth_chainId", []), "satellite chain ID") != 31_338:
            fail("satellite RPC chain ID differs from blueprint")
        self.messages: list[dict[str, Any]] = []
        self.replay_candidates: list[tuple[str, Domain, str, str, bytes]] = []

    def address(self, key: str) -> str:
        value = self.blueprint.get(key)
        return canonical_hex(decode_hex(str(value).lower(), key, 20))

    def hex32(self, key: str) -> str:
        value = self.blueprint.get(key)
        return canonical_hex(decode_hex(str(value).lower(), key, 32))

    def integer(self, key: str) -> int:
        value = self.blueprint.get(key)
        try:
            result = int(cast(str | int, value))
        except (TypeError, ValueError):
            fail(f"{key} is not an integer")
        if result <= 0:
            fail(f"{key} must be positive")
        return result

    @staticmethod
    def latest_timestamp(domain: Domain) -> int:
        block = require_object(
            domain.rpc.call("eth_getBlockByNumber", ["latest", False]),
            f"{domain.name} latest block",
        )
        return quantity(block.get("timestamp"), f"{domain.name} timestamp")

    @staticmethod
    def call(domain: Domain, to: str, data: bytes) -> bytes:
        value = domain.rpc.call(
            "eth_call",
            [{"to": to, "data": canonical_hex(data)}, "latest"],
        )
        return decode_hex(value, "eth_call result")

    @classmethod
    def uint_call(
        cls,
        domain: Domain,
        to: str,
        signature: str,
        arguments: bytes = b"",
    ) -> int:
        value = cls.call(domain, to, selector(signature) + arguments)
        if len(value) != 32:
            fail(f"{signature} returned malformed data")
        return int.from_bytes(value, "big")

    def transact(self, domain: Domain, sender: str, to: str, data: bytes) -> dict[str, Any]:
        transaction_hash = domain.rpc.call(
            "eth_sendTransaction",
            [
                {
                    "from": sender,
                    "to": to,
                    "data": canonical_hex(data),
                    "gas": hex(28_000_000),
                }
            ],
        )
        transaction_hash = canonical_hex(decode_hex(transaction_hash, "sent transaction hash", 32))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            raw = domain.rpc.call("eth_getTransactionReceipt", [transaction_hash])
            if raw is not None:
                receipt = require_object(raw, "transaction receipt")
                if receipt.get("status") != "0x1":
                    fail(f"{domain.name} transaction {transaction_hash} reverted")
                return receipt
            time.sleep(0.05)
        fail(f"timed out waiting for {domain.name} transaction {transaction_hash}")

    @staticmethod
    def exact_event(
        receipt: dict[str, Any],
        address: str,
        topic0: str,
        message_id: str | None = None,
    ) -> dict[str, Any]:
        matches: list[dict[str, Any]] = []
        for index, value in enumerate(require_list(receipt.get("logs"), "receipt logs")):
            log = require_object(value, f"receipt log {index}")
            topics = [
                canonical_hex(decode_hex(item, "event topic", 32))
                for item in require_list(log.get("topics"), "event topics")
            ]
            if (
                canonical_hex(decode_hex(log.get("address"), "event address", 20)) == address
                and topics
                and topics[0] == topic0
                and (message_id is None or (len(topics) > 1 and topics[1] == message_id))
            ):
                matches.append(log)
        if len(matches) != 1:
            fail(
                f"receipt must contain exactly one {topic0} event"
                + ("" if message_id is None else f" for {message_id}")
            )
        return matches[0]

    def envelope(self, domain: Domain, message_id: str) -> dict[str, Any]:
        result = self.call(
            domain,
            domain.coordinator,
            selector("messageEnvelope(bytes32)") + word_bytes32(message_id),
        )
        envelope = decode_envelope(result)
        if envelope["message_id"] != message_id:
            fail("stored envelope differs from source MessageSent identity")
        return envelope

    def inclusion(
        self,
        domain: Domain,
        transaction_hash: str,
        target_log_index: int,
    ) -> dict[str, Any]:
        namespace = argparse.Namespace(
            rpc_url=domain.rpc_url,
            transaction_hash=transaction_hash,
            domain=domain.name,
            coordinator_address=domain.coordinator,
            target_log_index=target_log_index,
            required_depth=12,
            mine_confirmations=True,
        )
        document = build_authenticated_inclusion(namespace)
        process = subprocess.run(  # noqa: S603
            [str(self.args.verifier)],
            input=json.dumps(document, separators=(",", ":")),
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )
        if process.returncode != 0:
            fail(
                f"production inclusion verifier rejected {domain.name} evidence: "
                f"{process.stderr.strip()}"
            )
        report = json.loads(process.stdout)
        if report.get("status") != BOUNDARY:
            fail("production inclusion verifier returned the wrong proof boundary")
        return document

    @staticmethod
    def event_log_index(log: dict[str, Any]) -> int:
        return quantity(log.get("logIndex"), "event log index")

    @staticmethod
    def receipt_identity(receipt: dict[str, Any]) -> dict[str, Any]:
        return {
            "transaction_hash": canonical_hex(
                decode_hex(receipt.get("transactionHash"), "receipt transaction hash", 32)
            ),
            "block_hash": canonical_hex(
                decode_hex(receipt.get("blockHash"), "receipt block hash", 32)
            ),
            "block_number": quantity(receipt.get("blockNumber"), "receipt block number"),
            "transaction_index": quantity(
                receipt.get("transactionIndex"), "receipt transaction index"
            ),
        }

    def make_proof(
        self,
        domain: Domain,
        inclusion: dict[str, Any],
        event_hash: str,
        log_index: int,
        finality_policy_hash: str,
    ) -> dict[str, Any]:
        fields = require_object(
            inclusion["verified_source_event_proof_fields"],
            "verified proof fields",
        )
        proof: dict[str, Any] = {
            "source_block_hash": fields["source_block_hash"],
            "source_block_number": fields["source_block_number"],
            "source_block_timestamp": fields["source_block_timestamp"],
            "transaction_hash": fields["transaction_hash"],
            "transaction_index": fields["transaction_index"],
            "receipt_root": fields["receipt_root"],
            "receipt_proof_hash": fields["receipt_proof_hash"],
            "log_index": log_index,
            "event_hash": event_hash,
            "finality_head_hash": fields["finality_head_hash"],
            "finality_head_number": fields["finality_head_number"],
            "required_depth": fields["required_depth"],
            "header_authority_hash": domain.observer_authority_hash,
            "observer_signed_header_commitment": ZERO32,
            "observer_signature": "0x" + "00" * 64,
            "finality_policy_hash": finality_policy_hash,
        }
        commitment = solidity_hash(
            "UNIFIED_OBSERVER_SIGNED_HEADER_V1",
            [
                word_bytes32(proof["source_block_hash"]),
                word_uint(proof["source_block_number"]),
                word_uint(proof["source_block_timestamp"]),
                word_bytes32(proof["finality_head_hash"]),
                word_uint(proof["finality_head_number"]),
                word_uint(proof["required_depth"]),
                word_bytes32(proof["header_authority_hash"]),
                word_bytes32(proof["finality_policy_hash"]),
            ],
        )
        proof["observer_signed_header_commitment"] = commitment
        proof["observer_signature"] = observer_helper("sign", domain.name, commitment)
        return proof

    @staticmethod
    def certificate(
        proof: dict[str, Any],
        message_id: str,
        evidence_domain: Domain,
        verifier_domain: Domain,
    ) -> dict[str, Any]:
        source_hash = proof_hash(proof)
        digest = solidity_hash(
            "UNIFIED_SYNTHETIC_FINALITY_V1",
            [
                word_uint(verifier_domain.chain_id),
                word_address(verifier_domain.verifier),
                word_bytes32(message_id),
                word_bytes32(source_hash),
                word_bytes32(evidence_domain.signer_set_hash),
                word_uint(1),
            ],
        )
        digest_bytes = decode_hex(digest, "certificate digest", 32)
        signatures = [
            canonical_hex(fixture_ecdsa_signature(index, digest_bytes)) for index in (1, 2)
        ]
        return {
            "message_id": message_id,
            "source_proof_hash": source_hash,
            "signer_set_hash": evidence_domain.signer_set_hash,
            "signer_set_version": 1,
            "signatures": signatures,
        }

    def bootstrap(self) -> tuple[dict[str, Any], bytes, dict[str, Any], bytes, str]:
        governance = self.address("local_governance")
        admin = self.address("local_admin")
        canonical = self.address("canonical_token")
        hub = self.address("bridge_hub")
        factory = self.address("loan_factory")
        loan_id = self.hex32("loan_id")
        lock_id = self.hex32("funding_lock_id")
        collateral_id = self.hex32("collateral_id")
        policy_hash = self.hex32("loan_policy_hash")
        principal = self.integer("principal_units")
        collateral_amount = self.integer("collateral_units")

        self.transact(
            self.home,
            governance,
            canonical,
            selector("approve(address,uint256)") + word_address(hub) + word_uint(principal),
        )
        terms = b"".join(
            [
                word_bytes32(loan_id),
                word_bytes32(canonical_hex(keccak256(b"LOCAL_FULL_FLOW_AGREEMENT"))),
                word_bytes32(lock_id),
                word_bytes32(collateral_id),
                word_address(admin),
                word_address(governance),
                word_uint(principal),
                word_uint(collateral_amount),
                word_bytes32(policy_hash),
            ]
        )
        expiry = self.latest_timestamp(self.home) + 2 * 24 * 60 * 60
        create_data = (
            selector(
                "createLoan((bytes32,bytes32,bytes32,bytes32,address,address,"
                "uint256,uint256,bytes32),uint64)"
            )
            + terms
            + word_uint(expiry)
        )
        mint_receipt = self.transact(self.home, governance, factory, create_data)
        mint_log = self.exact_event(
            mint_receipt,
            self.home.coordinator,
            MESSAGE_SENT_TOPIC,
        )
        mint_topics = require_list(mint_log.get("topics"), "mint MessageSent topics")
        decode_hex(mint_topics[1], "mint message ID", 32)
        account_result = self.call(
            self.home,
            factory,
            selector("loanAccount(bytes32)") + word_bytes32(loan_id),
        )
        if len(account_result) != 32:
            fail("loanAccount returned malformed data")
        account = canonical_hex(account_result[12:])

        provisioning = b"".join(
            [
                word_bytes32(loan_id),
                word_bytes32(lock_id),
                word_address(account),
                word_address(factory),
                word_address(admin),
                word_address(governance),
                word_address(self.address("wrapped_uft")),
                word_address(self.address("collateral_token")),
                word_bytes32(collateral_id),
                word_uint(principal),
                word_uint(collateral_amount),
                word_bytes32(self.hex32("repayment_route_hash")),
                word_bytes32(policy_hash),
            ]
        )
        self.transact(
            self.satellite,
            governance,
            self.address("satellite_loan_component"),
            selector(
                "provisionLoan((bytes32,bytes32,address,address,address,address,"
                "address,address,bytes32,uint256,uint256,bytes32,bytes32))"
            )
            + provisioning,
        )
        collateral_token = self.address("collateral_token")
        collateral_vault = self.address("satellite_collateral_vault")
        self.transact(
            self.satellite,
            governance,
            collateral_token,
            selector("transfer(address,uint256)")
            + word_address(admin)
            + word_uint(collateral_amount),
        )
        self.transact(
            self.satellite,
            admin,
            collateral_token,
            selector("approve(address,uint256)")
            + word_address(collateral_vault)
            + word_uint(collateral_amount),
        )
        collateral_receipt = self.transact(
            self.satellite,
            admin,
            collateral_vault,
            selector("lockCollateral(bytes32)") + word_bytes32(loan_id),
        )
        collateral_log = self.exact_event(
            collateral_receipt,
            self.satellite.coordinator,
            MESSAGE_SENT_TOPIC,
        )
        decode_hex(
            require_list(collateral_log.get("topics"), "collateral MessageSent topics")[1],
            "collateral message ID",
            32,
        )
        mint_payload = b"".join(
            [
                word_bytes32(lock_id),
                word_bytes32(loan_id),
                word_address(canonical),
                word_address(hub),
                word_address(self.address("wrapped_uft")),
                word_address(self.address("satellite_settlement_vault")),
                word_uint(principal),
            ]
        )
        collateral_payload = b"".join(
            [
                word_bytes32(loan_id),
                word_bytes32(collateral_id),
                word_address(account),
                word_address(admin),
                word_address(governance),
                word_address(collateral_token),
                word_uint(collateral_amount),
                word_bytes32(policy_hash),
            ]
        )
        return (
            mint_receipt,
            mint_payload,
            collateral_receipt,
            collateral_payload,
            account,
        )

    def execute_and_acknowledge(
        self,
        sequence: int,
        route_purpose: str,
        source_domain: Domain,
        destination_domain: Domain,
        source_receipt: dict[str, Any],
        payload: bytes,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        source_log = self.exact_event(
            source_receipt,
            source_domain.coordinator,
            MESSAGE_SENT_TOPIC,
        )
        source_topics = [
            canonical_hex(decode_hex(value, "source event topic", 32))
            for value in require_list(source_log.get("topics"), "source event topics")
        ]
        message_id = source_topics[1]
        envelope = self.envelope(source_domain, message_id)
        if canonical_hex(keccak256(payload)) != envelope["payload_hash"]:
            fail(f"message {sequence} payload differs from the stored envelope")
        source_identity = self.receipt_identity(source_receipt)
        source_log_index = self.event_log_index(source_log)
        source_inclusion = self.inclusion(
            source_domain,
            source_identity["transaction_hash"],
            source_log_index,
        )
        source_event_hash = solidity_hash(
            "UNIFIED_MESSAGE_SENT_V1",
            [
                word_address(envelope["source_coordinator"]),
                word_bytes32(message_id),
                word_bytes32(envelope["lane_id"]),
                word_uint(envelope["source_nonce"]),
                word_uint(envelope["action_ordinal"]),
                word_bytes32(envelope["payload_hash"]),
            ],
        )
        source_proof = self.make_proof(
            source_domain,
            source_inclusion,
            source_event_hash,
            source_log_index,
            envelope["source_finality_policy_hash"],
        )
        source_certificate = self.certificate(
            source_proof,
            message_id,
            source_domain,
            destination_domain,
        )
        source_record = {
            "chain_id": source_domain.chain_id,
            **source_identity,
            "log_index": source_log_index,
            "raw_evidence_object_hash": source_inclusion["raw_evidence_object_hash"],
            "proof_id": f"phase8-source-{sequence:02d}",
            "proof_hash": proof_hash(source_proof),
            "certificate_id": f"phase8-source-certificate-{sequence:02d}",
            "certificate_hash": certificate_hash(source_certificate),
            "proof": source_proof,
            "certificate": source_certificate,
            "authenticated_inclusion": source_inclusion["authenticated_inclusion"],
        }
        provider_attempts = observed_provider_attempts(
            sequence,
            self.args.provider_a_url,
            self.args.provider_b_url,
            message_id,
            envelope,
            source_proof,
            source_record["proof_hash"],
        )
        execute_input = execute_calldata(
            envelope,
            payload,
            source_proof,
            source_certificate,
        )
        expected_result = self.call(
            destination_domain,
            destination_domain.coordinator,
            execute_input,
        )
        if len(expected_result) != 32 or expected_result == b"\x00" * 32:
            fail("executeMessage preflight returned an invalid result hash")
        result_hash = canonical_hex(expected_result)
        destination_receipt = self.transact(
            destination_domain,
            self.address("local_governance"),
            destination_domain.coordinator,
            execute_input,
        )
        destination_log = self.exact_event(
            destination_receipt,
            destination_domain.coordinator,
            MESSAGE_EXECUTED_TOPIC,
            message_id,
        )
        destination_topics = [
            canonical_hex(decode_hex(value, "destination event topic", 32))
            for value in require_list(destination_log.get("topics"), "destination event topics")
        ]
        destination_data = decode_hex(destination_log.get("data"), "destination event data", 64)
        if (
            destination_topics[2] != envelope["lane_id"]
            or destination_topics[3] != canonical_hex(word_uint(envelope["source_nonce"]))
            or destination_data[:32] != word_address(envelope["destination_component"])
            or canonical_hex(destination_data[-32:]) != result_hash
        ):
            fail("MessageExecuted differs from the exact envelope/result")
        destination_identity = self.receipt_identity(destination_receipt)
        destination_log_index = self.event_log_index(destination_log)
        destination_inclusion = self.inclusion(
            destination_domain,
            destination_identity["transaction_hash"],
            destination_log_index,
        )
        acknowledgement_commitment = solidity_hash(
            "UNIFIED_XCHAIN_EXECUTION_ACKNOWLEDGEMENT_V1",
            [
                word_address(envelope["destination_coordinator"]),
                word_bytes32(message_id),
                word_bytes32(result_hash),
            ],
        )
        acknowledgement_proof = self.make_proof(
            destination_domain,
            destination_inclusion,
            acknowledgement_commitment,
            destination_log_index,
            envelope["destination_finality_policy_hash"],
        )
        acknowledgement_certificate = self.certificate(
            acknowledgement_proof,
            message_id,
            destination_domain,
            source_domain,
        )
        acknowledgement_input = acknowledgement_calldata(
            envelope,
            result_hash,
            acknowledgement_proof,
            acknowledgement_certificate,
        )
        expected_commitment = self.call(
            source_domain,
            source_domain.coordinator,
            acknowledgement_input,
        )
        if canonical_hex(expected_commitment) != acknowledgement_commitment:
            fail("recordAcknowledgement preflight commitment differs")
        acknowledgement_receipt = self.transact(
            source_domain,
            self.address("local_governance"),
            source_domain.coordinator,
            acknowledgement_input,
        )
        acknowledgement_log = self.exact_event(
            acknowledgement_receipt,
            source_domain.coordinator,
            MESSAGE_ACKNOWLEDGED_TOPIC,
            message_id,
        )
        acknowledgement_topics = [
            canonical_hex(decode_hex(value, "acknowledgement topic", 32))
            for value in require_list(acknowledgement_log.get("topics"), "acknowledgement topics")
        ]
        if acknowledgement_topics[2:] != [result_hash, acknowledgement_commitment]:
            fail("MessageAcknowledged differs from the exact result/commitment")

        destination_record = {
            "chain_id": destination_domain.chain_id,
            **destination_identity,
            "log_index": destination_log_index,
            "result_hash": result_hash,
        }
        acknowledgement_identity = self.receipt_identity(acknowledgement_receipt)
        acknowledgement_record = {
            **acknowledgement_identity,
            "log_index": self.event_log_index(acknowledgement_log),
            "commitment": acknowledgement_commitment,
            "finalized": True,
            "proof_id": f"phase8-acknowledgement-{sequence:02d}",
            "proof_hash": proof_hash(acknowledgement_proof),
            "certificate_id": f"phase8-ack-certificate-{sequence:02d}",
            "certificate_hash": certificate_hash(acknowledgement_certificate),
            "raw_evidence_object_hash": destination_inclusion["raw_evidence_object_hash"],
            "proof": acknowledgement_proof,
            "certificate": acknowledgement_certificate,
            "authenticated_inclusion": destination_inclusion["authenticated_inclusion"],
        }
        record = {
            "sequence": sequence,
            "route_purpose": route_purpose,
            "envelope": envelope,
            "payload": canonical_hex(payload),
            "source": source_record,
            "provider_attempts": provider_attempts,
            "destination": destination_record,
            "acknowledgement": acknowledgement_record,
            "source_final": True,
            "destination_executed": True,
            "execute_calldata": canonical_hex(execute_input),
            "acknowledgement_calldata": canonical_hex(acknowledgement_input),
        }
        replay_purpose = {1: "MINT", 6: "REPAYMENT", 7: "COLLATERAL_RELEASE"}.get(sequence)
        if replay_purpose is not None:
            self.replay_candidates.append(
                (
                    replay_purpose,
                    destination_domain,
                    message_id,
                    result_hash,
                    execute_input,
                )
            )
        return record, destination_receipt

    def run_replays(self) -> list[dict[str, Any]]:
        if len(self.replay_candidates) != 3:
            fail("full flow did not retain all required replay candidates")
        results: list[dict[str, Any]] = []
        for purpose, domain, message_id, original_result, execute_input in self.replay_candidates:
            replay_result = self.call(domain, domain.coordinator, execute_input)
            if canonical_hex(replay_result) != original_result:
                fail(f"{purpose} replay preflight result drifted")
            receipt = self.transact(
                domain,
                self.address("local_governance"),
                domain.coordinator,
                execute_input,
            )
            if require_list(receipt.get("logs"), f"{purpose} replay logs"):
                fail(f"{purpose} replay emitted a duplicate execution/economic event")
            identity = self.receipt_identity(receipt)
            results.append(
                {
                    "purpose": purpose,
                    "message_id": message_id,
                    "destination_chain_id": domain.chain_id,
                    "transaction_hash": identity["transaction_hash"],
                    "block_hash": identity["block_hash"],
                    "block_number": identity["block_number"],
                    "original_result_hash": original_result,
                    "replay_result_hash": original_result,
                    "economic_effect_delta_units": "0",
                    "duplicate_prevented": True,
                }
            )
        return results

    def run(self) -> dict[str, Any]:
        (
            mint_receipt,
            mint_payload,
            collateral_receipt,
            collateral_payload,
            account,
        ) = self.bootstrap()
        admin = self.address("local_admin")
        governance = self.address("local_governance")
        loan_id = self.hex32("loan_id")
        lock_id = self.hex32("funding_lock_id")
        collateral_id = self.hex32("collateral_id")
        policy_hash = self.hex32("loan_policy_hash")
        canonical = self.address("canonical_token")
        hub = self.address("bridge_hub")
        wrapped = self.address("wrapped_uft")
        collateral_token = self.address("collateral_token")
        principal = self.integer("principal_units")
        collateral_amount = self.integer("collateral_units")

        first, mint_execution_receipt = self.execute_and_acknowledge(
            1, "mint", self.home, self.satellite, mint_receipt, mint_payload
        )
        self.messages.append(first)
        if self.args.max_messages >= 2:
            second, _ = self.execute_and_acknowledge(
                2,
                "report",
                self.satellite,
                self.home,
                collateral_receipt,
                collateral_payload,
            )
            self.messages.append(second)
        report_payload = b"".join(
            [
                word_bytes32(loan_id),
                word_bytes32(lock_id),
                word_address(account),
                word_address(admin),
                word_address(governance),
                word_address(wrapped),
                word_uint(principal),
                word_bytes32(policy_hash),
            ]
        )
        mint_report_source_receipt = mint_execution_receipt
        if self.args.max_messages >= 3:
            third, mint_report_execution_receipt = self.execute_and_acknowledge(
                3,
                "report",
                self.satellite,
                self.home,
                mint_report_source_receipt,
                report_payload,
            )
            self.messages.append(third)
        else:
            mint_report_execution_receipt = {}
        borrower_received_principal = 0
        if self.args.max_messages >= 4:
            fourth, disbursement_execution_receipt = self.execute_and_acknowledge(
                4,
                "disbursement",
                self.home,
                self.satellite,
                mint_report_execution_receipt,
                report_payload,
            )
            self.messages.append(fourth)
            borrower_received_principal = self.uint_call(
                self.satellite,
                wrapped,
                "balanceOf(address)",
                word_address(admin),
            )
            if borrower_received_principal != principal:
                fail("borrower did not receive the exact disbursement principal")
        else:
            disbursement_execution_receipt = {}
        if self.args.max_messages >= 5:
            fifth, _ = self.execute_and_acknowledge(
                5,
                "report",
                self.satellite,
                self.home,
                disbursement_execution_receipt,
                report_payload,
            )
            self.messages.append(fifth)

        burn_id = canonical_hex(keccak256(b"LOCAL_FULL_FLOW_REPAYMENT_BURN"))
        payment_id = canonical_hex(keccak256(b"LOCAL_FULL_FLOW_PAYMENT"))
        if self.args.max_messages >= 6:
            burn_expiry = self.latest_timestamp(self.satellite) + 2 * 24 * 60 * 60
            burn_receipt = self.transact(
                self.satellite,
                admin,
                wrapped,
                selector("burnForLoanRepayment(bytes32,bytes32,bytes32,bytes32,uint256,uint64)")
                + word_bytes32(burn_id)
                + word_bytes32(loan_id)
                + word_bytes32(payment_id)
                + word_bytes32(self.hex32("repayment_route_hash"))
                + word_uint(principal)
                + word_uint(burn_expiry),
            )
            repayment_payload = b"".join(
                [
                    word_bytes32(burn_id),
                    word_bytes32(loan_id),
                    word_bytes32(payment_id),
                    word_bytes32(self.hex32("mint_route_hash")),
                    word_address(canonical),
                    word_address(hub),
                    word_address(wrapped),
                    word_address(governance),
                    word_uint(principal),
                ]
            )
            sixth, repayment_execution_receipt = self.execute_and_acknowledge(
                6,
                "repayment",
                self.satellite,
                self.home,
                burn_receipt,
                repayment_payload,
            )
            self.messages.append(sixth)
        else:
            repayment_execution_receipt = {}
        release_payload = b"".join(
            [
                word_bytes32(loan_id),
                word_bytes32(collateral_id),
                word_address(account),
                word_address(admin),
                word_address(governance),
                word_address(collateral_token),
                word_uint(collateral_amount),
                word_bytes32(policy_hash),
            ]
        )
        if self.args.max_messages >= 7:
            seventh, release_execution_receipt = self.execute_and_acknowledge(
                7,
                "collateral_release",
                self.home,
                self.satellite,
                repayment_execution_receipt,
                release_payload,
            )
            self.messages.append(seventh)
        else:
            release_execution_receipt = {}
        replays: list[dict[str, Any]] = []
        final_state: dict[str, Any] = {}
        if self.args.max_messages >= 8:
            eighth, _ = self.execute_and_acknowledge(
                8,
                "report",
                self.satellite,
                self.home,
                release_execution_receipt,
                release_payload,
            )
            self.messages.append(eighth)
            state = self.call(
                self.home,
                account,
                selector("state()"),
            )
            if len(state) != 32 or int.from_bytes(state, "big") != 4:
                fail("eight-message flow did not reach terminal CLOSED state")
            replays = self.run_replays()
            max_supply = self.uint_call(self.home, canonical, "MAX_SUPPLY()")
            lender_balance = self.uint_call(
                self.home,
                canonical,
                "balanceOf(address)",
                word_address(governance),
            )
            lender_received = lender_balance - (max_supply - principal)
            final_state = {
                "loan_state": "CLOSED",
                "outstanding_principal_units": str(
                    self.uint_call(self.home, account, "outstandingPrincipal()")
                ),
                "bridge_backing_units": str(self.uint_call(self.home, hub, "totalBridgeBacking()")),
                "loan_backing_units": str(
                    self.uint_call(
                        self.home,
                        hub,
                        "loanBacking(bytes32)",
                        word_bytes32(loan_id),
                    )
                ),
                "wrapped_supply_units": str(
                    self.uint_call(self.satellite, wrapped, "totalSupply()")
                ),
                "route_exposure_units": str(
                    self.uint_call(
                        self.home,
                        hub,
                        "routeBacking(bytes32)",
                        word_bytes32(self.hex32("mint_route_hash")),
                    )
                ),
                "aggregate_exposure_units": str(
                    self.uint_call(self.home, hub, "totalBridgeBacking()")
                ),
                "settlement_vault_units": str(
                    self.uint_call(
                        self.satellite,
                        wrapped,
                        "balanceOf(address)",
                        word_address(self.address("satellite_settlement_vault")),
                    )
                ),
                "collateral_vault_units": str(
                    self.uint_call(
                        self.satellite,
                        collateral_token,
                        "balanceOf(address)",
                        word_address(self.address("satellite_collateral_vault")),
                    )
                ),
                "collateral_released": self.uint_call(self.home, account, "collateralReleased()")
                == 1,
                "borrower_received_principal_units": str(borrower_received_principal),
                "lender_received_repayment_units": str(lender_received),
                "duplicate_economic_effects": "0",
            }
            if (
                final_state["outstanding_principal_units"] != "0"
                or final_state["bridge_backing_units"] != "0"
                or final_state["loan_backing_units"] != "0"
                or final_state["wrapped_supply_units"] != "0"
                or final_state["route_exposure_units"] != "0"
                or final_state["aggregate_exposure_units"] != "0"
                or final_state["settlement_vault_units"] != "0"
                or final_state["collateral_vault_units"] != "0"
                or final_state["collateral_released"] is not True
                or borrower_received_principal != principal
                or lender_received != principal
            ):
                fail("terminal economic state differs from the exact closed-loan invariant")
        return {
            "schema_version": 1,
            "artifact_type": "PHASE8_AUTHENTICATED_FLOW_INPUT",
            "environment": "local",
            "contains_real_value": False,
            "proof_boundary": BOUNDARY,
            "protocol_id": self.hex32("protocol_id"),
            "loan_id": self.hex32("loan_id"),
            "loan_account": account,
            "completed_message_count": len(self.messages),
            "requested_message_count": self.args.max_messages,
            "messages": self.messages,
            "replays": replays,
            "final_state": final_state,
        }


def load_blueprint(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read deployment blueprint: {error}")
    blueprint = require_object(raw, "deployment blueprint")
    if (
        blueprint.get("schema_version") != 1
        or blueprint.get("artifact_type") != "PHASE8_LIVE_DEPLOYMENT_BLUEPRINT"
        or blueprint.get("environment") != "local"
        or blueprint.get("contains_real_value") is not False
    ):
        fail("deployment blueprint is not the local deploy-only artifact")
    return blueprint


def controlled_output(path: Path) -> Path:
    resolved = path.resolve()
    allowed = [
        (ROOT / ".cache/phase8-release").resolve(),
        (ROOT / "protocol/deployments/local").resolve(),
    ]
    if not any(resolved == root or root in resolved.parents for root in allowed):
        fail("flow output must remain in a reset-controlled Phase 8 root")
    return resolved


def write_output(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(document, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".pending",
        dir=path.parent,
        text=True,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--home-rpc", required=True)
    parser.add_argument("--satellite-rpc", required=True)
    parser.add_argument("--provider-a-url", required=True)
    parser.add_argument("--provider-b-url", required=True)
    parser.add_argument("--blueprint", type=Path, required=True)
    parser.add_argument("--verifier", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-messages", type=int, choices=range(1, 9), default=8)
    args = parser.parse_args()
    provider_endpoint(args.provider_a_url, "/v1/messages")
    provider_endpoint(args.provider_b_url, "/v1/messages")
    args.verifier = args.verifier.resolve()
    if not args.verifier.is_file():
        fail("production inclusion verifier executable is absent")
    output = controlled_output(args.output)
    driver = FlowDriver(args, load_blueprint(args.blueprint.resolve()))
    document = driver.run()
    write_output(output, document)
    print(
        json.dumps(
            {
                "status": BOUNDARY,
                "completed_message_count": document["completed_message_count"],
                "output": str(output),
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
