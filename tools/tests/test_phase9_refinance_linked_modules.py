from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import check_phase9_refinance_linked_modules as checker  # noqa: E402


def _variable(
    identifier: int,
    name: str,
    type_string: str,
    storage_location: str = "default",
) -> dict[str, Any]:
    return {
        "id": identifier,
        "name": name,
        "nodeType": "VariableDeclaration",
        "stateVariable": False,
        "storageLocation": storage_location,
        "typeDescriptions": {"typeString": type_string},
    }


def _function(
    identifier: int,
    name: str,
    parameters: list[tuple[str, str]],
    returns: list[tuple[str, str]],
    *,
    visibility: str = "public",
    state_mutability: str = "nonpayable",
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "body": body,
        "id": identifier,
        "name": name,
        "nodeType": "FunctionDefinition",
        "parameters": {
            "parameters": [
                _variable(identifier + 100 + index, f"p{index}", type_string, location)
                for index, (type_string, location) in enumerate(parameters)
            ]
        },
        "returnParameters": {
            "parameters": [
                _variable(identifier + 200 + index, f"r{index}", type_string, location)
                for index, (type_string, location) in enumerate(returns)
            ]
        },
        "stateMutability": state_mutability,
        "visibility": visibility,
    }


def _yul_identifier(name: str) -> dict[str, str]:
    return {"name": name, "nodeType": "YulIdentifier"}


def _yul_number(value: str) -> dict[str, str]:
    return {"kind": "number", "nodeType": "YulLiteral", "value": value}


def _yul_call(name: str, *arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "arguments": list(arguments),
        "functionName": _yul_identifier(name),
        "nodeType": "YulFunctionCall",
    }


def _validation_assembly() -> dict[str, Any]:
    staticcall = _yul_call(
        "staticcall",
        _yul_call("gas"),
        _yul_identifier("target"),
        _yul_call("add", _yul_identifier("input"), _yul_number("32")),
        _yul_call("mload", _yul_identifier("input")),
        _yul_number("0"),
        _yul_number("0"),
    )
    return {
        "AST": {
            "nodeType": "YulBlock",
            "statements": [
                {
                    "nodeType": "YulAssignment",
                    "value": staticcall,
                    "variableNames": [_yul_identifier("ok")],
                },
                {
                    "nodeType": "YulVariableDeclaration",
                    "value": _yul_call("returndatasize"),
                    "variables": [_yul_identifier("size")],
                },
                {
                    "body": {
                        "nodeType": "YulBlock",
                        "statements": [
                            {
                                "nodeType": "YulAssignment",
                                "value": _yul_number("0"),
                                "variableNames": [_yul_identifier("ok")],
                            },
                            {
                                "nodeType": "YulAssignment",
                                "value": _yul_number("0"),
                                "variableNames": [_yul_identifier("size")],
                            },
                        ],
                    },
                    "condition": _yul_call(
                        "gt",
                        _yul_identifier("size"),
                        _yul_identifier("maximumReturndata"),
                    ),
                    "nodeType": "YulIf",
                },
                {
                    "nodeType": "YulAssignment",
                    "value": _yul_call("mload", _yul_number("0x40")),
                    "variableNames": [_yul_identifier("output")],
                },
                {
                    "expression": _yul_call(
                        "mstore", _yul_identifier("output"), _yul_identifier("size")
                    ),
                    "nodeType": "YulExpressionStatement",
                },
                {
                    "expression": _yul_call(
                        "returndatacopy",
                        _yul_call("add", _yul_identifier("output"), _yul_number("32")),
                        _yul_number("0"),
                        _yul_identifier("size"),
                    ),
                    "nodeType": "YulExpressionStatement",
                },
                {
                    "expression": _yul_call(
                        "mstore",
                        _yul_number("0x40"),
                        _yul_call(
                            "and",
                            _yul_call(
                                "add",
                                _yul_call(
                                    "add",
                                    _yul_identifier("output"),
                                    _yul_number("0x20"),
                                ),
                                _yul_call(
                                    "add", _yul_identifier("size"), _yul_number("0x1f")
                                ),
                            ),
                            _yul_call("not", _yul_number("0x1f")),
                        ),
                    ),
                    "nodeType": "YulExpressionStatement",
                },
            ],
        },
        "externalReferences": [],
        "flags": ["memory-safe"],
        "id": 2_050,
        "nodeType": "InlineAssembly",
    }


