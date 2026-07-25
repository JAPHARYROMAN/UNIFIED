// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Canonical Phase 8 cross-chain types and non-recursive digest helpers.
library CrossChainTypes {
    uint32 internal constant SCHEMA_VERSION = 1;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_ROUTE_EXPOSURE_BPS = 500;
    uint256 internal constant MAX_AGGREGATE_EXPOSURE_BPS = 1_500;
    // Domain text: "UNIFIED_XCHAIN_MESSAGE_V1".
    bytes32 private constant MESSAGE_DOMAIN_WORD =
        0x554e49464945445f58434841494e5f4d4553534147455f563100000000000000;

    /// @dev Ordinals exactly mirror unified.v1.CrossChainActionType.
    enum CrossChainActionType {
        UNSPECIFIED,
        CANONICAL_UFT_LOCKED_V1,
        WRAPPED_UFT_MINTED_V1,
        WRAPPED_UFT_BURNED_V1,
        CANONICAL_UFT_RELEASED_V1,
        SATELLITE_COLLATERAL_LOCKED_V1,
        HOME_DISBURSEMENT_AUTHORIZED_V1,
        SATELLITE_DISBURSEMENT_SETTLED_V1,
        SATELLITE_REPAYMENT_BURNED_V1,
        HOME_COLLATERAL_RELEASE_AUTHORIZED_V1,
        SATELLITE_COLLATERAL_RELEASED_V1,
        STATE_ACKNOWLEDGED_V1,
        CANCELLATION_REQUESTED_V1,
        DESTINATION_TOMBSTONED_V1,
        SOURCE_COMPENSATED_V1,
        SATELLITE_UFT_PERMANENT_BURNED_V1,
        ROUTE_GOVERNANCE_V1
    }

    CrossChainActionType internal constant ACTION_HOME_UFT_MINT_AUTHORIZED =
    CrossChainActionType.CANONICAL_UFT_LOCKED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_MINT_CONFIRMED =
    CrossChainActionType.WRAPPED_UFT_MINTED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_COLLATERAL_LOCKED =
    CrossChainActionType.SATELLITE_COLLATERAL_LOCKED_V1;
    CrossChainActionType internal constant ACTION_HOME_DISBURSEMENT_AUTHORIZED =
    CrossChainActionType.HOME_DISBURSEMENT_AUTHORIZED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_DISBURSEMENT_SETTLED =
    CrossChainActionType.SATELLITE_DISBURSEMENT_SETTLED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_REPAYMENT_BURNED =
    CrossChainActionType.SATELLITE_REPAYMENT_BURNED_V1;
    CrossChainActionType internal constant ACTION_HOME_COLLATERAL_RELEASE_AUTHORIZED =
    CrossChainActionType.HOME_COLLATERAL_RELEASE_AUTHORIZED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_COLLATERAL_RELEASED =
    CrossChainActionType.SATELLITE_COLLATERAL_RELEASED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_UFT_BURNED =
    CrossChainActionType.WRAPPED_UFT_BURNED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_UFT_PERMANENT_BURNED =
    CrossChainActionType.SATELLITE_UFT_PERMANENT_BURNED_V1;
    CrossChainActionType internal constant ACTION_HOME_LOAN_CANCELLATION_REQUESTED =
    CrossChainActionType.CANCELLATION_REQUESTED_V1;
    CrossChainActionType internal constant ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED =
    CrossChainActionType.SOURCE_COMPENSATED_V1;

    enum MessageState {
        NONE,
        CREATED,
        SOURCE_FINALIZING,
        SOURCE_FINAL,
        SENT,
        RELAYED,
        VERIFIED,
        EXECUTED,
        ACK_PENDING,
        ACKNOWLEDGED,
        REJECTED,
        FAILED,
        EXPIRED,
        RECOVERY_PENDING,
        DESTINATION_TOMBSTONED,
        SOURCE_COMPENSATED,
        RECOVERED,
        DISPUTED
    }

    enum RegistryStatus {
        NONE,
        ACTIVE,
        DEPRECATED
    }

    enum BridgeOperationState {
        NONE,
        LOCKED,
        RELEASED,
        CANONICAL_BURNED,
        COMPENSATED
    }

    enum CrossChainLoanState {
        NONE,
        ACTIVATING,
        ACTIVE,
        CLOSING,
        CLOSED,
        RECOVERY_PENDING,
        DISPUTED
    }

    enum SatelliteCollateralState {
        NONE,
        LOCKED,
        RELEASED
    }

    struct MessageEnvelope {
        uint32 schemaVersion;
        bytes32 messageId;
        bytes32 protocolId;
        uint256 sourceChainId;
        address sourceCoordinator;
        address sourceComponent;
        uint256 destinationChainId;
        address destinationCoordinator;
        address destinationComponent;
        bytes32 laneId;
        uint64 sourceNonce;
        bytes32 aggregateId;
        CrossChainActionType actionType;
        bytes32 payloadHash;
        uint64 createdAt;
        uint64 expiresAt;
        bytes32 routePolicyHash;
        bytes32 adapterSetPolicyHash;
        bytes32 sourceFinalityPolicyHash;
        bytes32 destinationFinalityPolicyHash;
        bytes32 correlationId;
        bytes32 causationMessageId;
        bytes32 supersededMessageId;
    }

    struct SourceEventProof {
        bytes32 sourceBlockHash;
        uint64 sourceBlockNumber;
        uint64 sourceBlockTimestamp;
        bytes32 transactionHash;
        uint32 transactionIndex;
        bytes32 receiptRoot;
        bytes32 receiptProofHash;
        uint32 logIndex;
        bytes32 eventHash;
        bytes32 finalityHeadHash;
        uint64 finalityHeadNumber;
        uint64 requiredDepth;
        bytes32 headerAuthorityHash;
        bytes32 observerSignedHeaderCommitment;
        bytes observerSignature;
        bytes32 finalityPolicyHash;
    }

    struct FinalityCertificate {
        bytes32 messageId;
        bytes32 sourceProofHash;
        bytes32 signerSetHash;
        uint32 signerSetVersion;
        bytes[] signatures;
    }

    struct CanonicalUftLockPayload {
        bytes32 lockId;
        bytes32 loanId;
        address canonicalToken;
        address homeBridgeHub;
        address wrappedToken;
        address destinationRecipient;
        uint256 amount;
    }

    struct WrappedUftMintedPayload {
        bytes32 loanId;
        bytes32 lockId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address wrappedToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct WrappedUftBurnedPayload {
        bytes32 burnId;
        bytes32 backingRoutePolicyHash;
        address canonicalToken;
        address homeBridgeHub;
        address wrappedToken;
        address recipient;
        uint256 amount;
    }

    struct CanonicalUftReleasedPayload {
        bytes32 burnId;
        address canonicalToken;
        address recipient;
        uint256 amount;
        bytes32 wrappedBurnMessageId;
    }

    struct SatelliteCollateralLockedPayload {
        bytes32 loanId;
        bytes32 collateralId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address collateralToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct HomeDisbursementAuthorizedPayload {
        bytes32 loanId;
        bytes32 fundingLockId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address wrappedToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct SatelliteDisbursementSettledPayload {
        bytes32 loanId;
        bytes32 fundingLockId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address wrappedToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct SatelliteRepaymentBurnedPayload {
        bytes32 burnId;
        bytes32 loanId;
        bytes32 paymentId;
        bytes32 backingRoutePolicyHash;
        address canonicalToken;
        address homeBridgeHub;
        address wrappedToken;
        address lender;
        uint256 amount;
    }

    struct HomeCollateralReleaseAuthorizedPayload {
        bytes32 loanId;
        bytes32 collateralId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address collateralToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct SatelliteCollateralReleasedPayload {
        bytes32 loanId;
        bytes32 collateralId;
        address homeLoanAccount;
        address borrower;
        address lender;
        address collateralToken;
        uint256 amount;
        bytes32 policyHash;
    }

    struct SatelliteUftPermanentBurnedPayload {
        bytes32 burnId;
        bytes32 backingRoutePolicyHash;
        address canonicalToken;
        address homeBridgeHub;
        address wrappedToken;
        uint256 amount;
    }

    struct LoanCancellationAuthorization {
        address loanRouter;
        bytes32 loanId;
        bytes32 fundingLockId;
        bytes32 disbursementMessageId;
        bytes32 disbursementTombstoneHash;
        uint256 amount;
        bytes32 policyHash;
        uint64 authorizationNonce;
        uint64 validUntil;
        bytes32 reasonCode;
        bytes32 authorizerSetHash;
        uint32 authorizerSetVersion;
    }

    struct LoanCancellationRequestedPayload {
        bytes32 cancellationId;
        bytes32 loanId;
        bytes32 fundingLockId;
        bytes32 disbursementMessageId;
        bytes32 disbursementTombstoneHash;
        address homeLoanAccount;
        address lender;
        address wrappedToken;
        uint256 amount;
        bytes32 policyHash;
        bytes32 reasonCode;
    }

    struct SatelliteFundingCancelledPayload {
        bytes32 cancellationId;
        bytes32 loanId;
        bytes32 fundingLockId;
        bytes32 disbursementMessageId;
        bytes32 disbursementTombstoneHash;
        bytes32 escrowBurnResultHash;
        address homeLoanAccount;
        address lender;
        address wrappedToken;
        uint256 amount;
        bytes32 policyHash;
    }

    /// @dev Synthetic-local provisioning only; never valid as a cross-chain payload.
    struct SatelliteLoanProvisioning {
        bytes32 loanId;
        bytes32 fundingLockId;
        address homeLoanAccount;
        address homeLoanRouter;
        address borrower;
        address lender;
        address wrappedToken;
        address collateralToken;
        bytes32 collateralId;
        uint256 principalAmount;
        uint256 collateralAmount;
        bytes32 repaymentRoutePolicyHash;
        bytes32 policyHash;
    }

    struct CrossChainLoanTerms {
        bytes32 loanId;
        bytes32 agreementHash;
        bytes32 fundingLockId;
        bytes32 collateralId;
        address borrower;
        address lender;
        uint256 principalAmount;
        uint256 collateralAmount;
        bytes32 policyHash;
    }

    function messageId(MessageEnvelope memory envelope) internal pure returns (bytes32) {
        // Split the canonical abi.encode preimage into static-word chunks to avoid
        // stack pressure without changing a byte. The dynamic string offset is
        // 23 words and its tail is one length word plus one padded data word.
        return keccak256(
            bytes.concat(
                abi.encode(
                    uint256(23 * 32),
                    envelope.schemaVersion,
                    envelope.protocolId,
                    envelope.sourceChainId,
                    envelope.sourceCoordinator,
                    envelope.sourceComponent,
                    envelope.destinationChainId,
                    envelope.destinationCoordinator
                ),
                abi.encode(
                    envelope.destinationComponent,
                    envelope.laneId,
                    envelope.sourceNonce,
                    envelope.aggregateId,
                    envelope.actionType,
                    envelope.payloadHash
                ),
                abi.encode(
                    envelope.createdAt,
                    envelope.expiresAt,
                    envelope.routePolicyHash,
                    envelope.adapterSetPolicyHash,
                    envelope.sourceFinalityPolicyHash,
                    envelope.destinationFinalityPolicyHash,
                    envelope.correlationId,
                    envelope.causationMessageId,
                    envelope.supersededMessageId
                ),
                abi.encode(uint256(25), MESSAGE_DOMAIN_WORD)
            )
        );
    }

    function laneId(
        bytes32 protocolId,
        uint256 sourceChainId,
        address sourceComponent,
        uint256 destinationChainId,
        address destinationComponent,
        bytes32 aggregateId,
        bytes32 actionFamily
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_XCHAIN_LANE_V1",
                protocolId,
                sourceChainId,
                sourceComponent,
                destinationChainId,
                destinationComponent,
                aggregateId,
                actionFamily
            )
        );
    }

    function sourceProofHash(SourceEventProof memory proof) internal pure returns (bytes32) {
        return keccak256(abi.encode(proof));
    }

    function finalityCertificateDigest(
        address verifier,
        uint256 destinationChainId,
        bytes32 messageId_,
        bytes32 sourceProofHash_,
        bytes32 signerSetHash,
        uint32 signerSetVersion
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_SYNTHETIC_FINALITY_V1",
                destinationChainId,
                verifier,
                messageId_,
                sourceProofHash_,
                signerSetHash,
                signerSetVersion
            )
        );
    }

    function tombstoneEventHash(
        address destinationCoordinator,
        bytes32 messageId_,
        bytes32 envelopeHash,
        uint64 recoveryNonce,
        bytes32 reasonCode
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "UNIFIED_XCHAIN_TOMBSTONE_V1",
                destinationCoordinator,
                messageId_,
                envelopeHash,
                recoveryNonce,
                reasonCode
            )
        );
    }

    function observerHeaderCommitment(SourceEventProof memory proof)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                "UNIFIED_OBSERVER_SIGNED_HEADER_V1",
                proof.sourceBlockHash,
                proof.sourceBlockNumber,
                proof.sourceBlockTimestamp,
                proof.finalityHeadHash,
                proof.finalityHeadNumber,
                proof.requiredDepth,
                proof.headerAuthorityHash,
                proof.finalityPolicyHash
            )
        );
    }

    function actionBit(CrossChainActionType actionType) internal pure returns (uint32) {
        return uint32(1) << uint8(actionType);
    }

    function isExitAction(CrossChainActionType actionType) internal pure returns (bool) {
        return actionType == ACTION_SATELLITE_UFT_BURNED
            || actionType == ACTION_SATELLITE_UFT_PERMANENT_BURNED
            || actionType == ACTION_SATELLITE_REPAYMENT_BURNED
            || actionType == ACTION_HOME_LOAN_CANCELLATION_REQUESTED
            || actionType == ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED
            || actionType == ACTION_HOME_COLLATERAL_RELEASE_AUTHORIZED
            || actionType == ACTION_SATELLITE_COLLATERAL_RELEASED;
    }

    /// @notice Reports attest completed custody/value effects and remain ingestible after
    /// transport expiry once their source event reaches configured finality.
    function isReportAction(CrossChainActionType actionType) internal pure returns (bool) {
        return actionType == ACTION_SATELLITE_MINT_CONFIRMED
            || actionType == ACTION_SATELLITE_COLLATERAL_LOCKED
            || actionType == ACTION_SATELLITE_DISBURSEMENT_SETTLED
            || actionType == ACTION_SATELLITE_LOAN_CANCELLATION_COMPLETED
            || actionType == ACTION_SATELLITE_COLLATERAL_RELEASED;
    }
}
