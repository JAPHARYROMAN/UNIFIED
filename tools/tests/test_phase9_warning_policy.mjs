import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";

import {
  additiveAbiPayload,
  controlBundleSha256,
  CONTROL_BUNDLE_PATHS,
  implementationEvidenceBundleSha256,
  IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS,
  IMPLEMENTATION_EVIDENCE_PATHS,
  LIEN_REGISTRY_ABI_ADDITIONS,
  ordinalUtf8Compare,
  PACKAGE_AUXILIARY_SOURCE_OWNERS,
  PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS,
  PHASE9_PRODUCTION_CONTRACTS,
  phase9ActivatedSignatures,
  phase9StubContracts,
  phase9WarningStubContracts,
  REFINANCE_ACTIVATED_SIGNATURES,
  REFINANCE_AUXILIARY_SOURCE_OWNERS,
  REFINANCE_COORDINATOR_ABI_ADDITIONS,
  REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
  REFINANCE_STATE_TRANSITIONED_EVENT,
  REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR,
  REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR,
  requireGitCleanWorktreeBytes,
  repositorySolidityDependencyHash,
  repositorySolidityDependencyPaths,
  solidityImportsFromSource,
  validateCheckpointAbiAdditions,
  validateCheckpointDependencyClosures,
  validatePackageAuxiliarySourceOwners,
  validatePhase9MutabilityDiagnostics,
} from "../compile_phase9_storage_layouts.mjs";

const SOURCE = "protocol/src/resolution/Phase9LoanFactory.sol";
const HASH = `sha256:${"1".repeat(64)}`;
const BASELINE = {
  commit: "4f01a5692df92c435ff8893840ebdcca055449f0",
  manifestSha256: "sha256:9237acd53b00f5e90d77bbd4f5ce09590ddb750d079c333be4b14d8e7b4238a2",
  rawFreezeArtifactsSha256:
    "sha256:b0d494141f0e229cf9fd542401036cd63ba04de73e2f056c1e89a25253cdb1a3",
  sourceSetSha256: "sha256:a40ac90f75c52fc7583651d2d57d2a4d82f1899ed673be8b460d17fb7b7425cb",
};

