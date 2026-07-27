#!/usr/bin/env python3
"""Fail-closed static gate for the ADR 0023 refinance linked modules."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final, cast

ROOT: Final = Path(__file__).resolve().parents[1]
COMPILATION_SOURCE: Final = "protocol/src/ProtocolCompilation.sol"
REFINANCE_SOURCE: Final = "protocol/src/resolution/RefinanceCoordinator.sol"
STORAGE_SNAPSHOT: Final = Path(
    "protocol/storage-layout/phase9/RefinanceCoordinator.storage.json"
)
COORDINATOR: Final = "RefinanceCoordinator"
VALIDATION_MODULE: Final = "Phase9RefinanceValidationModule"
REQUEST_MODULE: Final = "Phase9RefinanceRequestModule"
LIFECYCLE_MODULE: Final = "Phase9RefinanceLifecycleModule"
MODULES: Final = (VALIDATION_MODULE, REQUEST_MODULE, LIFECYCLE_MODULE)
EIP_170_LIMIT: Final = 24_576
MAX_VALIDATION_PLAN_BYTES: Final = 22_272
SOLC_VERSION: Final = "0.8.36+commit.8a079791.Emscripten.clang"
OPENZEPPELIN_VERSION: Final = "5.6.1"
COMPILER_SETTINGS: Final = {
    "evmVersion": "prague",
    "optimizer": {"enabled": True, "runs": 200},
    "viaIR": False,
}

METHOD_IDENTIFIERS: Final = {
    VALIDATION_MODULE: {
        "preflight(Phase9RefinanceValidationContext,Phase9Types.RefinanceRecord)": (
            "4f9ee1ee"
        ),
    },
    REQUEST_MODULE: {
        "begin(Phase9RefinanceStorageLayout storage,Phase9Types.RefinanceRecord)": (
            "3dc005b8"
        ),
        "complete(Phase9RefinanceStorageLayout storage,Phase9Types.RefinanceRecord,bytes)": (
            "0be276bb"
        ),
    },
    LIFECYCLE_MODULE: {
        "cancelRefinance(Phase9RefinanceStorageLayout storage,bytes32,bytes32)": (
            "9521f7f9"
        ),
        "executeRefinance(Phase9RefinanceStorageLayout storage,bytes32,bytes32)": (
            "ec32f45f"
        ),
        "recordFundingCommitment(Phase9RefinanceStorageLayout storage,"
        "Phase9Types.FundingCommitment)": "b145df9d",
        "refundCommitment(Phase9RefinanceStorageLayout storage,bytes32,bytes32)": (
            "8e2b3054"
        ),
    },
}
COORDINATOR_LINK_COUNTS: Final = {
    VALIDATION_MODULE: 1,
    REQUEST_MODULE: 2,
    LIFECYCLE_MODULE: 4,
}
COORDINATOR_CALLS: Final = {
    (VALIDATION_MODULE, "preflight"): 1,
    (REQUEST_MODULE, "begin"): 1,
    (REQUEST_MODULE, "complete"): 1,
    (LIFECYCLE_MODULE, "recordFundingCommitment"): 1,
    (LIFECYCLE_MODULE, "executeRefinance"): 1,
    (LIFECYCLE_MODULE, "cancelRefinance"): 1,
    (LIFECYCLE_MODULE, "refundCommitment"): 1,
}
_FORBIDDEN_YUL_OPERATIONS: Final = {
    "call",
    "callcode",
    "create",
    "create2",
    "delegatecall",
    "log0",
    "log1",
    "log2",
    "log3",
    "log4",
    "selfdestruct",
    "sload",
    "sstore",
}
BOUNDED_STATICCALL_SITES: Final = {
    "_validateRequestEnvironment": [
        ("emergencyState", 96),
        ("resolveRefinanceAsset", 160),
    ],
    "_resolveRefinancePolicy": [("resolveRefinancePolicy", 8_992)],
    "_resolveCreation": [("resolveLoanCreation", 704)],
    "_resolveBootstrap": [("resolveBootstrap", 11_712)],
    "_validateExistingLenderPosition": [("positionIds", 1_088)],
    "_validateFreshCustodyIdentity": [("resolveCustodyAsset", 160)],
    "_requireCollateralAbsent": [("lien", 36)],
    "_accountConfiguration": [("configuration", 608)],
    "_accountDebt": [("debtState", 672)],
    "_position": [("position", 192)],
    "_custody": [("custody", 224)],
    "_lien": [("lien", 352)],
    "_wordCall": [(None, 32)],
}


@dataclass(frozen=True)
class MirrorField:
    name: str
    type_string: str
    slot: int
    offset: int
    size: int
    padding: bool = False


MIRROR_FIELDS: Final = (
    MirrorField("loanRegistry", "address", 0, 0, 20),
    MirrorField("loanRegistryPadding", "uint96", 0, 20, 12, True),
    MirrorField("phase9LoanFactory", "address", 1, 0, 20),
    MirrorField("phase9LoanFactoryPadding", "uint96", 1, 20, 12, True),
    MirrorField("payoffQuoteEngine", "address", 2, 0, 20),
    MirrorField("payoffQuoteEnginePadding", "uint96", 2, 20, 12, True),
    MirrorField("lienRegistry", "address", 3, 0, 20),
    MirrorField("lienRegistryPadding", "uint96", 3, 20, 12, True),
    MirrorField("assetRegistry", "address", 4, 0, 20),
    MirrorField("assetRegistryPadding", "uint96", 4, 20, 12, True),
    MirrorField("policyRegistry", "address", 5, 0, 20),
    MirrorField("policyRegistryPadding", "uint96", 5, 20, 12, True),
    MirrorField("emergencyController", "address", 6, 0, 20),
    MirrorField("emergencyControllerPadding", "uint96", 6, 20, 12, True),
    MirrorField("treasuryFeeRecipient", "address", 7, 0, 20),
    MirrorField("treasuryFeeRecipientPadding", "uint96", 7, 20, 12, True),
    MirrorField("settlementToken", "contract IERC20", 8, 0, 20),
    MirrorField("settlementTokenPadding", "uint96", 8, 20, 12, True),
    MirrorField("nextRefinanceNonce", "mapping(bytes32 => uint64)", 9, 0, 32),
    MirrorField(
        "refinances",
        "mapping(bytes32 => struct Phase9Types.RefinanceRecord)",
        10,
        0,
        32,
    ),
    MirrorField("commitmentIds", "mapping(bytes32 => bytes32[])", 11, 0, 32),
    MirrorField(
        "commitments",
        "mapping(bytes32 => struct Phase9Types.FundingCommitment)",
        12,
        0,
        32,
    ),
    MirrorField("escrowedUnits", "mapping(bytes32 => uint256)", 13, 0, 32),
    MirrorField(
        "terminalResults",
        "mapping(bytes32 => struct Phase9Types.RefinanceTerminalResult)",
        14,
        0,
        32,
    ),
    MirrorField("processedOperationIds", "mapping(bytes32 => bool)", 15, 0, 32),
)
VALIDATION_CONTEXT_FIELDS: Final = (
    ("chainId", "uint256"),
    ("coordinator", "address"),
    ("loanRegistry", "address"),
    ("phase9LoanFactory", "address"),
    ("payoffQuoteEngine", "address"),
    ("lienRegistry", "address"),
    ("assetRegistry", "address"),
    ("policyRegistry", "address"),
    ("emergencyController", "address"),
    ("treasuryFeeRecipient", "address"),
    ("settlementToken", "address"),
    ("activeLock", "uint64"),
)

_PLACEHOLDER = re.compile(r"__\$[0-9a-fA-F]{34}\$__")
_HEX = re.compile(r"[0-9a-fA-F]*")


class LinkedModuleCheckError(RuntimeError):
    """Raised when a linked-module candidate violates ADR 0023."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise LinkedModuleCheckError(message)


