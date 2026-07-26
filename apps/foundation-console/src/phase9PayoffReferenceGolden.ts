import { create } from "@bufbuild/protobuf";
import { TimestampSchema } from "@bufbuild/protobuf/wkt";

import {
  type PayoffComponentReference,
  type PayoffPolicyReference,
  type PayoffQuoteIdentityReference,
  type SettlementRouteReference,
  canonicalPayoffComponents,
  componentBeneficiaryHash,
  encodeComponentBeneficiaries,
  payoffPolicyHash,
  payoffQuoteId,
  referenceBytesToHex,
  settlementRouteHash,
} from "../../../packages/phase9/typescript/payoffReference.js";
import {
  canonicalGoldenPayoffQuoteContext,
  payoffQuoteDigest,
} from "../../../packages/phase9/typescript/payoffQuoteCodec.js";
import {
  CanonicalDebtSnapshotSchema,
  PayoffComponentKind,
  PayoffComponentSchema,
  PayoffQuoteSchema,
} from "../../../packages/generated/typescript/unified/v1/refinance_pb.js";
import {
  AssetIdSchema,
  IdentifierSchema,
  LoanIdSchema,
  MoneySchema,
  PartyIdSchema,
  PolicyReferenceSchema,
} from "../../../packages/generated/typescript/unified/v1/types_pb.js";

const EXPECTED_POLICY_HASH =
  "5777a058cd8923e844c1c2e74ee82a0a8c4073084eddf4a44e860f68a3f5e718";
const EXPECTED_COMPONENT_HASH =
  "b43d774823fee6ffb1b0aaeaa005a119300aa1e65bcea9206f434fa4c3f01189";
const EXPECTED_ROUTE_HASH =
  "adc8f2b001860d4d37fe42ce1340628670fe587ea3401947f75d8b2c6aac3aba";
const EXPECTED_QUOTE_ID =
  "bfb9a4e4e14118a568ad2742e9607a45dc9ed0b3bf80b1d01364003f91d16988";
const EXISTING_CODEC_GOLDEN =
  "632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058";
const ASSET_VALUE = "asset:phase9:p9unit";

function repeated(byte: number, length: number): Uint8Array {
  return new Uint8Array(length).fill(byte);
}

function policy(): PayoffPolicyReference {
  return {
    chainId: 31337n,
    payoffQuoteEngine: repeated(0x11, 20),
    quotePolicyRegistry: repeated(0x12, 20),
    loanId: repeated(0x33, 32),
    loanAccount: repeated(0x44, 20),
    boundPolicySetHash: repeated(0x88, 32),
    feePenaltyBeneficiary: repeated(0x77, 20),
    settlementAssetId: repeated(0xaa, 32),
    settlementToken: repeated(0x22, 20),
    maximumValidity: 300n,
  };
}

function components(): readonly PayoffComponentReference[] {
  return canonicalPayoffComponents({
    principal: 90_000_000n,
    accruedInterest: 5_000_000n,
    fees: 3_000_000n,
    penalties: 3_000_000n,
    credits: 1_000_000n,
    lenderBeneficiary: repeated(0x99, 20),
    feePenaltyBeneficiary: repeated(0x77, 20),
  });
}

function route(policyHash: Uint8Array): SettlementRouteReference {
  return {
    chainId: 31337n,
    payoffQuoteEngine: repeated(0x11, 20),
    refinanceCoordinator: repeated(0x13, 20),
    loanId: repeated(0x33, 32),
    loanAccount: repeated(0x44, 20),
    settlementAssetId: repeated(0xaa, 32),
    settlementToken: repeated(0x22, 20),
    lenderBeneficiary: repeated(0x99, 20),
    feePenaltyBeneficiary: repeated(0x77, 20),
    policyHash,
  };
}

function identity(
  policyHash: Uint8Array,
  componentHash: Uint8Array,
  routeHash: Uint8Array,
): PayoffQuoteIdentityReference {
  return {
    payoffQuoteEngine: repeated(0x11, 20),
    chainId: 31337n,
    loanId: repeated(0x33, 32),
    loanAccount: repeated(0x44, 20),
    policyHash,
    debtStateVersion: 7n,
    principal: 90_000_000n,
    accruedInterest: 5_000_000n,
    fees: 3_000_000n,
    penalties: 3_000_000n,
    credits: 1_000_000n,
    componentBeneficiaryHash: componentHash,
    netPayoff: 100_000_000n,
    settlementAssetId: repeated(0xaa, 32),
    settlementToken: repeated(0x22, 20),
    settlementRouteHash: routeHash,
    issuedAt: 1_800_000_000n,
    validUntil: 1_800_000_300n,
    quoteNonce: 1n,
  };
}

function money(units: bigint) {
  return create(MoneySchema, {
    assetId: create(AssetIdSchema, { value: ASSET_VALUE }),
    units: units.toString(),
  });
}

