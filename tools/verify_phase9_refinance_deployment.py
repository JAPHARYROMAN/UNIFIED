#!/usr/bin/env python3
"""Prepare and verify non-activating Phase 9 refinance deployment topology evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping, Sequence
from datetime import UTC, datetime
from functools import lru_cache
from pathlib import Path
from typing import Any, NoReturn, cast

import check_phase9_refinance_linked_modules as linked_checker
import jsonschema
from Crypto.Hash import keccak

ROOT = Path(__file__).resolve().parents[1]
PLAN_RELATIVE = Path("protocol/deployments/local/phase9-refinance-deployment-plan.json")
CANDIDATE_RELATIVE = Path("protocol/deployments/local/phase9-refinance-deployment-candidate.json")
BROADCAST_RELATIVE = Path(
    "protocol/broadcast/DeployPhase9RefinanceLocal.s.sol/31337/run-latest.json"
)
EVIDENCE_RELATIVE = Path("protocol/deployments/local/phase9-refinance-deployment-evidence.json")
PLAN_SCHEMA_RELATIVE = Path("infrastructure/local/phase9-refinance-deployment-plan.schema.json")
CANDIDATE_SCHEMA_RELATIVE = Path(
    "infrastructure/local/phase9-refinance-deployment-candidate.schema.json"
)
EVIDENCE_SCHEMA_RELATIVE = Path(
    "infrastructure/local/phase9-refinance-deployment-evidence.schema.json"
)
DEFAULT_RESET_COMMAND = "pwsh ./scripts/smoke-phase9-refinance-anvil.ps1"
CHAIN_ID = 31_337
EIP_170_LIMIT = 24_576
EIP_3860_LIMIT = 49_152
SELF_PATCH_OFFSET = 1
SELF_PATCH_LENGTH = 20
REFINANCE_SOURCE = linked_checker.REFINANCE_SOURCE
FORGE_REFINANCE_SOURCE = "src/resolution/RefinanceCoordinator.sol"

_FORGE_SOURCE_UNIT_COMPILER = r"""
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import solc from "solc";

