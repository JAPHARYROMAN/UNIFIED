import assert from "node:assert/strict";
import test from "node:test";

import {
  ordinalUtf8Compare,
  phase9StubContracts,
  repositorySolidityDependencyHash,
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
    backlogId: "UNI-PAYOFF-001",
    contract: "PayoffQuoteEngine",
    dependencyClosureSha256: HASH,
    reviewPath: "security/reviews/phase-9-payoff-implementation.md",
    reviewSha256: HASH,
    sourceSha256: HASH,
    sourceSetSha256: HASH,
    status: "PASS",
    storageStructuralSha256: HASH,
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

test("node compilation guard verifies the current dependency closure", () => {
  const actual = repositorySolidityDependencyHash(
    "protocol/src/resolution/PayoffQuoteEngine.sol",
  );
  const valid = checkpointRegistry([checkpointEntry({ dependencyClosureSha256: actual })]);
  assert.doesNotThrow(() => validateCheckpointDependencyClosures(valid));
  const stale = checkpointRegistry([checkpointEntry()]);
  assert.throws(
    () => validateCheckpointDependencyClosures(stale),
    /dependency closure hash is stale/,
  );
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