function existingCodecQuote() {
  return create(PayoffQuoteSchema, {
    loanId: create(LoanIdSchema, { value: `0x${"33".repeat(32)}` }),
    debt: create(CanonicalDebtSnapshotSchema, {
      loanId: create(LoanIdSchema, { value: `0x${"33".repeat(32)}` }),
      loanAccountId: create(IdentifierSchema, { value: `0x${"44".repeat(20)}` }),
      principal: money(90_000_000n),
      accruedInterest: money(5_000_000n),
      capitalizedInterest: money(0n),
      fees: money(3_000_000n),
      penalties: money(3_000_000n),
      recoverableCosts: money(0n),
      credits: money(1_000_000n),
      debtStateVersion: 7n,
    }),
    components: [
      create(PayoffComponentSchema, {
        kind: PayoffComponentKind.PRINCIPAL,
        amount: money(90_000_000n),
        beneficiaryId: create(PartyIdSchema, { value: "party:old-lender" }),
        obligationCode: "PRINCIPAL",
      }),
    ],
    grossPayoff: money(101_000_000n),
    credits: money(1_000_000n),
    netPayoff: money(100_000_000n),
    componentBeneficiaryHash: repeated(0x66, 32),
    settlementRouteHash: repeated(0x77, 32),
    issuedAt: create(TimestampSchema, { seconds: 1_800_000_000n }),
    validUntil: create(TimestampSchema, { seconds: 1_800_000_300n }),
    quoteNonce: 1n,
    quotePolicy: create(PolicyReferenceSchema, { contentHash: repeated(0x55, 32) }),
  });
}

function assertChanged(
  label: string,
  baseline: Uint8Array,
  mutations: readonly Uint8Array[],
): void {
  const expected = referenceBytesToHex(baseline);
  if (mutations.some((mutation) => referenceBytesToHex(mutation) === expected)) {
    throw new Error(`${label} mutation did not change its commitment`);
  }
}

/**
 * Verify P9Q-POL-001/002, P9Q-COMP-001..004, P9Q-ROUTE-001/002, and
 * P9Q-ID-001..004 without importing any encoder implementation from the Solidity engine.
 */
