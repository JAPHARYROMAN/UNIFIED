import { createHash } from "node:crypto";
import { Buffer } from "node:buffer";
import { spawnSync } from "node:child_process";
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
export const PHASE9_PRODUCTION_CONTRACTS = PHASE9_CONTRACTS.slice(0, -1);
const PHASE9_MUTABILITY_WARNING_CODE = "2018";
const ACTIVATED_IMPLEMENTATION_SOURCES = new Map([
  ["PayoffQuoteEngine", "protocol/src/resolution/PayoffQuoteEngine.sol"],
  ["Phase9LoanFactory", "protocol/src/resolution/Phase9LoanFactory.sol"],
  ["Phase9LoanAccount", "protocol/src/resolution/Phase9LoanAccount.sol"],
  ["CollateralCustodyV2", "protocol/src/resolution/CollateralCustodyV2.sol"],
  ["LienRegistry", "protocol/src/resolution/LienRegistry.sol"],
  ["RefinanceCoordinator", "protocol/src/resolution/RefinanceCoordinator.sol"],
  ["PositionManagerV2", "protocol/src/resolution/PositionManagerV2.sol"],
]);
export const PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS = [
  ".gitattributes",
  ".github/workflows/foundation.yml",
  ".mise.toml",
  "adr/0020-phase-9-payoff-authority-and-implementation-activation.md",
  "apps/foundation-console/src/index.ts",
  "apps/foundation-console/src/phase9PayoffReferenceGolden.ts",
  "docs/architecture/phase-9-payoff-deployment-evidence.md",
  "docs/architecture/phase-9-payoff-quote-acceptance.md",
  "docs/architecture/phase-9-payoff-reference-evidence.md",
  "infrastructure/local/phase9-payoff-deployment-candidate.schema.json",
  "infrastructure/local/phase9-payoff-deployment-code-hashes.json",
  "infrastructure/local/phase9-payoff-deployment-evidence.schema.json",
  "models/foundation_model/src/unified_foundation/phase9_payoff_reference.py",
  "models/foundation_model/tests/test_phase9_payoff_reference.py",
  "package.json",
  "packages/phase9/typescript/payoffReference.ts",
  "pnpm-lock.yaml",
  "protocol/foundry.toml",
  "protocol/script/DeployPhase9Local.s.sol",
  "protocol/src/ProtocolCompilation.sol",
  "protocol/test/Phase9InterfaceFreeze.t.sol",
  "protocol/test/Phase9PayoffLocalDeploymentEvidence.t.sol",
  "protocol/test/Phase9PayoffQuote.t.sol",
  "protocol/test/Phase9PayoffQuoteAcceptanceMap.sol",
  "protocol/test/Phase9PayoffQuoteDeployment.t.sol",
  "protocol/test/Phase9PayoffQuoteFuzz.t.sol",
  "protocol/test/Phase9PayoffQuoteGolden.t.sol",
  "protocol/test/Phase9PayoffQuoteHarness.sol",
  "protocol/test/Phase9PayoffQuoteInvariants.t.sol",
  "pyproject.toml",
  "scripts/check-contract-sizes.py",
  "scripts/check-foundation.ps1",
  "scripts/prepare-foundry.ps1",
  "tools/check_phase9.py",
  "tools/check_phase9_implementation_checkpoints.py",
  "tools/check_phase9_storage_layouts.py",
  "tools/compile_phase9_storage_layouts.mjs",
  "tools/tests/test_phase9_compatibility.py",
  "tools/tests/test_phase9_implementation_checkpoints.py",
  "tools/tests/test_phase9_payoff_deployment_evidence_schema.py",
  "tools/tests/test_phase9_warning_policy.mjs",
  "tools/tests/test_update_phase9_implementation_checkpoint.py",
  "tools/update_phase9_implementation_checkpoint.py",
  "tools/verify_phase9_payoff_deployment.py",
  "tsconfig.json",
  "uv.lock",
];
export const REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS = [
  ".gitattributes",
  ".github/workflows/foundation.yml",
  ".mise.toml",
  "adr/0021-phase-9-atomic-refinance-authority-and-activation.md",
  "adr/0022-phase-9-factory-account-position-bootstrap-semantics.md",
  "adr/0023-phase-9-refinance-fixed-module-partition.md",
  "docs/architecture/phase-9-data-layouts.md",
  "docs/architecture/phase-9-refinance-acceptance.md",
  "docs/architecture/phase-9-refinance-deployment-evidence.md",
  "docs/architecture/phase-9-refinance-reference-evidence.md",
  "docs/architecture/phase-9-resolution-protection-recovery.md",
  "protocol/foundry.toml",
  "protocol/src/ProtocolCompilation.sol",
  "protocol/test/Phase9InterfaceFreeze.t.sol",
  "protocol/test/Phase9RefinanceBootstrapAcceptanceMap.sol",
  "protocol/test/Phase9RefinanceBootstrapHarness.sol",
  "protocol/test/Phase9RefinanceCustodyLienBootstrap.t.sol",
  "protocol/test/Phase9RefinanceFactoryBootstrap.t.sol",
  "protocol/test/Phase9RefinanceRequest.t.sol",
  "protocol/test/Phase9RefinanceRequestFuzz.t.sol",
  "protocol/test/Phase9RefinanceRequestGolden.t.sol",
  "protocol/test/Phase9RefinanceRequestInvariants.t.sol",
  "scripts/check-contract-sizes.py",
  "scripts/check-foundation.ps1",
  "scripts/prepare-foundry.ps1",
  "tools/check_abi.py",
  "tools/check_phase9.py",
  "tools/check_phase9_implementation_checkpoints.py",
  "tools/check_phase9_refinance_linked_modules.py",
  "tools/check_phase9_storage_layouts.py",
  "tools/compile_phase9_storage_layouts.mjs",
  "tools/tests/test_phase9_compatibility.py",
  "tools/tests/test_phase9_implementation_checkpoints.py",
  "tools/tests/test_phase9_refinance_linked_modules.py",
  "tools/tests/test_phase9_warning_policy.mjs",
  "tools/tests/test_update_phase9_implementation_checkpoint.py",
  "tools/update_phase9_implementation_checkpoint.py",
];
export const IMPLEMENTATION_EVIDENCE_PATHS = new Map([
  ["CollateralCustodyV2", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
  ["LienRegistry", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
  ["PayoffQuoteEngine", PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS],
  ["Phase9LoanAccount", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
  ["Phase9LoanFactory", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
  ["PositionManagerV2", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
  ["RefinanceCoordinator", REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS],
]);
export const IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS = new Map([
  ["P9-REFI-001", "D2-D4 exact implementation evidence paths are not frozen"],
]);
const PAYOFF_ACTIVATED_SIGNATURES = [
  "consumeQuote(bytes32,bytes32,uint64,bytes32)",
  "invalidateQuote(bytes32,bytes32)",
  "issueQuote(bytes32,uint64)",
];
export const REFINANCE_ACTIVATED_SIGNATURES = new Map([
  [
    "Phase9LoanFactory",
    [
      "createLoan((bytes32,uint64,bytes32,(address,address,address,bytes32,address,address,address,address,address,address,address,address,address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32),bytes32))",
    ],
  ],
  [
    "Phase9LoanAccount",
    [
      "activateReplacementLoan(bytes32,(uint8,uint8,uint64,uint64,uint64,uint64,uint64,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bytes32,bytes32),bytes32)",
      "initialize((address,address,address,bytes32,address,address,address,address,address,address,address,address,address,bytes32,bytes32,bytes32,bytes32,bytes32,bytes32),(uint8,uint8,uint64,uint64,uint64,uint64,uint64,bytes32,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bytes32,bytes32))",
      "recordRefinancePayoff(bytes32,uint256,bytes32)",
    ],
  ],
  [
    "CollateralCustodyV2",
    ["recordCustody((bytes32,bytes32,address,address,uint256,uint8,bytes32),bytes32)"],
  ],
  [
    "LienRegistry",
    [
      "beginHandoff(bytes32,bytes32,bytes32,uint64)",
      "completeHandoff(bytes32,bytes32)",
      "registerLien((bytes32,address,address,bytes32,uint256,address,bytes32,uint64,uint8,bytes32,bytes32))",
    ],
  ],
  [
    "RefinanceCoordinator",
    [
      "cancelRefinance(bytes32,bytes32)",
      "executeRefinance(bytes32,bytes32)",
      "recordFundingCommitment((bytes32,bytes32,bytes32,bytes32,address,uint256,uint64,bytes32,uint8,bytes32))",
      "refundCommitment(bytes32,bytes32)",
      "requestRefinance((bytes32,bytes32,bytes32,address,address,address,bytes32,bytes32,uint256,uint256,bytes32,bytes32,uint64,bytes32,bytes32,uint256,uint256,uint256,uint64,uint64,bytes32,uint64,uint8,uint64,uint256,uint32,bytes32))",
    ],
  ],
  [
    "PositionManagerV2",
    [
      "initialize(bytes32,address,address)",
      "issuePosition((bytes32,bytes32,address,uint256,uint256,uint8))",
      "registerTranche((bytes32,uint32,uint256,uint256,bytes32))",
    ],
  ],
]);
export const REFINANCE_STATE_TRANSITIONED_EVENT = {
  anonymous: false,
  inputs: [
    { indexed: true, internalType: "bytes32", name: "refinanceId", type: "bytes32" },
    {
      indexed: true,
      internalType: "enum Phase9Types.RefinanceState",
      name: "previousState",
      type: "uint8",
    },
    {
      indexed: true,
      internalType: "enum Phase9Types.RefinanceState",
      name: "nextState",
      type: "uint8",
    },
    { indexed: false, internalType: "uint64", name: "stateVersion", type: "uint64" },
    { indexed: false, internalType: "bytes32", name: "operationId", type: "bytes32" },
    { indexed: false, internalType: "bytes32", name: "evidenceHash", type: "bytes32" },
  ],
  name: "RefinanceStateTransitioned",
  type: "event",
};
export const REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR = {
  inputs: [
    {
      internalType: "bytes32",
      name: "commitmentId",
      type: "bytes32",
    },
  ],
  name: "UnknownFundingCommitment",
  type: "error",
};
export const REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR = {
  inputs: [
    {
      internalType: "bytes32",
      name: "handoffId",
      type: "bytes32",
    },
  ],
  name: "UnknownLienHandoff",
  type: "error",
};
export const REFINANCE_COORDINATOR_ABI_ADDITIONS = [
  REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR,
  REFINANCE_STATE_TRANSITIONED_EVENT,
];
export const LIEN_REGISTRY_ABI_ADDITIONS = [REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR];
export const REFINANCE_AUXILIARY_SOURCE_OWNERS = [
  ["protocol/src/interfaces/phase9/ILienRegistry.sol", "LienRegistry"],
  [
    "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
    "RefinanceCoordinator",
  ],
];
export const PACKAGE_AUXILIARY_SOURCE_OWNERS = new Map([
  ["P9-REFI-001", REFINANCE_AUXILIARY_SOURCE_OWNERS],
]);
export const KNOWN_MUTATOR_SIGNATURES = new Map([
  ["PayoffQuoteEngine", PAYOFF_ACTIVATED_SIGNATURES],
  ["Phase9LoanFactory", REFINANCE_ACTIVATED_SIGNATURES.get("Phase9LoanFactory")],
  [
    "Phase9LoanAccount",
    [
      ...REFINANCE_ACTIVATED_SIGNATURES.get("Phase9LoanAccount"),
      "applyRestructuring((bytes32,bytes32,bytes32,uint64,uint64,uint64,uint64,bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,uint256,bytes32),bytes32)",
      "closeLoan(bytes32)",
      "recordCoveredLoss(bytes32,uint256,bytes32)",
      "recordPostWriteOffRecovery(bytes32,uint256,bytes32)",
      "recordRealizedLoss(bytes32,uint256,bytes32)",
      "recordWriteOff(bytes32,uint256,bytes32)",
    ].sort(ordinalUtf8Compare),
  ],
  [
    "CollateralCustodyV2",
    [
      ...REFINANCE_ACTIVATED_SIGNATURES.get("CollateralCustodyV2"),
      "updateCustody(bytes32,uint256,uint8,bytes32)",
    ].sort(ordinalUtf8Compare),
  ],
  ["LienRegistry", REFINANCE_ACTIVATED_SIGNATURES.get("LienRegistry")],
  ["RefinanceCoordinator", REFINANCE_ACTIVATED_SIGNATURES.get("RefinanceCoordinator")],
  [
    "PositionManagerV2",
    [
      ...REFINANCE_ACTIVATED_SIGNATURES.get("PositionManagerV2"),
      "consumeVotingRight(bytes32,bytes32)",
      "createSnapshot((bytes32,bytes32,uint64,uint64,bytes32,uint256,uint32,uint32,uint32,bytes32))",
      "transferPosition(bytes32,address)",
    ].sort(ordinalUtf8Compare),
  ],
]);
const ACTIVATION_PACKAGES = new Map([
  [
    "P9-PAYOFF-001",
    {
      abiAdditions: new Map(),
      contracts: new Map([["PayoffQuoteEngine", PAYOFF_ACTIVATED_SIGNATURES]]),
      requiredBacklogIds: ["UNI-ADR-015", "UNI-PAYOFF-001"],
    },
  ],
  [
    "P9-REFI-001",
    {
      abiAdditions: new Map([
        ["LienRegistry", LIEN_REGISTRY_ABI_ADDITIONS],
        ["RefinanceCoordinator", REFINANCE_COORDINATOR_ABI_ADDITIONS],
      ]),
      contracts: REFINANCE_ACTIVATED_SIGNATURES,
      requiredBacklogIds: [
        "UNI-ADR-016",
        "UNI-ADR-017",
        "UNI-ADR-018",
        "UNI-REFI-001",
        "UNI-REFI-002",
      ],
    },
  ],
]);
// Bind every source that decides checkpoint activation, ABI/storage/schema compatibility,
// generated-schema freshness, warning exemptions, or foundation-gate orchestration.
export const CONTROL_BUNDLE_PATHS = [
  "buf.gen.yaml",
  "buf.yaml",
  "protocol/foundry.toml",
  "scripts/check-foundation.ps1",
  "scripts/generate.ps1",
  "tools/check_abi.py",
  "tools/check_phase9.py",
  "tools/check_phase9_implementation_checkpoints.py",
  "tools/check_phase9_refinance_linked_modules.py",
  "tools/check_phase9_schema.py",
  "tools/check_phase9_storage_layouts.py",
  "tools/compile_phase9_storage_layouts.mjs",
  "tools/tests/test_phase9_compatibility.py",
  "tools/tests/test_phase9_implementation_checkpoints.py",
  "tools/tests/test_phase9_refinance_linked_modules.py",
  "tools/tests/test_phase9_schema.py",
  "tools/tests/test_phase9_warning_policy.mjs",
  "tools/tests/test_update_phase9_implementation_checkpoint.py",
  "tools/update_phase9_implementation_checkpoint.py",
];
const BASELINE = {
  commit: "4f01a5692df92c435ff8893840ebdcca055449f0",
  manifestSha256: "sha256:9237acd53b00f5e90d77bbd4f5ce09590ddb750d079c333be4b14d8e7b4238a2",
  rawFreezeArtifactsSha256:
    "sha256:b0d494141f0e229cf9fd542401036cd63ba04de73e2f056c1e89a25253cdb1a3",
  sourceSetSha256: "sha256:a40ac90f75c52fc7583651d2d57d2a4d82f1899ed673be8b460d17fb7b7425cb",
};
const PAYOFF_ACCEPTED_PACKAGE_SHA256 =
  "sha256:5c5696120704f77edd5cc7fe256cd745e226cc1b33c1b9c01c7cc8250c185545";
const CHECKPOINT_ROOT_KEYS = [
  "baseline",
  "currentControlBundleSha256",
  "currentSourceSetSha256",
  "packages",
  "schemaVersion",
];
const CHECKPOINT_PACKAGE_KEYS = [
  "checkpointId",
  "requiredBacklogIds",
  "review",
  "revisions",
];
const CHECKPOINT_REVIEW_KEYS = [
  "architectureReviewer",
  "implementationAuthor",
  "reviewPath",
  "reviewSha256",
  "reviewedCommit",
  "securityReviewer",
  "status",
  "toolingReviewer",
];
const CHECKPOINT_REVISION_KEYS = [
  "abiSha256",
  "activatedSignatures",
  "contract",
  "dependencyClosureSha256",
  "implementationEvidenceBundleSha256",
  "revision",
  "sourceSha256",
  "sourceSetSha256",
  "storageStructuralSha256",
  "supersedes",
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

function repositoryPath(path, root = ROOT) {
  const result = relative(root, path);
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

export function foundryRemappings(root = ROOT) {
  const configPath = resolve(root, "protocol/foundry.toml");
  let content;
  try {
    content = readFileSync(configPath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") throw new Error("protocol/foundry.toml is missing");
    throw error;
  }
  const sectionStart = /^\[profile\.default\][ \t]*$/m.exec(content);
  if (sectionStart === null) throw new Error("Foundry default profile is missing");
  const sectionOffset = sectionStart.index + sectionStart[0].length;
  const remainder = content.slice(sectionOffset);
  const nextSection = /^\[[^\r\n]+\][ \t]*$/m.exec(remainder);
  const section = remainder.slice(0, nextSection?.index ?? remainder.length);
  const declarations = [...section.matchAll(/^[ \t]*remappings[ \t]*=[ \t]*\[([\s\S]*?)\]/gm)];
  if (declarations.length !== 1) throw new Error("Foundry remappings are missing or malformed");
  const body = declarations[0][1];
  const entries = [];
  let cursor = 0;
  while (cursor < body.length) {
    while (cursor < body.length && /[\s,]/.test(body[cursor])) cursor += 1;
    if (cursor === body.length) break;
    const token = /"(?:\\.|[^"\\])*"/y;
    token.lastIndex = cursor;
    const match = token.exec(body);
    if (match === null) throw new Error("Foundry remapping entry is not a basic string");
    entries.push(JSON.parse(match[0]));
    cursor = token.lastIndex;
    while (cursor < body.length && /\s/.test(body[cursor])) cursor += 1;
    if (cursor < body.length && body[cursor] !== ",") {
      throw new Error("Foundry remapping array is malformed");
    }
  }

  const parsed = new Map();
  for (const entry of entries) {
    const separator = entry.indexOf("=");
    const prefix = entry.slice(0, separator);
    const target = entry.slice(separator + 1);
    if (separator <= 0 || target.length === 0 || parsed.has(prefix)) {
      throw new Error(`Foundry remapping entry is malformed: ${entry}`);
    }
    const targetPath = resolve(dirname(configPath), target);
    if (!repositoryPath(targetPath, root)) {
      throw new Error(`Foundry remapping target is outside the repository: ${entry}`);
    }
    parsed.set(prefix, targetPath);
  }
  return [...parsed.entries()].sort(
    ([left], [right]) => right.length - left.length || ordinalUtf8Compare(left, right),
  );
}

function repositoryImportPath(sourcePath, importPath, root) {
  let candidates;
  if (importPath.startsWith(".")) {
    candidates = [resolve(dirname(sourcePath), importPath)];
  } else {
    const remapping = foundryRemappings(root).find(([prefix]) => importPath.startsWith(prefix));
    if (remapping !== undefined) {
      const [prefix, target] = remapping;
      try {
        if (!statSync(target).isDirectory()) throw new Error("target is not a directory");
      } catch (error) {
        if (error?.code === "ENOENT") {
          throw new Error(
            `Prepared Foundry remapping target is missing: ${relative(root, target)}`,
          );
        }
        throw error;
      }
      candidates = [resolve(target, importPath.slice(prefix.length))];
    } else {
      candidates = [resolve(root, importPath), resolve(root, "protocol/src", importPath)];
    }
  }
  for (const candidate of candidates) {
    if (!repositoryPath(candidate, root)) {
      if (importPath.startsWith(".")) {
        throw new Error(`${relative(root, sourcePath)} imports outside the repository: ${importPath}`);
      }
      continue;
    }
    try {
      if (!statSync(candidate).isFile()) continue;
      if (!candidate.toLowerCase().endsWith(".sol")) {
        throw new Error(
          `${relative(root, sourcePath)} imports a non-Solidity repository file: ${importPath}`,
        );
      }
      return candidate;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  const kind = [".", "protocol/", "src/"].some((prefix) => importPath.startsWith(prefix))
    ? "repository"
    : "non-relative";
  throw new Error(`${relative(root, sourcePath)} has an unresolved ${kind} import: ${importPath}`);
}

export function repositorySolidityDependencyPaths(sourcePath, { root = ROOT } = {}) {
  const rootSource = resolve(root, sourcePath);
  if (!repositoryPath(rootSource, root)) {
    throw new Error("Phase 9 implementation source is outside the repository");
  }
  const pending = [rootSource];
  const observed = new Set();
  while (pending.length > 0) {
    const current = pending.pop();
    if (observed.has(current)) continue;
    observed.add(current);
    for (const importPath of solidityImports(current)) {
      const dependency = repositoryImportPath(current, importPath, root);
      if (!observed.has(dependency)) pending.push(dependency);
    }
  }
  return [...observed].sort((left, right) =>
    ordinalUtf8Compare(
      relative(root, left).split(sep).join("/"),
      relative(root, right).split(sep).join("/"),
    ),
  );
}

export function repositorySolidityDependencyHash(sourcePath, { root = ROOT } = {}) {
  const payload = repositorySolidityDependencyPaths(sourcePath, { root })
    .map((path) => ({
      path: relative(root, path).split(sep).join("/"),
      sha256: sha256(readFileSync(path)),
    }));
  return sha256(canonicalJson(payload));
}

export function validatePackageAuxiliarySourceOwners(
  checkpointId,
  {
    entries = PACKAGE_AUXILIARY_SOURCE_OWNERS.get(checkpointId) ?? [],
    root = ROOT,
  } = {},
) {
  const definition = ACTIVATION_PACKAGES.get(checkpointId);
  if (definition === undefined) {
    throw new Error(`${checkpointId}: auxiliary source ownership is not activated`);
  }
  if (
    !Array.isArray(entries) ||
    entries.some(
      (entry) =>
        !Array.isArray(entry) ||
        entry.length !== 2 ||
        entry.some((value) => typeof value !== "string"),
    )
  ) {
    throw new Error(`${checkpointId}: auxiliary source ownership is malformed`);
  }

  const paths = entries.map(([path]) => path);
  if (new Set(paths).size !== paths.length) {
    throw new Error(`${checkpointId}: auxiliary source path is duplicated`);
  }
  const ordered = [...paths].sort(ordinalUtf8Compare);
  if (!ordered.every((path, index) => path === paths[index])) {
    throw new Error(`${checkpointId}: auxiliary source paths are not ordinal`);
  }

  const dependenciesByOwner = new Map();
  for (const [path, owner] of entries) {
    if (!definition.contracts.has(owner)) {
      throw new Error(`${checkpointId}: auxiliary source owner is not activated: ${owner}`);
    }
    const ownerSource = ACTIVATED_IMPLEMENTATION_SOURCES.get(owner);
    if (ownerSource === undefined) {
      throw new Error(`${checkpointId}: auxiliary source owner has no source: ${owner}`);
    }
    if (path === ownerSource) {
      throw new Error(`${checkpointId}: auxiliary source overlaps its owner source: ${path}`);
    }
    let dependencies = dependenciesByOwner.get(owner);
    if (dependencies === undefined) {
      dependencies = new Set(
        repositorySolidityDependencyPaths(ownerSource, { root }).map((dependency) =>
          relative(root, dependency).split(sep).join("/"),
        ),
      );
      dependenciesByOwner.set(owner, dependencies);
    }
    if (!dependencies.has(path)) {
      throw new Error(
        `${checkpointId}: auxiliary source is not a dependency of ${owner}: ${path}`,
      );
    }
  }
  return entries;
}

function gitHashPaths(paths, { root, clean }) {
  if (paths.some((path) => path.includes("\n") || path.includes("\r"))) {
    throw new Error("reviewed input path contains a line break");
  }
  const arguments_ = ["hash-object", "--stdin-paths"];
  if (!clean) arguments_.push("--no-filters");
  const result = spawnSync("git", arguments_, {
    cwd: root,
    input: `${paths.join("\n")}\n`,
    encoding: "utf8",
    windowsHide: true,
  });
  const digests = result.stdout?.trim().split(/\r?\n/) ?? [];
  if (
    result.error !== undefined ||
    result.status !== 0 ||
    digests.length !== paths.length ||
    digests.some((digest) => !/^[0-9a-f]{40}$/.test(digest))
  ) {
    throw new Error("Git cannot hash reviewed input paths");
  }
  return digests;
}

export function requireGitCleanWorktreeBytes(paths, { root = ROOT } = {}) {
  const rawDigests = gitHashPaths(paths, { root, clean: false });
  const cleanDigests = gitHashPaths(paths, { root, clean: true });
  for (const [index, path] of paths.entries()) {
    if (rawDigests[index] !== cleanDigests[index]) {
      throw new Error(`worktree bytes differ from Git-clean canonical bytes: ${path}`);
    }
  }
}

export function implementationEvidenceBundleSha256(contract, { root = ROOT } = {}) {
  const paths = IMPLEMENTATION_EVIDENCE_PATHS.get(contract);
  if (paths === undefined) {
    throw new Error(`${contract}: implementation evidence bundle is not activated`);
  }
  if (new Set(paths).size !== paths.length) {
    throw new Error(`${contract}: implementation evidence bundle contains duplicate paths`);
  }
  const ordered = [...paths].sort(ordinalUtf8Compare);
  if (!ordered.every((path, index) => path === paths[index])) {
    throw new Error(`${contract}: implementation evidence bundle paths are not ordinal`);
  }
  const payload = paths.map((path) => {
    const absolute = resolve(root, path);
    if (!repositoryPath(absolute, root)) {
      throw new Error(`${contract}: implementation evidence path is outside the repository: ${path}`);
    }
    try {
      if (!statSync(absolute).isFile()) throw new Error("not a file");
    } catch (error) {
      if (error?.code === "ENOENT") {
        throw new Error(`${contract}: implementation evidence is missing: ${path}`);
      }
      throw error;
    }
    return { path, sha256: sha256(readFileSync(absolute)) };
  });
  requireGitCleanWorktreeBytes(paths, { root });
  return sha256(canonicalJson(payload));
}

export function controlBundleSha256({ root = ROOT } = {}) {
  if (new Set(CONTROL_BUNDLE_PATHS).size !== CONTROL_BUNDLE_PATHS.length) {
    throw new Error("Phase 9 control bundle contains duplicate paths");
  }
  const ordered = [...CONTROL_BUNDLE_PATHS].sort(ordinalUtf8Compare);
  if (!ordered.every((path, index) => path === CONTROL_BUNDLE_PATHS[index])) {
    throw new Error("Phase 9 control bundle paths are not ordinal");
  }
  const payload = CONTROL_BUNDLE_PATHS.map((path) => {
    const absolute = resolve(root, path);
    if (!repositoryPath(absolute, root)) {
      throw new Error(`Phase 9 control bundle path is outside the repository: ${path}`);
    }
    try {
      if (!statSync(absolute).isFile()) throw new Error("not a file");
    } catch (error) {
      if (error?.code === "ENOENT") {
        throw new Error(`Phase 9 control bundle input is missing: ${path}`);
      }
      throw error;
    }
    return { path, sha256: sha256(readFileSync(absolute)) };
  });
  requireGitCleanWorktreeBytes(CONTROL_BUNDLE_PATHS, { root });
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

function canonicalAbiType(parameter) {
  if (typeof parameter?.type !== "string") {
    throw new Error("Phase 9 ABI contains a malformed parameter");
  }
  if (!parameter.type.startsWith("tuple")) return parameter.type;
  if (!Array.isArray(parameter.components)) {
    throw new Error("Phase 9 ABI tuple parameter lacks components");
  }
  const suffix = parameter.type.slice("tuple".length);
  return `(${parameter.components.map(canonicalAbiType).join(",")})${suffix}`;
}

function canonicalAbiSignature(entry) {
  return `${entry.name}(${entry.inputs.map(canonicalAbiType).join(",")})`;
}

function abiItemIdentity(entry) {
  if (entry === null || typeof entry !== "object" || typeof entry.type !== "string") {
    throw new Error("Phase 9 ABI contains a malformed item");
  }
  const name = entry.name ?? "";
  const inputs = entry.inputs ?? [];
  if (typeof name !== "string" || !Array.isArray(inputs)) {
    throw new Error("Phase 9 ABI contains a malformed named item");
  }
  return `${entry.type}:${name}(${inputs.map(canonicalAbiType).join(",")})`;
}

function abiSortKey(entry) {
  const order = new Map([
    ["constructor", 0],
    ["error", 1],
    ["event", 2],
    ["function", 3],
  ]);
  const rank = order.get(entry?.type);
  if (rank === undefined) {
    throw new Error(`Phase 9 ABI contains an unsupported item type: ${entry?.type}`);
  }
  return [rank, abiItemIdentity(entry)];
}

export function additiveAbiPayload(baseline, additions) {
  if (!Array.isArray(baseline) || !Array.isArray(additions)) {
    throw new Error("Phase 9 additive ABI inputs must be arrays");
  }
  const payload = structuredClone(baseline);
  const identities = new Set(payload.map(abiItemIdentity));
  if (identities.size !== payload.length) {
    throw new Error("Phase 9 baseline ABI contains duplicate canonical items");
  }
  for (const addition of additions) {
    if (!["error", "event"].includes(addition?.type)) {
      throw new Error("Phase 9 additive ABI allowlist may contain errors and events only");
    }
    const identity = abiItemIdentity(addition);
    if (identities.has(identity)) {
      throw new Error(`Phase 9 additive ABI item is duplicated: ${identity}`);
    }
    identities.add(identity);
    payload.push(structuredClone(addition));
  }
  return payload.sort((left, right) => {
    const [leftRank, leftIdentity] = abiSortKey(left);
    const [rightRank, rightIdentity] = abiSortKey(right);
    return leftRank - rightRank || ordinalUtf8Compare(leftIdentity, rightIdentity);
  });
}

function contractMutatorSignatures(output, sourceName, contractName) {
  const abi = output.contracts?.[sourceName]?.[contractName]?.abi;
  if (!Array.isArray(abi)) {
    throw new Error(`${contractName}: compiler did not return ABI`);
  }
  const byName = new Map();
  for (const entry of abi) {
    if (
      entry?.type !== "function" ||
      !["nonpayable", "payable"].includes(entry.stateMutability) ||
      typeof entry.name !== "string" ||
      !Array.isArray(entry.inputs)
    ) {
      continue;
    }
    const signature = canonicalAbiSignature(entry);
    const signatures = byName.get(entry.name) ?? [];
    signatures.push(signature);
    byName.set(entry.name, signatures);
  }
  return byName;
}

function functionSignature(signaturesByName, node, contractName) {
  const candidates = signaturesByName.get(node.name) ?? [];
  const parameterCount = node.parameters?.parameters?.length ?? 0;
  const matching = candidates.filter((signature) => {
    const abi = signature.slice(signature.indexOf("(") + 1, -1);
    if (abi.length === 0) return parameterCount === 0;
    let depth = 0;
    let count = 1;
    for (const character of abi) {
      if (character === "(") depth += 1;
      if (character === ")") depth -= 1;
      if (character === "," && depth === 0) count += 1;
    }
    return count === parameterCount;
  });
  if (matching.length !== 1) {
    throw new Error(`${contractName}.${node.name}: mutator ABI signature is ambiguous`);
  }
  return matching[0];
}

function functionLabel(sourceName, contractName, signature) {
  return `${sourceName}:${contractName}.${signature}`;
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
      const signaturesByName = contractMutatorSignatures(
        output,
        sourceName,
        contract.name,
      );
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
        const signature = functionSignature(signaturesByName, node, contract.name);
        functions.push({
          ...sourceRange(node),
          contract: contract.name,
          key: `${sourceName}:${node.id}`,
          label: functionLabel(sourceName, contract.name, signature),
          signature,
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
      const signaturesByName = contractMutatorSignatures(
        output,
        sourceName,
        contract.name,
      );
      for (const node of contract.nodes ?? []) {
        if (
          node.nodeType === "FunctionDefinition" &&
          node.kind === "function" &&
          ["external", "public"].includes(node.visibility) &&
          !["view", "pure"].includes(node.stateMutability)
        ) {
          const signature = functionSignature(signaturesByName, node, contract.name);
          functions.push({
            ...sourceRange(node),
            contract: contract.name,
            key: `${sourceName}:${node.id}`,
            label: functionLabel(sourceName, contract.name, signature),
            signature,
            sourceName,
          });
        }
      }
    }
  }
  return functions;
}

function checkpointLatestRevisions(payload) {
  if (
    !exactKeys(payload, CHECKPOINT_ROOT_KEYS) ||
    payload.schemaVersion !== 2 ||
    !Array.isArray(payload.packages) ||
    !exactKeys(payload.baseline, Object.keys(BASELINE)) ||
    canonicalJson(payload.baseline) !== canonicalJson(BASELINE) ||
    !SHA256_PATTERN.test(payload.currentControlBundleSha256) ||
    !SHA256_PATTERN.test(payload.currentSourceSetSha256)
  ) {
    throw new Error("Phase 9 implementation checkpoint registry is malformed");
  }

  const observedPackages = [];
  const latest = new Map();
  const origins = new Map();
  let effectiveAbis = new Map(
    PHASE9_PRODUCTION_CONTRACTS.map((contract) => [
      contract,
      JSON.parse(
        readFileSync(resolve(ROOT, `protocol/abi/phase9/${contract}.abi.json`), "utf8"),
      ),
    ]),
  );
  for (const checkpointPackage of payload.packages) {
    if (!exactKeys(checkpointPackage, CHECKPOINT_PACKAGE_KEYS)) {
      throw new Error("Phase 9 checkpoint package fields drifted");
    }
    const definition = ACTIVATION_PACKAGES.get(checkpointPackage.checkpointId);
    if (definition === undefined || observedPackages.includes(checkpointPackage.checkpointId)) {
      throw new Error("Phase 9 checkpoint package is not uniquely activated");
    }
    const closureLimitation = IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS.get(
      checkpointPackage.checkpointId,
    );
    if (closureLimitation !== undefined) {
      throw new Error(
        `${checkpointPackage.checkpointId}: implementation evidence closure is incomplete: ` +
          closureLimitation,
      );
    }
    validatePackageAuxiliarySourceOwners(checkpointPackage.checkpointId);
    observedPackages.push(checkpointPackage.checkpointId);
    if (
      !Array.isArray(checkpointPackage.requiredBacklogIds) ||
      canonicalJson(checkpointPackage.requiredBacklogIds) !==
        canonicalJson(definition.requiredBacklogIds) ||
      !Array.isArray(checkpointPackage.revisions) ||
      checkpointPackage.revisions.length === 0
    ) {
      throw new Error(`${checkpointPackage.checkpointId}: package activation drifted`);
    }
    const review = checkpointPackage.review;
    if (
      !exactKeys(review, CHECKPOINT_REVIEW_KEYS) ||
      !Object.values(review).every((value) => typeof value === "string") ||
      review.status !== "PASS" ||
      !SHA256_PATTERN.test(review.reviewSha256) ||
      !/^[0-9a-f]{40}$/.test(review.reviewedCommit)
    ) {
      throw new Error(`${checkpointPackage.checkpointId}: review identity fields drifted`);
    }
    const identities = [
      review.implementationAuthor,
      review.architectureReviewer,
      review.securityReviewer,
      review.toolingReviewer,
    ];
    if (
      identities.some((identity) => identity.trim().length === 0) ||
      new Set(identities.map((identity) => identity.toLocaleLowerCase("en-US"))).size !== 4
    ) {
      throw new Error(`${checkpointPackage.checkpointId}: review identities are ambiguous`);
    }

    const packageContracts = [];
    const packageAbis = new Map(effectiveAbis);
    for (const revision of checkpointPackage.revisions) {
      if (
        !exactKeys(revision, CHECKPOINT_REVISION_KEYS) ||
        !PHASE9_PRODUCTION_CONTRACTS.includes(revision.contract) ||
        packageContracts.includes(revision.contract) ||
        !Number.isSafeInteger(revision.revision) ||
        revision.revision < 1 ||
        !Array.isArray(revision.activatedSignatures) ||
        [
          revision.abiSha256,
          revision.dependencyClosureSha256,
          revision.implementationEvidenceBundleSha256,
          revision.sourceSha256,
          revision.sourceSetSha256,
          revision.storageStructuralSha256,
        ].some((value) => typeof value !== "string" || !SHA256_PATTERN.test(value))
      ) {
        throw new Error(`${checkpointPackage.checkpointId}: contract revision fields drifted`);
      }
      packageContracts.push(revision.contract);
      const expectedSignatures = definition.contracts.get(revision.contract);
      if (
        expectedSignatures === undefined ||
        canonicalJson(revision.activatedSignatures) !== canonicalJson(expectedSignatures)
      ) {
        throw new Error(
          `${checkpointPackage.checkpointId}/${revision.contract}: activated signatures drifted`,
        );
      }
      const expectedAbi = additiveAbiPayload(
        effectiveAbis.get(revision.contract),
        definition.abiAdditions.get(revision.contract) ?? [],
      );
      if (revision.abiSha256 !== sha256(canonicalJson(expectedAbi))) {
        throw new Error(
          `${checkpointPackage.checkpointId}/${revision.contract}: additive ABI drifted`,
        );
      }
      packageAbis.set(revision.contract, expectedAbi);
      const prior = latest.get(revision.contract);
      const expectedRevision = prior === undefined ? 1 : prior.revision + 1;
      if (revision.revision !== expectedRevision) {
        throw new Error(
          `${checkpointPackage.checkpointId}/${revision.contract}: revision is not monotonic`,
        );
      }
      if (prior === undefined) {
        if (revision.supersedes !== null) {
          throw new Error(
            `${checkpointPackage.checkpointId}/${revision.contract}: first revision supersedes`,
          );
        }
      } else {
        const previous = origins.get(revision.contract);
        if (
          !exactKeys(revision.supersedes, ["checkpointId", "revision"]) ||
          revision.supersedes.checkpointId !== previous.checkpointId ||
          revision.supersedes.revision !== previous.revision ||
          !prior.activatedSignatures.every((signature) =>
            revision.activatedSignatures.includes(signature),
          )
        ) {
          throw new Error(
            `${checkpointPackage.checkpointId}/${revision.contract}: supersession drifted`,
          );
        }
      }
      latest.set(revision.contract, revision);
      origins.set(revision.contract, {
        checkpointId: checkpointPackage.checkpointId,
        revision: revision.revision,
      });
    }
    const expectedContractOrder = PHASE9_PRODUCTION_CONTRACTS.filter((contract) =>
      definition.contracts.has(contract),
    );
    if (canonicalJson(packageContracts) !== canonicalJson(expectedContractOrder)) {
      throw new Error(`${checkpointPackage.checkpointId}: contract revision order drifted`);
    }
    if (
      checkpointPackage.checkpointId === "P9-PAYOFF-001" &&
      sha256(canonicalJson(checkpointPackage)) !== PAYOFF_ACCEPTED_PACKAGE_SHA256
    ) {
      throw new Error("P9-PAYOFF-001: accepted package identity drifted");
    }
    effectiveAbis = packageAbis;
  }

  const expectedPackageOrder = [...ACTIVATION_PACKAGES.keys()].filter((checkpointId) =>
    observedPackages.includes(checkpointId),
  );
  if (canonicalJson(observedPackages) !== canonicalJson(expectedPackageOrder)) {
    throw new Error("Phase 9 checkpoint package order drifted");
  }
  return latest;
}

function expectedCurrentAbis(payload) {
  checkpointLatestRevisions(payload);
  const abis = new Map(
    PHASE9_PRODUCTION_CONTRACTS.map((contract) => [
      contract,
      JSON.parse(
        readFileSync(resolve(ROOT, `protocol/abi/phase9/${contract}.abi.json`), "utf8"),
      ),
    ]),
  );
  for (const checkpointPackage of payload.packages) {
    const definition = ACTIVATION_PACKAGES.get(checkpointPackage.checkpointId);
    for (const revision of checkpointPackage.revisions) {
      abis.set(
        revision.contract,
        additiveAbiPayload(
          abis.get(revision.contract),
          definition.abiAdditions.get(revision.contract) ?? [],
        ),
      );
    }
  }
  return abis;
}

export function validateCheckpointAbiAdditions(output, payload) {
  const expected = expectedCurrentAbis(payload);
  const observed = new Map();
  for (const contracts of Object.values(output.contracts ?? {})) {
    for (const [contract, artifact] of Object.entries(contracts)) {
      if (!PHASE9_PRODUCTION_CONTRACTS.includes(contract)) continue;
      if (observed.has(contract) || !Array.isArray(artifact.abi)) {
        throw new Error(`${contract}: compiled ABI is missing or duplicated`);
      }
      observed.set(contract, artifact.abi);
    }
  }
  for (const contract of PHASE9_PRODUCTION_CONTRACTS) {
    if (canonicalJson(observed.get(contract)) !== canonicalJson(expected.get(contract))) {
      throw new Error(`${contract}: compiled ABI differs from the historical plus additive set`);
    }
  }
}

export function phase9ActivatedSignatures(payload) {
  return new Map(
    [...checkpointLatestRevisions(payload)].map(([contract, revision]) => [
      contract,
      new Set(revision.activatedSignatures),
    ]),
  );
}

export function phase9StubContracts(payload) {
  const activated = phase9ActivatedSignatures(payload);
  return PHASE9_PRODUCTION_CONTRACTS.filter(
    (contract) => (activated.get(contract)?.size ?? 0) === 0,
  );
}

export function phase9WarningStubContracts(payload) {
  const activated = phase9ActivatedSignatures(payload);
  return PHASE9_PRODUCTION_CONTRACTS.filter((contract) => {
    const active = activated.get(contract) ?? new Set();
    const known = KNOWN_MUTATOR_SIGNATURES.get(contract);
    return known === undefined || known.some((signature) => !active.has(signature));
  });
}

export function validateCheckpointDependencyClosures(payload) {
  if (payload.currentControlBundleSha256 !== controlBundleSha256()) {
    throw new Error("Phase 9 current control-bundle hash is stale");
  }
  for (const [contract, revision] of checkpointLatestRevisions(payload)) {
    const sourcePath = ACTIVATED_IMPLEMENTATION_SOURCES.get(contract);
    if (sourcePath === undefined) {
      throw new Error(`${contract}: implementation dependency closure is not activated`);
    }
    const actual = repositorySolidityDependencyHash(sourcePath);
    if (actual !== revision.dependencyClosureSha256) {
      throw new Error(`${contract}: reviewed Solidity dependency closure hash is stale`);
    }
  }
}

export function validatePhase9MutabilityDiagnostics(
  output,
  {
    activatedSignatures = new Map(),
    expectedCount,
    productionContracts = PHASE9_PRODUCTION_CONTRACTS,
  } = {},
) {
  const mutators = externalMutators(output, productionContracts);
  const canonical = canonicalFreezeMutators(output, productionContracts);
  const canonicalKeys = new Set(canonical.map((fn) => fn.key));
  const mutatorSignatures = new Map();
  for (const mutator of mutators) {
    const signatures = mutatorSignatures.get(mutator.contract) ?? new Set();
    signatures.add(mutator.signature);
    mutatorSignatures.set(mutator.contract, signatures);
    const active = activatedSignatures.get(mutator.contract)?.has(mutator.signature) ?? false;
    if (active === canonicalKeys.has(mutator.key)) {
      throw new Error(
        active
          ? `Activated Phase 9 mutator remains frozen: ${mutator.label}`
          : `Unopened Phase 9 mutator is not the exact freeze stub: ${mutator.label}`,
      );
    }
  }
  for (const [contract, signatures] of activatedSignatures) {
    const canonicalSignatures = mutatorSignatures.get(contract);
    if (
      canonicalSignatures === undefined ||
      [...signatures].some((signature) => !canonicalSignatures.has(signature))
    ) {
      throw new Error(`${contract}: checkpoint activates a noncanonical mutator signature`);
    }
  }

  const unopened = mutators.filter(
    (mutator) =>
      !(activatedSignatures.get(mutator.contract)?.has(mutator.signature) ?? false),
  );
  const requiredCount = expectedCount ?? unopened.length;
  if (canonical.length !== requiredCount || unopened.length !== requiredCount) {
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
    if (activatedSignatures.get(candidate.contract)?.has(candidate.signature) ?? false) {
      throw new Error(`Warning 2018 targets activated Phase 9 mutator: ${candidate.label}`);
    }
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
  const initialDependencyClosureSha256 = repositorySolidityDependencyHash(COMPILATION_ROOT);

  const input = {
    language: "Solidity",
    settings: {
      ...COMPILER_SETTINGS,
      outputSelection: {
        "*": { "": ["ast"], "*": ["abi", "storageLayout"] },
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
  const activated = phase9ActivatedSignatures(checkpointPayload);
  validateCheckpointDependencyClosures(checkpointPayload);
  validateCheckpointAbiAdditions(output, checkpointPayload);
  validatePhase9MutabilityDiagnostics(output, { activatedSignatures: activated });

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

  const finalDependencyClosureSha256 = repositorySolidityDependencyHash(COMPILATION_ROOT);
  if (finalDependencyClosureSha256 !== initialDependencyClosureSha256) {
    throw new Error("Protocol compilation dependency closure changed during storage compilation");
  }

  const artifact = canonicalize({
    compilationDependencyClosureSha256: finalDependencyClosureSha256,
    contracts: Object.fromEntries(PHASE9_CONTRACTS.map((name) => [name, matches.get(name)])),
    schemaVersion: 2,
  });
  await mkdir(dirname(OUTPUT_PATH), { recursive: true });
  await writeFile(OUTPUT_PATH, `${JSON.stringify(artifact, null, 2)}\n`, "utf8");
  process.stdout.write(`Phase 9 storage layouts compiled (${PHASE9_CONTRACTS.length} contracts).\n`);
}

if (process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