def _walk(value: object) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _definitions(source_ast: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    definitions: dict[str, dict[str, Any]] = {}
    for node in source_ast.get("nodes", []):
        if not isinstance(node, dict) or node.get("nodeType") != "ContractDefinition":
            continue
        name = node.get("name")
        if not isinstance(name, str):
            raise LinkedModuleCheckError("contract definition has no name")
        _require(name not in definitions, f"duplicate source-scope definition: {name}")
        definitions[name] = node
    return definitions


def _type_string(declaration: Mapping[str, Any]) -> str:
    descriptions = declaration.get("typeDescriptions")
    if not isinstance(descriptions, dict):
        raise LinkedModuleCheckError("variable declaration lacks type descriptions")
    type_string = descriptions.get("typeString")
    if not isinstance(type_string, str):
        raise LinkedModuleCheckError("variable declaration lacks a compiler type string")
    return type_string


def _validate_mirror(source_ast: Mapping[str, Any]) -> None:
    structs = [
        node
        for node in source_ast.get("nodes", [])
        if isinstance(node, dict)
        and node.get("nodeType") == "StructDefinition"
        and node.get("name") == "Phase9RefinanceStorageLayout"
    ]
    _require(len(structs) == 1, "expected exactly one file-scope Phase9RefinanceStorageLayout")
    members = structs[0].get("members")
    if not isinstance(members, list):
        raise LinkedModuleCheckError("Phase9RefinanceStorageLayout has no members")
    _require(
        len(members) == len(MIRROR_FIELDS),
        "Phase9RefinanceStorageLayout member count does not match ADR 0023",
    )

    padding_ids: set[int] = set()
    next_slot = 0
    next_offset = 0
    for index, (member, expected) in enumerate(zip(members, MIRROR_FIELDS, strict=True)):
        _require(isinstance(member, dict), f"mirror member {index} is malformed")
        _require(member.get("name") == expected.name, f"mirror member {index} name drift")
        _require(
            _type_string(member) == expected.type_string,
            f"mirror member {expected.name} type drift",
        )

        if expected.type_string.startswith("mapping("):
            if next_offset != 0:
                next_slot += 1
                next_offset = 0
            observed_slot, observed_offset = next_slot, 0
            next_slot += 1
        else:
            if next_offset + expected.size > 32:
                next_slot += 1
                next_offset = 0
            observed_slot, observed_offset = next_slot, next_offset
            next_offset += expected.size
            if next_offset == 32:
                next_slot += 1
                next_offset = 0
        _require(
            (observed_slot, observed_offset) == (expected.slot, expected.offset),
            f"mirror member {expected.name} does not pack at slot {expected.slot} "
            f"offset {expected.offset}",
        )
        if expected.padding:
            identifier = member.get("id")
            _require(isinstance(identifier, int), f"padding {expected.name} has no AST id")
            padding_ids.add(identifier)

    for node in _walk(source_ast):
        referenced = node.get("referencedDeclaration")
        if referenced in padding_ids:
            raise LinkedModuleCheckError(
                "padding member is read, written, or otherwise referenced: "
                f"AST declaration {referenced}"
            )


def _validate_validation_context(source_ast: Mapping[str, Any]) -> None:
    contexts = [
        node
        for node in source_ast.get("nodes", [])
        if isinstance(node, dict)
        and node.get("nodeType") == "StructDefinition"
        and node.get("name") == "Phase9RefinanceValidationContext"
    ]
    _require(
        len(contexts) == 1,
        "expected exactly one file-scope Phase9RefinanceValidationContext",
    )
    members = contexts[0].get("members")
    if not isinstance(members, list):
        raise LinkedModuleCheckError("Phase9RefinanceValidationContext has no members")
    observed: list[tuple[str, str]] = []
    for member in members:
        if not isinstance(member, dict) or not isinstance(member.get("name"), str):
            raise LinkedModuleCheckError("Phase9RefinanceValidationContext member is malformed")
        observed.append((str(member["name"]), _type_string(member)))
    _require(
        observed == list(VALIDATION_CONTEXT_FIELDS),
        "Phase9RefinanceValidationContext field inventory drift",
    )


def _validate_plan_cap(source_ast: Mapping[str, Any]) -> None:
    declarations = [
        node
        for node in source_ast.get("nodes", [])
        if isinstance(node, dict)
        and node.get("nodeType") == "VariableDeclaration"
        and node.get("name") == "PHASE9_REFINANCE_MAX_PLAN_BYTES"
    ]
    _require(len(declarations) == 1, "validation-plan byte cap declaration drift")
    declaration = declarations[0]
    value = declaration.get("value")
    _require(
        declaration.get("constant") is True
        and _type_string(declaration) == "uint256"
        and isinstance(value, dict)
        and value.get("nodeType") == "Literal"
        and value.get("kind") == "number"
        and isinstance(value.get("value"), str),
        "validation-plan byte cap declaration is malformed",
    )
    if not isinstance(value, dict) or not isinstance(value.get("value"), str):
        raise LinkedModuleCheckError("validation-plan byte cap declaration is malformed")
    try:
        observed = int(str(value["value"]), 0)
    except ValueError as error:
        raise LinkedModuleCheckError("validation-plan byte cap is not an integer") from error
    _require(
        observed == MAX_VALIDATION_PLAN_BYTES,
        "validation-plan byte cap must remain 22,272 bytes (696 ABI words)",
    )


def _layout_signature(layout: Mapping[str, Any]) -> list[tuple[str, int, int, str]]:
    storage = layout.get("storage")
    types = layout.get("types")
    if not isinstance(storage, list):
        raise LinkedModuleCheckError("coordinator storage layout is malformed")
    if not isinstance(types, dict):
        raise LinkedModuleCheckError("coordinator storage type table is malformed")
    result: list[tuple[str, int, int, str]] = []
    for entry in storage:
        _require(isinstance(entry, dict), "coordinator storage entry is malformed")
        type_id = entry.get("type")
        _require(isinstance(type_id, str), "coordinator storage type id is malformed")
        type_entry = types.get(type_id)
        if not isinstance(type_entry, dict):
            raise LinkedModuleCheckError(f"coordinator storage type is missing: {type_id}")
        label = type_entry.get("label")
        if not isinstance(label, str):
            raise LinkedModuleCheckError(
                f"coordinator storage type has no label: {type_id}"
            )
        result.append(
            (
                str(entry.get("label")),
                int(entry.get("slot")),
                int(entry.get("offset")),
                label,
            )
        )
    return result


def _validate_storage(
    contracts: Mapping[str, Any], snapshot: Mapping[str, Any]
) -> list[tuple[str, int, int, str]]:
    for module in MODULES:
        layout = contracts[module].get("storageLayout")
        _require(isinstance(layout, dict), f"{module}: missing compiler storage layout")
        _require(layout.get("storage") == [], f"{module}: library storage layout is not empty")

    coordinator_layout = contracts[COORDINATOR].get("storageLayout")
    if not isinstance(coordinator_layout, dict):
        raise LinkedModuleCheckError("coordinator storage layout is missing")
    snapshot_layout = snapshot.get("storageLayout")
    if not isinstance(snapshot_layout, dict):
        raise LinkedModuleCheckError("authoritative coordinator snapshot is malformed")
    actual = _layout_signature(coordinator_layout)
    expected = _layout_signature(snapshot_layout)
    _require(
        actual == expected,
        "coordinator storage layout differs from the authoritative snapshot",
    )

    logical = [field for field in MIRROR_FIELDS if not field.padding]
    mirror_signature = [
        (f"_{field.name}", field.slot, field.offset, field.type_string) for field in logical
    ]
    _require(
        actual == mirror_signature,
        "Phase9RefinanceStorageLayout logical fields do not match coordinator slots 0 through 15",
    )
    return actual


def _evm_artifact(contract: Mapping[str, Any], kind: str) -> Mapping[str, Any]:
    evm = contract.get("evm")
    if not isinstance(evm, dict):
        raise LinkedModuleCheckError("compiler EVM output is missing")
    artifact = evm.get(kind)
    if not isinstance(artifact, dict):
        raise LinkedModuleCheckError(f"compiler {kind} output is missing")
    return artifact


def _flatten_links(link_references: object) -> list[tuple[str, str, int, int]]:
    if not isinstance(link_references, dict):
        raise LinkedModuleCheckError("linkReferences is malformed")
    result: list[tuple[str, str, int, int]] = []
    for source_name, libraries in link_references.items():
        _require(isinstance(source_name, str), "link-reference source name is malformed")
        if not isinstance(libraries, dict):
            raise LinkedModuleCheckError("link-reference library map is malformed")
        for library, references in libraries.items():
            _require(isinstance(library, str), "link-reference library name is malformed")
            if not isinstance(references, list):
                raise LinkedModuleCheckError("link-reference offset list is malformed")
            for reference in references:
                if not isinstance(reference, dict):
                    raise LinkedModuleCheckError("link-reference offset is malformed")
                start = reference.get("start")
                length = reference.get("length")
                if not isinstance(start, int) or not isinstance(length, int):
                    raise LinkedModuleCheckError("link-reference start/length is malformed")
                result.append((source_name, library, start, length))
    return result


def _validate_bytecode_links(
    contract_name: str, artifact_name: str, artifact: Mapping[str, Any]
) -> list[tuple[str, str, int, int]]:
    bytecode = artifact.get("object")
    if not isinstance(bytecode, str):
        raise LinkedModuleCheckError(f"{contract_name}: {artifact_name} object is missing")
    _require(len(bytecode) % 2 == 0, f"{contract_name}: {artifact_name} has odd length")
    links = _flatten_links(artifact.get("linkReferences", {}))
    intervals: list[tuple[int, int]] = []
    for source_name, library, start, length in links:
        _require(
            source_name == REFINANCE_SOURCE and library in MODULES,
            f"{contract_name}: undeclared link target {source_name}:{library}",
        )
        _require(length == 20, f"{contract_name}: linked address is not 20 bytes")
        interval = (start * 2, (start + length) * 2)
        _require(interval[1] <= len(bytecode), f"{contract_name}: link offset is out of range")
        _require(interval not in intervals, f"{contract_name}: duplicate link offset")
        _require(
            all(interval[1] <= left or interval[0] >= right for left, right in intervals),
            f"{contract_name}: overlapping link offsets",
        )
        intervals.append(interval)
        _require(
            _PLACEHOLDER.fullmatch(bytecode[interval[0] : interval[1]]) is not None,
            f"{contract_name}: compiler link offset does not contain one unresolved placeholder",
        )

    placeholders = {(match.start(), match.end()) for match in _PLACEHOLDER.finditer(bytecode)}
    _require(
        placeholders == set(intervals),
        f"{contract_name}: bytecode has an unresolved or undeclared link placeholder",
    )
    zeroed = _PLACEHOLDER.sub("0" * 40, bytecode)
    _require(_HEX.fullmatch(zeroed) is not None, f"{contract_name}: bytecode is malformed")
    return links


def _executable_opcode_bytes(bytecode: str) -> list[int]:
    normalized = _PLACEHOLDER.sub("0" * 40, bytecode)
    _require(_HEX.fullmatch(normalized) is not None, "runtime bytecode is malformed")
    raw = bytes.fromhex(normalized)
    if len(raw) >= 2:
        metadata_length = int.from_bytes(raw[-2:], "big")
        metadata_start = len(raw) - metadata_length - 2
        if (
            metadata_length > 0
            and metadata_start >= 0
            and 0xA0 <= raw[metadata_start] <= 0xBF
        ):
            raw = raw[:metadata_start]
    opcodes: list[int] = []
    cursor = 0
    while cursor < len(raw):
        opcode = raw[cursor]
        opcodes.append(opcode)
        cursor += 1
        if 0x60 <= opcode <= 0x7F:
            cursor += opcode - 0x5F
    return opcodes


def _validate_bytecode(contracts: Mapping[str, Any]) -> dict[str, int]:
    sizes: dict[str, int] = {}
    for name in (*MODULES, COORDINATOR):
        contract = contracts[name]
        creation = _evm_artifact(contract, "bytecode")
        runtime = _evm_artifact(contract, "deployedBytecode")
        creation_links = _validate_bytecode_links(name, "creation bytecode", creation)
        runtime_links = _validate_bytecode_links(name, "runtime bytecode", runtime)
        if name in MODULES:
            _require(
                not creation_links and not runtime_links,
                f"{name}: module links another library",
            )
        else:
            for links, artifact_name in (
                (creation_links, "creation bytecode"),
                (runtime_links, "runtime bytecode"),
            ):
                observed_counts = {
                    module: sum(1 for _, library, _, _ in links if library == module)
                    for module in MODULES
                }
                _require(
                    observed_counts == COORDINATOR_LINK_COUNTS
                    and len(links) == sum(COORDINATOR_LINK_COUNTS.values()),
                    f"{COORDINATOR}: {artifact_name} does not contain the exact seven "
                    "ADR 0023 module links",
                )

        runtime_object = runtime.get("object")
        if not isinstance(runtime_object, str):
            raise LinkedModuleCheckError(f"{name}: runtime bytecode is missing")
        sizes[name] = len(runtime_object) // 2
        _require(sizes[name] <= EIP_170_LIMIT, f"{name}: runtime exceeds EIP-170")

        executable_opcodes = _executable_opcode_bytes(runtime_object)
        delegatecalls = executable_opcodes.count(0xF4)
        if name in MODULES:
            _require(delegatecalls == 0, f"{name}: module runtime contains DELEGATECALL")
            if name == VALIDATION_MODULE:
                forbidden_opcodes = {
                    0x54,
                    0x55,
                    0xA0,
                    0xA1,
                    0xA2,
                    0xA3,
                    0xA4,
                    0xF0,
                    0xF1,
                    0xF2,
                    0xF4,
                    0xF5,
                    0xFF,
                }
                _require(
                    not forbidden_opcodes.intersection(executable_opcodes),
                    f"{VALIDATION_MODULE}: executable runtime contains a forbidden opcode",
                )
                _require(
                    executable_opcodes.count(0xFA) >= 1,
                    f"{VALIDATION_MODULE}: executable runtime lacks bounded STATICCALL",
                )
        else:
            _require(
                0 < delegatecalls <= sum(COORDINATOR_LINK_COUNTS.values()),
                f"{COORDINATOR}: delegatecall inventory is not attributable to compiler links",
            )
    return sizes


def _validate_method_identifiers(contracts: Mapping[str, Any]) -> None:
    for module, expected in METHOD_IDENTIFIERS.items():
        evm = contracts[module].get("evm")
        _require(isinstance(evm, dict), f"{module}: EVM output is missing")
        observed = evm.get("methodIdentifiers")
        _require(isinstance(observed, dict), f"{module}: method identifiers are missing")
        _require(observed == expected, f"{module}: public linked-entry allowlist drift")


_PUBLIC_AST_SIGNATURES: Final = {
    VALIDATION_MODULE: {
        "preflight": (
            [
                ("struct Phase9RefinanceValidationContext", "memory"),
                ("struct Phase9Types.RefinanceRecord", "calldata"),
            ],
            [("bytes", "memory")],
        ),
    },
    REQUEST_MODULE: {
        "begin": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("struct Phase9Types.RefinanceRecord", "calldata"),
            ],
            [],
        ),
        "complete": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("struct Phase9Types.RefinanceRecord", "calldata"),
                ("bytes", "memory"),
            ],
            [("bytes32", "default")],
        ),
    },
    LIFECYCLE_MODULE: {
        "recordFundingCommitment": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("struct Phase9Types.FundingCommitment", "calldata"),
            ],
            [],
        ),
        "executeRefinance": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("bytes32", "default"),
                ("bytes32", "default"),
            ],
            [("struct Phase9Types.RefinanceTerminalResult", "memory")],
        ),
        "cancelRefinance": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("bytes32", "default"),
                ("bytes32", "default"),
            ],
            [],
        ),
        "refundCommitment": (
            [
                ("struct Phase9RefinanceStorageLayout", "storage"),
                ("bytes32", "default"),
                ("bytes32", "default"),
            ],
            [],
        ),
    },
}


