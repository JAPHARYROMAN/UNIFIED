import { create, fromBinary, toBinary } from "@bufbuild/protobuf";
import { TimestampSchema } from "@bufbuild/protobuf/wkt";
import { sha256 } from "@noble/hashes/sha2.js";
import { keccak_256 } from "@noble/hashes/sha3.js";

import {
  canonicalUftLockedPayloadHash,
  crossChainMessageId,
  encodeCanonicalUftLockedPayload,
  encodeLoanCancellationAuthorization,
  encodeLoanCancellationRequestedPayload,
  encodeSatelliteFundingCancelledPayload,
  recoveryAuthorizationDigest,
  syntheticFinalityDigest,
  toHex,
} from "../../../packages/crosschain/typescript/codec.js";
import {
  CanonicalUftLockPayloadSchema,
  CrossChainActionType,
  CrossChainMessageEnvelopeSchema,
  CrossChainRecoveryAuthorizationV2Schema,
  CrossChainRecoveryRequestV2Schema,
  LoanCancellationAuthorizationSchema,
  LoanCancellationRequestedPayloadSchema,
  RecoveryAction,
  SatelliteFundingCancelledPayloadSchema,
} from "../../../packages/generated/typescript/unified/v1/crosschain_pb.js";

const EXPECTED_PAYLOAD_HASH =
  "805585e890e898930c0ac7d38c1e157d0e4a5964eb8239552298bb2d3789877a";
const EXPECTED_MESSAGE_ID =
  "f8d9ef5672d829229110e480489155be0440e916833a1290a8955a8acf9c4801";
const EXPECTED_FINALITY_DIGEST =
  "6ebe5277d0c32b531c792319523fd367e073607937dea0c3949c5f8d43ca8820";
const GOLDEN_SOURCE_PROOF_HASH =
  "48d3a5bd4a6edfa6da4ceb1fb19fb7d7d975e24ac53af96bc4bc39947a566caf";
const EXPECTED_RECOVERY_AUTHORIZATION_DIGEST =
  "2ca5318f1079c2d3c45a5cefb7c5cf784728956bd328df3ee36feeb9b16af0ad";
const EXPECTED_CANCELLATION_AUTHORIZATION_ABI_HASH =
  "6559f566fae044a0b47fad5ad54de9a09b55e0cba3bd34290293e4e3e36b0bc0";
const EXPECTED_CANCELLATION_REQUEST_ABI_HASH =
  "d8b5a830c89f14d7eaebe14c1c819a2526194c05491fb357bf972464612fb992";
const EXPECTED_FUNDING_CANCELLED_ABI_HASH =
  "e272800252a7b96d69aba58e658c1151e5211a1c7137700ff341cbe2d9c23dba";
const EXPECTED_CANCELLATION_AUTHORIZATION_WIRE_HASH =
  "d49fc566ee4db808a2baa92b2ce06d3bf7c22f57909e8fe6325118033d11622a";
const EXPECTED_CANCELLATION_REQUEST_WIRE_HASH =
  "15e698482aa0b475255ea058fca3ed816a7cae9921658c1c85dfe958b4155285";
const EXPECTED_FUNDING_CANCELLED_WIRE_HASH =
  "1c7fe124da7a90146e157f9afea1b265ccda3394b1312b5044045766519a1909";

function repeated(byte: number, length: number): Uint8Array {
  return new Uint8Array(length).fill(byte);
}

