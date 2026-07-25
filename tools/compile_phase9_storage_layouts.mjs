import { createHash } from "node:crypto";
import { Buffer } from "node:buffer";
import { readFileSync, statSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
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
const ACTIVATED_IMPLEMENTATION_SOURCES = new Map([
  ["PayoffQuoteEngine", "protocol/src/resolution/PayoffQuoteEngine.sol"],
]);
const BASELINE = {
  commit: "4f01a5692df92c435ff8893840ebdcca055449f0",
  manifestSha256: "sha256:9237acd53b00f5e90d77bbd4f5ce09590ddb750d079c333be4b14d8e7b4238a2",
  rawFreezeArtifactsSha256:
    "sha256:b0d494141f0e229cf9fd542401036cd63ba04de73e2f056c1e89a25253cdb1a3",
  sourceSetSha256: "sha256:a40ac90f75c52fc7583651d2d57d2a4d82f1899ed673be8b460d17fb7b7425cb",
};
const CHECKPOINT_ROOT_KEYS = [
  "baseline",
  "currentSourceSetSha256",
  "implementations",
  "schemaVersion",
];
const CHECKPOINT_ENTRY_KEYS = [
  "abiSha256",
  "backlogId",
  "contract",
  "dependencyClosureSha256",
  "reviewPath",
  "reviewSha256",
  "sourceSha256",
  "sourceSetSha256",
  "status",
  "storageStructuralSha256",
];
const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/;

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

function exactKeys(value, expected) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const observed = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return observed.length === wanted.length && observed.every((key, index) => key === wanted[index]);
}

function repositoryPath(path) {
  const result = relative(ROOT, path);
  return result !== ".." && !result.startsWith(`..${sep}`) && !isAbsolute(result);
}

function solidityIdentifierCharacter(character) {
  return character !== undefined && /[A-Za-z0-9_$]/.test(character);
}

function skipSolidityComment(source, index) {
  if (source.startsWith("//", index)) {
    const lineEnds = ["\r", "\n"]
      .map((marker) => source.indexOf(marker, index + 2))
      .filter((position) => position !== -1);
    if (lineEnds.length === 0) return source.length;
    const end = Math.min(...lineEnds);
    return source.startsWith("\r\n", end) ? end + 2 : end + 1;
  }
  if (source.startsWith("/*", index)) {
    const end = source.indexOf("*/", index + 2);
    if (end === -1) throw new Error("Solidity dependency source has an unterminated block comment");
    return end + 2;
  }
  return null;
}

function readSolidityString(source, index) {
  const quote = source[index];
  let cursor = index + 1;
  const characters = [];
  while (cursor < source.length) {
    const character = source[cursor];
    if (character === "\\") {
      if (cursor + 1 >= source.length) {
        throw new Error("Solidity dependency source has an unterminated string escape");
      }
      characters.push(character, source[cursor + 1]);
      cursor += 2;
      continue;
    }
    if (character === quote) return { cursor: cursor + 1, value: characters.join("") };
    characters.push(character);
    cursor += 1;
  }
  throw new Error("Solidity dependency source has an unterminated string");
}

function readSolidityImport(source, index) {
  let cursor = index;
  let importPath = null;
  while (cursor < source.length) {
    const commentEnd = skipSolidityComment(source, cursor);
    if (commentEnd !== null) {
      cursor = commentEnd;
      continue;
    }
    const character = source[cursor];
    if (character === '"' || character === "'") {
      const parsed = readSolidityString(source, cursor);
      if (importPath !== null) {
        throw new Error("Solidity import directive contains multiple string literals");
      }
      if (parsed.value.includes("\\")) {
        throw new Error("Escaped Solidity import paths are not supported");
      }
      importPath = parsed.value;
      cursor = parsed.cursor;
      continue;
    }
    if (character === ";") {
      if (importPath === null) throw new Error("Solidity import directive lacks a path");
      return { cursor: cursor + 1, importPath };
    }
    cursor += 1;
  }
  throw new Error("Solidity import directive is unterminated");
}

export function solidityImportsFromSource(source) {
  const imports = [];
  let cursor = 0;
  while (cursor < source.length) {
    const commentEnd = skipSolidityComment(source, cursor);
    if (commentEnd !== null) {
      cursor = commentEnd;
      continue;
    }
    const character = source[cursor];
    if (character === '"' || character === "'") {
      cursor = readSolidityString(source, cursor).cursor;
      continue;
    }
    if (solidityIdentifierCharacter(character)) {
      const start = cursor;
      while (cursor < source.length && solidityIdentifierCharacter(source[cursor])) cursor += 1;
      if (source.slice(start, cursor) === "import") {
        const parsed = readSolidityImport(source, cursor);
        imports.push(parsed.importPath);
        cursor = parsed.cursor;
      }
      continue;
    }
    cursor += 1;
  }
  return imports;
}

