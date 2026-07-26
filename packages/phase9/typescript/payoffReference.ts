import { keccak_256 } from "@noble/hashes/sha3.js";

const WORD_BYTES = 32;
const UINT64_LIMIT = 1n << 64n;
const UINT256_LIMIT = 1n << 256n;

export const PAYOFF_POLICY_DOMAIN = "UNIFIED_PAYOFF_POLICY_V1";
export const PAYOFF_COMPONENTS_DOMAIN = "UNIFIED_PAYOFF_COMPONENT_BENEFICIARIES_V1";
export const PAYOFF_ROUTE_DOMAIN = "UNIFIED_PAYOFF_SETTLEMENT_ROUTE_V1";
export const PAYOFF_QUOTE_DOMAIN = "UNIFIED_PAYOFF_QUOTE_V1";

export interface PayoffPolicyReference {
  readonly chainId: bigint;
  readonly payoffQuoteEngine: Uint8Array;
  readonly quotePolicyRegistry: Uint8Array;
  readonly loanId: Uint8Array;
  readonly loanAccount: Uint8Array;
  readonly boundPolicySetHash: Uint8Array;
  readonly feePenaltyBeneficiary: Uint8Array;
  readonly settlementAssetId: Uint8Array;
  readonly settlementToken: Uint8Array;
  readonly maximumValidity: bigint;
}

export interface PayoffComponentReference {
  readonly kind: bigint;
  readonly amount: bigint;
  readonly beneficiary: Uint8Array;
  readonly obligationCode: string;
}

export interface SettlementRouteReference {
  readonly chainId: bigint;
  readonly payoffQuoteEngine: Uint8Array;
  readonly refinanceCoordinator: Uint8Array;
  readonly loanId: Uint8Array;
  readonly loanAccount: Uint8Array;
  readonly settlementAssetId: Uint8Array;
  readonly settlementToken: Uint8Array;
  readonly lenderBeneficiary: Uint8Array;
  readonly feePenaltyBeneficiary: Uint8Array;
  readonly policyHash: Uint8Array;
}