function runGit(root, ...arguments_) {
  const result = spawnSync("git", arguments_, {
    cwd: root,
    encoding: "utf8",
    windowsHide: true,
  });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

const REGISTRY = JSON.parse(
  readFileSync(resolve("protocol/compatibility/phase9-implementation-checkpoints.json"), "utf8"),
);
const PAYOFF_PACKAGE = REGISTRY.packages[0];

function baselineCompiledOutput() {
  return {
    contracts: Object.fromEntries(
      PHASE9_PRODUCTION_CONTRACTS.map((contract) => [
        `compiled/${contract}.sol`,
        {
          [contract]: {
            abi: JSON.parse(
              readFileSync(resolve(`protocol/abi/phase9/${contract}.abi.json`), "utf8"),
            ),
          },
        },
      ]),
    ),
  };
}

function checkpointRevision(overrides = {}) {
  return {
    ...structuredClone(PAYOFF_PACKAGE.revisions[0]),
    contract: "PayoffQuoteEngine",
    ...overrides,
  };
}

function checkpointPackage({
  checkpointId = "P9-PAYOFF-001",
  requiredBacklogIds = ["UNI-ADR-015", "UNI-PAYOFF-001"],
  review = {},
  revision = {},
} = {}) {
  return {
    checkpointId,
    requiredBacklogIds,
    review: { ...structuredClone(PAYOFF_PACKAGE.review), ...review },
    revisions: [checkpointRevision(revision)],
  };
}

function checkpointRegistry(packages = []) {
  return {
    baseline: BASELINE,
    currentControlBundleSha256: controlBundleSha256(),
    currentSourceSetSha256: HASH,
    packages,
    schemaVersion: 2,
  };
}

function freezeFunction(id, start, errorName = "Phase9ImplementationNotFrozen") {
  return {
    body: {
      statements: [
        {
          errorCall: { expression: { name: errorName } },
          nodeType: "RevertStatement",
        },
      ],
    },
    id,
    kind: "function",
    modifiers: [],
    name: `mutate${id}`,
    nodeType: "FunctionDefinition",
    parameters: { parameters: [] },
    src: `${start}:40:0`,
    stateMutability: "nonpayable",
    visibility: "external",
  };
}

function fixture(
  functions,
  locations,
  { contract = "Phase9LoanFactory", source = SOURCE } = {},
) {
  const abi = functions.map((fn) => ({
    inputs: [],
    name: fn.name,
    outputs: [],
    stateMutability: fn.stateMutability,
    type: "function",
  }));
  return {
    contracts: { [source]: { [contract]: { abi } } },
    errors: locations.map(({ end, file = source, start }) => ({
      errorCode: "2018",
      severity: "warning",
      sourceLocation: { end, file, start },
    })),
    sources: {
      [source]: {
        ast: {
          nodes: [
            {
              name: contract,
              nodeType: "ContractDefinition",
              nodes: functions,
            },
          ],
        },
      },
    },
  };
}

test("accepts exact warning-to-canonical-mutator equality", () => {
  assert.doesNotThrow(() =>
    validatePhase9MutabilityDiagnostics(fixture([freezeFunction(1, 0)], [{ start: 5, end: 10 }]), {
      expectedCount: 1,
      productionContracts: ["Phase9LoanFactory"],
    }),
  );
});

test("rejects warning 2018 on a noncanonical function in an allowed file", () => {
  const output = fixture(
    [freezeFunction(1, 0), freezeFunction(2, 50, "DifferentError")],
    [{ start: 55, end: 60 }],
  );
  assert.throws(
    () =>
      validatePhase9MutabilityDiagnostics(output, {
        expectedCount: 1,
        productionContracts: ["Phase9LoanFactory"],
      }),
    /not the exact freeze stub/,
  );
});

test("rejects a canonical mutator without its warning 2018", () => {
  assert.throws(
    () =>
      validatePhase9MutabilityDiagnostics(fixture([freezeFunction(1, 0)], []), {
        expectedCount: 1,
        productionContracts: ["Phase9LoanFactory"],
      }),
    /Expected 1 Phase 9 warning-2018 diagnostics, found 0/,
  );
});

test("allows only the exact activated signature while sibling methods remain frozen", () => {
  const output = fixture(
    [freezeFunction(1, 0), freezeFunction(2, 50, "DifferentError")],
    [{ start: 5, end: 10 }],
  );
  assert.doesNotThrow(() =>
    validatePhase9MutabilityDiagnostics(output, {
      activatedSignatures: new Map([["Phase9LoanFactory", new Set(["mutate2()"])]]),
      expectedCount: 1,
      productionContracts: ["Phase9LoanFactory"],
    }),
  );
  assert.throws(
    () =>
      validatePhase9MutabilityDiagnostics(output, {
        activatedSignatures: new Map([["Phase9LoanFactory", new Set(["mutate1()"])]]),
        expectedCount: 1,
        productionContracts: ["Phase9LoanFactory"],
      }),
    /Activated Phase 9 mutator remains frozen/,
  );
});

test("derives the exact stub set from implementation checkpoints", () => {
  const stubs = phase9StubContracts(checkpointRegistry([checkpointPackage()]));
  assert.equal(stubs.includes("PayoffQuoteEngine"), false);
  assert.equal(stubs.includes("Phase9LoanAccount"), true);
  assert.equal(stubs.length, 12);
});

test("derives warning exemptions from whether any canonical mutator remains frozen", () => {
  const beforeCheckpoint = phase9WarningStubContracts(checkpointRegistry());
  const afterCheckpoint = phase9WarningStubContracts(
    checkpointRegistry([checkpointPackage()]),
  );

  assert.equal(phase9StubContracts(checkpointRegistry()).includes("PayoffQuoteEngine"), true);
  assert.equal(beforeCheckpoint.includes("PayoffQuoteEngine"), true);
  assert.equal(beforeCheckpoint.includes("Phase9LoanAccount"), true);
  assert.equal(beforeCheckpoint.length, 13);
  assert.equal(afterCheckpoint.includes("PayoffQuoteEngine"), false);
  assert.equal(afterCheckpoint.length, 12);
});

test("rejects unknown or duplicate checkpoint packages", () => {
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointPackage({ checkpointId: "P9-UNKNOWN-001" })]),
      ),
    /not uniquely activated/,
  );
  assert.throws(
    () =>
      phase9StubContracts(checkpointRegistry([checkpointPackage(), checkpointPackage()])),
    /not uniquely activated/,
  );
});

