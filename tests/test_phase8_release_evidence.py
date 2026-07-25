from __future__ import annotations

import hashlib
import importlib.util
import json
from copy import deepcopy
from pathlib import Path
from typing import Any, cast

import pytest
from Crypto.PublicKey import ECC
from Crypto.Signature import eddsa

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "tools/check_phase8_release_evidence.py"
SPEC = importlib.util.spec_from_file_location("check_phase8_release_evidence", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:  # pragma: no cover - repository invariant
    raise RuntimeError("cannot load Phase 8 release-evidence validator")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)

# Captured from the blocked raw bundle's flow_message_01_abi. The top-level ABI
# head puts the source proof at byte offset 0x4a0 and source certificate at
# 0x700. These decoded values are internally coherent, but disagree with the
# adjacent flattened declarations preserved below.
SOURCE_PROOF_OFFSET = 0x4A0
SOURCE_CERTIFICATE_OFFSET = 0x700
FLATTENED_MESSAGE_ID = "0xbfea4547a48bbe9b37fa0f6e159a5d0993ebe1f0d25b936ee94b744ffb801fc5"
FLATTENED_PROOF_HASH = "0xb85a72450258be2d438c084a71336c2f16d238a75359193b04596fa03e5b8f5a"

PROOF: dict[str, Any] = {
    "source_block_hash": ("0xcba4e0ad8481524828fff2b403b75e18d1dc970f40edf47b3f9ad04220b77095"),
    "source_block_number": 100,
    "source_block_timestamp": 1784976316,
    "transaction_hash": ("0x7412c5933edc14b3bdc7675a9db9da28ff831f53399cc1f6804c7d95bee9405f"),
    "transaction_index": 1,
    "receipt_root": ("0x8137156ff002dfab76a7b2fa7754379a1ce8f5af9953eb1d60311ec0697e5f7c"),
    "receipt_proof_hash": ("0x4fa9373f53c38c62e27af4348c3e59a9cb66a2b4e3b6815436cb3044584ddb42"),
    "log_index": 1,
    "event_hash": ("0xd63b53b4b28920bc43be1e326bda587544173fc125db03b46fb744b752344286"),
    "finality_head_hash": ("0x19db36e86bdc4b096528dd4640cdef3b70ffad88412ff4df4e7002e0024f734d"),
    "finality_head_number": 112,
    "required_depth": 12,
    "header_authority_hash": ("0x73b626a0a72dd4a508466c79109241eef7aa8ac93680519d3bf0b7b1d49ed345"),
    "observer_signed_header_commitment": (
        "0xe4fb3a722c9449452f234708b30b37ec61365b3f87c4f17419820af389b7ad84"
    ),
    "observer_signature": (
        "0xa6beac3c1e92a1e10ea2bca5d2c08272b63faf2c09b2d93fcc507b58db8424e1"
        "9817a19c05ec7cdc4855c2168511dc80c1b4076e28fb104e0ccecebd303c8705"
    ),
    "finality_policy_hash": ("0xf324b04c8dc0791e95e056eb9a3fa8c41a453129da5709b5fa62bbad769ddedb"),
}

CERTIFICATE: dict[str, Any] = {
    "message_id": ("0x5886449b63d616959c24556b6bbd876ad922395651ea8fe24479772063d4301f"),
    "source_proof_hash": ("0xdae8814c79a6ccd10f73ce49fbff996a31a434ec697d34c222cc0bc1d4f2a411"),
    "signer_set_hash": ("0xf5ab8e842e3c1e44aea50c274dd5c730c26bb7987103511e7203086c76cce204"),
    "signer_set_version": 1,
    "signatures": [
        (
            "0x6e3d2efd08c1f37181736aceb20c013ceef61818c66814e8a30dd15f6a8f2fec"
            "7a2b3eebd0037949d262659888f9556d6f82533b5c355768b6acec1d554efbd21b"
        ),
        (
            "0x608d3cdffef076682eaac0b9487ab0dfc9c64e5f1ee87d6c02f19743865b2ba9"
            "39a2054e439f333b52d3cf611958808c5c0ea869c243d7fa2eee928b417274051b"
        ),
    ],
}

