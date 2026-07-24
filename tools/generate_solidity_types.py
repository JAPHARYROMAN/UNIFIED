"""Generate deterministic Solidity type projections from Unified Protobuf files."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTO_ROOT = ROOT / "schemas" / "proto" / "unified" / "v1"
OUTPUT = ROOT / "protocol" / "src" / "generated" / "FoundationTypes.sol"

ENUM_RE = re.compile(r"enum\s+(\w+)\s*\{(.*?)\}", re.DOTALL)
MESSAGE_RE = re.compile(r"message\s+(\w+)\s*\{(.*?)\}", re.DOTALL)
ENUM_VALUE_RE = re.compile(r"^\s*(\w+)\s*=\s*\d+\s*;", re.MULTILINE)
FIELD_RE = re.compile(
    r"^\s*(?:(repeated)\s+)?([\w.]+)\s+(\w+)\s*=\s*\d+\s*;",
    re.MULTILINE,
)

SOLIDITY_SCALARS = {
    "string": "string",
    "bytes": "bytes",
    "bool": "bool",
    "uint32": "uint32",
    "uint64": "uint64",
    "int32": "int32",
    "int64": "int64",
    "google.protobuf.Timestamp": "int64",
}


def lower_camel(value: str) -> str:
    first, *rest = value.split("_")
    return first + "".join(part.title() for part in rest)


def strip_comments(source: str) -> str:
    return re.sub(r"//.*", "", source)


def enum_member(enum_name: str, value: str) -> str:
    prefix = re.sub(r"(?<!^)(?=[A-Z])", "_", enum_name).upper() + "_"
    return value.removeprefix(prefix)


def main() -> None:
    proto_files = sorted(PROTO_ROOT.glob("*.proto"))
    if not proto_files:
        raise SystemExit("No Unified Protobuf files found")

    combined = "\n".join(path.read_text(encoding="utf-8") for path in proto_files)
    source_hash = hashlib.sha256(combined.encode()).hexdigest()
    source = strip_comments(combined)

    enums: list[tuple[str, list[str]]] = []
    for match in ENUM_RE.finditer(source):
        name, body = match.groups()
        values = [enum_member(name, item) for item in ENUM_VALUE_RE.findall(body)]
        enums.append((name, values))

    messages: list[tuple[str, list[tuple[bool, str, str]]]] = []
    for match in MESSAGE_RE.finditer(source):
        name, body = match.groups()
        fields = [
            (bool(repeated), field_type, lower_camel(field_name))
            for repeated, field_type, field_name in FIELD_RE.findall(body)
        ]
        messages.append((name, fields))

    known_types = {name for name, _ in enums} | {name for name, _ in messages}
    lines = [
        "// SPDX-License-Identifier: UNLICENSED",
        "pragma solidity 0.8.36;",
        "",
        "// Code generated from schemas/proto/unified/v1. DO NOT EDIT.",
        f"// Source SHA-256: {source_hash}",
        "library FoundationTypes {",
    ]

    for name, values in enums:
        lines.append(f"    enum {name} {{ {', '.join(values)} }}")
        lines.append("")

    for name, fields in messages:
        lines.append(f"    struct {name} {{")
        for repeated, field_type, field_name in fields:
            sol_type = SOLIDITY_SCALARS.get(field_type, field_type.rsplit(".", 1)[-1])
            if sol_type not in SOLIDITY_SCALARS.values() and sol_type not in known_types:
                raise SystemExit(f"Unsupported Solidity projection type: {field_type}")
            suffix = "[]" if repeated else ""
            lines.append(f"        {sol_type}{suffix} {field_name};")
        lines.append("    }")
        lines.append("")

    lines.append("}")
    lines.append("")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()