test("rejects required-backlog and signature substitutions", () => {
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointPackage({ requiredBacklogIds: ["UNI-WRONG-001"] })]),
      ),
    /package activation drifted/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointPackage({ revision: { activatedSignatures: ["issueQuote(bytes32,uint64)"] } }),
        ]),
      ),
    /activated signatures drifted/,
  );
});

test("rejects missing or malformed dependency-closure evidence", () => {
  const missing = checkpointRevision();
  delete missing.dependencyClosureSha256;
  const missingPackage = checkpointPackage();
  missingPackage.revisions = [missing];
  assert.throws(
    () => phase9StubContracts(checkpointRegistry([missingPackage])),
    /contract revision fields drifted/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointPackage({ revision: { dependencyClosureSha256: "stale" } }),
        ]),
      ),
    /contract revision fields drifted/,
  );
});

test("pins the accepted Payoff package independently of later revisions", () => {
  const mutated = structuredClone(PAYOFF_PACKAGE);
  mutated.revisions[0].dependencyClosureSha256 = HASH;
  assert.throws(
    () => phase9StubContracts(checkpointRegistry([mutated])),
    /P9-PAYOFF-001: accepted package identity drifted/,
  );
});

test("Node checkpoint validation rejects ambiguous identities and malformed review commits", () => {
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointPackage({ review: { architectureReviewer: "/root" } }),
        ]),
      ),
    /review identities are ambiguous/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointPackage({ review: { reviewedCommit: "A".repeat(40) } }),
        ]),
      ),
    /review identity fields drifted/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointPackage({ review: { toolingReviewer: " " } })]),
      ),
    /review identities are ambiguous/,
  );
});

test("node compilation guard verifies current dependency and control closures", () => {
  const actual = repositorySolidityDependencyHash(
    "protocol/src/resolution/PayoffQuoteEngine.sol",
  );
  assert.equal(actual, "sha256:443295b9b42d2b37581bba0a25c265fb25bd04f44dc419c198295623f863909d");
  const valid = checkpointRegistry([
    checkpointPackage({
      revision: { dependencyClosureSha256: actual },
    }),
  ]);
  assert.doesNotThrow(() => validateCheckpointDependencyClosures(valid));
  const stale = checkpointRegistry([
    checkpointPackage({ revision: { dependencyClosureSha256: HASH } }),
  ]);
  assert.throws(
    () => validateCheckpointDependencyClosures(stale),
    /accepted package identity drifted/,
  );
  const staleControl = structuredClone(valid);
  staleControl.currentControlBundleSha256 = HASH;
  assert.throws(
    () => validateCheckpointDependencyClosures(staleControl),
    /control-bundle hash is stale/,
  );
});

test("provisional refinance activation is method-exact and keeps updateCustody frozen", () => {
  assert.equal(
    REFINANCE_ACTIVATED_SIGNATURES.get("CollateralCustodyV2").includes(
      "recordCustody((bytes32,bytes32,address,address,uint256,uint8,bytes32),bytes32)",
    ),
    true,
  );
  assert.equal(
    REFINANCE_ACTIVATED_SIGNATURES.get("CollateralCustodyV2").includes(
      "updateCustody(bytes32,uint256,uint8,bytes32)",
    ),
    false,
  );
});

