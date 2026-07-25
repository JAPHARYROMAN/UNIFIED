// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.36;

/// @notice Shared resolution, refinance, lien, position, and restructuring ABI types.
library Phase9Types {
    enum LoanLifecycle {
        NONE,
        CREATED,
        ACTIVE,
        RESOLVING,
        CLOSED
    }

    enum ServicingState {
        NONE,
        CURRENT,
        DELINQUENT,
        DEFAULTED,
        TERMINAL
    }

    enum CustodyStatus {
        NONE,
        HELD,
        RELEASED
    }

    enum LienStatus {
        NONE,
        ACTIVE,
        HANDOFF_PENDING,
        RELEASED,
        DISPUTED
    }

    enum RefinanceState {
        NONE,
        REQUESTED,
        QUOTED,
        OFFERED,
        ACCEPTED,
        FUNDING_ESCROWED,
        EXECUTING,
        COMPLETED,
        REJECTED,
        EXPIRED,
        CANCELLED,
        REFUNDABLE,
        REFUNDED,
        DISPUTED
    }

    enum FundingCommitmentState {
        NONE,
        OFFERED,
        ACCEPTED,
        FUNDED,
        REFUNDABLE,
        REFUNDED,
        CONSUMED
    }

    enum LienHandoffState {
        NONE,
        ACTIVE_OLD,
        EXECUTING,
        ACTIVE_NEW,
        REVERTED,
        DISPUTED
    }

    enum PositionState {
        NONE,
        ACTIVE,
        TRANSFERRED,
        EXHAUSTED
    }

    enum RestructuringState {
        NONE,
        PROPOSED,
        REVIEW,
        VOTING,
        APPROVED,
        EXECUTING,
        EFFECTIVE,
        REJECTED,
        EXPIRED,
        WITHDRAWN,
        DISPUTED
    }

    enum VoteChoice {
        NONE,
        SUPPORT,
        OPPOSE,
        ABSTAIN
    }

    struct LoanConfiguration {
        address factory;
        address loanRegistry;
        address settlementToken;
        bytes32 settlementAssetId;
        address borrower;
        address positionManager;
        address collateralCustody;
        address lienRegistry;
        address payoffQuoteEngine;
        address refinanceCoordinator;
        address restructuringController;
        address insuranceManager;
        address recoveryManager;
        bytes32 loanId;
        bytes32 agreementHash;
        bytes32 policySetHash;
        bytes32 amendmentPolicyHash;
        bytes32 protectionPolicyHash;
        bytes32 recoveryPolicyHash;
    }

    struct LoanCreationRequest {
        bytes32 oldLoanId;
        uint64 newLoanNonce;
        bytes32 refinanceId;
        LoanConfiguration configuration;
        bytes32 creationId;
    }

    struct DebtState {
        LoanLifecycle lifecycle;
        ServicingState servicingState;
        uint64 termsVersion;
        uint64 debtStateVersion;
        uint64 stateNonce;
        uint64 commencementTime;
        uint64 maturityTime;
        bytes32 scheduleHash;
        uint256 outstandingPrincipal;
        uint256 accruedInterest;
        uint256 capitalizedInterest;
        uint256 accruedFees;
        uint256 accruedPenalties;
        uint256 recoverableCosts;
        uint256 unappliedCredit;
        uint256 coveredLossExposure;
        uint256 realizedLoss;
        uint256 writtenOffAmount;
        uint256 recoveredAfterWriteoff;
        bytes32 activeRefinanceId;
        bytes32 activeRestructureId;
    }

    struct LoanAmendment {
        bytes32 amendmentId;
        bytes32 restructureId;
        bytes32 loanId;
        uint64 priorTermsVersion;
        uint64 nextTermsVersion;
        uint64 priorDebtStateVersion;
        uint64 nextDebtStateVersion;
        bytes32 priorAgreementHash;
        bytes32 amendedTermsHash;
        bytes32 amendedScheduleHash;
        bytes32 accountingDeltaHash;
        uint256 capitalizedInterest;
        uint256 waivedFees;
        uint256 waivedPenalties;
        uint256 forgivenAmount;
        bytes32 amendmentDigest;
    }

    struct CustodyRecord {
        bytes32 collateralId;
        bytes32 assetId;
        address token;
        address borrower;
        uint256 quantity;
        CustodyStatus status;
        bytes32 identityHash;
    }

    struct Lien {
        bytes32 collateralId;
        address collateralManager;
        address vault;
        bytes32 assetId;
        uint256 quantity;
        address borrower;
        bytes32 seniorLoanId;
        uint64 lienVersion;
        LienStatus status;
        bytes32 pendingRefinanceId;
        bytes32 pendingTargetLoanId;
    }

    struct LienHandoffResult {
        bytes32 handoffId;
        bytes32 refinanceId;
        bytes32 collateralId;
        bytes32 oldLoanId;
        bytes32 newLoanId;
        uint64 priorLienVersion;
        uint64 nextLienVersion;
        LienHandoffState state;
        bytes32 evidenceHash;
    }

    struct RefinanceRecord {
        bytes32 refinanceId;
        bytes32 oldLoanId;
        bytes32 newLoanId;
        address borrower;
        address oldLender;
        address newPositionManager;
        bytes32 quoteId;
        bytes32 componentBeneficiaryHash;
        uint256 oldNetPayoff;
        uint256 newPrincipal;
        bytes32 settlementAssetId;
        bytes32 collateralSetHash;
        uint64 lienVersion;
        bytes32 proposedTermsHash;
        bytes32 newPolicySetHash;
        uint256 fundingAmount;
        uint256 refinanceFee;
        uint256 borrowerProceeds;
        uint64 expiresAt;
        uint64 refinanceNonce;
        bytes32 refinancePolicyHash;
        uint64 newLoanNonce;
        RefinanceState state;
        uint64 stateVersion;
        uint256 acceptedFunding;
        uint32 executionAttempts;
        bytes32 terminalEvidenceHash;
    }

    struct FundingCommitment {
        bytes32 commitmentId;
        bytes32 refinanceId;
        bytes32 positionId;
        bytes32 trancheId;
        address funder;
        uint256 amount;
        uint64 commitmentNonce;
        bytes32 commitmentDigest;
        FundingCommitmentState state;
        bytes32 fundingResultHash;
    }

    struct RefinanceTerminalResult {
        bytes32 refinanceId;
        bytes32 executionEventId;
        bytes32 resultHash;
        uint64 recordedAt;
        RefinanceState state;
    }

    struct Tranche {
        bytes32 trancheId;
        uint32 priority;
        uint256 originalClaim;
        uint256 outstandingClaim;
        bytes32 configurationHash;
    }

    struct Position {
        bytes32 positionId;
        bytes32 trancheId;
        address owner;
        uint256 votingPower;
        uint256 claim;
        PositionState state;
    }

    struct Checkpoint {
        uint64 blockNumber;
        uint256 value;
        address owner;
    }

    struct PositionRightSnapshot {
        bytes32 snapshotId;
        bytes32 loanId;
        uint64 termsVersion;
        uint64 snapshotBlock;
        bytes32 positionRoot;
        uint256 eligibleWeight;
        uint32 positionCount;
        uint32 quorumBasisPoints;
        uint32 approvalBasisPoints;
        bytes32 policyHash;
    }

    struct RestructuringProposal {
        bytes32 restructureId;
        bytes32 loanId;
        address proposer;
        uint64 activeTermsVersion;
        uint64 debtStateVersion;
        bytes32 amendmentPolicyHash;
        uint64 modificationMask;
        uint64 maturityExtensionSeconds;
        uint256 newRateRay;
        uint32 paymentHolidayPeriods;
        bytes32 paymentHolidayScheduleHash;
        uint256 feeWaiverAmount;
        uint256 penaltyWaiverAmount;
        uint256 arrearsCapitalizationAmount;
        uint256 newPrincipalCap;
        bytes32 addedCollateralCommitmentHash;
        uint256 partialForgivenessAmount;
        bytes32 positionLossAllocationHash;
        bytes32 amendedTermsHash;
        bytes32 amendedScheduleHash;
        bytes32 disclosureHash;
        bytes32 accountingDeltaHash;
        bytes32 positionSnapshotId;
        bytes32 positionSnapshotRoot;
        uint64 positionSnapshotBlock;
        uint256 eligibleWeight;
        uint32 quorumBasisPoints;
        uint32 approvalBasisPoints;
        address borrower;
        uint64 reviewStartsAt;
        uint64 votingEndsAt;
        uint64 executeBy;
        uint64 proposalNonce;
        bytes32 proposalDigest;
        LoanAmendment amendment;
        RestructuringState state;
    }

    struct BorrowerConsentRecord {
        bytes32 consentId;
        bytes32 restructureId;
        bytes32 loanId;
        address borrower;
        uint64 activeTermsVersion;
        bytes32 amendedTermsHash;
        bytes32 disclosureHash;
        bytes32 accountingDeltaHash;
        uint64 consentNonce;
        uint64 validUntil;
        bytes signature;
        bytes32 consentDigest;
    }

    struct VoteRecord {
        bytes32 voteId;
        bytes32 restructureId;
        bytes32 positionId;
        address owner;
        uint256 weight;
        VoteChoice choice;
        bytes32 authorizationHash;
        uint64 recordedAt;
    }

    struct RestructuringExecutionResult {
        bytes32 restructureId;
        bytes32 executionEventId;
        bytes32 amendmentDigest;
        bytes32 journalBatchHash;
        uint64 executedAt;
    }
}