def _ast_parameter_signature(function: Mapping[str, Any], key: str) -> list[tuple[str, str]]:
    container = function.get(key)
    if not isinstance(container, dict):
        raise LinkedModuleCheckError(f"linked entry has malformed {key}")
    parameters = container.get("parameters")
    if not isinstance(parameters, list):
        raise LinkedModuleCheckError(f"linked entry has malformed {key}")
    result: list[tuple[str, str]] = []
    for parameter in parameters:
        if not isinstance(parameter, dict):
            raise LinkedModuleCheckError(f"linked entry has malformed {key}")
        raw_type = _type_string(parameter)
        location = parameter.get("storageLocation")
        if not isinstance(location, str):
            raise LinkedModuleCheckError(f"linked entry has malformed {key}")
        suffix = f" {location}"
        base_type = raw_type[: -len(suffix)] if raw_type.endswith(suffix) else raw_type
        result.append((base_type, location))
    return result


def _validate_module_ast(definitions: Mapping[str, Mapping[str, Any]]) -> None:
    for module in MODULES:
        definition = definitions[module]
        for node in _walk(definition):
            if node.get("nodeType") == "VariableDeclaration" and node.get("stateVariable"):
                raise LinkedModuleCheckError(f"{module}: library declares a state variable")
            if (
                module != VALIDATION_MODULE
                and node.get("nodeType") == "InlineAssembly"
            ):
                raise LinkedModuleCheckError(f"{module}: inline assembly is forbidden")

        public_functions = [
            node
            for node in definition.get("nodes", [])
            if isinstance(node, dict)
            and node.get("nodeType") == "FunctionDefinition"
            and node.get("visibility") in {"public", "external"}
        ]
        expected = _PUBLIC_AST_SIGNATURES[module]
        _require(
            {str(node.get("name")) for node in public_functions} == set(expected)
            and len(public_functions) == len(expected),
            f"{module}: public linked-entry AST inventory drift",
        )
        for function in public_functions:
            name = str(function.get("name"))
            expected_parameters, expected_returns = expected[name]
            _require(
                function.get("visibility") == "public",
                f"{module}.{name}: linked entry is not public",
            )
            _require(
                _ast_parameter_signature(function, "parameters") == expected_parameters,
                f"{module}.{name}: parameter signature drift",
            )
            _require(
                _ast_parameter_signature(function, "returnParameters") == expected_returns,
                f"{module}.{name}: return signature drift",
            )
            if module == VALIDATION_MODULE:
                _require(
                    function.get("stateMutability") == "view",
                    f"{module}.{name}: validation entry is not view",
                )