test("Node and Python tooling share exact refinance auxiliary source ownership", () => {
  const python = readFileSync(
    resolve("tools/check_phase9_implementation_checkpoints.py"),
    "utf8",
  );
  const tuple = python.match(
    /REFINANCE_AUXILIARY_SOURCE_OWNERS = \(([\s\S]*?)\)\r?\nPACKAGE_AUXILIARY_SOURCE_OWNERS/,
  );
  assert.notEqual(tuple, null);
  const pythonOwners = [...tuple[1].matchAll(/\(\s*"([^"]+)",\s*"([^"]+)",?\s*\)/g)].map(
    (match) => [match[1], match[2]],
  );
  assert.deepEqual(REFINANCE_AUXILIARY_SOURCE_OWNERS, pythonOwners);
  assert.deepEqual(
    PACKAGE_AUXILIARY_SOURCE_OWNERS.get("P9-REFI-001"),
    REFINANCE_AUXILIARY_SOURCE_OWNERS,
  );
  assert.deepEqual(REFINANCE_AUXILIARY_SOURCE_OWNERS, [
    ["protocol/src/interfaces/phase9/ILienRegistry.sol", "LienRegistry"],
    [
      "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
      "RefinanceCoordinator",
    ],
  ]);
  assert.doesNotThrow(() => validatePackageAuxiliarySourceOwners("P9-REFI-001"));
  assert.throws(
    () =>
      validatePackageAuxiliarySourceOwners("P9-REFI-001", {
        entries: [
          [
            "protocol/src/interfaces/phase9/IRefinanceCoordinator.sol",
            "LienRegistry",
          ],
        ],
      }),
    /auxiliary source is not a dependency of LienRegistry/,
  );
});

