// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

// Code generated from schemas/proto/unified/v1. DO NOT EDIT.
// Source SHA-256: efa714ec94e230161fb0c7d3e6bf42abddd1c74fca0a615ac4bef1cf80a3a69f
library FoundationTypes {
    enum PostingSide { UNSPECIFIED, DEBIT, CREDIT }

    enum InterestKind { UNSPECIFIED, FIXED, VARIABLE, ZERO }

    enum AssetKind { UNSPECIFIED, NATIVE, FUNGIBLE_TOKEN, NON_FUNGIBLE_TOKEN, FIAT, OFF_CHAIN }

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
