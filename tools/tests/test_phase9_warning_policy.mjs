import assert from "node:assert/strict";
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
  implementationEvidenceBundleSha256,
  ordinalUtf8Compare,
  PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS,
  phase9StubContracts,
  phase9WarningStubContracts,
  repositorySolidityDependencyHash,
  repositorySolidityDependencyPaths,
  solidityImportsFromSource,
  validateCheckpointDependencyClosures,
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

function checkpointEntry(overrides = {}) {
  return {
    abiSha256: HASH,
    architectureReviewer: "Architecture Reviewer",
    backlogId: "UNI-PAYOFF-001",
    contract: "PayoffQuoteEngine",
    dependencyClosureSha256: HASH,
    implementationAuthor: "Implementation Author",
    implementationEvidenceBundleSha256: HASH,
    reviewPath: "security/reviews/phase-9-payoff-quote-engine.md",
    reviewSha256: HASH,
    reviewedCommit: "1".repeat(40),
    securityReviewer: "Security Reviewer",
    sourceSha256: HASH,
    sourceSetSha256: HASH,
    status: "PASS",
    storageStructuralSha256: HASH,
    toolingReviewer: "Tooling Reviewer",
    ...overrides,
  };
}

function checkpointRegistry(implementations = []) {
  return {
    baseline: BASELINE,
    currentSourceSetSha256: HASH,
    implementations,
    schemaVersion: 1,
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

function fixture(functions, locations) {
  return {
    errors: locations.map(({ end, file = SOURCE, start }) => ({
      errorCode: "2018",
      severity: "warning",
      sourceLocation: { end, file, start },
    })),
    sources: {
      [SOURCE]: {
        ast: {
          nodes: [
            {
              name: "Phase9LoanFactory",
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
    /not scoped to one canonical Phase 9 fail-closed mutator/,
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

test("derives the exact stub set from implementation checkpoints", () => {
  const stubs = phase9StubContracts(checkpointRegistry([checkpointEntry()]));
  assert.equal(stubs.includes("PayoffQuoteEngine"), false);
  assert.equal(stubs.includes("Phase9LoanAccount"), true);
  assert.equal(stubs.length, 12);
});

test("derives the same warning stub set before and after an activated checkpoint", () => {
  const beforeCheckpoint = phase9WarningStubContracts(checkpointRegistry());
  const afterCheckpoint = phase9WarningStubContracts(
    checkpointRegistry([checkpointEntry()]),
  );

  assert.equal(phase9StubContracts(checkpointRegistry()).includes("PayoffQuoteEngine"), true);
  assert.equal(beforeCheckpoint.includes("PayoffQuoteEngine"), false);
  assert.equal(beforeCheckpoint.includes("Phase9LoanAccount"), true);
  assert.equal(beforeCheckpoint.length, 12);
  assert.deepEqual(beforeCheckpoint, afterCheckpoint);
});

test("rejects unknown or duplicate checkpoint contracts", () => {
  assert.throws(
    () =>
      phase9StubContracts({
        ...checkpointRegistry([checkpointEntry({ contract: "Unexpected" })]),
      }),
    /contract set is invalid/,
  );
  assert.throws(
    () =>
      phase9StubContracts(checkpointRegistry([checkpointEntry(), checkpointEntry()])),
    /contract set is invalid/,
  );
});

test("rejects unopened contracts and backlog substitutions", () => {
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointEntry({ backlogId: "UNI-REFI-001", contract: "RefinanceCoordinator" }),
        ]),
      ),
    /contract set is invalid/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointEntry({ backlogId: "UNI-WRONG-001" })]),
      ),
    /contract set is invalid/,
  );
});

test("rejects missing or malformed dependency-closure evidence", () => {
  const missing = checkpointEntry();
  delete missing.dependencyClosureSha256;
  assert.throws(
    () => phase9StubContracts(checkpointRegistry([missing])),
    /contract set is invalid/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointEntry({ dependencyClosureSha256: "stale" })]),
      ),
    /contract set is invalid/,
  );
});

test("Node checkpoint validation rejects ambiguous identities and malformed review commits", () => {
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([
          checkpointEntry({ architectureReviewer: "Implementation Author" }),
        ]),
      ),
    /contract set is invalid/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointEntry({ reviewedCommit: "A".repeat(40) })]),
      ),
    /contract set is invalid/,
  );
  assert.throws(
    () =>
      phase9StubContracts(
        checkpointRegistry([checkpointEntry({ toolingReviewer: " " })]),
      ),
    /contract set is invalid/,
  );
});

test("node compilation guard verifies the current dependency closure", () => {
  const actual = repositorySolidityDependencyHash(
    "protocol/src/resolution/PayoffQuoteEngine.sol",
  );
  assert.equal(actual, "sha256:c39437d021534fe2a34109252e2a595d04c9104790abc298f8a988c19718ce53");
  const bundle = implementationEvidenceBundleSha256("PayoffQuoteEngine");
  const valid = checkpointRegistry([
    checkpointEntry({
      dependencyClosureSha256: actual,
      implementationEvidenceBundleSha256: bundle,
    }),
  ]);
  assert.doesNotThrow(() => validateCheckpointDependencyClosures(valid));
  const stale = checkpointRegistry([
    checkpointEntry({ implementationEvidenceBundleSha256: bundle }),
  ]);
  assert.throws(
    () => validateCheckpointDependencyClosures(stale),
    /dependency closure hash is stale/,
  );
  const staleBundle = checkpointRegistry([
    checkpointEntry({ dependencyClosureSha256: actual }),
  ]);
  assert.throws(
    () => validateCheckpointDependencyClosures(staleBundle),
    /implementation evidence bundle hash is stale/,
  );
});

test("Node and Python checkpoint tooling share the exact evidence path list", () => {
  const python = readFileSync(
    resolve("tools/check_phase9_implementation_checkpoints.py"),
    "utf8",
  );
  const tuple = python.match(
    /PAYOFF_IMPLEMENTATION_EVIDENCE_PATHS = \(([\s\S]*?)\)\r?\nIMPLEMENTATION_EVIDENCE_PATHS/,
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
