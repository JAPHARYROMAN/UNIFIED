// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Shared funded-protection policy, coverage, claim, and payment ABI types.
library Phase9ProtectionTypes {
    enum ReservePolicyState {
        NONE,
        SCHEDULED,
        ACTIVE,
        RESTRICTED,
        EXPIRED,
        DEPRECATED
    }
    enum CoverageState {
        NONE,
        DRAFT,
        PREMIUM_PENDING,
        ACTIVE,
        CLAIM_PENDING,
        EXHAUSTED,
        EXPIRED,
        CANCELLED
    }
    enum PremiumState {
        NONE,
        DUE,
        FUNDED,
        APPLIED,
        REFUNDED
    }
    enum InsuranceClaimState {
        NONE,
        SUBMITTED,
        UNDER_REVIEW,
        APPROVED,
        PARTIALLY_APPROVED,
        REJECTED,
        EXPIRED,
        DISPUTED,
        PAYMENT_PENDING,
        PAID
    }

    struct ReservePolicyVersion {
        bytes32 policyVersionId;
        bytes32 poolId;
        bytes32 settlementAssetId;
        address token;
        uint32 stressHaircutBasisPoints;
        uint256 modeledLossAtTargetConfidence;
        uint32 targetConfidenceBasisPoints;
        uint32 maximumCoverageBasisPoints;
        uint256 maximumSinglePolicy;
        uint256 aggregateCommitmentLimit;
        uint256 minimumReserveRatioRay;
        uint256 minimumCommitmentRatioRay;
        uint64 coveredEventMask;
        uint256 minimumDeductible;
        uint256 maximumDeductible;
        bytes32 premiumPolicyHash;
        bytes32 adjudicatorSetHash;
        bytes32 payoutWaterfallHash;
        bytes32 recoveryWaterfallHash;
        uint64 effectiveAt;
        uint64 expiresAt;
        ReservePolicyState state;
        bytes32 contentHash;
    }

    struct ReserveFundingResult {
        bytes32 fundingEventId;
        bytes32 poolId;
        bytes32 assetId;
        address payer;
        uint256 amount;
        bytes32 balanceDeltaHash;
        uint64 fundedAt;
    }

    struct LoanCoverage {
        bytes32 coverageId;
        bytes32 poolId;
        bytes32 loanId;
        address beneficiary;
        bytes32 settlementAssetId;
        uint64 coveredEventMask;
        uint256 deductible;
        uint32 coverageBasisPoints;
        uint256 coverageLimit;
        uint256 remainingLimit;
        uint256 premium;
        uint32 lossPriority;
        uint32 subrogationPriority;
        uint64 validFrom;
        uint64 expiresAt;
        uint64 coverageNonce;
        bytes32 policyVersionId;
        bytes32 coverageDigest;
        CoverageState state;
        bytes32 reservePolicyHash;
    }

    struct PremiumEvidence {
        bytes32 premiumEventId;
        bytes32 coverageId;
        bytes32 poolId;
        address payer;
        uint256 amount;
        bytes32 transactionHash;
        uint32 logIndex;
        bytes32 balanceDeltaHash;
        uint64 fundedAt;
        PremiumState state;
    }

    struct InsuranceClaim {
        bytes32 claimId;
        bytes32 coverageId;
        bytes32 lossId;
        address claimant;
        uint256 requestedAmount;
        uint256 eligibleUncoveredLoss;
        bytes32 evidenceHash;
        uint64 claimNonce;
        uint64 submittedAt;
        InsuranceClaimState state;
        bytes32 claimDigest;
    }

    struct ClaimDecision {
        bytes32 decisionId;
        bytes32 claimId;
        uint256 adjudicatedAmount;
        uint256 approvalCap;
        uint256 beneficiaryCoveredUnresolvedEntitlement;
        uint256 approvedAmount;
        uint256 authorizedCosts;
        bytes32 beneficiaryEntitlementHash;
        bytes32 evidenceHash;
        uint64 adjudicationNonce;
        uint64 validUntil;
        bytes32 adjudicatorSetHash;
        uint64 lossStateVersion;
        bytes32 decisionDigest;
    }

    struct ClaimPayment {
        bytes32 claimPaymentId;
        bytes32 claimId;
        bytes32 decisionId;
        bytes32 poolId;
        address beneficiary;
        uint256 amount;
        uint256 unpaidApprovedAmount;
        bytes32 transactionHash;
        uint32 logIndex;
        bytes32 balanceDeltaHash;
        bytes32 subrogationEntitlementHash;
        uint64 paidAt;
        uint64 paymentNonce;
    }

    struct AdjudicatorSet {
        bytes32 adjudicatorSetHash;
        address[3] adjudicators;
        uint8 threshold;
        uint64 validFrom;
        uint64 validUntil;
    }
}