test("RefinanceCoordinator additive ABI allowlist fixes its exact event and error", () => {
  const baseline = JSON.parse(
    readFileSync(resolve("protocol/abi/phase9/RefinanceCoordinator.abi.json"), "utf8"),
  );
  assert.deepEqual(REFINANCE_COORDINATOR_ABI_ADDITIONS, [
    REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR,
    REFINANCE_STATE_TRANSITIONED_EVENT,
  ]);
  const additive = additiveAbiPayload(baseline, REFINANCE_COORDINATOR_ABI_ADDITIONS);
  assert.equal(additive.length, baseline.length + 2);
  assert.deepEqual(
    additive.filter(
      (item) =>
        !["RefinanceStateTransitioned", "UnknownFundingCommitment"].includes(item.name),
    ),
    baseline,
  );
  const event = additive.find((item) => item.name === "RefinanceStateTransitioned");
  assert.deepEqual(event.inputs.map((input) => input.type), [
    "bytes32",
    "uint8",
    "uint8",
    "uint64",
    "bytes32",
    "bytes32",
  ]);
  assert.deepEqual(
    event.inputs.map((input) => input.indexed),
    [true, true, true, false, false, false],
  );
  assert.deepEqual(
    additive.find((item) => item.name === "UnknownFundingCommitment"),
    REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR,
  );
  assert.throws(
    () =>
      additiveAbiPayload(baseline, [
        {
          inputs: [],
          name: "unauthorizedSelector",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
      ]),
    /errors and events only/,
  );
});

test("LienRegistry additive ABI allowlist fixes its exact handoff error", () => {
  const baseline = JSON.parse(
    readFileSync(resolve("protocol/abi/phase9/LienRegistry.abi.json"), "utf8"),
  );
  assert.deepEqual(LIEN_REGISTRY_ABI_ADDITIONS, [
    REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR,
  ]);
  const additive = additiveAbiPayload(baseline, LIEN_REGISTRY_ABI_ADDITIONS);
  assert.equal(additive.length, baseline.length + 1);
  assert.deepEqual(
    additive.filter((item) => item.name !== "UnknownLienHandoff"),
    baseline,
  );
  assert.deepEqual(
    additive.find((item) => item.name === "UnknownLienHandoff"),
    REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR,
  );
  assert.equal(
    REFINANCE_COORDINATOR_ABI_ADDITIONS.includes(REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR),
    false,
  );
  assert.equal(
    LIEN_REGISTRY_ABI_ADDITIONS.includes(REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR),
    false,
  );
});

test("compiled-output ABI comparison rejects unauthorized errors and events", () => {
  assert.doesNotThrow(() => validateCheckpointAbiAdditions(baselineCompiledOutput(), REGISTRY));
  for (const unauthorized of [
    {
      inputs: [{ internalType: "bytes32", name: "unknownId", type: "bytes32" }],
      name: "UnknownUnauthorizedRecord",
      type: "error",
    },
    {
      anonymous: false,
      inputs: [{ indexed: true, internalType: "bytes32", name: "unknownId", type: "bytes32" }],
      name: "UnauthorizedStateTransitioned",
      type: "event",
    },
  ]) {
    const output = baselineCompiledOutput();
    output.contracts["compiled/RefinanceCoordinator.sol"].RefinanceCoordinator.abi.push(
      unauthorized,
    );
    assert.throws(
      () => validateCheckpointAbiAdditions(output, REGISTRY),
      /compiled ABI differs from the historical plus additive set/,
    );
  }
});

test("compiled-output ABI comparison rejects additions assigned to the wrong contract", () => {
  for (const [contract, misassigned] of [
    ["RefinanceCoordinator", REFINANCE_UNKNOWN_LIEN_HANDOFF_ERROR],
    ["LienRegistry", REFINANCE_UNKNOWN_FUNDING_COMMITMENT_ERROR],
    ["LienRegistry", REFINANCE_STATE_TRANSITIONED_EVENT],
  ]) {
    const output = baselineCompiledOutput();
    output.contracts[`compiled/${contract}.sol`][contract].abi.push(misassigned);
    assert.throws(
      () => validateCheckpointAbiAdditions(output, REGISTRY),
      new RegExp(`${contract}: compiled ABI differs from the historical plus additive set`),
    );
  }
});

test("Node and Python checkpoint tooling share the exact evidence path list", () => {
  const python = readFileSync(
    resolve("tools/check_phase9_implementation_checkpoints.py"),
    "utf8",
  );
  const tuple = python.match(
    /PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS = \(([\s\S]*?)\)\r?\nREFINANCE_IMPLEMENTATION_EVIDENCE_PATHS/,
  );
  assert.notEqual(tuple, null);
  const pythonPaths = [...tuple[1].matchAll(/^\s*"([^"]+)",\s*$/gm)].map(
    (match) => match[1],
  );
  assert.deepEqual(PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS, pythonPaths);
  assert.equal(
    [...PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS].sort(ordinalUtf8Compare).join("\n"),
    PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS.join("\n"),
  );
  assert.equal(
    new Set(PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS).size,
    PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS.length,
  );
  assert.ok(
    [
      ".gitattributes",
      ".github/workflows/foundation.yml",
      ".mise.toml",
      "package.json",
      "pnpm-lock.yaml",
      "protocol/foundry.toml",
      "protocol/src/ProtocolCompilation.sol",
      "pyproject.toml",
      "scripts/check-contract-sizes.py",
      "scripts/check-foundation.ps1",
      "scripts/prepare-foundry.ps1",
      "tsconfig.json",
      "uv.lock",
    ].every((path) => PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS.includes(path)),
  );

  const refinanceTuple = python.match(
    /REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS = \(([\s\S]*?)\)\r?\nIMPLEMENTATION_EVIDENCE_PATHS/,
  );
  assert.notEqual(refinanceTuple, null);
  const pythonRefinancePaths = [
    ...refinanceTuple[1].matchAll(/^\s*"([^"]+)",\s*$/gm),
  ].map((match) => match[1]);
  assert.deepEqual(REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS, pythonRefinancePaths);
  assert.equal(
    [...REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS].sort(ordinalUtf8Compare).join("\n"),
    REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS.join("\n"),
  );
  assert.equal(
    new Set(REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS).size,
    REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS.length,
  );
  assert.ok(
    [
      "adr/0022-phase-9-factory-account-position-bootstrap-semantics.md",
      "protocol/test/Phase9RefinanceBootstrapAcceptanceMap.sol",
      "protocol/test/Phase9RefinanceBootstrapHarness.sol",
      "protocol/test/Phase9RefinanceCustodyLienBootstrap.t.sol",
      "protocol/test/Phase9RefinanceFactoryBootstrap.t.sol",
      "protocol/test/Phase9RefinanceRequest.t.sol",
      "protocol/test/Phase9RefinanceRequestFuzz.t.sol",
      "protocol/test/Phase9RefinanceRequestGolden.t.sol",
      "protocol/test/Phase9RefinanceRequestInvariants.t.sol",
    ].every((path) => REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS.includes(path)),
  );
  for (const contract of REFINANCE_ACTIVATED_SIGNATURES.keys()) {
    assert.equal(
      IMPLEMENTATION_EVIDENCE_PATHS.get(contract),
      REFINANCE_IMPLEMENTATION_EVIDENCE_PATHS,
    );
  }
  assert.equal(
    IMPLEMENTATION_EVIDENCE_CLOSURE_LIMITATIONS.get("P9-REFI-001"),
    "D2-D4 exact implementation evidence paths are not frozen",
  );
});