def _linked_functions(module: str, start: int) -> list[dict[str, Any]]:
    return [
        _function(start + index, name, parameters, returns, state_mutability="view")
        if module == checker.VALIDATION_MODULE
        else _function(start + index, name, parameters, returns)
        for index, (name, (parameters, returns)) in enumerate(
            checker._PUBLIC_AST_SIGNATURES[module].items()
        )
    ]


def _library_call(module: str, method: str) -> dict[str, Any]:
    return {
        "expression": {
            "expression": {"name": module, "nodeType": "Identifier"},
            "memberName": method,
            "nodeType": "MemberAccess",
        },
        "nodeType": "FunctionCall",
    }


def _solidity_identifier(name: str) -> dict[str, str]:
    return {"name": name, "nodeType": "Identifier"}


def _solidity_number(value: int) -> dict[str, str]:
    return {"kind": "number", "nodeType": "Literal", "value": str(value)}


def _bounded_solidity_call(selector: str | None, cap: int) -> dict[str, Any]:
    if selector is None:
        encoded: dict[str, Any] = _solidity_identifier("input")
    else:
        encoded = {
            "arguments": [
                {
                    "expression": _solidity_identifier("IPhase9Source"),
                    "memberName": selector,
                    "nodeType": "MemberAccess",
                },
                {"components": [], "nodeType": "TupleExpression"},
            ],
            "expression": {
                "expression": _solidity_identifier("abi"),
                "memberName": "encodeCall",
                "nodeType": "MemberAccess",
            },
            "nodeType": "FunctionCall",
        }
    return {
        "arguments": [_solidity_identifier("target"), encoded, _solidity_number(cap)],
        "expression": _solidity_identifier("_boundedStaticcall"),
        "nodeType": "FunctionCall",
    }


def _unknown_lien_condition() -> dict[str, Any]:
    length_check = {
        "leftExpression": {
            "expression": _solidity_identifier("raw"),
            "memberName": "length",
            "nodeType": "MemberAccess",
        },
        "nodeType": "BinaryOperation",
        "operator": "!=",
        "rightExpression": _solidity_number(36),
    }
    error_encoding = {
        "arguments": [
            {
                "expression": {
                    "expression": _solidity_identifier("ILienRegistry"),
                    "memberName": "UnknownLien",
                    "nodeType": "MemberAccess",
                },
                "memberName": "selector",
                "nodeType": "MemberAccess",
            },
            _solidity_identifier("collateralId"),
        ],
        "expression": {
            "expression": _solidity_identifier("abi"),
            "memberName": "encodeWithSelector",
            "nodeType": "MemberAccess",
        },
        "nodeType": "FunctionCall",
    }
    hash_check = {
        "leftExpression": {
            "arguments": [_solidity_identifier("raw")],
            "expression": _solidity_identifier("keccak256"),
            "nodeType": "FunctionCall",
        },
        "nodeType": "BinaryOperation",
        "operator": "!=",
        "rightExpression": {
            "arguments": [error_encoding],
            "expression": _solidity_identifier("keccak256"),
            "nodeType": "FunctionCall",
        },
    }
    return {
        "leftExpression": {
            "leftExpression": _solidity_identifier("ok"),
            "nodeType": "BinaryOperation",
            "operator": "||",
            "rightExpression": length_check,
        },
        "nodeType": "BinaryOperation",
        "operator": "||",
        "rightExpression": hash_check,
    }


def _bounded_site_functions(start: int) -> list[dict[str, Any]]:
    functions: list[dict[str, Any]] = []
    for index, (name, sites) in enumerate(checker.BOUNDED_STATICCALL_SITES.items()):
        statements: list[dict[str, Any]] = [
            _bounded_solidity_call(selector, cap) for selector, cap in sites
        ]
        if name == "_requireCollateralAbsent":
            statements.append(
                {
                    "condition": _unknown_lien_condition(),
                    "nodeType": "IfStatement",
                    "trueBody": {"nodeType": "Block", "statements": []},
                }
            )
        functions.append(
            _function(
                start + index,
                name,
                [],
                [],
                visibility="private",
                state_mutability="view",
                body={"nodeType": "Block", "statements": statements},
            )
        )
    return functions


