import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import solc from "solc";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const COMPILATION_ROOT = "protocol/src/ProtocolCompilation.sol";
const OUTPUT_PATH = resolve(ROOT, ".cache/solc/phase9-storage-layouts.json");
const CHECKPOINT_PATH = resolve(
  ROOT,
  "protocol/compatibility/phase9-implementation-checkpoints.json",
);

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
const PHASE9_PRODUCTION_CONTRACTS = PHASE9_CONTRACTS.slice(0, -1);
const PHASE9_MUTABILITY_WARNING_CODE = "2018";
const ACTIVATED_IMPLEMENTATIONS = new Map([["PayoffQuoteEngine", "UNI-PAYOFF-001"]]);

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

function sourceRange(node) {
  const [startText, lengthText] = String(node.src ?? "").split(":", 2);
  const start = Number.parseInt(startText, 10);
  const length = Number.parseInt(lengthText, 10);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(length)) {
    throw new Error(`Invalid Solidity AST source range: ${node.src}`);
  }
  return { end: start + length, start };
}

function functionLabel(sourceName, contractName, node) {
  const parameterTypes = (node.parameters?.parameters ?? []).map(
    (parameter) => parameter.typeDescriptions?.typeString ?? "?",
  );
  return `${sourceName}:${contractName}.${node.name}(${parameterTypes.join(",")})`;
}

function canonicalFreezeMutators(output, productionContracts) {
  const functions = [];
  for (const [sourceName, sourceOutput] of Object.entries(output.sources ?? {})) {
    for (const contract of sourceOutput.ast?.nodes ?? []) {
      if (
        contract.nodeType !== "ContractDefinition" ||
        !productionContracts.includes(contract.name)
      ) {
        continue;
      }
      for (const node of contract.nodes ?? []) {
        const statements = node.body?.statements ?? [];
        if (
          node.nodeType !== "FunctionDefinition" ||
          node.kind !== "function" ||
          !["external", "public"].includes(node.visibility) ||
          node.stateMutability !== "nonpayable" ||
          (node.modifiers ?? []).length !== 0 ||
          statements.length !== 1 ||
          revertErrorName(statements[0]) !== "Phase9ImplementationNotFrozen"
        ) {
          continue;
        }
        functions.push({
          ...sourceRange(node),
          key: `${sourceName}:${node.id}`,
          label: functionLabel(sourceName, contract.name, node),
          sourceName,
        });
      }
    }
  }
  return functions;
}

function externalMutators(output, productionContracts) {
  const functions = [];
  for (const [sourceName, sourceOutput] of Object.entries(output.sources ?? {})) {
    for (const contract of sourceOutput.ast?.nodes ?? []) {
      if (
        contract.nodeType !== "ContractDefinition" ||
        !productionContracts.includes(contract.name)
      ) {
        continue;
      }
      for (const node of contract.nodes ?? []) {
        if (
          node.nodeType === "FunctionDefinition" &&
          node.kind === "function" &&
          ["external", "public"].includes(node.visibility) &&
          !["view", "pure"].includes(node.stateMutability)
        ) {
          functions.push(functionLabel(sourceName, contract.name, node));
        }
      }
    }
  }
  return functions;
}

export function phase9StubContracts(payload) {
  if (
    payload === null ||
    typeof payload !== "object" ||
    payload.schemaVersion !== 1 ||
    !Array.isArray(payload.implementations)
  ) {
    throw new Error("Phase 9 implementation checkpoint registry is malformed");
  }
  const implemented = payload.implementations.map((entry) => entry?.contract);
  if (
    payload.implementations.some(
      (entry) =>
        entry === null ||
        typeof entry !== "object" ||
        typeof entry.contract !== "string" ||
        !PHASE9_PRODUCTION_CONTRACTS.includes(entry.contract) ||
        entry.backlogId !== ACTIVATED_IMPLEMENTATIONS.get(entry.contract) ||
        entry.status !== "PASS",
    ) ||
    new Set(implemented).size !== implemented.length
  ) {
    throw new Error("Phase 9 implementation checkpoint contract set is invalid");
  }
  return PHASE9_PRODUCTION_CONTRACTS.filter((contract) => !implemented.includes(contract));
}

export function validatePhase9MutabilityDiagnostics(
  output,
  {
    expectedCount,
    productionContracts = PHASE9_PRODUCTION_CONTRACTS,
  } = {},
) {
  const mutators = externalMutators(output, productionContracts);
  const requiredCount = expectedCount ?? mutators.length;
  const canonical = canonicalFreezeMutators(output, productionContracts);
  if (canonical.length !== requiredCount) {
    throw new Error(
      `Expected ${requiredCount} canonical Phase 9 fail-closed mutators, found ${canonical.length}`,
    );
  }

  const warnings = (output.errors ?? []).filter(
    (diagnostic) =>
      diagnostic.severity === "warning" &&
      String(diagnostic.errorCode) === PHASE9_MUTABILITY_WARNING_CODE,
  );
  if (warnings.length !== requiredCount) {
    throw new Error(
      `Expected ${requiredCount} Phase 9 warning-2018 diagnostics, found ${warnings.length}`,
    );
  }

  const matched = new Set();
  for (const warning of warnings) {
    const location = warning.sourceLocation;
    if (
      location === undefined ||
      typeof location.file !== "string" ||
      !Number.isSafeInteger(location.start) ||
      !Number.isSafeInteger(location.end)
    ) {
      throw new Error("Warning 2018 is missing a precise source location");
    }
    const candidates = canonical.filter(
      (fn) =>
        fn.sourceName === location.file &&
        location.start >= fn.start &&
        location.end <= fn.end,
    );
    if (candidates.length !== 1) {
      throw new Error(
        `Warning 2018 is not scoped to one canonical Phase 9 fail-closed mutator: ${location.file}:${location.start}`,
      );
    }
    const [candidate] = candidates;
    if (matched.has(candidate.key)) {
      throw new Error(`Duplicate warning 2018 for ${candidate.label}`);
    }
    matched.add(candidate.key);
  }

  const missing = canonical.filter((fn) => !matched.has(fn.key));
  if (missing.length > 0) {
    throw new Error(
      `Canonical Phase 9 fail-closed mutators lack warning 2018: ${missing.map((fn) => fn.label).join(", ")}`,
    );
  }
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
  const checkpointPayload = await readJson(CHECKPOINT_PATH);
  const stubContracts = phase9StubContracts(checkpointPayload);
  validatePhase9MutabilityDiagnostics(output, { productionContracts: stubContracts });

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

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