test("node checkpoint validation rejects refinance while D2-D4 paths are unfrozen", () => {
  const refinancePackage = {
    checkpointId: "P9-REFI-001",
    requiredBacklogIds: ["UNI-ADR-016", "UNI-ADR-017", "UNI-REFI-001", "UNI-REFI-002"],
    review: {},
    revisions: [],
  };
  assert.throws(
    () => validateCheckpointDependencyClosures(
      checkpointRegistry([checkpointPackage(), refinancePackage]),
    ),
    /D2-D4 exact implementation evidence paths are not frozen/,
  );
});

test("Node and Python checkpoint tooling bind the exact control path list", () => {
  const python = readFileSync(
    resolve("tools/check_phase9_implementation_checkpoints.py"),
    "utf8",
  );
  const tuple = python.match(
    /CONTROL_BUNDLE_PATHS = \(([\s\S]*?)\)\r?\n\r?\n# Prepared Foundry dependencies/,
  );
  assert.notEqual(tuple, null);
  const pythonPaths = [...tuple[1].matchAll(/^\s*"([^"]+)",\s*$/gm)].map(
    (match) => match[1],
  );
  assert.deepEqual(CONTROL_BUNDLE_PATHS, pythonPaths);
  assert.deepEqual(CONTROL_BUNDLE_PATHS, [
    "buf.gen.yaml",
    "buf.yaml",
    "protocol/foundry.toml",
    "scripts/check-foundation.ps1",
    "scripts/generate.ps1",
    "tools/check_abi.py",
    "tools/check_phase9.py",
    "tools/check_phase9_implementation_checkpoints.py",
    "tools/check_phase9_schema.py",
    "tools/check_phase9_storage_layouts.py",
    "tools/compile_phase9_storage_layouts.mjs",
    "tools/tests/test_phase9_compatibility.py",
    "tools/tests/test_phase9_implementation_checkpoints.py",
    "tools/tests/test_phase9_schema.py",
    "tools/tests/test_phase9_warning_policy.mjs",
    "tools/tests/test_update_phase9_implementation_checkpoint.py",
    "tools/update_phase9_implementation_checkpoint.py",
  ]);
});

