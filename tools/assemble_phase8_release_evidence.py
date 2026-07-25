#!/usr/bin/env python3
"""Assemble authenticated Phase 8 deployment and flow evidence.

The deploy-only live blueprint and authenticated flow are diagnostics. This
program is the only bridge from those diagnostics to the sole authoritative manifest:
protocol/deployments/local/phase8-release-evidence.json. It fails closed until
all eight authenticated messages and all three replay receipts are present and
writes an intermediate manifest with ``durable: null`` for the Go worker.
"""

from __future__ import annotations

import argparse
import copy
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, cast

from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[1]
LIVE_BLUEPRINT = ROOT / "protocol/deployments/local/phase8-live-blueprint.json"
AUTHENTICATED_FLOW = ROOT / ".cache/phase8-release/phase8-authenticated-flow.json"
OUTPUT = ROOT / "protocol/deployments/local/phase8-release-evidence.json"
PROOF_BOUNDARY = "AUTHENTICATED_SIGNED_HEADER_TX_RECEIPT_MPT"

ROUTE_NAMES = (
    ("MINT", "mint"),
    ("REPORT", "report"),
    ("REPAYMENT", "repayment"),
    ("ALTERNATE_REPAYMENT", "alternate_repayment"),
    ("BRIDGE_EXIT", "bridge_exit"),
    ("DISBURSEMENT", "disbursement"),
    ("COLLATERAL_RELEASE", "collateral_release"),
)
EXPECTED_ACTIONS = (1, 5, 2, 6, 7, 8, 9, 10)
EXPECTED_SIGNERS = (
    "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf",
    "0x6813eb9362372eef6200f3b1dbc3f819671cba69",
    "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
)
OBSERVER_PUBLIC_KEYS = {
    "home": "0xe84d4f1b0cf0e0217292b079bb4db43ad1416f4609b111675e720d2b1dbc0eac",
    "satellite": "0xb442c9cb0eb1bce60df619505451f95701b64e32b269bda231d95a7475f5a6ac",
}

ABI_PATHS = {
    "role_manager": "protocol/abi/phase2/RoleManager.abi.json",
    "chain_registry": "protocol/abi/phase8/ChainRegistry.abi.json",
    "emergency_controller": "protocol/abi/phase2/EmergencyController.abi.json",
    "route_registry": "protocol/abi/phase8/RouteRegistry.abi.json",
    "finality_verifier": "protocol/abi/phase8/SyntheticFinalityVerifier.abi.json",
    "coordinator": "protocol/abi/phase8/CrossChainCoordinator.abi.json",
    "recovery_controller": "protocol/abi/phase8/CrossChainRecoveryController.abi.json",
    "canonical_uft": "protocol/abi/phase8/Phase8LocalSyntheticToken.abi.json",
    "loan_registry": "protocol/abi/phase2/LoanRegistry.abi.json",
    "bridge_exposure_policy": "protocol/abi/phase8/BridgeExposurePolicy.abi.json",
    "bridge_hub": "protocol/abi/phase8/UFTBridgeHub.abi.json",
    "loan_account_deployer": "protocol/abi/phase8/CrossChainLoanAccountDeployer.abi.json",
    "loan_factory": "protocol/abi/phase8/CrossChainLoanFactory.abi.json",
    "loan_policy": "protocol/abi/phase8/CrossChainLoanPolicy.abi.json",
    "loan_account": "protocol/abi/phase8/CrossChainLoanAccount.abi.json",
    "collateral_token": "protocol/abi/phase8/Phase8LocalSyntheticToken.abi.json",
    "wrapped_uft": "protocol/abi/phase8/WrappedUFT.abi.json",
    "satellite_loan_component": "protocol/abi/phase8/SatelliteLoanComponent.abi.json",
    "satellite_collateral_vault": "protocol/abi/phase8/SatelliteCollateralVault.abi.json",
    "satellite_settlement_vault": "protocol/abi/phase8/SatelliteSettlementVault.abi.json",
}

BLUEPRINT_CONTRACT_KEYS = {
    "home": {
        "role_manager": "home_role_manager",
        "chain_registry": "home_chain_registry",
        "emergency_controller": "home_emergency_controller",
        "route_registry": "home_route_registry",
        "finality_verifier": "home_finality_verifier",
        "coordinator": "home_coordinator",
        "recovery_controller": "home_recovery_controller",
        "canonical_uft": "canonical_token",
        "loan_registry": "loan_registry",
        "bridge_exposure_policy": "bridge_exposure_policy",
        "bridge_hub": "bridge_hub",
        "loan_account_deployer": "loan_account_deployer",
        "loan_factory": "loan_factory",
        "loan_policy": "loan_policy",
        "loan_account": "loan_account",
    },
    "satellite": {
        "role_manager": "satellite_role_manager",
        "chain_registry": "satellite_chain_registry",
        "emergency_controller": "satellite_emergency_controller",
        "route_registry": "satellite_route_registry",
        "finality_verifier": "satellite_finality_verifier",
        "coordinator": "satellite_coordinator",
        "recovery_controller": "satellite_recovery_controller",
        "collateral_token": "collateral_token",
        "wrapped_uft": "wrapped_uft",
        "satellite_loan_component": "satellite_loan_component",
        "satellite_collateral_vault": "satellite_collateral_vault",
        "satellite_settlement_vault": "satellite_settlement_vault",
    },
}


class AssemblyError(RuntimeError):
    """The raw evidence is incomplete or inconsistent."""