const repositoryRoot = resolve(process.argv[1]);
const libraries = JSON.parse(process.argv[2]);
const protocolRoot = resolve(repositoryRoot, "protocol");
const compilationSource = "src/ProtocolCompilation.sol";
const refinanceSource = "src/resolution/RefinanceCoordinator.sol";
const settings = {
  evmVersion: "prague",
  optimizer: { enabled: true, runs: 200 },
  viaIR: false,
};
const remappings = [
  ":@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
  ":openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/",
];
const outputFields = [
  "storageLayout",
  "evm.methodIdentifiers",
  "evm.bytecode.object",
  "evm.bytecode.linkReferences",
  "evm.deployedBytecode.object",
  "evm.deployedBytecode.immutableReferences",
  "evm.deployedBytecode.linkReferences",
  "evm.deployedBytecode.opcodes",
];
const input = {
  language: "Solidity",
  settings: {
    ...settings,
    remappings,
    ...(Object.keys(libraries).length === 0 ? {} : { libraries }),
    outputSelection: {
      "*": { "*": outputFields },
      [refinanceSource]: { "": ["ast"], "*": outputFields },
    },
  },
  sources: {
    [compilationSource]: {
      content: readFileSync(resolve(protocolRoot, compilationSource), "utf8"),
    },
  },
};
function findImport(importPath) {
  for (const candidate of [
    resolve(protocolRoot, importPath),
    resolve(repositoryRoot, "node_modules", importPath),
    resolve(protocolRoot, "src", importPath),
  ]) {
    try {
      return { contents: readFileSync(candidate, "utf8") };
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  return { error: `Import not found: ${importPath}` };
}
const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImport }));
output.compilerVersion = solc.version();
output.openzeppelinVersion = JSON.parse(
  readFileSync(
    resolve(repositoryRoot, "node_modules/@openzeppelin/contracts/package.json"),
    "utf8",
  ),
).version;
output.compilerSettings = settings;
output.compilerRemappings = remappings;
output.compilerLibraries = libraries;
process.stdout.write(JSON.stringify(output));
"""

RpcCall = Callable[[str, list[object]], object]

CONFIG_FIELDS = frozenset(
    {
        "loan_registry",
        "role_manager",
        "settlement_token",
        "quote_policy_registry",
        "refinance_policy_registry",
        "amendment_policy_registry",
        "protection_policy_registry",
        "recovery_policy_registry",
        "asset_registry",
        "emergency_controller",
        "treasury_fee_recipient",
        "maximum_quote_validity",
    }
)

SEQUENCE = (
    ("lien_registry", "LienRegistry", "protocol/src/resolution/LienRegistry.sol"),
    (
        "collateral_custody",
        "CollateralCustodyV2",
        "protocol/src/resolution/CollateralCustodyV2.sol",
    ),
    (
        "loan_account_implementation",
        "Phase9LoanAccount",
        "protocol/src/resolution/Phase9LoanAccount.sol",
    ),
    (
        "position_manager_implementation",
        "PositionManagerV2",
        "protocol/src/resolution/PositionManagerV2.sol",
    ),
    (
        "phase9_loan_factory",
        "Phase9LoanFactory",
        "protocol/src/resolution/Phase9LoanFactory.sol",
    ),
    (
        "validation_module",
        linked_checker.VALIDATION_MODULE,
        REFINANCE_SOURCE,
    ),
    ("request_module", linked_checker.REQUEST_MODULE, REFINANCE_SOURCE),
    ("lifecycle_module", linked_checker.LIFECYCLE_MODULE, REFINANCE_SOURCE),
    (
        "payoff_quote_engine",
        "PayoffQuoteEngine",
        "protocol/src/resolution/PayoffQuoteEngine.sol",
    ),
    ("refinance_coordinator", linked_checker.COORDINATOR, REFINANCE_SOURCE),
)

FORGE_ARTIFACTS = {
    "LienRegistry": "protocol/out/LienRegistry.sol/LienRegistry.json",
    "CollateralCustodyV2": ("protocol/out/CollateralCustodyV2.sol/CollateralCustodyV2.json"),
    "Phase9LoanAccount": "protocol/out/Phase9LoanAccount.sol/Phase9LoanAccount.json",
    "PositionManagerV2": "protocol/out/PositionManagerV2.sol/PositionManagerV2.json",
    "Phase9LoanFactory": "protocol/out/Phase9LoanFactory.sol/Phase9LoanFactory.json",
    "PayoffQuoteEngine": "protocol/out/PayoffQuoteEngine.sol/PayoffQuoteEngine.json",
    "Phase9LocalSyntheticToken": (
        "protocol/out/Phase9LocalSyntheticToken.sol/Phase9LocalSyntheticToken.json"
    ),
    "RoleManager": "protocol/out/RoleManager.sol/RoleManager.json",
    "LoanRegistry": "protocol/out/LoanRegistry.sol/LoanRegistry.json",
    "PolicyRegistry": "protocol/out/PolicyRegistry.sol/PolicyRegistry.json",
    "AssetRegistry": "protocol/out/AssetRegistry.sol/AssetRegistry.json",
    "EmergencyController": "protocol/out/EmergencyController.sol/EmergencyController.json",
}

ARTIFACT_SOURCES = {
    "LienRegistry": "src/resolution/LienRegistry.sol",
    "CollateralCustodyV2": "src/resolution/CollateralCustodyV2.sol",
    "Phase9LoanAccount": "src/resolution/Phase9LoanAccount.sol",
    "PositionManagerV2": "src/resolution/PositionManagerV2.sol",
    "Phase9LoanFactory": "src/resolution/Phase9LoanFactory.sol",
    "PayoffQuoteEngine": "src/resolution/PayoffQuoteEngine.sol",
    "Phase9LocalSyntheticToken": "src/token/Phase9LocalSyntheticToken.sol",
    "RoleManager": "src/kernel/RoleManager.sol",
    "LoanRegistry": "src/kernel/LoanRegistry.sol",
    "PolicyRegistry": "src/kernel/PolicyRegistry.sol",
    "AssetRegistry": "src/kernel/AssetRegistry.sol",
    "EmergencyController": "src/kernel/EmergencyController.sol",
}

DEPENDENCY_CONTRACTS = {
    "role_manager": "RoleManager",
    "loan_registry": "LoanRegistry",
    "settlement_token": "Phase9LocalSyntheticToken",
    "quote_policy_registry": "PolicyRegistry",
    "refinance_policy_registry": "PolicyRegistry",
    "amendment_policy_registry": "PolicyRegistry",
    "protection_policy_registry": "PolicyRegistry",
    "recovery_policy_registry": "PolicyRegistry",
    "asset_registry": "AssetRegistry",
    "emergency_controller": "EmergencyController",
}

DEPLOYMENT_ARTIFACT_PATHS = {
    "LienRegistry": "protocol/out/LienRegistry.sol/LienRegistry.json",
    "CollateralCustodyV2": "protocol/out/CollateralCustodyV2.sol/CollateralCustodyV2.json",
    "Phase9LoanAccount": "protocol/out/Phase9LoanAccount.sol/Phase9LoanAccount.json",
    "PositionManagerV2": "protocol/out/PositionManagerV2.sol/PositionManagerV2.json",
    "Phase9LoanFactory": "protocol/out/Phase9LoanFactory.sol/Phase9LoanFactory.json",
    linked_checker.VALIDATION_MODULE: (
        "protocol/out/RefinanceCoordinator.sol/Phase9RefinanceValidationModule.json"
    ),
    linked_checker.REQUEST_MODULE: (
        "protocol/out/RefinanceCoordinator.sol/Phase9RefinanceRequestModule.json"
    ),
    linked_checker.LIFECYCLE_MODULE: (
        "protocol/out/RefinanceCoordinator.sol/Phase9RefinanceLifecycleModule.json"
    ),
    "PayoffQuoteEngine": "protocol/out/PayoffQuoteEngine.sol/PayoffQuoteEngine.json",
    linked_checker.COORDINATOR: ("protocol/out/RefinanceCoordinator.sol/RefinanceCoordinator.json"),
}

CODE_DEPENDENCY_FIELDS = frozenset(
    {
        "role_manager",
        "loan_registry",
        "settlement_token",
        "quote_policy_registry",
        "refinance_policy_registry",
        "amendment_policy_registry",
        "protection_policy_registry",
        "recovery_policy_registry",
        "asset_registry",
        "emergency_controller",
    }
)

EXPECTED_LINK_COUNTS = {
    linked_checker.VALIDATION_MODULE: 1,
    linked_checker.REQUEST_MODULE: 2,
    linked_checker.LIFECYCLE_MODULE: 4,
}


class VerificationError(ValueError):
    """Fail-closed deployment evidence error."""


class _RejectRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(  # type: ignore[override]
        self,
        req: urllib.request.Request,
        fp: object,
        code: int,
        msg: str,
        headers: Mapping[str, str],
        newurl: str,
    ) -> None:
        del req, fp, code, msg, headers, newurl
        _fail("RPC redirects are forbidden")


def _fail(message: str) -> NoReturn:
    raise VerificationError(message)


def _pairs_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            _fail(f"JSON contains duplicate key: {key}")
        result[key] = value
    return result


def _read_json(path: Path) -> dict[str, Any]:
    try:
        payload: object = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=_pairs_object
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        _fail(f"cannot read JSON {path}: {error}")
    if not isinstance(payload, dict):
        _fail(f"JSON root must be an object: {path}")
    return cast(dict[str, Any], payload)


def _write_json(path: Path, payload: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _canonical_json(payload: object) -> bytes:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )


def _sha256(payload: object) -> str:
    return "sha256:" + hashlib.sha256(_canonical_json(payload)).hexdigest()


def _file_sha256(path: Path) -> str:
    try:
        content = path.read_bytes()
    except OSError as error:
        _fail(f"cannot hash canonical source {path}: {error}")
    return "sha256:" + hashlib.sha256(content).hexdigest()


def _git_identity(root: Path = ROOT) -> tuple[str, bool]:
    git = shutil.which("git")
    if git is None:
        _fail("Git executable is unavailable")
    try:
        commit = subprocess.run(  # noqa: S603 - resolved Git executable, fixed arguments
            (git, "rev-parse", "HEAD"),
            cwd=root,
            capture_output=True,
            check=False,
            text=True,
        )
        status = subprocess.run(  # noqa: S603 - resolved Git executable, fixed arguments
            (git, "status", "--porcelain", "--untracked-files=all"),
            cwd=root,
            capture_output=True,
            check=False,
            text=True,
        )
    except OSError as error:
        _fail(f"Git identity query failed: {error}")
    source_commit = commit.stdout.strip().lower()
    if commit.returncode != 0 or re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        _fail("source commit is unavailable")
    if status.returncode != 0:
        _fail("working-tree status is unavailable")
    return source_commit, not status.stdout.strip()


def _keccak(data: bytes) -> str:
    digest = keccak.new(digest_bits=256)
    digest.update(data)
    return "0x" + digest.hexdigest()


def _address(value: object, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"0x[0-9a-fA-F]{40}", value) is None:
        _fail(f"{label} must be an address")
    normalized = value.lower()
    if normalized == "0x" + "00" * 20:
        _fail(f"{label} must be nonzero")
    return normalized


def _bytes32(value: object, label: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"(?:0x|sha256:)[0-9a-fA-F]{64}", value) is None:
        _fail(f"{label} must be a 32-byte digest")
    return value.lower()


def _quantity(value: object, label: str) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        if value < 0:
            _fail(f"{label} must be nonnegative")
        return value
    if not isinstance(value, str) or re.fullmatch(r"0x(?:0|[1-9a-f][0-9a-f]*)", value) is None:
        _fail(f"{label} must be a canonical quantity")
    return int(value, 16)


def _hex_blob(value: object, label: str) -> bytes:
    if not isinstance(value, str) or re.fullmatch(r"0x(?:[0-9a-fA-F]{2})*", value) is None:
        _fail(f"{label} must be canonical hex bytes")
    return bytes.fromhex(value[2:])


def canonical_rpc_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if (
        parsed.scheme != "http"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
        or parsed.port is None
    ):
        _fail("RPC URL must be credential-free loopback HTTP with an explicit port")
    hostname = (parsed.hostname or "").lower()
    if hostname not in {"127.0.0.1", "localhost", "::1"}:
        _fail("RPC URL must use a literal loopback endpoint")
    host = f"[{hostname}]" if ":" in hostname else hostname
    return f"http://{host}:{parsed.port}"


class HttpRpc:
    def __init__(self, url: str) -> None:
        self.url = canonical_rpc_url(url)
        self._proxy_handler = urllib.request.ProxyHandler({})
        self._redirect_handler = _RejectRedirects()
        self._opener = urllib.request.build_opener(self._proxy_handler, self._redirect_handler)
        self._counter = 0

    def __call__(self, method: str, params: list[object]) -> object:
        self._counter += 1
        body = _canonical_json(
            {"jsonrpc": "2.0", "id": self._counter, "method": method, "params": params}
        )
        request = urllib.request.Request(  # noqa: S310 - canonical_rpc_url allows HTTP only
            self.url,
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with self._opener.open(request, timeout=10) as response:
                payload: object = json.loads(response.read(), object_pairs_hook=_pairs_object)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            _fail(f"RPC call failed: {method}: {error}")
        if not isinstance(payload, dict) or payload.get("error") is not None:
            _fail(f"RPC returned an error: {method}")
        return payload.get("result")


def _create_address(deployer: str, nonce: int) -> str:
    if nonce < 1 or nonce > 0x7F:
        _fail("only single-byte nonzero CREATE nonces are supported")
    encoded = bytes((0xD6, 0x94)) + bytes.fromhex(deployer[2:]) + bytes((nonce,))
    return "0x" + _keccak_bytes(encoded)[12:].hex()


def _keccak_bytes(data: bytes) -> bytes:
    digest = keccak.new(digest_bits=256)
    digest.update(data)
    return digest.digest()


LOAN_FACTORY_ROLE = _keccak_bytes(b"LOAN_FACTORY_ROLE")
ROLE_EXPIRY_SELECTOR = _keccak_bytes(b"roleExpiry(bytes32,address)")[:4]
HAS_ROLE_SELECTOR = _keccak_bytes(b"hasRole(bytes32,address)")[:4]
ROLE_EVENT_TOPICS = {
    _keccak(b"RoleGranted(bytes32,address,uint64,address)"),
    _keccak(b"RoleRevoked(bytes32,address,address)"),
    _keccak(b"RoleAdminChanged(bytes32,bytes32,bytes32)"),
}


def _word_address(value: str) -> bytes:
    return bytes(12) + bytes.fromhex(value[2:])


def _word_uint(value: int) -> bytes:
    if value < 0 or value >= 1 << 256:
        _fail("constructor integer is outside uint256")
    return value.to_bytes(32, "big")


def _configuration_hash(config: Mapping[str, object], broadcaster: str) -> str:
    registry_fields = (
        "role_manager",
        "loan_registry",
        "settlement_token",
        "quote_policy_registry",
        "refinance_policy_registry",
        "amendment_policy_registry",
        "protection_policy_registry",
        "recovery_policy_registry",
    )
    registry_hash = _keccak_bytes(
        b"".join(_word_address(cast(str, config[field])) for field in registry_fields)
    )
    local_hash = _keccak_bytes(
        _word_address(broadcaster)
        + _word_address(cast(str, config["asset_registry"]))
        + _word_address(cast(str, config["emergency_controller"]))
        + _word_address(cast(str, config["treasury_fee_recipient"]))
        + _word_uint(cast(int, config["maximum_quote_validity"]))
    )
    domain = _keccak_bytes(b"UNIFIED_PHASE9_REFINANCE_DEPLOYMENT_CONFIGURATION_V1")
    return _keccak(domain + _word_uint(CHAIN_ID) + registry_hash + local_hash)


def _validate_config(payload: Mapping[str, object]) -> dict[str, object]:
    if set(payload) != CONFIG_FIELDS:
        _fail(
            "configuration fields drifted; missing="
            + ",".join(sorted(CONFIG_FIELDS - set(payload)))
            + "; extra="
            + ",".join(sorted(set(payload) - CONFIG_FIELDS))
        )
    result: dict[str, object] = {}
    for field in sorted(CONFIG_FIELDS - {"maximum_quote_validity"}):
        result[field] = _address(payload[field], f"configuration.{field}")
    if result["quote_policy_registry"] != result["refinance_policy_registry"]:
        _fail(
            "configuration.quote_policy_registry must equal configuration.refinance_policy_registry"
        )
    validity = payload["maximum_quote_validity"]
    if (
        not isinstance(validity, int)
        or isinstance(validity, bool)
        or not 0 < validity <= (1 << 64) - 1
    ):
        _fail("configuration.maximum_quote_validity must be a nonzero uint64")
    result["maximum_quote_validity"] = validity
    return result


def _artifact_object(value: object, label: str) -> bytes:
    if not isinstance(value, str):
        _fail(f"{label} object is missing")
    normalized = value[2:] if value.startswith("0x") else value
    if re.fullmatch(r"[0-9a-fA-F]*", normalized) is None or len(normalized) % 2 != 0:
        _fail(f"{label} object is not linked hex")
    return bytes.fromhex(normalized)


def _compiler_artifact(
    output: Mapping[str, Any], source: str, contract: str
) -> tuple[bytes, bytes]:
    source_contracts = output.get("contracts", {}).get(source)
    if not isinstance(source_contracts, dict):
        _fail(f"canonical compiler source is missing: {source}")
    artifact = source_contracts.get(contract)
    if not isinstance(artifact, dict) or not isinstance(artifact.get("evm"), dict):
        _fail(f"canonical compiler artifact is missing: {source}:{contract}")
    evm = cast(Mapping[str, Any], artifact["evm"])
    bytecode = evm.get("bytecode")
    deployed = evm.get("deployedBytecode")
    if not isinstance(bytecode, dict) or not isinstance(deployed, dict):
        _fail(f"canonical compiler bytecode is missing: {source}:{contract}")
    return (
        _artifact_object(bytecode.get("object"), f"{contract} creation"),
        _artifact_object(deployed.get("object"), f"{contract} runtime"),
    )


def _immutable_offsets(output: Mapping[str, Any], source: str, contract: str) -> list[int]:
    source_contracts = output.get("contracts", {}).get(source)
    if not isinstance(source_contracts, dict):
        _fail(f"canonical compiler source is missing: {source}")
    artifact = source_contracts.get(contract)
    if not isinstance(artifact, dict) or not isinstance(artifact.get("evm"), dict):
        _fail(f"canonical compiler artifact is missing: {source}:{contract}")
    deployed = cast(Mapping[str, Any], artifact["evm"]).get("deployedBytecode")
    if not isinstance(deployed, dict):
        _fail(f"canonical deployed bytecode is missing: {source}:{contract}")
    references = deployed.get("immutableReferences", {})
    if not isinstance(references, dict):
        _fail(f"immutable references are malformed: {source}:{contract}")
    offsets: list[int] = []
    for entries in references.values():
        if not isinstance(entries, list):
            _fail(f"immutable references are malformed: {source}:{contract}")
        for entry in entries:
            if (
                not isinstance(entry, dict)
                or type(entry.get("start")) is not int
                or entry.get("length") != 32
            ):
                _fail(f"immutable reference is not a 32-byte offset: {source}:{contract}")
            offsets.append(cast(int, entry["start"]))
    if len(offsets) != len(set(offsets)):
        _fail(f"immutable references overlap: {source}:{contract}")
    return sorted(offsets)


def _patch_immutable_words(runtime: bytes, offsets: Sequence[int], word: bytes) -> bytes:
    if len(word) != 32:
        _fail("immutable replacement must be one ABI word")
    patched = bytearray(runtime)
    for offset in offsets:
        end = offset + 32
        if offset < 0 or end > len(patched) or patched[offset:end] != bytes(32):
            _fail("immutable runtime placeholder drifted")
        patched[offset:end] = word
    return bytes(patched)


def _source_set_facts(root: Path, output: Mapping[str, Any]) -> tuple[str, int]:
    sources = output.get("sources")
    if not isinstance(sources, dict) or not sources:
        _fail("canonical compiler source set is missing")
    hashes: dict[str, str] = {}
    for source in sorted(sources):
        if not isinstance(source, str) or ".." in Path(source).parts:
            _fail("canonical compiler source name is malformed")
        if source.startswith("src/"):
            path = root / "protocol" / source
        elif source.startswith("lib/openzeppelin-contracts/"):
            path = root / "protocol" / source
        else:
            _fail(f"canonical compiler source is outside the pinned source roots: {source}")
        try:
            content = path.read_bytes()
        except OSError as error:
            _fail(f"cannot hash canonical compiler source {source}: {error}")
        hashes[source] = "sha256:" + hashlib.sha256(content).hexdigest()
    return _sha256(hashes), len(hashes)


def _link_entries(value: object) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    if not isinstance(value, dict):
        _fail("linkReferences must be an object")
    for source, libraries in value.items():
        if not isinstance(source, str) or not isinstance(libraries, dict):
            _fail("linkReferences source map is malformed")
        for library, offsets in libraries.items():
            if not isinstance(library, str) or not isinstance(offsets, list):
                _fail("linkReferences library map is malformed")
            for offset in offsets:
                if not isinstance(offset, dict):
                    _fail("linkReferences offset is malformed")
                start = offset.get("start")
                length = offset.get("length")
                if type(start) is not int or length != 20:
                    _fail("linkReferences must contain 20-byte integer offsets")
                entries.append({"source": source, "library": library, "start": start, "length": 20})
    return sorted(entries, key=lambda item: cast(int, item["start"]))


def _link_hex(
    object_hex: object, links: Sequence[Mapping[str, object]], addresses: Mapping[str, str]
) -> bytes:
    if not isinstance(object_hex, str) or len(object_hex) % 2 != 0:
        _fail("unlinked bytecode object is malformed")
    mutable = list(object_hex)
    occupied: set[int] = set()
    for link in links:
        library = cast(str, link["library"])
        start = cast(int, link["start"]) * 2
        end = start + 40
        if library not in addresses or end > len(mutable):
            _fail("link target or offset is invalid")
        if occupied.intersection(range(start, end)):
            _fail("link offsets overlap")
        placeholder = "".join(mutable[start:end])
        if re.fullmatch(r"__\$[0-9a-fA-F]{34}\$__", placeholder) is None:
            _fail("link offset does not contain an unresolved compiler placeholder")
        mutable[start:end] = list(addresses[library][2:])
        occupied.update(range(start, end))
    linked = "".join(mutable)
    if "__$" in linked or re.fullmatch(r"[0-9a-fA-F]*", linked) is None:
        _fail("linked bytecode contains an unresolved placeholder")
    return bytes.fromhex(linked)


def _patched_module_runtime(template: bytes, address: str) -> bytes:
    end = SELF_PATCH_OFFSET + SELF_PATCH_LENGTH
    if (
        len(template) <= end
        or template[0] != 0x73
        or template[SELF_PATCH_OFFSET:end] != bytes(SELF_PATCH_LENGTH)
        or template[end] != 0x30
    ):
        _fail("module runtime self-patch template drifted")
    return template[:SELF_PATCH_OFFSET] + bytes.fromhex(address[2:]) + template[end:]


def _compile_forge_source_units(
    root: Path, libraries: Mapping[str, Mapping[str, str]]
) -> dict[str, Any]:
    node = shutil.which("node")
    if node is None:
        _fail("node executable is unavailable")
    result = subprocess.run(  # noqa: S603 - resolved Node executable, fixed arguments
        (
            node,
            "--input-type=module",
            "--eval",
            _FORGE_SOURCE_UNIT_COMPILER,
            str(root.resolve()),
            json.dumps(libraries, sort_keys=True, separators=(",", ":")),
        ),
        cwd=root,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "no compiler diagnostic"
        _fail(f"Forge-source-unit Solidity compilation failed: {detail}")
    try:
        payload: object = json.loads(result.stdout, object_pairs_hook=_pairs_object)
    except json.JSONDecodeError as error:
        _fail(f"Forge-source-unit Solidity compilation returned malformed JSON: {error}")
    if not isinstance(payload, dict):
        _fail("Forge-source-unit Solidity compilation returned a non-object")
    return cast(dict[str, Any], payload)


def _linked_checker_source_view(value: object) -> object:
    if isinstance(value, dict):
        return {
            ("protocol/" + key if isinstance(key, str) and key.startswith("src/") else key): (
                _linked_checker_source_view(item)
            )
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_linked_checker_source_view(item) for item in value]
    return value


def _executable_prefix(bytecode: bytes, label: str) -> bytes:
    if len(bytecode) < 2:
        _fail(f"{label} has no Solidity metadata length suffix")
    metadata_length = int.from_bytes(bytecode[-2:], "big")
    executable_end = len(bytecode) - metadata_length - 2
    if executable_end <= 0:
        _fail(f"{label} has a malformed Solidity metadata suffix")
    return bytecode[:executable_end]


def _compiler_facts(
    root: Path = ROOT, module_addresses: Mapping[str, str] | None = None
) -> dict[str, object]:
    if module_addresses is None or set(module_addresses) != set(linked_checker.MODULES):
        _fail("canonical compiler requires the exact three predicted module addresses")
    normalized_addresses = tuple(
        (module, _address(module_addresses[module], f"compiler library {module}"))
        for module in linked_checker.MODULES
    )
    return _compiler_facts_cached(str(root.resolve()), normalized_addresses)


@lru_cache(maxsize=4)
def _compiler_facts_cached(
    root_text: str, normalized_addresses: tuple[tuple[str, str], ...]
) -> dict[str, object]:
    root = Path(root_text)
    module_addresses = dict(normalized_addresses)
    unlinked_output = _compile_forge_source_units(root, {})
    compiler_libraries = {FORGE_REFINANCE_SOURCE: module_addresses}
    linked_output = _compile_forge_source_units(root, compiler_libraries)
    snapshot = _read_json(root / linked_checker.STORAGE_SNAPSHOT)
    validation_view = cast(Mapping[str, Any], _linked_checker_source_view(unlinked_output))
    try:
        linked_checker.validate_compiler_output(
            validation_view, coordinator_storage_snapshot=snapshot
        )
    except linked_checker.LinkedModuleCheckError as error:
        _fail(f"Forge-source-unit linked-module validation failed: {error}")
    unlinked_contracts = unlinked_output.get("contracts", {}).get(FORGE_REFINANCE_SOURCE)
    linked_contracts = linked_output.get("contracts", {}).get(FORGE_REFINANCE_SOURCE)
    if not isinstance(unlinked_contracts, dict) or not isinstance(linked_contracts, dict):
        _fail("refinance compiler artifacts are missing")
    artifacts: dict[str, dict[str, object]] = {}
    for module in linked_checker.MODULES:
        artifact = linked_contracts.get(module)
        if not isinstance(artifact, dict):
            _fail(f"{module} compiler artifact is missing")
        evm = artifact.get("evm")
        if not isinstance(evm, dict):
            _fail(f"{module} EVM artifact is missing")
        creation = cast(dict[str, object], evm["bytecode"])
        runtime = cast(dict[str, object], evm["deployedBytecode"])
        artifacts[module] = {
            "creation": _artifact_object(creation.get("object"), f"{module} creation"),
            "runtime": _artifact_object(runtime.get("object"), f"{module} runtime"),
        }
    coordinator = unlinked_contracts.get(linked_checker.COORDINATOR)
    if not isinstance(coordinator, dict) or not isinstance(coordinator.get("evm"), dict):
        _fail("coordinator compiler artifact is missing")
    coordinator_evm = cast(dict[str, Any], coordinator["evm"])
    creation = cast(dict[str, object], coordinator_evm["bytecode"])
    runtime = cast(dict[str, object], coordinator_evm["deployedBytecode"])
    creation_links = _link_entries(creation.get("linkReferences", {}))
    runtime_links = _link_entries(runtime.get("linkReferences", {}))
    linked_creation, linked_runtime = _compiler_artifact(
        linked_output, FORGE_REFINANCE_SOURCE, linked_checker.COORDINATOR
    )
    reproduced_creation = _link_hex(creation.get("object"), creation_links, module_addresses)
    reproduced_runtime = _link_hex(runtime.get("object"), runtime_links, module_addresses)
    if _executable_prefix(
        reproduced_creation, "reproduced coordinator creation"
    ) != _executable_prefix(linked_creation, "compiler-linked coordinator creation"):
        _fail("compiler-linked coordinator creation executable drifted from seven-link proof")
    if _executable_prefix(
        reproduced_runtime, "reproduced coordinator runtime"
    ) != _executable_prefix(linked_runtime, "compiler-linked coordinator runtime"):
        _fail("compiler-linked coordinator runtime executable drifted from seven-link proof")
    artifacts[linked_checker.COORDINATOR] = {
        "creation_hex": creation.get("object"),
        "runtime_hex": runtime.get("object"),
        "creation_links": creation_links,
        "runtime_links": runtime_links,
        "linked_creation": linked_creation,
        "linked_runtime": linked_runtime,
        "reproduced_creation_executable_hash": _keccak(
            _executable_prefix(reproduced_creation, "reproduced coordinator creation")
        ),
        "reproduced_runtime_executable_hash": _keccak(
            _executable_prefix(reproduced_runtime, "reproduced coordinator runtime")
        ),
    }
    for contract, source in ARTIFACT_SOURCES.items():
        creation_bytes, runtime_bytes = _compiler_artifact(linked_output, source, contract)
        artifacts[contract] = {
            "creation": creation_bytes,
            "runtime": runtime_bytes,
            "immutable_offsets": _immutable_offsets(linked_output, source, contract),
        }
    source_set_sha256, source_count = _source_set_facts(root, linked_output)
    if _source_set_facts(root, unlinked_output) != (source_set_sha256, source_count):
        _fail("linked and unlinked compiler source sets differ")
    return {
        "compiler": {
            "solidity": linked_checker.SOLC_VERSION,
            "openzeppelin": linked_checker.OPENZEPPELIN_VERSION,
            "settings": linked_checker.COMPILER_SETTINGS,
            "remappings": linked_output.get("compilerRemappings"),
            "source_set_sha256": source_set_sha256,
            "source_count": source_count,
        },
        "artifacts": artifacts,
    }


def _constructor(
    key: str, config: Mapping[str, object], addresses: Mapping[str, str]
) -> tuple[list[str], list[object], bytes]:
    address_fields: list[str]
    values: list[object]
    if key == "lien_registry":
        address_fields = ["refinance_coordinator"]
        values = [addresses[address_fields[0]]]
    elif key == "collateral_custody":
        address_fields = ["asset_registry", "lien_registry", "emergency_controller"]
        values = [
            config["asset_registry"],
            addresses["lien_registry"],
            config["emergency_controller"],
        ]
    elif key in {"loan_account_implementation", "position_manager_implementation"}:
        return [], [], b""
    elif key == "phase9_loan_factory":
        address_fields = [
            "loan_registry",
            "loan_account_implementation",
            "position_manager_implementation",
            "quote_policy_registry",
            "refinance_policy_registry",
            "amendment_policy_registry",
            "protection_policy_registry",
            "recovery_policy_registry",
        ]
        values = [config.get(field, addresses.get(field)) for field in address_fields]
    elif key in {"validation_module", "request_module", "lifecycle_module"}:
        return [], [], b""
    elif key == "payoff_quote_engine":
        address_fields = [
            "loan_registry",
            "quote_policy_registry",
            "phase9_loan_factory",
            "refinance_coordinator",
        ]
        values = [
            config["loan_registry"],
            config["quote_policy_registry"],
            config["maximum_quote_validity"],
            addresses["phase9_loan_factory"],
            addresses["refinance_coordinator"],
        ]
        types = ["address", "address", "uint64", "address", "address"]
        encoded = b"".join(
            _word_uint(cast(int, value)) if kind == "uint64" else _word_address(cast(str, value))
            for kind, value in zip(types, values, strict=True)
        )
        return types, values, encoded
    elif key == "refinance_coordinator":
        address_fields = [
            "loan_registry",
            "phase9_loan_factory",
            "payoff_quote_engine",
            "lien_registry",
            "asset_registry",
            "refinance_policy_registry",
            "emergency_controller",
            "treasury_fee_recipient",
            "settlement_token",
        ]
        values = [config.get(field, addresses.get(field)) for field in address_fields]
    else:
        _fail(f"unknown deployment key: {key}")
    if any(not isinstance(value, str) for value in values):
        _fail(f"{key} constructor address resolution failed")
    return (
        ["address"] * len(values),
        values,
        b"".join(_word_address(cast(str, value)) for value in values),
    )


def _storage_expectations(
    config: Mapping[str, object], addresses: Mapping[str, str]
) -> list[dict[str, object]]:
    def word(address: object) -> str:
        return "0x" + _word_address(cast(str, address)).hex()

    validity = cast(int, config["maximum_quote_validity"])
    packed_policy = int(cast(str, config["quote_policy_registry"]), 16) | (validity << 160)
    packed_recovery = int(cast(str, config["recovery_policy_registry"]), 16) | (1 << 160)
    values: list[tuple[str, int, str]] = [
        ("lien_registry", 0, word(addresses["refinance_coordinator"])),
        ("collateral_custody", 0, word(config["asset_registry"])),
        ("collateral_custody", 1, word(addresses["lien_registry"])),
        ("collateral_custody", 2, word(config["emergency_controller"])),
        ("loan_account_implementation", 37, "0x" + f"{1:064x}"),
        ("position_manager_implementation", 13, "0x" + f"{1:064x}"),
        ("phase9_loan_factory", 0, word(config["loan_registry"])),
        ("phase9_loan_factory", 1, word(addresses["loan_account_implementation"])),
        ("phase9_loan_factory", 2, word(addresses["position_manager_implementation"])),
        ("phase9_loan_factory", 3, word(config["quote_policy_registry"])),
        ("phase9_loan_factory", 4, word(config["refinance_policy_registry"])),
        ("phase9_loan_factory", 5, word(config["amendment_policy_registry"])),
        ("phase9_loan_factory", 6, word(config["protection_policy_registry"])),
        ("phase9_loan_factory", 7, "0x" + f"{packed_recovery:064x}"),
        ("payoff_quote_engine", 0, word(config["loan_registry"])),
        ("payoff_quote_engine", 1, "0x" + f"{packed_policy:064x}"),
        ("payoff_quote_engine", 2, word(addresses["phase9_loan_factory"])),
        ("payoff_quote_engine", 3, word(addresses["refinance_coordinator"])),
    ]
    coordinator_values = [
        config["loan_registry"],
        addresses["phase9_loan_factory"],
        addresses["payoff_quote_engine"],
        addresses["lien_registry"],
        config["asset_registry"],
        config["refinance_policy_registry"],
        config["emergency_controller"],
        config["treasury_fee_recipient"],
        config["settlement_token"],
    ]
    values.extend(
        ("refinance_coordinator", slot, word(value))
        for slot, value in enumerate(coordinator_values)
    )
    return [
        {"deployment": deployment, "slot": slot, "value": value}
        for deployment, slot, value in values
    ]


def build_plan(
    config_payload: Mapping[str, object],
    broadcaster_value: object,
    reset_identity_value: object,
    *,
    root: Path = ROOT,
    generated_at: str | None = None,
    reset_command: str = DEFAULT_RESET_COMMAND,
    nonce_transcript: Mapping[str, object] | None = None,
    pre_broadcast_block: Mapping[str, object] | None = None,
    source_commit: str | None = None,
    working_tree_clean: bool | None = None,
) -> dict[str, object]:
    config = _validate_config(config_payload)
    broadcaster = _address(broadcaster_value, "broadcaster")
    reset_identity = _bytes32(reset_identity_value, "reset_identity")
    if not reset_identity.startswith("0x"):
        _fail("reset_identity must be the canonical block-zero hash")
    observed_commit, observed_clean = _git_identity(root)
    commit = observed_commit if source_commit is None else source_commit
    clean = observed_clean if working_tree_clean is None else working_tree_clean
    if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        _fail("source_commit must be an exact lowercase Git commit")
    if commit != observed_commit:
        _fail("prepared source_commit does not match current HEAD")
    if clean is not True or observed_clean is not True:
        _fail("tracked or untracked source worktree changes are forbidden")
    timestamp = generated_at or datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", timestamp) is None:
        _fail("generated_at must be canonical UTC seconds")
    if not isinstance(reset_command, str) or not reset_command.strip():
        _fail("reset_command must be nonempty")
    transcript = dict(
        nonce_transcript
        or {
            "latest_before": "0x0",
            "pending_before": "0x0",
            "preparation_method": "anvil_setNonce",
            "preparation_value": "0x1",
            "preparation_result": None,
            "latest_prepared": "0x1",
            "pending_prepared": "0x1",
        }
    )
    expected_transcript = {
        "latest_before": "0x0",
        "pending_before": "0x0",
        "preparation_method": "anvil_setNonce",
        "preparation_value": "0x1",
        "preparation_result": None,
        "latest_prepared": "0x1",
        "pending_prepared": "0x1",
    }
    if transcript != expected_transcript:
        _fail("broadcaster nonce preparation transcript drifted")
    prepared_block = dict(pre_broadcast_block or {"number": "0x0", "hash": "0x" + "11" * 32})
    if set(prepared_block) != {"number", "hash"}:
        _fail("pre_broadcast_block fields drifted")
    _quantity(prepared_block["number"], "pre_broadcast_block.number")
    _bytes32(prepared_block["hash"], "pre_broadcast_block.hash")
    addresses = {
        key: _create_address(broadcaster, nonce)
        for nonce, (key, _contract, _source) in enumerate(SEQUENCE, start=1)
    }
    module_addresses = {
        linked_checker.VALIDATION_MODULE: addresses["validation_module"],
        linked_checker.REQUEST_MODULE: addresses["request_module"],
        linked_checker.LIFECYCLE_MODULE: addresses["lifecycle_module"],
    }
    facts = _compiler_facts(root, module_addresses)
    artifacts = cast(dict[str, dict[str, object]], facts["artifacts"])
    coordinator = artifacts[linked_checker.COORDINATOR]
    creation_links = cast(list[dict[str, object]], coordinator["creation_links"])
    runtime_links = cast(list[dict[str, object]], coordinator["runtime_links"])
    for entries, label in ((creation_links, "creation"), (runtime_links, "runtime")):
        counts = {
            module: sum(1 for entry in entries if entry["library"] == module)
            for module in linked_checker.MODULES
        }
        if counts != EXPECTED_LINK_COUNTS or len(entries) != 7:
            _fail(f"coordinator {label} link inventory drifted")
    linked_creation = cast(bytes, coordinator["linked_creation"])
    linked_runtime = cast(bytes, coordinator["linked_runtime"])

    runtime_by_key: dict[str, bytes] = {}
    creation_by_key: dict[str, bytes] = {}
    for key, contract, _source in SEQUENCE:
        artifact = artifacts[contract]
        if key in {"validation_module", "request_module", "lifecycle_module"}:
            creation_by_key[key] = cast(bytes, artifact["creation"])
            runtime_by_key[key] = _patched_module_runtime(
                cast(bytes, artifact["runtime"]), addresses[key]
            )
        elif key == "refinance_coordinator":
            creation_by_key[key] = linked_creation
            runtime_by_key[key] = linked_runtime
        else:
            creation_by_key[key] = cast(bytes, artifact["creation"])
            runtime_by_key[key] = cast(bytes, artifact["runtime"])

    transactions: list[dict[str, object]] = []
    for nonce, (key, contract, source) in enumerate(SEQUENCE, start=1):
        constructor_types, constructor_values, constructor_bytes = _constructor(
            key, config, addresses
        )
        creation_input = creation_by_key[key] + constructor_bytes
        runtime = runtime_by_key[key]
        if len(runtime) > EIP_170_LIMIT:
            _fail(f"{contract} runtime exceeds EIP-170")
        if len(creation_input) > EIP_3860_LIMIT:
            _fail(f"{contract} initcode exceeds EIP-3860")
        transactions.append(
            {
                "ordinal": nonce,
                "nonce": nonce,
                "sender": broadcaster,
                "value": 0,
                "deployment": key,
                "contract": contract,
                "source": source,
                "artifact": DEPLOYMENT_ARTIFACT_PATHS[contract],
                "source_sha256": _file_sha256(root / source),
                "predicted_address": addresses[key],
                "constructor_types": constructor_types,
                "constructor_values": constructor_values,
                "constructor_bytes": len(constructor_bytes),
                "creation_code_hash": _keccak(creation_by_key[key]),
                "creation_input_hash": _keccak(creation_input),
                "initcode_bytes": len(creation_input),
                "runtime_code_hash": _keccak(runtime),
                "runtime_bytes": len(runtime),
            }
        )

    modules: dict[str, object] = {}
    for key, module in (
        ("validation_module", linked_checker.VALIDATION_MODULE),
        ("request_module", linked_checker.REQUEST_MODULE),
        ("lifecycle_module", linked_checker.LIFECYCLE_MODULE),
    ):
        template = cast(bytes, artifacts[module]["runtime"])
        patched = runtime_by_key[key]
        modules[key] = {
            "contract": module,
            "address": addresses[key],
            "self_patch_offset": SELF_PATCH_OFFSET,
            "self_patch_length": SELF_PATCH_LENGTH,
            "template_runtime_code_hash": _keccak(template),
            "patched_runtime_code_hash": _keccak(patched),
            "runtime_bytes": len(patched),
        }

    plan: dict[str, object] = {
        "schema_version": 1,
        "artifact_type": "PHASE9_REFINANCE_DEPLOYMENT_PLAN",
        "environment": "local",
        "contains_real_value": False,
        "chain_id": CHAIN_ID,
        "activation_accepted": False,
        "topology_only": True,
        "topology_verified": False,
        "role_grant_performed": False,
        "source_commit": commit,
        "working_tree_clean": True,
        "generated_at": timestamp,
        "broadcaster": broadcaster,
        "starting_nonce": 1,
        "final_nonce": 11,
        "reset_identity": reset_identity,
        "reset_command": reset_command,
        "nonce_transcript": transcript,
        "pre_broadcast_block": prepared_block,
        "configuration_hash": _configuration_hash(config, broadcaster),
        "configuration": config,
        "addresses": addresses,
        "compiler": facts["compiler"],
        "forge_libraries": [
            {
                "source": "src/resolution/RefinanceCoordinator.sol",
                "library": module,
                "address": module_addresses[module],
            }
            for module in linked_checker.MODULES
        ],
        "forge_libraries_arguments": [
            "src/resolution/RefinanceCoordinator.sol:" + module + ":" + module_addresses[module]
            for module in linked_checker.MODULES
        ],
        "transactions": transactions,
        "modules": modules,
        "coordinator_links": {
            "creation": {
                "entries": creation_links,
                "linked_code_hash": _keccak(linked_creation),
                "linked_bytes": len(linked_creation),
                "reproduced_executable_hash": coordinator["reproduced_creation_executable_hash"],
            },
            "runtime": {
                "entries": runtime_links,
                "linked_code_hash": _keccak(linked_runtime),
                "linked_bytes": len(linked_runtime),
                "reproduced_executable_hash": coordinator["reproduced_runtime_executable_hash"],
            },
        },
        "storage_expectations": _storage_expectations(config, addresses),
    }
    plan["plan_sha256"] = _sha256(plan)
    return plan


def _validate_schema(payload: Mapping[str, object], schema_path: Path, label: str) -> None:
    schema = _read_json(schema_path)
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.validate(payload, schema)
    except jsonschema.ValidationError as error:
        _fail(f"{label} does not satisfy schema: {error.message}")


def _block_reference(block_hash: str) -> dict[str, object]:
    return {"blockHash": block_hash, "requireCanonical": True}


def _rpc_mapping(value: object, label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        _fail(f"{label} is missing")
    return cast(Mapping[str, Any], value)


def _broadcast_rows(
    payload: Mapping[str, Any],
) -> tuple[list[Mapping[str, Any]], list[Mapping[str, Any]]]:
    transactions = payload.get("transactions")
    receipts = payload.get("receipts")
    if not isinstance(transactions, list) or len(transactions) != 10:
        _fail("broadcast must contain exactly ten transactions")
    if not isinstance(receipts, list) or len(receipts) != 10:
        _fail("broadcast must contain exactly ten receipts")
    if not all(isinstance(row, dict) for row in transactions + receipts):
        _fail("broadcast rows must be objects")
    return cast(list[Mapping[str, Any]], transactions), cast(list[Mapping[str, Any]], receipts)


def _expected_inputs(
    plan: Mapping[str, Any], *, root: Path = ROOT
) -> tuple[dict[str, bytes], dict[str, bytes], dict[str, bytes]]:
    recomputed = build_plan(
        cast(Mapping[str, object], plan["configuration"]),
        plan["broadcaster"],
        plan["reset_identity"],
        root=root,
        generated_at=cast(str, plan["generated_at"]),
        reset_command=cast(str, plan["reset_command"]),
        nonce_transcript=cast(Mapping[str, object], plan["nonce_transcript"]),
        pre_broadcast_block=cast(Mapping[str, object], plan["pre_broadcast_block"]),
        source_commit=cast(str, plan["source_commit"]),
        working_tree_clean=True,
    )
    if recomputed != plan:
        _fail("deployment plan is stale or noncanonical")
    addresses = cast(dict[str, str], plan["addresses"])
    module_addresses = {
        linked_checker.VALIDATION_MODULE: addresses["validation_module"],
        linked_checker.REQUEST_MODULE: addresses["request_module"],
        linked_checker.LIFECYCLE_MODULE: addresses["lifecycle_module"],
    }
    facts = _compiler_facts(root, module_addresses)
    artifacts = cast(dict[str, dict[str, object]], facts["artifacts"])
    coordinator = artifacts[linked_checker.COORDINATOR]
    linked_creation = cast(bytes, coordinator["linked_creation"])
    linked_runtime = cast(bytes, coordinator["linked_runtime"])
    inputs: dict[str, bytes] = {}
    runtimes: dict[str, bytes] = {}
    for key, contract, _source in SEQUENCE:
        artifact = artifacts[contract]
        _types, _values, constructor = _constructor(
            key,
            cast(Mapping[str, object], plan["configuration"]),
            addresses,
        )
        if key in {"validation_module", "request_module", "lifecycle_module"}:
            creation = cast(bytes, artifact["creation"])
            runtime = _patched_module_runtime(cast(bytes, artifact["runtime"]), addresses[key])
        elif key == "refinance_coordinator":
            creation, runtime = linked_creation, linked_runtime
        else:
            creation = cast(bytes, artifact["creation"])
            runtime = cast(bytes, artifact["runtime"])
        inputs[key] = creation + constructor
        runtimes[key] = runtime
    role_manager_word = _word_address(cast(str, plan["configuration"]["role_manager"]))
    dependency_runtimes = {
        field: _patch_immutable_words(
            cast(bytes, artifacts[contract]["runtime"]),
            cast(Sequence[int], artifacts[contract].get("immutable_offsets", [])),
            role_manager_word,
        )
        for field, contract in DEPENDENCY_CONTRACTS.items()
    }
    return inputs, runtimes, dependency_runtimes


def verify(
    plan: Mapping[str, Any],
    candidate: Mapping[str, Any],
    broadcast: Mapping[str, Any],
    rpc: RpcCall,
    *,
    rpc_url: str,
    root: Path = ROOT,
) -> dict[str, object]:
    canonical_url = canonical_rpc_url(rpc_url)
    if rpc("eth_chainId", []) != "0x7a69":
        _fail("RPC eth_chainId must be canonical 0x7a69")
    _validate_schema(plan, root / PLAN_SCHEMA_RELATIVE, "plan")
    _validate_schema(candidate, root / CANDIDATE_SCHEMA_RELATIVE, "candidate")
    inputs, runtimes, dependency_runtimes = _expected_inputs(plan, root=root)
    configuration = cast(Mapping[str, object], plan["configuration"])
    expected_transactions_by_key = {
        cast(str, row["deployment"]): row
        for row in cast(list[Mapping[str, object]], plan["transactions"])
    }
    expected_candidate: dict[str, object] = {
        "schema_version": 1,
        "artifact_type": "PHASE9_REFINANCE_DEPLOYMENT_CANDIDATE",
        "environment": "local",
        "contains_real_value": False,
        "chain_id": CHAIN_ID,
        "topology_only": True,
        "topology_verified": False,
        "activation_accepted": False,
        "role_grant_performed": False,
        "post_broadcast_verification_required": True,
        "deployment_history_reverted": False,
        "plan_sha256": plan["plan_sha256"],
        "source_commit": plan["source_commit"],
        "broadcaster": plan["broadcaster"],
        "starting_nonce": 1,
        "final_nonce": 11,
        "reset_identity": plan["reset_identity"],
        "latest_nonce_before": "0x0",
        "pending_nonce_before": "0x0",
        "latest_nonce_prepared": "0x1",
        "pending_nonce_prepared": "0x1",
        "role_manager": configuration["role_manager"],
        "loan_registry": configuration["loan_registry"],
        "settlement_token": configuration["settlement_token"],
        "quote_policy_registry": configuration["quote_policy_registry"],
        "refinance_policy_registry": configuration["refinance_policy_registry"],
        "amendment_policy_registry": configuration["amendment_policy_registry"],
        "protection_policy_registry": configuration["protection_policy_registry"],
        "recovery_policy_registry": configuration["recovery_policy_registry"],
        "asset_registry": configuration["asset_registry"],
        "emergency_controller": configuration["emergency_controller"],
        "treasury_fee_recipient": configuration["treasury_fee_recipient"],
        "maximum_quote_validity": str(configuration["maximum_quote_validity"]),
        "configuration_hash": plan["configuration_hash"],
        "role_before_absent": True,
        "role_after_absent": True,
    }
    for key, address in cast(Mapping[str, str], plan["addresses"]).items():
        expected_candidate[f"predicted_{key}"] = address
        expected_candidate[f"actual_{key}"] = address
        expected_candidate[f"{key}_runtime_code_hash"] = expected_transactions_by_key[key][
            "runtime_code_hash"
        ]
    normalized_candidate = dict(candidate)
    candidate_address_fields = {
        "broadcaster",
        *(CONFIG_FIELDS - {"maximum_quote_validity"}),
        *(
            f"{prefix}_{key}"
            for key, _contract, _source in SEQUENCE
            for prefix in ("predicted", "actual")
        ),
    }
    for field in candidate_address_fields:
        normalized_candidate[field] = _address(candidate.get(field), f"candidate.{field}")
    if normalized_candidate != expected_candidate:
        _fail("candidate does not exactly bind the prepared plan")
    if _quantity(broadcast.get("chain"), "broadcast.chain") != CHAIN_ID:
        _fail("broadcast chain must be 31337")
    tx_rows, receipt_rows = _broadcast_rows(broadcast)
    observations: list[dict[str, object]] = []
    expected_transactions = cast(list[Mapping[str, Any]], plan["transactions"])
    addresses = cast(dict[str, str], plan["addresses"])
    for expected, row, receipt in zip(expected_transactions, tx_rows, receipt_rows, strict=True):
        key = cast(str, expected["deployment"])
        tx_hash = _bytes32(row.get("hash"), f"{key}.transactionHash").replace("sha256:", "0x")
        transaction = _rpc_mapping(row.get("transaction"), f"{key}.broadcast transaction")
        if (
            row.get("transactionType") != "CREATE"
            or row.get("contractName") != expected["contract"]
        ):
            _fail(f"{key} broadcast row identity drifted")
        if (
            _address(row.get("contractAddress"), f"{key}.contractAddress")
            != expected["predicted_address"]
        ):
            _fail(f"{key} broadcast CREATE address mismatch")
        if (
            _address(transaction.get("from"), f"{key}.from") != plan["broadcaster"]
            or transaction.get("to") is not None
            or _quantity(transaction.get("nonce"), f"{key}.nonce") != expected["nonce"]
            or _quantity(transaction.get("chainId"), f"{key}.chainId") != CHAIN_ID
            or _quantity(transaction.get("value"), f"{key}.value") != 0
            or _hex_blob(transaction.get("input"), f"{key}.input") != inputs[key]
        ):
            _fail(f"{key} broadcast transaction mismatch")
        rpc_tx = _rpc_mapping(rpc("eth_getTransactionByHash", [tx_hash]), f"{key} RPC transaction")
        if _bytes32(rpc_tx.get("hash"), f"{key}.rpc.hash").replace("sha256:", "0x") != tx_hash:
            _fail(f"{key} RPC transaction hash mismatch")
        if _address(rpc_tx.get("from"), f"{key}.rpc.from") != plan["broadcaster"]:
            _fail(f"{key} RPC transaction sender mismatch")
        if rpc_tx.get("to") is not None:
            _fail(f"{key} RPC transaction target mismatch")
        rpc_nonce = _quantity(rpc_tx.get("nonce"), f"{key}.rpc.nonce")
        if rpc_nonce != expected["nonce"]:
            _fail(
                f"{key} RPC transaction nonce mismatch for {tx_hash}: "
                f"observed {rpc_nonce}, expected {expected['nonce']}"
            )
        if _quantity(rpc_tx.get("chainId"), f"{key}.rpc.chainId") != CHAIN_ID:
            _fail(f"{key} RPC transaction chain mismatch")
        if _quantity(rpc_tx.get("value"), f"{key}.rpc.value") != 0:
            _fail(f"{key} RPC transaction value mismatch")
        rpc_input = _hex_blob(rpc_tx.get("input"), f"{key}.rpc.input")
        if rpc_input != inputs[key]:
            _fail(
                f"{key} RPC transaction input mismatch: observed {_keccak(rpc_input)} "
                f"({len(rpc_input)} bytes), expected {_keccak(inputs[key])} "
                f"({len(inputs[key])} bytes)"
            )
        rpc_receipt = _rpc_mapping(
            rpc("eth_getTransactionReceipt", [tx_hash]), f"{key} RPC receipt"
        )
        block_hash = _bytes32(rpc_receipt.get("blockHash"), f"{key}.blockHash").replace(
            "sha256:", "0x"
        )
        block_number = _quantity(rpc_receipt.get("blockNumber"), f"{key}.blockNumber")
        if (
            _quantity(rpc_receipt.get("status"), f"{key}.status") != 1
            or rpc_receipt.get("transactionHash") != tx_hash
            or _address(rpc_receipt.get("contractAddress"), f"{key}.receiptAddress")
            != expected["predicted_address"]
            or _address(rpc_receipt.get("from"), f"{key}.receiptFrom") != plan["broadcaster"]
            or rpc_receipt.get("to") is not None
            or receipt.get("transactionHash") != tx_hash
            or receipt.get("blockHash") != block_hash
            or _quantity(receipt.get("blockNumber"), f"{key}.broadcastBlock") != block_number
            or _quantity(receipt.get("status"), f"{key}.broadcastStatus") != 1
            or _address(receipt.get("contractAddress"), f"{key}.broadcastAddress")
            != expected["predicted_address"]
        ):
            _fail(f"{key} receipt mismatch")
        logs = rpc_receipt.get("logs", [])
        if not isinstance(logs, list) or not all(isinstance(log, dict) for log in logs):
            _fail(f"{key} receipt logs are malformed")
        for log in cast(list[dict[str, object]], logs):
            topics = log.get("topics", [])
            if not isinstance(topics, list):
                _fail(f"{key} receipt log topics are malformed")
            if topics and str(topics[0]).lower() in ROLE_EVENT_TOPICS:
                _fail("candidate topology contains a forbidden role grant/revoke/admin log")
        code = _hex_blob(
            rpc("eth_getCode", [expected["predicted_address"], _block_reference(block_hash)]),
            f"{key}.runtime",
        )
        if code != runtimes[key] or _keccak(code) != expected["runtime_code_hash"]:
            _fail(f"{key} deployed runtime mismatch")
        observations.append(
            {
                "ordinal": expected["ordinal"],
                "nonce": expected["nonce"],
                "deployment": key,
                "address": expected["predicted_address"],
                "transaction_hash": tx_hash,
                "block_hash": block_hash,
                "block_number": block_number,
                "runtime_code_hash": _keccak(code),
                "runtime_bytes": len(code),
            }
        )

    final_block_hash = cast(str, observations[-1]["block_hash"])
    block_reference = _block_reference(final_block_hash)
    for expectation in cast(list[Mapping[str, Any]], plan["storage_expectations"]):
        key = cast(str, expectation["deployment"])
        observed = rpc(
            "eth_getStorageAt",
            [addresses[key], hex(cast(int, expectation["slot"])), block_reference],
        )
        if observed != expectation["value"]:
            _fail(f"{key} constructor storage mismatch at slot {expectation['slot']}")

    role_manager = cast(str, cast(Mapping[str, object], plan["configuration"])["role_manager"])
    prepared_block = cast(Mapping[str, object], plan["pre_broadcast_block"])
    prepared_hash = cast(str, prepared_block["hash"])
    prepared_number = cast(str, prepared_block["number"])
    by_hash = _rpc_mapping(
        rpc("eth_getBlockByHash", [prepared_hash, False]), "pre-broadcast block by hash"
    )
    by_number = _rpc_mapping(
        rpc("eth_getBlockByNumber", [prepared_number, False]),
        "pre-broadcast block by number",
    )
    if (
        by_hash.get("hash") != prepared_hash
        or by_hash.get("number") != prepared_number
        or by_number.get("hash") != prepared_hash
        or by_number.get("number") != prepared_number
    ):
        _fail("pre-broadcast block is no longer canonical")
    genesis = _rpc_mapping(rpc("eth_getBlockByNumber", ["0x0", False]), "reset genesis block")
    if (
        genesis.get("number") != "0x0"
        or _bytes32(genesis.get("hash"), "reset genesis block hash") != plan["reset_identity"]
    ):
        _fail("reset_identity does not match the canonical block-zero hash")
    prepared_reference = _block_reference(prepared_hash)
    broadcaster_code = _hex_blob(
        rpc("eth_getCode", [plan["broadcaster"], prepared_reference]),
        "broadcaster.pre_broadcast.code",
    )
    if broadcaster_code:
        _fail("broadcaster must have no code before candidate deployment")
    for field in sorted(CODE_DEPENDENCY_FIELDS):
        dependency_code = _hex_blob(
            rpc("eth_getCode", [configuration[field], prepared_reference]),
            f"configuration.{field}.pre_broadcast.code",
        )
        if not dependency_code:
            _fail(f"configuration.{field} must contain code before broadcast")
        if dependency_code != dependency_runtimes[field]:
            _fail(
                f"configuration.{field} runtime does not match the canonical fixture: "
                f"observed {_keccak(dependency_code)} ({len(dependency_code)} bytes), "
                f"expected {_keccak(dependency_runtimes[field])} "
                f"({len(dependency_runtimes[field])} bytes)"
            )
    role_call_suffix = LOAN_FACTORY_ROLE + _word_address(addresses["phase9_loan_factory"])
    role_absence: dict[str, object] = {}
    for label, role_block_hash in (
        ("before", prepared_hash),
        ("after", final_block_hash),
    ):
        reference = _block_reference(role_block_hash)
        role_code = _hex_blob(
            rpc("eth_getCode", [role_manager, reference]), f"role_manager.{label}.code"
        )
        if not role_code:
            _fail(f"role manager has no code at {label} observation")
        expiry = _hex_blob(
            rpc(
                "eth_call",
                [
                    {
                        "to": role_manager,
                        "data": "0x" + (ROLE_EXPIRY_SELECTOR + role_call_suffix).hex(),
                    },
                    reference,
                ],
            ),
            f"role_manager.{label}.roleExpiry",
        )
        has_role = _hex_blob(
            rpc(
                "eth_call",
                [
                    {
                        "to": role_manager,
                        "data": "0x" + (HAS_ROLE_SELECTOR + role_call_suffix).hex(),
                    },
                    reference,
                ],
            ),
            f"role_manager.{label}.hasRole",
        )
        if expiry != bytes(32) or has_role != bytes(32):
            _fail("loan factory role must remain absent before and after candidate deployment")
        role_absence[label] = {
            "block_hash": role_block_hash,
            "role_expiry": "0",
            "has_role": False,
        }

    final_latest = rpc("eth_getTransactionCount", [plan["broadcaster"], "latest"])
    final_pending = rpc("eth_getTransactionCount", [plan["broadcaster"], "pending"])
    if final_latest != "0xb" or final_pending != "0xb":
        _fail("broadcaster final latest and pending nonces must both be canonical 0xb")

    evidence: dict[str, object] = {
        "schema_version": 1,
        "artifact_type": "PHASE9_REFINANCE_TOPOLOGY_EVIDENCE",
        "environment": "local",
        "contains_real_value": False,
        "chain_id": CHAIN_ID,
        "topology_only": True,
        "topology_verified": True,
        "activation_accepted": False,
        "role_grant_performed": False,
        "post_broadcast_verification_required": False,
        "deployment_history_reverted": False,
        "plan_sha256": plan["plan_sha256"],
        "source_commit": plan["source_commit"],
        "working_tree_clean": True,
        "generated_at": plan["generated_at"],
        "broadcaster": plan["broadcaster"],
        "starting_nonce": 1,
        "final_nonce": 11,
        "reset_identity": plan["reset_identity"],
        "reset_command": plan["reset_command"],
        "nonce_transcript": {
            **cast(Mapping[str, object], plan["nonce_transcript"]),
            "latest_final": "0xb",
            "pending_final": "0xb",
        },
        "rpc_url": canonical_url,
        "rpc_chain_id": "0x7a69",
        "addresses": plan["addresses"],
        "observations": observations,
        "modules": plan["modules"],
        "coordinator_links": plan["coordinator_links"],
        "role_absence": role_absence,
    }
    _validate_schema(evidence, root / EVIDENCE_SCHEMA_RELATIVE, "evidence")
    return evidence


def _canonical_output(path: Path, relative: Path, *, must_exist: bool) -> Path:
    if ".." in path.parts:
        _fail(f"path must not contain traversal: {relative.as_posix()}")
    expected = Path(os.path.abspath(ROOT / relative))
    supplied = Path(os.path.abspath(path))
    if os.path.normcase(os.fspath(supplied)) != os.path.normcase(os.fspath(expected)):
        _fail(f"path must be canonical: {relative.as_posix()}")
    _reject_reparse_components(expected)
    if must_exist and not expected.is_file():
        _fail(f"required canonical file is missing: {relative.as_posix()}")
    if not must_exist and expected.exists() and not expected.is_file():
        _fail(f"canonical output is not a regular file: {relative.as_posix()}")
    return expected


def _path_is_reparse(path: Path) -> bool:
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return False
    except OSError as error:
        _fail(f"cannot inspect canonical path component {path}: {error}")
    windows_attributes = cast(int, getattr(metadata, "st_file_attributes", 0))
    return stat.S_ISLNK(metadata.st_mode) or bool(windows_attributes & 0x400)


def _reject_reparse_components(path: Path) -> None:
    if not path.is_absolute():
        _fail("canonical path inspection requires an absolute path")
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        if _path_is_reparse(current):
            _fail(f"canonical path contains a symlink or reparse point: {current}")


def _remove_canonical_output(path: Path) -> None:
    _reject_reparse_components(path)
    try:
        path.unlink(missing_ok=True)
    except OSError as error:
        _fail(f"cannot remove stale canonical evidence {path}: {error}")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--broadcaster")
    parser.add_argument("--reset-identity")
    parser.add_argument("--reset-command", default=DEFAULT_RESET_COMMAND)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--broadcast", type=Path)
    parser.add_argument("--rpc-url")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(list(argv) if argv is not None else None)
    evidence_output: Path | None = None
    try:
        if args.prepare:
            if None in {
                args.config,
                args.broadcaster,
                args.reset_identity,
                args.plan,
                args.rpc_url,
            }:
                parser.error(
                    "--prepare requires config, broadcaster, reset-identity, plan, and rpc-url"
                )
            rpc = HttpRpc(cast(str, args.rpc_url))
            if rpc("eth_chainId", []) != "0x7a69":
                _fail("RPC eth_chainId must be canonical 0x7a69")
            broadcaster = _address(args.broadcaster, "broadcaster")
            latest_before = rpc("eth_getTransactionCount", [broadcaster, "latest"])
            pending_before = rpc("eth_getTransactionCount", [broadcaster, "pending"])
            if latest_before != "0x0" or pending_before != "0x0":
                _fail("fresh broadcaster latest and pending nonces must both be canonical 0x0")
            preparation_result = rpc("anvil_setNonce", [broadcaster, "0x1"])
            if preparation_result is not None:
                _fail("anvil_setNonce must return canonical null")
            latest_prepared = rpc("eth_getTransactionCount", [broadcaster, "latest"])
            pending_prepared = rpc("eth_getTransactionCount", [broadcaster, "pending"])
            if latest_prepared != "0x1" or pending_prepared != "0x1":
                _fail("prepared broadcaster latest and pending nonces must both be canonical 0x1")
            block = _rpc_mapping(
                rpc("eth_getBlockByNumber", ["latest", False]),
                "prepared latest block",
            )
            block_hash = _bytes32(block.get("hash"), "prepared block hash").replace("sha256:", "0x")
            block_number_raw = block.get("number")
            _quantity(block_number_raw, "prepared block number")
            if not isinstance(block_number_raw, str):
                _fail("prepared block number must be a canonical RPC quantity")
            plan = build_plan(
                _read_json(cast(Path, args.config)),
                broadcaster,
                args.reset_identity,
                reset_command=cast(str, args.reset_command),
                nonce_transcript={
                    "latest_before": latest_before,
                    "pending_before": pending_before,
                    "preparation_method": "anvil_setNonce",
                    "preparation_value": "0x1",
                    "preparation_result": preparation_result,
                    "latest_prepared": latest_prepared,
                    "pending_prepared": pending_prepared,
                },
                pre_broadcast_block={
                    "number": block_number_raw,
                    "hash": block_hash,
                },
            )
            _validate_schema(plan, ROOT / PLAN_SCHEMA_RELATIVE, "plan")
            output = _canonical_output(cast(Path, args.plan), PLAN_RELATIVE, must_exist=False)
            _write_json(output, plan)
            print("\n".join(cast(list[str], plan["forge_libraries_arguments"])))
            return 0

        if None in {args.plan, args.candidate, args.broadcast, args.rpc_url, args.output}:
            parser.error("--verify requires plan, candidate, broadcast, rpc-url, and output")
        evidence_output = _canonical_output(
            cast(Path, args.output), EVIDENCE_RELATIVE, must_exist=False
        )
        _remove_canonical_output(evidence_output)
        plan_path = _canonical_output(cast(Path, args.plan), PLAN_RELATIVE, must_exist=True)
        candidate_path = _canonical_output(
            cast(Path, args.candidate), CANDIDATE_RELATIVE, must_exist=True
        )
        broadcast_path = _canonical_output(
            cast(Path, args.broadcast), BROADCAST_RELATIVE, must_exist=True
        )
        if "dry-run" in {part.lower() for part in broadcast_path.parts}:
            _fail("dry-run broadcast artifacts cannot produce topology evidence")
        evidence = verify(
            _read_json(plan_path),
            _read_json(candidate_path),
            _read_json(broadcast_path),
            HttpRpc(cast(str, args.rpc_url)),
            rpc_url=cast(str, args.rpc_url),
        )
        _write_json(evidence_output, evidence)
        print(f"Phase 9 refinance topology evidence written: {evidence_output}")
        return 0
    except VerificationError as error:
        if evidence_output is not None:
            try:
                _remove_canonical_output(evidence_output)
            except VerificationError as cleanup_error:
                print(
                    f"Phase 9 refinance evidence cleanup failed: {cleanup_error}",
                    file=sys.stderr,
                )
        print(f"Phase 9 refinance deployment verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
