from __future__ import annotations

import sys
from pathlib import Path

from google.protobuf import descriptor_pb2  # type: ignore[import-untyped]

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from check_phase9_schema import (  # noqa: E402
    SchemaError,
    descriptor_set_from_buf,
    validate_descriptor_set,
    validate_sources_and_generated_outputs,
)


def test_phase9_descriptor_and_generated_boundary() -> None:
    descriptor_set = descriptor_set_from_buf()
    validate_descriptor_set(descriptor_set)
    validate_sources_and_generated_outputs()

    refinance = next(item for item in descriptor_set.file if item.name.endswith("/refinance.proto"))
    request = next(item for item in refinance.message_type if item.name == "RefinanceRequest")
    position_manager = next(
        item for item in request.field if item.name == "new_position_manager"
    )
    assert position_manager.number == 24
    assert position_manager.type == descriptor_pb2.FieldDescriptorProto.TYPE_BYTES


def test_phase9_descriptor_check_rejects_wire_tag_mutation() -> None:
    descriptor_set = descriptor_set_from_buf()
    mutated = descriptor_pb2.FileDescriptorSet()
    mutated.CopyFrom(descriptor_set)
    refinance = next(item for item in mutated.file if item.name.endswith("/refinance.proto"))
    payoff_quote = next(item for item in refinance.message_type if item.name == "PayoffQuote")
    net_payoff = next(item for item in payoff_quote.field if item.name == "net_payoff")
    net_payoff.number = 99

    try:
        validate_descriptor_set(mutated)
    except SchemaError as error:
        assert "exact descriptor differs" in str(error)
    else:
        raise AssertionError("mutated PayoffQuote wire tag passed the exact descriptor check")
