// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// Code generated from schemas/proto/unified/v1. DO NOT EDIT.
// Source SHA-256: 5a7030da225aacd625688d9edeeb5a1065792e4cc9332cbea8c59cbc29739860
library FoundationTypes {
    enum CollateralKind { UNSPECIFIED, NATIVE, ERC20, ERC721, ERC1155 }

    enum CollateralStatus { UNSPECIFIED, LOCKED, RELEASED, LIQUIDATED, CLAIMED }

    enum LiquidationRoute { UNSPECIFIED, DIRECT, DUTCH_AUCTION, ENGLISH_AUCTION }

    enum LiquidationStatus { UNSPECIFIED, ACTIVE, SETTLED, FAILED, CANCELLED }

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