def _context_guard_function(identifier: int) -> dict[str, Any]:
    address_this = {
        "arguments": [_solidity_identifier("this")],
        "expression": {"nodeType": "ElementaryTypeNameExpression"},
        "nodeType": "FunctionCall",
    }
    coordinator_guard = {
        "leftExpression": {
            "expression": _solidity_identifier("context"),
            "memberName": "coordinator",
            "nodeType": "MemberAccess",
        },
        "nodeType": "BinaryOperation",
        "operator": "!=",
        "rightExpression": address_this,
    }
    dependency_check = {
        "leftExpression": {
            "arguments": [],
            "expression": _solidity_identifier("_addressCall"),
            "nodeType": "FunctionCall",
        },
        "nodeType": "BinaryOperation",
        "operator": "!=",
        "rightExpression": {
            "expression": _solidity_identifier("context"),
            "memberName": "coordinator",
            "nodeType": "MemberAccess",
        },
    }
    return _function(
        identifier,
        "_validateContext",
        [],
        [],
        visibility="private",
        state_mutability="view",
        body={
            "nodeType": "Block",
            "statements": [
                {
                    "condition": {
                        "leftExpression": coordinator_guard,
                        "nodeType": "BinaryOperation",
                        "operator": "||",
                        "rightExpression": dependency_check,
                    },
                    "nodeType": "IfStatement",
                }
            ],
        },
    )


def _coordinator_functions(layout_assembly: dict[str, Any]) -> list[dict[str, Any]]:
    begin = _library_call(checker.REQUEST_MODULE, "begin")
    begin["src"] = "10:1:0"
    preflight = _library_call(checker.VALIDATION_MODULE, "preflight")
    preflight["src"] = "20:1:0"
    complete = _library_call(checker.REQUEST_MODULE, "complete")
    complete["src"] = "30:1:0"
    try_statement = {
        "clauses": [
            {
                "block": {"nodeType": "Block", "statements": []},
                "errorName": "",
                "nodeType": "TryCatchClause",
            },
            {
                "block": {
                    "nodeType": "Block",
                    "statements": [
                        {
                            "errorCall": {
                                "arguments": [],
                                "expression": _solidity_identifier("InvalidRefinance"),
                                "nodeType": "FunctionCall",
                            },
                            "nodeType": "RevertStatement",
                        }
                    ],
                },
                "errorName": "",
                "nodeType": "TryCatchClause",
            },
        ],
        "externalCall": preflight,
        "nodeType": "TryStatement",
    }
    functions = [
        _function(
            5_001,
            "_layout",
            [],
            [("struct Phase9RefinanceStorageLayout", "storage")],
            visibility="internal",
            body={"nodeType": "Block", "statements": [layout_assembly]},
        ),
        _function(
            5_010,
            "requestRefinance",
            [],
            [("bytes32", "default")],
            visibility="external",
            body={"nodeType": "Block", "statements": [begin, try_statement, complete]},
        ),
    ]
    for index, method in enumerate(
        [
            "recordFundingCommitment",
            "executeRefinance",
            "cancelRefinance",
            "refundCommitment",
        ]
    ):
        call = _library_call(checker.LIFECYCLE_MODULE, method)
        call["src"] = f"{40 + index * 10}:1:0"
        functions.append(
            _function(
                5_020 + index,
                method,
                [],
                [],
                visibility="external",
                body={"nodeType": "Block", "statements": [call]},
            )
        )
    return functions