export function verifyCrossChainGoldenVectors(): void {
  const payload = create(CanonicalUftLockPayloadSchema, {
    lockId: repeated(0x11, 32),
    loanId: repeated(0x22, 32),
    canonicalToken: repeated(0x11, 20),
    homeBridgeHub: repeated(0x22, 20),
    wrappedToken: repeated(0x33, 20),
    destinationRecipient: repeated(0x44, 20),
    amount: "1000000000000000000",
  });
  const payloadBytes = encodeCanonicalUftLockedPayload(payload);
  const payloadHash = canonicalUftLockedPayloadHash(payload);
  if (payloadBytes.length !== 7 * 32 || toHex(payloadHash) !== EXPECTED_PAYLOAD_HASH) {
    throw new Error("TypeScript canonical lock ABI golden vector changed");
  }

  const policyHash = repeated(0x11, 32);
  const envelope = create(CrossChainMessageEnvelopeSchema, {
    schemaVersion: 1,
    protocolId: repeated(0x01, 32),
    sourceChainId: "31337",
    sourceCoordinator: repeated(0x02, 20),
    sourceComponent: repeated(0x03, 20),
    destinationChainId: "31338",
    destinationCoordinator: repeated(0x04, 20),
    destinationComponent: repeated(0x05, 20),
    laneId: repeated(0x06, 32),
    sourceNonce: 1n,
    aggregateId: repeated(0x07, 32),
    actionType: CrossChainActionType.CANONICAL_UFT_LOCKED_V1,
    typedActionPayload: payloadBytes,
    payloadHash,
    createdAt: create(TimestampSchema, { seconds: 1_700_000_000n }),
    expiresAt: create(TimestampSchema, { seconds: 1_700_003_600n }),
    routePolicyHash: policyHash,
    adapterSetPolicyHash: policyHash,
    sourceFinalityPolicyHash: policyHash,
    destinationFinalityPolicyHash: policyHash,
    correlationId: policyHash,
    causationMessageId: new Uint8Array(32),
    supersededMessageId: new Uint8Array(32),
    typedAction: { case: "canonicalUftLock", value: payload },
  });
  const messageId = crossChainMessageId(envelope);
  if (toHex(messageId) !== EXPECTED_MESSAGE_ID) {
    throw new Error("TypeScript message-ID golden vector changed");
  }

  const finalityDigest = syntheticFinalityDigest({
    destinationChainId: 31338n,
    verifier: repeated(0x55, 20),
    messageId,
    sourceProofHash: Uint8Array.from(
      GOLDEN_SOURCE_PROOF_HASH.match(/../g) ?? [],
      (value) => Number.parseInt(value, 16),
    ),
    signerSetHash: repeated(0x77, 32),
    signerSetVersion: 1,
  });
  if (toHex(finalityDigest) !== EXPECTED_FINALITY_DIGEST) {
    throw new Error("TypeScript finality-digest golden vector changed");
  }

  const recovery = create(CrossChainRecoveryAuthorizationV2Schema, {
    protocolId: repeated(0x01, 32),
    sourceChainId: "31337",
    sourceCoordinator: repeated(0x02, 20),
    destinationChainId: "31338",
    destinationCoordinator: repeated(0x04, 20),
    request: create(CrossChainRecoveryRequestV2Schema, {
      messageId: repeated(0xaa, 32),
      envelopeHash: repeated(0xbb, 32),
      routePolicyHash: repeated(0xcc, 32),
      assetAmountCommitment: repeated(0xdd, 32),
      sourceStateCommitment: repeated(0xee, 32),
      destinationStateCommitment: repeated(0xff, 32),
      compensationPayloadHash: repeated(0x12, 32),
      messageExpiresAt: 1_700_003_600n,
      recoveryNonce: 7n,
      reasonCode: repeated(0x13, 32),
      action: RecoveryAction.TOMBSTONE_THEN_COMPENSATE,
      authorizerSetHash: repeated(0x14, 32),
      authorizerSetVersion: 1,
    }),
    authorizerSignatures: [repeated(0x21, 65), repeated(0x22, 65)],
    signerBitmap: 3,
  });
  const recoveryWire = toBinary(CrossChainRecoveryAuthorizationV2Schema, recovery);
  const recovered = fromBinary(CrossChainRecoveryAuthorizationV2Schema, recoveryWire);
  if (
    recoveryWire.length !== 549 ||
    toHex(recoveryAuthorizationDigest(recovered)) !==
      EXPECTED_RECOVERY_AUTHORIZATION_DIGEST
  ) {
    throw new Error("TypeScript recovery V2 protobuf/ABI golden vector changed");
  }

  const cancellationAuthorization = create(LoanCancellationAuthorizationSchema, {
    loanRouter: repeated(0x11, 20),
    loanId: repeated(0x22, 32),
    fundingLockId: repeated(0x33, 32),
    disbursementMessageId: repeated(0x44, 32),
    disbursementTombstoneHash: repeated(0x55, 32),
    amount: "1000000000000000000",
    policyHash: repeated(0x66, 32),
    authorizationNonce: 7n,
    validUntil: 1_700_003_600n,
    reasonCode: repeated(0x77, 32),
    authorizerSetHash: repeated(0x88, 32),
    authorizerSetVersion: 1,
  });
  const cancellationAuthorizationABI = encodeLoanCancellationAuthorization(
    cancellationAuthorization,
  );
  const cancellationAuthorizationWire = toBinary(
    LoanCancellationAuthorizationSchema,
    cancellationAuthorization,
  );
  if (
    cancellationAuthorizationABI.length !== 12 * 32 ||
    toHex(sha256(cancellationAuthorizationWire)) !==
      EXPECTED_CANCELLATION_AUTHORIZATION_WIRE_HASH ||
    toHex(keccak_256(cancellationAuthorizationABI)) !==
      EXPECTED_CANCELLATION_AUTHORIZATION_ABI_HASH
  ) {
    throw new Error("TypeScript loan-cancellation authorization golden changed");
  }

  const cancellationRequest = create(LoanCancellationRequestedPayloadSchema, {
    cancellationId: repeated(0x99, 32),
    loanId: repeated(0x22, 32),
    fundingLockId: repeated(0x33, 32),
    disbursementMessageId: repeated(0x44, 32),
    disbursementTombstoneHash: repeated(0x55, 32),
    homeLoanAccount: repeated(0xaa, 20),
    lender: repeated(0xbb, 20),
    wrappedToken: repeated(0xcc, 20),
    amount: "1000000000000000000",
    policyHash: repeated(0x66, 32),
    reasonCode: repeated(0x77, 32),
  });
  const cancellationRequestABI =
    encodeLoanCancellationRequestedPayload(cancellationRequest);
  const cancellationRequestWire = toBinary(
    LoanCancellationRequestedPayloadSchema,
    cancellationRequest,
  );
  if (
    cancellationRequestABI.length !== 11 * 32 ||
    toHex(sha256(cancellationRequestWire)) !==
      EXPECTED_CANCELLATION_REQUEST_WIRE_HASH ||
    toHex(keccak_256(cancellationRequestABI)) !==
      EXPECTED_CANCELLATION_REQUEST_ABI_HASH
  ) {
    throw new Error("TypeScript action-12 cancellation golden changed");
  }

  const fundingCancelled = create(SatelliteFundingCancelledPayloadSchema, {
    cancellationId: repeated(0x99, 32),
    loanId: repeated(0x22, 32),
    fundingLockId: repeated(0x33, 32),
    disbursementMessageId: repeated(0x44, 32),
    disbursementTombstoneHash: repeated(0x55, 32),
    escrowBurnResultHash: repeated(0xdd, 32),
    homeLoanAccount: repeated(0xaa, 20),
    lender: repeated(0xbb, 20),
    wrappedToken: repeated(0xcc, 20),
    amount: "1000000000000000000",
    policyHash: repeated(0x66, 32),
  });
  const fundingCancelledABI =
    encodeSatelliteFundingCancelledPayload(fundingCancelled);
  const fundingCancelledWire = toBinary(
    SatelliteFundingCancelledPayloadSchema,
    fundingCancelled,
  );
  if (
    fundingCancelledABI.length !== 11 * 32 ||
    toHex(sha256(fundingCancelledWire)) !==
      EXPECTED_FUNDING_CANCELLED_WIRE_HASH ||
    toHex(keccak_256(fundingCancelledABI)) !== EXPECTED_FUNDING_CANCELLED_ABI_HASH
  ) {
    throw new Error("TypeScript action-14 cancellation golden changed");
  }
}