def _yul_call_name(node: Mapping[str, Any]) -> str | None:
    if node.get("nodeType") != "YulFunctionCall":
        return None
    function_name = node.get("functionName")
    if not isinstance(function_name, dict):
        return None
    name = function_name.get("name")
    return name if isinstance(name, str) else None


def _is_yul_identifier(node: object, name: str) -> bool:
    return (
        isinstance(node, dict)
        and node.get("nodeType") == "YulIdentifier"
        and node.get("name") == name
    )


def _is_yul_number(node: object, value: str) -> bool:
    return (
        isinstance(node, dict)
        and node.get("nodeType") == "YulLiteral"
        and node.get("kind") == "number"
        and node.get("value") == value
    )


def _is_yul_word_number(node: object, value: int) -> bool:
    if not isinstance(node, dict) or node.get("nodeType") != "YulLiteral":
        return False
    raw = node.get("value")
    if not isinstance(raw, str):
        return False
    try:
        return int(raw, 0) == value
    except ValueError:
        return False


def _is_yul_call(node: object, name: str) -> bool:
    return isinstance(node, dict) and _yul_call_name(node) == name


def _yul_arguments(node: object, name: str, count: int) -> list[object] | None:
    if not _is_yul_call(node, name) or not isinstance(node, dict):
        return None
    arguments = node.get("arguments")
    if not isinstance(arguments, list) or len(arguments) != count:
        return None
    return list(arguments)


def _is_allocation_end(node: object, size_name: str) -> bool:
    outer = _yul_arguments(node, "and", 2)
    if outer is None:
        return False
    negation = _yul_arguments(outer[1], "not", 1)
    if negation is None or not _is_yul_word_number(negation[0], 31):
        return False
    end = _yul_arguments(outer[0], "add", 2)
    if end is None:
        return False
    output_header = _yul_arguments(end[0], "add", 2)
    padded_size = _yul_arguments(end[1], "add", 2)
    return (
        output_header is not None
        and _is_yul_identifier(output_header[0], "output")
        and _is_yul_word_number(output_header[1], 32)
        and padded_size is not None
        and _is_yul_identifier(padded_size[0], size_name)
        and _is_yul_word_number(padded_size[1], 31)
    )


def _yul_assigned_names(node: Mapping[str, Any]) -> list[str]:
    declarations = node.get("variables")
    if node.get("nodeType") == "YulAssignment":
        declarations = node.get("variableNames")
    if not isinstance(declarations, list):
        return []
    return [
        str(declaration.get("name"))
        for declaration in declarations
        if isinstance(declaration, dict) and isinstance(declaration.get("name"), str)
    ]


def _statement_index(statements: list[object], target: Mapping[str, Any]) -> int:
    for index, statement in enumerate(statements):
        if any(node is target for node in _walk(statement)):
            return index
    return -1


def _solidity_number(node: object) -> int | None:
    if not isinstance(node, dict) or node.get("nodeType") != "Literal":
        return None
    raw = node.get("value")
    if not isinstance(raw, str):
        return None
    try:
        return int(raw, 0)
    except ValueError:
        return None


def _bounded_call_selector(call: Mapping[str, Any]) -> str | None:
    arguments = call.get("arguments")
    if not isinstance(arguments, list) or len(arguments) != 3:
        raise LinkedModuleCheckError("_boundedStaticcall call arity drift")
    encoded = arguments[1]
    if not isinstance(encoded, dict) or encoded.get("nodeType") != "FunctionCall":
        return None
    expression = encoded.get("expression")
    if not (
        isinstance(expression, dict)
        and expression.get("nodeType") == "MemberAccess"
        and expression.get("memberName") == "encodeCall"
    ):
        return None
    encoded_arguments = encoded.get("arguments")
    if not isinstance(encoded_arguments, list) or not encoded_arguments:
        raise LinkedModuleCheckError("abi.encodeCall selector is malformed")
    selector = encoded_arguments[0]
    if not isinstance(selector, dict) or selector.get("nodeType") != "MemberAccess":
        raise LinkedModuleCheckError("abi.encodeCall selector is malformed")
    name = selector.get("memberName")
    if not isinstance(name, str):
        raise LinkedModuleCheckError("abi.encodeCall selector is malformed")
    return name


