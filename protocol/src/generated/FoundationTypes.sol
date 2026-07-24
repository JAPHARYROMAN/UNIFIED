// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// Code generated from schemas/proto/unified/v1. DO NOT EDIT.
// Source SHA-256: ed6b0be44aeed37d395ae58b7705772137459cd0f0dd20a553879ebeb8c7a9d9
library FoundationTypes {
    enum CollateralKind { UNSPECIFIED, NATIVE, ERC20, ERC721, ERC1155 }

    enum CollateralStatus { UNSPECIFIED, LOCKED, RELEASED, LIQUIDATED, CLAIMED }

    enum PostingSide { UNSPECIFIED, DEBIT, CREDIT }

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
