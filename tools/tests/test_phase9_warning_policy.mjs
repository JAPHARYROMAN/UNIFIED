import assert from "node:assert/strict";
import test from "node:test";

import { validatePhase9MutabilityDiagnostics } from "../compile_phase9_storage_layouts.mjs";

const SOURCE = "protocol/src/resolution/Phase9LoanFactory.sol";

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