def _validate_bounded_call_sites(definition: Mapping[str, Any]) -> None:
    observed: dict[str, list[tuple[str | None, int]]] = {}
    for function in definition.get("nodes", []):
        if not isinstance(function, dict) or function.get("nodeType") != "FunctionDefinition":
            continue
        function_name = function.get("name")
        if not isinstance(function_name, str):
            continue
        sites: list[tuple[str | None, int]] = []
        for node in _walk(function):
            if node.get("nodeType") != "FunctionCall":
                continue
            expression = node.get("expression")
            if not (
                isinstance(expression, dict)
                and expression.get("nodeType") == "Identifier"
                and expression.get("name") == "_boundedStaticcall"
            ):
                continue
            arguments = node.get("arguments")
            if not isinstance(arguments, list) or len(arguments) != 3:
                raise LinkedModuleCheckError("_boundedStaticcall call arity drift")
            cap = _solidity_number(arguments[2])
            if cap is None:
                raise LinkedModuleCheckError("_boundedStaticcall cap must be a literal")
            sites.append((_bounded_call_selector(node), cap))
        if sites:
            observed[function_name] = sites
    _require(
        observed == BOUNDED_STATICCALL_SITES,
        "bounded-staticcall selector/cap inventory drift",
    )


def _flatten_or(node: object) -> list[object]:
    if isinstance(node, dict) and node.get("nodeType") == "BinaryOperation":
        if node.get("operator") == "||":
            return _flatten_or(node.get("leftExpression")) + _flatten_or(
                node.get("rightExpression")
            )
    return [node]


def _is_identifier(node: object, name: str) -> bool:
    return (
        isinstance(node, dict)
        and node.get("nodeType") == "Identifier"
        and node.get("name") == name
    )


def _is_raw_length_check(node: object) -> bool:
    if not isinstance(node, dict) or node.get("nodeType") != "BinaryOperation":
        return False
    left = node.get("leftExpression")
    return (
        node.get("operator") == "!="
        and isinstance(left, dict)
        and left.get("nodeType") == "MemberAccess"
        and left.get("memberName") == "length"
        and _is_identifier(left.get("expression"), "raw")
        and _solidity_number(node.get("rightExpression")) == 36
    )


def _is_keccak_call(node: object, argument_name: str | None = None) -> bool:
    if not isinstance(node, dict) or node.get("nodeType") != "FunctionCall":
        return False
    if not _is_identifier(node.get("expression"), "keccak256"):
        return False
    arguments = node.get("arguments")
    if not isinstance(arguments, list) or len(arguments) != 1:
        return False
    return argument_name is None or _is_identifier(arguments[0], argument_name)


def _is_unknown_lien_encoding(node: object) -> bool:
    if not isinstance(node, dict) or node.get("nodeType") != "FunctionCall":
        return False
    expression = node.get("expression")
    if not (
        isinstance(expression, dict)
        and expression.get("nodeType") == "MemberAccess"
        and expression.get("memberName") == "encodeWithSelector"
        and _is_identifier(expression.get("expression"), "abi")
    ):
        return False
    arguments = node.get("arguments")
    if not isinstance(arguments, list) or len(arguments) != 2:
        return False
    selector = arguments[0]
    if not (
        isinstance(selector, dict)
        and selector.get("nodeType") == "MemberAccess"
        and selector.get("memberName") == "selector"
    ):
        return False
    error = selector.get("expression")
    return (
        isinstance(error, dict)
        and error.get("nodeType") == "MemberAccess"
        and error.get("memberName") == "UnknownLien"
        and _is_identifier(error.get("expression"), "ILienRegistry")
        and _is_identifier(arguments[1], "collateralId")
    )


def _is_unknown_lien_hash_check(node: object) -> bool:
    if not isinstance(node, dict) or node.get("nodeType") != "BinaryOperation":
        return False
    if node.get("operator") != "!=":
        return False
    left = node.get("leftExpression")
    right = node.get("rightExpression")
    if not _is_keccak_call(left, "raw") or not _is_keccak_call(right):
        return False
    if not isinstance(right, dict):
        return False
    arguments = right.get("arguments")
    return isinstance(arguments, list) and len(arguments) == 1 and _is_unknown_lien_encoding(
        arguments[0]
    )


def _validate_unknown_lien_absence(definition: Mapping[str, Any]) -> None:
    functions = [
        node
        for node in definition.get("nodes", [])
        if isinstance(node, dict)
        and node.get("nodeType") == "FunctionDefinition"
        and node.get("name") == "_requireCollateralAbsent"
    ]
    _require(len(functions) == 1, "unknown-lien absence helper inventory drift")
    conditions = [
        node.get("condition")
        for node in _walk(functions[0])
        if node.get("nodeType") == "IfStatement"
    ]
    matching = []
    for condition in conditions:
        operands = _flatten_or(condition)
        if (
            len(operands) == 3
            and _is_identifier(operands[0], "ok")
            and _is_raw_length_check(operands[1])
            and _is_unknown_lien_hash_check(operands[2])
        ):
            matching.append(condition)
    _require(
        len(matching) == 1,
        "lien absence must require failure, exact 36-byte UnknownLien data, and exact hash",
    )


def _is_context_coordinator_guard(node: Mapping[str, Any]) -> bool:
    if node.get("nodeType") != "BinaryOperation" or node.get("operator") != "!=":
        return False
    left = node.get("leftExpression")
    right = node.get("rightExpression")
    if not (
        isinstance(left, dict)
        and left.get("nodeType") == "MemberAccess"
        and left.get("memberName") == "coordinator"
        and _is_identifier(left.get("expression"), "context")
        and isinstance(right, dict)
        and right.get("nodeType") == "FunctionCall"
    ):
        return False
    expression = right.get("expression")
    arguments = right.get("arguments")
    return (
        isinstance(expression, dict)
        and expression.get("nodeType") == "ElementaryTypeNameExpression"
        and isinstance(arguments, list)
        and len(arguments) == 1
        and _is_identifier(arguments[0], "this")
    )


def _validate_context_guard(definition: Mapping[str, Any]) -> None:
    functions = {
        str(node.get("name")): node
        for node in definition.get("nodes", [])
        if isinstance(node, dict) and node.get("nodeType") == "FunctionDefinition"
    }
    preflight = functions.get("preflight")
    context_validation = functions.get("_validateContext")
    if not isinstance(preflight, dict) or not isinstance(context_validation, dict):
        raise LinkedModuleCheckError("validation context guard functions are missing")
    body = preflight.get("body")
    if not isinstance(body, dict):
        raise LinkedModuleCheckError("validation preflight body is malformed")
    statements = body.get("statements")
    if not isinstance(statements, list) or not statements:
        raise LinkedModuleCheckError("validation preflight is empty")
    first_calls = [node for node in _walk(statements[0]) if node.get("nodeType") == "FunctionCall"]
    _require(
        len(first_calls) == 1
        and _is_identifier(first_calls[0].get("expression"), "_validateContext"),
        "validation preflight must call _validateContext first",
    )

    nodes = list(_walk(context_validation))
    guard_indexes = [
        index
        for index, node in enumerate(nodes)
        if _is_context_coordinator_guard(node)
    ]
    dependency_indexes = [
        index
        for index, node in enumerate(nodes)
        if node.get("nodeType") == "FunctionCall"
        and isinstance(node.get("expression"), dict)
        and node["expression"].get("nodeType") == "Identifier"
        and node["expression"].get("name")
        in {"_addressCall", "_boundedStaticcall", "_wordCall"}
    ]
    _require(
        len(guard_indexes) == 1
        and bool(dependency_indexes)
        and guard_indexes[0] < min(dependency_indexes),
        "context.coordinator must equal address(this) before the first dependency call",
    )


