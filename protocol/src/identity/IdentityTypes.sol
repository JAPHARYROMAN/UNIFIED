// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

library IdentityTypes {
    enum ProviderStatus {
        NONE,
        ACTIVE,
        SUSPENDED,
        RETIRED
    }

    enum CredentialStatus {
        NONE,
        ACTIVE,
        REVOKED
    }

    enum DecisionStatus {
        NONE,
        ACTIVE,
        REVOKED
    }

    enum ExposureStatus {
        NONE,
        RESERVED,
        ACTIVE,
        RELEASED,
        CANCELLED
    }

    struct ProviderRecord {
        bytes32 providerId;
        address operator;
        bytes32 metadataHash;
        uint16 maximumAssurance;
        uint64 registeredAt;
        ProviderStatus status;
    }

    struct CredentialSchema {
        bytes32 schemaId;
        bytes32 providerId;
        bytes32 definitionHash;
        uint16 maximumAssurance;
        uint64 registeredAt;
        bool active;
    }

    struct Credential {
        bytes32 credentialId;
        bytes32 subjectCommitment;
        address boundAccount;
        bytes32 providerId;
        bytes32 schemaId;
        bytes32 claimsCommitment;
        bytes32 scopeHash;
        uint64 epoch;
        uint16 assurance;
        uint64 validFrom;
        uint64 validUntil;
        uint64 issuedAt;
        uint64 revokedAt;
        address issuer;
        CredentialStatus status;
    }

    struct CredentialInput {
        bytes32 credentialId;
        bytes32 subjectCommitment;
        address boundAccount;
        bytes32 providerId;
        bytes32 schemaId;
        bytes32 claimsCommitment;
        bytes32 scopeHash;
        uint64 epoch;
        uint16 assurance;
        uint64 validFrom;
        uint64 validUntil;
    }

    struct CreditDecision {
        bytes32 decisionId;
        bytes32 previousDecisionId;
        bytes32 credentialId;
        bytes32 subjectCommitment;
        address borrower;
        bytes32 credentialScopeHash;
        uint64 credentialEpoch;
        uint16 minimumAssurance;
        bytes32 policyId;
        uint32 policyMajor;
        uint32 policyMinor;
        uint32 policyPatch;
        bytes32 ruleSetHash;
        bytes32 modelSetHash;
        bytes32 featureEvidenceRoot;
        bytes32 featureSchemaHash;
        uint64 featuresAsOf;
        bytes32 settlementAssetId;
        bytes32 productHash;
        uint256 maximumExposure;
        uint64 maximumDuration;
        uint64 issuedAt;
        uint64 expiresAt;
        uint64 sequence;
        bytes32 reasonCodesHash;
        address underwriter;
        uint64 revokedAt;
        DecisionStatus status;
    }

    struct CreditDecisionInput {
        bytes32 decisionId;
        bytes32 previousDecisionId;
        bytes32 credentialId;
        bytes32 subjectCommitment;
        address borrower;
        bytes32 credentialScopeHash;
        uint64 credentialEpoch;
        uint16 minimumAssurance;
        bytes32 policyId;
        uint32 policyMajor;
        uint32 policyMinor;
        uint32 policyPatch;
        bytes32 ruleSetHash;
        bytes32 modelSetHash;
        bytes32 featureEvidenceRoot;
        bytes32 featureSchemaHash;
        uint64 featuresAsOf;
        bytes32 settlementAssetId;
        bytes32 productHash;
        uint256 maximumExposure;
        uint64 maximumDuration;
        uint64 expiresAt;
        uint64 sequence;
        bytes32 reasonCodesHash;
    }

    struct ExposureTotals {
        uint256 reserved;
        uint256 active;
    }

    struct ExposureReservation {
        bytes32 loanId;
        bytes32 decisionId;
        bytes32 subjectCommitment;
        address borrower;
        bytes32 settlementAssetId;
        bytes32 productHash;
        uint256 amount;
        uint64 duration;
        uint64 reservedAt;
        uint64 reservationExpiresAt;
        address factory;
        ExposureStatus status;
    }
}
