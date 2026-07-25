// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICrossChainCompensable } from "../interfaces/ICrossChainReceiver.sol";
import { CrossChainTypes } from "./CrossChainTypes.sol";
import { CrossChainCoordinator } from "./CrossChainCoordinator.sol";
import { RouteRegistry } from "./RouteRegistry.sol";
import { SyntheticFinalityVerifier } from "./SyntheticFinalityVerifier.sol";

/// @notice Multi-party, evidence-bound staged tombstone-then-compensate recovery.
contract CrossChainRecoveryController is ReentrancyGuard {
    using ECDSA for bytes32;

    error InvalidRecoveryConfiguration();
    error InvalidRecovery();
    error InsufficientRecoveryAuthorization();
    error ConflictingRecovery(bytes32 messageId, bytes32 existingRecoveryId);

    enum RecoveryAction {
        UNSPECIFIED,
        TOMBSTONE_THEN_COMPENSATE
    }

    enum RecoveryState {
        NONE,
        AUTHORIZED,
        DESTINATION_TOMBSTONED,
        SOURCE_COMPENSATED
    }

    struct RecoveryRequest {
        bytes32 messageId;
        bytes32 envelopeHash;
        bytes32 routePolicyHash;
        bytes32 assetAmountCommitment;
        bytes32 sourceStateCommitment;
        bytes32 destinationStateCommitment;
        bytes32 compensationPayloadHash;
        uint64 messageExpiresAt;
        uint64 recoveryNonce;
        bytes32 reasonCode;
        RecoveryAction action;
        bytes32 authorizerSetHash;
        uint32 authorizerSetVersion;
    }

    struct RecoveryRecord {
        bytes32 requestDigest;
        uint8 signerBitmap;
        RecoveryState state;
        bytes32 tombstoneEventHash;
        bytes32 compensationPayloadHash;
        bytes32 compensationResult;
    }

    uint8 public constant RECOVERY_THRESHOLD = 2;
    uint32 public constant AUTHORIZER_SET_VERSION = 1;

    CrossChainCoordinator public immutable coordinator;
    RouteRegistry public immutable routeRegistry;
    SyntheticFinalityVerifier public immutable finalityVerifier;
    bytes32 public immutable authorizerSetHash;
    address[3] public recoverySigners;

    mapping(bytes32 recoveryId => RecoveryRecord record) public recoveryRecords;
    mapping(bytes32 messageId => bytes32 recoveryId) public recoveryForMessage;
    mapping(bytes32 messageId => bytes32 tombstoneEventHash) public destinationTombstone;
    mapping(bytes32 messageId => bytes32 compensationResult) public sourceCompensation;
    mapping(bytes32 laneId => uint64 nonce) public nextRecoveryNonce;
    mapping(address loanRouter => mapping(bytes32 loanId => uint64 nonce)) public
        nextLoanCancellationNonce;
    mapping(address loanRouter => mapping(bytes32 loanId => bytes32 cancellationId)) public
        cancellationForLoan;
    mapping(bytes32 cancellationId => uint8 signerBitmap) public loanCancellationSignerBitmap;

    event RecoveryTombstoneRecorded(
        bytes32 indexed recoveryId,
        bytes32 indexed messageId,
        uint64 indexed recoveryNonce,
        bytes32 reasonCode,
        uint8 signerBitmap,
        bytes32 tombstoneEventHash
    );
    event SourceCompensated(
        bytes32 indexed recoveryId, bytes32 indexed messageId, bytes32 indexed resultHash
    );
    event LoanCancellationAuthorized(
        bytes32 indexed cancellationId,
        bytes32 indexed loanId,
        address indexed loanRouter,
        uint64 authorizationNonce,
        bytes32 reasonCode,
        uint8 signerBitmap
    );

    constructor(
        CrossChainCoordinator coordinator_,
        RouteRegistry routeRegistry_,
        SyntheticFinalityVerifier finalityVerifier_,
        address[3] memory recoverySigners_
    ) {
        if (
            address(coordinator_) == address(0) || address(routeRegistry_) == address(0)
                || address(finalityVerifier_) == address(0)
        ) {
            revert InvalidRecoveryConfiguration();
        }
        _sortSigners(recoverySigners_);
        if (
            recoverySigners_[0] == address(0) || recoverySigners_[0] == recoverySigners_[1]
                || recoverySigners_[1] == recoverySigners_[2]
        ) {
            revert InvalidRecoveryConfiguration();
        }
        coordinator = coordinator_;
        routeRegistry = routeRegistry_;
        finalityVerifier = finalityVerifier_;
        recoverySigners = recoverySigners_;
        authorizerSetHash = keccak256(
            abi.encode(
                "UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1",
                AUTHORIZER_SET_VERSION,
                RECOVERY_THRESHOLD,
                recoverySigners_
            )
        );
    }

    function recordDestinationTombstone(
        CrossChainTypes.MessageEnvelope calldata envelope,
        RecoveryRequest calldata request,
        bytes[] calldata signatures
    ) external returns (bytes32 tombstoneEventHash) {
        bytes32 recoveryId_ = recoveryId(request);
        bytes32 digest = _validateRequest(envelope, request);
        RecoveryRecord storage record = recoveryRecords[recoveryId_];
        if (record.requestDigest != bytes32(0)) {
            if (
                record.requestDigest != digest
                    || record.state != RecoveryState.DESTINATION_TOMBSTONED
            ) revert InvalidRecovery();
            return record.tombstoneEventHash;
        }
        _bindMessage(request.messageId, recoveryId_);
        if (
            envelope.destinationChainId != coordinator.localChainId()
                || envelope.destinationCoordinator != address(coordinator)
                || block.timestamp < envelope.expiresAt
                || request.recoveryNonce != nextRecoveryNonce[envelope.laneId] + 1
        ) revert InvalidRecovery();

        uint8 signerBitmap = _authorizationBitmap(digest, signatures);
        record.requestDigest = digest;
        record.signerBitmap = signerBitmap;
        record.state = RecoveryState.AUTHORIZED;
        nextRecoveryNonce[envelope.laneId] = request.recoveryNonce;
        tombstoneEventHash =
            coordinator.recordTombstone(envelope, request.recoveryNonce, request.reasonCode);
        record.tombstoneEventHash = tombstoneEventHash;
        record.state = RecoveryState.DESTINATION_TOMBSTONED;
        destinationTombstone[envelope.messageId] = tombstoneEventHash;
        emit RecoveryTombstoneRecorded(
            recoveryId_,
            envelope.messageId,
            request.recoveryNonce,
            request.reasonCode,
            signerBitmap,
            tombstoneEventHash
        );
    }

    function compensateSource(
        CrossChainTypes.MessageEnvelope calldata envelope,
        RecoveryRequest calldata request,
        bytes[] calldata signatures,
        bytes32 expectedTombstoneEventHash,
        bytes calldata compensationPayload,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate
    ) external nonReentrant returns (bytes32 resultHash) {
        bytes32 recoveryId_ = recoveryId(request);
        bytes32 digest = _validateRequest(envelope, request);
        if (request.compensationPayloadHash != keccak256(compensationPayload)) {
            revert InvalidRecovery();
        }
        RecoveryRecord storage record = recoveryRecords[recoveryId_];
        if (record.compensationResult != bytes32(0)) {
            if (
                record.requestDigest != digest
                    || record.tombstoneEventHash != expectedTombstoneEventHash
                    || record.compensationPayloadHash != keccak256(compensationPayload)
            ) revert InvalidRecovery();
            return record.compensationResult;
        }
        _bindMessage(request.messageId, recoveryId_);
        _validateSourceRecovery(envelope, request, expectedTombstoneEventHash, proof);
        uint8 signerBitmap = _authorizationBitmap(digest, signatures);
        record.requestDigest = digest;
        record.signerBitmap = signerBitmap;
        record.state = RecoveryState.DESTINATION_TOMBSTONED;
        record.tombstoneEventHash = expectedTombstoneEventHash;
        record.compensationPayloadHash = keccak256(compensationPayload);
        _verifyTombstoneFinality(envelope, proof, certificate, expectedTombstoneEventHash);
        resultHash = _executeCompensation(envelope, compensationPayload);
        if (resultHash == bytes32(0)) revert InvalidRecovery();
        _completeCompensation(recoveryId_, envelope.messageId, resultHash);
    }

    function _validateSourceRecovery(
        CrossChainTypes.MessageEnvelope calldata envelope,
        RecoveryRequest calldata request,
        bytes32 expectedTombstoneEventHash,
        CrossChainTypes.SourceEventProof calldata proof
    ) private view {
        if (
            envelope.sourceChainId != coordinator.localChainId()
                || envelope.sourceCoordinator != address(coordinator)
                || block.timestamp < envelope.expiresAt || expectedTombstoneEventHash == bytes32(0)
                || proof.eventHash != expectedTombstoneEventHash
                || expectedTombstoneEventHash
                    != CrossChainTypes.tombstoneEventHash(
                        envelope.destinationCoordinator,
                        envelope.messageId,
                        request.envelopeHash,
                        request.recoveryNonce,
                        request.reasonCode
                    )
        ) revert InvalidRecovery();
        CrossChainTypes.MessageEnvelope memory stored =
            coordinator.messageEnvelope(envelope.messageId);
        if (
            stored.messageId != envelope.messageId
                || keccak256(abi.encode(stored)) != request.envelopeHash
        ) revert InvalidRecovery();
    }

    function _verifyTombstoneFinality(
        CrossChainTypes.MessageEnvelope calldata envelope,
        CrossChainTypes.SourceEventProof calldata proof,
        CrossChainTypes.FinalityCertificate calldata certificate,
        bytes32 expectedTombstoneEventHash
    ) private view {
        RouteRegistry.RouteVersion memory route_ = routeRegistry.route(envelope.routePolicyHash);
        finalityVerifier.verify(
            envelope,
            proof,
            certificate,
            route_.config.destinationSignerSetHash,
            envelope.destinationFinalityPolicyHash,
            expectedTombstoneEventHash
        );
    }

    function _executeCompensation(
        CrossChainTypes.MessageEnvelope calldata envelope,
        bytes calldata compensationPayload
    ) private returns (bytes32) {
        return ICrossChainCompensable(envelope.sourceComponent)
            .compensateMessage(envelope.messageId, envelope.actionType, compensationPayload);
    }

    function _completeCompensation(bytes32 recoveryId_, bytes32 messageId, bytes32 resultHash)
        private
    {
        RecoveryRecord storage record = recoveryRecords[recoveryId_];
        record.compensationResult = resultHash;
        record.state = RecoveryState.SOURCE_COMPENSATED;
        sourceCompensation[messageId] = resultHash;
        emit SourceCompensated(recoveryId_, messageId, resultHash);
    }

    function recoveryId(RecoveryRequest calldata request) public pure returns (bytes32) {
        return keccak256(abi.encode("UNIFIED_XCHAIN_RECOVERY_ID_V1", request));
    }

    function recoveryAuthorizationDigest(
        CrossChainTypes.MessageEnvelope calldata envelope,
        RecoveryRequest calldata request
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_XCHAIN_RECOVERY_AUTHORIZATION_V2",
                envelope.protocolId,
                envelope.sourceChainId,
                envelope.sourceCoordinator,
                envelope.destinationChainId,
                envelope.destinationCoordinator,
                request
            )
        );
    }

    function loanCancellationAuthorizationDigest(
        CrossChainTypes.LoanCancellationAuthorization calldata request
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_LOAN_CANCELLATION_AUTHORIZATION_V1", block.chainid, address(this), request
            )
        );
    }

    function consumeLoanCancellationAuthorization(
        CrossChainTypes.LoanCancellationAuthorization calldata request,
        bytes[] calldata signatures
    ) external returns (bytes32 cancellationId) {
        if (
            msg.sender != request.loanRouter || request.loanRouter.code.length == 0
                || request.loanId == bytes32(0) || request.fundingLockId == bytes32(0)
                || request.amount == 0 || request.policyHash == bytes32(0)
                || request.authorizationNonce == 0 || request.validUntil == 0
                || request.reasonCode == bytes32(0)
                || request.authorizerSetHash != authorizerSetHash
                || request.authorizerSetVersion != AUTHORIZER_SET_VERSION
                || (request.disbursementMessageId == bytes32(0))
                    != (request.disbursementTombstoneHash == bytes32(0))
        ) revert InvalidRecovery();
        cancellationId = loanCancellationAuthorizationDigest(request);
        bytes32 existing = cancellationForLoan[request.loanRouter][request.loanId];
        if (existing != bytes32(0)) {
            if (existing != cancellationId) {
                revert ConflictingRecovery(request.loanId, existing);
            }
            return cancellationId;
        }
        if (
            block.timestamp > request.validUntil
                || request.authorizationNonce
                    != nextLoanCancellationNonce[request.loanRouter][request.loanId] + 1
        ) revert InvalidRecovery();
        uint8 signerBitmap = _authorizationBitmap(cancellationId, signatures);
        nextLoanCancellationNonce[request.loanRouter][request.loanId] = request.authorizationNonce;
        cancellationForLoan[request.loanRouter][request.loanId] = cancellationId;
        loanCancellationSignerBitmap[cancellationId] = signerBitmap;
        emit LoanCancellationAuthorized(
            cancellationId,
            request.loanId,
            request.loanRouter,
            request.authorizationNonce,
            request.reasonCode,
            signerBitmap
        );
    }

    function _validateRequest(
        CrossChainTypes.MessageEnvelope calldata envelope,
        RecoveryRequest calldata request
    ) private view returns (bytes32 digest) {
        if (
            request.messageId != envelope.messageId
                || request.envelopeHash != keccak256(abi.encode(envelope))
                || request.routePolicyHash != envelope.routePolicyHash
                || request.assetAmountCommitment
                    != keccak256(
                        abi.encode(
                            "UNIFIED_RECOVERY_ASSET_AMOUNT_COMMITMENT_V1",
                            envelope.actionType,
                            envelope.payloadHash
                        )
                    ) || request.sourceStateCommitment == bytes32(0)
                || request.destinationStateCommitment == bytes32(0)
                || request.compensationPayloadHash == bytes32(0)
                || request.messageExpiresAt != envelope.expiresAt || request.recoveryNonce == 0
                || request.reasonCode == bytes32(0)
                || request.action != RecoveryAction.TOMBSTONE_THEN_COMPENSATE
                || request.authorizerSetHash != authorizerSetHash
                || request.authorizerSetVersion != AUTHORIZER_SET_VERSION
        ) revert InvalidRecovery();
        digest = recoveryAuthorizationDigest(envelope, request);
    }

    function _bindMessage(bytes32 messageId, bytes32 recoveryId_) private {
        bytes32 existing = recoveryForMessage[messageId];
        if (existing != bytes32(0) && existing != recoveryId_) {
            revert ConflictingRecovery(messageId, existing);
        }
        recoveryForMessage[messageId] = recoveryId_;
    }

    function _authorizationBitmap(bytes32 digest, bytes[] calldata signatures)
        private
        view
        returns (uint8 bitmap)
    {
        if (signatures.length < RECOVERY_THRESHOLD || signatures.length > 3) {
            revert InsufficientRecoveryAuthorization();
        }
        for (uint256 index; index < signatures.length; ++index) {
            address recovered = digest.recover(signatures[index]);
            for (uint256 signerIndex; signerIndex < recoverySigners.length; ++signerIndex) {
                if (recovered == recoverySigners[signerIndex]) {
                    bitmap |= uint8(1) << uint8(signerIndex);
                    break;
                }
            }
        }
        uint256 valid;
        for (uint256 index; index < 3; ++index) {
            if (bitmap & (uint8(1) << uint8(index)) != 0) ++valid;
        }
        if (valid < RECOVERY_THRESHOLD) revert InsufficientRecoveryAuthorization();
    }

    function _sortSigners(address[3] memory signers) private pure {
        if (signers[0] > signers[1]) (signers[0], signers[1]) = (signers[1], signers[0]);
        if (signers[1] > signers[2]) (signers[1], signers[2]) = (signers[2], signers[1]);
        if (signers[0] > signers[1]) (signers[0], signers[1]) = (signers[1], signers[0]);
    }
}
