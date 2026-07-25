from __future__ import annotations

import base64
import importlib.util
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, ClassVar, cast

TOOLS = Path(__file__).resolve().parents[1] / "tools"
PRODUCER_SPEC = importlib.util.spec_from_file_location(
    "build_phase8_anvil_inclusion",
    TOOLS / "build_phase8_anvil_inclusion.py",
)
if PRODUCER_SPEC is None or PRODUCER_SPEC.loader is None:  # pragma: no cover
    raise RuntimeError("cannot load Phase 8 inclusion producer")
producer_module = importlib.util.module_from_spec(PRODUCER_SPEC)
sys.modules[PRODUCER_SPEC.name] = producer_module
PRODUCER_SPEC.loader.exec_module(producer_module)

FLOW_SPEC = importlib.util.spec_from_file_location(
    "run_phase8_authenticated_flow",
    TOOLS / "run_phase8_authenticated_flow.py",
)
if FLOW_SPEC is None or FLOW_SPEC.loader is None:  # pragma: no cover
    raise RuntimeError("cannot load Phase 8 authenticated flow runner")
flow_module = importlib.util.module_from_spec(FLOW_SPEC)
sys.modules[FLOW_SPEC.name] = flow_module
FLOW_SPEC.loader.exec_module(flow_module)
flow = cast(Any, flow_module)


class ProviderHandler(BaseHTTPRequestHandler):
    provider: ClassVar[str]
    requests: ClassVar[list[tuple[str, dict[str, Any]]]]

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers["Content-Length"])
        body = json.loads(self.rfile.read(length))
        self.requests.append((self.path, body))
        if self.path == "/v1/faults/retryable":
            status = 503
            response = {
                "provider": self.provider,
                "authority": "TRANSPORT_ONLY",
                "contains_real_value": False,
                "retryable": True,
            }
        else:
            status = 202
            response = {
                "provider": self.provider,
                "authority": "TRANSPORT_ONLY",
                "contains_real_value": False,
                "delivery_status": "ACCEPTED",
            }
        encoded = json.dumps(response, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        del format, args


def start_provider(
    provider: str,
) -> tuple[ThreadingHTTPServer, threading.Thread, type[ProviderHandler]]:
    handler = type(
        provider.replace("-", "_"),
        (ProviderHandler,),
        {"provider": provider, "requests": []},
    )
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, handler


def exact_fixture() -> tuple[str, dict[str, Any], dict[str, Any], str]:
    message_id = "0x" + "42" * 32
    envelope: dict[str, Any] = {}
    for key, kind in zip(flow.ENVELOPE_KEYS, flow.ENVELOPE_KINDS, strict=True):
        if kind == "uint":
            envelope[key] = 1
        elif kind == "address":
            envelope[key] = "0x" + "22" * 20
        else:
            envelope[key] = "0x" + "11" * 32
    envelope["message_id"] = message_id
    source_proof = {
        "source_block_hash": "0x" + "01" * 32,
        "source_block_number": 2,
        "source_block_timestamp": 3,
        "transaction_hash": "0x" + "04" * 32,
        "transaction_index": 0,
        "receipt_root": "0x" + "05" * 32,
        "receipt_proof_hash": "0x" + "06" * 32,
        "log_index": 1,
        "event_hash": "0x" + "07" * 32,
        "finality_head_hash": "0x" + "08" * 32,
        "finality_head_number": 14,
        "required_depth": 12,
        "header_authority_hash": "0x" + "09" * 32,
        "observer_signed_header_commitment": "0x" + "0a" * 32,
        "observer_signature": "0x" + "0b" * 64,
        "finality_policy_hash": "0x" + "0c" * 32,
    }
    return message_id, envelope, source_proof, flow.proof_hash(source_proof)


def test_observed_failover_posts_exact_transport_identities() -> None:
    server_a, thread_a, handler_a = start_provider("mock-bridge-provider-a")
    server_b, thread_b, handler_b = start_provider("mock-bridge-provider-b")
    message_id, envelope, source_proof, source_proof_hash = exact_fixture()
    try:
        attempts = flow.observed_provider_attempts(
            1,
            f"http://127.0.0.1:{server_a.server_port}",
            f"http://127.0.0.1:{server_b.server_port}",
            message_id,
            envelope,
            source_proof,
            source_proof_hash,
        )
    finally:
        server_a.shutdown()
        server_b.shutdown()
        thread_a.join(timeout=2)
        thread_b.join(timeout=2)
        server_a.server_close()
        server_b.server_close()

    assert [(item["provider_id"], item["status"], item["retryable"]) for item in attempts] == [
        ("mock-bridge-provider-a", "FAILED", True),
        ("mock-bridge-provider-b", "DELIVERED", False),
    ]
    expected_b_receipt = {
        "status_code": 202,
        "body": {
            "provider": "mock-bridge-provider-b",
            "authority": "TRANSPORT_ONLY",
            "contains_real_value": False,
            "delivery_status": "ACCEPTED",
        },
    }
    expected_b_receipt_hash = flow.canonical_hex(
        flow.keccak256(
            json.dumps(
                expected_b_receipt,
                separators=(",", ":"),
                sort_keys=True,
            ).encode()
        )
    )
    assert attempts[1]["transport_receipt_hash"] == expected_b_receipt_hash
    assert handler_a.requests[0][0] == "/v1/faults/retryable"
    assert handler_b.requests[0][0] == "/v1/messages"
    body = handler_b.requests[0][1]
    serialized_envelope = flow.envelope_encoding(envelope)
    serialized_proof = flow.word_uint(32) + flow.proof_tuple_encoding(source_proof)
    assert body["message_id"] == message_id[2:]
    assert base64.b64decode(body["envelope"]) == serialized_envelope
    assert body["envelope_hash"] == flow.keccak256(serialized_envelope).hex()
    assert base64.b64decode(body["source_proof"]) == serialized_proof
    assert body["proof_hash"] == source_proof_hash[2:]
    assert body["payload_hash"] == envelope["payload_hash"][2:]
    assert body["contains_real_value"] is False


def test_provider_endpoint_rejects_non_loopback_url() -> None:
    try:
        flow.provider_endpoint("https://example.com:443", "/v1/messages")
    except SystemExit as error:
        assert "loopback HTTP" in str(error)
    else:  # pragma: no cover - safety boundary
        raise AssertionError("non-loopback provider URL was accepted")
