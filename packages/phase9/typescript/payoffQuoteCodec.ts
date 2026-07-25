import type { Timestamp } from "@bufbuild/protobuf/wkt";
import { keccak_256 } from "@noble/hashes/sha3.js";

import type { PayoffQuote } from "../../generated/typescript/unified/v1/refinance_pb.js";
import type { Money } from "../../generated/typescript/unified/v1/types_pb.js";

const WORD_BYTES = 32;
const UINT64_LIMIT = 1n << 64n;
const UINT256_LIMIT = 1n << 256n;
const PAYOFF_QUOTE_DOMAIN = "UNIFIED_PAYOFF_QUOTE_V1";
const UNSIGNED_INTEGER = /^(0|[1-9][0-9]*)$/;
declare const TRUSTED_CONTEXT_TYPE: unique symbol;
export type TrustedPayoffQuoteContext = {
  readonly [TRUSTED_CONTEXT_TYPE]: "UNIFIED_PAYOFF_QUOTE_CONTEXT";
};

type TrustedAuthority = readonly [
  payoffQuoteEngineHex: string,
  chainId: bigint,
  settlementAssetValue: string,
  settlementAssetIdHex: string,
  settlementTokenHex: string,
];

interface PayoffQuoteDigestInput {
  readonly payoffQuoteEngine: Uint8Array;
  readonly chainId: bigint;
  readonly loanId: Uint8Array;
  readonly loanAccount: Uint8Array;
  readonly policyHash: Uint8Array;
  readonly debtStateVersion: bigint;
  readonly principal: bigint;
  readonly accruedInterest: bigint;
  readonly fees: bigint;
  readonly penalties: bigint;
  readonly credits: bigint;
  readonly componentBeneficiaryHash: Uint8Array;
  readonly netPayoff: bigint;
  readonly settlementAssetId: Uint8Array;
  readonly settlementToken: Uint8Array;
  readonly settlementRouteHash: Uint8Array;
  readonly issuedAt: bigint;
  readonly validUntil: bigint;
  readonly quoteNonce: bigint;
}