def _source_ast() -> dict[str, Any]:
    mirror_members = [
        _variable(1_000 + index, field.name, field.type_string)
        for index, field in enumerate(checker.MIRROR_FIELDS)
    ]
    validation_assembly = _validation_assembly()
    validation_nodes = _linked_functions(checker.VALIDATION_MODULE, 2_000)
    preflight = next(node for node in validation_nodes if node.get("name") == "preflight")
    preflight["body"] = {
        "nodeType": "Block",
        "statements": [
            {
                "arguments": [],
                "expression": _solidity_identifier("_validateContext"),
                "nodeType": "FunctionCall",
            }
        ],
    }
    validation_nodes.extend(_bounded_site_functions(2_100))
    validation_nodes.append(_context_guard_function(2_130))
    validation_nodes.append(
        _function(
            2_040,
            "_boundedStaticcall",
            [("address", "default"), ("bytes", "memory"), ("uint256", "default")],
            [("bool", "default"), ("bytes", "memory")],
            visibility="private",
            state_mutability="view",
            body={"nodeType": "Block", "statements": [validation_assembly]},
        )
    )
    validation = {
        "contractKind": "library",
        "id": 2_000,
        "name": checker.VALIDATION_MODULE,
        "nodeType": "ContractDefinition",
        "nodes": validation_nodes,
    }
    request = {
        "contractKind": "library",
        "id": 3_000,
        "name": checker.REQUEST_MODULE,
        "nodeType": "ContractDefinition",
        "nodes": _linked_functions(checker.REQUEST_MODULE, 3_001),
    }
    lifecycle = {
        "contractKind": "library",
        "id": 4_000,
        "name": checker.LIFECYCLE_MODULE,
        "nodeType": "ContractDefinition",
        "nodes": _linked_functions(checker.LIFECYCLE_MODULE, 4_001),
    }
    layout_assembly = {
        "AST": {
            "nodeType": "YulBlock",
            "statements": [
                {
                    "nodeType": "YulAssignment",
                    "value": _yul_number("0"),
                    "variableNames": [_yul_identifier("state.slot")],
                }
            ],
        },
        "externalReferences": [
            {"declaration": 5_002, "isOffset": False, "isSlot": True, "suffix": "slot"}
        ],
        "id": 5_003,
        "nodeType": "InlineAssembly",
    }
    coordinator = {
        "contractKind": "contract",
        "id": 5_000,
        "name": checker.COORDINATOR,
        "nodeType": "ContractDefinition",
        "nodes": _coordinator_functions(layout_assembly),
    }
    return {
        "nodeType": "SourceUnit",
        "nodes": [
            {
                "constant": True,
                "id": 899,
                "name": "PHASE9_REFINANCE_MAX_PLAN_BYTES",
                "nodeType": "VariableDeclaration",
                "typeDescriptions": {"typeString": "uint256"},
                "value": {"kind": "number", "nodeType": "Literal", "value": "22272"},
            },
            {
                "id": 900,
                "members": mirror_members,
                "name": "Phase9RefinanceStorageLayout",
                "nodeType": "StructDefinition",
            },
            {
                "id": 901,
                "members": [
                    _variable(902 + index, name, type_string)
                    for index, (name, type_string) in enumerate(
                        checker.VALIDATION_CONTEXT_FIELDS
                    )
                ],
                "name": "Phase9RefinanceValidationContext",
                "nodeType": "StructDefinition",
            },
            validation,
            request,
            lifecycle,
            coordinator,
        ],
    }


def _storage_layout() -> dict[str, Any]:
    types: dict[str, dict[str, str]] = {}
    storage: list[dict[str, object]] = []
    for index, field in enumerate(
        field for field in checker.MIRROR_FIELDS if not field.padding
    ):
        type_id = f"t_{index}"
        types[type_id] = {"label": field.type_string}
        storage.append(
            {
                "contract": f"{checker.REFINANCE_SOURCE}:{checker.COORDINATOR}",
                "label": f"_{field.name}",
                "offset": field.offset,
                "slot": str(field.slot),
                "type": type_id,
            }
        )
    return {"storage": storage, "types": types}


def _linked_artifact() -> dict[str, Any]:
    bytecode = ""
    offsets: dict[str, list[dict[str, int]]] = {module: [] for module in checker.MODULES}
    cursor = 0
    for module_index, module in enumerate(checker.MODULES, start=1):
        placeholder = "__$" + str(module_index) * 34 + "$__"
        for _ in range(checker.COORDINATOR_LINK_COUNTS[module]):
            bytecode += "73" + placeholder + "f4"
            offsets[module].append({"length": 20, "start": cursor + 1})
            cursor += 22
    return {
        "linkReferences": {checker.REFINANCE_SOURCE: offsets},
        "object": bytecode,
        "opcodes": "",
    }


