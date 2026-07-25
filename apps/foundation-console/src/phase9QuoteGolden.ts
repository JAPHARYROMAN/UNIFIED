import { create } from "@bufbuild/protobuf";
import { TimestampSchema } from "@bufbuild/protobuf/wkt";

import * as phase9QuoteCodec from "../../../packages/phase9/typescript/payoffQuoteCodec.js";
import type { TrustedPayoffQuoteContext } from "../../../packages/phase9/typescript/payoffQuoteCodec.js";
import {
  canonicalGoldenPayoffQuoteContext,
  payoffQuoteDigest,
  toHex,
  validatePayoffQuoteDigest,
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

const EXPECTED_DIGEST =
  "632cc3b4bcf2cfcddcf9699eb7f9eef6f946fa7f4ed392f4767925354f8a2058";
const ASSET_VALUE = "asset:phase9:p9unit";

function repeated(byte: number, length: number): Uint8Array {
  return new Uint8Array(length).fill(byte);
}

function money(units: bigint) {
  return create(MoneySchema, {
    assetId: create(AssetIdSchema, { value: ASSET_VALUE }),
    units: units.toString(),
  });
}

function quote() {
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

export function verifyPhase9QuoteGoldenVector(): void {
  const trusted = canonicalGoldenPayoffQuoteContext();
  const candidate = quote();
  const digest = payoffQuoteDigest(candidate, trusted);
  if (toHex(digest) !== EXPECTED_DIGEST) {
    throw new Error("TypeScript payoff-quote digest golden vector changed");
  }
  candidate.quoteId = create(IdentifierSchema, { value: `0x${EXPECTED_DIGEST}` });
  candidate.quoteDigest = digest;
  validatePayoffQuoteDigest(candidate, trusted);

  const substitutedAsset = quote();
  if (substitutedAsset.netPayoff?.assetId !== undefined) {
    substitutedAsset.netPayoff.assetId.value = "asset:caller:substitute";
  }
  try {
    payoffQuoteDigest(substitutedAsset, trusted);
    throw new Error("wire asset substitution was accepted");
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes("untrusted settlement asset")) {
      throw error;
    }
  }

  if (
    Object.getPrototypeOf(trusted) !== null ||
    !Object.isFrozen(trusted) ||
    Reflect.ownKeys(trusted).length !== 0
  ) {
    throw new Error("trusted context is not a frozen null-prototype opaque singleton");
  }

  let assignmentRejected = false;
  try {
    const mutableView = trusted as unknown as Record<string, unknown>;
    mutableView.payoffQuoteEngine = repeated(0x12, 20);
  } catch (error) {
    if (!(error instanceof TypeError)) {
      throw error;
    }
    assignmentRejected = true;
  }
  if (!assignmentRejected) {
    throw new Error("assignment to the opaque trusted context was accepted");
  }

  let prototypeTamperingRejected = false;
  try {
    Object.setPrototypeOf(trusted, {
      payoffQuoteEngine: repeated(0x12, 20),
      chainId: 31338n,
      settlementAssetValue: "asset:caller:substitute",
      settlementAssetId: repeated(0xbb, 32),
      settlementToken: repeated(0x23, 20),
    });
  } catch (error) {
    if (!(error instanceof TypeError)) {
      throw error;
    }
    prototypeTamperingRejected = true;
  }
  if (!prototypeTamperingRejected) {
    throw new Error("prototype tampering on the opaque context was accepted");
  }
  if (toHex(payoffQuoteDigest(quote(), trusted)) !== EXPECTED_DIGEST) {
    throw new Error("context tampering changed closure-held authority");
  }

  let alternateSourceRejected = false;
  try {
    const callerContext = Object.assign(Object.create(null), {
      payoffQuoteEngine: repeated(0x12, 20),
      chainId: 31338n,
      settlementAssetValue: "asset:caller:substitute",
      settlementAssetId: repeated(0xbb, 32),
      settlementToken: repeated(0x23, 20),
    }) as TrustedPayoffQuoteContext;
    payoffQuoteDigest(quote(), callerContext);
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes("canonical opaque singleton")) {
      throw error;
    }
    alternateSourceRejected = true;
  }
  if (!alternateSourceRejected) {
    throw new Error("caller engine/chain/asset/token context was accepted");
  }
  if (
    "TrustedPayoffQuoteContext" in phase9QuoteCodec ||
    "fromAuthenticatedRegistries" in phase9QuoteCodec
  ) {
    throw new Error("trusted-context constructor or arbitrary factory is publicly exported");
  }

  const forged = Object.create(Object.getPrototypeOf(trusted)) as TrustedPayoffQuoteContext;
  try {
    payoffQuoteDigest(quote(), forged);
    throw new Error("prototype-forged trusted context was accepted");
  } catch (error) {
    if (!(error instanceof Error) || !error.message.includes("canonical opaque singleton")) {
      throw error;
    }
  }
}