test("Git-clean evidence bytes are canonical LF across platforms", () => {
  const root = mkdtempSync(join(tmpdir(), "unified-phase9-git-clean-"));
  try {
    mkdirSync(join(root, "scripts"), { recursive: true });
    writeFileSync(join(root, ".gitattributes"), "* text=auto eol=lf\n*.ps1 text eol=lf\n");
    writeFileSync(join(root, "scripts/check.ps1"), "Write-Output 'ok'\n");
    runGit(root, "init", "--quiet");
    runGit(root, "config", "user.name", "Phase 9 Test");
    runGit(root, "config", "user.email", "phase9-test@unified.local");

    assert.doesNotThrow(() =>
      requireGitCleanWorktreeBytes([".gitattributes", "scripts/check.ps1"], { root }),
    );
    writeFileSync(join(root, "scripts/check.ps1"), "Write-Output 'ok'\r\n");
    assert.throws(
      () => requireGitCleanWorktreeBytes(["scripts/check.ps1"], { root }),
      /Git-clean canonical bytes/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("recursive Foundry remapping dependencies are hashed and unresolved imports fail closed", () => {
  const root = mkdtempSync(join(tmpdir(), "unified-phase9-node-"));
  try {
    const config = join(root, "protocol/foundry.toml");
    const source = join(root, "protocol/src/resolution/PayoffQuoteEngine.sol");
    const vendor = join(root, "protocol/lib/vendor/contracts");
    mkdirSync(dirname(source), { recursive: true });
    mkdirSync(vendor, { recursive: true });
    writeFileSync(
      config,
      '[profile.default]\nremappings = ["@vendor/=lib/vendor/contracts/"]\n',
    );
    writeFileSync(source, 'import "@vendor/One.sol";\ncontract PayoffQuoteEngine {}\n');
    writeFileSync(join(vendor, "One.sol"), 'import "./Two.sol";\nlibrary One {}\n');
    writeFileSync(join(vendor, "Two.sol"), "library Two {}\n");

    assert.deepEqual(
      repositorySolidityDependencyPaths(
        "protocol/src/resolution/PayoffQuoteEngine.sol",
        { root },
      ).map((path) => path.slice(root.length + 1).replaceAll("\\", "/")),
      [
        "protocol/lib/vendor/contracts/One.sol",
        "protocol/lib/vendor/contracts/Two.sol",
        "protocol/src/resolution/PayoffQuoteEngine.sol",
      ],
    );
    const before = repositorySolidityDependencyHash(
      "protocol/src/resolution/PayoffQuoteEngine.sol",
      { root },
    );
    writeFileSync(join(vendor, "Two.sol"), "library Two { uint256 constant X = 1; }\n");
    assert.notEqual(
      repositorySolidityDependencyHash("protocol/src/resolution/PayoffQuoteEngine.sol", {
        root,
      }),
      before,
    );

    writeFileSync(source, 'import "@vendor/Missing.sol";\ncontract PayoffQuoteEngine {}\n');
    assert.throws(
      () =>
        repositorySolidityDependencyHash("protocol/src/resolution/PayoffQuoteEngine.sol", {
          root,
        }),
      /unresolved non-relative import/,
    );
    writeFileSync(source, 'import "missing/Nope.sol";\ncontract PayoffQuoteEngine {}\n');
    assert.throws(
      () =>
        repositorySolidityDependencyHash("protocol/src/resolution/PayoffQuoteEngine.sol", {
          root,
        }),
      /unresolved non-relative import/,
    );
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test("Solidity import lexer preserves comment markers inside strings", () => {
  const sources = [
    'string constant X = "x//"; import "../risk/PayoffLogic.sol";',
    'string constant X = "x/* not a comment */"; import "../risk/PayoffLogic.sol";',
    String.raw`string constant X = "escaped \" //"; import "../risk/PayoffLogic.sol";`,
    String.raw`string constant X = "escaped \" /* */"; import "../risk/PayoffLogic.sol";`,
    String.raw`string constant X = "import \"../risk/Fake.sol\"; //"; import "../risk/PayoffLogic.sol";`,
  ];
  for (const source of sources) {
    assert.deepEqual(solidityImportsFromSource(source), ["../risk/PayoffLogic.sol"]);
  }
});

test("Solidity import lexer handles LF, CR, and CRLF line comments", () => {
  for (const lineEnd of ["\n", "\r", "\r\n"]) {
    assert.deepEqual(
      solidityImportsFromSource(`// hidden text${lineEnd}import "../risk/PayoffLogic.sol";`),
      ["../risk/PayoffLogic.sol"],
    );
  }
});

test("dependency paths use explicit ordinal UTF-8 order", () => {
  const paths = [
    "protocol/src/risk/aHelper.sol",
    "protocol/src/risk/_Helper.sol",
    "protocol/src/risk/ZHelper.sol",
    "protocol/src/risk/AHelper.sol",
  ];
  assert.deepEqual(paths.sort(ordinalUtf8Compare), [
    "protocol/src/risk/AHelper.sol",
    "protocol/src/risk/ZHelper.sol",
    "protocol/src/risk/_Helper.sol",
    "protocol/src/risk/aHelper.sol",
  ]);
});