def _module_contract(name: str) -> dict[str, Any]:
    runtime = "6000fa00" if name == checker.VALIDATION_MODULE else "600000"
    return {
        "storageLayout": {"storage": [], "types": None},
        "evm": {
            "bytecode": {"linkReferences": {}, "object": "600000"},
            "deployedBytecode": {
                "linkReferences": {},
                "object": runtime,
                "opcodes": "",
            },
            "methodIdentifiers": copy.deepcopy(checker.METHOD_IDENTIFIERS[name]),
        },
    }


def _fixture() -> tuple[dict[str, Any], dict[str, Any]]:
    layout = _storage_layout()
    contracts = {module: _module_contract(module) for module in checker.MODULES}
    contracts[checker.COORDINATOR] = {
        "storageLayout": copy.deepcopy(layout),
        "evm": {
            "bytecode": _linked_artifact(),
            "deployedBytecode": _linked_artifact(),
            "methodIdentifiers": {},
        },
    }
    output = {
        "compilerSettings": copy.deepcopy(checker.COMPILER_SETTINGS),
        "compilerVersion": checker.SOLC_VERSION,
        "contracts": {checker.REFINANCE_SOURCE: contracts},
        "errors": [],
        "openzeppelinVersion": checker.OPENZEPPELIN_VERSION,
        "sources": {checker.REFINANCE_SOURCE: {"ast": _source_ast()}},
    }
    return output, {"storageLayout": copy.deepcopy(layout)}


def _validate(output: dict[str, Any], snapshot: dict[str, Any]) -> dict[str, object]:
    return checker.validate_compiler_output(output, coordinator_storage_snapshot=snapshot)


def _definition(output: dict[str, Any], name: str) -> dict[str, Any]:
    return next(
        node
        for node in output["sources"][checker.REFINANCE_SOURCE]["ast"]["nodes"]
        if node.get("name") == name
    )


def test_valid_compiler_payload_passes() -> None:
    output, snapshot = _fixture()

    result = _validate(output, snapshot)

    assert result["runtimeBytes"] == {
        checker.VALIDATION_MODULE: 4,
        checker.REQUEST_MODULE: 3,
        checker.LIFECYCLE_MODULE: 3,
        checker.COORDINATOR: 154,
    }


def test_missing_candidate_fails_closed() -> None:
    output, snapshot = _fixture()
    nodes = output["sources"][checker.REFINANCE_SOURCE]["ast"]["nodes"]
    nodes[:] = [node for node in nodes if node.get("name") != checker.VALIDATION_MODULE]

    with pytest.raises(checker.LinkedModuleCheckError, match="candidate definitions are missing"):
        _validate(output, snapshot)


def test_method_identifier_allowlist_drift_is_rejected() -> None:
    output, snapshot = _fixture()
    methods = output["contracts"][checker.REFINANCE_SOURCE][checker.REQUEST_MODULE][
        "evm"
    ]["methodIdentifiers"]
    methods["extra(Phase9RefinanceStorageLayout storage)"] = "deadbeef"

    with pytest.raises(checker.LinkedModuleCheckError, match="linked-entry allowlist drift"):
        _validate(output, snapshot)


def test_validation_context_requires_active_lock() -> None:
    output, snapshot = _fixture()
    context = _definition(output, "Phase9RefinanceValidationContext")
    context["members"] = context["members"][:-1]

    with pytest.raises(checker.LinkedModuleCheckError, match="field inventory drift"):
        _validate(output, snapshot)


def test_validation_plan_cap_is_pinned_to_current_schema() -> None:
    output, snapshot = _fixture()
    cap = _definition(output, "PHASE9_REFINANCE_MAX_PLAN_BYTES")
    cap["value"]["value"] = "65536"

    with pytest.raises(checker.LinkedModuleCheckError, match="696 ABI words"):
        _validate(output, snapshot)


def test_bounded_staticcall_selector_cap_inventory_is_pinned() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    debt = next(node for node in validation["nodes"] if node.get("name") == "_accountDebt")
    call = next(
        node
        for node in checker._walk(debt)
        if node.get("nodeType") == "FunctionCall"
        and node.get("expression", {}).get("name") == "_boundedStaticcall"
    )
    call["arguments"][2]["value"] = "704"

    with pytest.raises(checker.LinkedModuleCheckError, match="selector/cap inventory drift"):
        _validate(output, snapshot)


