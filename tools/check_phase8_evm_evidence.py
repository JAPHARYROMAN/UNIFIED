"""Check atomic Phase 8 EVM evidence against exact broadcast calldata."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, NoReturn

from Crypto.Hash import keccak


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def hex_bytes(value: Any, label: str) -> bytes:
    if (
        not isinstance(value, str)
        or not value.startswith("0x")
        or value != value.lower()
        or len(value) % 2
    ):
        fail(f"{label} is not canonical lowercase 0x hex")
    try:
        return bytes.fromhex(value[2:])
    except ValueError as error:
        fail(f"{label} is not hexadecimal: {error}")


def word(data: bytes, index: int, label: str) -> bytes:
    start = index * 32
    value = data[start : start + 32]
    if len(value) != 32:
        fail(f"{label} is truncated at word {index}")
    return value


def uint_word(data: bytes, index: int, label: str) -> int:
    return int.from_bytes(word(data, index, label), "big")


def keccak256(data: bytes) -> bytes:
    return keccak.new(digest_bits=256, data=data).digest()


def solidity_domain_hash(domain: str, words: list[bytes]) -> bytes:
    domain_bytes = domain.encode("ascii")
    offset = ((len(words) + 1) * 32).to_bytes(32, "big")
    tail = (
        len(domain_bytes).to_bytes(32, "big")
        + domain_bytes
        + bytes((-len(domain_bytes)) % 32)
    )
    return keccak256(offset + b"".join(words) + tail)


def decode_dynamic_bytes(data: bytes, offset: int, label: str) -> tuple[bytes, int]:
    if offset % 32:
        fail(f"{label} offset is not word-aligned")
    length = uint_word(data[offset:], 0, label)
    start = offset + 32
    padded_end = start + ((length + 31) // 32) * 32
    if padded_end > len(data):
        fail(f"{label} dynamic bytes are truncated")
    return data[start : start + length], padded_end


def proof_fields(encoded: bytes, label: str) -> dict[str, Any]:
    if uint_word(encoded, 0, label) != 32:
        fail(f"{label} lacks the canonical top-level tuple offset")
    body = encoded[32:]
    signature_offset = uint_word(body, 14, label)
    signature, end = decode_dynamic_bytes(body, signature_offset, f"{label}.signature")
    if end != len(body):
        fail(f"{label} has trailing or noncanonical data")
    return {
        "hash": keccak256(encoded),
        "source_block_hash": word(body, 0, label),
        "source_block_number": uint_word(body, 1, label),
        "source_block_timestamp": uint_word(body, 2, label),
        "finality_head_hash": word(body, 9, label),
        "finality_head_number": uint_word(body, 10, label),
        "required_depth": uint_word(body, 11, label),
        "authority_hash": word(body, 12, label),
        "commitment": word(body, 13, label),
        "signature": signature,
        "policy_hash": word(body, 15, label),
        "body": body,
    }


def certificate_fields(encoded: bytes, label: str) -> dict[str, Any]:
    if uint_word(encoded, 0, label) != 32:
        fail(f"{label} lacks the canonical top-level tuple offset")
    body = encoded[32:]
    signatures_offset = uint_word(body, 4, label)
    if signatures_offset < 5 * 32 or signatures_offset >= len(body):
        fail(f"{label} signatures offset is invalid")
    return {
        "message_id": word(body, 0, label),
        "proof_hash": word(body, 1, label),
        "signer_set_hash": word(body, 2, label),
        "version": uint_word(body, 3, label),
        "body": body,
    }


def padded_dynamic(value: bytes) -> bytes:
    return len(value).to_bytes(32, "big") + value + bytes((-len(value)) % 32)


def check_execute_calldata(
    calldata: bytes,
    envelope: bytes,
    payload: bytes,
    proof: bytes,
    certificate: bytes,
    label: str,
) -> None:
    if len(calldata) < 4 + 26 * 32:
        fail(f"{label} calldata is truncated")
    args = calldata[4:]
    if args[: 23 * 32] != envelope:
        fail(f"{label} envelope ABI differs from execute calldata")
    payload_offset = uint_word(args, 23, label)
    proof_offset = uint_word(args, 24, label)
    certificate_offset = uint_word(args, 25, label)
    if not (26 * 32 <= payload_offset < proof_offset < certificate_offset):
        fail(f"{label} dynamic argument offsets are not canonical")
    if args[payload_offset:proof_offset] != padded_dynamic(payload):
        fail(f"{label} payload differs from execute calldata")
    if args[proof_offset:certificate_offset] != proof[32:]:
        fail(f"{label} proof ABI differs from execute calldata")
    if args[certificate_offset:] != certificate[32:]:
        fail(f"{label} certificate ABI differs from execute calldata")


def check_ack_calldata(
    calldata: bytes,
    envelope: bytes,
    result_hash: bytes,
    proof: bytes,
    certificate: bytes,
    label: str,
) -> None:
    if len(calldata) < 4 + 26 * 32:
        fail(f"{label} calldata is truncated")
    args = calldata[4:]
    if args[: 23 * 32] != envelope or word(args, 23, label) != result_hash:
        fail(f"{label} envelope/result differs from acknowledgement calldata")
    proof_offset = uint_word(args, 24, label)
    certificate_offset = uint_word(args, 25, label)
    if not (26 * 32 <= proof_offset < certificate_offset):
        fail(f"{label} dynamic argument offsets are not canonical")
    if args[proof_offset:certificate_offset] != proof[32:]:
        fail(f"{label} proof ABI differs from acknowledgement calldata")
    if args[certificate_offset:] != certificate[32:]:
        fail(f"{label} certificate ABI differs from acknowledgement calldata")


def broadcast_inputs(raw: dict[str, Any]) -> dict[int, set[bytes]]:
    result: dict[int, set[bytes]] = {}
    for deployment in raw.get("deployments", []):
        chain = int(deployment["chain"])
        for transaction in deployment.get("transactions", []):
            input_hex = transaction.get("transaction", {}).get("input")
            if isinstance(input_hex, str):
                result.setdefault(chain, set()).add(hex_bytes(input_hex, "broadcast input"))
    return result


def check_message(
    evidence: dict[str, Any],
    sequence: int,
    live_inputs: dict[int, set[bytes]],
) -> None:
    prefix = f"flow_message_{sequence:02d}"
    message = evidence.get(prefix)
    if not isinstance(message, dict):
        fail(f"{prefix} is missing")
    envelope = hex_bytes(message[f"{prefix}_envelope_abi"], f"{prefix}.envelope")
    if len(envelope) != 23 * 32:
        fail(f"{prefix} envelope ABI has the wrong length")
    message_id = word(envelope, 1, prefix)
    declared_message_id = hex_bytes(message[f"{prefix}_message_id"], f"{prefix}.message_id")
    if message_id != declared_message_id:
        fail(f"{prefix} declared message ID differs from envelope")
    if solidity_domain_hash(
        "UNIFIED_XCHAIN_MESSAGE_V1", [word(envelope, 0, prefix)] + [
            word(envelope, index, prefix) for index in range(2, 23)
        ]
    ) != message_id:
        fail(f"{prefix} canonical message ID does not recompute")
    payload = hex_bytes(message[f"{prefix}_payload"], f"{prefix}.payload")
    payload_hash = keccak256(payload)
    if (
        payload_hash != word(envelope, 13, prefix)
        or payload_hash
        != hex_bytes(message[f"{prefix}_payload_hash"], f"{prefix}.payload_hash")
    ):
        fail(f"{prefix} payload hash differs")

    source_proof_abi = hex_bytes(
        message[f"{prefix}_source_proof_abi"], f"{prefix}.source_proof"
    )
    source_certificate_abi = hex_bytes(
        message[f"{prefix}_source_certificate_abi"], f"{prefix}.source_certificate"
    )
    source_proof = proof_fields(source_proof_abi, f"{prefix}.source_proof")
    source_certificate = certificate_fields(
        source_certificate_abi, f"{prefix}.source_certificate"
    )
    if source_certificate["message_id"] != message_id:
        fail(f"{prefix} source certificate message ID differs")
    if source_certificate["proof_hash"] != source_proof["hash"]:
        fail(f"{prefix} source certificate proof hash differs")
    if source_proof["commitment"] != solidity_domain_hash(
        "UNIFIED_OBSERVER_SIGNED_HEADER_V1",
        [
            source_proof["source_block_hash"],
            source_proof["source_block_number"].to_bytes(32, "big"),
            source_proof["source_block_timestamp"].to_bytes(32, "big"),
            source_proof["finality_head_hash"],
            source_proof["finality_head_number"].to_bytes(32, "big"),
            source_proof["required_depth"].to_bytes(32, "big"),
            source_proof["authority_hash"],
            source_proof["policy_hash"],
        ],
    ):
        fail(f"{prefix} source observer commitment does not recompute")
    if (
        source_proof["commitment"]
        != hex_bytes(
            message[f"{prefix}_source_observer_commitment"],
            f"{prefix}.source_observer_commitment",
        )
        or source_proof["signature"]
        != hex_bytes(
            message[f"{prefix}_source_observer_signature"],
            f"{prefix}.source_observer_signature",
        )
        or source_proof["hash"]
        != hex_bytes(message[f"{prefix}_source_proof_hash"], f"{prefix}.source_proof_hash")
    ):
        fail(f"{prefix} source expanded evidence differs from proof ABI")

    acknowledgement_proof_abi = hex_bytes(
        message[f"{prefix}_acknowledgement_proof_abi"],
        f"{prefix}.acknowledgement_proof",
    )
    acknowledgement_certificate_abi = hex_bytes(
        message[f"{prefix}_acknowledgement_certificate_abi"],
        f"{prefix}.acknowledgement_certificate",
    )
    acknowledgement_proof = proof_fields(
        acknowledgement_proof_abi, f"{prefix}.acknowledgement_proof"
    )
    acknowledgement_certificate = certificate_fields(
        acknowledgement_certificate_abi, f"{prefix}.acknowledgement_certificate"
    )
    if acknowledgement_certificate["message_id"] != message_id:
        fail(f"{prefix} acknowledgement certificate message ID differs")
    if acknowledgement_certificate["proof_hash"] != acknowledgement_proof["hash"]:
        fail(f"{prefix} acknowledgement certificate proof hash differs")
    if (
        acknowledgement_proof["commitment"]
        != hex_bytes(
            message[f"{prefix}_acknowledgement_observer_commitment"],
            f"{prefix}.acknowledgement_observer_commitment",
        )
        or acknowledgement_proof["signature"]
        != hex_bytes(
            message[f"{prefix}_acknowledgement_observer_signature"],
            f"{prefix}.acknowledgement_observer_signature",
        )
        or acknowledgement_proof["hash"]
        != hex_bytes(
            message[f"{prefix}_acknowledgement_proof_hash"],
            f"{prefix}.acknowledgement_proof_hash",
        )
    ):
        fail(f"{prefix} acknowledgement expanded evidence differs from proof ABI")

    execute_calldata = hex_bytes(
        message[f"{prefix}_execute_calldata"], f"{prefix}.execute_calldata"
    )
    acknowledgement_calldata = hex_bytes(
        message[f"{prefix}_acknowledgement_calldata"],
        f"{prefix}.acknowledgement_calldata",
    )
    result_hash = hex_bytes(
        message[f"{prefix}_destination_result_hash"], f"{prefix}.destination_result_hash"
    )
    check_execute_calldata(
        execute_calldata,
        envelope,
        payload,
        source_proof_abi,
        source_certificate_abi,
        prefix,
    )
    check_ack_calldata(
        acknowledgement_calldata,
        envelope,
        result_hash,
        acknowledgement_proof_abi,
        acknowledgement_certificate_abi,
        prefix,
    )
    source_chain = uint_word(envelope, 3, prefix)
    destination_chain = uint_word(envelope, 6, prefix)
    if execute_calldata not in live_inputs.get(destination_chain, set()):
        fail(f"{prefix} exact execute calldata is absent from destination broadcast")
    if acknowledgement_calldata not in live_inputs.get(source_chain, set()):
        fail(f"{prefix} exact acknowledgement calldata is absent from source broadcast")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("broadcast", type=Path)
    args = parser.parse_args()
    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    broadcast = json.loads(args.broadcast.read_text(encoding="utf-8"))
    live_inputs = broadcast_inputs(broadcast)
    for sequence in range(1, 9):
        check_message(evidence, sequence, live_inputs)
    print(
        "Phase 8 EVM evidence passed: 8 execute/ack calldata pairs are internally "
        "consistent and byte-identical to the broadcast."
    )


if __name__ == "__main__":
    main()
