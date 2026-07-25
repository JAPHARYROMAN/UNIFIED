import { keccak_256 } from "@noble/hashes/sha3.js";

import type {
  CanonicalUftLockPayload,
  CrossChainMessageEnvelope,
  CrossChainRecoveryAuthorizationV2,
  LoanCancellationAuthorization,
  LoanCancellationRequestedPayload,
  SatelliteFundingCancelledPayload,
} from "../../generated/typescript/unified/v1/crosschain_pb.js";

const WORD_BYTES = 32;
const UINT256_LIMIT = 1n << 256n;
const MESSAGE_DOMAIN = "UNIFIED_XCHAIN_MESSAGE_V1";
const FINALITY_DOMAIN = "UNIFIED_SYNTHETIC_FINALITY_V1";
const RECOVERY_AUTHORIZATION_DOMAIN = "UNIFIED_XCHAIN_RECOVERY_AUTHORIZATION_V2";

function concat(parts: readonly Uint8Array[]): Uint8Array {
  const length = parts.reduce((total, part) => total + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function uintWord(value: bigint): Uint8Array {
  if (value < 0n || value >= UINT256_LIMIT) {
    throw new Error("value is outside uint256");
  }
  const result = new Uint8Array(WORD_BYTES);
  let remaining = value;
  for (let index = WORD_BYTES - 1; index >= 0; index -= 1) {
    result[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  return result;
}

function exactBytes(value: Uint8Array, length: number, field: string): Uint8Array {
  if (value.length !== length) {
    throw new Error(`${field} must contain ${length} bytes`);
  }
  return value;
}

function addressWord(value: Uint8Array, field: string): Uint8Array {
  return concat([new Uint8Array(12), exactBytes(value, 20, field)]);
}

function dynamicStringTail(value: string): Uint8Array {
  const encoded = new TextEncoder().encode(value);
  const padding = (WORD_BYTES - (encoded.length % WORD_BYTES)) % WORD_BYTES;
  return concat([uintWord(BigInt(encoded.length)), encoded, new Uint8Array(padding)]);
}

function abiEncodeDynamicDomain(
  domain: string,
  staticWords: readonly Uint8Array[],
): Uint8Array {
  const argumentCount = staticWords.length + 1;
  return concat([
    uintWord(BigInt(argumentCount * WORD_BYTES)),
    ...staticWords.map((word, index) => exactBytes(word, WORD_BYTES, `word ${index}`)),
    dynamicStringTail(domain),
  ]);
}

export function encodeCanonicalUftLockedPayload(
  payload: CanonicalUftLockPayload,
): Uint8Array {
  return concat([
    exactBytes(payload.lockId, 32, "lock_id"),
    exactBytes(payload.loanId, 32, "loan_id"),
    addressWord(payload.canonicalToken, "canonical_token"),
    addressWord(payload.homeBridgeHub, "home_bridge_hub"),
    addressWord(payload.wrappedToken, "wrapped_token"),
    addressWord(payload.destinationRecipient, "destination_recipient"),
    uintWord(BigInt(payload.amount)),
  ]);
}

export function canonicalUftLockedPayloadHash(
  payload: CanonicalUftLockPayload,
): Uint8Array {
  return keccak_256(encodeCanonicalUftLockedPayload(payload));
}

export function encodeLoanCancellationAuthorization(
  authorization: LoanCancellationAuthorization,
): Uint8Array {
  return concat([
    addressWord(authorization.loanRouter, "loan_router"),
    exactBytes(authorization.loanId, 32, "loan_id"),
    exactBytes(authorization.fundingLockId, 32, "funding_lock_id"),
    exactBytes(
      authorization.disbursementMessageId,
      32,
      "disbursement_message_id",
    ),
    exactBytes(
      authorization.disbursementTombstoneHash,
      32,
      "disbursement_tombstone_hash",
    ),
    uintWord(BigInt(authorization.amount)),
    exactBytes(authorization.policyHash, 32, "policy_hash"),
    uintWord(authorization.authorizationNonce),
    uintWord(authorization.validUntil),
    exactBytes(authorization.reasonCode, 32, "reason_code"),
    exactBytes(authorization.authorizerSetHash, 32, "authorizer_set_hash"),
    uintWord(BigInt(authorization.authorizerSetVersion)),
  ]);
}

export function encodeLoanCancellationRequestedPayload(
  payload: LoanCancellationRequestedPayload,
): Uint8Array {
  return concat([
    exactBytes(payload.cancellationId, 32, "cancellation_id"),
    exactBytes(payload.loanId, 32, "loan_id"),
    exactBytes(payload.fundingLockId, 32, "funding_lock_id"),
    exactBytes(payload.disbursementMessageId, 32, "disbursement_message_id"),
    exactBytes(
      payload.disbursementTombstoneHash,
      32,
      "disbursement_tombstone_hash",
    ),
    addressWord(payload.homeLoanAccount, "home_loan_account"),
    addressWord(payload.lender, "lender"),
    addressWord(payload.wrappedToken, "wrapped_token"),
    uintWord(BigInt(payload.amount)),
    exactBytes(payload.policyHash, 32, "policy_hash"),
    exactBytes(payload.reasonCode, 32, "reason_code"),
  ]);
}

export function encodeSatelliteFundingCancelledPayload(
  payload: SatelliteFundingCancelledPayload,
): Uint8Array {
  return concat([
    exactBytes(payload.cancellationId, 32, "cancellation_id"),
    exactBytes(payload.loanId, 32, "loan_id"),
    exactBytes(payload.fundingLockId, 32, "funding_lock_id"),
    exactBytes(payload.disbursementMessageId, 32, "disbursement_message_id"),
    exactBytes(
      payload.disbursementTombstoneHash,
      32,
      "disbursement_tombstone_hash",
    ),
    exactBytes(payload.escrowBurnResultHash, 32, "escrow_burn_result_hash"),
    addressWord(payload.homeLoanAccount, "home_loan_account"),
    addressWord(payload.lender, "lender"),
    addressWord(payload.wrappedToken, "wrapped_token"),
    uintWord(BigInt(payload.amount)),
    exactBytes(payload.policyHash, 32, "policy_hash"),
  ]);
}

export function crossChainMessageId(envelope: CrossChainMessageEnvelope): Uint8Array {
  if (envelope.createdAt === undefined || envelope.expiresAt === undefined) {
    throw new Error("created_at and expires_at are required");
  }
  const staticWords = [
    uintWord(BigInt(envelope.schemaVersion)),
    exactBytes(envelope.protocolId, 32, "protocol_id"),
    uintWord(BigInt(envelope.sourceChainId)),
    addressWord(envelope.sourceCoordinator, "source_coordinator"),
    addressWord(envelope.sourceComponent, "source_component"),
    uintWord(BigInt(envelope.destinationChainId)),
    addressWord(envelope.destinationCoordinator, "destination_coordinator"),
    addressWord(envelope.destinationComponent, "destination_component"),
    exactBytes(envelope.laneId, 32, "lane_id"),
    uintWord(envelope.sourceNonce),
    exactBytes(envelope.aggregateId, 32, "aggregate_id"),
    uintWord(BigInt(envelope.actionType)),
    exactBytes(envelope.payloadHash, 32, "payload_hash"),
    uintWord(envelope.createdAt.seconds),
    uintWord(envelope.expiresAt.seconds),
    exactBytes(envelope.routePolicyHash, 32, "route_policy_hash"),
    exactBytes(envelope.adapterSetPolicyHash, 32, "adapter_set_policy_hash"),
    exactBytes(envelope.sourceFinalityPolicyHash, 32, "source_finality_policy_hash"),
    exactBytes(
      envelope.destinationFinalityPolicyHash,
      32,
      "destination_finality_policy_hash",
    ),
    exactBytes(envelope.correlationId, 32, "correlation_id"),
    exactBytes(envelope.causationMessageId, 32, "causation_message_id"),
    exactBytes(envelope.supersededMessageId, 32, "superseded_message_id"),
  ];
  return keccak_256(abiEncodeDynamicDomain(MESSAGE_DOMAIN, staticWords));
}

export interface FinalityDigestInput {
  destinationChainId: bigint;
  verifier: Uint8Array;
  messageId: Uint8Array;
  sourceProofHash: Uint8Array;
  signerSetHash: Uint8Array;
  signerSetVersion: number;
}

export function syntheticFinalityDigest(input: FinalityDigestInput): Uint8Array {
  return keccak_256(
    abiEncodeDynamicDomain(FINALITY_DOMAIN, [
      uintWord(input.destinationChainId),
      addressWord(input.verifier, "verifier"),
      exactBytes(input.messageId, 32, "message_id"),
      exactBytes(input.sourceProofHash, 32, "source_proof_hash"),
      exactBytes(input.signerSetHash, 32, "signer_set_hash"),
      uintWord(BigInt(input.signerSetVersion)),
    ]),
  );
}

export function recoveryAuthorizationDigest(
  authorization: CrossChainRecoveryAuthorizationV2,
): Uint8Array {
  const request = authorization.request;
  if (request === undefined) {
    throw new Error("recovery request is required");
  }
  return keccak_256(
    abiEncodeDynamicDomain(RECOVERY_AUTHORIZATION_DOMAIN, [
      exactBytes(authorization.protocolId, 32, "protocol_id"),
      uintWord(BigInt(authorization.sourceChainId)),
      addressWord(authorization.sourceCoordinator, "source_coordinator"),
      uintWord(BigInt(authorization.destinationChainId)),
      addressWord(authorization.destinationCoordinator, "destination_coordinator"),
      exactBytes(request.messageId, 32, "message_id"),
      exactBytes(request.envelopeHash, 32, "envelope_hash"),
      exactBytes(request.routePolicyHash, 32, "route_policy_hash"),
      exactBytes(request.assetAmountCommitment, 32, "asset_amount_commitment"),
      exactBytes(request.sourceStateCommitment, 32, "source_state_commitment"),
      exactBytes(
        request.destinationStateCommitment,
        32,
        "destination_state_commitment",
      ),
      exactBytes(
        request.compensationPayloadHash,
        32,
        "compensation_payload_hash",
      ),
      uintWord(request.messageExpiresAt),
      uintWord(request.recoveryNonce),
      exactBytes(request.reasonCode, 32, "reason_code"),
      uintWord(BigInt(request.action)),
      exactBytes(request.authorizerSetHash, 32, "authorizer_set_hash"),
      uintWord(BigInt(request.authorizerSetVersion)),
    ]),
  );
}

export function toHex(value: Uint8Array): string {
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