function concat(parts: readonly Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function exactBytes(value: Uint8Array, length: number, field: string): Uint8Array {
  if (value.length !== length) {
    throw new Error(`${field} must contain ${length} bytes`);
  }
  return value;
}

function exactUint(value: bigint, limit: bigint, field: string): bigint {
  if (value < 0n || value >= limit) {
    throw new Error(`${field} is outside its unsigned integer range`);
  }
  return value;
}

function uintWord(value: bigint, field: string): Uint8Array {
  let remaining = exactUint(value, UINT256_LIMIT, field);
  const result = new Uint8Array(WORD_BYTES);
  for (let index = WORD_BYTES - 1; index >= 0; index -= 1) {
    result[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return result;
}

function addressWord(value: Uint8Array, field: string): Uint8Array {
  return concat([new Uint8Array(12), exactBytes(value, 20, field)]);
}

function dynamicStringTail(value: string): Uint8Array {
  const encoded = new TextEncoder().encode(value);
  return concat([
    uintWord(BigInt(encoded.length), "string length"),
    encoded,
    new Uint8Array((-encoded.length) & 31),
  ]);
}

function required<T>(value: T | undefined, field: string): T {
  if (value === undefined) {
    throw new Error(`${field} is required`);
  }
  return value;
}

function decodeHex(value: string, length: number, field: string): Uint8Array {
  if (!new RegExp(`^0x[0-9a-fA-F]{${length * 2}}$`).test(value)) {
    throw new Error(`${field} must be canonical 0x-prefixed ${length}-byte hex`);
  }
  return Uint8Array.from(value.slice(2).match(/../g) ?? [], (byte) => Number.parseInt(byte, 16));
}

function moneyUnits(
  value: Money | undefined,
  settlementAssetValue: string,
  field: string,
): bigint {
  const money = required(value, field);
  const asset = required(money.assetId, `${field}.asset_id`);
  if (asset.value !== settlementAssetValue) {
    throw new Error(`${field} uses an untrusted settlement asset`);
  }
  if (!UNSIGNED_INTEGER.test(money.units)) {
    throw new Error(`${field}.units must be a canonical unsigned integer`);
  }
  return exactUint(BigInt(money.units), UINT256_LIMIT, field);
}

function timestampSeconds(value: Timestamp | undefined, field: string): bigint {
  const timestamp = required(value, field);
  if (timestamp.nanos !== 0) {
    throw new Error(`${field} must have zero nanoseconds`);
  }
  return exactUint(timestamp.seconds, UINT64_LIMIT, field);
}

function resolvePayoffQuoteDigestInput(
  quote: PayoffQuote,
  authority: TrustedAuthority,
): PayoffQuoteDigestInput {
  const [engineHex, chainId, settlementAssetValue, assetIdHex, tokenHex] = authority;
  const loanId = required(quote.loanId, "loan_id");
  const debt = required(quote.debt, "debt");
  if (loanId.value !== required(debt.loanId, "debt.loan_id").value) {
    throw new Error("quote and debt snapshot loan IDs differ");
  }

  const principal = moneyUnits(debt.principal, settlementAssetValue, "principal");
  const accruedInterest = moneyUnits(
    debt.accruedInterest,
    settlementAssetValue,
    "accrued_interest",
  );
  const capitalizedInterest = moneyUnits(
    debt.capitalizedInterest,
    settlementAssetValue,
    "capitalized_interest",
  );
  const fees = moneyUnits(debt.fees, settlementAssetValue, "fees");
  const penalties = moneyUnits(debt.penalties, settlementAssetValue, "penalties");
  const recoverableCosts = moneyUnits(
    debt.recoverableCosts,
    settlementAssetValue,
    "recoverable_costs",
  );
  const credits = moneyUnits(debt.credits, settlementAssetValue, "debt.credits");
  if (capitalizedInterest !== 0n || recoverableCosts !== 0n) {
    throw new Error("Phase 9 quote V1 requires zero capitalized interest and recoverable costs");
  }
  const grossPayoff = moneyUnits(quote.grossPayoff, settlementAssetValue, "gross_payoff");
  const quoteCredits = moneyUnits(quote.credits, settlementAssetValue, "quote.credits");
  const netPayoff = moneyUnits(quote.netPayoff, settlementAssetValue, "net_payoff");
  if (grossPayoff !== principal + accruedInterest + fees + penalties || quoteCredits !== credits) {
    throw new Error("quote gross payoff or credits do not match canonical debt");
  }
  if (credits > grossPayoff || netPayoff !== grossPayoff - credits) {
    throw new Error("quote net payoff equation is invalid");
  }
  quote.components.forEach((component, index) => {
    moneyUnits(component.amount, settlementAssetValue, `components[${index}].amount`);
  });

  const issuedAt = timestampSeconds(quote.issuedAt, "issued_at");
  const validUntil = timestampSeconds(quote.validUntil, "valid_until");
  if (validUntil <= issuedAt) {
    throw new Error("quote validity interval is empty");
  }
  return {
    payoffQuoteEngine: decodeHex(`0x${engineHex}`, 20, "payoff_quote_engine"),
    chainId,
    loanId: decodeHex(loanId.value, 32, "loan_id"),
    loanAccount: decodeHex(required(debt.loanAccountId, "loan_account_id").value, 20, "loan_account_id"),
    policyHash: exactBytes(required(quote.quotePolicy, "quote_policy").contentHash, 32, "quote policy hash"),
    debtStateVersion: exactUint(debt.debtStateVersion, UINT64_LIMIT, "debt_state_version"),
    principal,
    accruedInterest,
    fees,
    penalties,
    credits,
    componentBeneficiaryHash: exactBytes(quote.componentBeneficiaryHash, 32, "component_beneficiary_hash"),
    netPayoff,
    settlementAssetId: decodeHex(`0x${assetIdHex}`, 32, "settlement_asset_id"),
    settlementToken: decodeHex(`0x${tokenHex}`, 20, "settlement_token"),
    settlementRouteHash: exactBytes(quote.settlementRouteHash, 32, "settlement_route_hash"),
    issuedAt,
    validUntil,
    quoteNonce: exactUint(quote.quoteNonce, UINT64_LIMIT, "quote_nonce"),
  };
}

function encodePayoffQuotePreimage(value: PayoffQuoteDigestInput): Uint8Array {
  const staticWords = [
    addressWord(value.payoffQuoteEngine, "payoff_quote_engine"),
    uintWord(value.chainId, "chain_id"),
    exactBytes(value.loanId, 32, "loan_id"),
    addressWord(value.loanAccount, "loan_account"),
    exactBytes(value.policyHash, 32, "policy_hash"),
    uintWord(value.debtStateVersion, "debt_state_version"),
    uintWord(value.principal, "principal"),
    uintWord(value.accruedInterest, "accrued_interest"),
    uintWord(value.fees, "fees"),
    uintWord(value.penalties, "penalties"),
    uintWord(value.credits, "credits"),
    exactBytes(value.componentBeneficiaryHash, 32, "component_beneficiary_hash"),
    uintWord(value.netPayoff, "net_payoff"),
    exactBytes(value.settlementAssetId, 32, "settlement_asset_id"),
    addressWord(value.settlementToken, "settlement_token"),
    exactBytes(value.settlementRouteHash, 32, "settlement_route_hash"),
    uintWord(value.issuedAt, "issued_at"),
    uintWord(value.validUntil, "valid_until"),
    uintWord(value.quoteNonce, "quote_nonce"),
  ];
  return concat([
    uintWord(BigInt((staticWords.length + 1) * WORD_BYTES), "domain offset"),
    ...staticWords.map((word, index) => exactBytes(word, WORD_BYTES, `word ${index}`)),
    dynamicStringTail(PAYOFF_QUOTE_DOMAIN),
  ]);
}

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length && left.every((byte, index) => byte === right[index]);
}

function buildTrustedPayoffQuoteCodec() {
  const singleton = Object.freeze(Object.create(null)) as TrustedPayoffQuoteContext;
  const authority: TrustedAuthority = Object.freeze([
    "11".repeat(20),
    31337n,
    "asset:phase9:p9unit",
    "aa".repeat(32),
    "22".repeat(20),
  ] as const);

  function canonicalContext(): TrustedPayoffQuoteContext {
    return singleton;
  }

  function resolveAuthority(context: TrustedPayoffQuoteContext): TrustedAuthority {
    if (context !== singleton) {
      throw new Error("payoff quote context is not the canonical opaque singleton");
    }
    return authority;
  }

  function digest(
    quote: PayoffQuote,
    context: TrustedPayoffQuoteContext,
  ): Uint8Array {
    const resolved = resolvePayoffQuoteDigestInput(quote, resolveAuthority(context));
    return keccak_256(encodePayoffQuotePreimage(resolved));
  }

  function validate(
    quote: PayoffQuote,
    context: TrustedPayoffQuoteContext,
  ): Uint8Array {
    const quoteDigest = digest(quote, context);
    if (!bytesEqual(quote.quoteDigest, quoteDigest)) {
      throw new Error("quote_digest does not match the trusted-context preimage");
    }
    const quoteId = decodeHex(required(quote.quoteId, "quote_id").value, 32, "quote_id");
    if (!bytesEqual(quoteId, quoteDigest)) {
      throw new Error("quote_id does not match the trusted-context preimage");
    }
    return quoteDigest;
  }

  return Object.freeze({ canonicalContext, digest, validate });
}

const TRUSTED_PAYOFF_QUOTE_CODEC = buildTrustedPayoffQuoteCodec();

/** Return the fixed cross-language test fixture; this is not a value factory. */
export const canonicalGoldenPayoffQuoteContext =
  TRUSTED_PAYOFF_QUOTE_CODEC.canonicalContext;
export const payoffQuoteDigest = TRUSTED_PAYOFF_QUOTE_CODEC.digest;
export const validatePayoffQuoteDigest = TRUSTED_PAYOFF_QUOTE_CODEC.validate;

export function toHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