class RPC:
    def __init__(self, url: str) -> None:
        self.url = url
        self.request_id = 0

    def call(self, method: str, params: list[Any]) -> Any:
        self.request_id += 1
        payload = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": self.request_id,
                "method": method,
                "params": params,
            },
            separators=(",", ":"),
        ).encode()
        request = urllib.request.Request(  # noqa: S310
            self.url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310
                decoded = json.loads(response.read())
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            raise AssemblyError(f"{method} failed at {self.url}: {error}") from error
        if not isinstance(decoded, dict) or decoded.get("error") is not None:
            raise AssemblyError(f"{method} returned an RPC error at {self.url}")
        return decoded.get("result")

    def eth_call(self, contract: str, signature: str, arguments: bytes = b"") -> bytes:
        data = keccak256(signature.encode())[:4] + arguments
        result = self.call(
            "eth_call",
            [{"to": contract, "data": "0x" + data.hex()}, "latest"],
        )
        if not isinstance(result, str) or not result.startswith("0x"):
            raise AssemblyError(f"eth_call {signature} returned invalid data")
        try:
            return bytes.fromhex(result[2:])
        except ValueError as error:
            raise AssemblyError(f"eth_call {signature} returned invalid hex") from error


def mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise AssemblyError(f"{label} must be an object")
    return cast("dict[str, Any]", value)


def sequence(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise AssemblyError(f"{label} must be an array")
    return value


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode()


def sha256_file(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise AssemblyError(f"ABI snapshot is missing: {relative}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keccak256(value: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(value)
    return digest.digest()


def hex32(value: bytes) -> str:
    if len(value) != 32:
        raise AssemblyError("expected one 32-byte value")
    return "0x" + value.hex()


def word_uint(value: int) -> bytes:
    if value < 0 or value >= 1 << 256:
        raise AssemblyError("ABI integer is outside uint256")
    return value.to_bytes(32, "big")


def word_hex(value: Any, label: str, size: int) -> bytes:
    normalized = lower_hex(value, label, size)
    return bytes.fromhex(normalized[2:]).rjust(32, b"\x00")


def solidity_hash(domain: str, abi_words: list[bytes]) -> str:
    offset = word_uint((len(abi_words) + 1) * 32)
    encoded = offset + b"".join(abi_words) + word_uint(len(domain)) + domain.encode()
    encoded += bytes((-len(encoded)) % 32)
    return hex32(keccak256(encoded))


def split_words(value: bytes, count: int, label: str) -> list[bytes]:
    if len(value) != count * 32:
        raise AssemblyError(f"{label} must contain exactly {count} ABI words")
    return [value[offset : offset + 32] for offset in range(0, len(value), 32)]


def words(value: Any, count: int, label: str) -> list[bytes]:
    if not isinstance(value, str) or not value.startswith("0x"):
        raise AssemblyError(f"{label} is not hex ABI")
    try:
        raw = bytes.fromhex(value[2:])
    except ValueError as error:
        raise AssemblyError(f"{label} is not hex ABI") from error
    if len(raw) != count * 32:
        raise AssemblyError(f"{label} must contain exactly {count} ABI words")
    return [raw[offset : offset + 32] for offset in range(0, len(raw), 32)]


def address(word: bytes) -> str:
    if word[:12] != bytes(12):
        raise AssemblyError("ABI address is not canonically padded")
    return "0x" + word[12:].hex()


def number(word: bytes) -> int:
    return int.from_bytes(word, "big")


def lower_hex(value: Any, label: str, size: int) -> str:
    if not isinstance(value, str) or not value.startswith("0x"):
        raise AssemblyError(f"{label} is not hex")
    try:
        raw = bytes.fromhex(value[2:])
    except ValueError as error:
        raise AssemblyError(f"{label} is not hex") from error
    if len(raw) != size:
        raise AssemblyError(f"{label} has the wrong size")
    return "0x" + raw.hex()


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        return mapping(json.loads(path.read_text(encoding="utf-8")), label)
    except (OSError, json.JSONDecodeError) as error:
        raise AssemblyError(f"cannot read {label}: {error}") from error


def scan_receipts(rpc: RPC) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    latest_raw = rpc.call("eth_blockNumber", [])
    if not isinstance(latest_raw, str):
        raise AssemblyError("RPC block number is unavailable")
    deployments: dict[str, dict[str, Any]] = {}
    receipts: list[dict[str, Any]] = []
    for block_number in range(1, int(latest_raw, 16) + 1):
        block = mapping(
            rpc.call("eth_getBlockByNumber", [hex(block_number), True]),
            f"block {block_number}",
        )
        for transaction_raw in sequence(block.get("transactions"), "block transactions"):
            transaction = mapping(transaction_raw, "transaction")
            transaction_hash = transaction.get("hash")
            if not isinstance(transaction_hash, str):
                raise AssemblyError("transaction lacks a hash")
            receipt = mapping(
                rpc.call("eth_getTransactionReceipt", [transaction_hash]),
                "transaction receipt",
            )
            receipts.append(receipt)
            created = receipt.get("contractAddress")
            if isinstance(created, str):
                deployments[created.lower()] = receipt
    return deployments, receipts


def receipt_identity(receipt: dict[str, Any]) -> tuple[str, int]:
    transaction_hash = lower_hex(receipt.get("transactionHash"), "receipt tx", 32)
    block_raw = receipt.get("blockNumber")
    if not isinstance(block_raw, str):
        raise AssemblyError("receipt block number is missing")
    return transaction_hash, int(block_raw, 16)


def find_log_receipt(
    receipts: list[dict[str, Any]],
    emitter: str,
    topic0: str,
    topic1: str,
) -> dict[str, Any]:
    matches = []
    for receipt in receipts:
        for raw_log in sequence(receipt.get("logs", []), "receipt logs"):
            log = mapping(raw_log, "receipt log")
            topics = sequence(log.get("topics", []), "log topics")
            if (
                str(log.get("address", "")).lower() == emitter
                and len(topics) > 1
                and str(topics[0]).lower() == topic0
                and str(topics[1]).lower() == topic1
            ):
                matches.append(receipt)
    if len(matches) != 1:
        raise AssemblyError(
            f"expected one receipt for emitter {emitter}, topic {topic0}, id {topic1}"
        )
    return matches[0]


def decode_live_route(
    blueprint: dict[str, Any],
    purpose: str,
    suffix: str,
    rpc: RPC,
    registry: str,
) -> dict[str, Any]:
    route_hash = lower_hex(
        blueprint[f"{suffix}_route_hash"],
        f"{purpose} route hash",
        32,
    )
    live = split_words(
        rpc.eth_call(
            registry,
            "route(bytes32)",
            bytes.fromhex(route_hash[2:]),
        ),
        27,
        f"{purpose} live route",
    )
    if hex32(live[0]) != route_hash or any(number(word) != 0 for word in live[24:26]):
        raise AssemblyError(f"{purpose} route is not the exact active live route")
    if number(live[26]) != 1:
        raise AssemblyError(f"{purpose} route version is not active")
    decoded = live[1:24]
    source_chain_id = number(decoded[2])
    destination_chain_id = number(decoded[6])
    domains = {31337: "home", 31338: "satellite"}
    if source_chain_id not in domains or destination_chain_id not in domains:
        raise AssemblyError(f"{purpose} route is not local")
    return {
        "purpose": purpose,
        "version": number(decoded[0]),
        "route_policy_hash": route_hash,
        "source_domain": domains[source_chain_id],
        "destination_domain": domains[destination_chain_id],
        "source_chain_version": number(decoded[0]),
        "destination_chain_version": number(decoded[1]),
        "source_chain_id": source_chain_id,
        "source_coordinator": address(decoded[3]),
        "source_component": address(decoded[4]),
        "source_component_code_hash": hex32(decoded[5]),
        "destination_chain_id": destination_chain_id,
        "destination_coordinator": address(decoded[7]),
        "destination_component": address(decoded[8]),
        "destination_component_code_hash": hex32(decoded[9]),
        "action_family": hex32(decoded[10]),
        "allowed_actions_bitmap": number(decoded[11]),
        "adapter_id": hex32(decoded[12]),
        "adapter_code_hash": hex32(decoded[13]),
        "adapter_set_policy_hash": hex32(decoded[14]),
        "source_finality_policy_hash": hex32(decoded[15]),
        "destination_finality_policy_hash": hex32(decoded[16]),
        "source_signer_set_hash": hex32(decoded[17]),
        "destination_signer_set_hash": hex32(decoded[18]),
        "absolute_cap_units": str(number(decoded[19])),
        "chain_cap_units": str(number(decoded[20])),
        "adapter_cap_units": str(number(decoded[21])),
        "activated_at": number(decoded[22]),
    }


def decode_live_policy(
    rpc: RPC,
    verifier: str,
    route: dict[str, Any],
    purpose: str,
    destination: bool,
) -> dict[str, Any]:
    kind = "destination" if destination else "source"
    expected_hash = route[
        "destination_finality_policy_hash" if destination else "source_finality_policy_hash"
    ]
    decoded = split_words(
        rpc.eth_call(
            verifier,
            "finalityPolicy(bytes32)",
            bytes.fromhex(expected_hash[2:]),
        ),
        15,
        f"{purpose} {kind} live finality policy",
    )
    return {
        "route_purpose": purpose,
        "policy_hash": expected_hash,
        "destination_evidence": number(decoded[0]) == 1,
        "source_chain_id": number(decoded[1]),
        "source_coordinator": address(decoded[2]),
        "source_component": address(decoded[3]),
        "destination_chain_id": number(decoded[4]),
        "destination_coordinator": address(decoded[5]),
        "destination_component": address(decoded[6]),
        "evidence_chain_version": number(decoded[7]),
        "evidence_chain_configuration_hash": hex32(decoded[8]),
        "action_family": hex32(decoded[9]),
        "allowed_actions_bitmap": number(decoded[10]),
        "required_depth": number(decoded[11]),
        "observer_authority_hash": hex32(decoded[12]),
        "signer_set_hash": hex32(decoded[13]),
        "signer_set_version": number(decoded[14]),
    }


def domain_contracts(
    domain_name: str,
    blueprint: dict[str, Any],
    authenticated: dict[str, Any],
    rpc: RPC,
    deployments: dict[str, dict[str, Any]],
    receipts: list[dict[str, Any]],
    loan_id: str,
) -> dict[str, Any]:
    contracts: dict[str, Any] = {}
    for contract_name, blueprint_key in BLUEPRINT_CONTRACT_KEYS[domain_name].items():
        configured_value: Any = blueprint.get(blueprint_key)
        if contract_name == "loan_account":
            configured_value = authenticated.get("loan_account")
        configured_address = lower_hex(
            configured_value,
            f"{domain_name}.{contract_name}.address",
            20,
        )
        code = rpc.call("eth_getCode", [configured_address, "latest"])
        if not isinstance(code, str) or not code.startswith("0x"):
            raise AssemblyError(f"{domain_name}.{contract_name} live code is unavailable")
        try:
            code_bytes = bytes.fromhex(code[2:])
        except ValueError as error:
            raise AssemblyError(f"{domain_name}.{contract_name} live code is invalid") from error
        if not code_bytes:
            raise AssemblyError(f"{domain_name}.{contract_name} has no live code")
        runtime_hash = hex32(keccak256(code_bytes))
        abi_path = ABI_PATHS[contract_name]
        record: dict[str, Any] = {
            "address": configured_address,
            "runtime_code_hash": runtime_hash,
            "abi_path": abi_path,
            "abi_sha256": sha256_file(abi_path),
        }
        if contract_name != "loan_account":
            receipt = deployments.get(configured_address)
            if receipt is None:
                raise AssemblyError(
                    f"{domain_name}.{contract_name} has no CREATE deployment receipt"
                )
            transaction_hash, block_number = receipt_identity(receipt)
            record.update(
                {
                    "deployment_kind": "CREATE_TRANSACTION",
                    "deployment_tx_hash": transaction_hash,
                    "deployment_block_number": block_number,
                }
            )
        else:
            factory = lower_hex(
                blueprint["loan_factory"],
                "loan factory",
                20,
            )
            signature = "CrossChainLoanCreated(bytes32,address,address,address,bytes32)"
            topic0 = hex32(keccak256(signature.encode()))
            receipt = find_log_receipt(receipts, factory, topic0, loan_id)
            transaction_hash, block_number = receipt_identity(receipt)
            record.update(
                {
                    "deployment_kind": "INTERNAL_CREATE2",
                    "deployment_tx_hash": transaction_hash,
                    "deployment_block_number": block_number,
                    "creation_event": {
                        "emitter": factory,
                        "signature": signature,
                        "topic0": topic0,
                        "indexed_id": loan_id,
                        "indexed_id_topic_position": 1,
                        "indexed_address_topic_position": 2,
                    },
                }
            )
        contracts[contract_name] = record
    return contracts


def signer_set(
    blueprint: dict[str, Any],
    domain_name: str,
    rpc: RPC,
    verifier: str,
) -> dict[str, Any]:
    signer_hash = lower_hex(
        blueprint[f"{domain_name}_signer_set_hash"],
        f"{domain_name} signer set hash",
        32,
    )
    decoded = split_words(
        rpc.eth_call(
            verifier,
            "signerSetRecord(bytes32)",
            bytes.fromhex(signer_hash[2:]),
        ),
        9,
        f"{domain_name} live signer set",
    )
    signers = [address(decoded[index]) for index in range(3, 6)]
    observer_key = bytes.fromhex(OBSERVER_PUBLIC_KEYS[domain_name][2:])
    if (
        signers != list(EXPECTED_SIGNERS)
        or number(decoded[8]) != 1
        or hex32(decoded[0]) != signer_hash
        or decoded[1] != keccak256(observer_key)
    ):
        raise AssemblyError(f"{domain_name} signer set is not the frozen active two-of-three set")
    return {
        "version": number(decoded[2]),
        "hash": signer_hash,
        "threshold": 2,
        "valid_from": number(decoded[6]),
        "valid_until": number(decoded[7]),
        "sorted_addresses": signers,
    }


def block_identity(rpc: RPC, block_number: int) -> tuple[str, int]:
    block = mapping(
        rpc.call("eth_getBlockByNumber", [hex(block_number), False]),
        f"block {block_number}",
    )
    block_hash = lower_hex(block.get("hash"), "block hash", 32)
    timestamp_raw = block.get("timestamp")
    if not isinstance(timestamp_raw, str):
        raise AssemblyError("block timestamp is missing")
    return block_hash, int(timestamp_raw, 16)


def docker_count(resource: str) -> int:
    command = [
        "docker",
        resource,
        "ls",
        "--quiet",
        "--filter",
        "label=com.unified.environment=local",
    ]
    if resource == "container":
        command = [
            "docker",
            "ps",
            "--all",
            "--quiet",
            "--filter",
            "label=com.unified.environment=local",
        ]
    completed = subprocess.run(  # noqa: S603,S607
        command,
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise AssemblyError(f"cannot count labeled Docker {resource} resources")
    return len([line for line in completed.stdout.splitlines() if line.strip()])


def git_head() -> str:
    executable = shutil.which("git")
    if executable is None:
        raise AssemblyError("git executable is unavailable")
    completed = subprocess.run(  # noqa: S603
        [executable, "rev-parse", "HEAD"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    value = completed.stdout.strip().lower()
    if completed.returncode != 0 or len(value) != 40:
        raise AssemblyError("cannot resolve the source Git commit")
    return value


def build_replays(flow_input: dict[str, Any]) -> list[dict[str, Any]]:
    replays = sequence(flow_input.get("replays"), "authenticated flow replays")
    if len(replays) < 3:
        raise AssemblyError("authenticated flow lacks the three required replay receipts")
    clean: list[dict[str, Any]] = []
    expected = {
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
    }
    for index, raw in enumerate(replays):
        replay = mapping(raw, f"replay {index}")
        if set(replay) != expected:
            raise AssemblyError(f"replay {index} does not use the frozen schema")
        clean.append(copy.deepcopy(replay))
    return clean


def build_flow(
    blueprint: dict[str, Any],
    authenticated: dict[str, Any],
    contracts: dict[str, dict[str, Any]],
    routes: list[dict[str, Any]],
    rpcs: dict[str, RPC],
) -> dict[str, Any]:
    if (
        authenticated.get("proof_boundary") != PROOF_BOUNDARY
        or authenticated.get("completed_message_count") != 8
        or authenticated.get("requested_message_count") != 8
    ):
        raise AssemblyError("authenticated flow is incomplete or uses the wrong proof boundary")
    messages_raw = sequence(authenticated.get("messages"), "authenticated messages")
    if len(messages_raw) != 8:
        raise AssemblyError("authenticated flow must contain exactly eight messages")
    messages: list[dict[str, Any]] = []
    for index, raw_message in enumerate(messages_raw):
        message = copy.deepcopy(mapping(raw_message, f"message {index + 1}"))
        message.pop("execute_calldata", None)
        message.pop("acknowledgement_calldata", None)
        envelope = mapping(message.get("envelope"), f"message {index + 1}.envelope")
        if (
            message.get("sequence") != index + 1
            or envelope.get("action_ordinal") != EXPECTED_ACTIONS[index]
        ):
            raise AssemblyError(f"message {index + 1} action sequence is not frozen")
        attempts = sequence(
            message.get("provider_attempts"),
            f"message {index + 1}.provider_attempts",
        )
        expected_path = (
            [
                ("mock-bridge-provider-a", 1, "FAILED", True),
                ("mock-bridge-provider-b", 2, "DELIVERED", False),
            ]
            if index == 0
            else [("mock-bridge-provider-a", 1, "DELIVERED", False)]
        )
        actual_path: list[tuple[Any, Any, Any, Any]] = []
        for attempt_index, raw_attempt in enumerate(attempts):
            attempt = mapping(
                raw_attempt,
                f"message {index + 1}.provider_attempts[{attempt_index}]",
            )
            if set(attempt) != {
                "provider_id",
                "attempt_number",
                "status",
                "retryable",
                "message_id",
                "payload_hash",
                "source_proof_hash",
                "transport_receipt_hash",
            }:
                raise AssemblyError("provider attempt contains an authority or fabrication field")
            lower_hex(
                attempt["transport_receipt_hash"],
                "transport receipt hash",
                32,
            )
            actual_path.append(
                (
                    attempt["provider_id"],
                    attempt["attempt_number"],
                    attempt["status"],
                    attempt["retryable"],
                )
            )
        if actual_path != expected_path:
            raise AssemblyError("provider attempt path differs from observed local transport")
        messages.append(message)
    loan_id = lower_hex(blueprint["loan_id"], "loan ID", 32)
    loan_account = contracts["home"]["loan_account"]["address"]
    principal = str(blueprint["principal_units"])
    collateral = str(blueprint["collateral_units"])

    def live_uint(
        rpc: RPC,
        contract: str,
        signature: str,
        arguments: bytes = b"",
    ) -> int:
        result = rpc.eth_call(contract, signature, arguments)
        if len(result) != 32:
            raise AssemblyError(f"live state call {signature} returned invalid data")
        return int.from_bytes(result, "big")

    home = rpcs["home"]
    satellite = rpcs["satellite"]
    hub = contracts["home"]["bridge_hub"]["address"]
    wrapped = contracts["satellite"]["wrapped_uft"]["address"]
    settlement_vault = contracts["satellite"]["satellite_settlement_vault"]["address"]
    collateral_token = contracts["satellite"]["collateral_token"]["address"]
    collateral_vault = contracts["satellite"]["satellite_collateral_vault"]["address"]
    loan_word = bytes.fromhex(loan_id[2:])
    mint_route = next(route for route in routes if route["purpose"] == "MINT")
    loan_state = live_uint(home, loan_account, "state()")
    collateral_released = live_uint(home, loan_account, "collateralReleased()")
    if loan_state != 4 or collateral_released != 1:
        raise AssemblyError("live authenticated flow did not close and release collateral")
    live_final_state = {
        "loan_state": "CLOSED",
        "outstanding_principal_units": str(live_uint(home, loan_account, "outstandingPrincipal()")),
        "bridge_backing_units": str(live_uint(home, hub, "totalBridgeBacking()")),
        "loan_backing_units": str(live_uint(home, hub, "loanBacking(bytes32)", loan_word)),
        "wrapped_supply_units": str(live_uint(satellite, wrapped, "totalSupply()")),
        "route_exposure_units": str(
            live_uint(
                home,
                hub,
                "routeBacking(bytes32)",
                bytes.fromhex(str(mint_route["route_policy_hash"])[2:]),
            )
        ),
        "aggregate_exposure_units": str(live_uint(home, hub, "totalBridgeBacking()")),
        "settlement_vault_units": str(
            live_uint(
                satellite,
                wrapped,
                "balanceOf(address)",
                word_hex(settlement_vault, "settlement vault", 20),
            )
        ),
        "collateral_vault_units": str(
            live_uint(
                satellite,
                collateral_token,
                "balanceOf(address)",
                word_hex(collateral_vault, "collateral vault", 20),
            )
        ),
        "collateral_released": True,
    }
    observed_final_state = mapping(
        authenticated.get("final_state"),
        "authenticated final_state",
    )
    required_final_fields = {
        *live_final_state,
        "borrower_received_principal_units",
        "lender_received_repayment_units",
        "duplicate_economic_effects",
    }
    if set(observed_final_state) != required_final_fields:
        raise AssemblyError("authenticated final_state does not use the frozen schema")
    for field, live_value in live_final_state.items():
        if observed_final_state[field] != live_value:
            raise AssemblyError(f"authenticated final_state.{field} differs from live RPC state")
    if (
        observed_final_state["borrower_received_principal_units"] != principal
        or observed_final_state["lender_received_repayment_units"] != principal
        or observed_final_state["duplicate_economic_effects"] != "0"
    ):
        raise AssemblyError("authenticated balance deltas do not prove the exact full flow")
    final_state = copy.deepcopy(observed_final_state)
    return {
        "loan_id": loan_id,
        "loan_account": {
            "domain": "home",
            "chain_id": 31337,
            "address": loan_account,
        },
        "funding_lock_id": lower_hex(
            blueprint["funding_lock_id"],
            "funding lock ID",
            32,
        ),
        "collateral_id": lower_hex(blueprint["collateral_id"], "collateral ID", 32),
        "principal_units": principal,
        "collateral_units": collateral,
        "canonical_asset": {
            "domain": "home",
            "chain_id": 31337,
            "address": contracts["home"]["canonical_uft"]["address"],
        },
        "wrapped_asset": {
            "domain": "satellite",
            "chain_id": 31338,
            "address": contracts["satellite"]["wrapped_uft"]["address"],
        },
        "collateral_asset": {
            "domain": "satellite",
            "chain_id": 31338,
            "address": contracts["satellite"]["collateral_token"]["address"],
        },
        "messages": messages,
        "replays": build_replays(authenticated),
        "final_state": final_state,
    }


def build_domain(
    domain_name: str,
    chain_id: int,
    rpc_url: str,
    rpc: RPC,
    receipts: list[dict[str, Any]],
    contracts: dict[str, Any],
    blueprint: dict[str, Any],
    policies: list[dict[str, Any]],
) -> dict[str, Any]:
    registry = contracts["chain_registry"]["address"]
    live_chain = split_words(
        rpc.eth_call(
            registry,
            "chainVersion(uint256,uint32)",
            word_uint(chain_id) + word_uint(1),
        ),
        10,
        f"{domain_name} live chain version",
    )
    if (
        number(live_chain[0]) != chain_id
        or number(live_chain[1]) != 1
        or address(live_chain[2]) != contracts["coordinator"]["address"]
        or address(live_chain[3]) != contracts["finality_verifier"]["address"]
        or hex32(live_chain[4]) != contracts["coordinator"]["runtime_code_hash"]
        or hex32(live_chain[5]) != contracts["finality_verifier"]["runtime_code_hash"]
        or number(live_chain[8]) != 0
        or number(live_chain[9]) != 1
    ):
        raise AssemblyError(f"{domain_name} live chain registration is inconsistent")
    registered_topic = hex32(
        keccak256(
            b"ChainVersionRegistered(uint256,uint32,address,address,bytes32,bytes32,bytes32,uint64)"
        )
    )
    registration = find_log_receipt(
        receipts,
        registry,
        registered_topic,
        "0x" + word_uint(chain_id).hex(),
    )
    _, registration_block = receipt_identity(registration)
    genesis_hash, _ = block_identity(rpc, 0)
    observer_public_key = OBSERVER_PUBLIC_KEYS[domain_name]
    observer_authority = hex32(keccak256(bytes.fromhex(observer_public_key[2:])))
    configuration_hash = hex32(live_chain[6])
    activation_candidates = [
        candidate
        for candidate in range(registration_block + 1)
        if solidity_hash(
            "UNIFIED_LOCAL_CHAIN_CONFIGURATION_V1",
            [
                word_uint(chain_id),
                word_uint(1),
                word_hex(contracts["coordinator"]["address"], "coordinator", 20),
                word_hex(
                    contracts["finality_verifier"]["address"],
                    "finality verifier",
                    20,
                ),
                word_hex(observer_authority, "observer authority", 32),
                word_uint(candidate),
            ],
        )
        == configuration_hash
    ]
    if len(activation_candidates) != 1:
        raise AssemblyError(
            f"{domain_name} activation block is not uniquely bound by live configuration"
        )
    activation_block = activation_candidates[0]
    return {
        "chain_id": chain_id,
        "chain_version": 1,
        "rpc_url": rpc_url,
        "genesis_hash": genesis_hash,
        "configuration_hash": configuration_hash,
        "activation_block": activation_block,
        "activation_timestamp": number(live_chain[7]),
        "registry_status": "ACTIVE",
        "observer_fixture": f"phase8-{domain_name}-ed25519-public-fixture-v1",
        "observer_public_key_ed25519": observer_public_key,
        "observer_authority_hash": observer_authority,
        "confirmation_depth": 12,
        "signer_set": signer_set(
            blueprint,
            domain_name,
            rpc,
            contracts["finality_verifier"]["address"],
        ),
        "contracts": contracts,
        "registry_bindings": {
            "route_registry_chain_registry": registry,
            "finality_verifier_chain_registry": registry,
        },
        "finality_policies": copy.deepcopy(policies),
    }


def build_exposure_policy(
    blueprint: dict[str, Any],
    home_rpc: RPC,
    contracts: dict[str, dict[str, Any]],
    routes: list[dict[str, Any]],
) -> dict[str, Any]:
    def blueprint_int(field: str) -> int:
        value = blueprint.get(field)
        if isinstance(value, bool) or not isinstance(value, (int, str)):
            raise AssemblyError(f"blueprint {field} is not an integer")
        try:
            result = int(value)
        except ValueError as error:
            raise AssemblyError(f"blueprint {field} is not an integer") from error
        if result < 0:
            raise AssemblyError(f"blueprint {field} is negative")
        return result

    supply_reference = blueprint_int("circulating_supply_reference_units")
    route_cap = blueprint_int("route_absolute_cap_units")
    chain_cap = blueprint_int("chain_absolute_cap_units")
    adapter_cap = blueprint_int("adapter_absolute_cap_units")
    aggregate_cap = blueprint_int("aggregate_absolute_cap_units")
    route_bps = blueprint_int("route_percentage_ceiling_bps")
    aggregate_bps = blueprint_int("aggregate_percentage_ceiling_bps")
    activation_delay = blueprint_int("activation_delay")
    active_from = blueprint_int("active_from")
    exposure = {
        "policy_version": blueprint_int("exposure_policy_version"),
        "policy_hash": lower_hex(
            blueprint["exposure_policy_hash"],
            "exposure policy hash",
            32,
        ),
        "circulating_supply_reference_units": str(supply_reference),
        "circulating_supply_evidence_hash": lower_hex(
            blueprint["circulating_supply_evidence_hash"],
            "circulating supply evidence hash",
            32,
        ),
        "route_absolute_cap_units": str(route_cap),
        "chain_absolute_cap_units": str(chain_cap),
        "adapter_absolute_cap_units": str(adapter_cap),
        "aggregate_absolute_cap_units": str(aggregate_cap),
        "route_percentage_ceiling_basis_points": route_bps,
        "aggregate_percentage_ceiling_basis_points": aggregate_bps,
        "activation_delay": activation_delay,
        "active_from": active_from,
    }
    live_words = [
        word_uint(supply_reference),
        word_hex(
            exposure["circulating_supply_evidence_hash"],
            "circulating supply evidence",
            32,
        ),
        word_uint(route_cap),
        word_uint(chain_cap),
        word_uint(adapter_cap),
        word_uint(aggregate_cap),
        word_uint(route_bps),
        word_uint(aggregate_bps),
        word_uint(activation_delay),
        word_uint(active_from),
    ]
    if solidity_hash("UNIFIED_BRIDGE_EXPOSURE_POLICY_V1", live_words) != exposure["policy_hash"]:
        raise AssemblyError("blueprint exposure policy hash is not Solidity-canonical")
    contract = contracts["home"]["bridge_exposure_policy"]["address"]
    live_policy = home_rpc.eth_call(
        contract,
        "policy(bytes32)",
        bytes.fromhex(str(exposure["policy_hash"])[2:]),
    )
    if live_policy != b"".join(live_words):
        raise AssemblyError("blueprint exposure policy differs from live policy")
    mint = next(route for route in routes if route["purpose"] == "MINT")
    active = home_rpc.eth_call(
        contract,
        "activePolicyForRoute(bytes32)",
        bytes.fromhex(str(mint["route_policy_hash"])[2:]),
    )
    if active != bytes.fromhex(str(exposure["policy_hash"])[2:]):
        raise AssemblyError("MINT route does not use the blueprint exposure policy")
    max_supply = home_rpc.eth_call(
        contracts["home"]["canonical_uft"]["address"],
        "MAX_SUPPLY()",
    )
    if max_supply != live_words[0]:
        raise AssemblyError("blueprint supply reference differs from live MAX_SUPPLY")
    return exposure


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".phase8-release-evidence-",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def assemble(
    blueprint_path: Path = LIVE_BLUEPRINT,
    flow_path: Path = AUTHENTICATED_FLOW,
) -> dict[str, Any]:
    blueprint = read_json(blueprint_path, "Phase 8 live deployment blueprint")
    authenticated = read_json(flow_path, "authenticated Phase 8 flow")
    if (
        blueprint.get("artifact_type") != "PHASE8_LIVE_DEPLOYMENT_BLUEPRINT"
        or blueprint.get("contains_real_value") is not False
        or authenticated.get("artifact_type") != "PHASE8_AUTHENTICATED_FLOW_INPUT"
        or authenticated.get("contains_real_value") is not False
        or blueprint.get("protocol_id") != authenticated.get("protocol_id")
        or blueprint.get("loan_id") != authenticated.get("loan_id")
    ):
        raise AssemblyError("live blueprint and authenticated flow identities differ")

    rpcs = {"home": RPC("http://127.0.0.1:8545"), "satellite": RPC("http://127.0.0.1:8546")}
    scanned = {name: scan_receipts(rpc) for name, rpc in rpcs.items()}
    loan_id = lower_hex(blueprint["loan_id"], "loan ID", 32)
    contracts = {
        name: domain_contracts(
            name,
            blueprint,
            authenticated,
            rpcs[name],
            scanned[name][0],
            scanned[name][1],
            loan_id,
        )
        for name in ("home", "satellite")
    }

    routes: list[dict[str, Any]] = []
    for purpose, suffix in ROUTE_NAMES:
        home_route = decode_live_route(
            blueprint,
            purpose,
            suffix,
            rpcs["home"],
            contracts["home"]["route_registry"]["address"],
        )
        satellite_route = decode_live_route(
            blueprint,
            purpose,
            suffix,
            rpcs["satellite"],
            contracts["satellite"]["route_registry"]["address"],
        )
        if home_route != satellite_route:
            raise AssemblyError(f"{purpose} route differs across live registries")
        routes.append(home_route)
    route_topic = hex32(
        keccak256(b"RouteRegistered(bytes32,uint256,uint256,address,address,bytes32,uint32)")
    )
    policies: list[dict[str, Any]] = []
    for route, (purpose, _) in zip(routes, ROUTE_NAMES, strict=True):
        for domain_name in ("home", "satellite"):
            registry = contracts[domain_name]["route_registry"]["address"]
            receipt = find_log_receipt(
                scanned[domain_name][1],
                registry,
                route_topic,
                route["route_policy_hash"],
            )
            transaction_hash, block_number = receipt_identity(receipt)
            route[f"{domain_name}_registration_tx_hash"] = transaction_hash
            route[f"{domain_name}_registration_block_number"] = block_number
            route[f"{domain_name}_registry_hash"] = route["route_policy_hash"]
        for destination in (False, True):
            home_policy = decode_live_policy(
                rpcs["home"],
                contracts["home"]["finality_verifier"]["address"],
                route,
                purpose,
                destination,
            )
            satellite_policy = decode_live_policy(
                rpcs["satellite"],
                contracts["satellite"]["finality_verifier"]["address"],
                route,
                purpose,
                destination,
            )
            if home_policy != satellite_policy:
                raise AssemblyError(f"{purpose} finality policy differs across live verifiers")
            policies.append(home_policy)

    domains: dict[str, Any] = {}
    for domain_name, chain_id, rpc_url in (
        ("home", 31337, "http://127.0.0.1:8545"),
        ("satellite", 31338, "http://127.0.0.1:8546"),
    ):
        domains[domain_name] = build_domain(
            domain_name,
            chain_id,
            rpc_url,
            rpcs[domain_name],
            scanned[domain_name][1],
            contracts[domain_name],
            blueprint,
            policies,
        )

    flow = build_flow(blueprint, authenticated, contracts, routes, rpcs)
    exposure_policy = build_exposure_policy(
        blueprint,
        rpcs["home"],
        contracts,
        routes,
    )
    recovery_hash = solidity_hash(
        "UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1",
        [
            word_uint(1),
            word_uint(2),
            *(word_hex(signer, "recovery signer", 20) for signer in EXPECTED_SIGNERS),
        ],
    )
    recovery = {
        "action": "TOMBSTONE_THEN_COMPENSATE",
        "authorizer_set_version": 1,
        "threshold": 2,
        "authorizer_set_hash": recovery_hash,
        "sorted_authorizer_addresses": list(EXPECTED_SIGNERS),
    }
    providers = [
        {
            "id": "mock-bridge-provider-a",
            "url": "http://127.0.0.1:58081",
            "authority": "TRANSPORT_ONLY",
        },
        {
            "id": "mock-bridge-provider-b",
            "url": "http://127.0.0.1:58082",
            "authority": "TRANSPORT_ONLY",
        },
    ]
    deployment_flow = {
        "protocol_id": blueprint["protocol_id"],
        "proof_boundary": PROOF_BOUNDARY,
        "domains": domains,
        "routes": routes,
        "exposure_policy": exposure_policy,
        "recovery": recovery,
        "providers": providers,
        "flow": flow,
    }
    commitment = hashlib.sha256(canonical_json(deployment_flow)).hexdigest()
    latest_timestamp = max(
        int(
            mapping(
                mapping(message, "flow message")["acknowledgement"],
                "acknowledgement",
            )["proof"]["source_block_timestamp"]
        )
        for message in flow["messages"]
    )
    generated_at = (
        datetime.datetime.fromtimestamp(latest_timestamp, datetime.UTC)
        .isoformat()
        .replace("+00:00", "Z")
    )
    run_id = "phase8-local-" + commitment[:20]
    reset_before = {
        "labeled_containers": docker_count("container"),
        "labeled_volumes": docker_count("volume"),
        "labeled_networks": docker_count("network"),
        "deployment_artifacts": len(list((ROOT / "protocol/deployments/local").glob("*.json"))),
    }
    if any(value <= 0 for value in reset_before.values()):
        raise AssemblyError("labeled topology is incomplete before release assembly")
    result = {
        "schema_version": 1,
        "artifact_type": "PHASE8_RELEASE_EVIDENCE",
        "environment": "local",
        "contains_real_value": False,
        "run_id": run_id,
        "protocol_id": blueprint["protocol_id"],
        "proof_boundary": PROOF_BOUNDARY,
        "generated_at": generated_at,
        "source_commit": git_head(),
        "deployment_flow_sha256": commitment,
        "domains": domains,
        "routes": routes,
        "exposure_policy": exposure_policy,
        "recovery": recovery,
        "providers": providers,
        "flow": flow,
        "durable": None,
        "reset": {
            "command": "pwsh ./scripts/local-reset.ps1",
            "required_before": reset_before,
            "expected_after": {
                "labeled_containers": 0,
                "labeled_volumes": 0,
                "labeled_networks": 0,
                "deployment_artifacts": 0,
            },
            "remove_deployment_directory": True,
            "remove_cache_directory": True,
        },
        "validation": {
            "deployment_complete": True,
            "rpc_code_verified": True,
            "trust_consistent": True,
            "synthetic_boundary_explicit": True,
            "authenticated_inclusion_verified": True,
            "solidity_hashes_recomputed": True,
            "full_flow_complete": True,
            "replay_complete": True,
            "restart_complete": False,
            "journals_balanced": False,
            "reconciliation_matched": False,
            "state_parity_matched": False,
        },
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blueprint", type=Path, default=LIVE_BLUEPRINT)
    parser.add_argument("--flow", type=Path, default=AUTHENTICATED_FLOW)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    blueprint_path = args.blueprint.resolve()
    flow_path = args.flow.resolve()
    output_path = args.output.resolve()
    try:
        assembled = assemble(blueprint_path, flow_path)
        atomic_write(output_path, assembled)
    except AssemblyError as error:
        print(f"Phase 8 release assembly failed: {error}")
        return 1
    print(
        "Phase 8 authenticated intermediate assembled at "
        "protocol/deployments/local/phase8-release-evidence.json (durable: null)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