def _validate_validation_assembly(definition: Mapping[str, Any]) -> dict[str, Any]:
    _validate_bounded_call_sites(definition)
    _validate_unknown_lien_absence(definition)
    _validate_context_guard(definition)
    helpers = [
        node
        for node in definition.get("nodes", [])
        if isinstance(node, dict)
        and node.get("nodeType") == "FunctionDefinition"
        and node.get("name") == "_boundedStaticcall"
    ]
    _require(len(helpers) == 1, "validation module must declare one _boundedStaticcall helper")
    helper = helpers[0]
    _require(
        helper.get("visibility") == "private" and helper.get("stateMutability") == "view",
        "_boundedStaticcall must be private view",
    )
    _require(
        _ast_parameter_signature(helper, "parameters")
        == [("address", "default"), ("bytes", "memory"), ("uint256", "default")],
        "_boundedStaticcall parameter signature drift",
    )
    _require(
        _ast_parameter_signature(helper, "returnParameters")
        == [("bool", "default"), ("bytes", "memory")],
        "_boundedStaticcall return signature drift",
    )
    body = helper.get("body")
    if not isinstance(body, dict):
        raise LinkedModuleCheckError("_boundedStaticcall body is malformed")
    body_statements = body.get("statements")
    if not (
        isinstance(body_statements, list)
        and len(body_statements) == 1
        and isinstance(body_statements[0], dict)
        and body_statements[0].get("nodeType") == "InlineAssembly"
    ):
        raise LinkedModuleCheckError(
            "_boundedStaticcall must contain only its pinned assembly block"
        )
    assembly = body_statements[0]
    _require(
        assembly.get("flags") == ["memory-safe"],
        "_boundedStaticcall assembly must be memory-safe",
    )
    block = assembly.get("AST")
    if not isinstance(block, dict) or block.get("nodeType") != "YulBlock":
        raise LinkedModuleCheckError("_boundedStaticcall assembly is malformed")
    statements = block.get("statements")
    if not isinstance(statements, list):
        raise LinkedModuleCheckError("_boundedStaticcall assembly is malformed")
    calls = [node for node in _walk(block) if node.get("nodeType") == "YulFunctionCall"]
    names = [_yul_call_name(node) for node in calls]
    forbidden = sorted(name for name in names if name in _FORBIDDEN_YUL_OPERATIONS)
    _require(not forbidden, f"_boundedStaticcall uses forbidden Yul operations: {forbidden}")
    _require(names.count("staticcall") == 1, "_boundedStaticcall must use one staticcall")
    _require(
        names.count("returndatasize") == 1
        and names.count("returndatacopy") == 1
        and names.count("gt") == 1,
        "_boundedStaticcall returndata bound inventory drift",
    )
    _require(
        not any(
            node.get("nodeType")
            in {
                "YulBreak",
                "YulContinue",
                "YulForLoop",
                "YulFunctionDefinition",
                "YulLeave",
                "YulSwitch",
            }
            for node in _walk(block)
        ),
        "_boundedStaticcall contains unapproved Yul control flow",
    )

    staticcall = next(node for node in calls if _yul_call_name(node) == "staticcall")
    arguments = staticcall.get("arguments")
    if not isinstance(arguments, list) or len(arguments) != 6:
        raise LinkedModuleCheckError("staticcall arity drift")
    _require(_is_yul_call(arguments[0], "gas"), "staticcall must forward current gas")
    _require(_is_yul_identifier(arguments[1], "target"), "staticcall target drift")
    _require(
        _is_yul_call(arguments[2], "add")
        and _is_yul_call(arguments[3], "mload")
        and _is_yul_number(arguments[4], "0")
        and _is_yul_number(arguments[5], "0"),
        "staticcall input/output arguments drift",
    )
    input_add = arguments[2].get("arguments")
    input_length = arguments[3].get("arguments")
    _require(
        isinstance(input_add, list)
        and len(input_add) == 2
        and _is_yul_identifier(input_add[0], "input")
        and (_is_yul_number(input_add[1], "32") or _is_yul_number(input_add[1], "0x20"))
        and isinstance(input_length, list)
        and len(input_length) == 1
        and _is_yul_identifier(input_length[0], "input"),
        "staticcall calldata slice is not the exact bytes payload",
    )

    staticcall_owners = [
        node
        for node in _walk(block)
        if node.get("value") is staticcall and "ok" in _yul_assigned_names(node)
    ]
    _require(len(staticcall_owners) == 1, "staticcall result must assign ok once")
    staticcall_owner = staticcall_owners[0]
    returndata_size = next(node for node in calls if _yul_call_name(node) == "returndatasize")
    size_owners = [
        node
        for node in _walk(block)
        if node.get("value") is returndata_size and _yul_assigned_names(node)
    ]
    _require(len(size_owners) == 1, "returndatasize must be assigned once")
    size_name = _yul_assigned_names(size_owners[0])[0]
    guards = [node for node in _walk(block) if node.get("nodeType") == "YulIf"]
    _require(len(guards) == 1, "returndata handling must use one maximum-size guard")
    guard = guards[0]
    condition = guard.get("condition")
    if not isinstance(condition, dict) or not _is_yul_call(condition, "gt"):
        raise LinkedModuleCheckError("returndata guard must use gt")
    guard_arguments = condition.get("arguments")
    _require(
        isinstance(guard_arguments, list)
        and len(guard_arguments) == 2
        and _is_yul_identifier(guard_arguments[0], size_name)
        and _is_yul_identifier(guard_arguments[1], "maximumReturndata"),
        "returndata guard is not size > maximumReturndata",
    )
    guard_body = guard.get("body")
    _require(isinstance(guard_body, dict), "returndata guard body is malformed")
    guard_assignments = [
        node for node in _walk(guard_body) if node.get("nodeType") == "YulAssignment"
    ]
    _require(
        any(
            _yul_assigned_names(node) == ["ok"] and _is_yul_number(node.get("value"), "0")
            for node in guard_assignments
        )
        and any(
            _yul_assigned_names(node) == [size_name]
            and _is_yul_number(node.get("value"), "0")
            for node in guard_assignments
        ),
        "oversized returndata must clear ok and the copy length",
    )
    copy = next(node for node in calls if _yul_call_name(node) == "returndatacopy")
    copy_arguments = copy.get("arguments")
    _require(
        isinstance(copy_arguments, list)
        and len(copy_arguments) == 3
        and _is_yul_call(copy_arguments[0], "add")
        and _is_yul_number(copy_arguments[1], "0")
        and _is_yul_identifier(copy_arguments[2], size_name),
        "returndatacopy does not use the bounded size",
    )
    if not isinstance(copy_arguments, list):
        raise LinkedModuleCheckError("returndatacopy arguments are malformed")
    copy_target = _yul_arguments(copy_arguments[0], "add", 2)
    _require(
        copy_target is not None
        and _is_yul_identifier(copy_target[0], "output")
        and _is_yul_word_number(copy_target[1], 32),
        "returndatacopy destination drift",
    )

    output_assignments = [
        node
        for node in _walk(block)
        if _yul_assigned_names(node) == ["output"] and _is_yul_call(node.get("value"), "mload")
    ]
    _require(len(output_assignments) == 1, "output pointer must be assigned once")
    output_load = _yul_arguments(output_assignments[0].get("value"), "mload", 1)
    _require(
        output_load is not None and _is_yul_word_number(output_load[0], 64),
        "output must allocate at the free-memory pointer",
    )
    mstores = [node for node in calls if _yul_call_name(node) == "mstore"]
    length_stores = []
    free_pointer_stores = []
    for mstore in mstores:
        mstore_arguments = mstore.get("arguments")
        if not isinstance(mstore_arguments, list) or len(mstore_arguments) != 2:
            continue
        if _is_yul_identifier(mstore_arguments[0], "output") and _is_yul_identifier(
            mstore_arguments[1], size_name
        ):
            length_stores.append(mstore)
        if _is_yul_word_number(mstore_arguments[0], 64) and _is_allocation_end(
            mstore_arguments[1], size_name
        ):
            free_pointer_stores.append(mstore)
    _require(len(length_stores) == 1, "output length store drift")
    _require(len(free_pointer_stores) == 1, "free-memory update drift")
    _require(
        _statement_index(statements, staticcall_owner)
        < _statement_index(statements, size_owners[0])
        < _statement_index(statements, guard)
        < _statement_index(statements, output_assignments[0])
        < _statement_index(statements, length_stores[0])
        < _statement_index(statements, copy),
        "bounded staticcall statements are out of order",
    )
    _require(
        _statement_index(statements, copy)
        < _statement_index(statements, free_pointer_stores[0]),
        "free-memory update must follow the bounded copy",
    )
    return assembly


