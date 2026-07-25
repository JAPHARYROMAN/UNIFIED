// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// Code generated from schemas/proto/unified/v1. DO NOT EDIT.
// Source SHA-256: be288c30a0144cb44c19ef70b22e0e02c4e2d73023d5922fca06e5b9309c702d
library FoundationTypes {
    enum CollateralKind { UNSPECIFIED, NATIVE, ERC20, ERC721, ERC1155 }

    enum CollateralStatus { UNSPECIFIED, LOCKED, RELEASED, LIQUIDATED, CLAIMED }

    enum LiquidationRoute { UNSPECIFIED, DIRECT, DUTCH_AUCTION, ENGLISH_AUCTION }

    enum LiquidationStatus { UNSPECIFIED, ACTIVE, SETTLED, FAILED, CANCELLED }

    enum CrossChainMessageState { UNSPECIFIED, CREATED, SOURCE_FINALIZING, SOURCE_FINAL, SENT, RELAYED, VERIFIED, EXECUTED, ACK_PENDING, ACKNOWLEDGED, REJECTED, FAILED, EXPIRED, RECOVERY_PENDING, DESTINATION_TOMBSTONED, SOURCE_COMPENSATED, RECOVERED, DISPUTED }

    enum CrossChainRecoveryState { UNSPECIFIED, REQUESTED, DESTINATION_CHECKED, TOMBSTONED, COMPENSATED, RECOVERED, DISPUTED }

    enum RecoveryAction { UNSPECIFIED, TOMBSTONE_THEN_COMPENSATE }

    enum RecoveryState { NONE_UNSPECIFIED, AUTHORIZED, DESTINATION_TOMBSTONED, SOURCE_COMPENSATED }

    enum CrossChainActionType { UNSPECIFIED, CANONICAL_UFT_LOCKED_V1, WRAPPED_UFT_MINTED_V1, WRAPPED_UFT_BURNED_V1, CANONICAL_UFT_RELEASED_V1, SATELLITE_COLLATERAL_LOCKED_V1, HOME_DISBURSEMENT_AUTHORIZED_V1, SATELLITE_DISBURSEMENT_SETTLED_V1, SATELLITE_REPAYMENT_BURNED_V1, HOME_COLLATERAL_RELEASE_AUTHORIZED_V1, SATELLITE_COLLATERAL_RELEASED_V1, STATE_ACKNOWLEDGED_V1, CANCELLATION_REQUESTED_V1, DESTINATION_TOMBSTONED_V1, SOURCE_COMPENSATED_V1, SATELLITE_UFT_PERMANENT_BURNED_V1, ROUTE_GOVERNANCE_V1 }

    enum CrossChainFailureClass { UNSPECIFIED, RETRYABLE_TRANSPORT, RETRYABLE_TARGET, REJECTED, EXPIRED, NONRETRYABLE, SAFETY_CONTRADICTION }

    enum CrossChainGovernanceActionType { UNSPECIFIED, REGISTER_ROUTE_VERSION, DEPRECATE_ROUTE_VERSION, PAUSE_NEW_EXPOSURE, RESUME_NEW_EXPOSURE, LOWER_EXPOSURE_CAP, ACTIVATE_DELAYED_EXPOSURE_POLICY }

    enum CrossChainSignerSetStatus { UNSPECIFIED, ACTIVE, DEPRECATED, COMPROMISED }

    enum PostingSide { UNSPECIFIED, DEBIT, CREDIT }

    enum IdentityProviderStatus { UNSPECIFIED, ACTIVE, SUSPENDED, RETIRED }

    enum IdentityCredentialStatus { UNSPECIFIED, ACTIVE, REVOKED }

    enum CreditDecisionStatus { UNSPECIFIED, ACTIVE, REVOKED }

    enum ExposureReservationStatus { UNSPECIFIED, RESERVED, ACTIVE, RELEASED, CANCELLED }

    enum InterestKind { UNSPECIFIED, FIXED, VARIABLE, ZERO }

    enum TenderState { UNSPECIFIED, OPEN, COMMITMENT_PENDING, FULFILLED, CANCELLED, EXPIRED }

    enum OfferState { UNSPECIFIED, ACTIVE, COUNTERED, CONSUMED, CANCELLED, EXPIRED }

    enum LoanLifecycle { UNSPECIFIED, PROPOSED, UNDERWRITING, FUNDING, ACTIVATING, ACTIVE, CLOSED, CANCELLED }

    enum ServicingState { UNSPECIFIED, CURRENT, GRACE, DELINQUENT, ACCELERATED, RESTRUCTURING, REFINANCING, DEFAULTED, REPAID, SETTLED, WRITTEN_OFF }

    enum FundingState { UNSPECIFIED, OPEN, PARTIALLY_FUNDED, FUNDED, FAILED, REFUNDING, CLOSED }

    enum PaymentState { UNSPECIFIED, REQUESTED, AUTHORIZED, PROCESSING, PROVISIONAL, FINAL, ALLOCATED, REVERSED, DISPUTED, FAILED, REFUNDED }

    enum FinalityState { UNSPECIFIED, PROVISIONAL, FINAL, REORGED }

    enum PaymentRail { UNSPECIFIED, BANK, CARD }

    enum PaymentStatus { UNSPECIFIED, CREATED, PROCESSING, PROVISIONAL, FINAL, FAILED, REVERSED, DISPUTED }

    enum ProviderStatementKind { UNSPECIFIED, SETTLED, REVERSED }

    enum ReconciliationStatus { UNSPECIFIED, MATCHED, EXCEPTION, RESOLVED }

    enum PaymentAllocationMode { UNSPECIFIED, SYNTHETIC_PROJECTION, CANONICAL_GATEWAY }

    enum CanonicalizationState { UNSPECIFIED, PREPARED, SUBMITTED, CONFIRMED, FAILED, QUARANTINED, INCIDENT }

    enum CanonicalSettlementReorgKind { UNSPECIFIED, SHALLOW, DEEP }

    enum CanonicalTransactionReceiptStatus { UNSPECIFIED, REVERTED }

    enum ScheduleKind { UNSPECIFIED, BULLET, EQUAL_PRINCIPAL, ANNUITY, INTEREST_ONLY, BALLOON, CUSTOM }

    enum InstallmentState { UNSPECIFIED, SCHEDULED, DUE, PARTIALLY_PAID, PAID, OVERDUE, WAIVED, DEFERRED, REPLACED }

    enum FundingRoundStatus { UNSPECIFIED, SCHEDULED, OPEN, ACTIVE, FAILED, CANCELLED, CLOSED }

    enum CommitmentStatus { UNSPECIFIED, FUNDED, POSITION_ACTIVE, REFUNDED }

    enum PositionStatus { UNSPECIFIED, PENDING, ACTIVE, PLEDGED, FROZEN, MERGED, REDEEMED, CANCELLED }

    enum PositionTransferPolicy { UNSPECIFIED, NON_TRANSFERABLE, FREELY_TRANSFERABLE }

    enum AssetKind { UNSPECIFIED, NATIVE, FUNGIBLE_TOKEN, NON_FUNGIBLE_TOKEN, FIAT, OFF_CHAIN }

    struct CollateralItem {
        Identifier collateralId;
        LoanId loanId;
        AssetId assetId;
        CollateralKind kind;
        string tokenAddress;
        string tokenId;
        string quantity;
        PartyId ownerId;
        int64 lockedAt;
        CollateralStatus status;
        bytes custodyEvidenceHash;
    }

    struct CollateralBundle {
        LoanId loanId;
        CollateralItem[] items;
        uint64 stateVersion;
    }

    struct UftCollateralExposure {
        LoanId loanId;
        PartyId borrowerId;
        string loanQuantity;
        string borrowerQuantity;
        string circulatingSupply;
        Money backedDebtValue;
        Money protocolDebtCeiling;
        bytes policyEvidenceHash;
    }

    struct LiquidationPlan {
        Identifier liquidationId;
        LoanId loanId;
        Identifier collateralId;
        LiquidationRoute route;
        string quantity;
        Money referenceProceeds;
        Money reservePrice;
        Money executionCostCap;
        uint32 incentiveBasisPoints;
        uint32 minimumBidIncrementBasisPoints;
        int64 startsAt;
        int64 endsAt;
        bytes policySetHash;
        bytes triggerSnapshotHash;
        OracleObservation pricingObservation;
        LiquidationStatus status;
    }

    struct LiquidationBid {
        Identifier liquidationId;
        PartyId bidderId;
        Money amount;
        int64 placedAt;
        bytes transactionEvidenceHash;
    }

    struct LiquidationSettlement {
        Identifier liquidationId;
        LoanId loanId;
        Money grossProceeds;
        Money executionCosts;
        Money liquidationIncentive;
        Money securedClaimPaid;
        Money borrowerSurplus;
        Money residualBadDebt;
        PartyId buyerId;
        PartyId executorId;
        Identifier paymentId;
        bytes journalReference;
        bytes pricingEvidenceHash;
        int64 settledAt;
    }

    struct CrossChainDomain {
        string chainId;
        bytes coordinator;
        bytes configurationHash;
        bytes finalityVerifier;
        uint64 version;
    }

    struct CrossChainLane {
        bytes laneId;
        string sourceChainId;
        bytes sourceComponent;
        string destinationChainId;
        bytes destinationComponent;
        bytes aggregateId;
        string actionFamily;
    }

    struct CrossChainSignerSet {
        bytes signerSetHash;
        uint32 version;
        uint32 threshold;
        bytes[] signerAddresses;
        bytes observerAuthorityHash;
        int64 validFrom;
        int64 validUntil;
        CrossChainSignerSetStatus status;
    }

    struct CrossChainRoutePolicy {
        Identifier routeId;
        uint64 routeVersion;
        CrossChainDomain sourceDomain;
        CrossChainDomain destinationDomain;
        CrossChainActionType[] allowedActions;
        bytes adapterSetPolicyHash;
        bytes sourceFinalityPolicyHash;
        bytes destinationFinalityPolicyHash;
        uint32 signerThreshold;
        uint64 timeoutSeconds;
        string routeAbsoluteCapUnits;
        string chainAbsoluteCapUnits;
        string adapterAbsoluteCapUnits;
        bytes policyHash;
        bytes sourceSignerSetHash;
        uint32 sourceSignerSetVersion;
        bytes destinationSignerSetHash;
        uint32 destinationSignerSetVersion;
    }

    struct CrossChainMessageEnvelope {
        uint32 schemaVersion;
        bytes messageId;
        bytes protocolId;
        string sourceChainId;
        bytes sourceCoordinator;
        bytes sourceComponent;
        string destinationChainId;
        bytes destinationCoordinator;
        bytes destinationComponent;
        bytes laneId;
        uint64 sourceNonce;
        bytes aggregateId;
        CrossChainActionType actionType;
        bytes typedActionPayload;
        bytes payloadHash;
        int64 createdAt;
        int64 expiresAt;
        bytes routePolicyHash;
        bytes adapterSetPolicyHash;
        bytes sourceFinalityPolicyHash;
        bytes destinationFinalityPolicyHash;
        bytes correlationId;
        bytes causationMessageId;
        bytes supersededMessageId;
        CanonicalUftLockPayload canonicalUftLock;
        WrappedUftMintedPayload wrappedUftMinted;
        WrappedUftBurnedPayload wrappedUftBurned;
        CanonicalUftReleasedPayload canonicalUftReleased;
        SatelliteCollateralLockedPayload satelliteCollateralLocked;
        HomeDisbursementAuthorizedPayload homeDisbursementAuthorized;
        SatelliteDisbursementSettledPayload satelliteDisbursementSettled;
        SatelliteRepaymentBurnedPayload satelliteRepaymentBurned;
        HomeCollateralReleaseAuthorizedPayload homeCollateralReleaseAuthorized;
        SatelliteCollateralReleasedPayload satelliteCollateralReleased;
        LoanCancellationRequestedPayload loanCancellationRequested;
        SatelliteFundingCancelledPayload satelliteFundingCancelled;
        SatelliteUftPermanentBurnedPayload satelliteUftPermanentBurned;
    }

    struct CrossChainSourceEventProof {
        bytes messageId;
        string sourceChainId;
        bytes sourceContract;
        bytes sourceBlockHash;
        uint64 sourceBlockNumber;
        int64 sourceBlockTimestamp;
        bytes transactionHash;
        uint64 transactionIndex;
        bytes receiptRoot;
        bytes receiptProofHash;
        uint64 logIndex;
        bytes eventHash;
        bytes finalityHeadHash;
        uint64 finalityHeadNumber;
        uint64 requiredDepth;
        bytes headerAuthorityHash;
        bytes observerSignature;
        bytes finalityPolicyHash;
        bytes observerSignedHeaderCommitment;
    }

    struct CrossChainFinalityCertificate {
        bytes messageId;
        bytes sourceProofHash;
        bytes signerSetHash;
        uint32 signerSetVersion;
        uint32 threshold;
        bytes[] signatures;
        int64 validFrom;
        int64 validUntil;
        bytes certificateHash;
    }

    struct CrossChainProviderDeliveryAttempt {
        bytes messageId;
        string providerId;
        uint32 attemptNumber;
        bytes serializedEnvelopeHash;
        bytes sourceProofHash;
        string status;
        bytes providerReceiptHash;
        int64 attemptedAt;
    }

    struct CrossChainExecutionResult {
        bytes messageId;
        bytes laneId;
        uint64 sourceNonce;
        CrossChainActionType actionType;
        bytes target;
        bytes resultHash;
        string destinationChainId;
        bytes transactionHash;
        uint64 logIndex;
        int64 executedAt;
    }

    struct CrossChainAcknowledgement {
        bytes messageId;
        bytes executionResultHash;
        CrossChainSourceEventProof destinationExecutionProof;
        CrossChainFinalityCertificate finalityCertificate;
        int64 acknowledgedAt;
    }

    struct CrossChainTransitionEvidence {
        bytes messageId;
        CrossChainMessageState fromState;
        CrossChainMessageState toState;
        uint64 stateVersion;
        CrossChainFailureClass failureClass;
        bytes evidenceHash;
        int64 occurredAt;
    }

    struct CrossChainCancellationRequest {
        Identifier recoveryId;
        bytes originalMessageId;
        bytes immutableEnvelopeHash;
        uint64 recoveryNonce;
        string reasonCode;
        bytes sourceStateCommitment;
        bytes destinationStateCommitment;
        string boundedUnits;
        AssetId assetId;
        uint64 routeVersion;
        bytes authorizerSetHash;
        bytes[] authorizerSignatures;
        int64 requestedAt;
    }

    struct CrossChainRecoveryRequestV2 {
        bytes messageId;
        bytes envelopeHash;
        bytes routePolicyHash;
        bytes assetAmountCommitment;
        bytes sourceStateCommitment;
        bytes destinationStateCommitment;
        bytes compensationPayloadHash;
        uint64 messageExpiresAt;
        uint64 recoveryNonce;
        bytes reasonCode;
        RecoveryAction action;
        bytes authorizerSetHash;
        uint32 authorizerSetVersion;
    }

    struct CrossChainRecoveryAuthorizationV2 {
        bytes protocolId;
        string sourceChainId;
        bytes sourceCoordinator;
        string destinationChainId;
        bytes destinationCoordinator;
        CrossChainRecoveryRequestV2 request;
        bytes[] authorizerSignatures;
        uint32 signerBitmap;
    }

    struct CrossChainRecoveryAuthorizerSetV2 {
        uint32 version;
        uint32 threshold;
        bytes[] authorizers;
        bytes setHash;
    }

    struct CrossChainRecoveryRecordV2 {
        bytes recoveryId;
        bytes requestDigest;
        uint32 signerBitmap;
        RecoveryState state;
        bytes tombstoneEventHash;
        bytes compensationPayloadHash;
        bytes compensationResult;
    }

    struct CrossChainTombstone {
        Identifier recoveryId;
        bytes originalMessageId;
        bytes immutableEnvelopeHash;
        uint64 recoveryNonce;
        string reasonCode;
        bytes destinationStateCommitment;
        bytes tombstoneHash;
        int64 tombstonedAt;
    }

    struct CrossChainCompensation {
        Identifier recoveryId;
        bytes originalMessageId;
        bytes tombstoneHash;
        string compensationType;
        AssetId assetId;
        string units;
        PartyId recipient;
        bytes resultHash;
        int64 compensatedAt;
    }

    struct CrossChainRecoveryRecord {
        Identifier recoveryId;
        bytes originalMessageId;
        CrossChainRecoveryState state;
        CrossChainCancellationRequest request;
        CrossChainTombstone tombstone;
        CrossChainCompensation compensation;
        bytes supersedingMessageId;
        uint64 version;
    }

    struct CanonicalUftLockPayload {
        bytes lockId;
        bytes loanId;
        bytes canonicalToken;
        bytes homeBridgeHub;
        bytes wrappedToken;
        bytes destinationRecipient;
        string amount;
    }

    struct WrappedUftMintedPayload {
        bytes loanId;
        bytes lockId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes wrappedToken;
        string amount;
        bytes policyHash;
    }

    struct WrappedUftBurnedPayload {
        bytes burnId;
        bytes backingRoutePolicyHash;
        bytes canonicalToken;
        bytes homeBridgeHub;
        bytes wrappedToken;
        bytes recipient;
        string amount;
    }

    struct CanonicalUftReleasedPayload {
        bytes burnId;
        bytes canonicalToken;
        bytes recipient;
        string amount;
        bytes wrappedBurnMessageId;
    }

    struct SatelliteCollateralLockedPayload {
        bytes loanId;
        bytes collateralId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes collateralToken;
        string amount;
        bytes policyHash;
    }

    struct HomeDisbursementAuthorizedPayload {
        bytes loanId;
        bytes fundingLockId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes wrappedToken;
        string amount;
        bytes policyHash;
    }

    struct SatelliteDisbursementSettledPayload {
        bytes loanId;
        bytes fundingLockId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes wrappedToken;
        string amount;
        bytes policyHash;
    }

    struct SatelliteRepaymentBurnedPayload {
        bytes burnId;
        bytes loanId;
        bytes paymentId;
        bytes backingRoutePolicyHash;
        bytes canonicalToken;
        bytes homeBridgeHub;
        bytes wrappedToken;
        bytes lender;
        string amount;
    }

    struct HomeCollateralReleaseAuthorizedPayload {
        bytes loanId;
        bytes collateralId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes collateralToken;
        string amount;
        bytes policyHash;
    }

    struct SatelliteCollateralReleasedPayload {
        bytes loanId;
        bytes collateralId;
        bytes homeLoanAccount;
        bytes borrower;
        bytes lender;
        bytes collateralToken;
        string amount;
        bytes policyHash;
    }

    struct LoanCancellationAuthorization {
        bytes loanRouter;
        bytes loanId;
        bytes fundingLockId;
        bytes disbursementMessageId;
        bytes disbursementTombstoneHash;
        string amount;
        bytes policyHash;
        uint64 authorizationNonce;
        uint64 validUntil;
        bytes reasonCode;
        bytes authorizerSetHash;
        uint32 authorizerSetVersion;
    }

    struct LoanCancellationRequestedPayload {
        bytes cancellationId;
        bytes loanId;
        bytes fundingLockId;
        bytes disbursementMessageId;
        bytes disbursementTombstoneHash;
        bytes homeLoanAccount;
        bytes lender;
        bytes wrappedToken;
        string amount;
        bytes policyHash;
        bytes reasonCode;
    }

    struct SatelliteFundingCancelledPayload {
        bytes cancellationId;
        bytes loanId;
        bytes fundingLockId;
        bytes disbursementMessageId;
        bytes disbursementTombstoneHash;
        bytes escrowBurnResultHash;
        bytes homeLoanAccount;
        bytes lender;
        bytes wrappedToken;
        string amount;
        bytes policyHash;
    }

    struct SatelliteUftPermanentBurnedPayload {
        bytes burnId;
        bytes backingRoutePolicyHash;
        bytes canonicalToken;
        bytes homeBridgeHub;
        bytes wrappedToken;
        string amount;
    }

    struct CrossChainLoanTerms {
        LoanId loanId;
        PartyId borrower;
        PartyId lender;
        AssetId principalAssetId;
        string principalUnits;
        AssetId collateralAssetId;
        string collateralUnits;
        bytes homeLoan;
        bytes satelliteComponent;
        bytes immutablePolicyHash;
        uint64 policyVersion;
    }

    struct CrossChainLoanState {
        CrossChainLoanTerms terms;
        string outstandingPrincipalUnits;
        string lifecycleState;
        uint64 stateNonce;
        bytes disbursementMessageId;
        bytes[] repaymentMessageIds;
        bytes collateralReleaseMessageId;
        bytes stateCommitment;
    }

    struct SatelliteCollateralPosition {
        Identifier positionId;
        LoanId loanId;
        PartyId borrower;
        AssetId assetId;
        string units;
        bytes satelliteVault;
        string status;
        bytes custodyCommitment;
    }

    struct BridgeExposureSnapshot {
        Identifier routeId;
        uint64 policyVersion;
        string routeEscrowUnits;
        string chainEscrowUnits;
        string adapterEscrowUnits;
        string aggregateEscrowUnits;
        string circulatingSupplyReferenceUnits;
        bytes circulatingSupplyEvidenceHash;
        string routeAbsoluteCapUnits;
        string chainAbsoluteCapUnits;
        string adapterAbsoluteCapUnits;
        string aggregateAbsoluteCapUnits;
        uint32 routePercentageBasisPoints;
        uint32 aggregatePercentageBasisPoints;
        bytes blockHash;
        uint64 blockNumber;
    }

    struct WrappedUftBackingSnapshot {
        Identifier routeId;
        AssetId canonicalUftAssetId;
        AssetId wrappedUftAssetId;
        string canonicalEscrowUnits;
        string wrappedSupplyUnits;
        string pendingMintUnits;
        string pendingBurnUnits;
        bytes homeBlockHash;
        bytes satelliteBlockHash;
        bytes evidenceHash;
    }

    struct CrossChainLedgerPostingIntent {
        Identifier postingIntentId;
        bytes messageId;
        string sourceChainId;
        string destinationChainId;
        Identifier routeId;
        uint64 routeVersion;
        LoanId loanId;
        string entryType;
        AssetId assetId;
        string units;
        string[] debitAccountCodes;
        string[] creditAccountCodes;
        bytes sourceEvidenceHash;
        string idempotencyKey;
        Identifier correlationId;
        bytes causationMessageId;
        int64 effectiveAt;
    }

    struct CrossChainReconciliationDifference {
        Identifier differenceId;
        Identifier runId;
        string dimension;
        string reasonCode;
        AssetId assetId;
        string expectedUnits;
        string observedUnits;
        bytes messageId;
        LoanId loanId;
        string severity;
        string owner;
        int64 detectedAt;
        int64 resolutionDeadline;
        bytes evidenceHash;
        string status;
    }

    struct CrossChainReconciliationRun {
        Identifier runId;
        string homeChainId;
        string satelliteChainId;
        uint64 routeVersion;
        bytes homeHeadHash;
        bytes satelliteHeadHash;
        WrappedUftBackingSnapshot backing;
        BridgeExposureSnapshot exposure;
        CrossChainReconciliationDifference[] differences;
        int64 startedAt;
        int64 completedAt;
        string status;
    }

    struct CrossChainGovernanceAction {
        Identifier governanceActionId;
        CrossChainGovernanceActionType actionType;
        Identifier routeId;
        uint64 currentRouteVersion;
        uint64 proposedRouteVersion;
        bytes exactPayloadHash;
        bytes authoritySetHash;
        int64 executableAfter;
        int64 expiresAt;
        bytes supersededPolicyHash;
    }

    struct CrossChainReorganizationEvidence {
        string chainId;
        bytes orphanedBlockHash;
        bytes replacementBlockHash;
        bytes detectedHeadHash;
        uint64 blockNumber;
        uint64 detectedHeadNumber;
        bytes[] affectedMessageIds;
        bytes evidenceHash;
        int64 detectedAt;
        CrossChainSourceEventProof orphanedSourceProof;
        bytes orphanedEventEvidenceHash;
        uint64 replacementBlockNumber;
        bytes replacementHeaderAuthorityHash;
        bytes replacementObserverSignedHeaderCommitment;
        bytes replacementObserverSignature;
        bytes detectedHeadHeaderAuthorityHash;
        bytes detectedHeadObserverSignedHeaderCommitment;
        bytes detectedHeadObserverSignature;
        bytes finalityPolicyHash;
        CrossChainFinalityCertificate orphanedFinalityCertificate;
        CrossChainSourceEventProof[] affectedOrphanedSourceProofs;
        bytes[] affectedOrphanedEventEvidenceHashes;
        CrossChainFinalityCertificate[] affectedOrphanedFinalityCertificates;
    }

    struct CrossChainIncident {
        Identifier incidentId;
        Identifier routeId;
        bytes[] affectedMessageIds;
        string reasonCode;
        string owner;
        bytes evidenceHash;
        int64 openedAt;
        string status;
    }

    struct CommandEnvelope {
        Identifier commandId;
        string commandType;
        string schemaVersion;
        PartyId actorId;
        string idempotencyKey;
        Identifier correlationId;
        Identifier causationId;
        int64 issuedAt;
        int64 expiresAt;
        string payloadType;
        bytes payload;
        bytes payloadHash;
    }

    struct EventEnvelope {
        Identifier eventId;
        string eventType;
        string schemaVersion;
        string authorityClass;
        Identifier aggregateId;
        uint64 aggregateVersion;
        Identifier correlationId;
        Identifier causationId;
        int64 occurredAt;
        int64 recordedAt;
        string payloadType;
        bytes payload;
        bytes payloadHash;
    }

    struct LedgerEntryIntent {
        string accountCode;
        PostingSide side;
        Money amount;
        PartyId partyId;
    }

    struct LedgerPostingIntent {
        Identifier postingId;
        string legalEntityId;
        string bookId;
        string sourceSystem;
        string idempotencyKey;
        int64 effectiveAt;
        LedgerEntryIntent[] entries;
        Identifier correlationId;
        bytes evidenceHash;
    }

    struct PaymentEvidence {
        Identifier paymentId;
        string providerId;
        string providerReference;
        string finalityStatus;
        Money amount;
        int64 observedAt;
        bytes evidenceHash;
    }

    struct CrossChainMessage {
        Identifier messageId;
        string sourceDomain;
        string destinationDomain;
        uint64 sourceNonce;
        string actionType;
        bytes actionPayload;
        bytes sourceEvidenceHash;
        int64 expiresAt;
    }

    struct GovernanceAction {
        Identifier proposalId;
        string proposalClass;
        string targetDomain;
        bytes payload;
        bytes payloadHash;
        int64 executableAfter;
        int64 expiresAt;
        string authorityScope;
    }

    struct IdentityProvider {
        Identifier providerId;
        PartyId operatorId;
        bytes metadataHash;
        uint32 maximumAssurance;
        int64 registeredAt;
        IdentityProviderStatus status;
    }

    struct IdentityCredentialSchema {
        Identifier schemaId;
        Identifier providerId;
        bytes definitionHash;
        uint32 maximumAssurance;
        int64 registeredAt;
        bool active;
    }

    struct IdentityCredential {
        Identifier credentialId;
        bytes subjectCommitment;
        PartyId boundAccountId;
        Identifier providerId;
        Identifier schemaId;
        bytes claimsCommitment;
        bytes scopeHash;
        uint64 epoch;
        uint32 assurance;
        int64 validFrom;
        int64 validUntil;
        int64 issuedAt;
        int64 revokedAt;
        PartyId issuerId;
        IdentityCredentialStatus status;
    }

    struct CreditDecision {
        Identifier decisionId;
        Identifier credentialId;
        bytes subjectCommitment;
        PartyId borrowerAccountId;
        bytes credentialScopeHash;
        uint64 credentialEpoch;
        uint32 minimumAssurance;
        PolicyReference policy;
        bytes ruleSetHash;
        bytes modelSetHash;
        bytes featureEvidenceRoot;
        bytes featureSchemaHash;
        int64 featuresAsOf;
        AssetId settlementAssetId;
        bytes productHash;
        Money maximumExposure;
        uint64 maximumDurationSeconds;
        int64 issuedAt;
        int64 expiresAt;
        bytes reasonCodesHash;
        PartyId underwriterId;
        int64 revokedAt;
        CreditDecisionStatus status;
        Identifier previousDecisionId;
        uint64 sequence;
    }

    struct ExposureReservation {
        LoanId loanId;
        Identifier decisionId;
        bytes subjectCommitment;
        PartyId borrowerAccountId;
        AssetId settlementAssetId;
        bytes productHash;
        Money amount;
        uint64 durationSeconds;
        int64 reservedAt;
        int64 reservationExpiresAt;
        PartyId factoryId;
        ExposureReservationStatus status;
        bytes evidenceHash;
    }

    struct UnderwritingFeatureEvidence {
        Identifier featureId;
        Identifier sourceId;
        string transformationVersion;
        bytes valueCommitment;
        bytes evidenceHash;
        int64 observedAt;
    }

    struct UnderwrittenActivationEvidence {
        LoanId loanId;
        Identifier decisionId;
        bytes subjectCommitment;
        PartyId borrowerAccountId;
        PartyId lenderAccountId;
        PartyId loanAccountId;
        Identifier tenderId;
        Identifier offerId;
        AssetId settlementAssetId;
        bytes productHash;
        Money principal;
        uint64 durationSeconds;
        bytes agreementHash;
        bytes consentEvidenceHash;
        bytes activationEvidenceHash;
        bytes journalReference;
        uint32 protocolVersion;
        int64 activatedAt;
    }

    struct UnderwrittenExposureReleaseEvidence {
        LoanId loanId;
        Identifier decisionId;
        bytes subjectCommitment;
        AssetId settlementAssetId;
        Money releasedPrincipal;
        bytes terminalEvidenceHash;
        int64 releasedAt;
    }

    struct LoanTerms {
        LoanId loanId;
        PartyId borrowerId;
        Money principal;
        InterestKind interestKind;
        int64 annualRateBasisPoints;
        int64 accrualStartsAt;
        int64 maturityAt;
        PolicyReference[] policies;
        bytes agreementHash;
        string schemaVersion;
    }

    struct Tender {
        Identifier tenderId;
        PartyId borrowerId;
        bytes metadataHash;
        TenderState state;
        Identifier selectedOfferId;
        int64 expiresAt;
    }

    struct SignedOffer {
        Identifier offerId;
        Identifier tenderId;
        Identifier parentOfferId;
        PartyId lenderId;
        PartyId borrowerId;
        LoanTerms terms;
        Money originationFee;
        uint64 nonce;
        int64 expiresAt;
        bytes signature;
        OfferState state;
    }

    struct LoanAgreementSnapshot {
        LoanTerms terms;
        Identifier tenderId;
        Identifier offerId;
        PartyId lenderId;
        Money originationFee;
        bytes policySetHash;
        bytes agreementHash;
        int64 activatedAt;
    }

    struct LoanStateVector {
        LoanId loanId;
        LoanLifecycle lifecycle;
        FundingState funding;
        PaymentState latestPayment;
        Money outstandingPrincipal;
        uint64 stateVersion;
        ServicingState servicing;
    }

    struct ChainEventReference {
        Identifier eventId;
        string chainDomain;
        bytes transactionHash;
        uint64 blockNumber;
        bytes blockHash;
        uint32 logIndex;
        FinalityState finality;
    }

    struct LoanActivated {
        LoanAgreementSnapshot agreement;
        LoanStateVector state;
        ChainEventReference evidence;
    }

    struct PrincipalRepaid {
        Identifier paymentId;
        LoanId loanId;
        PartyId payerId;
        Money amount;
        Money outstandingPrincipal;
        uint64 stateVersion;
        ChainEventReference evidence;
    }

    struct TransactionPreparation {
        Identifier preparationId;
        string chainDomain;
        string toAddress;
        bytes callData;
        string valueUnits;
        bytes expectedTermsHash;
        int64 expiresAt;
    }

    struct PaymentIntentRecord {
        Identifier paymentId;
        string legalEntityId;
        string idempotencyKey;
        Identifier correlationId;
        PartyId payerReference;
        LoanId loanId;
        string providerId;
        PaymentRail rail;
        string purpose;
        Money amount;
        int64 expiresAt;
        PaymentStatus status;
        uint64 aggregateVersion;
        uint32 schemaVersion;
    }

    struct ProviderPaymentCallback {
        string providerId;
        Identifier providerEventId;
        Identifier paymentId;
        string providerReference;
        PaymentStatus status;
        Money amount;
        int64 occurredAt;
        int64 expiresAt;
        bytes evidenceHash;
    }

    struct ProviderCallbackReceipt {
        Identifier ingressId;
        string providerId;
        Identifier providerEventId;
        bytes rawPayloadHash;
        bytes signatureHash;
        int64 receivedAt;
    }

    struct PaymentTransitionEvidence {
        Identifier paymentId;
        string providerId;
        Identifier providerEventId;
        PaymentStatus fromStatus;
        PaymentStatus toStatus;
        Money amount;
        Identifier[] journalIds;
        bytes evidenceHash;
        int64 occurredAt;
        int64 receivedAt;
    }

    struct PaymentQuarantineEvidence {
        Identifier quarantineId;
        string providerId;
        Identifier providerEventId;
        Identifier paymentId;
        bytes rawPayloadHash;
        bytes evidenceHash;
        string reasonCode;
        string owner;
        int64 receivedAt;
        int64 resolutionDeadline;
    }

    struct ProviderStatementEntry {
        Identifier entryId;
        string providerId;
        string providerReference;
        Identifier paymentId;
        Money amount;
        ProviderStatementKind kind;
        int64 occurredAt;
    }

    struct PaymentReconciliationRunEvidence {
        Identifier runId;
        string providerId;
        AssetId assetId;
        int64 asOf;
        bytes providerSnapshotHash;
        bytes ledgerSnapshotHash;
        string expectedUnits;
        string observedUnits;
        string differenceUnits;
        ReconciliationStatus status;
        string owner;
        int64 resolutionDeadline;
        uint32 unmatchedItems;
    }

    struct PaymentReconciliationExceptionEvidence {
        Identifier exceptionId;
        Identifier runId;
        string providerId;
        AssetId assetId;
        string differenceUnits;
        string reasonCode;
        string owner;
        int64 detectedAt;
        int64 resolutionDeadline;
        uint32 unmatchedItems;
    }

    struct PaymentReconciliationResolutionEvidence {
        Identifier resolutionId;
        Identifier exceptionId;
        bytes evidenceHash;
        Identifier resolutionJournalId;
        string resolvedBy;
        int64 resolvedAt;
    }

    struct LoanObligationSnapshotEvidence {
        LoanId loanId;
        PartyId borrowerId;
        PartyId lenderId;
        Money outstandingPrincipal;
        uint64 aggregateVersion;
        string sourceAuthority;
        bytes sourceEvidenceHash;
        int64 asOf;
    }

    struct FinalPaymentAllocationEvidence {
        Identifier allocationId;
        Identifier paymentId;
        LoanId loanId;
        string providerId;
        string providerReference;
        Money grossPayment;
        Money principalAllocation;
        Money refundableExcess;
        Money debtBefore;
        Money debtAfter;
        uint64 obligationVersionBefore;
        uint64 obligationVersionAfter;
        bytes waterfallPolicyHash;
        bytes finalityPolicyHash;
        Identifier reconciliationId;
        Identifier[] journalIds;
        bytes evidenceHash;
        int64 reversalDeadline;
        int64 allocatedAt;
    }

    struct PaymentAllocationReversalEvidence {
        Identifier reversalId;
        Identifier allocationId;
        Identifier paymentId;
        LoanId loanId;
        Money restoredPrincipal;
        Money removedRefundableExcess;
        Money debtBefore;
        Money debtAfter;
        uint64 obligationVersionBefore;
        uint64 obligationVersionAfter;
        string reasonCode;
        Identifier[] journalIds;
        bytes evidenceHash;
        int64 reversedAt;
    }

    struct CollateralReleaseEligibilityEvidence {
        Identifier evidenceId;
        Identifier allocationId;
        LoanId loanId;
        bool eligible;
        Money projectedOutstandingPrincipal;
        bool paymentFinal;
        bool reconciliationMatched;
        bool reversalDeadlineElapsed;
        bool allocationReversed;
        bytes evidenceHash;
        int64 evaluatedAt;
    }

    struct PaymentAllocationModeClaimEvidence {
        Identifier claimId;
        Identifier paymentId;
        PaymentAllocationMode mode;
        uint64 expectedVersion;
        uint64 claimedVersion;
        bool priorAllocationAbsent;
        uint32 priorAllocationJournalCount;
        bytes evidenceHash;
        int64 claimedAt;
        Identifier allocationId;
        bytes instructionDigest;
        bytes claimDigest;
    }

    struct CanonicalizationEligibilityEvidence {
        Identifier eligibilityId;
        Identifier allocationModeClaimId;
        Identifier paymentId;
        LoanId loanId;
        string providerId;
        string providerReference;
        Money sourcePayment;
        Money targetTokens;
        Identifier reconciliationId;
        Identifier[] originalJournalIds;
        bytes finalityPolicyHash;
        bytes conversionPolicyHash;
        bytes waterfallPolicyHash;
        bytes policySetHash;
        int64 reversalDeadline;
        bool eligible;
        bytes evidenceHash;
        int64 evaluatedAt;
        Identifier paymentFinalEventId;
        Identifier providerStatementEntryId;
    }

    struct CanonicalizationPlanEvidence {
        Identifier canonicalizationId;
        Identifier allocationModeClaimId;
        Identifier allocationId;
        Identifier paymentId;
        LoanId loanId;
        Money sourcePayment;
        Money targetTokens;
        Money expectedDebt;
        Money principalAllocation;
        Money refundableExcess;
        uint64 expectedStateNonce;
        PartyId finalizerId;
        string targetChainDomain;
        string gatewayAddress;
        bytes instructionDigest;
        bytes accountingAttestation;
        bytes evidenceHash;
        int64 preparedAt;
        PartyId borrowerId;
        PartyId lenderId;
    }

    struct CanonicalizationSubmissionEvidence {
        Identifier canonicalizationId;
        CanonicalizationState state;
        string targetChainDomain;
        string gatewayAddress;
        PartyId senderId;
        uint64 senderNonce;
        bytes calldataHash;
        bytes transactionHash;
        bytes evidenceHash;
        int64 submittedAt;
    }

    struct CanonicalSettlementConversionEvidence {
        Identifier conversionId;
        Identifier canonicalizationId;
        Identifier paymentId;
        string providerId;
        string providerReference;
        Money sourcePayment;
        Money targetTokens;
        string rateNumerator;
        string rateDenominator;
        string sourceAccountCode;
        Identifier[] originalJournalIds;
        PartyId finalizerId;
        bytes gatewayTransactionHash;
        bool providerAssetIrrevocablyAcquired;
        bool laterReversalRiskAssumed;
        bytes evidenceHash;
        int64 convertedAt;
    }

    struct CanonicalizationConfirmationEvidence {
        Identifier canonicalizationId;
        Identifier allocationId;
        Identifier paymentId;
        LoanId loanId;
        CanonicalizationState state;
        string targetChainDomain;
        string gatewayAddress;
        bytes transactionHash;
        Identifier gatewayEventId;
        bytes blockHash;
        uint64 blockNumber;
        uint32 logIndex;
        Money targetTokens;
        Money principalAllocation;
        Money refundableExcess;
        Money debtBefore;
        Money debtAfter;
        Identifier[] journalIds;
        bytes evidenceHash;
        int64 confirmedAt;
        bytes instructionDigest;
        PartyId borrowerId;
        PartyId lenderId;
        uint64 confirmationDepth;
        uint64 finalityHeadBlock;
        bytes finalityHeadHash;
        bytes finalityEvidenceHash;
        FinalizedCanonicalSettlementEvidence finalizedSettlement;
    }

    struct CanonicalLenderPayoutEvidence {
        Identifier payoutId;
        Identifier canonicalizationId;
        LoanId loanId;
        PartyId lenderId;
        Money amount;
        bytes gatewayTransactionHash;
        Identifier gatewayEventId;
        Identifier journalId;
        bytes evidenceHash;
        int64 paidAt;
    }

    struct CanonicalBorrowerRefundEvidence {
        Identifier refundId;
        Identifier canonicalizationId;
        LoanId loanId;
        PartyId borrowerId;
        Money amount;
        bytes gatewayTransactionHash;
        Identifier gatewayEventId;
        Identifier journalId;
        bytes evidenceHash;
        int64 refundedAt;
    }

    struct CanonicalSettlementIncidentEvidence {
        Identifier incidentId;
        Identifier canonicalizationId;
        Identifier paymentId;
        string providerId;
        Identifier providerEventId;
        PaymentStatus reportedStatus;
        CanonicalizationState canonicalizationState;
        string reasonCode;
        string owner;
        bool paymentStateUnchanged;
        bool economicJournalsSuppressed;
        bytes rawPayloadHash;
        bytes evidenceHash;
        int64 observedAt;
        int64 resolutionDeadline;
        Identifier quarantineId;
        Identifier resolutionId;
        FinalizedCanonicalSettlementEvidence finalizedSettlement;
    }

    struct CanonicalSettlementReorgEvidence {
        Identifier reorgId;
        Identifier canonicalizationId;
        bytes orphanedTransactionHash;
        Identifier orphanedGatewayEventId;
        bytes orphanedBlockHash;
        uint64 orphanedBlockNumber;
        uint64 replacementBlockNumber;
        CanonicalSettlementReorgKind kind;
        bool compensationRequired;
        bytes orphanedEventEvidenceHash;
        bytes evidenceHash;
        int64 detectedAt;
        bytes paymentId;
        bytes allocationId;
        bytes instructionDigest;
        bytes replacementBlockHash;
        uint64 confirmationDepth;
        uint64 detectedHeadBlockNumber;
        bytes detectedHeadBlockHash;
        bytes orphanedRawPayloadHash;
        string chainId;
        string gatewayAddress;
        uint64 orphanedTransactionIndex;
        bytes orphanedReceiptsRoot;
        bytes orphanedInclusionProofHash;
        bytes orphanedReceiptHeaderSignatureHash;
        bytes finalityPolicyHash;
        bytes headerAuthorityHash;
        bytes replacementHeaderSignatureHash;
        bytes detectedHeadHeaderSignatureHash;
    }

    struct CanonicalSettlementReorgCompensationEvidence {
        Identifier compensationId;
        Identifier canonicalizationId;
        bytes orphanedTransactionHash;
        Identifier orphanedGatewayEventId;
        bytes orphanedBlockHash;
        Identifier[] originalJournalIds;
        Identifier[] reversalJournalIds;
        bytes evidenceHash;
        int64 detectedAt;
        Identifier reorgId;
        Identifier incidentId;
    }

    struct CanonicalSettlementInstruction {
        bytes paymentId;
        bytes allocationId;
        bytes loanId;
        bytes sourceAssetId;
        bytes targetAssetId;
        string sourceUnits;
        string targetUnits;
        bytes providerIdHash;
        bytes providerReferenceHash;
        bytes reconciliationId;
        bytes reconciliationCommitment;
        bytes originalJournalSetHash;
        bytes conversionPolicyHash;
        bytes finalityPolicyHash;
        bytes evidenceHash;
        bytes journalRef;
        uint64 finalizedAtUnixSeconds;
        uint64 reversalDeadlineUnixSeconds;
        string expectedDebtUnits;
        uint64 expectedStateNonce;
        string attesterAddress;
    }

    struct CanonicalSettlementDigestContext {
        bytes eligibilityDomainHash;
        string chainId;
        string gatewayAddress;
        string finalizerAddress;
        bytes policySetHash;
        CanonicalSettlementInstruction instruction;
        bytes instructionDigest;
    }

    struct CanonicalSettlementExecutedEventData {
        bytes instructionDigest;
        bytes policySetHash;
        string loanAccountAddress;
        string finalizerAddress;
        string attesterAddress;
        bytes sourceAssetId;
        bytes targetAssetId;
        string targetTokenAddress;
        string sourceUnits;
        string grossUnits;
        bytes providerIdHash;
        bytes providerReferenceHash;
        bytes reconciliationId;
        bytes reconciliationCommitment;
        bytes originalJournalSetHash;
        bytes conversionPolicyHash;
        bytes finalityPolicyHash;
        bytes instructionEvidenceHash;
        bytes journalRef;
        uint64 finalizedAtUnixSeconds;
        uint64 reversalDeadlineUnixSeconds;
        string debtBeforeUnits;
        string principalUnits;
        string refundableExcessUnits;
        string debtAfterUnits;
        uint64 stateNonceBefore;
        uint64 stateNonceAfter;
        string lenderAddress;
        string borrowerAddress;
    }

    struct CanonicalSettlementLogEnvelope {
        string chainId;
        string gatewayAddress;
        bytes transactionHash;
        bytes gatewayEventId;
        uint32 logIndex;
        uint64 blockNumber;
        bytes blockHash;
        bytes rawPayloadHash;
        bytes paymentId;
        bytes allocationId;
        bytes loanId;
        CanonicalSettlementExecutedEventData settlement;
        uint64 transactionIndex;
        bytes receiptsRoot;
        bytes inclusionProofHash;
        bytes receiptHeaderSignatureHash;
    }

    struct CanonicalSettlementFinalityProof {
        uint64 confirmationDepth;
        uint64 headBlockNumber;
        bytes headBlockHash;
        bytes evidenceHash;
        int64 observedAt;
        bytes finalityPolicyHash;
        bytes headerAuthorityHash;
        bytes headHeaderSignatureHash;
    }

    struct FinalizedCanonicalSettlementEvidence {
        CanonicalSettlementLogEnvelope eventEnvelope;
        CanonicalSettlementFinalityProof finality;
    }

    struct CanonicalSubmittedTransactionFailureEvidence {
        Identifier canonicalizationId;
        bytes paymentId;
        bytes allocationId;
        bytes instructionDigest;
        string chainId;
        string gatewayAddress;
        bytes transactionHash;
        CanonicalTransactionReceiptStatus receiptStatus;
        bytes receiptPayloadHash;
        uint64 blockNumber;
        bytes blockHash;
        uint64 confirmationDepth;
        uint64 headBlockNumber;
        bytes headBlockHash;
        bytes evidenceHash;
        int64 observedAt;
        uint64 transactionIndex;
        bytes receiptsRoot;
        bytes inclusionProofHash;
        bytes finalityPolicyHash;
        bytes headerAuthorityHash;
        bytes receiptHeaderSignatureHash;
        bytes headHeaderSignatureHash;
    }

    struct CanonicalReversalResolutionEvidence {
        Identifier resolutionId;
        Identifier quarantineId;
        Identifier canonicalizationId;
        bytes paymentId;
        bytes allocationId;
        bytes instructionDigest;
        CanonicalizationState originState;
        CanonicalSubmittedTransactionFailureEvidence submittedTransactionFailure;
        ProviderPaymentCallback providerReversalEvent;
        ProviderCallbackReceipt providerReversalReceipt;
        Identifier phase7aReversalEventId;
        Identifier[] phase7aReversalJournalIds;
        uint64 coordinatorVersionBefore;
        uint64 coordinatorVersionAfter;
        bool permanentTombstone;
        string resolvedBy;
        bytes evidenceHash;
        int64 resolvedAt;
    }

    struct OracleObservation {
        AssetId assetId;
        AssetId quoteAssetId;
        string normalizedValue;
        uint32 decimals;
        int64 observedAt;
        int64 retrievedAt;
        uint64 roundId;
        uint32 confidenceBasisPoints;
        bytes sourceEvidenceHash;
    }

    struct InterestTerms {
        string annualRateRay;
        string spreadRay;
        string floorRateRay;
        string capRateRay;
        uint64 maximumBenchmarkAgeSeconds;
        string dayCountConvention;
        string roundingMode;
    }

    struct SchedulePlan {
        ScheduleKind kind;
        Money principal;
        Money totalInterest;
        string periodicRateRay;
        Money balloonPrincipal;
        int64 startAt;
        uint64 periodSeconds;
        uint32 installmentCount;
        uint32 paymentHolidayCount;
    }

    struct Installment {
        uint32 index;
        int64 dueAt;
        Money principalDue;
        Money interestDue;
        InstallmentState state;
    }

    struct ServicingRecord {
        LoanId loanId;
        Money amountDue;
        Money amountPaid;
        int64 dueAt;
        int64 graceEndsAt;
        int64 cureEndsAt;
        ServicingState status;
        uint64 stateVersion;
    }

    struct FundingRound {
        Identifier roundId;
        LoanId loanId;
        PartyId borrowerId;
        Money minimumFunding;
        Money targetFunding;
        Money maximumFunding;
        Money totalCommitted;
        int64 opensAt;
        int64 closesAt;
        FundingRoundStatus status;
        bytes agreementHash;
        bytes policySetHash;
    }

    struct FundingCommitment {
        Identifier commitmentId;
        Identifier roundId;
        Identifier trancheId;
        Identifier positionId;
        PartyId lenderId;
        Money amount;
        CommitmentStatus status;
        bytes settlementEvidenceHash;
    }

    struct Tranche {
        Identifier trancheId;
        LoanId loanId;
        string name;
        uint32 seniorityRank;
        Money targetSize;
        Money fundedPrincipal;
        Money outstandingPrincipal;
        uint32 couponBasisPoints;
        uint32 votingBasisPoints;
        PositionTransferPolicy transferPolicy;
    }

    struct LenderPosition {
        Identifier positionId;
        LoanId loanId;
        Identifier trancheId;
        PartyId ownerId;
        PartyId pledgeeId;
        string shareUnits;
        string votingPower;
        Money accruedDistribution;
        int64 acquiredAt;
        PositionStatus status;
    }

    struct PositionTransfer {
        Identifier transferId;
        Identifier positionId;
        PartyId sellerId;
        PartyId buyerId;
        string shareUnits;
        uint64 cutoffBlock;
        bytes settlementEvidenceHash;
        int64 settledAt;
        Money outstandingClaim;
    }

    struct PositionDistributionAllocation {
        Identifier positionId;
        PartyId ownerId;
        Money amount;
    }

    struct SyndicateDistribution {
        Identifier paymentId;
        LoanId loanId;
        Money finalizedAmount;
        PositionDistributionAllocation[] allocations;
        Money explicitResidual;
        bytes journalReference;
        bytes settlementEvidenceHash;
        int64 finalizedAt;
    }

    struct Identifier {
        string value;
    }

    struct AssetId {
        string value;
    }

    struct PartyId {
        string value;
    }

    struct LoanId {
        string value;
    }

    struct AssetDescriptor {
        AssetId assetId;
        AssetKind kind;
        string chainDomain;
        string contractAddress;
        string symbol;
        uint32 decimals;
        string registryVersion;
    }

    struct Money {
        AssetId assetId;
        string units;
    }

    struct PolicyReference {
        string policyId;
        string version;
        bytes contentHash;
    }

}
