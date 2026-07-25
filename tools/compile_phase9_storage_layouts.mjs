import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import solc from "solc";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const COMPILATION_ROOT = "protocol/src/ProtocolCompilation.sol";
const OUTPUT_PATH = resolve(ROOT, ".cache/solc/phase9-storage-layouts.json");

const PHASE9_CONTRACTS = [
  "Phase9LoanFactory",
  "Phase9LoanAccount",
  "PayoffQuoteEngine",
  "CollateralCustodyV2",
  "LienRegistry",
  "RefinanceCoordinator",
  "PositionManagerV2",
  "RestructuringController",
  "InsuranceReserveVault",
  "ReservePolicy",
  "InsuranceManager",
  "GuaranteeVault",
  "RecoveryManager",
  "Phase9LocalSyntheticToken",
];

const COMPILER_SETTINGS = {
  evmVersion: "prague",
  optimizer: { enabled: true, runs: 200 },
  viaIR: false,
};

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonicalize(value));
}

function sha256(value) {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

function findImport(importPath) {
  const candidates = [
    resolve(ROOT, importPath),
    resolve(ROOT, "node_modules", importPath),
    resolve(ROOT, "protocol/src", importPath),
  ];
  for (const candidate of candidates) {
    try {
      return { contents: readFileSync(candidate, "utf8") };
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  return { error: `Import not found: ${importPath}` };
}

function contractDefinitions(output) {
  const definitions = new Map();
  for (const [sourceName, sourceOutput] of Object.entries(output.sources ?? {})) {
    for (const node of sourceOutput.ast?.nodes ?? []) {
      if (node.nodeType === "ContractDefinition") {
        definitions.set(node.id, {
          node,
          qualifiedName: `${sourceName}:${node.name}`,
          sourceName,
        });
      }
    }
  }
  return definitions;
}

function revertErrorName(statement) {
  if (statement?.nodeType !== "RevertStatement") return null;
  const expression = statement.errorCall?.expression;
  return expression?.name ?? expression?.memberName ?? null;
}

function freezeSurface(definition) {
  const stateVariables = [];
  const functions = [];
  for (const node of definition.node.nodes ?? []) {
    if (node.nodeType === "VariableDeclaration" && node.stateVariable) {
      stateVariables.push({
        constant: Boolean(node.constant),
        immutable: node.mutability === "immutable",
        name: node.name,
        type: node.typeDescriptions?.typeString ?? "",
        visibility: node.visibility,
      });
    }
    if (node.nodeType === "FunctionDefinition") {
      const statements = node.body?.statements ?? [];
      functions.push({
        bodyStatementKinds: statements.map((statement) => statement.nodeType),
        implemented: Boolean(node.implemented),
        kind: node.kind,
        modifiers: (node.modifiers ?? []).map(
          (modifier) => modifier.modifierName?.name ?? modifier.modifierName?.namePath ?? "",
        ),
        name: node.name,
        revertError:
          statements.length === 1 ? revertErrorName(statements[0]) : null,
        stateMutability: node.stateMutability,
        visibility: node.visibility,
      });
    }
  }
  return { functions, stateVariables };
}

function normalizedType(type) {
  const normalized = {
    encoding: type.encoding,
    label: type.label,
    numberOfBytes: type.numberOfBytes,
  };
  for (const key of ["base", "key", "value"]) {
    if (type[key] !== undefined) normalized[key] = type[key];
  }
  if (type.members !== undefined) {
    normalized.members = type.members.map((member) => ({
      contract: member.contract,
      label: member.label,
      offset: member.offset,
      slot: member.slot,
      type: member.type,
    }));
  }
  return normalized;
}

function normalizedLayout(contractName, sourceName, contractOutput, definition, definitions) {
  const rawLayout = contractOutput.storageLayout;
  if (rawLayout === undefined) {
    throw new Error(`${contractName}: compiler did not return storageLayout`);
  }
  const types = Object.fromEntries(
    Object.entries(rawLayout.types ?? {})
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([typeId, type]) => [typeId, normalizedType(type)]),
  );
  return canonicalize({
    compiler: {
      openzeppelinVersion: "5.6.1",
      settings: COMPILER_SETTINGS,
      settingsHash: sha256(canonicalJson(COMPILER_SETTINGS)),
      version: solc.version(),
    },
    contract: contractName,
    freezeSurface: freezeSurface(definition),
    linearizedBases: (definition.node.linearizedBaseContracts ?? []).map((identifier) => {
      const base = definitions.get(identifier);
      if (base === undefined) throw new Error(`${contractName}: unknown base AST id ${identifier}`);
      return base.qualifiedName;
    }),
    schemaVersion: 1,
    source: sourceName,
    storageLayout: {
      storage: (rawLayout.storage ?? []).map((entry) => ({
        contract: entry.contract,
        label: entry.label,
        offset: entry.offset,
        slot: entry.slot,
        type: entry.type,
      })),
      types,
    },
  });
}

async function main() {
  const compilerVersion = solc.version();
  if (!compilerVersion.startsWith("0.8.36+")) {
    throw new Error(`Expected solc 0.8.36, received ${compilerVersion}`);
  }
  const openzeppelinPackage = await readJson(
    resolve(ROOT, "node_modules/@openzeppelin/contracts/package.json"),
  );
  if (openzeppelinPackage.version !== "5.6.1") {
    throw new Error(`Expected OpenZeppelin 5.6.1, received ${openzeppelinPackage.version}`);
  }

  const input = {
    language: "Solidity",
    settings: {
      ...COMPILER_SETTINGS,
      outputSelection: {
        "*": { "": ["ast"], "*": ["storageLayout"] },
      },
    },
    sources: {
      [COMPILATION_ROOT]: { content: await readFile(resolve(ROOT, COMPILATION_ROOT), "utf8") },
    },
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImport }));
  const diagnostics = output.errors ?? [];
  for (const diagnostic of diagnostics) {
    const stream = diagnostic.severity === "error" ? process.stderr : process.stdout;
    stream.write(`${diagnostic.formattedMessage ?? diagnostic.message}\n`);
  }
  const errors = diagnostics.filter((diagnostic) => diagnostic.severity === "error");
  if (errors.length > 0) throw new Error(`Solidity compilation failed (${errors.length} errors)`);

  const definitions = contractDefinitions(output);
  const matches = new Map();
  for (const [identifier, definition] of definitions.entries()) {
    if (!PHASE9_CONTRACTS.includes(definition.node.name)) continue;
    const contractOutput = output.contracts?.[definition.sourceName]?.[definition.node.name];
    if (contractOutput === undefined) continue;
    if (matches.has(definition.node.name)) {
      throw new Error(`${definition.node.name}: duplicate contract definition`);
    }
    matches.set(
      definition.node.name,
      normalizedLayout(
        definition.node.name,
        definition.sourceName,
        contractOutput,
        definition,
        definitions,
      ),
    );
  }
  const missing = PHASE9_CONTRACTS.filter((contract) => !matches.has(contract));
  if (missing.length > 0) throw new Error(`Missing Phase 9 contracts: ${missing.join(", ")}`);

  const artifact = canonicalize({
    contracts: Object.fromEntries(PHASE9_CONTRACTS.map((name) => [name, matches.get(name)])),
    schemaVersion: 1,
  });
  await mkdir(dirname(OUTPUT_PATH), { recursive: true });
  await writeFile(OUTPUT_PATH, `${JSON.stringify(artifact, null, 2)}\n`, "utf8");
  process.stdout.write(`Phase 9 storage layouts compiled (${PHASE9_CONTRACTS.length} contracts).\n`);
}

await main();