EVIDENCE_DOMAIN: dict[str, Any] = {
    "observer_authority_hash": PROOF["header_authority_hash"],
    "observer_public_key_ed25519": (
        "0xe84d4f1b0cf0e0217292b079bb4db43ad1416f4609b111675e720d2b1dbc0eac"
    ),
    "confirmation_depth": 12,
    "signer_set": {
        "hash": CERTIFICATE["signer_set_hash"],
        "version": 1,
        "sorted_addresses": validator.EXPECTED_SIGNERS,
    },
}
VERIFIER_DOMAIN: dict[str, Any] = {
    "chain_id": 31338,
    "contracts": {"finality_verifier": {"address": "0xdc64a140aa3e981100a9beca4e685f962f0cf6c9"}},
}


def check_vector(expected_message_id: str) -> tuple[str, str]:
    return cast(
        tuple[str, str],
        validator.check_proof_certificate(
            PROOF,
            CERTIFICATE,
            label="captured source proof",
            expected_domain=EVIDENCE_DOMAIN,
            verifier_domain=VERIFIER_DOMAIN,
            expected_message_id=expected_message_id,
            expected_event_hash=PROOF["event_hash"],
            expected_policy_hash=PROOF["finality_policy_hash"],
        ),
    )


type RLPInput = bytes | list[RLPInput]