def test_unknown_lien_absence_requires_exact_failure_shape() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    absence = next(
        node for node in validation["nodes"] if node.get("name") == "_requireCollateralAbsent"
    )
    condition = next(
        node.get("condition")
        for node in checker._walk(absence)
        if node.get("nodeType") == "IfStatement"
    )
    condition["leftExpression"]["leftExpression"] = {
        "nodeType": "UnaryOperation",
        "operator": "!",
        "subExpression": _solidity_identifier("ok"),
    }

    with pytest.raises(checker.LinkedModuleCheckError, match="exact 36-byte UnknownLien"):
        _validate(output, snapshot)


def test_exact_seven_link_inventory_is_enforced() -> None:
    output, snapshot = _fixture()
    runtime = output["contracts"][checker.REFINANCE_SOURCE][checker.COORDINATOR][
        "evm"
    ]["deployedBytecode"]
    placeholder = "__$" + "1" * 34 + "$__"
    start = len(runtime["object"]) // 2 + 1
    runtime["object"] += "73" + placeholder + "f4"
    runtime["linkReferences"][checker.REFINANCE_SOURCE][checker.VALIDATION_MODULE].append(
        {"length": 20, "start": start}
    )

    with pytest.raises(checker.LinkedModuleCheckError, match="exact seven"):
        _validate(output, snapshot)


@pytest.mark.parametrize("violation", ["storage", "delegatecall", "module_link"])
def test_module_storage_delegatecall_and_links_are_rejected(violation: str) -> None:
    output, snapshot = _fixture()
    module = output["contracts"][checker.REFINANCE_SOURCE][checker.LIFECYCLE_MODULE]
    if violation == "storage":
        module["storageLayout"]["storage"] = [{"label": "bad"}]
        expected = "storage layout is not empty"
    elif violation == "delegatecall":
        module["evm"]["deployedBytecode"]["object"] = "f4"
        expected = "module runtime contains DELEGATECALL"
    else:
        placeholder = "__$" + "1" * 34 + "$__"
        module["evm"]["deployedBytecode"] = {
            "linkReferences": {
                checker.REFINANCE_SOURCE: {
                    checker.VALIDATION_MODULE: [{"length": 20, "start": 1}]
                }
            },
            "object": "73" + placeholder,
            "opcodes": "",
        }
        expected = "module links another library"

    with pytest.raises(checker.LinkedModuleCheckError, match=expected):
        _validate(output, snapshot)


def test_validation_runtime_forbidden_opcode_is_rejected() -> None:
    output, snapshot = _fixture()
    runtime = output["contracts"][checker.REFINANCE_SOURCE][checker.VALIDATION_MODULE][
        "evm"
    ]["deployedBytecode"]
    runtime["object"] = "faf1"

    with pytest.raises(checker.LinkedModuleCheckError, match="forbidden opcode"):
        _validate(output, snapshot)


def test_padding_reference_is_rejected() -> None:
    output, snapshot = _fixture()
    mirror = _definition(output, "Phase9RefinanceStorageLayout")
    padding_id = next(
        member["id"]
        for member in mirror["members"]
        if member["name"] == "loanRegistryPadding"
    )
    _definition(output, checker.COORDINATOR)["nodes"].append(
        {"nodeType": "Identifier", "referencedDeclaration": padding_id}
    )

    with pytest.raises(checker.LinkedModuleCheckError, match="padding member is read"):
        _validate(output, snapshot)


def test_coordinator_layout_assembly_drift_is_rejected() -> None:
    output, snapshot = _fixture()
    coordinator = _definition(output, checker.COORDINATOR)
    assembly = next(
        node for node in checker._walk(coordinator) if node.get("nodeType") == "InlineAssembly"
    )
    assembly["AST"]["statements"][0]["value"]["value"] = "1"

    with pytest.raises(checker.LinkedModuleCheckError, match="literal zero"):
        _validate(output, snapshot)


def test_validation_assembly_must_be_memory_safe() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    assembly = next(
        node for node in checker._walk(validation) if node.get("nodeType") == "InlineAssembly"
    )
    assembly["flags"] = []

    with pytest.raises(checker.LinkedModuleCheckError, match="must be memory-safe"):
        _validate(output, snapshot)


def test_validation_assembly_forbidden_yul_operation_is_rejected() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    staticcall = next(
        node
        for node in checker._walk(validation)
        if checker._yul_call_name(node) == "staticcall"
    )
    staticcall["functionName"]["name"] = "call"

    with pytest.raises(checker.LinkedModuleCheckError, match="forbidden Yul"):
        _validate(output, snapshot)