def _validate_forbidden_constructs(
    source_ast: Mapping[str, Any], definitions: Mapping[str, Mapping[str, Any]]
) -> None:
    for node in _walk(source_ast):
        if node.get("nodeType") == "MemberAccess" and node.get("memberName") == "delegatecall":
            raise LinkedModuleCheckError("source contains a raw high-level delegatecall")
    validation = definitions[VALIDATION_MODULE]
    for node in _walk(validation):
        if node.get("nodeType") == "MemberAccess" and node.get("memberName") in {
            "call",
            "callcode",
            "delegatecall",
            "staticcall",
        }:
            raise LinkedModuleCheckError("validation module contains an unbounded low-level call")
        if node.get("nodeType") == "EmitStatement":
            raise LinkedModuleCheckError("validation module contains a forbidden construct")
        if node.get("nodeType") == "NewExpression":
            type_name = node.get("typeName")
            if isinstance(type_name, dict) and type_name.get("nodeType") == "UserDefinedTypeName":
                raise LinkedModuleCheckError("validation module contains contract creation")
        if node.get("nodeType") == "FunctionCall":
            expression = node.get("expression")
            if isinstance(expression, dict) and expression.get("nodeType") == "Identifier":
                if expression.get("name") in {"selfdestruct", "suicide"}:
                    raise LinkedModuleCheckError("validation module contains selfdestruct")


def _source_start(node: Mapping[str, Any], fallback: int) -> int:
    source = node.get("src")
    if not isinstance(source, str):
        return fallback
    try:
        return int(source.split(":", 1)[0])
    except ValueError:
        return fallback


def _linked_calls(function: Mapping[str, Any]) -> list[tuple[str, str, Mapping[str, Any]]]:
    calls: list[tuple[int, int, str, str, Mapping[str, Any]]] = []
    for fallback, node in enumerate(_walk(function)):
        if node.get("nodeType") != "FunctionCall":
            continue
        expression = node.get("expression")
        if not isinstance(expression, dict) or expression.get("nodeType") != "MemberAccess":
            continue
        target = expression.get("expression")
        if not isinstance(target, dict) or target.get("nodeType") != "Identifier":
            continue
        module = target.get("name")
        method = expression.get("memberName")
        if module in MODULES and isinstance(method, str):
            calls.append((_source_start(node, fallback), fallback, str(module), method, node))
    calls.sort(key=lambda item: (item[0], item[1]))
    return [(module, method, node) for _, _, module, method, node in calls]


def _invalid_refinance_catch(statement: Mapping[str, Any]) -> bool:
    clauses = statement.get("clauses")
    if not isinstance(clauses, list) or len(clauses) != 2:
        return False
    catch_clause = clauses[1]
    if not isinstance(catch_clause, dict) or catch_clause.get("errorName") != "":
        return False
    block = catch_clause.get("block")
    if not isinstance(block, dict):
        return False
    statements = block.get("statements")
    if not isinstance(statements, list) or len(statements) != 1:
        return False
    revert = statements[0]
    if not isinstance(revert, dict) or revert.get("nodeType") != "RevertStatement":
        return False
    error_call = revert.get("errorCall")
    if not isinstance(error_call, dict):
        return False
    expression = error_call.get("expression")
    return (
        isinstance(expression, dict)
        and expression.get("nodeType") == "Identifier"
        and expression.get("name") == "InvalidRefinance"
        and error_call.get("arguments") == []
    )


def _validate_coordinator_calls(definition: Mapping[str, Any]) -> None:
    functions = {
        str(node.get("name")): node
        for node in definition.get("nodes", [])
        if isinstance(node, dict) and node.get("nodeType") == "FunctionDefinition"
    }
    request = functions.get("requestRefinance")
    if not isinstance(request, dict):
        raise LinkedModuleCheckError("coordinator requestRefinance wrapper is missing")
    request_calls = _linked_calls(request)
    _require(
        [(module, method) for module, method, _ in request_calls]
        == [
            (REQUEST_MODULE, "begin"),
            (VALIDATION_MODULE, "preflight"),
            (REQUEST_MODULE, "complete"),
        ],
        "coordinator requestRefinance linked-call order drift",
    )
    try_statements = [node for node in _walk(request) if node.get("nodeType") == "TryStatement"]
    _require(
        len(try_statements) == 1
        and try_statements[0].get("externalCall") is request_calls[1][2]
        and _invalid_refinance_catch(try_statements[0]),
        "validation preflight must be try/catch-normalized to InvalidRefinance",
    )

    lifecycle_wrappers = {
        "recordFundingCommitment": "recordFundingCommitment",
        "executeRefinance": "executeRefinance",
        "cancelRefinance": "cancelRefinance",
        "refundCommitment": "refundCommitment",
    }
    for wrapper, method in lifecycle_wrappers.items():
        function = functions.get(wrapper)
        if not isinstance(function, dict):
            raise LinkedModuleCheckError(f"coordinator {wrapper} wrapper is missing")
        calls = _linked_calls(function)
        _require(
            [(module, observed_method) for module, observed_method, _ in calls]
            == [(LIFECYCLE_MODULE, method)],
            f"coordinator {wrapper} linked-call inventory drift",
        )

    all_calls = _linked_calls(definition)
    inventory: dict[tuple[str, str], int] = {}
    for module, method, _ in all_calls:
        key = (module, method)
        inventory[key] = inventory.get(key, 0) + 1
    _require(inventory == COORDINATOR_CALLS, "coordinator linked-call AST inventory drift")


def _validate_assemblies(
    source_ast: Mapping[str, Any], definitions: Mapping[str, Mapping[str, Any]]
) -> None:
    validation_assembly = _validate_validation_assembly(definitions[VALIDATION_MODULE])
    coordinator_assemblies = [
        node
        for node in _walk(definitions[COORDINATOR])
        if node.get("nodeType") == "InlineAssembly"
    ]
    _require(len(coordinator_assemblies) == 1, "coordinator layout assembly inventory drift")
    all_assemblies = [
        node for node in _walk(source_ast) if node.get("nodeType") == "InlineAssembly"
    ]
    _require(
        len(all_assemblies) == 2
        and validation_assembly in all_assemblies
        and coordinator_assemblies[0] in all_assemblies,
        "source must contain only the validation and coordinator assembly exceptions",
    )
    assembly = coordinator_assemblies[0]
    block = assembly.get("AST")
    if not isinstance(block, dict) or block.get("nodeType") != "YulBlock":
        raise LinkedModuleCheckError("coordinator layout assembly is malformed")
    statements = block.get("statements")
    if not isinstance(statements, list) or len(statements) != 1:
        raise LinkedModuleCheckError("coordinator layout assembly has extra statements")
    assignment = statements[0]
    _require(
        isinstance(assignment, dict) and assignment.get("nodeType") == "YulAssignment",
        "coordinator assembly is not a Yul assignment",
    )
    names = assignment.get("variableNames")
    value = assignment.get("value")
    _require(
        isinstance(names, list)
        and len(names) == 1
        and isinstance(names[0], dict)
        and names[0].get("nodeType") == "YulIdentifier"
        and names[0].get("name") == "state.slot",
        "coordinator assembly target must be state.slot",
    )
    _require(
        isinstance(value, dict)
        and value.get("nodeType") == "YulLiteral"
        and value.get("kind") == "number"
        and value.get("value") == "0",
        "state.slot must be assigned literal zero",
    )
    external = assembly.get("externalReferences")
    _require(
        isinstance(external, list)
        and len(external) == 1
        and external[0].get("isSlot") is True
        and external[0].get("isOffset") is False
        and external[0].get("suffix") == "slot",
        "coordinator assembly reference is not the compiler-attributed layout slot",
    )