export function verifyPhase9PayoffReferenceGoldenVectors(): void {
  const basePolicy = policy();
  const policyHash = payoffPolicyHash(basePolicy);
  const baseComponents = components();
  const componentHash = componentBeneficiaryHash(baseComponents);
  const baseRoute = route(policyHash);
  const routeHash = settlementRouteHash(baseRoute);
  const baseIdentity = identity(policyHash, componentHash, routeHash);
  const quoteId = payoffQuoteId(baseIdentity);

  const actualGoldens = [policyHash, componentHash, routeHash, quoteId].map(referenceBytesToHex);
  const expectedGoldens = [
    EXPECTED_POLICY_HASH,
    EXPECTED_COMPONENT_HASH,
    EXPECTED_ROUTE_HASH,
    EXPECTED_QUOTE_ID,
  ];
  if (actualGoldens.some((actual, index) => actual !== expectedGoldens[index])) {
    throw new Error("TypeScript Phase 9 payoff reference golden vector changed");
  }

  const oldIdentity = identity(repeated(0x55, 32), repeated(0x66, 32), repeated(0x77, 32));
  const referenceOldId = payoffQuoteId(oldIdentity);
  const codecOldId = payoffQuoteDigest(
    existingCodecQuote(),
    canonicalGoldenPayoffQuoteContext(),
  );
  if (
    referenceBytesToHex(referenceOldId) !== EXISTING_CODEC_GOLDEN ||
    referenceBytesToHex(codecOldId) !== EXISTING_CODEC_GOLDEN
  ) {
    throw new Error("independent quote-ID encoder diverged from the frozen quote codec");
  }

  assertChanged("policy", policyHash, [
    payoffPolicyHash({ ...basePolicy, chainId: 31338n }),
    payoffPolicyHash({ ...basePolicy, payoffQuoteEngine: repeated(0x10, 20) }),
    payoffPolicyHash({ ...basePolicy, quotePolicyRegistry: repeated(0x14, 20) }),
    payoffPolicyHash({ ...basePolicy, loanId: repeated(0x34, 32) }),
    payoffPolicyHash({ ...basePolicy, loanAccount: repeated(0x45, 20) }),
    payoffPolicyHash({ ...basePolicy, boundPolicySetHash: repeated(0x89, 32) }),
    payoffPolicyHash({ ...basePolicy, feePenaltyBeneficiary: repeated(0x78, 20) }),
    payoffPolicyHash({ ...basePolicy, settlementAssetId: repeated(0xab, 32) }),
    payoffPolicyHash({ ...basePolicy, settlementToken: repeated(0x23, 20) }),
    payoffPolicyHash({ ...basePolicy, maximumValidity: 301n }),
  ]);

  const componentMutations: readonly (readonly PayoffComponentReference[])[] = [
    [{ ...baseComponents[0]!, kind: 4n }, ...baseComponents.slice(1)],
    [{ ...baseComponents[0]!, amount: 0n }, ...baseComponents.slice(1)],
    [
      { ...baseComponents[0]!, beneficiary: repeated(0x98, 20) },
      ...baseComponents.slice(1),
    ],
    [
      { ...baseComponents[0]!, obligationCode: "PRINCIPAL_CHANGED" },
      ...baseComponents.slice(1),
    ],
    [baseComponents[1]!, baseComponents[0]!, ...baseComponents.slice(2)],
  ];
  assertChanged(
    "component",
    componentHash,
    componentMutations.map((mutation) => componentBeneficiaryHash(mutation)),
  );
  let omissionRejected = false;
  try {
    encodeComponentBeneficiaries(baseComponents.slice(0, 4));
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes("exactly five")) {
      throw error;
    }
    omissionRejected = true;
  }
  if (!omissionRejected) {
    throw new Error("four-entry payoff vector was accepted");
  }
  const zeroComponents = canonicalPayoffComponents({
    principal: 90_000_000n,
    accruedInterest: 0n,
    fees: 0n,
    penalties: 0n,
    credits: 0n,
    lenderBeneficiary: repeated(0x99, 20),
    feePenaltyBeneficiary: repeated(0x77, 20),
  });
  if (
    zeroComponents.length !== 5 ||
    zeroComponents.map((component) => component.amount).join(",") !== "90000000,0,0,0,0"
  ) {
    throw new Error("zero-valued fixed payoff components were omitted");
  }

  assertChanged("route", routeHash, [
    settlementRouteHash({ ...baseRoute, chainId: 31338n }),
    settlementRouteHash({ ...baseRoute, payoffQuoteEngine: repeated(0x10, 20) }),
    settlementRouteHash({ ...baseRoute, refinanceCoordinator: repeated(0x14, 20) }),
    settlementRouteHash({ ...baseRoute, loanId: repeated(0x34, 32) }),
    settlementRouteHash({ ...baseRoute, loanAccount: repeated(0x45, 20) }),
    settlementRouteHash({ ...baseRoute, settlementAssetId: repeated(0xab, 32) }),
    settlementRouteHash({ ...baseRoute, settlementToken: repeated(0x23, 20) }),
    settlementRouteHash({ ...baseRoute, lenderBeneficiary: repeated(0x98, 20) }),
    settlementRouteHash({ ...baseRoute, feePenaltyBeneficiary: repeated(0x78, 20) }),
    settlementRouteHash({ ...baseRoute, policyHash: repeated(0x57, 32) }),
  ]);

  assertChanged("quote ID", quoteId, [
    payoffQuoteId({ ...baseIdentity, payoffQuoteEngine: repeated(0x10, 20) }),
    payoffQuoteId({ ...baseIdentity, chainId: 31338n }),
    payoffQuoteId({ ...baseIdentity, loanId: repeated(0x34, 32) }),
    payoffQuoteId({ ...baseIdentity, loanAccount: repeated(0x45, 20) }),
    payoffQuoteId({ ...baseIdentity, policyHash: repeated(0x57, 32) }),
    payoffQuoteId({ ...baseIdentity, debtStateVersion: 8n }),
    payoffQuoteId({ ...baseIdentity, principal: 90_000_001n }),
    payoffQuoteId({ ...baseIdentity, accruedInterest: 5_000_001n }),
    payoffQuoteId({ ...baseIdentity, fees: 3_000_001n }),
    payoffQuoteId({ ...baseIdentity, penalties: 3_000_001n }),
    payoffQuoteId({ ...baseIdentity, credits: 1_000_001n }),
    payoffQuoteId({ ...baseIdentity, componentBeneficiaryHash: repeated(0xb5, 32) }),
    payoffQuoteId({ ...baseIdentity, netPayoff: 100_000_001n }),
    payoffQuoteId({ ...baseIdentity, settlementAssetId: repeated(0xab, 32) }),
    payoffQuoteId({ ...baseIdentity, settlementToken: repeated(0x23, 20) }),
    payoffQuoteId({ ...baseIdentity, settlementRouteHash: repeated(0xae, 32) }),
    payoffQuoteId({ ...baseIdentity, issuedAt: 1_800_000_001n }),
    payoffQuoteId({ ...baseIdentity, validUntil: 1_800_000_301n }),
    payoffQuoteId({ ...baseIdentity, quoteNonce: 2n }),
  ]);

  const exactFieldOrder = [
    "payoffQuoteEngine",
    "chainId",
    "loanId",
    "loanAccount",
    "policyHash",
    "debtStateVersion",
    "principal",
    "accruedInterest",
    "fees",
    "penalties",
    "credits",
    "componentBeneficiaryHash",
    "netPayoff",
    "settlementAssetId",
    "settlementToken",
    "settlementRouteHash",
    "issuedAt",
    "validUntil",
    "quoteNonce",
  ];
  if (Object.keys(baseIdentity).join(",") !== exactFieldOrder.join(",")) {
    throw new Error("quote identity field set/order drifted or included gross/quote ID");
  }
}
