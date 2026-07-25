"""Build live Anvil signed-header transaction/receipt MPT evidence.

The producer is deliberately restricted to local one-transaction blocks. It
reconstructs exact header and receipt RLP from Anvil v1.7.1 RPC responses,
matches the live block, transaction, transaction-root, and receipt-root hashes,
mines or observes the exact confirmation depth, signs every header through the
deterministic local observer helper, and emits the release-evidence inclusion
shape consumed by the production Phase 7C verifier.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, NoReturn, cast
from urllib.parse import urlparse

from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[1]
OBSERVER_HELPER = ROOT / "tools/sign_phase8_observer.py"
BOUNDARY = "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT"
HEADER_DOMAIN = b"UNIFIED_EVM_HEADER_AUTHORITY_V1\x00"
PROOF_DOMAIN = b"UNIFIED_EVM_TRANSACTION_RECEIPT_INCLUSION_V1\x00"


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def keccak256(value: bytes) -> bytes:
    return keccak.new(digest_bits=256, data=value).digest()


def canonical_hex(value: bytes) -> str:
    return "0x" + value.hex()


def decode_hex(value: object, label: str, expected: int | None = None) -> bytes:
    if not isinstance(value, str) or not value.startswith("0x") or value != value.lower():
        fail(f"{label} must be canonical lower-case 0x hex")
    try:
        decoded = bytes.fromhex(value[2:])
    except ValueError as error:
        fail(f"{label} is not hexadecimal: {error}")
    if expected is not None and len(decoded) != expected:
        fail(f"{label} must be {expected} bytes")
    return decoded


def quantity(value: object, label: str) -> int:
    if not isinstance(value, str) or not value.startswith("0x"):
        fail(f"{label} must be an RPC quantity")
    try:
        result = int(value, 16)
    except ValueError as error:
        fail(f"{label} is not a quantity: {error}")
    if result < 0 or value != hex(result):
        fail(f"{label} is not a canonical RPC quantity")
    return result


def quantity_bytes(value: object, label: str) -> bytes:
    number = quantity(value, label)
    if number == 0:
        return b""
    return number.to_bytes((number.bit_length() + 7) // 8, "big")


def rlp_bytes(value: bytes) -> bytes:
    if len(value) == 1 and value[0] < 0x80:
        return value
    if len(value) <= 55:
        return bytes([0x80 + len(value)]) + value
    length = len(value).to_bytes((len(value).bit_length() + 7) // 8, "big")
    return bytes([0xB7 + len(length)]) + length + value


def rlp_list(values: list[bytes]) -> bytes:
    payload = b"".join(values)
    if len(payload) <= 55:
        return bytes([0xC0 + len(payload)]) + payload
    length = len(payload).to_bytes((len(payload).bit_length() + 7) // 8, "big")
    return bytes([0xF7 + len(length)]) + length + payload


def rlp_quantity(value: int) -> bytes:
    if value == 0:
        return b"\x80"
    return rlp_bytes(value.to_bytes((value.bit_length() + 7) // 8, "big"))


def bytes_to_nibbles(value: bytes) -> list[int]:
    result: list[int] = []
    for item in value:
        result.extend((item >> 4, item & 0x0F))
    return result


def compact_leaf_path(key: bytes) -> bytes:
    nibbles = bytes_to_nibbles(key)
    odd = len(nibbles) % 2 == 1
    prefixed = [3, *nibbles] if odd else [2, 0, *nibbles]
    return bytes(
        (prefixed[index] << 4) | prefixed[index + 1] for index in range(0, len(prefixed), 2)
    )


def single_leaf_node(index: int, value: bytes) -> bytes:
    key = rlp_quantity(index)
    return rlp_list([rlp_bytes(compact_leaf_path(key)), rlp_bytes(value)])


def length_prefixed(value: bytes) -> bytes:
    return len(value).to_bytes(8, "big") + value


class LocalRPC:
    def __init__(self, url: str) -> None:
        parsed = urlparse(url)
        if (
            parsed.scheme != "http"
            or parsed.hostname not in {"127.0.0.1", "localhost"}
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
        ):
            fail("RPC URL must be an unauthenticated local HTTP endpoint")
        self.host = parsed.hostname
        self.port = parsed.port or 80
        self.path = parsed.path or "/"
        self.identifier = 0

    def call(self, method: str, parameters: list[object]) -> Any:
        self.identifier += 1
        body = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": self.identifier,
                "method": method,
                "params": parameters,
            },
            separators=(",", ":"),
        )
        connection = http.client.HTTPConnection(self.host, self.port, timeout=10)
        try:
            connection.request(
                "POST",
                self.path,
                body=body,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            raw = response.read()
        finally:
            connection.close()
        if response.status != 200:
            fail(f"{method} returned HTTP {response.status}")
        decoded = json.loads(raw)
        if not isinstance(decoded, dict) or decoded.get("error") is not None:
            fail(f"{method} failed: {decoded!r}")
        return decoded.get("result")


def require_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} is not an object")
    return cast(dict[str, Any], value)


def require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{label} is not a list")
    return value


def encode_header(block: dict[str, Any]) -> bytes:
    fields = [
        rlp_bytes(decode_hex(block.get("parentHash"), "parentHash", 32)),
        rlp_bytes(decode_hex(block.get("sha3Uncles"), "sha3Uncles", 32)),
        rlp_bytes(decode_hex(block.get("miner"), "miner", 20)),
        rlp_bytes(decode_hex(block.get("stateRoot"), "stateRoot", 32)),
        rlp_bytes(decode_hex(block.get("transactionsRoot"), "transactionsRoot", 32)),
        rlp_bytes(decode_hex(block.get("receiptsRoot"), "receiptsRoot", 32)),
        rlp_bytes(decode_hex(block.get("logsBloom"), "logsBloom", 256)),
        rlp_bytes(quantity_bytes(block.get("difficulty"), "difficulty")),
        rlp_bytes(quantity_bytes(block.get("number"), "number")),
        rlp_bytes(quantity_bytes(block.get("gasLimit"), "gasLimit")),
        rlp_bytes(quantity_bytes(block.get("gasUsed"), "gasUsed")),
        rlp_bytes(quantity_bytes(block.get("timestamp"), "timestamp")),
        rlp_bytes(decode_hex(block.get("extraData"), "extraData")),
        rlp_bytes(decode_hex(block.get("mixHash"), "mixHash", 32)),
        rlp_bytes(decode_hex(block.get("nonce"), "nonce", 8)),
    ]
    optional = (
        ("baseFeePerGas", "quantity", None),
        ("withdrawalsRoot", "hex", 32),
        ("blobGasUsed", "quantity", None),
        ("excessBlobGas", "quantity", None),
        ("parentBeaconBlockRoot", "hex", 32),
        ("requestsHash", "hex", 32),
    )
    optional_gap_seen = False
    for name, kind, width in optional:
        value = block.get(name)
        if value is None:
            optional_gap_seen = True
            continue
        if optional_gap_seen:
            fail(f"header field {name} is present after an earlier fork field is missing")
        payload = (
            quantity_bytes(value, name) if kind == "quantity" else decode_hex(value, name, width)
        )
        fields.append(rlp_bytes(payload))
    encoded = rlp_list(fields)
    expected_hash = decode_hex(block.get("hash"), "block hash", 32)
    if keccak256(encoded) != expected_hash:
        fail("reconstructed header RLP does not match the live block hash")
    return encoded


def encode_log(value: Any, index: int) -> bytes:
    log = require_object(value, f"log {index}")
    topics = require_list(log.get("topics"), f"log {index} topics")
    return rlp_list(
        [
            rlp_bytes(decode_hex(log.get("address"), f"log {index} address", 20)),
            rlp_list([rlp_bytes(decode_hex(topic, f"log {index} topic", 32)) for topic in topics]),
            rlp_bytes(decode_hex(log.get("data"), f"log {index} data")),
        ]
    )


def encode_receipt(receipt: dict[str, Any]) -> bytes:
    status = receipt.get("status")
    if status is None:
        fail("pre-Byzantium state-root receipts are outside the local gate")
    logs = require_list(receipt.get("logs"), "receipt logs")
    payload = rlp_list(
        [
            rlp_bytes(quantity_bytes(status, "receipt status")),
            rlp_bytes(quantity_bytes(receipt.get("cumulativeGasUsed"), "cumulativeGasUsed")),
            rlp_bytes(decode_hex(receipt.get("logsBloom"), "logsBloom", 256)),
            rlp_list([encode_log(log, index) for index, log in enumerate(logs)]),
        ]
    )
    receipt_type = quantity(receipt.get("type", "0x0"), "receipt type")
    if receipt_type == 0:
        return payload
    if receipt_type > 0x7F:
        fail("receipt type is outside EIP-2718")
    return bytes([receipt_type]) + payload


def observer_helper(operation: str, domain: str, value: str | None = None) -> str:
    arguments = [sys.executable, str(OBSERVER_HELPER), operation, domain]
    if value is not None:
        arguments.append(value)
    result = subprocess.run(  # noqa: S603
        arguments,
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    return result.stdout.strip()


def signed_header(block: dict[str, Any], chain_id: int, domain: str) -> dict[str, str]:
    header_rlp = encode_header(block)
    timestamp = quantity(block.get("timestamp"), "timestamp")
    observed_nanos = timestamp * 1_000_000_000
    if observed_nanos > (1 << 63) - 1:
        fail("header observed time exceeds Go time.Unix nanos")
    digest = keccak256(
        HEADER_DOMAIN
        + chain_id.to_bytes(8, "big")
        + observed_nanos.to_bytes(8, "big")
        + keccak256(header_rlp)
    )
    signature = observer_helper("sign", domain, canonical_hex(digest))
    decode_hex(signature, "header signature", 64)
    return {
        "header_rlp": canonical_hex(header_rlp),
        "header_observed_at_unix_nanos": str(observed_nanos),
        "header_signature_ed25519": signature,
    }


def receipt_proof_hash(
    block_hash: str,
    index: int,
    transaction_rlp: bytes,
    transaction_node: bytes,
    receipt_rlp: bytes,
    receipt_node: bytes,
) -> str:
    digest = keccak256(
        PROOF_DOMAIN
        + length_prefixed(block_hash.encode("ascii"))
        + index.to_bytes(8, "big")
        + length_prefixed(transaction_rlp)
        + length_prefixed(transaction_node)
        + length_prefixed(receipt_rlp)
        + length_prefixed(receipt_node)
    )
    return canonical_hex(digest)


def build(args: argparse.Namespace) -> dict[str, Any]:
    rpc = LocalRPC(args.rpc_url)
    chain_id = quantity(rpc.call("eth_chainId", []), "chain id")
    if chain_id == 0:
        fail("chain ID must be nonzero")
    receipt = require_object(
        rpc.call("eth_getTransactionReceipt", [args.transaction_hash]),
        "transaction receipt",
    )
    transaction_hash = canonical_hex(
        decode_hex(receipt.get("transactionHash"), "transaction hash", 32)
    )
    if transaction_hash != args.transaction_hash:
        fail("receipt transaction hash differs from requested transaction")
    block_hash = canonical_hex(decode_hex(receipt.get("blockHash"), "block hash", 32))
    block = require_object(
        rpc.call("eth_getBlockByHash", [block_hash, False]),
        "source block",
    )
    transactions = require_list(block.get("transactions"), "block transactions")
    if transactions != [transaction_hash]:
        fail("authenticated inclusion producer requires a one-transaction Anvil block")
    transaction_index = quantity(receipt.get("transactionIndex"), "transaction index")
    if transaction_index != 0:
        fail("one-transaction block must use transaction index zero")
    block_receipts = require_list(
        rpc.call("eth_getBlockReceipts", [block_hash]),
        "block receipts",
    )
    if len(block_receipts) != 1:
        fail("one-transaction block must have exactly one receipt")
    receipt = require_object(block_receipts[0], "block receipt zero")
    receipt_logs = require_list(receipt.get("logs"), "receipt logs")
    target_logs = [
        require_object(value, f"receipt log {index}")
        for index, value in enumerate(receipt_logs)
        if quantity(
            require_object(value, f"receipt log {index}").get("logIndex"),
            f"receipt log {index} index",
        )
        == args.target_log_index
    ]
    if len(target_logs) != 1:
        fail("target log index does not identify exactly one receipt log")
    target_log = target_logs[0]
    target_log_address = canonical_hex(
        decode_hex(target_log.get("address"), "target log address", 20)
    )
    if target_log_address != args.coordinator_address:
        fail("target log is not emitted by the configured coordinator")
    target_log_topics = [
        canonical_hex(decode_hex(topic, "target log topic", 32))
        for topic in require_list(target_log.get("topics"), "target log topics")
    ]
    if not target_log_topics:
        fail("target coordinator log must have at least one topic")
    target_log_data = canonical_hex(decode_hex(target_log.get("data"), "target log data"))

    transaction_rlp = decode_hex(
        rpc.call("eth_getRawTransactionByHash", [transaction_hash]),
        "raw transaction",
    )
    if keccak256(transaction_rlp) != decode_hex(transaction_hash, "transaction hash", 32):
        fail("raw transaction RLP does not match transaction hash")
    receipt_rlp = encode_receipt(receipt)
    transaction_node = single_leaf_node(0, transaction_rlp)
    receipt_node = single_leaf_node(0, receipt_rlp)
    if keccak256(transaction_node) != decode_hex(
        block.get("transactionsRoot"), "transactions root", 32
    ):
        fail("transaction MPT root does not match live header")
    if keccak256(receipt_node) != decode_hex(block.get("receiptsRoot"), "receipts root", 32):
        fail("receipt MPT root does not match live header")

    block_number = quantity(block.get("number"), "block number")
    target_head = block_number + args.required_depth
    current_head = quantity(rpc.call("eth_blockNumber", []), "current block number")
    if current_head < target_head:
        if not args.mine_confirmations:
            fail(
                f"chain head {current_head} is below required finality head {target_head}; "
                "pass --mine-confirmations for the isolated local chain"
            )
        rpc.call("anvil_mine", [hex(target_head - current_head)])

    confirmations: list[dict[str, str]] = []
    previous_hash = block_hash
    for number in range(block_number + 1, target_head + 1):
        confirmation = require_object(
            rpc.call("eth_getBlockByNumber", [hex(number), False]),
            f"confirmation block {number}",
        )
        parent_hash = canonical_hex(
            decode_hex(confirmation.get("parentHash"), "confirmation parent hash", 32)
        )
        if parent_hash != previous_hash:
            fail(f"confirmation block {number} is not parent-linked")
        signed = signed_header(confirmation, chain_id, args.domain)
        confirmations.append(signed)
        previous_hash = canonical_hex(
            decode_hex(confirmation.get("hash"), "confirmation block hash", 32)
        )

    source_header = signed_header(block, chain_id, args.domain)
    proof_hash = receipt_proof_hash(
        block_hash,
        0,
        transaction_rlp,
        transaction_node,
        receipt_rlp,
        receipt_node,
    )
    public_key = observer_helper("public", args.domain)
    decode_hex(public_key, "observer public key", 32)
    inclusion = {
        **source_header,
        "receipts": [
            {
                "transaction_index": 0,
                "transaction_rlp": canonical_hex(transaction_rlp),
                "transaction_proof_nodes": [canonical_hex(transaction_node)],
                "receipt_rlp": canonical_hex(receipt_rlp),
                "receipt_proof_nodes": [canonical_hex(receipt_node)],
            }
        ],
        "confirmation_headers": confirmations,
    }
    inclusion_hash = canonical_hex(
        keccak256(
            json.dumps(
                inclusion,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=False,
            ).encode("utf-8")
        )
    )
    finality_head_hash = previous_hash
    return {
        "schema_version": 1,
        "artifact_type": "PHASE8_ANVIL_AUTHENTICATED_INCLUSION",
        "proof_boundary": BOUNDARY,
        "environment": "local",
        "contains_real_value": False,
        "domain": args.domain,
        "chain_id": chain_id,
        "coordinator_address": args.coordinator_address,
        "required_depth": args.required_depth,
        "target_transaction_index": 0,
        "observer_public_key_ed25519": public_key,
        "expected_log": {
            "address": target_log_address,
            "topics": target_log_topics,
            "data": target_log_data,
            "log_index": args.target_log_index,
        },
        "authenticated_inclusion": inclusion,
        "raw_evidence_object_hash": inclusion_hash,
        "verified_source_event_proof_fields": {
            "transaction_hash": transaction_hash,
            "source_block_number": block_number,
            "source_block_timestamp": quantity(block.get("timestamp"), "block timestamp"),
            "source_block_hash": block_hash,
            "transaction_index": 0,
            "receipt_root": canonical_hex(
                decode_hex(block.get("receiptsRoot"), "receipts root", 32)
            ),
            "receipt_proof_hash": proof_hash,
            "finality_head_number": target_head,
            "finality_head_hash": finality_head_hash,
            "required_depth": args.required_depth,
        },
    }


def write_output(path: Path, document: dict[str, Any]) -> None:
    path = path.resolve()
    workspace = ROOT.resolve()
    if workspace not in path.parents:
        fail("output must remain inside the workspace")
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
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--transaction-hash", required=True)
    parser.add_argument("--domain", choices=("home", "satellite"), required=True)
    parser.add_argument("--coordinator-address", required=True)
    parser.add_argument("--target-log-index", required=True, type=int)
    parser.add_argument("--required-depth", type=int, default=12)
    parser.add_argument("--mine-confirmations", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.required_depth <= 0:
        fail("required depth must be positive")
    if args.target_log_index < 0:
        fail("target log index must be nonnegative")
    args.transaction_hash = canonical_hex(decode_hex(args.transaction_hash, "transaction hash", 32))
    args.coordinator_address = canonical_hex(
        decode_hex(args.coordinator_address, "coordinator address", 20)
    )
    document = build(args)
    if args.output is None:
        print(json.dumps(document, indent=2, sort_keys=True))
    else:
        write_output(args.output, document)


if __name__ == "__main__":
    main()