function solidityImports(sourcePath) {
  return solidityImportsFromSource(readFileSync(sourcePath, "utf8"));
}

export function ordinalUtf8Compare(left, right) {
  return Buffer.compare(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
}

function repositoryImportPath(sourcePath, importPath) {
  const candidates = importPath.startsWith(".")
    ? [resolve(dirname(sourcePath), importPath)]
    : [resolve(ROOT, importPath), resolve(ROOT, "protocol/src", importPath)];
  for (const candidate of candidates) {
    if (!repositoryPath(candidate)) {
      if (importPath.startsWith(".")) {
        throw new Error(`${relative(ROOT, sourcePath)} imports outside the repository: ${importPath}`);
      }
      continue;
    }
    try {
      if (!statSync(candidate).isFile()) continue;
      if (!candidate.toLowerCase().endsWith(".sol")) {
        throw new Error(
          `${relative(ROOT, sourcePath)} imports a non-Solidity repository file: ${importPath}`,
        );
      }
      return candidate;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  if ([".", "protocol/", "src/"].some((prefix) => importPath.startsWith(prefix))) {
    throw new Error(`${relative(ROOT, sourcePath)} has an unresolved repository import: ${importPath}`);
  }
  return null;
}

export function repositorySolidityDependencyHash(sourcePath) {
  const rootSource = resolve(ROOT, sourcePath);
  if (!repositoryPath(rootSource)) {
    throw new Error("Phase 9 implementation source is outside the repository");
  }
  const pending = [rootSource];
  const observed = new Set();
  while (pending.length > 0) {
    const current = pending.pop();
    if (observed.has(current)) continue;
    observed.add(current);
    for (const importPath of solidityImports(current)) {
      const dependency = repositoryImportPath(current, importPath);
      if (dependency !== null && !observed.has(dependency)) pending.push(dependency);
    }
  }
  const payload = [...observed]
    .map((path) => ({
      path: relative(ROOT, path).split(sep).join("/"),
      sha256: sha256(readFileSync(path)),
    }))
    .sort((left, right) => ordinalUtf8Compare(left.path, right.path));
  return sha256(canonicalJson(payload));
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
    !exactKeys(payload, CHECKPOINT_ROOT_KEYS) ||
    payload.schemaVersion !== 1 ||
    !Array.isArray(payload.implementations) ||
    !exactKeys(payload.baseline, Object.keys(BASELINE)) ||
    canonicalJson(payload.baseline) !== canonicalJson(BASELINE) ||
    !SHA256_PATTERN.test(payload.currentSourceSetSha256)
  ) {
    throw new Error("Phase 9 implementation checkpoint registry is malformed");
  }
  const implemented = payload.implementations.map((entry) => entry?.contract);
  if (
    payload.implementations.some(
      (entry) =>
        !exactKeys(entry, CHECKPOINT_ENTRY_KEYS) ||
        !Object.values(entry).every((value) => typeof value === "string") ||
        typeof entry.contract !== "string" ||
        !PHASE9_PRODUCTION_CONTRACTS.includes(entry.contract) ||
        entry.backlogId !== ACTIVATED_IMPLEMENTATIONS.get(entry.contract) ||
        entry.status !== "PASS" ||
        [
          entry.abiSha256,
          entry.dependencyClosureSha256,
          entry.reviewSha256,
          entry.sourceSha256,
          entry.sourceSetSha256,
          entry.storageStructuralSha256,
        ].some((value) => !SHA256_PATTERN.test(value)),
    ) ||
    new Set(implemented).size !== implemented.length
  ) {
    throw new Error("Phase 9 implementation checkpoint contract set is invalid");
  }
  return PHASE9_PRODUCTION_CONTRACTS.filter((contract) => !implemented.includes(contract));
}

export function validateCheckpointDependencyClosures(payload) {
  for (const entry of payload.implementations) {
    const sourcePath = ACTIVATED_IMPLEMENTATION_SOURCES.get(entry.contract);
    if (sourcePath === undefined) {
      throw new Error(`${entry.contract}: implementation dependency closure is not activated`);
    }
    const actual = repositorySolidityDependencyHash(sourcePath);
    if (actual !== entry.dependencyClosureSha256) {
      throw new Error(`${entry.contract}: reviewed Solidity dependency closure hash is stale`);
    }
  }
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
  validateCheckpointDependencyClosures(checkpointPayload);
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