def rlp(value: RLPInput) -> bytes:
    if isinstance(value, list):
        payload = b"".join(rlp(item) for item in value)
        if len(payload) < 56:
            return bytes([0xC0 + len(payload)]) + payload
        length = len(payload).to_bytes((len(payload).bit_length() + 7) // 8, "big")
        return bytes([0xF7 + len(length)]) + length + payload
    if len(value) == 1 and value[0] < 0x80:
        return value
    if len(value) < 56:
        return bytes([0x80 + len(value)]) + value
    length = len(value).to_bytes((len(value).bit_length() + 7) // 8, "big")
    return bytes([0xB7 + len(length)]) + length + value


def scalar(value: int) -> bytes:
    return value.to_bytes((value.bit_length() + 7) // 8, "big")


def leaf(value: bytes) -> bytes:
    # RLP(0) is 0x80, whose MPT nibbles are [8, 0]. The even leaf compact
    # encoding is therefore [2, 0, 8, 0] => 0x2080.
    return rlp([b"\x20\x80", value])


def header(
    parent_hash: bytes,
    transactions_root: bytes,
    receipts_root: bytes,
    number: int,
    timestamp: int,
) -> bytes:
    return rlp(
        [
            parent_hash,
            b"\x11" * 32,
            b"\x22" * 20,
            b"\x33" * 32,
            transactions_root,
            receipts_root,
            b"\x00" * 256,
            b"",
            scalar(number),
            scalar(30_000_000),
            scalar(21_000),
            scalar(timestamp),
        ]
    )


def sign_header(
    private_key: ECC.EccKey,
    chain_id: int,
    header_rlp: bytes,
    observed_nanos: int,
) -> bytes:
    digest = validator.keccak256(
        b"UNIFIED_EVM_HEADER_AUTHORITY_V1\x00"
        + chain_id.to_bytes(8, "big")
        + observed_nanos.to_bytes(8, "big")
        + validator.keccak256(header_rlp)
    )
    return eddsa.new(private_key, "rfc8032").sign(digest)


def actual_inclusion_vector() -> tuple[
    dict[str, Any],
    dict[str, Any],
    str,
    list[str],
    bytes,
    str,
]:
    chain_id = 31337
    address = "0x" + "44" * 20
    topics = ["0x" + byte * 32 for byte in ("55", "66", "77", "88")]
    data = b"\x99" * 64
    transaction_rlp = rlp([b"\x01"])
    receipt_rlp = rlp(
        [
            b"\x01",
            scalar(21_000),
            b"\x00" * 256,
            [[bytes.fromhex(address[2:]), [bytes.fromhex(topic[2:]) for topic in topics], data]],
        ]
    )
    transaction_leaf = leaf(transaction_rlp)
    receipt_leaf = leaf(receipt_rlp)
    transaction_root = validator.keccak256(transaction_leaf)
    receipt_root = validator.keccak256(receipt_leaf)
    source_header = header(b"\xaa" * 32, transaction_root, receipt_root, 100, 1_700_000_000)
    source_hash = validator.keccak256(source_header)
    confirmation_header = header(
        source_hash,
        validator.keccak256(rlp(b"")),
        validator.keccak256(rlp(b"")),
        101,
        1_700_000_001,
    )
    # PyCryptodome accepts a documented 32-byte Ed25519 seed; its stub is narrower.
    key = ECC.construct(curve="Ed25519", seed=b"\x42" * 32)  # type: ignore[arg-type]
    public_key = "0x" + key.public_key().export_key(format="raw").hex()
    source_observed = 1_700_000_000_000_000_000
    confirmation_observed = 1_700_000_001_000_000_000
    inclusion: dict[str, Any] = {
        "header_rlp": "0x" + source_header.hex(),
        "header_observed_at_unix_nanos": str(source_observed),
        "header_signature_ed25519": (
            "0x" + sign_header(key, chain_id, source_header, source_observed).hex()
        ),
        "receipts": [
            {
                "transaction_index": 0,
                "transaction_rlp": "0x" + transaction_rlp.hex(),
                "transaction_proof_nodes": ["0x" + transaction_leaf.hex()],
                "receipt_rlp": "0x" + receipt_rlp.hex(),
                "receipt_proof_nodes": ["0x" + receipt_leaf.hex()],
            }
        ],
        "confirmation_headers": [
            {
                "header_rlp": "0x" + confirmation_header.hex(),
                "header_observed_at_unix_nanos": str(confirmation_observed),
                "header_signature_ed25519": (
                    "0x"
                    + sign_header(
                        key,
                        chain_id,
                        confirmation_header,
                        confirmation_observed,
                    ).hex()
                ),
            }
        ],
    }
    proof = deepcopy(PROOF)
    proof.update(
        {
            "source_block_hash": "0x" + source_hash.hex(),
            "source_block_number": 100,
            "source_block_timestamp": 1_700_000_000,
            "transaction_hash": "0x" + validator.keccak256(transaction_rlp).hex(),
            "transaction_index": 0,
            "receipt_root": "0x" + receipt_root.hex(),
            "receipt_proof_hash": validator.phase7c_inclusion_hash(
                "0x" + source_hash.hex(),
                0,
                transaction_rlp,
                [transaction_leaf],
                receipt_rlp,
                [receipt_leaf],
            ),
            "log_index": 0,
            "finality_head_hash": "0x" + validator.keccak256(confirmation_header).hex(),
            "finality_head_number": 101,
            "required_depth": 1,
        }
    )
    return inclusion, proof, public_key, topics, data, address


def test_captured_abi_proof_and_quorum_are_independently_valid() -> None:
    proof_hash, certificate_hash = check_vector(CERTIFICATE["message_id"])

    assert SOURCE_PROOF_OFFSET == 1184
    assert SOURCE_CERTIFICATE_OFFSET == 1792
    assert proof_hash == CERTIFICATE["source_proof_hash"]
    assert proof_hash != FLATTENED_PROOF_HASH
    assert certificate_hash == (
        "0x98fe574908b4d512722b09024b9c725ddae6b937307b739a8076da796c490deb"
    )


def test_flattened_message_id_mismatch_is_rejected() -> None:
    assert FLATTENED_MESSAGE_ID != CERTIFICATE["message_id"]

    with pytest.raises(
        validator.EvidenceError,
        match="certificate diverges from the exact proof/signer set",
    ):
        check_vector(FLATTENED_MESSAGE_ID)


def test_authenticated_signed_header_and_mpt_inclusion_are_valid() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()

    validator.check_authenticated_inclusion(
        inclusion,
        proof=proof,
        chain_id=31337,
        observer_public_key=public_key,
        expected_address=address,
        expected_topics=topics,
        expected_data=data,
        expected_raw_hash=validator.canonical_object_keccak(inclusion),
        label="actual inclusion",
    )


def test_mutated_receipt_mpt_proof_is_rejected() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    mutated = deepcopy(inclusion)
    receipt = mutated["receipts"][0]
    node = bytearray.fromhex(receipt["receipt_proof_nodes"][0][2:])
    node[-1] ^= 1
    receipt["receipt_proof_nodes"][0] = "0x" + node.hex()

    with pytest.raises(
        validator.EvidenceError,
        match="transaction or receipt MPT inclusion is invalid",
    ):
        validator.check_authenticated_inclusion(
            mutated,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(mutated),
            label="mutated MPT",
        )


def test_mutated_transaction_mpt_proof_is_rejected() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    mutated = deepcopy(inclusion)
    receipt = mutated["receipts"][0]
    node = bytearray.fromhex(receipt["transaction_proof_nodes"][0][2:])
    node[-1] ^= 1
    receipt["transaction_proof_nodes"][0] = "0x" + node.hex()

    with pytest.raises(
        validator.EvidenceError,
        match="transaction or receipt MPT inclusion is invalid",
    ):
        validator.check_authenticated_inclusion(
            mutated,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(mutated),
            label="mutated transaction MPT",
        )


def test_mutated_header_signature_is_rejected() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    mutated = deepcopy(inclusion)
    signature = bytearray.fromhex(mutated["header_signature_ed25519"][2:])
    signature[-1] ^= 1
    mutated["header_signature_ed25519"] = "0x" + signature.hex()

    with pytest.raises(
        validator.EvidenceError,
        match="Phase 7C signed header is invalid",
    ):
        validator.check_authenticated_inclusion(
            mutated,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(mutated),
            label="mutated header signature",
        )


def test_exact_log_topic_is_required() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    wrong_topics = [*topics]
    wrong_topics[-1] = "0x" + "aa" * 32

    with pytest.raises(
        validator.EvidenceError,
        match="authenticated receipt lacks one exact canonical event",
    ):
        validator.check_authenticated_inclusion(
            inclusion,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=wrong_topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(inclusion),
            label="wrong log topic",
        )


def test_exact_log_data_is_required() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()

    with pytest.raises(
        validator.EvidenceError,
        match="authenticated receipt lacks one exact canonical event",
    ):
        validator.check_authenticated_inclusion(
            inclusion,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data[:-1] + b"\xaa",
            expected_raw_hash=validator.canonical_object_keccak(inclusion),
            label="wrong log data",
        )


def test_block_global_log_index_is_required() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    wrong_proof = deepcopy(proof)
    wrong_proof["log_index"] = 1

    with pytest.raises(
        validator.EvidenceError,
        match="authenticated receipt lacks one exact canonical event",
    ):
        validator.check_authenticated_inclusion(
            inclusion,
            proof=wrong_proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(inclusion),
            label="wrong global log index",
        )


def test_noncontiguous_signed_confirmation_header_is_rejected() -> None:
    inclusion, proof, public_key, topics, data, address = actual_inclusion_vector()
    mutated = deepcopy(inclusion)
    wrong_header = header(
        b"\xbb" * 32,
        validator.keccak256(rlp(b"")),
        validator.keccak256(rlp(b"")),
        101,
        1_700_000_001,
    )
    observed = 1_700_000_001_000_000_000
    # PyCryptodome accepts a documented 32-byte Ed25519 seed; its stub is narrower.
    key = ECC.construct(curve="Ed25519", seed=b"\x42" * 32)  # type: ignore[arg-type]
    mutated["confirmation_headers"][0] = {
        "header_rlp": "0x" + wrong_header.hex(),
        "header_observed_at_unix_nanos": str(observed),
        "header_signature_ed25519": ("0x" + sign_header(key, 31337, wrong_header, observed).hex()),
    }

    with pytest.raises(
        validator.EvidenceError,
        match="signed confirmation-header chain is not contiguous",
    ):
        validator.check_authenticated_inclusion(
            mutated,
            proof=proof,
            chain_id=31337,
            observer_public_key=public_key,
            expected_address=address,
            expected_topics=topics,
            expected_data=data,
            expected_raw_hash=validator.canonical_object_keccak(mutated),
            label="noncontiguous finality",
        )


@pytest.mark.parametrize(
    ("input_bytes", "proof_bytes", "message"),
    [
        (validator.MAX_BLOCK_INPUT_BYTES + 1, 0, "aggregate authenticated input"),
        (0, validator.MAX_BLOCK_PROOF_BYTES + 1, "aggregate MPT proof bytes"),
    ],
)
def test_phase7c_aggregate_overflow_is_rejected(
    input_bytes: int,
    proof_bytes: int,
    message: str,
) -> None:
    with pytest.raises(validator.EvidenceError, match=message):
        validator.check_phase7c_aggregate_bounds(
            input_bytes,
            proof_bytes,
            "oversized inclusion",
        )


def test_synthetic_boundary_is_explicitly_not_ready(tmp_path: Path) -> None:
    evidence = tmp_path / "synthetic.json"
    evidence.write_text(
        json.dumps({"proof_boundary": validator.SYNTHETIC_PROOF_BOUNDARY}),
        encoding="utf-8",
    )

    with pytest.raises(validator.EvidenceError, match="NOT READY"):
        validator.check_pre_reset(evidence)


def test_frozen_schema_rejects_unknown_top_level_field() -> None:
    schema = json.loads(validator.SCHEMA_PATH.read_text(encoding="utf-8"))

    with pytest.raises(validator.EvidenceError, match="schema-unknown fields: bogus"):
        validator.validate_schema_node(
            {"bogus": True},
            schema,
            schema,
            "release evidence",
        )


def test_frozen_schema_rejects_missing_top_level_fields() -> None:
    schema = json.loads(validator.SCHEMA_PATH.read_text(encoding="utf-8"))

    with pytest.raises(validator.EvidenceError, match="schema-missing fields"):
        validator.validate_schema_node({}, schema, schema, "release evidence")


def test_schema_node_validates_pattern_properties_and_cardinality() -> None:
    schema: dict[str, Any] = {
        "type": "object",
        "additionalProperties": False,
        "minProperties": 1,
        "maxProperties": 1,
        "patternProperties": {
            r"^item-[0-9]+$": {"type": "integer"},
        },
    }

    validator.validate_schema_node({"item-1": 1}, schema, schema, "pattern map")
    with pytest.raises(validator.EvidenceError, match="schema-unknown fields"):
        validator.validate_schema_node({"other": 1}, schema, schema, "pattern map")
    with pytest.raises(validator.EvidenceError, match="does not have schema type"):
        validator.validate_schema_node(
            {"item-1": "1"},
            schema,
            schema,
            "pattern map",
        )
    with pytest.raises(validator.EvidenceError, match="too many schema properties"):
        validator.validate_schema_node(
            {"item-1": 1, "item-2": 2},
            schema,
            schema,
            "pattern map",
        )


def test_message_purpose_mapping_is_explicit_and_case_strict() -> None:
    expected = {
        "mint": "MINT",
        "report": "REPORT",
        "repayment": "REPAYMENT",
        "alternate_repayment": "ALTERNATE_REPAYMENT",
        "bridge_exit": "BRIDGE_EXIT",
        "disbursement": "DISBURSEMENT",
        "collateral_release": "COLLATERAL_RELEASE",
    }
    assert {
        purpose: validator.registry_purpose_for_message(purpose)
        for purpose in expected
    } == expected
    for invalid in ("MINT", "Collateral_Release", "unknown"):
        with pytest.raises(validator.EvidenceError, match="lowercase vocabulary"):
            validator.registry_purpose_for_message(invalid)


def test_message_action_purpose_vector_is_exact() -> None:
    for index, (action, purpose) in enumerate(
        validator.EXPECTED_MESSAGE_ACTION_PURPOSES
    ):
        validator.check_canonical_message_step(index, purpose, action)

    with pytest.raises(validator.EvidenceError, match="not canonical"):
        validator.check_canonical_message_step(0, "MINT", 1)
    with pytest.raises(validator.EvidenceError, match="not canonical"):
        validator.check_canonical_message_step(0, "mint", 2)
    with pytest.raises(validator.EvidenceError, match="outside the canonical"):
        validator.check_canonical_message_step(8, "report", 10)


def test_postgres_json_hex_preserves_bytea_canonical_text() -> None:
    row = {
        "message_id": r"\x" + "ab" * 32,
        "units": 1,
    }
    encoded = json.dumps(row, sort_keys=True).encode("utf-8").hex()

    decoded = validator.decode_postgres_json_hex(encoded, "bytea row")

    assert decoded == row
    assert validator.canonical_rows_sha256([decoded]) == validator.canonical_rows_sha256(
        [row]
    )
    with pytest.raises(validator.EvidenceError, match="non-JSON evidence"):
        validator.decode_postgres_json_hex("zz", "invalid row")


def test_draft_2020_12_schema_rejects_null_authenticated_inclusion() -> None:
    schema = json.loads(validator.SCHEMA_PATH.read_text(encoding="utf-8"))
    fragment = {
        "$ref": "#/$defs/authenticatedInclusion",
        "$defs": schema["$defs"],
    }
    errors = list(validator.Draft202012Validator(fragment).iter_errors(None))

    assert errors
    assert "is not of type 'object'" in errors[0].message


def test_reverted_receipt_with_logs_is_rejected() -> None:
    reverted_receipt = rlp(
        [
            b"",
            scalar(21_000),
            b"\x00" * 256,
            [
                [
                    b"\x11" * 20,
                    [b"\x22" * 32],
                    b"",
                ]
            ],
        ]
    )

    with pytest.raises(
        validator.EvidenceError,
        match="reverted receipt contains logs",
    ):
        validator.decode_receipt(reverted_receipt, "reverted")


def valid_exposure_policy() -> dict[str, Any]:
    exposure: dict[str, Any] = {
        "policy_version": 1,
        "policy_hash": "0x" + "00" * 32,
        "circulating_supply_reference_units": "1000000000000000000000000",
        "circulating_supply_evidence_hash": "0x" + "11" * 32,
        "route_absolute_cap_units": "1000",
        "chain_absolute_cap_units": "1000",
        "adapter_absolute_cap_units": "1000",
        "aggregate_absolute_cap_units": "1000",
        "route_percentage_ceiling_basis_points": 500,
        "aggregate_percentage_ceiling_basis_points": 1500,
        "activation_delay": 0,
        "active_from": 1_800_000_000,
    }
    exposure["policy_hash"] = validator.canonical_exposure_policy_hash(exposure)
    return exposure


@pytest.mark.parametrize(
    ("field", "substitution"),
    [
        ("circulating_supply_reference_units", "999"),
        ("circulating_supply_evidence_hash", "0x" + "22" * 32),
        ("route_absolute_cap_units", "999"),
        ("chain_absolute_cap_units", "999"),
        ("adapter_absolute_cap_units", "999"),
        ("aggregate_absolute_cap_units", "999"),
    ],
)
def test_exposure_policy_provenance_substitution_changes_exact_hash(
    field: str,
    substitution: Any,
) -> None:
    exposure = valid_exposure_policy()
    declared = exposure["policy_hash"]
    exposure[field] = substitution

    assert validator.canonical_exposure_policy_hash(exposure) != declared


def object_store_vector() -> tuple[list[Any], dict[str, Any]]:
    messages: list[Any] = []
    objects: dict[str, Any] = {}
    for index in range(8):
        message_id = "0x" + f"{index + 1:064x}"
        message: dict[str, Any] = {
            "envelope": {"message_id": message_id},
        }
        for kind in ("source", "acknowledgement"):
            inclusion = {"kind": kind, "sequence": index + 1}
            encoded = validator.canonical_json(inclusion)
            digest = "0x" + validator.keccak256(encoded).hex()
            message[kind] = {
                "authenticated_inclusion": inclusion,
                "raw_evidence_object_hash": digest,
            }
            key = f"phase8/authenticated-inclusion/v1/{message_id[2:]}/{kind}/{digest[2:]}.json"
            objects[key] = {"keccak256": digest, "size_bytes": len(encoded)}
        messages.append(message)
    report = {
        "bucket": "crosschain-evidence",
        "object_count": 16,
        "object_set_sha256": hashlib.sha256(validator.canonical_json(objects)).hexdigest(),
        "rehydrated": True,
        "objects": objects,
    }
    return messages, report


@pytest.mark.parametrize(
    "mutation",
    ["key", "hash", "size", "set_hash", "rehydrated"],
)
def test_object_store_restart_evidence_rejects_substitution(mutation: str) -> None:
    messages, report = object_store_vector()
    mutated = deepcopy(report)
    first_key = next(iter(mutated["objects"]))
    if mutation == "key":
        value = mutated["objects"].pop(first_key)
        mutated["objects"]["phase8/authenticated-inclusion/v1/substituted.json"] = value
    elif mutation == "hash":
        mutated["objects"][first_key]["keccak256"] = "0x" + "ff" * 32
    elif mutation == "size":
        mutated["objects"][first_key]["size_bytes"] += 1
    elif mutation == "set_hash":
        mutated["object_set_sha256"] = "ff" * 32
    else:
        mutated["rehydrated"] = False

    with pytest.raises(validator.EvidenceError):
        validator.check_object_store_evidence(mutated, messages)


def test_frozen_schema_requires_exact_49_table_set() -> None:
    schema = json.loads(validator.SCHEMA_PATH.read_text(encoding="utf-8"))
    table_schema = {
        **schema["$defs"]["durable"]["properties"]["sql"]["properties"]["tables"],
        "$defs": schema["$defs"],
    }
    tables = {
        table: {"row_count": 0, "ordered_sha256": "00" * 32} for table in validator.REQUIRED_TABLES
    }
    assert len(tables) == 49
    assert not list(validator.Draft202012Validator(table_schema).iter_errors(tables))

    missing = deepcopy(tables)
    missing.pop(next(iter(missing)))
    assert list(validator.Draft202012Validator(table_schema).iter_errors(missing))

    unknown = deepcopy(tables)
    unknown.pop(next(iter(unknown)))
    unknown["crosschain.fabricated"] = {"row_count": 0, "ordered_sha256": "00" * 32}
    assert list(validator.Draft202012Validator(table_schema).iter_errors(unknown))


def valid_provider_attempts() -> list[dict[str, Any]]:
    common = {
        "message_id": "0x" + "11" * 32,
        "payload_hash": "0x" + "22" * 32,
        "source_proof_hash": "0x" + "33" * 32,
    }
    return [
        {
            **common,
            "provider_id": "mock-bridge-provider-a",
            "attempt_number": 1,
            "status": "FAILED",
            "retryable": True,
            "transport_receipt_hash": "0x" + "44" * 32,
        },
        {
            **common,
            "provider_id": "mock-bridge-provider-b",
            "attempt_number": 2,
            "status": "DELIVERED",
            "retryable": False,
            "transport_receipt_hash": "0x" + "55" * 32,
        },
    ]


@pytest.mark.parametrize(
    "mutation",
    ["authority", "status", "retryability", "order", "payload", "proof"],
)
def test_provider_attempt_path_rejects_authority_and_identity_substitution(
    mutation: str,
) -> None:
    attempts = valid_provider_attempts()
    if mutation == "authority":
        attempts[0]["authority"] = "FINALITY"
    elif mutation == "status":
        attempts[0]["status"] = "DELIVERED"
    elif mutation == "retryability":
        attempts[0]["retryable"] = False
    elif mutation == "order":
        attempts.reverse()
    elif mutation == "payload":
        attempts[0]["payload_hash"] = "0x" + "66" * 32
    else:
        attempts[0]["source_proof_hash"] = "0x" + "77" * 32

    with pytest.raises(validator.EvidenceError):
        validator.check_provider_attempt_path(
            attempts,
            sequence_number=1,
            message_id="0x" + "11" * 32,
            payload_hash="0x" + "22" * 32,
            source_proof_hash="0x" + "33" * 32,
        )


def test_assembler_uses_blueprint_not_legacy_raw_authority() -> None:
    assembler = (
        Path(__file__).resolve().parents[1] / "tools/assemble_phase8_release_evidence.py"
    ).read_text(encoding="utf-8")

    assert "phase8-evm-evidence.json" not in assembler
    assert "RAW_EVM_EVIDENCE" not in assembler
    assert "--raw" not in assembler
    assert "LIVE_BLUEPRINT" in assembler
    compile(assembler, "assemble_phase8_release_evidence.py", "exec")