export interface PayoffQuoteIdentityReference {
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
  const output = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

function exactBytes(value: Uint8Array, length: number, field: string): Uint8Array {
  if (value.length !== length) {
    throw new Error(`${field} must contain ${length} bytes`);
  }
  return value;
}

function uintWord(value: bigint, limit: bigint, field: string): Uint8Array {
  if (value < 0n || value >= limit) {
    throw new Error(`${field} is outside its unsigned integer range`);
  }
  const output = new Uint8Array(WORD_BYTES);
  let remaining = value;
  for (let index = WORD_BYTES - 1; index >= 0; index -= 1) {
    output[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return output;
}

function addressWord(value: Uint8Array, field: string): Uint8Array {
  return concat([new Uint8Array(12), exactBytes(value, 20, field)]);
}

function stringTail(value: string): Uint8Array {
  const encoded = new TextEncoder().encode(value);
  return concat([
    uintWord(BigInt(encoded.length), UINT256_LIMIT, "string length"),
    encoded,
    new Uint8Array((-encoded.length) & 31),
  ]);
}

function domainAndStaticWords(domain: string, staticWords: readonly Uint8Array[]): Uint8Array {
  return concat([
    uintWord(BigInt((staticWords.length + 1) * WORD_BYTES), UINT256_LIMIT, "domain offset"),
    ...staticWords.map((word) => exactBytes(word, WORD_BYTES, "static ABI word")),
    stringTail(domain),
  ]);
}

export function encodePayoffPolicy(reference: PayoffPolicyReference): Uint8Array {
  return domainAndStaticWords(PAYOFF_POLICY_DOMAIN, [
    uintWord(reference.chainId, UINT256_LIMIT, "chain_id"),
    addressWord(reference.payoffQuoteEngine, "payoff_quote_engine"),
    addressWord(reference.quotePolicyRegistry, "quote_policy_registry"),
    exactBytes(reference.loanId, 32, "loan_id"),
    addressWord(reference.loanAccount, "loan_account"),
    exactBytes(reference.boundPolicySetHash, 32, "bound_policy_set_hash"),
    addressWord(reference.feePenaltyBeneficiary, "fee_penalty_beneficiary"),
    exactBytes(reference.settlementAssetId, 32, "settlement_asset_id"),
    addressWord(reference.settlementToken, "settlement_token"),
    uintWord(reference.maximumValidity, UINT64_LIMIT, "maximum_validity"),
  ]);
}

export function payoffPolicyHash(reference: PayoffPolicyReference): Uint8Array {
  return keccak_256(encodePayoffPolicy(reference));
}

export function canonicalPayoffComponents(input: {
  readonly principal: bigint;
  readonly accruedInterest: bigint;
  readonly fees: bigint;
  readonly penalties: bigint;
  readonly credits: bigint;
  readonly lenderBeneficiary: Uint8Array;
  readonly feePenaltyBeneficiary: Uint8Array;
}): readonly PayoffComponentReference[] {
  return Object.freeze([
    Object.freeze({
      kind: 1n,
      amount: input.principal,
      beneficiary: input.lenderBeneficiary,
      obligationCode: "PRINCIPAL",
    }),
    Object.freeze({
      kind: 2n,
      amount: input.accruedInterest,
      beneficiary: input.lenderBeneficiary,
      obligationCode: "ACCRUED_INTEREST",
    }),
    Object.freeze({
      kind: 4n,
      amount: input.fees,
      beneficiary: input.feePenaltyBeneficiary,
      obligationCode: "FEE",
    }),
    Object.freeze({
      kind: 5n,
      amount: input.penalties,
      beneficiary: input.feePenaltyBeneficiary,
      obligationCode: "PENALTY",
    }),
    Object.freeze({
      kind: 7n,
      amount: input.credits,
      beneficiary: input.feePenaltyBeneficiary,
      obligationCode: "FEE_PENALTY_CREDIT",
    }),
  ]);
}

function encodeComponent(component: PayoffComponentReference): Uint8Array {
  return concat([
    uintWord(component.kind, 1n << 8n, "component.kind"),
    uintWord(component.amount, UINT256_LIMIT, "component.amount"),
    addressWord(component.beneficiary, "component.beneficiary"),
    uintWord(BigInt(4 * WORD_BYTES), UINT256_LIMIT, "component obligation-code offset"),
    stringTail(component.obligationCode),
  ]);
}

export function encodeComponentBeneficiaries(
  components: readonly PayoffComponentReference[],
): Uint8Array {
  if (components.length !== 5) {
    throw new Error("the V1 payoff component vector must contain exactly five entries");
  }
  const encodedComponents = components.map(encodeComponent);
  let nextOffset = BigInt(components.length * WORD_BYTES);
  const offsets = encodedComponents.map((component) => {
    const offset = uintWord(nextOffset, UINT256_LIMIT, "component offset");
    nextOffset += BigInt(component.length);
    return offset;
  });
  const arrayTail = concat([
    uintWord(BigInt(components.length), UINT256_LIMIT, "component count"),
    ...offsets,
    ...encodedComponents,
  ]);
  const domainTail = stringTail(PAYOFF_COMPONENTS_DOMAIN);
  return concat([
    uintWord(2n * BigInt(WORD_BYTES), UINT256_LIMIT, "component domain offset"),
    uintWord(
      2n * BigInt(WORD_BYTES) + BigInt(domainTail.length),
      UINT256_LIMIT,
      "component array offset",
    ),
    domainTail,
    arrayTail,
  ]);
}

export function componentBeneficiaryHash(
  components: readonly PayoffComponentReference[],
): Uint8Array {
  return keccak_256(encodeComponentBeneficiaries(components));
}

export function encodeSettlementRoute(reference: SettlementRouteReference): Uint8Array {
  return domainAndStaticWords(PAYOFF_ROUTE_DOMAIN, [
    uintWord(reference.chainId, UINT256_LIMIT, "chain_id"),
    addressWord(reference.payoffQuoteEngine, "payoff_quote_engine"),
    addressWord(reference.refinanceCoordinator, "refinance_coordinator"),
    exactBytes(reference.loanId, 32, "loan_id"),
    addressWord(reference.loanAccount, "loan_account"),
    exactBytes(reference.settlementAssetId, 32, "settlement_asset_id"),
    addressWord(reference.settlementToken, "settlement_token"),
    addressWord(reference.lenderBeneficiary, "lender_beneficiary"),
    addressWord(reference.feePenaltyBeneficiary, "fee_penalty_beneficiary"),
    exactBytes(reference.policyHash, 32, "policy_hash"),
  ]);
}

export function settlementRouteHash(reference: SettlementRouteReference): Uint8Array {
  return keccak_256(encodeSettlementRoute(reference));
}

export function encodePayoffQuoteIdentity(reference: PayoffQuoteIdentityReference): Uint8Array {
  return domainAndStaticWords(PAYOFF_QUOTE_DOMAIN, [
    addressWord(reference.payoffQuoteEngine, "payoff_quote_engine"),
    uintWord(reference.chainId, UINT256_LIMIT, "chain_id"),
    exactBytes(reference.loanId, 32, "loan_id"),
    addressWord(reference.loanAccount, "loan_account"),
    exactBytes(reference.policyHash, 32, "policy_hash"),
    uintWord(reference.debtStateVersion, UINT64_LIMIT, "debt_state_version"),
    uintWord(reference.principal, UINT256_LIMIT, "principal"),
    uintWord(reference.accruedInterest, UINT256_LIMIT, "accrued_interest"),
    uintWord(reference.fees, UINT256_LIMIT, "fees"),
    uintWord(reference.penalties, UINT256_LIMIT, "penalties"),
    uintWord(reference.credits, UINT256_LIMIT, "credits"),
    exactBytes(reference.componentBeneficiaryHash, 32, "component_beneficiary_hash"),
    uintWord(reference.netPayoff, UINT256_LIMIT, "net_payoff"),
    exactBytes(reference.settlementAssetId, 32, "settlement_asset_id"),
    addressWord(reference.settlementToken, "settlement_token"),
    exactBytes(reference.settlementRouteHash, 32, "settlement_route_hash"),
    uintWord(reference.issuedAt, UINT64_LIMIT, "issued_at"),
    uintWord(reference.validUntil, UINT64_LIMIT, "valid_until"),
    uintWord(reference.quoteNonce, UINT64_LIMIT, "quote_nonce"),
  ]);
}

export function payoffQuoteId(reference: PayoffQuoteIdentityReference): Uint8Array {
  return keccak_256(encodePayoffQuoteIdentity(reference));
}

export function referenceBytesToHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