def test_validation_assembly_must_bound_copy_length() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    guard = next(
        node
        for node in checker._walk(validation)
        if node.get("nodeType") == "YulIf"
        and checker._is_yul_call(node.get("condition"), "gt")
    )
    guard["body"]["statements"] = guard["body"]["statements"][:1]

    with pytest.raises(checker.LinkedModuleCheckError, match="copy length"):
        _validate(output, snapshot)


def test_raw_high_level_delegatecall_is_rejected() -> None:
    output, snapshot = _fixture()
    _definition(output, checker.COORDINATOR)["nodes"].append(
        {"memberName": "delegatecall", "nodeType": "MemberAccess"}
    )

    with pytest.raises(checker.LinkedModuleCheckError, match="raw high-level delegatecall"):
        _validate(output, snapshot)


def test_validation_contract_creation_is_rejected() -> None:
    output, snapshot = _fixture()
    _definition(output, checker.VALIDATION_MODULE)["nodes"].append(
        {
            "nodeType": "NewExpression",
            "typeName": {"nodeType": "UserDefinedTypeName", "name": "Hostile"},
        }
    )

    with pytest.raises(checker.LinkedModuleCheckError, match="contract creation"):
        _validate(output, snapshot)


def test_coordinator_call_inventory_is_enforced() -> None:
    output, snapshot = _fixture()
    coordinator = _definition(output, checker.COORDINATOR)
    request = next(node for node in coordinator["nodes"] if node.get("name") == "requestRefinance")
    request["body"]["statements"][0], request["body"]["statements"][2] = (
        request["body"]["statements"][2],
        request["body"]["statements"][0],
    )
    request["body"]["statements"][0]["src"] = "10:1:0"
    request["body"]["statements"][2]["src"] = "30:1:0"

    with pytest.raises(checker.LinkedModuleCheckError, match="linked-call order drift"):
        _validate(output, snapshot)


def test_validation_preflight_catch_must_normalize_error() -> None:
    output, snapshot = _fixture()
    coordinator = _definition(output, checker.COORDINATOR)
    request = next(node for node in coordinator["nodes"] if node.get("name") == "requestRefinance")
    try_statement = next(
        node for node in checker._walk(request) if node.get("nodeType") == "TryStatement"
    )
    catch_revert = try_statement["clauses"][1]["block"]["statements"][0]
    catch_revert["errorCall"]["expression"]["name"] = "Unexpected"

    with pytest.raises(checker.LinkedModuleCheckError, match="try/catch-normalized"):
        _validate(output, snapshot)


def test_context_coordinator_guard_must_precede_dependency() -> None:
    output, snapshot = _fixture()
    validation = _definition(output, checker.VALIDATION_MODULE)
    guard = next(node for node in validation["nodes"] if node.get("name") == "_validateContext")
    condition = guard["body"]["statements"][0]["condition"]
    condition["leftExpression"], condition["rightExpression"] = (
        condition["rightExpression"],
        condition["leftExpression"],
    )

    with pytest.raises(checker.LinkedModuleCheckError, match="before the first dependency"):
        _validate(output, snapshot)


def test_eip_170_boundary_is_enforced() -> None:
    output, snapshot = _fixture()
    runtime = output["contracts"][checker.REFINANCE_SOURCE][checker.REQUEST_MODULE][
        "evm"
    ]["deployedBytecode"]
    runtime["object"] = "00" * (checker.EIP_170_LIMIT + 1)

    with pytest.raises(checker.LinkedModuleCheckError, match="runtime exceeds EIP-170"):
        _validate(output, snapshot)


def test_repository_candidate_integration() -> None:
    source_path = checker.ROOT / checker.REFINANCE_SOURCE
    if not source_path.is_file():
        pytest.skip("ADR 0023 candidate source is being created")
    source = source_path.read_text(encoding="utf-8")
    if not all(f"library {module}" in source for module in checker.MODULES):
        pytest.skip("accepted three-library candidate is not present yet")

    result = checker.check_repository()

    assert set(result["runtimeBytes"]) == {*checker.MODULES, checker.COORDINATOR}