def validate_compiler_output(
    output: Mapping[str, Any], *, coordinator_storage_snapshot: Mapping[str, Any]
) -> dict[str, object]:
    """Validate one pinned standard-JSON compiler result."""

    _require(output.get("compilerVersion") == SOLC_VERSION, "unexpected Solidity compiler version")
    _require(
        output.get("openzeppelinVersion") == OPENZEPPELIN_VERSION,
        "unexpected OpenZeppelin Contracts version",
    )
    _require(output.get("compilerSettings") == COMPILER_SETTINGS, "compiler settings drift")
    diagnostics = output.get("errors", [])
    _require(isinstance(diagnostics, list), "compiler diagnostics are malformed")
    compiler_errors = [
        diagnostic
        for diagnostic in diagnostics
        if isinstance(diagnostic, dict) and diagnostic.get("severity") == "error"
    ]
    if compiler_errors:
        detail = "; ".join(
            str(diagnostic.get("formattedMessage") or diagnostic.get("message") or "error")
            .strip()
            .replace("\r", " ")
            .replace("\n", " ")
            for diagnostic in compiler_errors[:3]
        )
        raise LinkedModuleCheckError(f"Solidity standard-JSON compilation failed: {detail}")

    source_output = output.get("sources", {}).get(REFINANCE_SOURCE)
    _require(isinstance(source_output, dict), "refinance source AST is missing")
    source_ast = source_output.get("ast")
    _require(isinstance(source_ast, dict), "refinance source AST is missing")
    definitions = _definitions(source_ast)
    _require(
        all(name in definitions for name in (*MODULES, COORDINATOR)),
        "ADR 0023 candidate definitions are missing",
    )
    _require(
        definitions[COORDINATOR].get("contractKind") == "contract"
        and all(definitions[module].get("contractKind") == "library" for module in MODULES),
        "ADR 0023 candidate definition kinds are incorrect",
    )
    source_libraries = {
        name for name, node in definitions.items() if node.get("contractKind") == "library"
    }
    source_contracts = {
        name for name, node in definitions.items() if node.get("contractKind") == "contract"
    }
    _require(source_libraries == set(MODULES), "unexpected same-source library definition")
    _require(source_contracts == {COORDINATOR}, "unexpected same-source contract definition")

    contract_source = output.get("contracts", {}).get(REFINANCE_SOURCE)
    _require(isinstance(contract_source, dict), "refinance compiler contract output is missing")
    _require(
        all(name in contract_source for name in (*MODULES, COORDINATOR)),
        "candidate compiler artifacts are missing",
    )
    contracts = {name: contract_source[name] for name in (*MODULES, COORDINATOR)}
    _require(
        all(isinstance(contract, dict) for contract in contracts.values()),
        "candidate compiler artifact is malformed",
    )

    _validate_mirror(source_ast)
    _validate_validation_context(source_ast)
    _validate_plan_cap(source_ast)
    _validate_module_ast(definitions)
    _validate_forbidden_constructs(source_ast, definitions)
    _validate_coordinator_calls(definitions[COORDINATOR])
    _validate_assemblies(source_ast, definitions)
    storage = _validate_storage(contracts, coordinator_storage_snapshot)
    _validate_method_identifiers(contracts)
    sizes = _validate_bytecode(contracts)
    return {"runtimeBytes": sizes, "storage": storage}


_NODE_COMPILER = r"""
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import solc from "solc";

const root = resolve(process.argv[1]);
const compilationSource = "protocol/src/ProtocolCompilation.sol";
const refinanceSource = "protocol/src/resolution/RefinanceCoordinator.sol";
const settings = {
  evmVersion: "prague",
  optimizer: { enabled: true, runs: 200 },
  viaIR: false,
};
const outputFields = [
  "storageLayout",
  "evm.methodIdentifiers",
  "evm.bytecode.object",
  "evm.bytecode.linkReferences",
  "evm.deployedBytecode.object",
  "evm.deployedBytecode.linkReferences",
  "evm.deployedBytecode.opcodes",
];
const input = {
  language: "Solidity",
  settings: {
    ...settings,
    outputSelection: { [refinanceSource]: { "": ["ast"], "*": outputFields } },
  },
  sources: {
    [compilationSource]: { content: readFileSync(resolve(root, compilationSource), "utf8") },
  },
};
function findImport(importPath) {
  for (const candidate of [
    resolve(root, importPath),
    resolve(root, "node_modules", importPath),
    resolve(root, "protocol/src", importPath),
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
  readFileSync(resolve(root, "node_modules/@openzeppelin/contracts/package.json"), "utf8"),
).version;
output.compilerSettings = settings;
process.stdout.write(JSON.stringify(output));
"""


def compile_protocol(root: Path = ROOT) -> dict[str, Any]:
    """Compile the canonical protocol target using the pinned local solc-js package."""

    node = shutil.which("node")
    if node is None:
        raise LinkedModuleCheckError("node executable is unavailable")
    result = subprocess.run(  # noqa: S603 - fixed executable and argument vector
        (node, "--input-type=module", "--eval", _NODE_COMPILER, str(root.resolve())),
        cwd=root,
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "no compiler diagnostic"
        raise LinkedModuleCheckError(f"Solidity compiler invocation failed: {detail}")
    try:
        payload: object = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise LinkedModuleCheckError("Solidity compiler returned malformed JSON") from error
    if not isinstance(payload, dict):
        raise LinkedModuleCheckError("Solidity compiler output is not an object")
    return cast(dict[str, Any], payload)


def check_repository(root: Path = ROOT) -> dict[str, object]:
    snapshot_path = root / STORAGE_SNAPSHOT
    try:
        snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise LinkedModuleCheckError(
            "authoritative RefinanceCoordinator storage snapshot is unavailable"
        ) from error
    _require(isinstance(snapshot, dict), "authoritative storage snapshot is malformed")
    return validate_compiler_output(
        compile_protocol(root), coordinator_storage_snapshot=snapshot
    )


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(argv if argv is not None else sys.argv[1:])
    if arguments:
        print("usage: check_phase9_refinance_linked_modules.py", file=sys.stderr)
        return 2
    try:
        result = check_repository()
    except LinkedModuleCheckError as error:
        print(f"Phase 9 refinance linked-module check failed: {error}", file=sys.stderr)
        return 1
    sizes = result["runtimeBytes"]
    if not isinstance(sizes, dict):
        print("Phase 9 refinance linked-module check returned malformed sizes", file=sys.stderr)
        return 1
    rendered = ", ".join(f"{name}={sizes[name]}" for name in (*MODULES, COORDINATOR))
    print(f"Phase 9 refinance linked-module check passed ({rendered} runtime bytes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
