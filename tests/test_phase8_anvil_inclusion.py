from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any, cast

import pytest

PRODUCER_PATH = Path(__file__).resolve().parents[1] / "tools/build_phase8_anvil_inclusion.py"
SPEC = importlib.util.spec_from_file_location("build_phase8_anvil_inclusion", PRODUCER_PATH)
if SPEC is None or SPEC.loader is None:  # pragma: no cover - repository invariant
    raise RuntimeError("cannot load Phase 8 Anvil inclusion producer")
producer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(producer)


def base_block() -> dict[str, Any]:
    return {
        "parentHash": "0x" + "11" * 32,
        "sha3Uncles": "0x" + "22" * 32,
        "miner": "0x" + "33" * 20,
        "stateRoot": "0x" + "44" * 32,
        "transactionsRoot": "0x" + "55" * 32,
        "receiptsRoot": "0x" + "66" * 32,
        "logsBloom": "0x" + "00" * 256,
        "difficulty": "0x0",
        "number": "0x1",
        "gasLimit": "0x1c9c380",
        "gasUsed": "0x5208",
        "timestamp": "0x2",
        "extraData": "0x",
        "mixHash": "0x" + "77" * 32,
        "nonce": "0x" + "00" * 8,
    }


def expected_header(module: ModuleType, block: dict[str, Any]) -> bytes:
    fields = [
        module.rlp_bytes(bytes.fromhex(block["parentHash"][2:])),
        module.rlp_bytes(bytes.fromhex(block["sha3Uncles"][2:])),
        module.rlp_bytes(bytes.fromhex(block["miner"][2:])),
        module.rlp_bytes(bytes.fromhex(block["stateRoot"][2:])),
        module.rlp_bytes(bytes.fromhex(block["transactionsRoot"][2:])),
        module.rlp_bytes(bytes.fromhex(block["receiptsRoot"][2:])),
        module.rlp_bytes(bytes.fromhex(block["logsBloom"][2:])),
        module.rlp_bytes(b""),
        module.rlp_bytes(b"\x01"),
        module.rlp_bytes(bytes.fromhex("01c9c380")),
        module.rlp_bytes(bytes.fromhex("5208")),
        module.rlp_bytes(b"\x02"),
        module.rlp_bytes(b""),
        module.rlp_bytes(bytes.fromhex(block["mixHash"][2:])),
        module.rlp_bytes(bytes.fromhex(block["nonce"][2:])),
    ]
    for name, kind in (
        ("baseFeePerGas", "quantity"),
        ("withdrawalsRoot", "hex"),
        ("blobGasUsed", "quantity"),
        ("excessBlobGas", "quantity"),
        ("parentBeaconBlockRoot", "hex"),
        ("requestsHash", "hex"),
    ):
        if name not in block:
            break
        value = block[name]
        payload = (
            module.quantity_bytes(value, name) if kind == "quantity" else bytes.fromhex(value[2:])
        )
        fields.append(module.rlp_bytes(payload))
    return cast(bytes, module.rlp_list(fields))


@pytest.mark.parametrize(
    "optional",
    [
        {"baseFeePerGas": "0x7"},
        {
            "baseFeePerGas": "0x7",
            "withdrawalsRoot": "0x" + "88" * 32,
            "blobGasUsed": "0x0",
            "excessBlobGas": "0x0",
            "parentBeaconBlockRoot": "0x" + "99" * 32,
            "requestsHash": "0x" + "aa" * 32,
        },
    ],
)
def test_encode_header_accepts_canonical_trailing_optional_layouts(
    optional: dict[str, Any],
) -> None:
    block = {**base_block(), **optional}
    encoded = expected_header(producer, block)
    block["hash"] = "0x" + producer.keccak256(encoded).hex()
    assert producer.encode_header(block) == encoded


def test_encode_header_rejects_later_field_after_optional_gap() -> None:
    block = {
        **base_block(),
        "baseFeePerGas": "0x7",
        "blobGasUsed": "0x0",
        "hash": "0x" + "00" * 32,
    }
    with pytest.raises(SystemExit, match="present after an earlier fork field is missing"):
        producer.encode_header(block)
